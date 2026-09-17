#!/usr/bin/env python3
"""Fetch five CC0 photographic materials using cached official API records.

Powered by Poly Haven — https://polyhaven.com
The game ships local assets; it never connects to the Poly Haven API.
"""
import concurrent.futures
import hashlib
import json
import pathlib
import shutil
import subprocess
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parents[2]
RUNTIME = PROJECT / "godot-game/assets/3d/abandoned_mine/textures"
MANIFEST = RUNTIME.parent / "material_manifest.json"
USER_AGENT = "BlackwaterCaveMaterialAcquisition/1.0 (Powered by Poly Haven)"
SELECTION = [
    ("rock_boulder_dry", "pale_fractured_rock", 0.060),
    ("dark_rock_02", "dark_layered_rock", 0.090),
    ("brown_mud_rocks_01", "damp_gravel_mud", 0.035),
    ("rough_wood", "weathered_timber", 0.007),
    ("rust_coarse_01", "rusted_iron", 0.004),
]
CHANNELS = {
    "albedo": ("Diffuse", "sRGB"),
    "normal_gl": ("nor_gl", "linear / Non-Color"),
    "roughness": ("Rough", "linear / Non-Color"),
    "height": ("Displacement", "linear / Non-Color"),
}


def digest(path, algorithm):
    result = hashlib.new(algorithm)
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def fetch_file(record, target):
    if target.exists() and digest(target, "md5") == record["md5"]:
        return target
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".part")
    request = urllib.request.Request(record["url"], headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response, temporary.open("wb") as output:
        shutil.copyfileobj(response, output)
    if temporary.stat().st_size != record["size"] or digest(temporary, "md5") != record["md5"]:
        raise ValueError("Source size / checksum mismatch: " + target.name)
    temporary.replace(target)
    return target


def prepare_channel(asset_id, channel, record):
    name = "%s_%s_2k.jpg" % (asset_id, channel)
    source = fetch_file(record, HERE / "originals" / name)
    target = RUNTIME / name
    # The source already provides JPEG normals / height. Keep their exact
    # supplied bytes to avoid an extra data-map compression pass.
    if channel in ("normal_gl", "height"):
        shutil.copyfile(source, target)
        processing = "Original official 2K JPEG, byte-for-byte unchanged"
    else:
        quality = "88" if channel == "albedo" else "90"
        subprocess.run([
            "/usr/bin/sips", "-s", "format", "jpeg", "-s", "formatOptions", quality,
            str(source), "--out", str(target),
        ], check=True, stdout=subprocess.DEVNULL)
        processing = "JPEG storage optimization at quality %s; 2048x2048 retained; no color or pattern edits" % quality
    probe = subprocess.check_output([
        "/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(target)
    ], text=True)
    if "pixelWidth: 2048" not in probe or "pixelHeight: 2048" not in probe:
        raise ValueError("Runtime texture resolution mismatch: " + name)
    return channel, {
        "path": "res://assets/3d/abandoned_mine/textures/" + name,
        "relative_path": "textures/" + name,
        "source_url": record["url"],
        "source_md5": record["md5"],
        "source_bytes": record["size"],
        "runtime_sha256": digest(target, "sha256"),
        "runtime_bytes": target.stat().st_size,
        "size_pixels": [2048, 2048],
        "colorspace": CHANNELS[channel][1],
        "processing": processing,
    }


def main():
    RUNTIME.mkdir(parents=True, exist_ok=True)
    materials = []
    for asset_id, role, displacement in SELECTION:
        files = json.loads((HERE / (asset_id + "_files.json")).read_text())
        metadata = json.loads((HERE / (asset_id + "_metadata.json")).read_text())
        jobs = [(asset_id, channel, files[source_key]["2k"]["jpg"])
                for channel, (source_key, _colorspace) in CHANNELS.items()]
        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(lambda job: prepare_channel(*job), jobs))
        details = dict(results)
        tile_size = [round(value / 1000.0, 6) for value in metadata["dimensions"]]
        materials.append({
            "id": asset_id,
            "name": metadata["name"],
            "role": role,
            "source_url": "https://polyhaven.com/a/" + asset_id,
            "source_api_url": "https://api.polyhaven.com/files/" + asset_id,
            "license": "CC0-1.0",
            "license_url": "https://polyhaven.com/license",
            "legal_code_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "authors": metadata["authors"],
            "physical_size_m": tile_size,
            "physical_size_provenance": "Official API dimensions in millimetres, converted to metres; corroborated by the asset page's tile dimensions",
            "normal_convention": "OpenGL tangent-space +Y (green up); do not invert green for Blender or Godot",
            "channels": {key: value["path"] for key, value in details.items()},
            "channel_details": details,
            "suggested_displacement_m": displacement,
            "displacement_note": "Art-direction starting value, not a measured source scan height. Height midlevel 0.5. Use mesh geometry for large silhouette changes.",
            "suggested_metallic": 0.05 if role == "rusted_iron" else 0.0,
            "metallic_note": "Heavy rust is mostly dielectric; use separate worn bare-metal parts for brighter metallic response" if role == "rusted_iron" else "Non-metallic scanned surface",
        })
        print("Ready:", asset_id, tile_size, flush=True)
    total = sum(item["runtime_bytes"] for mat in materials for item in mat["channel_details"].values())
    manifest = {
        "schema_version": 1,
        "source_library": "Poly Haven",
        "acquisition_date": "2026-09-05",
        "api_credit": "Powered by Poly Haven — https://polyhaven.com",
        "api_terms_url": "https://github.com/Poly-Haven/Public-API/blob/master/ToS.md",
        "total_runtime_texture_bytes": total,
        "materials": materials,
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    (HERE / "material_manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    if total > 40_000_000:
        raise ValueError("Texture budget exceeded: %s bytes" % total)
    print("Verified 20 maps: %.2f MB total" % (total / 1e6), flush=True)


if __name__ == "__main__":
    main()
