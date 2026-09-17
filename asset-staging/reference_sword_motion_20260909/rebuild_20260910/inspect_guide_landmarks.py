"""Read original GLB vertices/indices only. No Blender, rendering or motion synthesis."""
from pathlib import Path
import hashlib
import json
import math
import struct

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "godot-game/assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
CONSTANTS = json.loads(Path(__file__).with_name("GODOT_ARM_CONSTANTS.json").read_text())
S = CONSTANTS["source_ready_matrix_rows"]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def point(m, v):
    return [sum(m[i][j] * v[j] for j in range(3)) + m[i][3] for i in range(3)]


def inverse(m):
    a = [list(m[i]) + [float(i == j) for j in range(4)] for i in range(4)]
    for j in range(4):
        pivot = max(range(j, 4), key=lambda i: abs(a[i][j]))
        a[j], a[pivot] = a[pivot], a[j]
        scale = a[j][j]
        a[j] = [v / scale for v in a[j]]
        for i in range(4):
            if i != j:
                scale = a[i][j]
                a[i] = [v - scale * w for v, w in zip(a[i], a[j])]
    return [row[4:] for row in a]


IDENTITY = [[float(i == j) for j in range(4)] for i in range(4)]
SI = inverse(S)


def node_matrix(node):
    if "matrix" in node:
        return [[node["matrix"][4 * j + i] for j in range(4)] for i in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    length = math.sqrt(x*x + y*y + z*z + w*w)
    x, y, z, w = x/length, y/length, z/length, w/length
    r = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    scale = node.get("scale", [1, 1, 1])
    translate = node.get("translation", [0, 0, 0])
    return [[r[i][j] * scale[j] for j in range(3)] + [translate[i]] for i in range(3)] + [[0, 0, 0, 1]]


blob = SOURCE.read_bytes()
assert hashlib.sha256(blob).hexdigest() == CONSTANTS["source"]["sha256"]
magic, version, total = struct.unpack_from("<III", blob)
assert magic == 0x46546C67 and version == 2 and total == len(blob)
chunks = {}
offset = 12
while offset < len(blob):
    size, kind = struct.unpack_from("<II", blob, offset)
    chunks[kind] = blob[offset+8:offset+8+size]
    offset += 8 + size
gltf = json.loads(chunks[0x4E4F534A])
binary = chunks[0x004E4942]


def accessor(index):
    data = gltf["accessors"][index]
    assert "sparse" not in data and not data.get("normalized", False)
    view = gltf["bufferViews"][data["bufferView"]]
    assert view["buffer"] == 0
    form = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[data["componentType"]]
    size = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[data["type"]]
    form = "<" + form * size
    offset = view.get("byteOffset", 0) + data.get("byteOffset", 0)
    stride = view.get("byteStride", struct.calcsize(form))
    return [struct.unpack_from(form, binary, offset + i * stride) for i in range(data["count"])]


def bounds(records, key="canonical"):
    return {"min": [min(r[key][i] for r in records) for i in range(3)],
            "max": [max(r[key][i] for r in records) for i in range(3)]}


meshes = {}


def visit(index, parent):
    node = gltf["nodes"][index]
    world = mul(parent, node_matrix(node))
    if "mesh" in node:
        records = []
        triangles = []
        for pi, primitive in enumerate(gltf["meshes"][node["mesh"]]["primitives"]):
            assert primitive.get("mode", 4) == 4
            ai = primitive["attributes"]["POSITION"]
            start = len(records)
            for vi, v in enumerate(accessor(ai)):
                camera = point(world, v)
                records.append({"node_index": index, "primitive": pi, "position_accessor": ai,
                                "vertex_index": vi, "raw": list(v), "source_camera": camera,
                                "canonical": point(SI, camera)})
            indices = [v[0] for v in accessor(primitive["indices"])]
            triangles += [tuple(start + n for n in indices[i:i+3]) for i in range(0, len(indices), 3)]
        meshes[node["name"]] = {"records": records, "triangles": triangles, "bounds": bounds(records)}
    for child in node.get("children", []):
        visit(child, world)


for index in gltf["scenes"][gltf.get("scene", 0)]["nodes"]:
    visit(index, IDENTITY)


def components(mesh):
    records = mesh["records"]
    parents = list(range(len(records)))

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    def join(i, j):
        parents[find(i)] = find(j)

    welded = {}
    for i, record in enumerate(records):
        key = tuple(round(v, 6) for v in record["canonical"])
        if key in welded:
            join(i, welded[key])
        else:
            welded[key] = i
    for a, b, c in mesh["triangles"]:
        join(a, b)
        join(a, c)
    groups = {}
    for i, record in enumerate(records):
        groups.setdefault(find(i), []).append(record)
    return sorted(groups.values(), key=lambda rs: bounds(rs)["min"][1])


def midpoint_bounds(records):
    box = bounds(records)
    return [(a + b) * 0.5 for a, b in zip(box["min"], box["max"])]


def evidence(records):
    groups = {}
    for row in records:
        groups.setdefault((row["node_index"], row["primitive"], row["position_accessor"]), set()).add(row["vertex_index"])
    result = []
    for (node, primitive, position), indices in sorted(groups.items()):
        ranges = []
        for index in sorted(indices):
            if ranges and ranges[-1][1] + 1 == index:
                ranges[-1][1] = index
            else:
                ranges.append([index, index])
        result.append({"node_index": node, "primitive": primitive, "POSITION_accessor": position,
                       "vertex_index_ranges_inclusive": ranges})
    return result


def landmark(label, rows, definition, confidence="high_geometry_medium_reference_2d_correspondence"):
    v = midpoint_bounds(rows)
    return {"label": label, "definition": definition, "canonical": v, "source_camera": point(S, v),
            "geometry_confidence": confidence, "support_bounds_canonical": bounds(rows),
            "support_record_count_including_seam_duplicates": len(rows), "evidence": evidence(rows)}


def build_guides():
    blade = meshes["Sword_PittedBlade"]["records"]
    groups = components(meshes["Sword_SwordsmanLongsword_Surface"])
    peen, pommel, lower_ferrule, upper_ferrule, guard = groups
    assert len(guard) == 424 and len(pommel) == 493 and len(peen) == 171
    guide = {
        "blade_tip_geometry": landmark("B", [r for r in blade if r["canonical"][1] > 1.0349], "Bounding center of actual terminal blade section, not nearest single split vertex."),
        "crossguard_axis_intersection": landmark("G", [r for r in guard if abs(r["canonical"][0]) < 1e-6], "Midpoint of crossguard root section on blade axis. Crossguard has thickness, so this is an explicit center convention, not a uniquely named GLB vertex."),
        "crossguard_left_end": landmark("GL", [r for r in guard if abs(r["canonical"][0] + .152) < 1e-6], "Bounding center of outermost negative-X quillon terminal section."),
        "crossguard_right_end": landmark("GR", [r for r in guard if abs(r["canonical"][0] - .152) < 1e-6], "Bounding center of outermost positive-X quillon terminal section."),
        "pommel_widest_section_center": landmark("P", [r for r in pommel if abs(r["canonical"][1] + .3442) < 1e-6], "Center of maximum-width pommel body section. Preferred repeatable body landmark; not an inferred object origin."),
        "pommel_body_bounds_center": landmark("P_bounds", pommel, "AABB center of the connected pommel body component; differs from its widest-section center."),
        "hilt_terminal_peen_center": landmark("P_end", [r for r in peen if abs(r["canonical"][1] + .3676) < 1e-6], "Center of actual lowest terminal peen section, separate from pommel body center."),
    }
    for key, code_key, label in [("hand_grip_marker", "hand_grip", "H"), ("wrist_anchor_code", "rest_wrist", "W")]:
        v = CONSTANTS["canonical_points"][code_key]
        guide[key] = {"label": label, "canonical": v, "source_camera": point(S, v),
                      "geometry_confidence": "code_anchor_not_unique_surface_vertex",
                      "definition": "Production grip contact anchor, not crossguard or wrist." if label == "H" else "Production sleeve wrist anchor, not grip center or a supplied bone; GLB has no skin/joint metadata.",
                      "code_source": "godot-game/scripts/sword_long_grip_visual.gd:8" if label == "H" else "godot-game/scripts/sword_long_grip_visual.gd:12"}
    sections = []
    for y in [-.01, .024, .046, .077, .16, .44, .71, .88, .947, .988, 1.014, 1.035]:
        rows = [r for r in blade if abs(r["canonical"][1] - y) < 1e-6]
        sections.append({"nominal_y": y, "center_canonical": midpoint_bounds(rows), "bounds_canonical": bounds(rows), "evidence": evidence(rows)})
    camera_direction = [S[i][1] for i in range(3)]
    norm = math.sqrt(sum(v*v for v in camera_direction))
    camera_direction = [v/norm for v in camera_direction]
    grip = meshes["Sword_GripLeather"]
    plane_points = []
    plane_records = []
    for tri in grip["triangles"]:
        vertices = [grip["records"][i]["canonical"] for i in tri]
        for a, b in zip(vertices, vertices[1:]+vertices[:1]):
            if min(a[1], b[1]) < -.108 < max(a[1], b[1]):
                t = (-.108 - a[1])/(b[1]-a[1])
                plane_points.append({"canonical": [a[i]+t*(b[i]-a[i]) for i in range(3)]})
                plane_records += [grip["records"][i] for i in tri]
    def distance(a, b):
        return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))
    g = guide["crossguard_axis_intersection"]["canonical"]
    h = guide["hand_grip_marker"]["canonical"]
    w = guide["wrist_anchor_code"]["canonical"]
    tip = guide["blade_tip_geometry"]["canonical"]
    result = {
        "status": "static_glb_vertex_measurements_not_authored_motion",
        "source": {"path": str(SOURCE.relative_to(ROOT)), "sha256": hashlib.sha256(blob).hexdigest(), "meshes": len(gltf["meshes"]), "skins": len(gltf.get("skins", [])), "animations": len(gltf.get("animations", []))},
        "units": "meters", "coordinate_space": "godot_camera_local_x_right_y_up_minus_z_forward",
        "source_camera_meaning": "Cumulative original GLB node transforms; this GLB is authored in the source camera arrangement. Not the new clip frame and not Blender world space.",
        "normalization": "canonical = inverse(SOURCE_READY) * source_camera; sample pose projects T(t) * canonical",
        "source_ready_matrix_rows": S,
        "precision_note": "Input POSITION accessors are float32. Extra decimal places expose the calculation, not submicron source accuracy.",
        "landmarks": guide,
        "blade_axis": {"canonical_origin": [0, 0, 0], "canonical_direction": [0, 1, 0], "source_camera_origin": point(S, [0, 0, 0]), "source_camera_direction_unit": camera_direction,
                       "max_sampled_section_center_distance_to_ideal_axis_m": max(math.hypot(s["center_canonical"][0], s["center_canonical"][2]) for s in sections), "section_measurements": sections},
        "measurements_m": {
            "crossguard_total_x_width": bounds(guard)["max"][0]-bounds(guard)["min"][0],
            "crossguard_end_center_distance": distance(guide["crossguard_left_end"]["canonical"], guide["crossguard_right_end"]["canonical"]),
            "crossguard_root_y_extent": [bounds([r for r in guard if abs(r["canonical"][0]) < 1e-6])[k][1] for k in ["min", "max"]],
            "pommel_body_max_x_width": bounds(pommel)["max"][0]-bounds(pommel)["min"][0],
            "pommel_body_max_z_depth": bounds(pommel)["max"][2]-bounds(pommel)["min"][2],
            "blade_total_axial_extent": bounds(blade)["max"][1]-bounds(blade)["min"][1],
            "blade_root_x_width": sections[0]["bounds_canonical"]["max"][0]-sections[0]["bounds_canonical"]["min"][0],
            "guard_G_to_tip_B_axial": tip[1]-g[1],
            "guard_G_to_hand_H_distance": distance(g, h),
            "guard_G_to_wrist_W_distance": distance(g, w),
            "hand_H_to_wrist_W_distance": distance(h, w),
            "blade_tip_code_marker_to_terminal_section_center": distance(CONSTANTS["canonical_points"]["blade_tip"], tip),
            "entire_metal_tip_to_peen_axial_extent": bounds(blade)["max"][1]-bounds(peen)["min"][1]},
        "hand_grip_geometry_check": {"node": "Sword_GripLeather", "plane_canonical_y": -.108, "triangle_plane_intersection_bounds": bounds(plane_points),
                                     "marker_z_from_blade_center_plane": .002, "claim": "Marker lies within the leather section X/Z bounds. It is an interior contact/axis reference, not an observed surface vertex or full extended-hilt midpoint.", "triangle_support": evidence(plane_records)},
        "metal_component_evidence": [{"interpretation": name, "record_count_including_seam_duplicates": len(rows), "bounds_canonical": bounds(rows), "evidence": evidence(rows)} for name, rows in [("terminal peen", peen), ("pommel body", pommel), ("lower hilt ferrule", lower_ferrule), ("upper hilt ferrule/collar", upper_ferrule), ("crossguard quillons", guard)]],
        "component_method": "Triangle connectivity after welding canonical POSITION coordinates rounded to 1e-6m across primitives. No original mesh modification.",
        "ambiguities": ["No supplied GLB marker explicitly names a crossguard center or pommel center. Definitions are geometry-based conventions with evidence.", "The guard is curved. The midpoint of its end centers has y about +0.016 and is not the root G at -0.009 (25mm difference).", "Visible blade/guard junction may refer to a front edge, center, or occluded outline. Match the same explicit G convention in model overlay and reference annotation.", "The wrist is a production code anchor, not a bone location independently stored in this static GLB.", "Reference video 3D depths and correspondence are not established by these static GLB measurements."]}
    target = Path(__file__).with_name("GUIDE_LANDMARKS.json")
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    return result


if __name__ == "__main__":
    import sys
    if "--write-guides" in sys.argv:
        result = build_guides()
        print(json.dumps({"written": "GUIDE_LANDMARKS.json", "measurements_m": result["measurements_m"]}, indent=2))
        raise SystemExit
    for name, mesh in meshes.items():
        if name.startswith("Sword_"):
            print(name, json.dumps(mesh["bounds"]))
    for group in components(meshes["Sword_SwordsmanLongsword_Surface"]):
        print("COMPONENT", len(group), json.dumps(bounds(group)))
