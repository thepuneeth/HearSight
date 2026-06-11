import { buildRouteStages } from "./checkpoints.js";
import { bearingDegrees, isValidCoordinate, offsetCoordinate } from "./geo.js";
import { fallbackDescription } from "./mistralDescriber.js";
import { createMockWalkthrough, safetyNoticeText } from "./mockData.js";

export class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = "ValidationError";
  }
}

export async function createWalkthrough({
  request,
  config,
  googleMapsClient,
  describer
}) {
  const normalized = validateWalkthroughRequest(request);

  if (config.useMocks) {
    return createMockWalkthrough(normalized);
  }

  const destination = normalized.destination ||
    await googleMapsClient.resolveDestinationText({
      destinationText: normalized.destinationText,
      origin: normalized.origin,
      language: normalized.language
    });

  if (destination.confidence === "low") {
    throw new ValidationError(`Destination match was too broad: ${destination.formattedAddress || destination.name}. Please enter a more specific destination.`);
  }

  const route = await googleMapsClient.computeWalkingRoute({
    origin: normalized.origin,
    destination: destination.coordinate,
    language: normalized.language
  });
  const stages = buildRouteStages({
    route,
    publicBaseUrl: config.publicBaseUrl,
    maxStages: config.maxStages,
    checkpointSpacingMeters: config.checkpointSpacingMeters
  });

  const describedStages = await mapWithConcurrency(
    stages,
    config.descriptionConcurrency,
    (stage) => describeStage(stage, normalized.language, googleMapsClient, describer)
  );
  const polishedStages = polishStages(describedStages, config.maxStages);

  return {
    id: `walkthrough-${Date.now()}`,
    language: normalized.language,
    destination,
    generatedAt: new Date().toISOString(),
    routeSummary: {
      distanceMeters: route.distanceMeters,
      duration: route.duration,
      encodedPolyline: route.encodedPolyline,
      stageCount: polishedStages.length,
      safetyNotice: safetyNoticeText()
    },
    stages: polishedStages
  };
}

export function validateWalkthroughRequest(request) {
  if (!request || typeof request !== "object") {
    throw new ValidationError("Request body must be a JSON object.");
  }

  const origin = normalizeCoordinate(request.origin);
  const destination = normalizeCoordinate(request.destination);
  const destinationText = typeof request.destinationText === "string" && request.destinationText.trim()
    ? request.destinationText.trim()
    : null;
  const language = typeof request.language === "string" && request.language.trim()
    ? request.language.trim()
    : "en-US";

  if (!isValidCoordinate(origin)) {
    throw new ValidationError("origin must include valid latitude and longitude numbers.");
  }
  if (!destinationText && !isValidCoordinate(destination)) {
    throw new ValidationError("destination must include valid latitude and longitude numbers.");
  }

  return { origin, destination: isValidCoordinate(destination) ? destination : null, destinationText, language };
}

async function describeStage(stage, language, googleMapsClient, describer) {
  const context = await buildStageContext(stage, language, googleMapsClient);

  try {
    const streetView = await findStreetViewForStage(stage, googleMapsClient);
    if (!streetView) {
      const fallbackStage = {
        ...stage,
        context: {
          ...context,
          streetViewAvailable: false,
          fallbackReason: "Street View imagery was not available nearby."
        }
      };
      return {
        ...fallbackStage,
        snapshotUrl: null,
        streetView: null,
        description: fallbackDescription(fallbackStage, fallbackStage.context.fallbackReason)
      };
    }

    const image = await googleMapsClient.fetchStreetViewImage({
      coordinate: streetView.coordinate || stage.coordinate,
      headingDegrees: stage.headingDegrees
    });

    const stageWithContext = {
      ...stage,
      coordinate: streetView.coordinate || stage.coordinate,
      context: {
        ...context,
        streetViewAvailable: true,
        streetViewDate: streetView.date,
        fallbackReason: null
      }
    };
    const description = await describer.describeImage({
      imageBytes: image.bytes,
      contentType: image.contentType,
      stage: stageWithContext,
      streetViewMetadata: streetView,
      context: stageWithContext.context,
      language
    });

    return { ...stageWithContext, streetView, description };
  } catch (error) {
    const fallbackStage = {
      ...stage,
      context: {
        ...context,
        streetViewAvailable: false,
        fallbackReason: "Image description could not be generated."
      }
    };
    return {
      ...fallbackStage,
      snapshotUrl: null,
      streetView: null,
      description: fallbackDescription(fallbackStage, error.message)
    };
  }
}

async function buildStageContext(stage, language, googleMapsClient) {
  const [geocode, landmarks] = await Promise.all([
    googleMapsClient.reverseGeocode({ coordinate: stage.coordinate, language }).catch(() => ({})),
    googleMapsClient.getNearbyLandmarks({ coordinate: stage.coordinate, language }).catch(() => [])
  ]);

  return {
    streetName: geocode.streetName || null,
    nearestIntersection: geocode.nearestIntersection || null,
    nearbyLandmarks: landmarks,
    streetViewAvailable: false,
    streetViewDate: null,
    fallbackReason: null
  };
}

function polishStages(stages, maxStages = 8) {
  if (!Array.isArray(stages) || !stages.length) return [];

  const cleaned = stages
    .map(cleanStageContext)
    .filter((stage) => stage.coordinate);
  const unique = uniqueStages(cleaned);
  const capped = capPolishedStages(unique, maxStages);

  return reindexStages(capped);
}

function cleanStageContext(stage) {
  const context = stage.context || {};
  const description = stage.description || {};
  const cleanedNearbyLandmarks = Array.isArray(context.nearbyLandmarks)
    ? context.nearbyLandmarks.map(cleanLandmarkName).filter(Boolean)
    : [];
  const cleanedDescriptionLandmarks = Array.isArray(description.landmarks)
    ? description.landmarks.map(cleanLandmarkName).filter(Boolean)
    : [];

  return {
    ...stage,
    routeInstruction: cleanDisplayText(stage.routeInstruction || ""),
    context: {
      ...context,
      streetName: cleanContextName(context.streetName),
      nearestIntersection: cleanContextName(context.nearestIntersection),
      nearbyLandmarks: cleanedNearbyLandmarks
    },
    description: {
      ...description,
      spokenCue: cleanDisplayText(description.spokenCue || stage.routeInstruction || ""),
      landmarks: cleanedDescriptionLandmarks.length ? cleanedDescriptionLandmarks : cleanedNearbyLandmarks,
      crossingOrIntersectionNotes: Array.isArray(description.crossingOrIntersectionNotes)
        ? description.crossingOrIntersectionNotes.map(cleanDisplayText).filter(Boolean)
        : [],
      uncertainties: Array.isArray(description.uncertainties)
        ? description.uncertainties.map(cleanDisplayText).filter(Boolean)
        : [],
      confidence: Number.isFinite(description.confidence) ? description.confidence : 0
    }
  };
}

function uniqueStages(stages) {
  const seenCueKeys = new Set();
  const unique = [];
  let hasFallbackCue = false;

  for (const stage of stages.sort(compareStageDistance)) {
    const cue = stage.description?.spokenCue || stage.routeInstruction || "";
    const key = normalizeCueKey(cue);
    const isDestination = stage.kind === "destination";
    const isWeakFallback = stage.description?.confidence === 0 &&
      /\bstreet view is limited here\b/i.test(cue);

    if (!isDestination && key && seenCueKeys.has(key)) continue;
    if (!isDestination && isWeakFallback && hasFallbackCue) continue;

    if (key) seenCueKeys.add(key);
    if (isWeakFallback) hasFallbackCue = true;
    unique.push(stage);
  }

  const destination = stages.find((stage) => stage.kind === "destination");
  if (destination && !unique.some((stage) => stage.kind === "destination")) {
    unique.push(destination);
  }

  return unique.sort(compareStageDistance);
}

function capPolishedStages(stages, maxStages) {
  const limit = Math.max(1, Number(maxStages) || 8);
  if (stages.length <= limit) return stages;

  const destination = stages.find((stage) => stage.kind === "destination") || stages.at(-1);
  const start = stages[0];
  const routeDistance = destination?.routeDistanceMeters ||
    Math.max(...stages.map((stage) => stage.routeDistanceMeters || 0));
  const finalApproachStart = Math.max(0, routeDistance - 350);
  const required = [start]
    .concat(stages.filter((stage) => stage.kind === "maneuver" && stage.routeDistanceMeters >= finalApproachStart))
    .concat(destination ? [destination] : [])
    .filter(Boolean);
  const requiredIds = new Set(required.map((stage) => stage.id));
  const finalApproach = stages.filter((stage) =>
    stage.routeDistanceMeters >= finalApproachStart && !requiredIds.has(stage.id)
  );
  const routeProgress = stages.filter((stage) =>
    stage.routeDistanceMeters < finalApproachStart &&
    stage.kind !== "destination" &&
    !requiredIds.has(stage.id)
  );
  const routeBudget = routeDistance > 3200 ? 2 : routeDistance > 800 ? 1 : 0;
  const finalBudget = Math.max(0, limit - required.length - routeBudget);

  return [
    ...required,
    ...evenlyPick(routeProgress, Math.max(0, Math.min(routeBudget, limit - required.length))),
    ...evenlyPick(finalApproach, finalBudget)
  ]
    .sort(compareStageDistance)
    .slice(0, limit);
}

function reindexStages(stages) {
  return stages
    .sort(compareStageDistance)
    .map((stage, index) => ({
      ...stage,
      id: `stage-${String(index + 1).padStart(3, "0")}`,
      index
    }));
}

function evenlyPick(items, count) {
  if (items.length <= count) return items;
  if (count <= 0) return [];
  if (count === 1) return [items.at(-1)];

  const picked = [];
  const step = (items.length - 1) / (count - 1);
  for (let index = 0; index < count; index += 1) {
    picked.push(items[Math.round(index * step)]);
  }
  return picked;
}

function cleanContextName(value) {
  const text = cleanDisplayText(value || "");
  if (!text) return null;
  if (/^the (?:destination area|final approach)$/i.test(text)) return null;
  return text;
}

function cleanLandmarkName(value) {
  const text = cleanDisplayText(value || "");
  if (!text) return null;
  const normalized = text.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
  const blocked = new Set([
    "traffic",
    "road",
    "the route",
    "sidewalk",
    "destination",
    "entrance",
    "building",
    "nearby signage",
    "final approach",
    "normal mobility tools",
    "street view"
  ]);
  if (blocked.has(normalized)) return null;
  if (normalized.includes("unnamed road")) return null;
  return text;
}

function cleanDisplayText(value) {
  return String(value || "")
    .replace(/\bUnnamed Road\b/gi, "the destination area")
    .replace(/\bnear the final approach near the final approach\b/gi, "near the destination area")
    .replace(/\bExpect the final approach near the final approach\b/gi, "Expect the final approach near the destination area")
    .replace(/\bNo Street View image is available[^.]*\.?/gi, "Street View is limited here.")
    .replace(/\s+/g, " ")
    .replace(/\s+\./g, ".")
    .trim();
}

function normalizeCueKey(value) {
  return cleanDisplayText(value)
    .toLowerCase()
    .replace(/\bstreet view is limited here\b/g, "")
    .replace(/\buse route instructions and normal mobility tools\b/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function compareStageDistance(a, b) {
  if (a.kind === "destination" && b.kind !== "destination") return 1;
  if (b.kind === "destination" && a.kind !== "destination") return -1;

  const distanceDelta = (a.routeDistanceMeters || 0) - (b.routeDistanceMeters || 0);
  if (Math.abs(distanceDelta) > 0.1) return distanceDelta;
  return (a.index || 0) - (b.index || 0);
}

async function findStreetViewForStage(stage, googleMapsClient) {
  const candidates = streetViewCandidateCoordinates(stage);
  const tried = new Set();

  for (const coordinate of candidates) {
    const key = `${coordinate.latitude.toFixed(6)},${coordinate.longitude.toFixed(6)}`;
    if (tried.has(key)) continue;
    tried.add(key);

    const metadata = await googleMapsClient
      .getStreetViewMetadata({ coordinate, radiusMeters: 45 })
      .catch(() => null);

    if (metadata?.status === "OK") return metadata;
  }

  return null;
}

function streetViewCandidateCoordinates(stage) {
  const heading = Number.isFinite(stage.headingDegrees) ? stage.headingDegrees : 0;
  const next = stage.nextCoordinate || offsetCoordinate(stage.coordinate, 20, heading);
  const forwardBearing = bearingDegrees(stage.coordinate, next);

  return [
    stage.coordinate,
    next,
    offsetCoordinate(stage.coordinate, 18, forwardBearing),
    offsetCoordinate(stage.coordinate, 18, (forwardBearing + 180) % 360),
    offsetCoordinate(stage.coordinate, 12, (forwardBearing + 90) % 360),
    offsetCoordinate(stage.coordinate, 12, (forwardBearing + 270) % 360)
  ];
}

function normalizeCoordinate(value) {
  if (!value || typeof value !== "object") return null;
  if (!hasCoordinateValue(value.latitude) || !hasCoordinateValue(value.longitude)) return null;
  return {
    latitude: Number(value.latitude),
    longitude: Number(value.longitude)
  };
}

function hasCoordinateValue(value) {
  return value !== null && value !== undefined && value !== "";
}

async function mapWithConcurrency(items, concurrency, mapper) {
  const results = new Array(items.length);
  let nextIndex = 0;
  const workerCount = Math.max(1, Math.min(Number(concurrency) || 1, items.length));

  async function worker() {
    while (nextIndex < items.length) {
      const index = nextIndex;
      nextIndex += 1;
      results[index] = await mapper(items[index], index);
    }
  }

  await Promise.all(Array.from({ length: workerCount }, worker));
  return results;
}
