import test from "node:test";
import assert from "node:assert/strict";
import { buildRouteStages } from "../src/checkpoints.js";

test("creates capped, ordered stages from route steps", () => {
  const route = {
    distanceMeters: 500,
    destination: { latitude: 0, longitude: 0.0045 },
    overviewCoordinates: [
      { latitude: 0, longitude: 0 },
      { latitude: 0, longitude: 0.0045 }
    ],
    steps: [{
      instruction: "Walk east on Main Street.",
      startLocation: { latitude: 0, longitude: 0 },
      endLocation: { latitude: 0, longitude: 0.0045 },
      polylineCoordinates: [
        { latitude: 0, longitude: 0 },
        { latitude: 0, longitude: 0.0045 }
      ]
    }]
  };

  const stages = buildRouteStages({
    route,
    publicBaseUrl: "http://localhost:8787",
    maxStages: 5,
    checkpointSpacingMeters: 50
  });

  assert.equal(stages.length, 5);
  assert.equal(stages[0].id, "stage-001");
  assert.equal(stages.at(-1).kind, "destination");
  assert.ok(stages.every((stage, index) => stage.index === index));
  assert.ok(stages.every((stage) => stage.snapshotUrl.startsWith("http://localhost:8787/api/streetview?")));
  assert.ok(stages.every((stage) => stage.headingDegrees >= 0 && stage.headingDegrees <= 360));
});

test("keeps long routes compact and weighted toward final approach", () => {
  const route = {
    distanceMeters: 6000,
    destination: { latitude: 0, longitude: 0.054 },
    overviewCoordinates: [
      { latitude: 0, longitude: 0 },
      { latitude: 0, longitude: 0.018 },
      { latitude: 0, longitude: 0.036 },
      { latitude: 0, longitude: 0.054 }
    ],
    steps: [{
      instruction: "Walk east on Main Street.",
      startLocation: { latitude: 0, longitude: 0 },
      endLocation: { latitude: 0, longitude: 0.054 },
      polylineCoordinates: [
        { latitude: 0, longitude: 0 },
        { latitude: 0, longitude: 0.018 },
        { latitude: 0, longitude: 0.036 },
        { latitude: 0, longitude: 0.054 }
      ]
    }]
  };

  const stages = buildRouteStages({
    route,
    publicBaseUrl: "http://localhost:8787",
    maxStages: 8,
    checkpointSpacingMeters: 120
  });

  assert.ok(stages.length <= 8);
  assert.equal(stages.at(-1).kind, "destination");
  assert.ok(stages.filter((stage) => stage.routeDistanceMeters >= 5650).length >= 2);
  assert.ok(stages.every((stage) => !/Unnamed Road/i.test(stage.routeInstruction)));
});
