# SRT validation receiver

Temporary desktop helper for Phase 2. Validates MPEG-TS over SRT from the iPhone (HEVC video).

## Preferred (Linux/macOS with GStreamer)

```bash
# Listen for MPEG-TS over SRT and dump to file + decode probe
gst-launch-1.0 \
  srtsrc uri="srt://0.0.0.0:9001?mode=listener&latency=200" ! \
  tee name=t \
  t. ! queue ! filesink location=received.ts \
  t. ! queue ! tsdemux ! h265parse ! avdec_h265 ! videoconvert ! autovideosink
```

If a HEVC decoder element is unavailable, still capture the TS:

```bash
gst-launch-1.0 \
  srtsrc uri="srt://0.0.0.0:9001?mode=listener&latency=200" ! \
  filesink location=received.ts
```

Then inspect:

```bash
ffprobe -hide_banner received.ts
python ../PacketizationCheck/check_pcap_or_sizes.py --sizes-json observed_sizes.json
```

## Notes

- Galahad iPhone is always **SRT caller**.
- Video codec is **H.265 / HEVC** (VideoToolbox on device).
- Receiver is listener **only for lab validation**.
- Configure packetization for 1316-byte payloads where supported and **verify** with `PacketizationCheck`.
- Do not use FFmpeg as the product send path; `ffprobe` here is inspection-only.
