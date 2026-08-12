# FeasibilityBenchmark

Phase 2 device harness only. **Not** the product Galahad UI.

## On macOS

```bash
cd ..
./Scripts/generate-xcodeproj.sh
open GalahadIOS.xcodeproj
```

Select a physical iPhone, build/run `FeasibilityBenchmark`.

Until `Vendor/GStreamer/GStreamer.xcframework` exists and plugins register on device, the app correctly reports **DEVICE VALIDATION REQUIRED**.

## Explicit non-goals

- ReplayKit broadcast extension
- Product identity / destination UX
- Control WebSocket
