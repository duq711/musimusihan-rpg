#!/usr/bin/env python3
"""Snapshot benchmark sources without modifying user data or imported assets.

This utility does not start Godot. Never run --editor/import in its output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(source: Path, destination: Path, user_dir: str) -> dict:
    if destination.exists():
        raise FileExistsError(f"Immutable benchmark destination already exists: {destination}")
    destination.mkdir(parents=True)
    for folder in ("scripts", "shaders", "tests"):
        shutil.copytree(source / folder, destination / folder)
    for path in [source / "project.godot", *source.glob("*.tscn")]:
        shutil.copy2(path, destination / path.name)

    # Only these asset branches contain mutable benchmark inputs. Other large
    # artwork and imported resources are shared read-only by the runner.
    mutable = [
        Path("cave_water.gdshader"), Path("cave_rock.gdshader"),
        Path("3d/abandoned_mine/mine_water.gdshader"),
        Path("3d/dark_fantasy/generated_lods"),
    ]

    def link_assets(relative: Path) -> None:
        original = source / "assets" / relative
        target = destination / "assets" / relative
        if relative in mutable:
            if original.is_dir():
                shutil.copytree(original, target)
            else:
                shutil.copy2(original, target)
        elif original.is_dir() and any(relative in item.parents for item in mutable):
            target.mkdir()
            for item in original.iterdir():
                link_assets(relative / item.name)
        else:
            target.symlink_to(original.resolve(), target_is_directory=original.is_dir())

    link_assets(Path("."))
    cache = destination / ".godot"
    cache.mkdir()
    (cache / "imported").symlink_to((source / ".godot/imported").resolve(), target_is_directory=True)
    for name in ("uid_cache.bin", "global_script_class_cache.cfg"):
        if (source / ".godot" / name).exists():
            shutil.copy2(source / ".godot" / name, cache / name)
    override = destination / "override.cfg"
    override.write_text(
        '[application]\nconfig/use_custom_user_dir=true\n'
        f'config/custom_user_dir_name="{user_dir}"\n\n'
        '[rendering]\nrendering_device/pipeline_cache/enable=true\n'
    )
    hashes = {}
    for folder in ("scripts", "shaders", "tests"):
        for path in sorted((destination / folder).rglob("*")):
            if path.is_file() and path.suffix in (".gd", ".gdshader", ".sh", ".py"):
                hashes[str(path.relative_to(destination))] = sha256(path)
    hashes["project.godot"] = sha256(destination / "project.godot")
    report = {
        "source_project": str(source), "snapshot_project": str(destination),
        "source_sha256": hashes,
        "benchmark_override": {"contents": override.read_text(), "sha256": sha256(override)},
        "import_policy": "Shared imported/large artwork are runtime-read-only; never run --editor/import in this snapshot.",
        "mutable_asset_policy": "External shader sources and generated LOD assets are private copies.",
        "user_cache_policy": "Only the named Codex benchmark user directory is used; existing game/editor user data and caches are untouched.",
    }
    (destination / "benchmark_provenance.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--user-dir", default="CodexPerformanceBaseline01")
    args = parser.parse_args()
    if not args.user_dir.startswith("CodexPerformance") or any(c in args.user_dir for c in '/\\"\n\r'):
        parser.error("user-dir must be one safe CodexPerformance directory name")
    result = snapshot(args.source.resolve(), args.destination.resolve(), args.user_dir)
    print(json.dumps({"snapshot_project": result["snapshot_project"], "source_files": len(result["source_sha256"])}))
