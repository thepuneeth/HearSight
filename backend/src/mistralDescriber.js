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
    describeImage: (request) => describeImage({ ...request, apiKey, model, fetchImpl })
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
      max_tokens: 700,
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
            "You describe route familiarity cues for a blind pedestrian.",
            "Return only JSON that follows the provided schema.",
            "Never claim a crossing is safe. Never say 'cross now' or 'safe to cross'.",
            "Use cautious phrasing such as 'expect', 'Street View suggests', and 'image may be outdated'.",
            "Describe stable landmarks, surface changes visible in the image, intersections, driveways, stairs, curb cuts, storefronts, and other context that may help familiarity.",
            "This is not live safety guidance."
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

export function fallbackDescription(stage, reason = "Street View imagery was not available for this route stage.") {
  const instruction = stage.routeInstruction || "Continue along the walking route.";
  const context = stage.context || {};
  const contextParts = [
    context.streetName ? `near ${context.streetName}` : null,
    context.nearestIntersection ? `near ${context.nearestIntersection}` : null,
    Array.isArray(context.nearbyLandmarks) && context.nearbyLandmarks.length
      ? `near landmarks including ${context.nearbyLandmarks.slice(0, 2).join(" and ")}`
      : null
  ].filter(Boolean);

  return {
    spokenCue: [
      "No Street View image is available for this point.",
      contextParts.length ? `This stage appears to be ${contextParts[0]}.` : null,
      `Route instruction: ${instruction}`,
      "Use live surroundings and your normal mobility tools."
    ].filter(Boolean).join(" "),
    landmarks: Array.isArray(context.nearbyLandmarks) ? context.nearbyLandmarks : [],
    crossingOrIntersectionNotes: context.nearestIntersection ? [`Near ${context.nearestIntersection}.`] : [],
    uncertainties: [[
      cleanFallbackReason(reason),
      "No image description was generated for this stage."
    ].join(" ")],
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
    context.streetName ? `Nearby street or route name: ${context.streetName}.` : "Nearby street name is unknown.",
    context.nearestIntersection ? `Nearest intersection: ${context.nearestIntersection}.` : "Nearest intersection is unknown.",
    Array.isArray(context.nearbyLandmarks) && context.nearbyLandmarks.length
      ? `Nearby landmark names: ${context.nearbyLandmarks.join(", ")}.`
      : "Nearby landmark names are unavailable.",
    streetViewMetadata?.date ? `Street View capture date: ${streetViewMetadata.date}.` : "Street View capture date is unknown.",
    "Create one concise spoken cue of 1-3 sentences for this stage.",
    "Mention visible landmarks and uncertainty. Do not give live safety commands.",
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
    landmarks: Array.isArray(description.landmarks) ? description.landmarks : [],
    crossingOrIntersectionNotes: Array.isArray(description.crossingOrIntersectionNotes)
      ? description.crossingOrIntersectionNotes
      : [],
    uncertainties: Array.isArray(description.uncertainties) ? description.uncertainties : [],
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
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\bsafe to cross\b/gi, "crossing safety cannot be determined")
    .replace(/\bcross now\b/gi, "approach the crossing and decide using live traffic cues")
    .replace(/\byou can cross\b/gi, "do not rely on this app to decide when to cross");
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
