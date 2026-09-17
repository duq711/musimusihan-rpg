#!/usr/bin/env python3
"""Compare unchanged owned production objects across completed final captures."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[3]
FAMILY = ROOT / "godot-game/artifacts/visual_qa/dark_fantasy_objects"
OLD = FAMILY / "final_iteration_02"
NEW = FAMILY / "final_iteration_03"
DIRECT_REVIEW = {"ossuary_wall", "wet_flagstone_floor", "crypt_ceiling", "hideout_hearth"}
VIEWS = ["front", "back", "left", "right", "top", "bottom"]

manifest = json.loads((NEW / "capture_manifest.json").read_text())
assert manifest["source_files_unchanged"] is True and manifest["captured_count"] == 126
review = json.loads((ROOT / "concept-art/dark_fantasy_all_objects/props_final_review.json").read_text())
records = []
for entry in review["entries"]:
    if entry["id"] in DIRECT_REVIEW:
        continue
    for view in VIEWS:
        name = f'{entry["id"]}_{view}.png'
        with Image.open(OLD / name) as first, Image.open(NEW / name) as second:
            a, b = first.convert("RGBA"), second.convert("RGBA")
            equal = a.size == b.size and a.tobytes() == b.tobytes()
            bounds = None
            if not equal and a.size == b.size:
                diff = ImageChops.difference(a, b)
                bounds = diff.convert("RGB").getbbox() or diff.getchannel("A").getbbox()
            records.append({"id": entry["id"], "view": view, "pixels_identical": equal, "difference_bounds": bounds})
result = {
    "old_iteration": OLD.name,
    "new_iteration": NEW.name,
    "new_manifest_sha256": hashlib.sha256((NEW / "capture_manifest.json").read_bytes()).hexdigest(),
    "directly_rereviewed_ids": sorted(DIRECT_REVIEW),
    "unchanged_objects_checked": len(records) // 6,
    "unchanged_views_checked": len(records),
    "identical_views": sum(record["pixels_identical"] for record in records),
    "all_pixels_identical": all(record["pixels_identical"] for record in records),
    "records": records,
}
target = ROOT / "concept-art/dark_fantasy_all_objects/props_final_pixel_consistency.json"
target.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({key: value for key, value in result.items() if key != "records"}))
