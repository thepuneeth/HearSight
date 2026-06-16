export function createMockWalkthrough({ origin, destination, language = "en-US" }) {
  const midpoint = {
    latitude: (origin.latitude + destination.latitude) / 2,
    longitude: (origin.longitude + destination.longitude) / 2
  };

  return {
    id: `mock-${Date.now()}`,
    language,
    generatedAt: new Date().toISOString(),
    routeSummary: {
      distanceMeters: 240,
      duration: "240s",
      encodedPolyline: null,
      stageCount: 3,
      safetyNotice: safetyNoticeText()
    },
    stages: [
      mockStage(0, origin, 45, "Start walking toward the destination.", "At the start, expect to orient yourself before moving. Street View may be unavailable."),
      mockStage(1, midpoint, 90, "Continue straight.", "About halfway, expect a simple continuation point."),
      mockStage(2, destination, 0, "Arrive near the destination.", "You are near the destination. Confirm the entrance and surroundings using live cues.")
    ]
  };
}

function mockStage(index, coordinate, headingDegrees, instruction, cue) {
  return {
    id: `stage-${String(index + 1).padStart(3, "0")}`,
    index,
    coordinate,
    routeDistanceMeters: index * 120,
    headingDegrees,
    routeInstruction: instruction,
    kind: index === 0 ? "maneuver" : index === 2 ? "destination" : "checkpoint",
    snapshotUrl: null,
    streetView: {
      status: "MOCK",
      panoId: null,
      date: null,
      coordinate,
      copyright: null
    },
    description: {
      spokenCue: cue,
      landmarks: [],
      crossingOrIntersectionNotes: [],
      uncertainties: ["Live route details may be limited."],
      confidence: 0
    }
  };
}

export function safetyNoticeText() {
  return "Street View may be outdated. Use this for route familiarity, not safety decisions.";
}
