import { haversineDistanceMeters } from "./geo.js";
import { decodePolyline } from "./polyline.js";

const ROUTES_ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes";
const PLACES_TEXT_SEARCH_ENDPOINT = "https://places.googleapis.com/v1/places:searchText";
const PLACES_NEARBY_SEARCH_ENDPOINT = "https://places.googleapis.com/v1/places:searchNearby";
const GEOCODING_ENDPOINT = "https://maps.googleapis.com/maps/api/geocode/json";
const STREET_VIEW_METADATA_ENDPOINT = "https://maps.googleapis.com/maps/api/streetview/metadata";
const STREET_VIEW_IMAGE_ENDPOINT = "https://maps.googleapis.com/maps/api/streetview";

const ROUTES_FIELD_MASK = [
  "routes.distanceMeters",
  "routes.duration",
  "routes.polyline.encodedPolyline",
  "routes.legs.steps.distanceMeters",
  "routes.legs.steps.staticDuration",
  "routes.legs.steps.polyline.encodedPolyline",
  "routes.legs.steps.startLocation",
  "routes.legs.steps.endLocation",
  "routes.legs.steps.navigationInstruction"
].join(",");

export class GoogleApiError extends Error {
  constructor(message, { status, payload } = {}) {
    super(message);
    this.name = "GoogleApiError";
    this.status = status;
    this.payload = payload;
  }
}

export function createGoogleMapsClient({ apiKey, fetchImpl = fetch }) {
  return {
    resolveDestinationText: (request) => resolveDestinationText({ ...request, apiKey, fetchImpl }),
    computeWalkingRoute: (request) => computeWalkingRoute({ ...request, apiKey, fetchImpl }),
    reverseGeocode: (request) => reverseGeocode({ ...request, apiKey, fetchImpl }),
    getNearbyLandmarks: (request) => getNearbyLandmarks({ ...request, apiKey, fetchImpl }),
    getStreetViewMetadata: (request) => getStreetViewMetadata({ ...request, apiKey, fetchImpl }),
    fetchStreetViewImage: (request) => fetchStreetViewImage({ ...request, apiKey, fetchImpl })
  };
}

export async function resolveDestinationText({
  destinationText,
  origin,
  language = "en-US",
  apiKey,
  fetchImpl = fetch
}) {
  const place = await textSearchDestination({ destinationText, origin, language, apiKey, fetchImpl });
  if (place) return place;

  const geocode = await geocodeDestination({ destinationText, language, apiKey, fetchImpl });
  if (geocode) return geocode;

  throw new GoogleApiError("No reliable destination match was found.", {
    status: 404,
    payload: { destinationText }
  });
}

async function textSearchDestination({ destinationText, origin, language, apiKey, fetchImpl }) {
  const response = await fetchImpl(PLACES_TEXT_SEARCH_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "places.id",
        "places.displayName",
        "places.formattedAddress",
        "places.location",
        "places.types"
      ].join(",")
    },
    body: JSON.stringify({
      textQuery: destinationText,
      languageCode: language,
      maxResultCount: 8,
      locationBias: origin ? {
        circle: {
          center: toGoogleLatLng(origin),
          radius: 50000
        }
      } : undefined
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new GoogleApiError("Google Places text search failed.", {
      status: response.status,
      payload
    });
  }

  const place = chooseBestDestinationPlace(payload.places || [], destinationText, origin);
  if (!place?.location) return null;
  const matchScore = scorePlaceCandidate(place, destinationText, origin);

  return normalizeDestination({
    source: "places",
    placeId: place.id,
    name: place.displayName?.text || destinationText,
    formattedAddress: place.formattedAddress || null,
    coordinate: fromGoogleLatLng(place.location),
    confidence: matchScore >= 24 ? "high" : "medium",
    types: place.types || []
  });
}

async function geocodeDestination({ destinationText, language, apiKey, fetchImpl }) {
  const params = new URLSearchParams({
    address: destinationText,
    language,
    key: apiKey
  });

  const response = await fetchImpl(`${GEOCODING_ENDPOINT}?${params.toString()}`);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload.status !== "OK") {
    if (payload.status === "ZERO_RESULTS") return null;
    throw new GoogleApiError("Google Geocoding request failed.", {
      status: response.status,
      payload
    });
  }

  const result = payload.results?.[0];
  if (!result?.geometry?.location) return null;

  const locationType = result.geometry.location_type;
  const weak = result.partial_match || ["APPROXIMATE"].includes(locationType);

  return normalizeDestination({
    source: "geocoding",
    placeId: result.place_id || null,
    name: result.formatted_address || destinationText,
    formattedAddress: result.formatted_address || null,
    coordinate: fromLegacyLatLng(result.geometry.location),
    confidence: weak ? "low" : "medium",
    types: result.types || []
  });
}

function chooseBestDestinationPlace(places, destinationText, origin) {
  const candidates = places.filter((place) => place?.location);
  if (!candidates.length) return null;

  return candidates
    .map((place, index) => ({
      place,
      index,
      score: scorePlaceCandidate(place, destinationText, origin)
    }))
    .sort((a, b) => {
      const scoreDelta = b.score - a.score;
      if (Math.abs(scoreDelta) > 0.001) return scoreDelta;
      return a.index - b.index;
    })[0].place;
}

function scorePlaceCandidate(place, destinationText, origin) {
  const name = place.displayName?.text || "";
  const address = place.formattedAddress || "";
  const types = Array.isArray(place.types) ? place.types.join(" ") : "";
  const nameText = normalizeSearchText(name);
  const haystack = normalizeSearchText(`${name} ${address} ${types}`);
  const queryTokens = meaningfulQueryTokens(destinationText);
  let score = 0;

  queryTokens.forEach((token, index) => {
    if (matchesToken(haystack, token)) {
      score += token.length <= 2 ? 10 : 12;
      if (index === 0 && matchesToken(nameText, token)) {
        score += 8;
      }
    }
  });

  for (const phrase of adjacentTokenPhrases(queryTokens)) {
    if (matchesPhrase(haystack, phrase)) {
      score += 18;
    }
  }

  const queryText = normalizeSearchText(destinationText);
  if (queryText && haystack.includes(queryText)) {
    score += 30;
  }

  if (origin && place.location) {
    const distanceMeters = haversineDistanceMeters(origin, fromGoogleLatLng(place.location));
    score -= Math.min(16, distanceMeters / 10_000);
  }

  return score;
}

function meaningfulQueryTokens(text) {
  const stopWords = new Set([
    "a",
    "an",
    "and",
    "at",
    "by",
    "for",
    "go",
    "going",
    "in",
    "near",
    "of",
    "on",
    "the",
    "to"
  ]);

  return normalizeSearchText(text)
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length > 1 && !stopWords.has(token));
}

function adjacentTokenPhrases(tokens) {
  const phrases = [];
  for (let index = 0; index < tokens.length - 1; index += 1) {
    const left = tokens[index];
    const right = tokens[index + 1];
    if (left.length <= 2 && right.length <= 2) continue;
    phrases.push([left, right]);
  }
  return phrases;
}

function matchesToken(haystack, token) {
  return tokenVariants(token).some((variant) =>
    new RegExp(`(?:^|\\s)${escapeRegExp(variant)}(?:\\s|$)`, "i").test(haystack)
  );
}

function matchesPhrase(haystack, phraseTokens) {
  const variants = phraseTokens.map(tokenVariants);
  for (const left of variants[0]) {
    for (const right of variants[1]) {
      const phrase = `${left} ${right}`;
      if (haystack.includes(phrase)) return true;
    }
  }
  return false;
}

function tokenVariants(token) {
  const streetSuffixes = {
    avenue: ["ave"],
    ave: ["avenue"],
    boulevard: ["blvd"],
    blvd: ["boulevard"],
    circle: ["cir"],
    cir: ["circle"],
    court: ["ct"],
    ct: ["court"],
    drive: ["dr"],
    dr: ["drive"],
    highway: ["hwy"],
    hwy: ["highway"],
    lane: ["ln"],
    ln: ["lane"],
    parkway: ["pkwy"],
    pkwy: ["parkway"],
    road: ["rd"],
    rd: ["road"],
    street: ["st"],
    st: ["street"],
    terrace: ["ter"],
    ter: ["terrace"]
  };
  const states = {
    alabama: ["al"],
    al: ["alabama"],
    alaska: ["ak"],
    ak: ["alaska"],
    arizona: ["az"],
    az: ["arizona"],
    arkansas: ["ar"],
    ar: ["arkansas"],
    california: ["ca"],
    ca: ["california"],
    colorado: ["co"],
    co: ["colorado"],
    connecticut: ["ct"],
    delaware: ["de"],
    de: ["delaware"],
    florida: ["fl"],
    fl: ["florida"],
    georgia: ["ga"],
    ga: ["georgia"],
    illinois: ["il"],
    il: ["illinois"],
    indiana: ["in"],
    kansas: ["ks"],
    ks: ["kansas"],
    kentucky: ["ky"],
    ky: ["kentucky"],
    mississippi: ["ms"],
    ms: ["mississippi"],
    missouri: ["mo"],
    mo: ["missouri"],
    north: ["n"],
    n: ["north"],
    south: ["s"],
    s: ["south"],
    tennessee: ["tn"],
    tn: ["tennessee"],
    texas: ["tx"],
    tx: ["texas"],
    virginia: ["va"],
    va: ["virginia"]
  };

  return Array.from(new Set([
    token,
    ...(streetSuffixes[token] || []),
    ...(states[token] || [])
  ]));
}

function normalizeSearchText(text) {
  return String(text || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export async function computeWalkingRoute({
  origin,
  destination,
  language = "en-US",
  apiKey,
  fetchImpl = fetch
}) {
  const response = await fetchImpl(ROUTES_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": ROUTES_FIELD_MASK
    },
    body: JSON.stringify({
      origin: { location: { latLng: toGoogleLatLng(origin) } },
      destination: { location: { latLng: toGoogleLatLng(destination) } },
      travelMode: "WALK",
      languageCode: language,
      units: "IMPERIAL"
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new GoogleApiError("Google Routes API request failed.", {
      status: response.status,
      payload
    });
  }

  const rawRoute = payload.routes?.[0];
  if (!rawRoute) {
    throw new GoogleApiError("Google Routes API returned no route.", { payload });
  }

  return normalizeRoute(rawRoute, origin, destination);
}

export async function getStreetViewMetadata({
  coordinate,
  radiusMeters = 35,
  apiKey,
  fetchImpl = fetch
}) {
  const params = new URLSearchParams({
    location: `${coordinate.latitude},${coordinate.longitude}`,
    radius: String(radiusMeters),
    source: "outdoor",
    key: apiKey
  });
  const response = await fetchImpl(`${STREET_VIEW_METADATA_ENDPOINT}?${params.toString()}`);
  const payload = await response.json().catch(() => ({}));

  if (!response.ok) {
    throw new GoogleApiError("Street View metadata request failed.", {
      status: response.status,
      payload
    });
  }

  return {
    status: payload.status,
    panoId: payload.pano_id || null,
    date: payload.date || null,
    coordinate: payload.location
      ? { latitude: payload.location.lat, longitude: payload.location.lng }
      : coordinate,
    copyright: payload.copyright || null
  };
}

export async function reverseGeocode({
  coordinate,
  language = "en-US",
  apiKey,
  fetchImpl = fetch
}) {
  const params = new URLSearchParams({
    latlng: `${coordinate.latitude},${coordinate.longitude}`,
    language,
    result_type: "street_address|route|intersection",
    key: apiKey
  });

  const response = await fetchImpl(`${GEOCODING_ENDPOINT}?${params.toString()}`);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !["OK", "ZERO_RESULTS"].includes(payload.status)) {
    throw new GoogleApiError("Reverse geocoding request failed.", {
      status: response.status,
      payload
    });
  }

  const results = payload.results || [];
  const route = results.find((result) => result.types?.includes("route")) || results[0];
  const intersection = results.find((result) => result.types?.includes("intersection"));

  return {
    streetName: route ? cleanPlaceContextName(extractStreetName(route) || route.formatted_address) : null,
    nearestIntersection: cleanPlaceContextName(intersection?.formatted_address)
  };
}

export async function getNearbyLandmarks({
  coordinate,
  language = "en-US",
  apiKey,
  fetchImpl = fetch
}) {
  const response = await fetchImpl(PLACES_NEARBY_SEARCH_ENDPOINT, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Goog-Api-Key": apiKey,
      "X-Goog-FieldMask": [
        "places.displayName",
        "places.types",
        "places.location"
      ].join(",")
    },
    body: JSON.stringify({
      languageCode: language,
      maxResultCount: 6,
      rankPreference: "DISTANCE",
      includedTypes: [
        "store",
        "restaurant",
        "cafe",
        "transit_station",
        "school",
        "park",
        "bank",
        "pharmacy"
      ],
      locationRestriction: {
        circle: {
          center: toGoogleLatLng(coordinate),
          radius: 90
        }
      }
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new GoogleApiError("Nearby places request failed.", {
      status: response.status,
      payload
    });
  }

  return (payload.places || [])
    .map((place) => place.displayName?.text)
    .filter(Boolean)
    .slice(0, 5);
}

export async function fetchStreetViewImage({
  coordinate,
  headingDegrees,
  apiKey,
  size = "640x640",
  fetchImpl = fetch
}) {
  const params = new URLSearchParams({
    size,
    location: `${coordinate.latitude},${coordinate.longitude}`,
    heading: String(Math.round(headingDegrees)),
    fov: "80",
    pitch: "0",
    source: "outdoor",
    return_error_code: "true",
    key: apiKey
  });

  const response = await fetchImpl(`${STREET_VIEW_IMAGE_ENDPOINT}?${params.toString()}`);
  if (!response.ok) {
    throw new GoogleApiError("Street View image request failed.", {
      status: response.status
    });
  }

  const contentType = response.headers.get("content-type") || "image/jpeg";
  const bytes = Buffer.from(await response.arrayBuffer());

  return { bytes, contentType };
}

function normalizeRoute(rawRoute, fallbackOrigin, fallbackDestination) {
  const overviewCoordinates = decodePolyline(rawRoute.polyline?.encodedPolyline);
  const steps = [];

  for (const leg of rawRoute.legs || []) {
    for (const step of leg.steps || []) {
      const encodedStepPolyline = step.polyline?.encodedPolyline || "";
      const startLocation = fromGoogleLocation(step.startLocation) || fallbackOrigin;
      const endLocation = fromGoogleLocation(step.endLocation) || fallbackDestination;

      steps.push({
        distanceMeters: step.distanceMeters || 0,
        duration: step.staticDuration || null,
        instruction: stripHtml(step.navigationInstruction?.instructions || "Continue along the walking route."),
        maneuver: step.navigationInstruction?.maneuver || null,
        startLocation,
        endLocation,
        encodedPolyline: encodedStepPolyline,
        polylineCoordinates: decodePolyline(encodedStepPolyline)
      });
    }
  }

  return {
    distanceMeters: rawRoute.distanceMeters || 0,
    duration: rawRoute.duration || null,
    encodedPolyline: rawRoute.polyline?.encodedPolyline || null,
    overviewCoordinates: overviewCoordinates.length ? overviewCoordinates : [fallbackOrigin, fallbackDestination],
    origin: fallbackOrigin,
    destination: fallbackDestination,
    steps: steps.length ? steps : [{
      distanceMeters: rawRoute.distanceMeters || 0,
      duration: rawRoute.duration || null,
      instruction: "Continue along the walking route.",
      startLocation: fallbackOrigin,
      endLocation: fallbackDestination,
      encodedPolyline: rawRoute.polyline?.encodedPolyline || "",
      polylineCoordinates: overviewCoordinates
    }]
  };
}

function toGoogleLatLng(coordinate) {
  return {
    latitude: coordinate.latitude,
    longitude: coordinate.longitude
  };
}

function fromGoogleLatLng(latLng) {
  return {
    latitude: latLng.latitude,
    longitude: latLng.longitude
  };
}

function fromLegacyLatLng(latLng) {
  return {
    latitude: latLng.lat,
    longitude: latLng.lng
  };
}

function normalizeDestination(destination) {
  return {
    ...destination,
    coordinate: {
      latitude: Number(destination.coordinate.latitude),
      longitude: Number(destination.coordinate.longitude)
    }
  };
}

function fromGoogleLocation(location) {
  const latLng = location?.latLng;
  if (!latLng) return null;
  return {
    latitude: latLng.latitude,
    longitude: latLng.longitude
  };
}

function stripHtml(text) {
  return String(text)
    .replace(/<[^>]*>/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function extractStreetName(result) {
  const route = result.address_components?.find((component) => component.types?.includes("route"));
  return route?.long_name || null;
}

function cleanPlaceContextName(value) {
  const text = String(value || "").trim();
  if (!text) return null;
  if (/^unnamed(?:\s+road)?$/i.test(text)) return null;
  if (/\bunnamed road\b/i.test(text)) return null;
  if (/^-?\d+(?:\.\d+)?\s*,\s*-?\d+(?:\.\d+)?$/.test(text)) return null;
  return text;
}
