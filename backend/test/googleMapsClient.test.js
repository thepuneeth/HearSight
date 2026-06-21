import test from "node:test";
import assert from "node:assert/strict";
import { resolveDestinationText } from "../src/googleMapsClient.js";

test("destination text resolver prefers the candidate matching typed street and state", async () => {
  let capturedRequest = null;
  const destination = await resolveDestinationText({
    destinationText: "Walmart on Mallory Lane in TN",
    origin: { latitude: 36.1627, longitude: -86.7816 },
    apiKey: "test-key",
    fetchImpl: async (url, request) => {
      assert.match(url, /places:searchText/);
      capturedRequest = JSON.parse(request.body);

      return Response.json({
        places: [
          {
            id: "nearby-walmart",
            displayName: { text: "Walmart Supercenter" },
            formattedAddress: "2421 Powell Ave, Nashville, TN 37204",
            location: { latitude: 36.1262, longitude: -86.7673 },
            types: ["department_store", "store"]
          },
          {
            id: "mallory-lane-walmart",
            displayName: { text: "Walmart Supercenter" },
            formattedAddress: "3600 Mallory Ln, Franklin, TN 37067",
            location: { latitude: 35.9532, longitude: -86.8151 },
            types: ["department_store", "store"]
          }
        ]
      });
    }
  });

  assert.equal(capturedRequest.maxResultCount, 8);
  assert.equal(destination.placeId, "mallory-lane-walmart");
  assert.equal(destination.name, "Walmart Supercenter");
  assert.equal(destination.formattedAddress, "3600 Mallory Ln, Franklin, TN 37067");
  assert.equal(destination.confidence, "high");
});

