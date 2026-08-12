#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift toolchain not found."
  echo "On Windows scaffold hosts, unit tests run on macOS CI / local Mac."
  exit 2
fi

swift test --package-path "$ROOT"
