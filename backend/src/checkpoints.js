import {
  bearingDegrees,
  coordinateKey,
  cumulativeDistances,
  haversineDistanceMeters,
  interpolateCoordinate
} from "./geo.js";

export function buildRouteStages({
  route,
  publicBaseUrl,
  maxStages = 30,
  checkpointSpacingMeters = 50
}) {
  const candidates = collectCandidates(route, checkpointSpacingMeters);
  const reduced = enforceStageLimit(dedupeCandidates(candidates), maxStages);

  return reduced.map((candidate, index) => {
    const next = reduced[index + 1]?.coordinate || candidate.nextCoordinate || candidate.coordinate;
    const headingDegrees = Math.round(bearingDegrees(candidate.coordinate, next));

    return {
      id: `stage-${String(index + 1).padStart(3, "0")}`,
      index,
      coordinate: candidate.coordinate,
      routeDistanceMeters: Math.round(candidate.routeDistanceMeters),
      headingDegrees,
      routeInstruction: candidate.instruction,
      kind: candidate.kind,
      snapshotUrl: makeStreetViewProxyUrl(publicBaseUrl, candidate.coordinate, headingDegrees),
      streetView: null,
      description: null,
      context: {
        streetName: null,
        nearestIntersection: null,
        nearbyLandmarks: [],
        streetViewAvailable: false,
        streetViewDate: null,
        fallbackReason: null
      }
    };
  });
}

function collectCandidates(route, spacingMeters) {
  const candidates = [];
  const overview = route.overviewCoordinates;
  const overviewDistances = cumulativeDistances(overview);

  for (const step of route.steps) {
    const points = step.polylineCoordinates?.length >= 2
      ? step.polylineCoordinates
      : [step.startLocation, step.endLocation].filter(Boolean);
    if (!points.length) continue;

    addCandidate(candidates, {
      coordinate: points[0],
      nextCoordinate: points[1],
      instruction: step.instruction,
      kind: "maneuver",
      routeDistanceMeters: nearestRouteDistance(points[0], overview, overviewDistances)
    });

    addSegmentSamples(candidates, points, spacingMeters, step.instruction, overview, overviewDistances);
  }

  const destination = overview[overview.length - 1] || route.destination;
  if (destination) {
    addCandidate(candidates, {
      coordinate: destination,
      instruction: "Arrive near the destination.",
      kind: "destination",
      routeDistanceMeters: route.distanceMeters || nearestRouteDistance(destination, overview, overviewDistances)
    });
  }

  return candidates.sort(compareCandidates);
}

function addSegmentSamples(candidates, points, spacingMeters, instruction, overview, overviewDistances) {
  for (let index = 1; index < points.length; index += 1) {
    const start = points[index - 1];
    const end = points[index];
    const segmentDistance = haversineDistanceMeters(start, end);
    const sampleCount = Math.floor(segmentDistance / spacingMeters);

    for (let sample = 1; sample <= sampleCount; sample += 1) {
      const coordinate = interpolateCoordinate(start, end, (sample * spacingMeters) / segmentDistance);
      addCandidate(candidates, {
        coordinate,
        nextCoordinate: end,
        instruction,
        kind: "checkpoint",
        routeDistanceMeters: nearestRouteDistance(coordinate, overview, overviewDistances)
      });
    }
  }
}

function addCandidate(candidates, candidate) {
  if (!candidate.coordinate) return;
  candidates.push(candidate);
}

function dedupeCandidates(candidates) {
  const seen = new Set();
  const deduped = [];

  for (const candidate of candidates) {
    const key = coordinateKey(candidate.coordinate);
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(candidate);
  }

  return deduped;
}

function enforceStageLimit(candidates, maxStages) {
  if (candidates.length <= maxStages) return candidates;

  const required = candidates.filter((candidate) => candidate.kind !== "checkpoint");
  const checkpointBudget = Math.max(0, maxStages - required.length);
  const checkpoints = candidates.filter((candidate) => candidate.kind === "checkpoint");

  if (checkpointBudget === 0) {
    return evenlyPick(candidates, maxStages);
  }

  return [
    ...required,
    ...evenlyPick(checkpoints, checkpointBudget)
  ].sort(compareCandidates).slice(0, maxStages);
}

function evenlyPick(items, count) {
  if (items.length <= count) return items;
  if (count <= 0) return [];
  if (count === 1) return [items[0]];

  const picked = [];
  const step = (items.length - 1) / (count - 1);
  for (let index = 0; index < count; index += 1) {
    picked.push(items[Math.round(index * step)]);
  }
  return picked;
}

function nearestRouteDistance(point, overview, overviewDistances) {
  if (!overview.length) return 0;

  let bestIndex = 0;
  let bestDistance = Infinity;
  for (let index = 0; index < overview.length; index += 1) {
    const distance = haversineDistanceMeters(point, overview[index]);
    if (distance < bestDistance) {
      bestDistance = distance;
      bestIndex = index;
    }
  }
  return overviewDistances[bestIndex] || 0;
}

function makeStreetViewProxyUrl(publicBaseUrl, coordinate, headingDegrees) {
  const params = new URLSearchParams({
    lat: coordinate.latitude.toFixed(6),
    lng: coordinate.longitude.toFixed(6),
    heading: String(headingDegrees)
  });
  return `${publicBaseUrl.replace(/\/$/, "")}/api/streetview?${params.toString()}`;
}

function compareCandidates(a, b) {
  if (a.kind === "destination" && b.kind !== "destination") return 1;
  if (b.kind === "destination" && a.kind !== "destination") return -1;

  const distanceDelta = a.routeDistanceMeters - b.routeDistanceMeters;
  if (Math.abs(distanceDelta) > 0.1) return distanceDelta;
  return kindPriority(a.kind) - kindPriority(b.kind);
}

function kindPriority(kind) {
  if (kind === "maneuver") return 0;
  if (kind === "checkpoint") return 1;
  if (kind === "destination") return 2;
  return 3;
}
