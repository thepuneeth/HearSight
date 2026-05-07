const EARTH_RADIUS_METERS = 6371008.8;

export function toRadians(degrees) {
  return degrees * Math.PI / 180;
}

export function toDegrees(radians) {
  return radians * 180 / Math.PI;
}

export function haversineDistanceMeters(a, b) {
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const dLat = toRadians(b.latitude - a.latitude);
  const dLng = toRadians(b.longitude - a.longitude);

  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.sqrt(h));
}

export function bearingDegrees(a, b) {
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const dLng = toRadians(b.longitude - a.longitude);

  const y = Math.sin(dLng) * Math.cos(lat2);
  const x = Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);

  return (toDegrees(Math.atan2(y, x)) + 360) % 360;
}

export function interpolateCoordinate(a, b, fraction) {
  const clamped = Math.max(0, Math.min(1, fraction));
  return {
    latitude: a.latitude + (b.latitude - a.latitude) * clamped,
    longitude: a.longitude + (b.longitude - a.longitude) * clamped
  };
}

export function offsetCoordinate(coordinate, distanceMeters, bearing) {
  const angularDistance = distanceMeters / EARTH_RADIUS_METERS;
  const bearingRadians = toRadians(bearing);
  const latitudeRadians = toRadians(coordinate.latitude);
  const longitudeRadians = toRadians(coordinate.longitude);

  const targetLatitude = Math.asin(
    Math.sin(latitudeRadians) * Math.cos(angularDistance) +
    Math.cos(latitudeRadians) * Math.sin(angularDistance) * Math.cos(bearingRadians)
  );
  const targetLongitude = longitudeRadians + Math.atan2(
    Math.sin(bearingRadians) * Math.sin(angularDistance) * Math.cos(latitudeRadians),
    Math.cos(angularDistance) - Math.sin(latitudeRadians) * Math.sin(targetLatitude)
  );

  return {
    latitude: toDegrees(targetLatitude),
    longitude: ((toDegrees(targetLongitude) + 540) % 360) - 180
  };
}

export function cumulativeDistances(points) {
  const distances = [0];
  for (let index = 1; index < points.length; index += 1) {
    distances.push(
      distances[index - 1] + haversineDistanceMeters(points[index - 1], points[index])
    );
  }
  return distances;
}

export function coordinateKey(coordinate) {
  return `${coordinate.latitude.toFixed(6)},${coordinate.longitude.toFixed(6)}`;
}

export function isValidCoordinate(value) {
  return value &&
    Number.isFinite(value.latitude) &&
    Number.isFinite(value.longitude) &&
    value.latitude >= -90 &&
    value.latitude <= 90 &&
    value.longitude >= -180 &&
    value.longitude <= 180;
}

export function distanceFromPolylineMeters(point, polyline) {
  if (!polyline.length) return Infinity;
  if (polyline.length === 1) return haversineDistanceMeters(point, polyline[0]);

  let best = Infinity;
  for (let index = 1; index < polyline.length; index += 1) {
    best = Math.min(best, distanceFromSegmentMeters(point, polyline[index - 1], polyline[index]));
  }
  return best;
}

function distanceFromSegmentMeters(point, start, end) {
  const meanLat = toRadians((start.latitude + end.latitude + point.latitude) / 3);
  const metersPerDegreeLat = 111320;
  const metersPerDegreeLng = 111320 * Math.cos(meanLat);

  const px = (point.longitude - start.longitude) * metersPerDegreeLng;
  const py = (point.latitude - start.latitude) * metersPerDegreeLat;
  const vx = (end.longitude - start.longitude) * metersPerDegreeLng;
  const vy = (end.latitude - start.latitude) * metersPerDegreeLat;
  const lengthSquared = vx * vx + vy * vy;

  if (lengthSquared === 0) return haversineDistanceMeters(point, start);

  const t = Math.max(0, Math.min(1, (px * vx + py * vy) / lengthSquared));
  const projection = {
    latitude: start.latitude + (end.latitude - start.latitude) * t,
    longitude: start.longitude + (end.longitude - start.longitude) * t
  };

  return haversineDistanceMeters(point, projection);
}
