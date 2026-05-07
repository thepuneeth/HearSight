import http from "node:http";
import { loadConfig, loadDotEnv } from "./config.js";
import { createAppServer } from "./server.js";

loadDotEnv();
const config = loadConfig();
const server = http.createServer(createAppServer({ config }));

server.listen(config.port, () => {
  console.log(`HearSight backend listening on ${config.publicBaseUrl}`);
  if (config.useMocks) {
    console.log("Mock mode is enabled; Google/Mistral APIs will not be called.");
  }
});
