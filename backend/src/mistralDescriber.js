const DESCRIPTION_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: [
    "spokenCue",
    "landmarks",
    "crossingOrIntersectionNotes",
    "uncertainties",
    "confidence"
  ],
  properties: {
    spokenCue: { type: "string" },
    landmarks: { type: "array", items: { type: "string" } },
    crossingOrIntersectionNotes: { type: "array", items: { type: "string" } },
    uncertainties: { type: "array", items: { type: "string" } },
    confidence: { type: "number", minimum: 0, maximum: 1 }
  }
};

const MISTRAL_CHAT_COMPLETIONS_ENDPOINT = "https://api.mistral.ai/v1/chat/completions";

export function createMistralDescriber({
  apiKey,
  model = "mistral-medium-2505",
  fetchImpl = fetch
}) {
  return {
    describeImage: (request) => describeImage({ ...request, apiKey, model, fetchImpl }),
    describeWithText: (request) => describeWithText({ ...request, apiKey, model, fetchImpl })
  };
}

export async function describeImage({
  imageBytes,
  contentType = "image/jpeg",
  stage,
  streetViewMetadata,
  context,
  language = "en-US",
  apiKey,
  model,
  fetchImpl = fetch
}) {
  const prompt = buildPrompt({ stage, streetViewMetadata, context, language });
  const imageUrl = `data:${contentType};base64,${Buffer.from(imageBytes).toString("base64")}`;

  const response = await fetchImpl(MISTRAL_CHAT_COMPLETIONS_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      max_tokens: 1000,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "route_stage_description",
          schema: DESCRIPTION_SCHEMA,
          strict: true
        }
      },
      messages: [
        {
          role: "system",
          content: [
            "You write rich, reassuring route familiarity cues for a blind or low-vision pedestrian so they can build a confident mental picture of the route before they travel and feel safe.",
            "The user cannot see, so NEVER use visual phrasing: no 'you will see', 'look for', 'you'll notice', 'visible', 'spot', or 'watch for'. Instead, describe the surroundings as facts that exist there — 'there is a church on the corner', 'the road runs through a row of shops', 'a park borders the left side'.",
            "spokenCue must be 2 to 3 sentences: (1) the navigation action with direction and the street name, (2) the real, named landmarks and the character of the area along this stretch (a church, a school, a shopping row, a quiet residential street, a busy main road), and (3) the cross street or landmark at the next turn so they know the turn is coming.",
            "DESCRIBE CONFIDENTLY but only what is actually grounded in the image, the place names, and the route data. Paint the scene with real, certain detail.",
            "CRITICAL: Never invent or guess transient sensory details. Do not describe sounds, textures, surfaces, smells, breezes, or weather. Forbidden phrasing: 'may have', 'might', 'if there is a breeze', 'a slight rustling sound', 'the surface will change', and any hedged speculation. State real, stable facts confidently, or leave it out.",
            "For destination stages: describe the building and its setting using its name and type so they can picture arriving (for example, a large school set back from the road, or a storefront in a shopping row). Do not fabricate specific doors, ramps, mats, or buzzers you cannot verify.",
            "Only include specific named places or clear physical structures as landmarks.",
            "Do not list generic concepts such as traffic, road, sidewalk, entrance, destination, or mobility tools as landmarks.",
            "Never claim a crossing is safe. Do not make safety decisions.",
            "Return only JSON that follows the provided schema."
          ].join(" ")
        },
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: imageUrl }
          ]
        }
      ]
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Mistral description request failed with status ${response.status}: ${JSON.stringify(payload)}`);
  }

  return sanitizeDescription(parseChatCompletionJson(payload));
}

export async function describeWithText({
  stage,
  context,
  language = "en-US",
  apiKey,
  model,
  fetchImpl = fetch
}) {
  const response = await fetchImpl(MISTRAL_CHAT_COMPLETIONS_ENDPOINT, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model,
      temperature: 0.2,
      max_tokens: 1000,
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "route_stage_description",
          schema: DESCRIPTION_SCHEMA,
          strict: true
        }
      },
      messages: [
        {
          role: "system",
          content: [
            "You write rich, reassuring route familiarity cues for a blind or low-vision pedestrian so they can build a confident mental picture of the route and feel safe.",
            "The user cannot see, so NEVER use visual phrasing: no 'you will see', 'look for', 'you'll notice', 'visible', 'spot', or 'watch for'. Describe surroundings as facts that exist there — 'there is a school on the corner', 'the road runs through a residential neighborhood'.",
            "No Street View image is available. Build the description from the street name, the nearby named landmarks, and the navigation instruction.",
            "spokenCue must be 2 to 3 sentences: (1) the navigation action with direction and the street name, (2) the named landmarks along this stretch and the character of the area (a quiet residential street, a commercial row, a busy main road), and (3) the cross street or landmark at the next turn.",
            "Infer the character of the area from real cues: street suffix (Drive/Lane/Court/Circle = residential; Pike/Highway = busy arterial; Boulevard = commercial) and nearby place types (schools/parks/churches = residential; stores/restaurants = commercial). Describe it confidently as the likely setting.",
            "CRITICAL: Never invent transient sensory details. Do not describe sounds, textures, surfaces, smells, breezes, or weather. Forbidden phrasing: 'may have', 'might', 'if there is a breeze', 'a slight rustling sound', 'the surface will change'. State stable facts; leave out anything you cannot ground.",
            "For destination stages: describe the building and its setting from its name and type so they can picture arriving. Do not fabricate specific doors, ramps, mats, or buzzers you cannot verify.",
            "Never claim a crossing is safe. Do not make safety decisions.",
            "Return only JSON following the schema."
          ].join(" ")
        },
        {
          role: "user",
          content: buildTextPrompt({ stage, context, language })
        }
      ]
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(`Mistral text description failed with status ${response.status}: ${JSON.stringify(payload)}`);
  }

  return sanitizeDescription(parseChatCompletionJson(payload));
}

export function fallbackDescription(stage, reason = "Street View imagery was not available for this route stage.") {
  const rawInstruction = sanitizeCue(stage.routeInstruction || "Continue along the walking route.");
  const instruction = /[.!?]$/.test(rawInstruction) ? rawInstruction : `${rawInstruction}.`;
  const context = stage.context || {};
  const streetName = sanitizeCue(context.streetName || "");
  const intersection = sanitizeCue(context.nearestIntersection || "");
  const landmarks = Array.isArray(context.nearbyLandmarks)
    ? context.nearbyLandmarks.map(sanitizeCue).filter(Boolean)
    : [];

  const parts = [instruction];

  if (intersection) {
    parts.push(`The nearest intersection is ${intersection}.`);
  } else if (streetName) {
    parts.push(`You are on ${streetName}.`);
  }

  if (landmarks.length > 0) {
    parts.push(`${landmarks[0]} is nearby on this section of the route.`);
  }

  const spokenCue = parts.join(" ").replace(/\s+/g, " ").trim();

  return {
    spokenCue,
    landmarks,
    crossingOrIntersectionNotes: intersection ? [`Nearest intersection: ${intersection}.`] : [],
    uncertainties: [cleanFallbackReason(reason)],
    confidence: 0
  };
}

function buildPrompt({ stage, streetViewMetadata, context = {}, language }) {
  return [
    `Language: ${language}.`,
    `Route stage index: ${stage.index + 1}.`,
    `Approximate route distance: ${stage.routeDistanceMeters} meters from the start.`,
    `Walking instruction from route engine: ${stage.routeInstruction || "Continue."}`,
    `Camera heading: ${stage.headingDegrees} degrees.`,
    context.streetName ? `Nearby street or route name: ${sanitizeCue(context.streetName)}.` : "Nearby street name is unknown.",
    context.nearestIntersection ? `Nearest intersection: ${sanitizeCue(context.nearestIntersection)}.` : "Nearest intersection is unknown.",
    Array.isArray(context.nearbyLandmarks) && context.nearbyLandmarks.length
      ? `Nearby landmark names: ${context.nearbyLandmarks.map(sanitizeCue).filter(Boolean).join(", ")}.`
      : "Nearby landmark names are unavailable.",
    streetViewMetadata?.date ? `Street View capture date: ${streetViewMetadata.date}.` : "Street View capture date is unknown.",
    "The user is blind. Never use visual phrasing — no 'you will see', 'look for', 'visible', 'spot', 'watch for'. Describe surroundings as facts that exist there.",
    stage.kind === "destination"
      ? "This is the destination stage. Describe the building and its setting from its name and type so they can picture arriving. Do not fabricate specific doors, ramps, mats, or buzzers you cannot verify."
      : "Describe the navigation action, the named landmarks and character of the area along this stretch, and the cross street or landmark at the next turn.",
    "spokenCue: 2 to 3 sentences. Paint a confident mental picture using the real landmarks and the character of the area so the user feels prepared and safe.",
    "CRITICAL: Never invent transient sensory details. Do not describe sounds, textures, surfaces, smells, breezes, or weather. Forbidden phrasing includes 'may have', 'might', 'if there is a breeze', 'a slight rustling sound', 'the surface will change'. State stable facts confidently or leave them out.",
    "Use named landmarks only when they are specific places or physical structures.",
    "Do not give live safety commands or safety judgments.",
    "Return JSON only."
  ].join("\n");
}

function buildTextPrompt({ stage, context = {}, language }) {
  const landmarks = Array.isArray(context.nearbyLandmarks)
    ? context.nearbyLandmarks.map(sanitizeCue).filter(Boolean)
    : [];

  return [
    `Language: ${language}.`,
    `Route stage index: ${stage.index + 1}.`,
    `Route distance from walk start: ${stage.routeDistanceMeters} meters.`,
    `Navigation instruction: ${sanitizeCue(stage.routeInstruction || "Continue.")}`,
    context.streetName
      ? `Street name: ${sanitizeCue(context.streetName)}.`
      : "Street name unknown.",
    context.nearestIntersection
      ? `Nearest intersection: ${sanitizeCue(context.nearestIntersection)}.`
      : "Nearest intersection unknown.",
    landmarks.length
      ? `Nearby places: ${landmarks.join(", ")}.`
      : "No nearby landmark data.",
    stage.kind === "destination"
      ? "This is the destination. Describe the likely building type and how to find the entrance."
      : "Describe the environment character (residential, busy road, commercial, etc.) and what the user will likely hear or feel here.",
    "spokenCue: 2-3 sentences — navigation action, environment character, then sensory cues.",
    "Return JSON only."
  ].join("\n");
}

function parseChatCompletionJson(payload) {
  const content = payload.choices?.[0]?.message?.content;

  if (typeof content === "string") {
    return JSON.parse(stripJsonFence(content));
  }

  if (Array.isArray(content)) {
    const text = content
      .map((part) => part.text || part.content || "")
      .join("");
    if (text.trim()) return JSON.parse(stripJsonFence(text));
  }

  throw new Error("Mistral response did not include message content.");
}

export function sanitizeDescription(description) {
  const spokenCue = sanitizeCue(description.spokenCue || "");
  return {
    spokenCue,
    landmarks: Array.isArray(description.landmarks)
      ? description.landmarks.map(sanitizeCue).filter(Boolean)
      : [],
    crossingOrIntersectionNotes: Array.isArray(description.crossingOrIntersectionNotes)
      ? description.crossingOrIntersectionNotes.map(sanitizeCue).filter(Boolean)
      : [],
    uncertainties: Array.isArray(description.uncertainties)
      ? description.uncertainties.filter((item) => !isRepeatedOutdatedDisclaimer(item))
      : [],
    confidence: clampConfidence(description.confidence)
  };
}

function stripJsonFence(text) {
  return String(text)
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function sanitizeCue(text) {
  return String(text)
    .replace(/\bZERO_RESULTS\b/gi, "no imagery available")
    .replace(/\bREQUEST_DENIED\b/gi, "imagery unavailable")
    .replace(/\bPERMISSION_DENIED\b/gi, "imagery unavailable")
    .replace(/\bINVALID_REQUEST\b/gi, "imagery unavailable")
    .replace(/\bUNKNOWN_ERROR\b/gi, "imagery unavailable")
    .replace(/\bGoogleApiError\b/g, "")
    .replace(/\bError:\s*/g, "")
    .replace(/\bUnnamed Road\b/gi, "the route")
    .replace(/\bNo Street View image is available[^.]*\.?/gi, "Use route instructions and normal mobility tools.")
    .replace(/\bStreet View is limited here[^.]*\.?/gi, "Use route instructions and normal mobility tools.")
    .replace(/\bStreet View unavailable\b/gi, "Use route instructions and normal mobility tools")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b(?:the )?image may be outdated\.?/gi, "")
    .replace(/\bStreet View may be outdated\.?/gi, "")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\bsafe to cross\b/gi, "crossing safety cannot be determined")
    .replace(/\bcross now\b/gi, "approach the crossing and decide using live traffic cues")
    .replace(/\byou can cross\b/gi, "do not rely on this app to decide when to cross");
}

function isRepeatedOutdatedDisclaimer(text) {
  return /\b(?:image|street view) may be outdated\b/i.test(String(text || ""));
}

function cleanFallbackReason(reason) {
  const text = String(reason || "Street View imagery was not available.");
  if (/\bZERO_RESULTS\b/i.test(text)) return "Street View imagery was not available nearby.";
  if (/\bREQUEST_DENIED|PERMISSION_DENIED\b/i.test(text)) return "Street View imagery could not be loaded.";
  if (/Mistral/i.test(text)) return "Image description could not be generated.";
  return "Street View imagery was not available nearby.";
}

function clampConfidence(value) {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}
