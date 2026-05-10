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

  return {
    id: `walkthrough-${Date.now()}`,
    language: normalized.language,
    destination,
    generatedAt: new Date().toISOString(),
    routeSummary: {
      distanceMeters: route.distanceMeters,
      duration: route.duration,
      encodedPolyline: route.encodedPolyline,
      stageCount: describedStages.length,
      safetyNotice: safetyNoticeText()
    },
    stages: describedStages
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
