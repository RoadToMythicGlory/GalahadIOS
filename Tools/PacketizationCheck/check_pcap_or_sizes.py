#!/usr/bin/env python3
"""Verify observed SRT/UDP payload sizes against preferred 1316-byte MPEG-TS packing."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter


PREFERRED = 1316


def verify(sizes: list[int], preferred: int = PREFERRED, threshold: float = 0.85) -> dict:
    if not sizes:
        return {
            "preferredBytes": preferred,
            "observedSizes": [],
            "dominantSize": None,
            "matchesPreferred": False,
            "notes": "No packets observed; cannot claim 1316-byte packetization.",
        }

    counts = Counter(sizes)
    dominant, _ = counts.most_common(1)[0]
    ratio = counts.get(preferred, 0) / len(sizes)
    matches = ratio >= threshold
    if matches:
        notes = f"Observed {ratio * 100:.1f}% payloads at {preferred} bytes (7×188 MPEG-TS)."
    else:
        notes = f"Dominant payload size {dominant} bytes; preferred {preferred} not verified."
    return {
        "preferredBytes": preferred,
        "observedSizes": sorted(set(sizes)),
        "dominantSize": dominant,
        "matchesPreferred": matches,
        "notes": notes,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sizes-json", help="JSON array of observed payload sizes")
    parser.add_argument("--sizes", nargs="*", type=int, help="Inline sizes")
    args = parser.parse_args()

    sizes: list[int] = []
    if args.sizes_json:
        with open(args.sizes_json, encoding="utf-8") as fh:
            sizes = list(json.load(fh))
    if args.sizes:
        sizes.extend(args.sizes)

    report = verify(sizes)
    print(json.dumps(report, indent=2))
    return 0 if report["matchesPreferred"] else 1


if __name__ == "__main__":
    sys.exit(main())
