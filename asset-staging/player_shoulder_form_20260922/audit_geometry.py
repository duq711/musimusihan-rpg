"""Read-only geometry audit; run with Blender --background --python this_file.

Loads the preserved trouser-only source and current sculpt. Writes only the
adjacent geometry_audit.json; does not save or export either model. Visual
acceptance deliberately remains pending until the actual renders are reviewed.
"""

import hashlib
import json
from pathlib import Path
import struct

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE.parent / "player_trousers_only_20260922"
SOURCE_GLB = SOURCE_DIR / "gravebound_player_trousers_only.glb"
RESULT_GLB = HERE / "gravebound_player_shoulder_form.glb"
TARGETS = ["Gravebound_QuiltedTorso", "Gravebound_FP_L_Arm", "Gravebound_FP_R_Arm"]


def read_glb(path):
    data = path.read_bytes()
    assert data[:4] == b"glTF" and struct.unpack_from("<I", data, 8)[0] == len(data)
    json_length = struct.unpack_from("<I", data, 12)[0]
    document = json.loads(data[20:20 + json_length])
    binary = data[28 + json_length:]

    def accessor(index):
        item = document["accessors"][index]
        view = document["bufferViews"][item["bufferView"]]
        count = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[item["type"]]
        component = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}[item["componentType"]]
        fmt = "<" + component * count
        stride = view.get("byteStride", struct.calcsize(fmt))
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(item["count"])]

    meshes = {}
    for node in document["nodes"]:
        if "mesh" not in node:
            continue
        primitives = []
        for primitive in document["meshes"][node["mesh"]]["primitives"]:
            primitives.append({
                "attrs": {name: accessor(index) for name, index in primitive["attributes"].items()},
                "indices": [value[0] for value in accessor(primitive["indices"])],
                "material_name": document["materials"][primitive["material"]]["name"],
            })
        meshes[node["name"]] = {
            "prims": primitives,
            "transform": {key: node[key] for key in ("translation", "rotation", "scale", "matrix") if key in node},
        }
    images = {}
    for index, item in enumerate(document.get("images", [])):
        if "bufferView" not in item:
            continue
        view = document["bufferViews"][item["bufferView"]]
        offset = view.get("byteOffset", 0)
        images[item.get("name", str(index))] = hashlib.sha256(binary[offset:offset + view["byteLength"]]).hexdigest()
    return meshes, hashlib.sha256(data).hexdigest(), images


def primary_data(mesh):
    return {
        "transform": mesh["transform"],
        "prims": [{
            "attrs": {name: value for name, value in primitive["attrs"].items() if name != "TANGENT"},
            "indices": primitive["indices"],
            "material_name": primitive["material_name"],
        } for primitive in mesh["prims"]],
    }


def lower_triangles(mesh):
    result = set()
    for primitive in mesh["prims"]:
        points, indices = primitive["attrs"]["POSITION"], primitive["indices"]
        for i in range(0, len(indices), 3):
            triangle = [points[index] for index in indices[i:i + 3]]
            # glTF exports Y up. Target node rotations only rotate about Y.
            if max(point[1] for point in triangle) <= 1.18:
                result.add(tuple(sorted(tuple(round(value, 6) for value in point) for point in triangle)))
    return result


def surface_bvh(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    points, polygons = [], []
    for name in TARGETS:
        obj = bpy.data.objects[name]
        offset = len(points)
        points.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons)
    return BVHTree.FromPolygons(points, polygons)


source, source_hash, source_images = read_glb(SOURCE_GLB)
result, result_hash, result_images = read_glb(RESULT_GLB)
preserved = {name: primary_data(source[name]) == primary_data(result[name]) for name in result if name not in TARGETS and name in source}
report = {
    "model_sha256": result_hash,
    "source_glb_sha256": source_hash,
    "mesh_count": len(result),
    "modified_meshes": TARGETS,
    "unexpected_mesh_set_changes": sorted(set(source) ^ set(result)),
    "preserved_meshes": preserved,
    "preserved_mesh_count": sum(preserved.values()),
    "preservation_basis": "Exact exported POSITION, NORMAL, UV, indices, node transform and material name for all 17 non-target meshes; derived tangents are reported separately.",
    "embedded_images_preserved": source_images == result_images,
    "embedded_image_count": len(result_images),
    "geometry_preserved_below_1_18m": {},
}
report["preserved_mesh_tangent_max_delta"] = {
    name: max((abs(a - b)
               for p, q in zip(source[name]["prims"], result[name]["prims"])
               for v, w in zip(p["attrs"].get("TANGENT", []), q["attrs"].get("TANGENT", []))
               for a, b in zip(v, w)), default=0)
    for name in preserved
}
for name in TARGETS:
    old, new = lower_triangles(source[name]), lower_triangles(result[name])
    report["geometry_preserved_below_1_18m"][name] = {
        "source_triangle_count": len(old), "result_triangle_count": len(new),
        "missing_source_triangles": len(old - new), "new_triangles": len(new - old),
        "includes_uv": False, "pass": old == new,
    }

x_samples = [.14, .155, .17, .185, .20, .215, .23, .245]
sections = {}
side_profiles = {}
for label, path in [("source", SOURCE_DIR / "Gravebound_Trousers_Only.blend"), ("result", HERE / "Gravebound_Shoulder_Form.blend")]:
    bvh, rows = surface_bvh(path), []
    for height in [1.29, 1.31, 1.33, 1.35, 1.37, 1.39]:
        for side in [-1, 1]:
            for surface in ["front", "rear"]:
                depth, direction = (-.6, 1) if surface == "front" else (.6, -1)
                values = []
                for x in x_samples:
                    hit = bvh.ray_cast(Vector((side * x, depth, height)), Vector((0, direction, 0)), 1.2)[0]
                    values.append(abs(hit.y) if hit is not None else None)
                rise, minimum = 0, 1
                for value in values:
                    if value is not None:
                        minimum = min(minimum, value)
                        rise = max(rise, value - minimum)
                rows.append({
                    "height_m": height, "side": side, "surface": surface,
                    "depth_m": [round(value, 6) if value is not None else None for value in values],
                    "secondary_lobe_rise_m": round(rise, 6),
                })
    sections[label] = rows
    # A narrow fin at depth Y=0 can survive the front/rear lobe test. Compare
    # its lateral extent against a smooth parabola through Y=+/-2cm and 4cm.
    side_rows = []
    for step in range(10):
        height = 1.38 + step * .005
        for side in [-1, 1]:
            depths = [-.04, -.02, 0, .02, .04]
            hits = [bvh.ray_cast(Vector((side * .6, depth, height)), Vector((-side, 0, 0)), 1.2)[0] for depth in depths]
            values = [side * hit.x if hit is not None else None for hit in hits]
            expected = None
            residual = None
            if all(value is not None for value in values):
                inner = (values[1] + values[3]) / 2
                outer = (values[0] + values[4]) / 2
                expected = (4 * inner - outer) / 3
                residual = max(0, values[2] - expected)
            side_rows.append({
                "height_m": round(height, 6), "side": side,
                "depth_samples_m": depths,
                "lateral_extent_m": [round(value, 6) if value is not None else None for value in values],
                "smooth_center_estimate_m": round(expected, 6) if expected is not None else None,
                "center_ridge_residual_m": round(residual, 6) if residual is not None else None,
            })
    side_profiles[label] = side_rows

old_rise = max(row["secondary_lobe_rise_m"] for row in sections["source"])
new_rise = max(row["secondary_lobe_rise_m"] for row in sections["result"])
coverage = all(all(value is not None for value in row["depth_m"][:5]) for row in sections["result"])
report["cross_section_analysis"] = {
    "axis": "Blender world coordinates: X lateral, Y front/rear, Z up",
    "absolute_x_samples_m": x_samples,
    "sample_rows_per_model": len(sections["result"]),
    "samples": sections,
    "required_chest_to_arm_samples_present": coverage,
    "maximum_secondary_lobe_rise_source_m": old_rise,
    "maximum_secondary_lobe_rise_result_m": new_rise,
    "maximum_secondary_lobe_rise_reduction_percent": round((1 - new_rise / old_rise) * 100, 2) if old_rise else None,
}
side_coverage = all(row["center_ridge_residual_m"] is not None for row in side_profiles["result"])
ridge = max((row["center_ridge_residual_m"] for row in side_profiles["result"] if row["center_ridge_residual_m"] is not None), default=1)
report["lateral_shoulder_ridge_analysis"] = {
    "method": "Side rays compare Y=0 lateral extent with a parabola through average Y=+/-0.02m and +/-0.04m extents; positive residual denotes an isolated center fin.",
    "samples": side_profiles,
    "all_required_samples_present": side_coverage,
    "maximum_result_center_ridge_residual_m": ridge,
    "limit_m": .0025,
    "pass": side_coverage and ridge <= .0025,
}
# The final loop above leaves the result garment BVH active. A valid shoulder
# fairing must not lift the hidden neck floor back into the donor neck opening.
neck_probes = []
for x in [-.035, 0, .035]:
    for depth in [-.035, 0, .035]:
        hit = bvh.ray_cast(Vector((x, depth, 1.55)), Vector((0, 0, -1)), .4)[0]
        neck_probes.append({
            "x_m": x, "depth_m": depth,
            "highest_garment_hit_m": round(hit.z, 6) if hit is not None else None,
            "pass": hit is not None and hit.z < 1.445,
        })
report["neck_opening_probes"] = neck_probes
report["pass"] = (
    len(result) == 20 and not report["unexpected_mesh_set_changes"]
    and report["preserved_mesh_count"] == 17 and report["embedded_images_preserved"]
    and all(row["pass"] for row in report["geometry_preserved_below_1_18m"].values())
    and coverage and new_rise < .004 and all(probe["pass"] for probe in neck_probes)
    and report["lateral_shoulder_ridge_analysis"]["pass"]
)
report["visual_review"] = {
    "status": "pending",
    "scope": "Geometry continuity and volume improvement do not imply visual acceptance. Await actual Godot front, rear, three-quarter and clay captures.",
}
(HERE / "geometry_audit.json").write_text(json.dumps(report, indent=2) + "\n")
print("SHOULDER GEOMETRY AUDIT", "PASS" if report["pass"] else "FAIL", result_hash)
print("Unchanged meshes:", report["preserved_mesh_count"], "Secondary lobe rise:", old_rise, "->", new_rise)
assert report["pass"], "Review geometry_audit.json for the failed checks."
