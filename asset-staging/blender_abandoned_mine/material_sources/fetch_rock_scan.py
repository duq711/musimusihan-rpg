#!/usr/bin/env python3
"""Fetch one optional CC0 cliff mesh. Powered by https://polyhaven.com."""
import json
import pathlib
import sys
from fetch_materials import HERE, fetch_file, digest

ASSET_ID = sys.argv[1] if len(sys.argv) > 1 else "rock_face_02"
if ASSET_ID not in ("rock_face_01", "rock_face_02"):
    raise ValueError("Only the two reviewed cliff scans are supported")


def main():
    records = json.loads((HERE / (ASSET_ID + "_model_files.json")).read_text())
    record = records["gltf"]["1k"]["gltf"]
    folder = HERE / (ASSET_ID + "_scan")
    folder.mkdir(parents=True, exist_ok=True)
    main_file = folder / (ASSET_ID + "_1k.gltf")
    fetched = [(main_file.name, fetch_file(record, main_file), record)]
    for relative, included in record.get("include", {}).items():
        path = folder / relative
        if not path.resolve().is_relative_to(folder.resolve()):
            raise ValueError("Untrusted include path")
        fetched.append((relative, fetch_file(included, path), included))
    model = json.loads(main_file.read_text())
    metadata = json.loads((HERE / (ASSET_ID + "_model_metadata.json")).read_text())
    for section in ("buffers", "images"):
        for entry in model.get(section, []):
            uri = entry.get("uri", "")
            if uri and not uri.startswith("data:"):
                assert (folder / uri).is_file(), "Missing glTF dependency: " + uri
    triangle_count = sum(model["accessors"][primitive["indices"]]["count"] // 3
                         for mesh in model["meshes"] for primitive in mesh["primitives"]
                         if primitive.get("mode", 4) == 4)
    info = {
        "id": ASSET_ID,
        "source_url": "https://polyhaven.com/a/" + ASSET_ID,
        "license": "CC0-1.0",
        "license_url": "https://polyhaven.com/license",
        "authors": metadata["authors"],
        "declared_source_dimensions_m": [d / 1000.0 for d in metadata["dimensions"]],
        "triangle_count": triangle_count,
        "source_width_provenance": "Official API dimensions. Inspect glTF actual vertex bounds before placing; exported mesh extent can differ from the library's source metadata.",
        "use_note": "Optional genuine irregular cliff silhouette source for Blender. Contains outdoor lichen; use the five selected cave PBR sets if that appearance is unsuitable. The game has not automatically imported or placed this staging asset.",
        "files": [{"relative_path": name, "source_url": rec["url"],
                   "source_md5": rec["md5"], "sha256": digest(path, "sha256"),
                   "bytes": path.stat().st_size} for name, path, rec in fetched],
    }
    (folder / "source_manifest.json").write_text(json.dumps(info, indent=2) + "\n")
    print("Verified optional cliff:", triangle_count, "triangles;", sum(path.stat().st_size for _, path, _ in fetched), "bytes")


if __name__ == "__main__":
    main()
