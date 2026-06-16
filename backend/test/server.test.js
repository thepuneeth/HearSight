import test from "node:test";
import assert from "node:assert/strict";
import { Readable } from "node:stream";
import { createAppServer } from "../src/server.js";

test("returns clean 400 for missing or null coordinates", async () => {
  const handler = createAppServer({
    config: {
      useMocks: true,
      publicBaseUrl: "http://localhost",
      maxStages: 3,
      checkpointSpacingMeters: 80,
      descriptionConcurrency: 1
    }
  });
  const request = jsonRequest("/api/walkthroughs", {
    origin: { latitude: null, longitude: -87.6298 },
    destination: { latitude: 41.8826, longitude: -87.6226 }
  });
  const response = captureResponse();

  await handler(request, response);

  assert.equal(response.status, 400);
  assert.deepEqual(JSON.parse(response.body), {
    error: "origin must include valid latitude and longitude numbers."
  });
});

test("synthesizes TTS audio through Google WaveNet", async () => {
  const calls = [];
  const handler = createAppServer({
    config: {
      useMocks: false,
      publicBaseUrl: "http://localhost",
      googleTtsApiKey: "tts-key",
      googleTtsVoice: "en-US-Wavenet-F",
      googleTtsAudioEncoding: "MP3"
    },
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return {
        ok: true,
        status: 200,
        json: async () => ({ audioContent: Buffer.from("audio").toString("base64") })
      };
    }
  });
  const request = jsonRequest("/api/tts", {
    text: "Turn left at the corner.",
    language: "en-US"
  });
  const response = captureResponse();

  await handler(request, response);

  assert.equal(response.status, 200);
  assert.equal(response.headers["Content-Type"], "audio/mpeg");
  assert.equal(response.body, "audio");
  assert.match(calls[0].url, /texttospeech\.googleapis\.com/);
  const payload = JSON.parse(calls[0].options.body);
  assert.equal(payload.voice.name, "en-US-Wavenet-F");
  assert.equal(payload.voice.languageCode, "en-US");
  assert.equal(payload.audioConfig.audioEncoding, "MP3");
});

function jsonRequest(url, body) {
  const request = Readable.from([Buffer.from(JSON.stringify(body))]);
  request.method = "POST";
  request.url = url;
  request.headers = {
    host: "localhost",
    "content-type": "application/json"
  };
  return request;
}

function captureResponse() {
  return {
    status: null,
    headers: {},
    body: "",
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    writeHead(status, headers = {}) {
      this.status = status;
      Object.assign(this.headers, headers);
    },
    end(body = "") {
      this.body = Buffer.isBuffer(body) ? body.toString("utf8") : String(body);
    }
  };
}
