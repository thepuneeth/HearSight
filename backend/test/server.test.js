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
