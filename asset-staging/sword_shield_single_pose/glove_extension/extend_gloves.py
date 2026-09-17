#!/usr/bin/env python3
"""Append fitted fingerless leather to corrected hand GLBs, using stdlib only.

No existing accessor, mesh, material, joint, skin or rigid sleeve is modified.
The added shell is clipped from the actual weighted proximal skin triangles;
new boundary vertices barycentrically inherit their source skin influences.
The source GLB's Y-up node transforms, not Blender's old global Y heuristic,
define each proximal phalanx and its finger opening.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import struct

STAGE = Path(__file__).resolve().parent
SOURCES = STAGE / "source_corrected_arms"
CORRECTED = STAGE.parent / "corrected_arms"
DIGITS = ("little", "ring", "middle", "index", "thumb")
COMPONENTS = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def sha(data): return hashlib.sha256(data).hexdigest()
def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, s): return tuple(x * s for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def length(a): return math.sqrt(dot(a, a))
def unit(a): return mul(a, 1 / max(1e-15, length(a)))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def mix(a, b, t): return add(mul(a, 1-t), mul(b, t))
def identity(): return [[float(i == j) for j in range(4)] for i in range(4)]
def mm(a, b): return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def point(m, p): return tuple(sum(m[i][j]*p[j] for j in range(3))+m[i][3] for i in range(3))


def node_matrix(node):
    if "matrix" in node: return [[node["matrix"][j*4+i] for j in range(4)] for i in range(4)]
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    n = math.sqrt(x*x+y*y+z*z+w*w)
    x, y, z, w = x/n, y/n, z/n, w/n
    m = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w), 0],
         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w), 0],
         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y), 0], [0, 0, 0, 1]]
    scale = node.get("scale", [1, 1, 1])
    for i in range(3):
        for j in range(3): m[i][j] *= scale[j]
        m[i][3] = node.get("translation", [0, 0, 0])[i]
    return m


class GLB:
    def __init__(self, data):
        assert struct.unpack_from("<4sII", data) == (b"glTF", 2, len(data))
        size, kind = struct.unpack_from("<II", data, 12)
        assert kind == 0x4E4F534A
        self.doc = json.loads(data[20:20+size])
        count, kind = struct.unpack_from("<II", data, 20+size)
        assert kind == 0x004E4942 and 28+size+count == len(data)
        self.binary = bytearray(data[28+size:])

    def read(self, index):
        a = self.doc["accessors"][index]
        assert "sparse" not in a and not a.get("normalized")
        v = self.doc["bufferViews"][a["bufferView"]]
        fmt = "<"+COMPONENTS[a["componentType"]]*WIDTH[a["type"]]
        offset = v.get("byteOffset", 0)+a.get("byteOffset", 0)
        stride = v.get("byteStride", struct.calcsize(fmt))
        return [struct.unpack_from(fmt, self.binary, offset+i*stride) for i in range(a["count"])]

    def append(self, rows, kind, component=5126, target=34962):
        self.binary.extend(b"\0"*(-len(self.binary)%4))
        offset = len(self.binary)
        fmt = "<"+COMPONENTS[component]*WIDTH[kind]
        self.binary.extend(b"".join(struct.pack(fmt, *row) for row in rows))
        view = len(self.doc["bufferViews"])
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(self.binary)-offset, "target": target})
        accessor = {"bufferView": view, "componentType": component, "count": len(rows), "type": kind}
        if kind == "VEC3":
            accessor.update(min=[min(r[k] for r in rows) for k in range(3)], max=[max(r[k] for r in rows) for k in range(3)])
        result = len(self.doc["accessors"])
        self.doc["accessors"].append(accessor)
        return result

    def encode(self):
        self.binary.extend(b"\0"*(-len(self.binary)%4))
        self.doc["buffers"][0]["byteLength"] = len(self.binary)
        document = json.dumps(self.doc, ensure_ascii=False, separators=(",", ":")).encode()
        document += b" "*(-len(document)%4)
        return (struct.pack("<4sII", b"glTF", 2, 28+len(document)+len(self.binary))
                +struct.pack("<II", len(document), 0x4E4F534A)+document
                +struct.pack("<II", len(self.binary), 0x004E4942)+self.binary)


def interpolate(a, b, t):
    result = {k: mix(a[k], b[k], t) for k in ("p", "n", "uv", "tangent")}
    result["weights"] = {j: a["weights"].get(j, 0)*(1-t)+b["weights"].get(j, 0)*t for j in a["weights"].keys() | b["weights"].keys()}
    return result


def clip(poly, scalar, boundary, keep_greater):
    out = []
    for a, b in zip(poly, poly[1:]+poly[:1]):
        av, bv = scalar(a)-boundary, scalar(b)-boundary
        inside_a = av >= -1e-12 if keep_greater else av <= 1e-12
        inside_b = bv >= -1e-12 if keep_greater else bv <= 1e-12
        if inside_a: out.append(a)
        if inside_a != inside_b: out.append(interpolate(a, b, av/(av-bv)))
    return out


def encode_primitive(glb, vertices, triangles, material):
    attrs = {"POSITION": glb.append([v["p"] for v in vertices], "VEC3"),
             "NORMAL": glb.append([unit(v["n"]) for v in vertices], "VEC3"),
             "TEXCOORD_0": glb.append([v["uv"] for v in vertices], "VEC2")}
    tangents, joints, weights = [], [], []
    for v in vertices:
        n = unit(v["n"])
        tangent = unit(sub(v["tangent"][:3], mul(n, dot(v["tangent"][:3], n))))
        if length(tangent) < .5: tangent = unit(cross(n, (0, 1, 0) if abs(n[1]) < .9 else (1, 0, 0)))
        tangents.append(tangent+(v["tangent"][3],))
        influence = sorted(((j, w) for j, w in v["weights"].items() if w > 1e-8), key=lambda jw: -jw[1])
        # All source skin triangles use at most four nonzero influences. Do not
        # silently truncate a clipped edge's inherited weight vector.
        assert len(influence) <= 4, influence
        total = sum(w for _, w in influence)
        assert abs(total-1.0) < 2e-6, total
        influence += [(0, 0)]*(4-len(influence))
        joints.append(tuple(j for j, _ in influence))
        weights.append(tuple(w for _, w in influence))
    attrs["TANGENT"] = glb.append(tangents, "VEC4")
    attrs["JOINTS_0"] = glb.append(joints, "VEC4", 5121)
    attrs["WEIGHTS_0"] = glb.append(weights, "VEC4")
    indices = glb.append([(v,) for tri in triangles for v in tri], "SCALAR", 5125, 34963)
    return {"attributes": attrs, "indices": indices, "material": material, "mode": 4}


def extend(side):
    source_path = SOURCES/f"{side}_arm.glb"
    if not source_path.exists(): source_path.write_bytes((CORRECTED/source_path.name).read_bytes())
    source = source_path.read_bytes()
    glb = GLB(source)
    before = copy.deepcopy(glb.doc)
    original_binary = bytes(glb.binary)
    nodes = glb.doc["nodes"]
    lookup = {n["name"].split(".")[0]: i for i, n in enumerate(nodes)}
    parents = {child: i for i, n in enumerate(nodes) for child in n.get("children", [])}
    transforms = {}
    def global_transform(index):
        if index not in transforms:
            transforms[index] = mm(global_transform(parents[index]) if index in parents else identity(), node_matrix(nodes[index]))
        return transforms[index]
    skin_node = nodes[lookup["ContinuousAnatomicalHand"]]
    assert node_matrix(skin_node) == identity() and global_transform(lookup["HandRig"]) == identity()
    skin = glb.doc["skins"][skin_node["skin"]]
    names = [nodes[j]["name"] for j in skin["joints"]]
    skin_primitive = glb.doc["meshes"][skin_node["mesh"]]["primitives"][0]
    attrs = {k: glb.read(a) for k, a in skin_primitive["attributes"].items()}
    vertices = []
    for i, p in enumerate(attrs["POSITION"]):
        vertices.append({"p": p, "n": attrs["NORMAL"][i], "uv": attrs["TEXCOORD_0"][i], "tangent": attrs["TANGENT"][i],
                         "weights": {j: w for j, w in zip(attrs["JOINTS_0"][i], attrs["WEIGHTS_0"][i]) if w > 0}})
    indices = [v[0] for v in glb.read(skin_primitive["indices"])]
    triangles = [indices[i:i+3] for i in range(0, len(indices), 3)]
    material = next(i for i, m in enumerate(glb.doc["materials"]) if m["name"] == "FP_WornLeather")
    edge_material = next(i for i, m in enumerate(glb.doc["materials"]) if m["name"] == "FP_LeatherEdge")
    primitives, reports = [], []
    all_shell_vertices, all_shell_faces, all_rim_vertices, all_rim_faces = [], [], [], []
    for digit in DIGITS:
        # Thumb0 is the metacarpal (CMC); thumb1 is the true proximal
        # phalanx (MCP to IP). The existing global palm mask already covers
        # thumb0 completely, so extending it would add no finger coverage.
        proximal_bone = 1 if digit == "thumb" else 0
        start = point(global_transform(lookup[digit+str(proximal_bone)]), (0, 0, 0))
        end = point(global_transform(lookup[digit+str(proximal_bone+1)]), (0, 0, 0))
        axis, span = unit(sub(end, start)), length(sub(end, start))
        upper = .65 if digit == "thumb" else .80
        lower = 0.0 if digit == "thumb" else .20
        def fraction(v): return dot(sub(v["p"], start), axis)/span
        flat_vertices, faces, cache = [], [], {}
        def vertex_index(v):
            key = tuple(round(x, 10) for x in v["p"]+v["n"]+v["uv"])+tuple(sorted((j, round(w, 10)) for j, w in v["weights"].items()))
            if key not in cache:
                cache[key] = len(flat_vertices)
                flat_vertices.append(v)
            return cache[key]
        for triangle in triangles:
            poly = [vertices[i] for i in triangle]
            totals = {name: sum(w for v in poly for j, w in v["weights"].items() if names[j].startswith(name)) for name in DIGITS}
            if max(totals, key=totals.get) != digit or totals[digit] < .6: continue
            poly = clip(poly, fraction, lower, True)
            if len(poly) < 3: continue
            poly = clip(poly, fraction, upper, False)
            if len(poly) < 3: continue
            ids = [vertex_index(v) for v in poly]
            for i in range(1, len(ids)-1):
                tri = (ids[0], ids[i], ids[i+1])
                a, b, c = [flat_vertices[k]["p"] for k in tri]
                if length(cross(sub(b, a), sub(c, a))) > 1e-12: faces.append(tri)
        assert len(faces) > 100, (side, digit, len(faces))
        outer, inner = [], []
        for v in flat_vertices:
            # GLB (x,y,z) corresponds to Blender (x,-z,y). Match the existing
            # tiny leather wrinkles; an extra .3mm avoids coincident overlap.
            normal = unit(v["n"])
            outer_offset = .00225+.0005*math.sin(-v["p"][2]*220+v["p"][0]*80)
            a, b = copy.deepcopy(v), copy.deepcopy(v)
            a["p"] = add(v["p"], mul(normal, outer_offset))
            b["p"] = add(v["p"], mul(normal, outer_offset-.0015))
            b["n"] = mul(normal, -1)
            b["tangent"] = b["tangent"][:3]+(-b["tangent"][3],)
            outer.append(a); inner.append(b)
        count = len(outer)
        shell = outer+inner
        shell_faces = faces+[(c+count, b+count, a+count) for a, b, c in faces]
        base = len(all_shell_vertices)
        all_shell_vertices.extend(shell)
        all_shell_faces.extend(tuple(i+base for i in triangle) for triangle in shell_faces)
        # Detect actual topological boundary edges after position welding, so
        # UV seams do not incorrectly receive a rim across the finger surface.
        edges = {}
        def position_key(i): return tuple(round(x, 8) for x in flat_vertices[i]["p"])
        for a, b, c in faces:
            for i, j in ((a,b), (b,c), (c,a)):
                key = tuple(sorted((position_key(i), position_key(j))))
                edges.setdefault(key, []).append((i, j))
        rim_vertices, rim_faces = [], []
        boundary_types = {"overlap_start": 0, "finger_opening": 0, "other": 0}
        other_boundary_fractions = []
        for edge in edges.values():
            if len(edge) != 1: continue
            a, b = edge[0]
            midpoint_fraction = (fraction(flat_vertices[a])+fraction(flat_vertices[b]))*.5
            boundary_types["overlap_start" if abs(midpoint_fraction-lower) < 1e-5 else "finger_opening" if abs(midpoint_fraction-upper) < 1e-5 else "other"] += 1
            if abs(midpoint_fraction-lower) >= 1e-5 and abs(midpoint_fraction-upper) >= 1e-5: other_boundary_fractions.append(midpoint_fraction)
            quad = [copy.deepcopy(outer[a]), copy.deepcopy(inner[a]), copy.deepcopy(inner[b]), copy.deepcopy(outer[b])]
            normal = unit(cross(sub(quad[1]["p"], quad[0]["p"]), sub(quad[2]["p"], quad[0]["p"])))
            for v in quad: v["n"] = normal
            index = len(rim_vertices)
            rim_vertices.extend(quad)
            rim_faces.extend([(index,index+1,index+2),(index,index+2,index+3)])
        assert len(rim_faces) > 10
        base = len(all_rim_vertices)
        all_rim_vertices.extend(rim_vertices)
        all_rim_faces.extend(tuple(i+base for i in triangle) for triangle in rim_faces)
        reports.append({"digit": digit, "actual_proximal_bone": digit+str(proximal_bone), "actual_proximal_root_y_up": start, "actual_next_joint_root_y_up": end,
                        "actual_proximal_axis_y_up": axis, "proximal_length_m": span,
                        "opening_fraction": upper, "overlap_start_fraction": lower,
                        "bare_distance_before_middle_joint_m": (1-upper)*span,
                        "outer_skin_offset_m": [0.00175,0.00275], "leather_thickness_m": .0015,
                        "source_skin_surface_triangles": len(faces), "added_triangles": len(shell_faces)+len(rim_faces),
                        "bound_edge_counts": boundary_types,
                        "other_boundary_fraction_bounds": [min(other_boundary_fractions), max(other_boundary_fractions)] if other_boundary_fractions else [],
                        "outer_bounds_y_up": {"min": [min(v["p"][k] for v in outer) for k in range(3)], "max": [max(v["p"][k] for v in outer) for k in range(3)]}})
    primitives.append(encode_primitive(glb, all_shell_vertices, all_shell_faces, material))
    primitives.append(encode_primitive(glb, all_rim_vertices, all_rim_faces, edge_material))
    mesh_index = len(glb.doc["meshes"])
    glb.doc["meshes"].append({"name": "ProximalFingerlessLeatherExtensions", "primitives": primitives})
    node_index = len(nodes)
    nodes.append({"name": "ProximalFingerlessLeatherExtensions", "mesh": mesh_index, "skin": skin_node["skin"],
                  "extras": {"source": "actual unchanged skin triangles", "coverage": "proximal80_thumb65", "skin_weight_method": "original values and barycentric boundary interpolation"}})
    nodes[lookup["HandRig"]]["children"].append(node_index)
    output = glb.encode()
    saved = GLB(output)
    assert bytes(saved.binary[:len(original_binary)]) == original_binary
    for key in ("skins", "materials", "images", "textures", "samplers", "scenes"):
        assert saved.doc.get(key) == before.get(key), key
    for key in ("meshes", "accessors", "bufferViews"):
        assert saved.doc[key][:len(before[key])] == before[key], key
    for index, node in enumerate(before["nodes"]):
        actual = copy.deepcopy(saved.doc["nodes"][index])
        if index == lookup["HandRig"]: actual["children"].remove(node_index)
        assert actual == node, (index, node["name"])
    path = STAGE/f"{side}_arm.glb"
    path.write_bytes(output)
    return {"file": path.name, "source_sha256": sha(source), "output_sha256": sha(output),
            "source_binary_sha256": sha(original_binary), "preserved_binary_prefix_sha256": sha(saved.binary[:len(original_binary)]),
            "original_binary_bytes_preserved": len(original_binary), "appended_binary_bytes": len(saved.binary)-len(original_binary),
            "original_nodes_unchanged_except_one_appended_child": True, "all_original_meshes_and_accessors_unchanged": True,
            "all_skin_geometry_normals_uv_weights_unchanged": True, "all_original_glove_geometry_unchanged": True,
            "joint_transforms_and_inverse_bind_matrices_unchanged": True, "all_rigid_sleeves_unchanged": True,
            "materials_textures_images_unchanged": True, "existing_skin_index_reused": skin_node["skin"],
            "new_mesh_nodes": 1, "new_surfaces": len(primitives), "digits": reports}


def main():
    SOURCES.mkdir(parents=True, exist_ok=True)
    report = {"method": "Append fitted leather only; no original binary edits", "coordinate_system": "GLB Y up; actual transformed proximal bone axes", "arms": [extend(side) for side in ("left", "right")], "gpu_and_engine_validation": "Not run; root performs production import and gameplay captures"}
    (STAGE/"preservation_report.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps({"outputs": [{k:a[k] for k in ("file", "source_sha256", "output_sha256", "appended_binary_bytes")} for a in report["arms"]]}, indent=2))


if __name__ == "__main__": main()
