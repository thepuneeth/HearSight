import { createGoogleMapsClient } from "./googleMapsClient.js";
import { createMistralDescriber } from "./mistralDescriber.js";
import { requireRealApiConfig } from "./config.js";
import { createWalkthrough, ValidationError } from "./walkthroughService.js";
import { isValidCoordinate } from "./geo.js";

const MAX_BODY_BYTES = 64 * 1024;

export function createAppServer({ config, fetchImpl = fetch }) {
  const googleMapsClient = createGoogleMapsClient({
    apiKey: config.googleMapsApiKey,
    fetchImpl
  });
  const describer = createMistralDescriber({
    apiKey: config.mistralApiKey,
    model: config.mistralModel,
    fetchImpl
  });

  return async function handleRequest(request, response) {
    try {
      await routeRequest({
        request,
        response,
        config,
        googleMapsClient,
        describer
      });
    } catch (error) {
      sendError(response, error);
    }
  };
}

async function routeRequest({ request, response, config, googleMapsClient, describer }) {
  const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);

  if (request.method === "OPTIONS") {
    writeCorsHeaders(response);
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    sendJson(response, 200, {
      ok: true,
      mockMode: config.useMocks,
      missingConfig: config.useMocks ? [] : requireRealApiConfig(config)
    });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/walkthroughs") {
    const missingConfig = config.useMocks ? [] : requireRealApiConfig(config);
    if (missingConfig.length) {
      sendJson(response, 503, {
        error: "Backend is missing required API configuration.",
        missingConfig
      });
      return;
    }

    const body = await readJsonBody(request);
    const walkthrough = await createWalkthrough({
      request: body,
      config,
      googleMapsClient,
      describer
    });
    sendJson(response, 200, walkthrough);
    return;
  }

  if (request.method === "GET" && url.pathname === "/api/streetview") {
    await proxyStreetView({ url, response, config, googleMapsClient });
    return;
  }

  sendJson(response, 404, { error: "Not found." });
}

async function proxyStreetView({ url, response, config, googleMapsClient }) {
  if (config.useMocks || !config.googleMapsApiKey) {
    sendJson(response, 503, { error: "Street View proxy requires GOOGLE_MAPS_API_KEY and real mode." });
    return;
  }

  const coordinate = {
    latitude: Number(url.searchParams.get("lat")),
    longitude: Number(url.searchParams.get("lng"))
  };
  const headingDegrees = Number(url.searchParams.get("heading") || 0);

  if (!isValidCoordinate(coordinate) || !Number.isFinite(headingDegrees)) {
    sendJson(response, 400, { error: "lat, lng, and heading query parameters are required." });
    return;
  }

  const image = await googleMapsClient.fetchStreetViewImage({ coordinate, headingDegrees });
  writeCorsHeaders(response);
  response.writeHead(200, {
    "Content-Type": image.contentType,
    "Cache-Control": "no-store"
  });
  response.end(image.bytes);
}

async function readJsonBody(request) {
  const chunks = [];
  let bytes = 0;

  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > MAX_BODY_BYTES) {
      throw Object.assign(new Error("Request body is too large."), { status: 413 });
    }
    chunks.push(chunk);
  }

  if (!chunks.length) return {};

  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new ValidationError("Request body must be valid JSON."), { status: 400 });
  }
}

function sendJson(response, status, payload) {
  writeCorsHeaders(response);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  response.end(JSON.stringify(payload, null, 2));
}

function sendError(response, error) {
  const status = error.status || (error instanceof ValidationError ? 400 : 500);
  sendJson(response, status, {
    error: error.message || "Unexpected server error."
  });
}

function writeCorsHeaders(response) {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type");
}
