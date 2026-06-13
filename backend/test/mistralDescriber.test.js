import test from "node:test";
import assert from "node:assert/strict";
import { describeImage } from "../src/mistralDescriber.js";

test("sends Street View images to Mistral chat completions with JSON schema output", async () => {
  let capturedUrl = null;
  let capturedRequest = null;

  const description = await describeImage({
    imageBytes: Buffer.from("fake image"),
    contentType: "image/jpeg",
    apiKey: "test-key",
    model: "mistral-medium-2505",
    stage: {
      index: 0,
      routeDistanceMeters: 0,
      routeInstruction: "Walk north.",
      headingDegrees: 0
    },
    streetViewMetadata: { date: "2025-01" },
    fetchImpl: async (url, request) => {
      capturedUrl = url;
      capturedRequest = JSON.parse(request.body);

      return Response.json({
        choices: [{
          message: {
            content: JSON.stringify({
              spokenCue: "Street View suggests a storefront ahead. Image may be outdated.",
              landmarks: ["storefront"],
              crossingOrIntersectionNotes: [],
              uncertainties: ["image may be outdated"],
              confidence: 0.7
            })
          }
        }]
      });
    }
  });

  assert.equal(capturedUrl, "https://api.mistral.ai/v1/chat/completions");
  assert.equal(capturedRequest.model, "mistral-medium-2505");
  assert.equal(capturedRequest.response_format.type, "json_schema");
  assert.match(capturedRequest.messages[0].content, /2-3 sentences/);
  assert.match(capturedRequest.messages[0].content, /not live safety guidance/i);
  assert.doesNotMatch(capturedRequest.messages[0].content, /image may be outdated/i);
  assert.match(capturedRequest.messages[1].content[0].text, /2-3 sentences/);
  assert.match(capturedRequest.messages[1].content[0].text, /sensory or surface cue/);
  assert.equal(capturedRequest.messages[1].content[1].type, "image_url");
  assert.match(capturedRequest.messages[1].content[1].image_url, /^data:image\/jpeg;base64,/);
  assert.equal(description.confidence, 0.7);
  assert.deepEqual(description.landmarks, ["storefront"]);
  assert.equal(description.spokenCue, "Street View suggests a storefront ahead.");
  assert.deepEqual(description.uncertainties, []);
});
