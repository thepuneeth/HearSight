import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const CONFIG_DIR = path.dirname(fileURLToPath(import.meta.url));
const BACKEND_DIR = path.resolve(CONFIG_DIR, "..");

export function loadDotEnv(filePath = path.join(BACKEND_DIR, ".env"), env = process.env) {
  if (!fs.existsSync(filePath)) return;

  const contents = fs.readFileSync(filePath, "utf8");
  for (const line of contents.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separatorIndex = trimmed.indexOf("=");
    if (separatorIndex === -1) continue;

    const key = trimmed.slice(0, separatorIndex).trim();
    const rawValue = trimmed.slice(separatorIndex + 1).trim();
    if (!key || Object.prototype.hasOwnProperty.call(env, key)) continue;

    env[key] = unquoteEnvValue(rawValue);
  }
}

export function loadConfig(env = process.env) {
  const port = Number(env.PORT || 8787);

  return {
    port,
    publicBaseUrl: env.PUBLIC_BASE_URL || `http://localhost:${port}`,
    googleMapsApiKey: env.GOOGLE_MAPS_API_KEY || "",
    mistralApiKey: env.MISTRAL_API_KEY || "",
    mistralModel: env.MISTRAL_MODEL || "mistral-medium-2505",
    useMocks: env.HEARSIGHT_USE_MOCKS === "true",
    maxStages: Number(env.MAX_STAGES || 12),
    checkpointSpacingMeters: Number(env.CHECKPOINT_SPACING_METERS || 120),
    descriptionConcurrency: Number(env.DESCRIPTION_CONCURRENCY || 5)
  };
}

function unquoteEnvValue(value) {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

export function requireRealApiConfig(config) {
  const missing = [];
  if (!config.googleMapsApiKey) missing.push("GOOGLE_MAPS_API_KEY");
  if (!config.mistralApiKey) missing.push("MISTRAL_API_KEY");
  return missing;
}
