#!/usr/bin/env bash
# Build a minimal custom GStreamer iOS XCFramework for Galahad (mux + SRT).
# Video encode is VideoToolbox HEVC outside GStreamer.
# MUST run on macOS with Xcode. Do not invent success from CI on Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/Vendor/GStreamer"
WORK="$ROOT/.build/gstreamer-ios"
RECIPE_LOCK="$ROOT/third_party/deps.lock"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "ERROR: build-gstreamer-ios.sh requires macOS + Xcode."
  echo "DEVICE VALIDATION REQUIRED"
  exit 2
fi

mkdir -p "$OUT" "$WORK"

cat <<EOF
Galahad GStreamer iOS recipe
============================
Output:  $OUT/GStreamer.xcframework
Work:    $WORK
Lock:    $RECIPE_LOCK

Required plugins / elements (egress only — no video encode plugin):
  - coreelements, app (appsrc)
  - videoconvert, videoscale (optional lab helpers)
  - mpegtsmux
  - srt (srtsink)
  - audioconvert, atenc (AAC)

Video encode: VideoToolbox HEVC in Swift (not packaged here).

This script documents and prepares the build. The first successful Mac run
must pin exact Cerbero revisions into third_party/deps.lock.

Steps (operator):
  1. Install Xcode + command line tools
  2. Clone GStreamer cerbero matching the pinned revision
  3. Enable mpegtsmux + SRT (+ applemedia AAC) in the iOS package recipe
  4. Produce GStreamer.xcframework into Vendor/GStreamer
  5. Run Scripts/probe-plugins-ios.sh on a physical device
EOF

# Placeholder marker so CI can detect missing framework without claiming success.
cat > "$OUT/README.md" <<'EOF'
# Vendor/GStreamer

Place the custom `GStreamer.xcframework` produced by `Scripts/build-gstreamer-ios.sh` here.

Until that artifact exists and plugin registration is proven on arm64 iPhone,
mux/SRT device validation remains **DEVICE VALIDATION REQUIRED**.
EOF

if [[ ! -d "$OUT/GStreamer.xcframework" ]]; then
  echo
  echo "GStreamer.xcframework not present."
  echo "DEVICE VALIDATION REQUIRED"
  exit 3
fi

echo "Found GStreamer.xcframework — continue with device probe."
