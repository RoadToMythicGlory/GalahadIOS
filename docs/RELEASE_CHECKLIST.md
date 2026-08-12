# Release checklist

## Signing & targets

- [ ] XcodeGen: `./Scripts/generate-xcodeproj.sh`
- [ ] App ID `gg.galahad.ios` + App Group `group.gg.galahad.ios`
- [ ] Extension ID `gg.galahad.ios.broadcast` in same App Group
- [ ] Host embeds Broadcast Upload Extension
- [ ] Distribution cert / provisioning for app + extension
      (via Codemagic: App Store Connect integration `galahad_asc` +
      `ios_signing` in `codemagic.yaml` handles both bundle IDs; tag `v*`
      builds publish to TestFlight)

## Privacy strings

- [ ] `NSCameraUsageDescription`
- [ ] `NSMicrophoneUsageDescription`
- [ ] `NSLocalNetworkUsageDescription` (SRT caller)

## Media stack

- [ ] VideoToolbox HEVC encode probed OK on device
- [ ] Vendor GStreamer XCFramework linked (`Scripts/build-gstreamer-ios.sh`) for SRT egress; pin SHAs in `third_party/deps.lock`
- [ ] Static plugins include `srt` (plus `mpegtsmux`, `videoparsersbad` for the lab A/B graph — product mux is MediaCore `MpegTsStreamMuxer`)
- [ ] Probe reports `has_srtsink == true` on device
- [ ] MPEG-TS output validated against a real receiver/decoder (ffprobe/VLC via `Tools/SrtReceiver`)
- [ ] AAC audio present and in sync (camera mic path + broadcast app-audio path)
- [ ] No FFmpeg dependency in app or extension
- [ ] NOTICE / license inventory updated (`third_party/licenses/NOTICE.md`) from the actual framework build

## Product gates

- [ ] At least one HEVC preset classified `SUPPORTED` on device (Phase 2 evidence)
- [ ] UI quality picker offers only catalog presets (720p30 … 1080p60, progressive only)
- [ ] UI does not offer unvalidated presets as production-startable
- [ ] FeasibilityBenchmark remains a separate lab scheme (not the store UI)

## App Store metadata

- [ ] App icon present (`Galahad/Galahad/Assets.xcassets/AppIcon.appiconset`, 1024 px universal)
- [ ] Marketing version / build number bumped for the release
- [ ] Privacy "nutrition label" answers (camera, microphone, no tracking)
- [ ] Export-compliance answer (uses standard encryption: HTTPS/WSS + SRT passphrase support)
- [ ] `UIBackgroundModes: audio` justification prepared for review: live contribution
      encoder must keep mic capture + SRT egress alive when backgrounded mid-stream

## TestFlight

- [ ] Internal build of **Galahad** scheme
- [ ] Verify camera start/stop, screen broadcast sheet, control WebSocket reconnect
- [ ] 30+ minute soak on a supported preset (thermal + battery telemetry recorded)
