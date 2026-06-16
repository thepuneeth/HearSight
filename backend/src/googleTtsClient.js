const TTS_ENDPOINT = "https://texttospeech.googleapis.com/v1/text:synthesize";
const MAX_TTS_TEXT_CHARS = 1000;

export class GoogleTtsError extends Error {
  constructor(message, { status, payload } = {}) {
    super(message);
    this.name = "GoogleTtsError";
    this.status = status;
    this.payload = payload;
  }
}

export function createGoogleTtsClient({ apiKey, voice, audioEncoding = "MP3", fetchImpl = fetch }) {
  return {
    synthesizeSpeech: (request) => synthesizeSpeech({
      ...request,
      apiKey,
      voice,
      audioEncoding,
      fetchImpl
    })
  };
}

export async function synthesizeSpeech({
  text,
  language = "en-US",
  apiKey,
  voice = "en-US-Wavenet-F",
  audioEncoding = "MP3",
  fetchImpl = fetch
}) {
  const normalized = validateTtsText(text);
  const response = await fetchImpl(`${TTS_ENDPOINT}?key=${encodeURIComponent(apiKey)}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      input: { text: normalized },
      voice: {
        languageCode: languageCodeForVoice(voice, language),
        name: voice
      },
      audioConfig: {
        audioEncoding,
        speakingRate: 0.92
      }
    })
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new GoogleTtsError("Google Text-to-Speech request failed.", {
      status: response.status,
      payload
    });
  }

  if (!payload.audioContent) {
    throw new GoogleTtsError("Google Text-to-Speech response did not include audio.", {
      status: 502,
      payload
    });
  }

  return {
    bytes: Buffer.from(payload.audioContent, "base64"),
    contentType: contentTypeForEncoding(audioEncoding)
  };
}

function validateTtsText(text) {
  if (typeof text !== "string") {
    throw Object.assign(new Error("text is required."), { status: 400 });
  }

  const normalized = text.trim().replace(/\s+/g, " ");
  if (!normalized) {
    throw Object.assign(new Error("text is required."), { status: 400 });
  }
  if (normalized.length > MAX_TTS_TEXT_CHARS) {
    throw Object.assign(new Error(`text must be ${MAX_TTS_TEXT_CHARS} characters or less.`), { status: 413 });
  }
  return normalized;
}

function languageCodeForVoice(voice, fallbackLanguage) {
  const match = /^([a-z]{2,3}-[A-Z]{2})-/.exec(voice);
  return match?.[1] || fallbackLanguage || "en-US";
}

function contentTypeForEncoding(audioEncoding) {
  switch (audioEncoding) {
  case "MP3":
    return "audio/mpeg";
  case "OGG_OPUS":
    return "audio/ogg";
  case "LINEAR16":
    return "audio/wav";
  default:
    return "application/octet-stream";
  }
}
