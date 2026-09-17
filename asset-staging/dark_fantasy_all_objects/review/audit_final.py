#!/usr/bin/env python3
"""Verify preserved concept provenance and actual final capture evidence."""
import hashlib
import json
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GAME = ROOT / "godot-game"
ART = ROOT / "concept-art/dark_fantasy_all_objects"
BASELINE = HERE.parent / "baseline_project"
VIEWS = {"front", "back", "left", "right", "top", "bottom"}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png(path, expected=None):
    with path.open("rb") as stream:
        header = stream.read(24)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", path
    size = struct.unpack(">II", header[16:24])
    assert size == expected if expected else min(size) >= 512, (path, size)


def verified_image(folder, record, expected=None):
    path = folder / record["file"]
    png(path, expected)
    assert sha(path) == record["sha256"], path


def latest_complete(family, key, count):
    candidates = sorted((GAME / "artifacts/visual_qa" / family).glob("*/capture_manifest.json"), key=lambda p: p.stat().st_mtime_ns, reverse=True)
    for path in candidates:
        data = json.loads(path.read_text())
        if len(data.get(key, [])) == count and data.get("source_files_unchanged"):
            return path, data
    raise AssertionError(f"No final unchanged-source capture: {family}")


def check_renderer(data):
    assert data["actual_renderer"] == "vulkan"
    assert data["display_driver"] == "embedded"
    assert data["expedition_and_cursor_preserved"]
    assert not data["desktop_capture"] and not data["external_input"]


def check_sources(data):
    sources = data.get("sources", data.get("source_sha256", {}))
    assert sources
    for source, digest in sources.items():
        assert source.startswith("res://")
        path = GAME / source.removeprefix("res://")
        assert sha(path) == digest, f"Source changed after capture: {source}"
    assert "res://assets/3d/abandoned_mine/mine_water.gdshader" in sources
    assert sum(p.endswith(".png") and "/concept_" in p for p in sources) == 7
    return len(sources)


inventory = json.loads((GAME / "assets/art_direction/object_inventory.json").read_text())
active = {e["id"] for e in inventory["entries"] if not e.get("excluded_by_user")}
excluded = {e["id"] for e in inventory["entries"] if e.get("excluded_by_user")}
assert len(active) == 126 and excluded == {"gravebound_player", "chest_hands"}
authored_models = []
for source in sorted({e["asset_path"] for e in inventory["entries"] if e["id"] in active and e.get("asset_path")}):
    assert source.startswith("res://")
    relative = source.removeprefix("res://")
    digest = sha(GAME / relative)
    assert digest == sha(BASELINE / relative), f"Original authored model changed: {source}"
    authored_models.append({"file": source, "sha256": digest})
generation = json.loads((ART / "generation_manifest.json").read_text())
assert {e["id"] for e in generation["concepts"]} == active
for entry in generation["concepts"]:
    path = ROOT / entry["concept_file"]
    png(path)
    assert sha(path) == entry["sha256"] == sha(Path(entry["builtin_original"]))
    assert set(entry["required_views"]) == VIEWS
    assert entry["prompt_files"] and all((ROOT / p).is_file() for p in entry["prompt_files"])
assert len(generation["runtime_surface_textures"]) == 7
for entry in generation["runtime_surface_textures"]:
    assert sha(ROOT / entry["file"]) == entry["sha256"] == sha(Path(entry["builtin_original"]))

object_path, objects = latest_complete("dark_fantasy_objects", "objects", 126)
check_renderer(objects)
object_sources = check_sources(objects)
assert objects["complete_catalog"] and objects["captured_count"] == 126
assert {entry["id"] for entry in objects["objects"]} == active
model_source_hashes = {}
for entry in objects["objects"]:
    source = entry["source_path"]
    assert source.startswith("res://")
    if source not in model_source_hashes:
        model_source_hashes[source] = sha(GAME / source.removeprefix("res://"))
    assert model_source_hashes[source] == entry["source_sha256"], source
    assert len(entry["images"]) == 6 and {v["view"] for v in entry["images"]} == VIEWS
    for view in entry["images"]:
        verified_image(object_path.parent, view, (512, 512))
    png(object_path.parent / entry["sheet"], (1536, 1024))

baseline_objects = {}
for path in sorted((BASELINE / "artifacts/visual_qa/dark_fantasy_objects").glob("*/capture_manifest.json"), key=lambda p: p.stat().st_mtime_ns):
    data = json.loads(path.read_text())
    check_renderer(data)
    for entry in data["objects"]:
        if len(entry["images"]) == 6:
            baseline_objects[entry["id"]] = (path, entry)
assert set(baseline_objects) == active
for path, entry in baseline_objects.values():
    for view in entry["images"]:
        verified_image(path.parent, view, (512, 512))

scene_path, scenes = latest_complete("dark_fantasy_scenes", "images", 10)
check_renderer(scenes)
scene_sources = check_sources(scenes)
baseline_scene_path = BASELINE / "artifacts/visual_qa/dark_fantasy_scenes/baseline_torch_idle_04/capture_manifest.json"
baseline_scenes = json.loads(baseline_scene_path.read_text())
check_renderer(baseline_scenes)
before_by_id = {e["id"]: e for e in baseline_scenes["images"]}
assert {e["id"] for e in scenes["images"]} == set(before_by_id)
for entry in scenes["images"]:
    before = before_by_id[entry["id"]]
    assert all(entry[k] == before[k] for k in ("position", "target", "fov")), entry["id"]
    verified_image(scene_path.parent, entry, (1280, 720))
    verified_image(baseline_scene_path.parent, before, (1280, 720))

test_log = GAME / "artifacts/visual_qa/dark_fantasy_final_art_tests_03.log"
test_text = test_log.read_text()
assert test_text.rstrip().endswith("Headless validation: 15 passed, 0 failed.")
assert "SCRIPT ERROR:" not in test_text and "Parse Error:" not in test_text

regression_logs = []
for filename, count in (("dark_fantasy_final_integration_tests.log", 4),
                        ("dark_fantasy_join_regression_02.log", 3),
                        ("dark_fantasy_hearth_refinement.log", 3),
                        ("dark_fantasy_hearth_normals_02.log", 2)):
    path = GAME / "artifacts/visual_qa" / filename
    contents = path.read_text()
    assert contents.rstrip().endswith(f"Headless validation: {count} passed, 0 failed.")
    assert "SCRIPT ERROR:" not in contents and "Parse Error:" not in contents
    regression_logs.append({"file": str(path.relative_to(ROOT)), "passed": count, "sha256": sha(path)})

review_paths = [ART / "mine_final_review.json", ART / "props_final_review.json",
                ART / "equipment_and_surfaces_final_review.json",
                HERE / f"vfx_review_final_{object_path.parent.name.rsplit('_', 1)[1]}.json"]
reviewed_ids = []
for path in review_paths:
    review = json.loads(path.read_text())
    records = review.get("entries", review.get("objects", []))
    reviewed_ids.extend(entry["id"] for entry in records)
    for entry in records:
        reference = next((entry.get(key) for key in ("actual_capture_path", "actual_file", "capture_file", "sheet") if entry.get(key)), None)
        assert reference, (path, entry["id"])
        sheet_path = Path(reference)
        if not sheet_path.is_absolute():
            sheet_path = ROOT / sheet_path
        assert sheet_path.parent == object_path.parent, f"Review points to an older capture: {entry['id']}"
        png(sheet_path, (1536, 1024))
assert len(reviewed_ids) == 126 and set(reviewed_ids) == active, "Per-object visual reviews must cover each active ID once"
scene_review_path = ART / "scene_final_review.json"
scene_review = json.loads(scene_review_path.read_text())
assert scene_review["capture_iteration"] == scene_path.parent.name and scene_review["final_accepted"]
assert {entry["id"] for entry in scene_review["entries"]} == set(before_by_id)
for entry in scene_review["entries"]:
    assert sha(ROOT / entry["current_file"]) == entry["current_sha256"]

viewer_qa_path = HERE / "viewer_qa.json"
viewer_qa = json.loads(viewer_qa_path.read_text())
assert viewer_qa["passed"] and not viewer_qa["page_errors"]
assert viewer_qa["data_audit"]["current_object_iterations"] == [object_path.parent.name]
assert viewer_qa["data_audit"]["current_scene_iterations"] == [scene_path.parent.name]
assert viewer_qa["data_audit"]["html_sha256"] == sha(HERE / "index.html")
assert viewer_qa["data_audit"]["coverage"] == {"total": 126, "concept": 126, "baseline": 126, "current": 126}

result = {"status": "PASS", "active_object_types": len(active), "excluded": sorted(excluded),
          "imagegen_original_matches": 126, "runtime_generated_maps": 7,
          "final_objects": str(object_path.relative_to(ROOT)), "final_scenes": str(scene_path.relative_to(ROOT)),
          "current_individual_views": 756, "current_six_view_sheets": 126,
          "baseline_individual_views": 756, "matching_scene_camera_pairs": 10,
          "current_sources_verified": {"objects": object_sources, "scenes": scene_sources},
          "current_factory_source_files_verified": len(model_source_hashes),
          "inventory_authored_models_preserved": authored_models,
          "art_test_suites_passed": 15, "art_test_log": str(test_log.relative_to(ROOT)),
          "art_test_log_sha256": sha(test_log),
          "regression_logs": regression_logs,
          "reviewed_unique_object_types": len(reviewed_ids),
          "object_review_files": [str(p.relative_to(ROOT)) for p in review_paths],
          "scene_review_file": str(scene_review_path.relative_to(ROOT)),
          "viewer_qa_file": str(viewer_qa_path.relative_to(ROOT)),
          "pixel_hashes_verified": True, "visual_similarity_score_claimed": False}
(HERE / "final_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(result, ensure_ascii=False))
