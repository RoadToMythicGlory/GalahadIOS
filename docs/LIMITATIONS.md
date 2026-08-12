# Limitations

- Phase 2 physical-device HEVC sustainment evidence is still pending; production presets stay capability-gated until measured. **Nothing in this repo has been compiled or run on an iPhone yet** — the macOS CI jobs (`swift test` + unsigned `xcodebuild`) verify compilation, not device behavior.
- The GStreamer iOS xcframework (official prebuilt 1.28.6, pinned in `third_party/deps.lock`) is fetched by `Scripts/fetch-gstreamer-ios.sh` on CI and local macOS builds; `GALAHAD_HAS_GSTREAMER` is defined in `project.yml`. The runtime probe (`has_srtsink`) still gates streaming: presets unlock only when the device proves hardware HEVC **and** a registered `srtsink` at bootstrap.
- `StubHEVCEncoder` cannot produce product GO; product encode requires VideoToolbox HEVC on device.
- GStreamer is used for **SRT egress only**. Video encode is VideoToolbox; MPEG-TS mux is MediaCore's `MpegTsStreamMuxer` (pure Swift, unit-tested).
- GStreamer `srtsink` must be present (`has_srtsink`) for production SRT. There is no FFmpeg fallback.
- Audio: single AAC-LC stream in the TS (PID 0x0101). The broadcast extension has **no audio mixer** yet — when both app audio and mic are enabled, app audio wins and mic is dropped. Per-channel `gain` from `AudioConfig` is not yet applied (mute/enable are honored).
- Screen capture always requires Apple's `RPSystemBroadcastPickerView` confirmation — no remote bypass.
- Protected content may render blank and/or silent in ReplayKit; this is an OS restriction.
- iOS has no Windows-style per-app audio process picker; screen path uses `.audioApp` / `.audioMic` sample types only.
- SRT listener/fan-out is out of scope.
- Quality catalog is mobile-oriented: **720p30 through 1080p60** — no ≤480p, no 4K. Interlaced presets (1080i50/i60) were removed: VideoToolbox HEVC cannot produce true interlaced output, so offering them would silently deliver progressive frames. Re-scope against receiver requirements if interlacing ever becomes a hard requirement.
- `UIBackgroundModes: audio` is declared to keep mic capture + SRT egress alive when the host app is backgrounded mid-stream; App Review may ask for this justification (see docs/RELEASE_CHECKLIST.md).
