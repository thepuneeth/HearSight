import test from "node:test";
import assert from "node:assert/strict";
import { fallbackDescription, sanitizeDescription } from "../src/mistralDescriber.js";
import { createWalkthrough, validateWalkthroughRequest } from "../src/walkthroughService.js";

test("validates coordinate payloads", () => {
  assert.deepEqual(validateWalkthroughRequest({
    origin: { latitude: "41.1", longitude: "-87.1" },
    destination: { latitude: 41.2, longitude: -87.2 },
    language: "en-US"
  }), {
    origin: { latitude: 41.1, longitude: -87.1 },
    destination: { latitude: 41.2, longitude: -87.2 },
    destinationText: null,
    language: "en-US"
  });

  assert.deepEqual(validateWalkthroughRequest({
    origin: { latitude: "41.1", longitude: "-87.1" },
    destinationText: "Millennium Park",
    language: "en-US"
  }), {
    origin: { latitude: 41.1, longitude: -87.1 },
    destination: null,
    destinationText: "Millennium Park",
    language: "en-US"
  });

  assert.throws(() => validateWalkthroughRequest({
    origin: { latitude: 99, longitude: 0 },
    destination: { latitude: 41.2, longitude: -87.2 }
  }), /origin/);
});

test("resolves destination text and includes clean stage context", async () => {
  const calls = [];
  const walkthrough = await createWalkthrough({
    request: {
      origin: { latitude: 41.8781, longitude: -87.6298 },
      destinationText: "Millennium Park"
    },
    config: {
      useMocks: false,
      publicBaseUrl: "http://localhost:8787",
      maxStages: 4,
      checkpointSpacingMeters: 80,
      descriptionConcurrency: 1
    },
    googleMapsClient: {
      resolveDestinationText: async ({ destinationText }) => ({
        source: "places",
        name: destinationText,
        formattedAddress: "Millennium Park, Chicago, IL",
        coordinate: { latitude: 41.8826, longitude: -87.6226 },
        confidence: "high"
      }),
      computeWalkingRoute: async ({ destination }) => mockRoute(destination),
      reverseGeocode: async () => ({
        streetName: "Michigan Avenue",
        nearestIntersection: "Michigan Avenue and Monroe Street"
      }),
      getNearbyLandmarks: async () => ["Millennium Park", "Chicago Cultural Center"],
      getStreetViewMetadata: async ({ coordinate }) => ({
        status: "OK",
        panoId: "pano-1",
        date: "2025-01",
        coordinate,
        copyright: null
      }),
      fetchStreetViewImage: async () => ({
        bytes: Buffer.from("image"),
        contentType: "image/jpeg"
      })
    },
    describer: {
      describeImage: async ({ context }) => {
        calls.push(context);
        return {
          spokenCue: `Street View suggests you are near ${context.streetName}.`,
          landmarks: context.nearbyLandmarks,
          crossingOrIntersectionNotes: [],
          uncertainties: ["image may be outdated"],
          confidence: 0.8
        };
      }
    }
  });

  assert.equal(walkthrough.destination.name, "Millennium Park");
  assert.equal(walkthrough.stages[0].context.streetName, "Michigan Avenue");
  assert.equal(walkthrough.stages[0].context.streetViewAvailable, true);
  assert.equal(walkthrough.stages[0].context.streetViewDate, "2025-01");
  assert.deepEqual(calls[0].nearbyLandmarks, ["Millennium Park", "Chicago Cultural Center"]);
});

test("uses nearby Street View fallback before giving up", async () => {
  let metadataCalls = 0;
  const walkthrough = await createWalkthrough({
    request: {
      origin: { latitude: 41.8781, longitude: -87.6298 },
      destination: { latitude: 41.8790, longitude: -87.6240 }
    },
    config: {
      useMocks: false,
      publicBaseUrl: "http://localhost:8787",
      maxStages: 2,
      checkpointSpacingMeters: 100,
      descriptionConcurrency: 1
    },
    googleMapsClient: {
      computeWalkingRoute: async () => mockRoute({ latitude: 41.8790, longitude: -87.6240 }),
      reverseGeocode: async () => ({}),
      getNearbyLandmarks: async () => [],
      getStreetViewMetadata: async ({ coordinate }) => {
        metadataCalls += 1;
        if (metadataCalls === 1) return { status: "ZERO_RESULTS", coordinate };
        return { status: "OK", date: "2024-10", coordinate };
      },
      fetchStreetViewImage: async () => ({ bytes: Buffer.from("image"), contentType: "image/jpeg" })
    },
    describer: {
      describeImage: async () => ({
        spokenCue: "Street View suggests a sidewalk ahead.",
        landmarks: [],
        crossingOrIntersectionNotes: [],
        uncertainties: [],
        confidence: 0.6
      })
    }
  });

  assert.ok(metadataCalls > 1);
  assert.equal(walkthrough.stages[0].context.streetViewAvailable, true);
  assert.equal(walkthrough.stages[0].context.streetViewDate, "2024-10");
});

test("does not speak raw Street View or Mistral failures", async () => {
  const noStreetViewCue = fallbackDescription({
    routeInstruction: "Continue west.",
    context: {
      streetName: "Main Street",
      nearestIntersection: null,
      nearbyLandmarks: [],
      streetViewAvailable: false,
      streetViewDate: null,
      fallbackReason: "Street View status was ZERO_RESULTS."
    }
  }, "Street View status was ZERO_RESULTS.").spokenCue;

  assert.doesNotMatch(noStreetViewCue, /ZERO_RESULTS|Street View status/i);
  assert.match(noStreetViewCue, /No Street View image is available/);

  const mistralCue = fallbackDescription({
    routeInstruction: "Continue west.",
    context: {
      nearbyLandmarks: []
    }
  }, "Mistral description request failed with status 500").spokenCue;

  assert.doesNotMatch(mistralCue, /Mistral|500|failed/i);
});

test("uses mock walkthroughs without external services", async () => {
  const walkthrough = await createWalkthrough({
    request: {
      origin: { latitude: 41.0, longitude: -87.0 },
      destination: { latitude: 41.001, longitude: -87.001 }
    },
    config: { useMocks: true },
    googleMapsClient: null,
    describer: null
  });

  assert.equal(walkthrough.stages.length, 3);
  assert.equal(walkthrough.stages[0].description.confidence, 0);
  assert.match(walkthrough.routeSummary.safetyNotice, /prototype/);
});

test("sanitizes unsafe crossing phrasing from model output", () => {
  const result = sanitizeDescription({
    spokenCue: "Cross now when you reach the corner because it is safe to cross.",
    landmarks: ["corner"],
    crossingOrIntersectionNotes: [],
    uncertainties: [],
    confidence: 0.9
  });

  assert.doesNotMatch(result.spokenCue, /\bcross now\b/i);
  assert.doesNotMatch(result.spokenCue, /\bsafe to cross\b/i);
  assert.equal(result.confidence, 0.9);
});

function mockRoute(destination) {
  const start = { latitude: 41.8781, longitude: -87.6298 };
  return {
    distanceMeters: 250,
    duration: "240s",
    encodedPolyline: null,
    overviewCoordinates: [start, destination],
    origin: start,
    destination,
    steps: [{
      distanceMeters: 250,
      duration: "240s",
      instruction: "Walk toward the destination.",
      startLocation: start,
      endLocation: destination,
      polylineCoordinates: [start, destination]
    }]
  };
}
