#!/usr/bin/env python3
"""Measure actual downloaded glTF vertices; no app window or renderer."""
import json
import math
import pathlib
import struct

HERE = pathlib.Path(__file__).resolve().parent


def inspect(asset_id):
    folder = HERE / (asset_id + "_scan")
    scene = json.loads((folder / (asset_id + "_1k.gltf")).read_text())
    blobs = [(folder / b["uri"]).read_bytes() for b in scene["buffers"]]

    def values(index):
        accessor = scene["accessors"][index]
        view = scene["bufferViews"][accessor["bufferView"]]
        types = {5126: ("f", 4), 5125: ("I", 4), 5123: ("H", 2), 5121: ("B", 1)}
        kind, width = types[accessor["componentType"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", count * width)
        return [struct.unpack_from("<" + kind * count, blobs[view["buffer"]], offset + i * stride)
                for i in range(accessor["count"])]

    assert all(not any(key in n for key in ("matrix", "scale", "translation", "rotation"))
               for n in scene["nodes"]), "This inspector expects identity source nodes"
    positions = []
    normal_sum = [0.0, 0.0, 0.0]
    total_area = 0.0
    for mesh in scene["meshes"]:
        for primitive in mesh["primitives"]:
            vertices = values(primitive["attributes"]["POSITION"])
            indices = [v[0] for v in values(primitive["indices"])]
            positions.extend(vertices)
            for i in range(0, len(indices), 3):
                a, b, c = (vertices[j] for j in indices[i:i + 3])
                ab, ac = ([b[j] - a[j] for j in range(3)], [c[j] - a[j] for j in range(3)])
                cross = [ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0]]
                for axis in range(3):
                    normal_sum[axis] += cross[axis] * 0.5
                total_area += math.sqrt(sum(v * v for v in cross)) * 0.5
    low = [min(p[i] for p in positions) for i in range(3)]
    high = [max(p[i] for p in positions) for i in range(3)]
    length = math.sqrt(sum(v * v for v in normal_sum))
    result = {
        "gltf_units": "metres, +Y up, identity node transforms",
        "gltf_bounds_min": low,
        "gltf_bounds_max": high,
        "gltf_size_xyz": [high[i] - low[i] for i in range(3)],
        "gltf_floor_center_offset": [-(low[0] + high[0]) * 0.5, -low[1], -(low[2] + high[2]) * 0.5],
        "blender_axis_conversion": "glTF (x,y,z) maps to Blender (x,-z,y); Blender +Z up",
        "blender_bounds_min": [low[0], -high[2], low[1]],
        "blender_bounds_max": [high[0], -low[2], high[1]],
        "net_surface_normal_gltf": [v / length for v in normal_sum],
        "net_surface_area_ratio": length / total_area,
        "orientation_note": "Net normal estimates the outward direction of an open scan patch; it is not a authored forward axis. Recenter on the floor before applying placement rotation. Inspect the scan's visible face in the scene render.",
    }
    manifest_path = folder / "source_manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["measured_geometry"] = result
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(asset_id, json.dumps(result))


if __name__ == "__main__":
    for selected in ("rock_face_01", "rock_face_02"):
        inspect(selected)
