# Phase 2 — HEVC sustainment gate

## Goal

Discover what a real iPhone can sustain with **VideoToolbox H.265 → MPEG-TS → GStreamer SRT caller**.

This gate is **not** "force 1080p60 to succeed".

## Required evidence checklist

- [ ] arm64 iOS build of Galahad / FeasibilityBenchmark + GStreamer XCFramework (mux/SRT)
- [ ] VideoToolbox HEVC encode available on device
- [ ] Static GStreamer plugin registration on device (`mpegtsmux`, `srtsink`, …)
- [ ] Negotiated pixel formats + normalization cost
- [ ] 720p30 sustained run (≥30 min)
- [ ] 1080p30 sustained run (≥30 min)
- [ ] 1080p60 sustained run (≥30 min)
- [ ] Optional: 1080p50 / 1080p60 if operator-required (interlaced removed: VideoToolbox HEVC is progressive-only)
- [ ] Sustained FPS / CPU / memory / thermal / power
- [ ] HEVC bitrate vs preset `hevcKbps` + encoder latency
- [ ] End-to-end Capture → Encode → Mux → SRT → Receiver latency
- [ ] MPEG-TS validation (HEVC decode / probe)
- [ ] SRT delivery validation
- [ ] Observed packetization verification (prefer 1316-byte payloads)
- [ ] Licensing / deployment blockers listed

## Classification

For each profile:

| Class | Meaning |
|-------|---------|
| `SUPPORTED` | Passes sustained-run criteria on the declared device class |
| `UNSUPPORTED` | Test completed but failed criteria |
| `DEVICE-SPECIFIC` | Passes only on named models; GO needs explicit allow-list |
| `INCONCLUSIVE` | Incomplete / unreproducible evidence |
| `NOT TESTED` | Not yet run |

## Sustained-run pass bar

- ≥30 continuous minutes
- ≥99% of expected frames after warm-up; no progressive frame-loss growth
- No crash / OOM / stall; end memory within 10% of post-warm-up baseline
- Never critical thermal; serious thermal must not break real-time criterion
- Decodable MPEG-TS (HEVC) + successful SRT delivery + recorded latencies/metrics

## GO / NO-GO

- **GO:** ≥1 useful profile (`720p30` or higher in catalog) is `SUPPORTED`
- **NO-GO:** VideoToolbox HEVC / mux / SRT path not viable; or no useful SUPPORTED profile
- **DEVICE VALIDATION REQUIRED:** no Mac + physical iPhone evidence (current Windows scaffold)

JPEG XS is out of scope for this product.
