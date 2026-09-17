#!/usr/bin/env python3
"""Compare immutable VFX captures; this verifies evidence, not art similarity."""
import argparse
import hashlib
import json
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("previous")
    parser.add_argument("current")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    workspace = Path(__file__).resolve().parents[3]
    capture_root = workspace / "godot-game/artifacts/visual_qa/dark_fantasy_objects"
    prior_review = json.loads((Path(__file__).parent / "vfx_review_final_02.json").read_text())
    paths = [capture_root / value for value in (args.previous, args.current)]
    manifests = [json.loads((path / "capture_manifest.json").read_text()) for path in paths]
    for manifest in manifests:
        assert manifest["actual_renderer"] and manifest["complete_catalog"]
        assert manifest["source_files_unchanged"] and manifest["expedition_and_cursor_preserved"]
        assert manifest["captured_count"] == 126
    indexed = [{entry["id"]: entry for entry in manifest["objects"]} for manifest in manifests]
    comparisons = []
    for review in prior_review["objects"]:
        object_id = review["id"]
        objects = [entries[object_id] for entries in indexed]
        records = []
        for view in manifests[1]["view_order"]:
            images = [next(image for image in entry["images"] if image["view"] == view) for entry in objects]
            hashes = [sha(directory / image["file"]) for directory, image in zip(paths, images)]
            assert all(value == image["sha256"] for value, image in zip(hashes, images))
            records.append({"view": view, "same_png_bytes": hashes[0] == hashes[1], "previous_sha256": hashes[0], "current_sha256": hashes[1]})
        sheet_hashes = [sha(directory / entry["sheet"]) for directory, entry in zip(paths, objects)]
        comparisons.append({
            "id": object_id,
            "same_bounds": objects[0]["bounds"] == objects[1]["bounds"],
            "same_direct_factory_source": objects[0]["source_sha256"] == objects[1]["source_sha256"],
            "same_sheet_bytes": sheet_hashes[0] == sheet_hashes[1],
            "current_sheet": str((paths[1] / objects[1]["sheet"]).relative_to(workspace)),
            "current_sheet_sha256": sheet_hashes[1],
            "views": records,
            "direct_visual_review_required": any(not record["same_png_bytes"] for record in records),
        })
    report = {"previous": args.previous, "current": args.current, "method": "SHA-256 comparison of unmodified renderer PNGs and exact recorded AABBs. Changed pixels require visual review; matching bytes inherit the prior direct review.", "objects": comparisons}
    Path(args.output).write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"objects": len(comparisons), "requires_direct_review": [item["id"] for item in comparisons if item["direct_visual_review_required"]]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
