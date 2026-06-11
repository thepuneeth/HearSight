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
            "You write short route familiarity cues for a blind or low-vision pedestrian.",
            "Return only JSON that follows the provided schema.",
            "Make spokenCue 1-2 short sentences maximum.",
            "Keep the tone calm, concise, and navigation-focused.",
            "Focus on stable orientation context: turns, sidewalks, crossings, intersections, signs, entrances, major buildings, and parks.",
            "Only include specific named places or clear physical objects in landmarks.",
            "Do not list generic concepts such as traffic, road, sidewalk, entrance, destination, or mobility tools as landmarks.",
            "Do not be overly descriptive.",
            "Never claim a crossing is safe. Never say 'cross now' or 'safe to cross'.",
            "Do not make safety decisions.",
            "Do not speak confidently about traffic, construction, crowds, weather, lighting, or other temporary conditions.",
            "When uncertain, use cautious wording such as 'appears' or 'possible'.",
            "This is route familiarity, not live safety guidance."
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
  const instruction = sanitizeCue(stage.routeInstruction || "Continue along the walking route.");
  const context = stage.context || {};
  const approachTarget = sanitizeCue(context.streetName ||
    context.nearestIntersection ||
    (Array.isArray(context.nearbyLandmarks) ? context.nearbyLandmarks[0] : null) ||
    "");
  const routeContext = approachTarget
    ? `Use nearby context around ${approachTarget} and normal mobility tools.`
    : `${instruction} Use route instructions and normal mobility tools.`;

  return {
    spokenCue: `Street View is limited here. ${routeContext}`,
    landmarks: Array.isArray(context.nearbyLandmarks)
      ? context.nearbyLandmarks.map(sanitizeCue).filter(Boolean)
      : [],
    crossingOrIntersectionNotes: context.nearestIntersection ? [`Near ${sanitizeCue(context.nearestIntersection)}.`] : [],
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
    "Create one calm spoken cue of 1-2 short sentences for this stage.",
    "Prioritize stable orientation context: turns, sidewalks, crossings, intersections, signs, entrances, major buildings, and parks.",
    "Use named landmarks only when they are specific places or physical objects.",
    "Avoid extra visual detail. Do not give live safety commands or safety judgments.",
    "Do not confidently describe traffic, construction, crowds, weather, lighting, or other temporary conditions.",
    "Use 'appears' or 'possible' when uncertain.",
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
    .replace(/\bNo Street View image is available[^.]*\.?/gi, "Street View is limited here.")
    .replace(/\bStreet View unavailable\b/gi, "Street View is limited here")
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
