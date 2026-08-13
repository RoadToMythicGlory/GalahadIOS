# Galahad iOS

[![CI](https://github.com/RoadToMythicGlory/GalahadIOS/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/RoadToMythicGlory/GalahadIOS/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.5-0A84FF)](https://github.com/RoadToMythicGlory/GalahadIOS/releases/tag/v1.0.5)
[![iOS](https://img.shields.io/badge/iOS-17%2B-000000?logo=apple&logoColor=white)](#build)
[![Swift](https://img.shields.io/badge/Swift-5.10-F05138?logo=swift&logoColor=white)](Package.swift)
[![License](https://img.shields.io/badge/license-Proprietary-6E6E73)](LICENSE)

Native iPhone live contribution encoder for Galahad / Sport 5 workflows.

Capture → normalize → **VideoToolbox H.265** → **MPEG-TS** → **GStreamer SRT (caller)** — with an independent control WebSocket and a ReplayKit Broadcast Upload Extension for screen share.

| | |
|---|---|
| **Platform** | iOS 17+, iPhone |
| **Version** | [1.0.5](https://github.com/RoadToMythicGlory/GalahadIOS/releases/tag/v1.0.5) |
| **Bundle IDs** | `gg.galahad.ios` · `gg.galahad.ios.broadcast` |
| **CI** | [GitHub Actions](https://github.com/RoadToMythicGlory/GalahadIOS/actions/workflows/ci.yml) (push / PR) · [Codemagic](codemagic.yaml) (TestFlight on `v*` tags) |
| **Ship gate** | Device validation required — see [docs/GO_NOGO_REPORT.md](docs/GO_NOGO_REPORT.md) |

---

## Features

- **Camera** — front/rear AVFoundation capture, preview, orientation, interruptions
- **Screen** — ReplayKit upload extension with its own full encode → mux → SRT pipeline
- **Video** — hardware HEVC (VideoToolbox), presets 720p30 … 1080p60
- **Audio** — AAC-LC / ADTS (mic + app audio paths)
- **Mux** — production MPEG-TS (`MpegTsStreamMuxer`: PAT/PMT, PES, PTS/PCR, continuity)
- **Transport** — SRT caller via GStreamer `srtsink`, transport-owned reconnect
- **Control** — independent WebSocket (hello / telemetry / commands / log upload)
- **Gating** — production start blocked until a preset is device-validated and `srtsink` is present

## Repository layout

```text
Galahad/                 Product SwiftUI host app
GalahadBroadcast/        ReplayKit Broadcast Upload Extension
MediaCore/               Shared models, coordinator, muxer, control, tests
Shared/Encoders/         VideoToolbox HEVC + AAC encoders
GStreamerBridge/         ObjC++ appsrc → srtsink bridge
FeasibilityBenchmark/    Lab harness (Phase 2 evidence; not the store UI)
Scripts/                 XcodeGen, GStreamer build, probes
Tools/                   SRT receiver notes, packetization check, TS dump
docs/                    Architecture, player guide, checklists, gate reports
Vendor/GStreamer/        Place XCFramework here after Cerbero build
codemagic.yaml           Codemagic workflows (tests, iOS build, TestFlight)
```

## Architecture (summary)

```text
SwiftUI host ──► Camera (AVFoundation)
       │              │
       │              ▼
       │         MediaCore: normalize → HEVC → MpegTsStreamMuxer → SRT
       │
       ├──► Control WebSocket (independent of media)
       └──► App Group ◄──► Broadcast Upload Extension
                              (own normalize → encode → mux → SRT)
```

Hard constraints: VideoToolbox HEVC only · SRT caller only · no FFmpeg · no ST 2110 · reconnect only in the transport layer. Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Build

### Codemagic (recommended)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `swift-tests` | push / PR | Native `swift test` on macOS |
| `ios-build` | push / PR | XcodeGen + unsigned arm64 compile of app + extension |
| `ios-testflight` | tag `v*` | Signed IPA → TestFlight |

**TestFlight one-time setup:** Codemagic App Store Connect integration named `galahad_asc`; register both bundle IDs with App Group `group.gg.galahad.ios`.

### Local Mac

```bash
brew install xcodegen
./Scripts/generate-xcodeproj.sh
./Scripts/build-gstreamer-ios.sh   # produces Vendor/GStreamer XCFramework
swift test
open GalahadIOS.xcodeproj          # scheme: Galahad
```

### Scaffold / Linux (MediaCore only)

```bash
docker run --rm -v "${PWD}:/src" -w /src swift:5.10-jammy \
  swift test --scratch-path /tmp/build
```

## Documentation

| Doc | Purpose |
|-----|---------|
| [docs/PLAYER_GUIDE.md](docs/PLAYER_GUIDE.md) | Operator / player setup |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Layering and contracts |
| [docs/DEVICE_CHECKLIST.md](docs/DEVICE_CHECKLIST.md) | Physical iPhone validation |
| [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) | Signing, privacy, TestFlight |
| [docs/LIMITATIONS.md](docs/LIMITATIONS.md) | Known gaps and honest constraints |
| [docs/GO_NOGO_REPORT.md](docs/GO_NOGO_REPORT.md) | Phase 2 gate status |
| [third_party/licenses/NOTICE.md](third_party/licenses/NOTICE.md) | Third-party notices |

## Production readiness

MediaCore, muxer, encoders, UI, control plane, and the GStreamer bridge **implementation** are in tree. Shipping still requires:

1. GStreamer iOS XCFramework built and linked (`Vendor/GStreamer`)
2. Phase 2 sustainment evidence on a physical iPhone (≥1 preset `SUPPORTED`)
3. Signing, App Store metadata, and TestFlight soak

Until then, release builds refuse production start — by design. See the GO/NO-GO report.

## License

Proprietary. © Galahad / Sport 5. All rights reserved. See [LICENSE](LICENSE).
Third-party components: [NOTICE](third_party/licenses/NOTICE.md).
