# HearSight

HearSight is a personal iOS prototype for route familiarity. It generates a walking route, samples that route into ordered stages, pulls Street View snapshots for those stages, asks Mistral for cautious image descriptions, and speaks those descriptions as the user approaches each stage.

This is not a mobility aid replacement. It does not verify traffic, construction, sidewalk access, curb ramps, obstacles, or whether it is safe to cross.

## Structure

- `backend/` - Node backend that protects API keys and exposes `POST /api/walkthroughs`.
- `ios/` - SwiftUI iOS prototype with CoreLocation progress tracking and AVSpeechSynthesizer speech.

## Backend Setup

```sh
cd backend
cp .env.example .env
```

Fill in:

```sh
GOOGLE_MAPS_API_KEY=...
MISTRAL_API_KEY=...
MISTRAL_MODEL=mistral-medium-2505
```

Enable and allow these Google APIs on the backend key:

- Routes API
- Street View Static API
- Places API (New)
- Geocoding API

Run real mode:

```sh
node src/index.js
```

Run mock mode for simulator/UI testing without external services:

```sh
HEARSIGHT_USE_MOCKS=true node src/index.js
```

Health check:

```sh
curl http://localhost:8787/health
```

Example walkthrough request:

```sh
curl -X POST http://localhost:8787/api/walkthroughs \
  -H 'Content-Type: application/json' \
  -d '{
    "origin": { "latitude": 41.8781, "longitude": -87.6298 },
    "destinationText": "Millennium Park Chicago",
    "language": "en-US"
  }'
```

## iOS Setup

Open `ios/HearSight.xcodeproj` in Xcode.

The app defaults to `http://127.0.0.1:8787`, which works for the iOS simulator. On a physical iPhone, replace that field in the app with the Mac's local network address, for example `http://192.168.1.10:8787`.

The app uses:

- Google Places and Geocoding through the backend for destination entry.
- CoreLocation for live location and heading.
- AVSpeechSynthesizer for spoken cues.
- VoiceOver labels, Dynamic Type text, large controls, and haptic feedback.

## Tests

```sh
cd backend
npm test
```

The backend tests cover polyline decoding, route checkpoint generation, coordinate math, destination resolution, Street View fallback handling, request validation, mock walkthroughs, and unsafe phrase sanitization.

## Prototype Limits

- Street View can be missing or outdated. When imagery is unavailable, HearSight speaks a clean route-instruction fallback instead of raw API status text.
- Google walking routes may miss pedestrian-only paths or sidewalk constraints.
- Mistral image descriptions can be wrong, incomplete, or overly confident.
- The app speaks route stages in order; it intentionally does not decide when it is safe to cross.
