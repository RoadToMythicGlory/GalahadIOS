# Galahad iOS Architecture

```text
Host SwiftUI app                    Broadcast Upload Extension
        │                                      │
 AVFoundation camera                     RPSampleHandler
 RPSystemBroadcastPickerView                   │
        │                                      │
        └──────── App Group config/status ─────┘
                         │
                 Shared MediaCore
                         │
                 Frame normalization
                         │
              VideoEncoder protocol
                    │
        ┌───────────┴────────────┐
        ▼                        ▼
  VideoToolbox HEVC         Stub (lab / DEBUG)
        │
        ▼
  MPEG-TS mux (GStreamer mpegtsmux in product)
        │
 SRT caller transport  ←── GStreamer srtsink + reconnect
        │                   (no FFmpeg)
        ▼
 Validation receiver (GStreamer srtsrc)

Independent control WebSocket ─── forever reconnect; media unaffected
```

## Layer ownership

| Layer | Responsibility | Must not own |
|-------|----------------|--------------|
| Capture | CMSampleBuffer / ReplayKit samples | Encode, mux, SRT |
| Normalize | Pixel format / scale / stride | Encoder vendor APIs |
| `VideoEncoder` | HEVC access units (VideoToolbox in product) | Mux, transport, UI |
| MPEG-TS mux | TS packaging | Reconnect |
| SRT transport | Caller connect/send/reconnect via GStreamer `srtsink` | Encoding |
| Coordinator | Wire layers + metrics | Become a GStreamer God Object |
| Control WebSocket | Commands / telemetry | Media send path |

## Process topology

- **Host app (`gg.galahad.ios`):** front/rear camera + native preview + camera pipeline + control channel + broadcast picker
- **Broadcast Upload Extension (`gg.galahad.ios.broadcast`):** independent screen capture + full Normalize → HEVC → Mux → GStreamer SRT pipeline (must not require host foreground)
- **App Group `group.gg.galahad.ios`:** shared `ClientConfig` + `StreamStatus`

## Encode + transport

- Video: **H.265 / HEVC** via `VideoToolboxHEVCEncoder` (`VTCompressionSession`)
- Quality: user-selectable presets `720p30` … `1080p60` (progressive only) with `hevcKbps` targets
- SRT **caller only** via GStreamer `srtsink` (`GStreamerSrtTransport`)
- `RecordingSrtTransport` is an in-memory test fake only
- FFmpeg is not used for encode, mux, or SRT
- JPEG XS / SVT is not used

## Out of scope

- ST 2110
- SRT listener / fan-out as a general mobile topology
- JPEG XS encode path
- 4K and ≤480p quality presets
- Windows-style per-app audio process picker on iOS
