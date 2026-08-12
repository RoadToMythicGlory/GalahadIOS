#!/usr/bin/env bash
# Run on macOS after installing FeasibilityBenchmark / Galahad on a physical iPhone.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "DEVICE VALIDATION REQUIRED"
  exit 2
fi

echo "Install Galahad (or FeasibilityBenchmark) on a physical arm64 iPhone, then:"
echo "  1. Launch the app"
echo "  2. Confirm VideoToolbox HEVC is available"
echo "  3. Confirm GStreamer plugin probe shows mpegtsmux + srtsink"
echo "  4. Run sustained tests for presets 720p30 … 1080p60"
echo "  5. Export JSON into docs/reports/"
echo "  6. Verify MPEG-TS/SRT with Tools/SrtReceiver and PacketizationCheck"
echo
echo "Do not mark product GO without physical-device evidence."
echo "DEVICE VALIDATION REQUIRED until then."
