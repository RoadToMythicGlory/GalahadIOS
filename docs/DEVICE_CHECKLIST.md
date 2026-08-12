# Device verification checklist

Run on Mac + physical iPhone when available. Do not invent results on Windows.

## Sources

- [ ] Rear camera start/stop
- [ ] Front camera start/stop
- [ ] Switch camera (clean restart)
- [ ] Screen share via system broadcast picker
- [ ] Extension continues when host backgrounds

## Audio

- [ ] Mic on camera path
- [ ] App audio + mic on screen path
- [ ] Mute / gain toggles reflected in mix (when AAC path live)

## Resilience

- [ ] Orientation changes
- [ ] Audio session interruptions (phone call)
- [ ] Network blip → SRT reconnect (transport-owned; GStreamer `srtsink`)
- [ ] Thermal pressure reflected in status
- [ ] 30+ minute sustained session

## Encode + egress

- [ ] VideoToolbox HEVC available; selected preset applies (`hevcKbps`)
- [ ] MPEG-TS with HEVC decodable at receiver
- [ ] SRT via GStreamer `srtsrc` listener (see `Tools/SrtReceiver/README.md`)
- [ ] Observed payload sizes prefer 1316 bytes
- [ ] End-to-end latency recorded (no fabricated numbers)
- [ ] No FFmpeg / no JPEG XS on the send path

## Control

- [ ] Hello + 1 Hz telemetry
- [ ] stop_stream / push_config / switch_quality
- [ ] Screen start_stream → `user_action_required`
- [ ] Control disconnect does not stop media; media stop does not stop control reconnect
