#!/usr/bin/env python3
"""Index original concepts and verified renderer outputs without changing pixels."""
from __future__ import annotations

import json
import os
from pathlib import Path
from urllib.parse import quote

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PRODUCTION = ROOT / "godot-game"
BASELINE = HERE.parent / "baseline_project"
IDLE_BASELINE_MANIFEST = BASELINE / "artifacts/visual_qa/dark_fantasy_scenes/baseline_torch_idle_04/capture_manifest.json"
BASELINE_SCENE_ITERATION = "baseline_torch_idle_04" if IDLE_BASELINE_MANIFEST.is_file() else "baseline_torch_03"


def link(path: Path) -> str:
    return quote(os.path.relpath(path, HERE), safe="/")


def captures(project: Path, family: str, records_key: str) -> dict:
    latest = {}
    manifests = sorted((project / "artifacts/visual_qa" / family).glob("*/capture_manifest.json"), key=lambda p: p.stat().st_mtime_ns)
    for path in manifests:
        manifest = json.loads(path.read_text())
        if manifest.get("source_files_unchanged") is False or not manifest.get("expedition_and_cursor_preserved") or manifest.get("display_driver") != "embedded" or manifest.get("actual_renderer") != "vulkan":
            continue
        # Prefer the final settled idle torch pose once its complete manifest is
        # available; older experiments omitted normal production torch lighting.
        if project == BASELINE and family == "dark_fantasy_scenes" and path.parent.name != BASELINE_SCENE_ITERATION:
            continue
        for record in manifest.get(records_key, []):
            if records_key == "objects":
                views = {image["view"]: link(path.parent / image["file"]) for image in record["images"] if (path.parent / image["file"]).is_file()}
                if len(views) != 6 or not (path.parent / record["sheet"]).is_file():
                    continue
                latest[record["id"]] = {"sheet": link(path.parent / record["sheet"]), "views": views, "iteration": path.parent.name, "manifest": link(path)}
            elif (path.parent / record["file"]).is_file():
                latest[record["id"]] = {"sheet": link(path.parent / record["file"]), "iteration": path.parent.name, "manifest": link(path), "position": record["position"], "target": record["target"], "fov": record["fov"]}
    return latest


inventory = json.loads((PRODUCTION / "assets/art_direction/object_inventory.json").read_text())
baseline = captures(BASELINE, "dark_fantasy_objects", "objects")
current = captures(PRODUCTION, "dark_fantasy_objects", "objects")
objects = []
for entry in inventory["entries"]:
    if entry.get("excluded_by_user"):
        continue
    object_id = entry["id"]
    concept = ROOT / "concept-art/dark_fantasy_all_objects" / (object_id + ".png")
    objects.append({"id": object_id, "title": entry["title"], "category": entry["category"], "source": entry["factory"], "concept": link(concept) if concept.is_file() else None, "baseline": baseline.get(object_id), "current": current.get(object_id)})

scene_names = {"hideout_hearth": "은신처 · 모닥불", "hideout_storage": "은신처 · 창고", "hideout_saint": "은신처 · 머리 없는 성인", "hideout_workshop": "은신처 · 작업실", "dungeon_entry": "성물실 · 입구", "dungeon_chest": "성물실 · 보급 상자", "dungeon_sanctum": "성물실 · 봉인", "mine_entrance": "폐광 · 입구", "mine_timber": "폐광 · 지지대", "mine_water_shore": "폐광 · 물가"}
baseline_scenes = captures(BASELINE, "dark_fantasy_scenes", "images")
current_scenes = captures(PRODUCTION, "dark_fantasy_scenes", "images")
scenes = [{"id": key, "title": title, "baseline": baseline_scenes.get(key), "current": current_scenes.get(key)} for key, title in scene_names.items()]
data = {"objects": objects, "scenes": scenes, "counts": {"total": len(objects), "concept": sum(bool(o["concept"]) for o in objects), "baseline": sum(bool(o["baseline"]) for o in objects), "current": sum(bool(o["current"]) for o in objects)}}

# The report is self-contained HTML; its images remain the original files.
payload = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")
template = (HERE / "review_template.html").read_text()
(HERE / "index.html").write_text(template.replace("__REVIEW_DATA__", payload))
(HERE / "coverage.json").write_text(json.dumps(data["counts"], ensure_ascii=False, indent=2) + "\n")
print(json.dumps(data["counts"], ensure_ascii=False))
