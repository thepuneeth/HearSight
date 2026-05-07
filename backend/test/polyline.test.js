import test from "node:test";
import assert from "node:assert/strict";
import { decodePolyline } from "../src/polyline.js";

test("decodes Google encoded polylines", () => {
  const coordinates = decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");

  assert.deepEqual(coordinates, [
    { latitude: 38.5, longitude: -120.2 },
    { latitude: 40.7, longitude: -120.95 },
    { latitude: 43.252, longitude: -126.453 }
  ]);
});

test("returns an empty array for missing polylines", () => {
  assert.deepEqual(decodePolyline(""), []);
  assert.deepEqual(decodePolyline(null), []);
});
