import test from "node:test";
import assert from "node:assert/strict";
import {
  bearingDegrees,
  distanceFromPolylineMeters,
  haversineDistanceMeters,
  interpolateCoordinate,
  isValidCoordinate
} from "../src/geo.js";

test("calculates walking-scale distances", () => {
  const a = { latitude: 41.8781, longitude: -87.6298 };
  const b = { latitude: 41.8790, longitude: -87.6298 };

  assert.ok(haversineDistanceMeters(a, b) > 95);
  assert.ok(haversineDistanceMeters(a, b) < 105);
});

test("calculates bearings", () => {
  assert.equal(Math.round(bearingDegrees(
    { latitude: 0, longitude: 0 },
    { latitude: 1, longitude: 0 }
  )), 0);

  assert.equal(Math.round(bearingDegrees(
    { latitude: 0, longitude: 0 },
    { latitude: 0, longitude: 1 }
  )), 90);
});

test("interpolates coordinates", () => {
  assert.deepEqual(
    interpolateCoordinate(
      { latitude: 10, longitude: 20 },
      { latitude: 20, longitude: 40 },
      0.5
    ),
    { latitude: 15, longitude: 30 }
  );
});

test("validates coordinate bounds", () => {
  assert.equal(isValidCoordinate({ latitude: 90, longitude: 180 }), true);
  assert.equal(isValidCoordinate({ latitude: 91, longitude: 0 }), false);
  assert.equal(isValidCoordinate({ latitude: 0, longitude: Number.NaN }), false);
});

test("estimates distance from a route polyline", () => {
  const polyline = [
    { latitude: 0, longitude: 0 },
    { latitude: 0, longitude: 0.01 }
  ];

  const near = { latitude: 0.0001, longitude: 0.005 };
  const far = { latitude: 0.01, longitude: 0.005 };

  assert.ok(distanceFromPolylineMeters(near, polyline) < 20);
  assert.ok(distanceFromPolylineMeters(far, polyline) > 1000);
});
