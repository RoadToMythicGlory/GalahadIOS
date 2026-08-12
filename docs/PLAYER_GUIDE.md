# Galahad iOS Player Guide

## First launch

1. Open **Galahad** (not FeasibilityBenchmark).
2. On **Setup**, set display name, SRT destination host/port, and latency (200 or 400 ms).
3. Choose source: front camera, rear camera, or screen.
4. Pick an H.265 quality preset (720p30 … 1080p60). Labels marked `(lab)` are DEBUG/stub-only until device validation marks them production-startable.
5. Toggle microphone / app audio as needed.
6. Optionally set a control WebSocket URL.
7. Tap **Save**.

## Camera streaming

1. Open **Live**.
2. Tap **Start**. Preview uses the native camera layer.
3. Use **Switch camera** for a clean pipeline restart to the other lens.
4. Tap **Stop** to tear down encode/mux/transport.

## Screen streaming

1. On Setup, select **Screen**, save destination/preset.
2. On Live, tap the system broadcast control (red record glyph).
3. Confirm **Galahad Broadcast** in Apple’s sheet.
4. The upload extension reads App Group config and runs the full media pipeline itself.

## Diagnostics

- **Diagnostics** shows `playerId`, `sessionId`, control state, last error, and recent logs.
- **Copy diagnostics** places a text snapshot on the pasteboard for support.

## Control channel

When a control URL is configured, the app reconnects forever independently of media.
Remote **start/restart** for screen returns `user_action_required` — you must still confirm the broadcast sheet.
