#!/usr/bin/env bash
# Fetch the official prebuilt GStreamer iOS xcframework into Vendor/GStreamer.
#
# Used by CI (Codemagic / GitHub Actions) and local macOS builds before
# `xcodegen generate` + `xcodebuild`. The version and checksum are pinned in
# third_party/deps.lock — keep them in sync when bumping.
#
# The xcframework's merged static archive contains every GStreamer plugin,
# including srt (srtsink). Only the plugins registered in
# GStreamerBridge/src/gst_ios_init.m end up in the linked binary.
set -euo pipefail

VERSION="1.28.6"
SHA256="48437f2a8f17bc1de40097eec9aedc0d307a30c15d9e996bf75bc07562bd79a5"
URL="https://gstreamer.freedesktop.org/data/pkg/ios/${VERSION}/gstreamer-${VERSION}-xcframework.tar.xz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/GStreamer"
MARKER="$DEST/.gstreamer-version"

if [[ -d "$DEST/GStreamer.xcframework" && -f "$MARKER" && "$(cat "$MARKER")" == "$VERSION" ]]; then
  echo "GStreamer.xcframework $VERSION already present — skipping download."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ARCHIVE="$WORK/gstreamer-${VERSION}-xcframework.tar.xz"
echo "Downloading GStreamer iOS xcframework ${VERSION} (~1.1 GB)…"
curl --fail --location --retry 3 --output "$ARCHIVE" "$URL"

echo "${SHA256}  ${ARCHIVE}" | shasum -a 256 -c -

echo "Extracting…"
tar -xJf "$ARCHIVE" -C "$WORK"

FOUND="$(find "$WORK" -maxdepth 3 -name "GStreamer.xcframework" -type d | head -n 1)"
if [[ -z "$FOUND" ]]; then
  echo "ERROR: GStreamer.xcframework not found in archive." >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$DEST/GStreamer.xcframework"
mv "$FOUND" "$DEST/GStreamer.xcframework"
echo "$VERSION" > "$MARKER"

echo "GStreamer.xcframework $VERSION installed into Vendor/GStreamer."
