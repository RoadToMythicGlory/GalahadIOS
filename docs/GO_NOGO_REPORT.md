# Phase 2 GO / NO-GO Report

**Report version:** phase2-v2-hevc  
**Verdict:** `DEVICE VALIDATION REQUIRED`  
**Generated on scaffold host:** Windows x86_64 (no Xcode, no physical iPhone)

## Executive summary

Phase 1 scaffold and product media contracts are in place under `GalahadIOS`.  
Encode path is **VideoToolbox H.265**; GStreamer is **mux + SRT only**.  
No arm64 iOS binary, GStreamer plugin registration, sustained HEVC run, MPEG-TS validation, or SRT packetization verification was executed on a physical iPhone in this environment.

Per plan rules: **do not invent measurements**.  
Therefore the gate verdict is:

```text
DEVICE VALIDATION REQUIRED
```

This is **not** GO.

## Evidence matrix

| Item | Result |
|------|--------|
| arm64 iOS build | NOT EXECUTED |
| VideoToolbox HEVC | NOT EXECUTED on device |
| GStreamer mux/SRT plugin registration | NOT EXECUTED |
| Pixel formats | Declared candidates only (`bgra`, `nv12`, `i420`, `yuy2`, `i422_10le`) |
| 720p30 | `INCONCLUSIVE` |
| 1080p30 | `INCONCLUSIVE` |
| 1080p60 | `INCONCLUSIVE` |
| 1080p50 | `NOT TESTED` |
| Sustained FPS / CPU / memory / thermal / power | NOT MEASURED |
| HEVC bitrate | NOT MEASURED |
| Encoder latency | NOT MEASURED |
| End-to-end latency | NOT MEASURED |
| MPEG-TS validation | NOT EXECUTED |
| SRT validation | NOT EXECUTED |
| 1316-byte packetization verification | NOT VERIFIED (no observed packets) |
| Licensing / deployment blockers | Listed in JSON report |

## Viable profiles

_None. `viableProfiles: []`_

## Machine-readable artifact

See latest JSON:

- [`docs/reports/PHASE2_LATEST.json`](reports/PHASE2_LATEST.json)

Regenerate on this host:

```powershell
python Scripts\emit-device-validation-report.py
```

## Code-complete addendum (2026-08-12)

The egress path is now **fully implemented in code** (previously stubs):

- `MediaCore/MpegTsStreamMuxer` — real MPEG-TS (PAT/PMT + CRC32, PES/PTS, PCR,
  continuity counters, HEVC + ADTS AAC, 1316-aligned output), unit-tested.
- `Shared/Encoders/AACAudioEncoder` — AAC-LC/ADTS audio chain, wired into the
  camera mic path and the broadcast `.audioApp`/`.audioMic` path.
- `GStreamerBridge/GalahadGSTBridge.mm` — complete `appsrc ! srtsink` element
  graph, plugin probe, buffer push, and payload-size observation behind
  `GALAHAD_HAS_GSTREAMER` (activates when the XCFramework is linked).

Verified off-device (Linux Swift 5.10 container, 2026-08-12):

- **First-ever compile of MediaCore** — clean (the compile surfaced and fixed
  two latent errors: actor transports could not satisfy the nonisolated
  `isConnected`/`isReconnecting` protocol requirements, and `AppGroupStore`
  used a Darwin-only API unguarded).
- **All 27 unit tests pass** (`swift test`), including 8 new `MpegTsStreamMuxer`
  tests and the layered pipeline test which now verifies 1316-byte packetization
  through the production muxer.
- **ffprobe demuxes the muxer output correctly**: Program 1, PMT PID 0x1000,
  PCR PID 0x0100, HEVC on 0x100, AAC on 0x101, monotonic PES timestamps
  (`swift run galahad-ts-dump` + ffprobe).

None of this changes the verdict: it has still never been compiled for or run
on a physical iPhone (VideoToolbox/AVFoundation/ReplayKit/bridge code needs
Xcode), and `viableProfiles` remains empty until Phase 2 evidence exists. The
gate stays honest.

## Next actions for a real GO attempt

1. Move the repo to a Mac with Xcode.
2. `./Scripts/generate-xcodeproj.sh`
3. Build custom GStreamer XCFramework via `./Scripts/build-gstreamer-ios.sh` (SRT egress) and pin SHAs in `third_party/deps.lock`.
4. Deploy `Galahad` / `FeasibilityBenchmark` to a physical iPhone.
5. Prove VideoToolbox HEVC + plugin registration (`srtsink`; `mpegtsmux`/`h265parse` for the lab A/B graph).
6. Run 30-minute sustained tests for catalog presets (start with 720p30 / 1080p30 / 1080p60).
7. Verify MPEG-TS (HEVC + AAC) against a real decoder + SRT + observed packetization with `Tools/`.
8. Replace this report with measured classifications and an explicit GO or NO-GO.

## Authorization stop

Work stops here pending user review of the gate report.
