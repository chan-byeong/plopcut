#!/usr/bin/env python3
"""Writes a deterministic synthetic plopcut library for performance measurements.

Usage: scripts/generate-perf-library.py OUTPUT_DIR [COUNT]   (COUNT defaults to 5000)

OUTPUT_DIR must not exist or must be empty, and must not be a real plopcut
storage folder. The drops go to OUTPUT_DIR/drops, the same layout the app scans.
About 90% are text drops, 10% are image drops. Same arguments, same output.
"""
import json
import os
import random
import sys
from datetime import datetime, timedelta, timezone

PNG = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00])
APPS = ["Safari", "Chrome", "Xcode", "Notes", "Slack", "Terminal", "Preview", "Mail"]
TAGS = ["research", "swift", "quote", "todo", "idea", "bug", "reading", "design", "ko", "work"]
WORDS = ("alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike "
         "november oscar papa quebec romeo sierra tango uniform victor whiskey xray yankee zulu "
         "라이브러리 드롭 검색 노트 태그 캡처 저장 설정").split()


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    out = sys.argv[1]
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
    if os.path.exists(out) and os.listdir(out):
        sys.exit(f"{out} is not empty")
    rng = random.Random(20260101)
    base = datetime(2026, 1, 1, tzinfo=timezone.utc)
    drops_dir = os.path.join(out, "drops")
    for i in range(count):
        created = base + timedelta(minutes=7 * i, microseconds=i)
        stamp = created.strftime("%Y-%m-%dT%H:%M:%S.") + f"{created.microsecond:06d}000Z"
        is_image = i % 10 == 9
        app = APPS[rng.randrange(len(APPS))]
        title = " ".join(rng.choice(WORDS) for _ in range(rng.randint(2, 5)))
        drop_id = created.strftime("%Y-%m-%d_%H%M%S_") + f"{created.microsecond:06d}000_drop-{i:05d}"
        folder = os.path.join(drops_dir, drop_id)
        os.makedirs(folder)
        tags = sorted(set(rng.choice(TAGS) for _ in range(rng.randint(0, 3))))
        meta = {
            "id": drop_id, "type": "image" if is_image else "text", "title": title,
            "text": None, "imagePath": "image.png" if is_image else None,
            "source": {"appName": app, "windowTitle": f"{app} window {i % 50}",
                       "url": f"https://example.com/page/{i}" if i % 3 == 0 else None, "filePath": None},
            "note": None, "tags": tags, "createdAt": stamp, "updatedAt": stamp,
        }
        with open(os.path.join(folder, "drop.json"), "w", encoding="utf-8") as f:
            json.dump(meta, f, ensure_ascii=False, indent=2)
        if is_image:
            with open(os.path.join(folder, "image.png"), "wb") as f:
                f.write(PNG)
        else:
            body = " ".join(rng.choice(WORDS) for _ in range(rng.randint(20, 200)))
            with open(os.path.join(folder, "content.md"), "w", encoding="utf-8") as f:
                f.write(body)
        note = " ".join(rng.choice(WORDS) for _ in range(10)) if i % 4 == 0 else ""
        with open(os.path.join(folder, "note.md"), "w", encoding="utf-8") as f:
            f.write(note)
    print(f"wrote {count} drops to {drops_dir}")


if __name__ == "__main__":
    main()
