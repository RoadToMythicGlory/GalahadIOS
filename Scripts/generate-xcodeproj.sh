#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Xcode project generation requires macOS."
  echo "On Mac: brew install xcodegen && ./Scripts/generate-xcodeproj.sh"
  exit 2
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing tip: brew install xcodegen"
  exit 3
fi

xcodegen generate --spec project.yml
echo "Generated GalahadIOS.xcodeproj"
echo "Open with: open GalahadIOS.xcodeproj"
