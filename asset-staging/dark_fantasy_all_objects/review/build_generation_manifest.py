#!/usr/bin/env python3
"""Reconcile preserved imagegen originals with the final active art inventory."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ART = ROOT / "concept-art/dark_fantasy_all_objects"
INVENTORY = ROOT / "godot-game/assets/art_direction/object_inventory.json"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


folders = {Path("/Users/duq711gmail.com/.codex/generated_images/01a07265-2d3a-7d73-8f38-8c0f3ba02f79")}
for path in (ART / "prompts").glob("*.provenance.json"):
    entry = json.loads(path.read_text())
    if entry.get("source"):
        folders.add(Path(entry["source"]).parent)
originals = {}
for folder in folders:
    for path in folder.glob("*.png"):
        originals[sha256(path)] = str(path)

entries = []
for entry in json.loads(INVENTORY.read_text())["entries"]:
    if entry.get("excluded_by_user"):
        continue
    object_id = entry["id"]
    concept = ART / (object_id + ".png")
    digest = sha256(concept)
    entries.append({
        "id": object_id,
        "name": entry["title"],
        "concept_file": str(concept.relative_to(ROOT)),
        "sha256": digest,
        "builtin_original": originals.get(digest),
        "prompt_files": [str(p.relative_to(ROOT)) for p in sorted((ART / "prompts").glob(object_id + "*.txt"))],
        "required_views": entry["required_views"],
        "factory": entry["factory"],
        "variant_coverage": entry.get("variant_coverage", []),
    })
textures = []
for path in sorted((ROOT / "godot-game/assets/ai/materials").glob("concept_*.png")):
    digest = sha256(path)
    textures.append({"file": str(path.relative_to(ROOT)), "sha256": digest,
                     "builtin_original": originals.get(digest),
                     "prompt_file": str((ART / "prompts" / (path.stem + ".txt")).relative_to(ROOT))})
result = {
    "tool": "Codex built-in imagegen",
    "active_archetypes": len(entries),
    "excluded_ids": ["gravebound_player", "chest_hands"],
    "concepts": entries,
    "runtime_surface_textures": textures,
    "direction_note": "Generated drawings are art references; exact six-axis projection is validated from actual Godot renderer images. Repeated placements are grouped by type, with all covered names preserved in variant_coverage.",
}
(ART / "generation_manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
print(json.dumps({"concepts": len(entries), "original_matches": sum(bool(e["builtin_original"]) for e in entries), "runtime_maps": len(textures)}))
