#!/usr/bin/env python3
"""Emit Phase 2 DEVICE VALIDATION REQUIRED report without inventing measurements."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "docs" / "reports"


def main() -> None:
    now = datetime.now(timezone.utc)
    # Align with QualityPreset.catalog (720p30 … 1080p60, progressive only)
    catalog = ["720p30", "1080p30", "1080p50", "1080p60"]
    primary = ["720p30", "1080p30", "1080p60"]
    secondary = [pid for pid in catalog if pid not in primary]

    profile_results = [
        {
            "profileID": pid,
            "deviceModel": "none",
            "classification": "INCONCLUSIVE",
            "durationSeconds": 0,
            "expectedFramesAfterWarmup": 0,
            "deliveredFramesAfterWarmup": 0,
            "frameDeliveryRatio": 0,
            "measuredFps": 0,
            "cpuPercentAverage": 0,
            "memoryBytesBaseline": 0,
            "memoryBytesEnd": 0,
            "memoryGrowthRatio": 0,
            "peakThermal": "nominal",
            "bitrateMbps": 0,
            "encoderLatencyMs": 0,
            "endToEndLatencyMs": 0,
            "mpegTsDecodable": False,
            "srtDelivered": False,
            "packetizationVerified": False,
            "notes": "Not executed on a physical iPhone. DEVICE VALIDATION REQUIRED.",
        }
        for pid in primary
    ] + [
        {
            "profileID": pid,
            "deviceModel": "none",
            "classification": "NOT TESTED",
            "durationSeconds": 0,
            "expectedFramesAfterWarmup": 0,
            "deliveredFramesAfterWarmup": 0,
            "frameDeliveryRatio": 0,
            "measuredFps": 0,
            "cpuPercentAverage": 0,
            "memoryBytesBaseline": 0,
            "memoryBytesEnd": 0,
            "memoryGrowthRatio": 0,
            "peakThermal": "nominal",
            "bitrateMbps": 0,
            "encoderLatencyMs": 0,
            "endToEndLatencyMs": 0,
            "mpegTsDecodable": False,
            "srtDelivered": False,
            "packetizationVerified": False,
            "notes": "In catalog; not yet run on device.",
        }
        for pid in secondary
    ]

    report = {
        "reportVersion": "phase2-v2-hevc",
        "generatedAt": now.isoformat().replace("+00:00", "Z"),
        "hostEnvironment": {
            "osName": "Windows",
            "arch": "x86_64",
            "hasXcode": False,
            "hasPhysicaliPhone": False,
            "notes": "Scaffold/harness authoring host. arm64 iOS device validation cannot run here.",
        },
        "toolchain": {
            "swiftVersion": "5.10+",
            "xcodeVersion": None,
            "gstreamerRecipe": "Scripts/build-gstreamer-ios.sh",
            "hevcEncoder": "VideoToolbox VTCompressionSession HEVC (not validated on device)",
        },
        "pluginRegistration": {
            "gstInitSucceeded": False,
            "registeredPlugins": [],
            "missingPlugins": [
                "coreelements",
                "app",
                "videoconvert",
                "videoscale",
                "mpegtsmux",
                "srtsink",
                "audioconvert",
                "atenc",
            ],
            "detail": "GStreamer static registration was not executed on arm64 iOS. Encode is VideoToolbox HEVC, not a GStreamer video encoder.",
        },
        "pixelFormats": ["bgra", "nv12", "i420", "yuy2", "i422_10le"],
        "profileResults": profile_results,
        "packetization": {
            "preferredBytes": 1316,
            "observedSizes": [],
            "dominantSize": None,
            "matchesPreferred": False,
            "notes": "No packets observed on device; 1316-byte packetization not verified.",
        },
        "licensingBlockers": [
            "GStreamer and libsrt licenses must be inventoried after first successful iOS link.",
        ],
        "deploymentBlockers": [
            "No arm64 iOS binary produced in this environment.",
            "App Store / ReplayKit / signing validation deferred until post-GO phases.",
            "Binary size unknown until custom XCFramework is built on macOS.",
            "HEVC sustainment (thermal/fps/bitrate) not yet measured on device.",
        ],
        "decision": {
            "verdict": "DEVICE VALIDATION REQUIRED",
            "reason": "DEVICE VALIDATION REQUIRED — no macOS + physical iPhone evidence in this environment.",
            "viableProfiles": [],
        },
    }

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    out = OUT_DIR / f"PHASE2_DEVICE_VALIDATION_REQUIRED_{stamp}.json"
    latest = OUT_DIR / "PHASE2_LATEST.json"
    text = json.dumps(report, indent=2) + "\n"
    out.write_text(text, encoding="utf-8")
    latest.write_text(text, encoding="utf-8")
    print(f"Wrote {out}")
    print(f"Wrote {latest}")
    print("Verdict: DEVICE VALIDATION REQUIRED")


if __name__ == "__main__":
    main()
