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

# 1.28.9 fixes CVE-2026-119610 (GStreamer SA-2026-0095, rtph264depay OOB read).
# Do not go below 1.28.9.
VERSION="1.28.9"
# Pinned checksum. Empty = not pinned yet: the script then verifies against the
# official .sha256sum published next to the archive and prints the hash so it
# can be pinned here and in third_party/deps.lock.
SHA256=""
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

UPSTREAM_SUM="$(curl --fail --location --retry 3 "${URL}.sha256sum" | awk '{print $1}')"
if [[ ! "$UPSTREAM_SUM" =~ ^[0-9a-f]{64}$ ]]; then
  echo "ERROR: could not read upstream checksum from ${URL}.sha256sum" >&2
  exit 1
fi
if [[ -n "$SHA256" && "$SHA256" != "$UPSTREAM_SUM" ]]; then
  echo "ERROR: pinned SHA256 does not match upstream .sha256sum" >&2
  exit 1
fi
echo "${SHA256:-$UPSTREAM_SUM}  ${ARCHIVE}" | shasum -a 256 -c -
if [[ -z "$SHA256" ]]; then
  echo "NOTE: SHA256 not pinned. Pin this value in Scripts/fetch-gstreamer-ios.sh and third_party/deps.lock:"
  echo "      $UPSTREAM_SUM"
fi

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
