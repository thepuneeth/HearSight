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
  maxStages = 8,
  checkpointSpacingMeters = 120
}) {
  const candidates = collectCandidates(route, checkpointSpacingMeters);
  const reduced = enforceStageLimit(
    preferFinalApproach(compactCandidates(dedupeCandidates(candidates)), maxStages),
    maxStages
  );

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

function compactCandidates(candidates) {
  const compacted = [];
  const minDistanceMeters = 36;

  for (const candidate of candidates.sort(compareCandidates)) {
    const previous = compacted.at(-1);

    if (candidate.kind === "destination") {
      if (previous?.kind === "checkpoint" &&
          Math.abs(candidate.routeDistanceMeters - previous.routeDistanceMeters) < minDistanceMeters) {
        compacted.pop();
      }
      compacted.push(candidate);
      continue;
    }

    if (previous && candidate.kind === "checkpoint") {
      const distanceDelta = Math.abs(candidate.routeDistanceMeters - previous.routeDistanceMeters);
      const sameInstruction = normalizeInstruction(candidate.instruction) === normalizeInstruction(previous.instruction);
      if (distanceDelta < minDistanceMeters || sameInstruction && distanceDelta < 95) {
        continue;
      }
    }

    compacted.push(candidate);
  }

  return compacted.sort(compareCandidates);
}

function preferFinalApproach(candidates, maxStages) {
  if (candidates.length <= maxStages) return candidates;

  const destination = candidates.find((candidate) => candidate.kind === "destination") || candidates.at(-1);
  const start = candidates[0];
  const routeDistance = destination?.routeDistanceMeters || Math.max(...candidates.map((candidate) => candidate.routeDistanceMeters));

  // Scale final approach with route length: 15% of route, min 350m, max 1500m
  const finalApproachLength = Math.min(Math.max(routeDistance * 0.15, 350), 1500);
  const finalApproachStart = Math.max(0, routeDistance - finalApproachLength);

  // Always keep: start, destination, and every turn in the final approach
  const required = [start]
    .concat(candidates.filter((candidate) => candidate.kind === "maneuver" && candidate.routeDistanceMeters >= finalApproachStart))
    .concat(destination ? [destination] : [])
    .filter(Boolean);

  const requiredKeys = new Set(required.map(candidateKey));

  // Early zone: prefer maneuvers; fall back to checkpoints if none exist
  const earlyManeuvers = candidates.filter((candidate) =>
    candidate.kind === "maneuver" &&
    candidate.routeDistanceMeters < finalApproachStart &&
    !requiredKeys.has(candidateKey(candidate))
  );
  const earlyCheckpoints = candidates.filter((candidate) =>
    candidate.kind === "checkpoint" &&
    candidate.routeDistanceMeters < finalApproachStart &&
    !requiredKeys.has(candidateKey(candidate))
  );
  const earlySlotCandidates = earlyManeuvers.length > 0 ? earlyManeuvers : earlyCheckpoints;

  const finalApproachCheckpoints = candidates.filter((candidate) =>
    candidate.kind === "checkpoint" &&
    candidate.routeDistanceMeters >= finalApproachStart &&
    !requiredKeys.has(candidateKey(candidate))
  );

  const remainingBudget = Math.max(0, maxStages - required.length);
  const finalDetailBudget = Math.min(2, Math.floor(remainingBudget / 3));
  const routeManeuverBudget = remainingBudget - finalDetailBudget;

  const earlyPicked = evenlyPick(earlySlotCandidates, routeManeuverBudget);
  const spillover = routeManeuverBudget - earlyPicked.length;
  const finalPicked = evenlyPick(finalApproachCheckpoints, finalDetailBudget + spillover);

  return uniqueCandidates([
    ...required,
    ...earlyPicked,
    ...finalPicked
  ]).sort(compareCandidates);
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

function uniqueCandidates(candidates) {
  const seen = new Set();
  const unique = [];

  for (const candidate of candidates) {
    const key = candidateKey(candidate);
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(candidate);
  }

  return unique;
}

function candidateKey(candidate) {
  return `${candidate.kind}:${coordinateKey(candidate.coordinate)}:${normalizeInstruction(candidate.instruction)}`;
}

function normalizeInstruction(instruction) {
  return String(instruction || "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
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
  if (overview.length === 1) return 0;

  let bestDistance = Infinity;
  let bestRouteDistance = 0;

  for (let index = 1; index < overview.length; index += 1) {
    const start = overview[index - 1];
    const end = overview[index];
    const segmentDistance = overviewDistances[index] - overviewDistances[index - 1] ||
      haversineDistanceMeters(start, end);
    const fraction = projectedFraction(point, start, end);
    const projected = interpolateCoordinate(start, end, fraction);
    const distance = haversineDistanceMeters(point, projected);

    if (distance < bestDistance) {
      bestDistance = distance;
      bestRouteDistance = (overviewDistances[index - 1] || 0) + segmentDistance * fraction;
    }
  }

  return bestRouteDistance;
}

function projectedFraction(point, start, end) {
  const meanLatitude = toRadians((point.latitude + start.latitude + end.latitude) / 3);
  const pointX = point.longitude * Math.cos(meanLatitude);
  const pointY = point.latitude;
  const startX = start.longitude * Math.cos(meanLatitude);
  const startY = start.latitude;
  const endX = end.longitude * Math.cos(meanLatitude);
  const endY = end.latitude;
  const deltaX = endX - startX;
  const deltaY = endY - startY;
  const lengthSquared = deltaX * deltaX + deltaY * deltaY;

  if (!lengthSquared) return 0;

  return Math.max(0, Math.min(1, ((pointX - startX) * deltaX + (pointY - startY) * deltaY) / lengthSquared));
}

function toRadians(degrees) {
  return degrees * Math.PI / 180;
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
