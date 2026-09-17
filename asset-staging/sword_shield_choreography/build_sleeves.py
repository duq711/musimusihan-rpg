"""Replace only the three rigid sleeve meshes; preserve all hand data verbatim.

Run with system Python. One background Blender run creates rigid geometry only.
The GLB splice retains the complete original binary chunk as an unchanged prefix,
so skin positions, normals, indices, UVs, weights, joints and inverse binds are not
round-tripped through Blender. No sword/shield file is read for writing.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys

STAGE = Path(__file__).resolve().parent
ROOT = STAGE.parents[1]
BASELINE = STAGE / "baseline_before_animation"
OUT = ROOT / "godot-game/assets/3d/player/sword_shield"
GENERATED = STAGE / "generated_sleeves"
PARTS = ("Forearm", "UpperArm", "WristCuff")


def read_glb(path):
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    assert magic == 0x46546C67 and version == 2 and length == len(data)
    chunks = {}
    cursor = 12
    while cursor < len(data):
        size, kind = struct.unpack_from("<II", data, cursor)
        chunks[kind] = data[cursor + 8:cursor + 8 + size]
        cursor += 8 + size
    return json.loads(chunks[0x4E4F534A]), chunks[0x004E4942]


def write_glb(path, document, binary):
    js = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
    js += b" " * (-len(js) % 4)
    binary += b"\0" * (-len(binary) % 4)
    data = struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(binary))
    data += struct.pack("<II", len(js), 0x4E4F534A) + js
    data += struct.pack("<II", len(binary), 0x004E4942) + binary
    Path(path).write_bytes(data)


def hand_fingerprint(document, binary):
    """Hash every skin primitive payload and all nodes outside the rigid parts."""
    digest = hashlib.sha256()
    protected = {"skins": document["skins"], "nodes": [], "meshes": []}
    accessors = set()
    for node in document["nodes"]:
        if not any(node.get("name", "").startswith(p) for p in PARTS):
            protected["nodes"].append(node)
        if "skin" in node:
            mesh = document["meshes"][node["mesh"]]
            protected["meshes"].append(mesh)
            for primitive in mesh["primitives"]:
                accessors.update(primitive["attributes"].values())
                accessors.add(primitive["indices"])
    for skin in document["skins"]:
        accessors.add(skin["inverseBindMatrices"])
    for index in sorted(accessors):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        digest.update(json.dumps(accessor, sort_keys=True).encode())
        digest.update(json.dumps(view, sort_keys=True).encode())
        start = view.get("byteOffset", 0)
        digest.update(binary[start:start + view["byteLength"]])
    digest.update(json.dumps(protected, sort_keys=True).encode())
    return digest.hexdigest()


def validate_rigid_surface(document, binary, mesh):
    """Catch inward tubular faces before installing a renderer-facing model."""
    def unpack_accessor(index):
        accessor = document["accessors"][index]
        view = document["bufferViews"][accessor["bufferView"]]
        width = {"SCALAR": 1, "VEC3": 3}[accessor["type"]]
        code = {5123: "H", 5125: "I", 5126: "f"}[accessor["componentType"]]
        fmt = "<" + code * width
        size = struct.calcsize(fmt)
        start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        return [struct.unpack_from(fmt, binary, start+i*view.get("byteStride",size)) for i in range(accessor["count"])]
    for primitive in mesh["primitives"]:
        material_name = document["materials"][primitive["material"]]["name"]
        if material_name not in ("FP_LayeredVambrace", "FP_QuiltedLinen"):
            continue
        positions = unpack_accessor(primitive["attributes"]["POSITION"])
        normals = unpack_accessor(primitive["attributes"]["NORMAL"])
        dots = [p[0]*n[0]+p[1]*n[1] for p,n in zip(positions,normals)]
        # The linen primitive also batches the round underarm seam, whose inner
        # half correctly faces toward the sleeve; the large fabric face must not.
        assert sum(d > .015 for d in dots) / len(dots) > .90, "Sleeve tube must have outward radial normals"
        indices = [v[0] for v in unpack_accessor(primitive["indices"])]
        for a,b,c in zip(indices[::3],indices[1::3],indices[2::3]):
            u = [positions[b][k]-positions[a][k] for k in range(3)]
            v = [positions[c][k]-positions[a][k] for k in range(3)]
            cross = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            assert sum(cross[k]*normals[a][k] for k in range(3)) >= -1e-9, "Triangle winding must match the visible sleeve normal"


def splice_sleeves(side):
    original, old_bin = read_glb(BASELINE / f"{side}_arm.glb")
    live, live_bin = read_glb(OUT / f"{side}_arm.glb")
    fingerprint = hand_fingerprint(original, old_bin)
    assert hand_fingerprint(live, live_bin) == fingerprint, "Live hand diverged from preserved baseline"
    fresh, new_bin = read_glb(GENERATED / f"{side}_sleeves.glb")
    assert not fresh.get("skins") and not fresh.get("animations")
    assert not fresh.get("images") and not fresh.get("textures")
    result = copy.deepcopy(original)
    offsets = {key: len(result.get(key, [])) for key in ("bufferViews", "accessors", "materials", "meshes")}
    for view in fresh["bufferViews"]:
        view = copy.deepcopy(view)
        assert view["buffer"] == 0
        view["byteOffset"] = view.get("byteOffset", 0) + len(old_bin)
        result["bufferViews"].append(view)
    for accessor in fresh["accessors"]:
        accessor = copy.deepcopy(accessor)
        assert "sparse" not in accessor
        accessor["bufferView"] += offsets["bufferViews"]
        result["accessors"].append(accessor)
    result["materials"].extend(fresh["materials"])
    for mesh in fresh["meshes"]:
        mesh = copy.deepcopy(mesh)
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4 and not primitive.get("targets")
            primitive["attributes"] = {k: v + offsets["accessors"] for k, v in primitive["attributes"].items()}
            primitive["indices"] += offsets["accessors"]
            primitive["material"] += offsets["materials"]
        result["meshes"].append(mesh)
    counts = {}
    for part in PARTS:
        nodes = [n for n in fresh["nodes"] if n.get("name") == part + "_Surface"]
        assert len(nodes) == 1
        new_node = nodes[0]
        # The original articulation nodes and imported rest axes must stay intact.
        assert not any(k in new_node for k in ("matrix", "translation", "rotation", "scale"))
        old_nodes = [n for n in result["nodes"] if n.get("name", "").startswith(part) and "mesh" in n]
        assert len(old_nodes) == 1
        old_nodes[0]["mesh"] = new_node["mesh"] + offsets["meshes"]
        mesh = result["meshes"][old_nodes[0]["mesh"]]
        validate_rigid_surface(result, old_bin + new_bin, mesh)
        counts[part] = {
            "surfaces": len(mesh["primitives"]),
            "vertices": sum(result["accessors"][p["attributes"]["POSITION"]]["count"] for p in mesh["primitives"]),
            "triangles": sum(result["accessors"][p["indices"]]["count"] // 3 for p in mesh["primitives"]),
        }
    combined = old_bin + new_bin
    result["buffers"][0]["byteLength"] = len(combined)
    assert combined[:len(old_bin)] == old_bin
    assert hand_fingerprint(result, combined) == fingerprint
    # These checks also prevent accidentally retaining a newly generated hand.
    assert result["skins"] == original["skins"] and len(result["nodes"]) == len(original["nodes"])
    # Stage first. Root installs these only when the active renderer capture ends.
    path = GENERATED / f"{side}_arm.glb"
    write_glb(path, result, combined)
    after, after_bin = read_glb(path)
    assert hand_fingerprint(after, after_bin) == fingerprint
    return {"side": side, "parts": counts, "protected_hand_sha256": fingerprint,
            "original_binary_bytes_preserved": len(old_bin), "new_rigid_binary_bytes": len(new_bin),
            "bones": len(original["skins"][0]["joints"]), "node_count": len(result["nodes"])}


def blender_stage():
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    GENERATED.mkdir(parents=True, exist_ok=True)

    def material(name, color, roughness, metal=0):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        shader = mat.node_tree.nodes.get("Principled BSDF")
        shader.inputs["Base Color"].default_value = (*color, 1)
        shader.inputs["Roughness"].default_value = roughness
        shader.inputs["Metallic"].default_value = metal
        mat.diffuse_color = (*color, 1)
        return mat

    leather = material("FP_LayeredVambrace", (.20, .13, .075), .82)
    strap = material("FP_SleeveStrap", (.105, .063, .032), .82)
    edge = material("FP_LeatherEdge", (.11, .071, .040), .86)
    cloth = material("FP_QuiltedLinen", (.105, .108, .102), .94)
    thread = material("FP_WaxedThread", (.18, .137, .080), .91)
    buckle = material("FP_SleeveBuckles", (.22, .225, .21), .67, .48)

    def obj_mesh(name, vertices, faces, mat, uvs=None):
        data = bpy.data.meshes.new(name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        data.materials.append(mat)
        layer = data.uv_layers.new(name="UVMap")
        for face in data.polygons:
            face.use_smooth = True
            for li in face.loop_indices:
                vi = data.loops[li].vertex_index
                v = data.vertices[vi].co
                layer.data[li].uv = uvs[vi] if uvs else (v.x * 6, -v.y * 6)
        return obj

    def cord(name, points, radius, mat):
        data = bpy.data.curves.new(name, "CURVE")
        data.dimensions = "3D"
        data.resolution_u = 1
        data.bevel_depth = radius
        data.bevel_resolution = 1
        spline = data.splines.new("POLY")
        spline.points.add(len(points) - 1)
        for dst, point in zip(spline.points, points):
            dst.co = (*point, 1)
        obj = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(obj)
        data.materials.append(mat)
        return obj

    def ring_surface(name, start, end, profile, mat, rows=38, columns=56, cap=False):
        vertices, faces, uvs = [], [], []
        for row in range(rows):
            t = row / (rows - 1)
            s = start + (end - start) * t
            for col in range(columns + 1):
                a = math.tau * col / columns
                vertices.append(profile(s, a))
                # Meter-scaled UVs avoid stretching short straps into coarse grain.
                uvs.append((col / columns * 2, s * 7))
        for row in range(rows - 1):
            for col in range(columns):
                i = row * (columns + 1) + col
                faces.append((i, i + 1, i + columns + 2, i + columns + 1))
        if cap:
            faces += [tuple(reversed(range(columns))), tuple((rows - 1) * (columns + 1) + i for i in range(columns))]
        return obj_mesh(name, vertices, faces, mat, uvs)

    def export_parts(parts, side):
        for label, objects in parts.items():
            bpy.ops.object.select_all(action="DESELECT")
            for obj in objects:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = objects[0]
            bpy.ops.object.convert(target="MESH")
            bpy.ops.object.join()
            obj = bpy.context.object
            obj.name = label + "_Surface"
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            triangulate = obj.modifiers.new("Stable triangulation", "TRIANGULATE")
            bpy.ops.object.modifier_apply(modifier=triangulate.name)
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=str(GENERATED / f"{side}_sleeves.glb"), export_format="GLB",
                                 use_selection=True, export_apply=True, export_animations=False,
                                 export_yup=True, export_skins=False, export_normals=True,
                                 export_tangents=True, export_image_format="NONE")
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)

    for side in ("left", "right"):
        sign = -1 if side == "left" else 1
        elbow_radius = .065 if side == "left" else .072
        shoulder_radius = .082 if side == "left" else .091
        parts = {p: [] for p in PARTS}
        fore = parts["Forearm"]
        upper = parts["UpperArm"]
        cuff = parts["WristCuff"]

        def fore_profile(s, a, extra=0):
            t = max(0, min(1, s / .27))
            base = .044 + (elbow_radius - .044) * t ** .8
            # Long shallow creases, unequal swelling and a lapped inner seam.
            fold = .0007 * math.sin(a * 5 + t * 4) + .00045 * math.sin(a * 11 - t * 17)
            fold += .0015 * math.sin(a + .3) * math.sin(t * math.pi)
            r = base + fold + extra
            return (math.cos(a) * r, -s, math.sin(a) * r * .81)

        fore.append(ring_surface("FittedLeather", .025, .271, fore_profile, leather, rows=43))
        for s in (.029, .267):
            fore.append(cord("TurnedBracerHem", [fore_profile(s, math.tau*i/80, .0008) for i in range(81)], .0009, edge))
        # A single long overlapping side seam, not concentric metal-looking lames.
        for angle in (.26, math.pi - .26):
            fore.append(cord("LappedLeatherEdge", [fore_profile(.032 + .23*i/44, angle, .0011) for i in range(45)], .00075, edge))
            for j in range(23):
                s = .04 + j * .0095
                fore.append(cord("HandStitchedEdge", [fore_profile(s + d, angle + .035, .0018) for d in (-.00135, .00135)], .00036, thread))

        for s, width in ((.083, .017), (.207, .020)):
            fore.append(ring_surface("BroadLeatherStrap", s-width/2, s+width/2,
                                     lambda q,a: fore_profile(q,a,.0026), strap, rows=4))
            for edge_s in (s-width/2, s+width/2):
                fore.append(cord("StrapBoundEdge", [fore_profile(edge_s,math.tau*i/72,.0030) for i in range(73)], .00065, edge))
            # Buckle sits on the dorsal/outer quadrant. Two real open rectangles,
            # each with a crossbar and tongue, follow the leather tangent plane.
            angle = .98 if sign > 0 else math.pi - .98
            center = Vector(fore_profile(s, angle, .0061))
            tangent = Vector((-math.sin(angle),0,math.cos(angle)*.81)).normalized()
            length = Vector((0,-1,0))
            normal = tangent.cross(length).normalized()
            w, h = .014, width*.63
            pts = [center+tangent*x+length*y for x,y in [(-w/2,-h/2),(w/2,-h/2),(w/2,h/2),(-w/2,h/2),(-w/2,-h/2)]]
            fore.append(cord("OpenIronBuckle", pts,.00115,buckle))
            fore.append(cord("BuckleBar",[center-length*h/2,center+length*h/2],.0009,buckle))
            fore.append(cord("BuckleTongue",[center+normal*.0003,center+tangent*w*.55+normal*.001],.0008,buckle))

        def upper_profile(s, a):
            t = max(0,min(1,(s-.224)/.382))
            base = elbow_radius-.004 + (shoulder_radius-elbow_radius+.004)*math.sin(t*math.pi/2)**.82
            elbow = math.exp(-((s-.272)/.055)**2)
            # Compression wrinkles peak inside the elbow; upper cloth hangs in
            # fewer broad longitudinal folds with asymmetric real silhouette.
            inside = .3+.7*max(0,math.cos(a-.6))**2
            fold = elbow*inside*(.0038*math.sin((s-.225)*151+1.7*math.sin(a))+.0020*math.sin((s-.22)*241-2*a))
            fold += (.0007+.0017*t)*math.sin(a*5+t*3.1)+.0008*math.sin(a*9-t*4)
            fold += .002*math.sin(t*math.pi)*math.sin(a-1.2)
            r = base+fold
            return (math.cos(a)*r+sign*.003*math.sin(t*math.pi), -s,
                    math.sin(a)*r*(.82+.055*t))

        upper.append(ring_surface("TailoredClothSleeve",.224,.606,upper_profile,cloth,rows=63,columns=64))
        # Low raised underarm seam; no diagonal wire grid or repeated ring seams.
        seam_angle = 4.7 if sign > 0 else 4.5
        upper.append(cord("UnderarmTailorSeam",[upper_profile(.229+.371*i/68,seam_angle) for i in range(69)],.00075,cloth))

        def cuff_profile(s,a):
            t = max(0,min(1,(s+.012)/.073))
            rx = .0448+.0042*math.sin(t*math.pi/2)
            rz = .0324+.0040*t
            fold = .00035*math.sin(a*5+t*8)
            return (math.cos(a)*(rx+fold),-s,math.sin(a)*(rz+fold))

        cuff.append(ring_surface("NarrowWristConnection",-.012,.061,cuff_profile,leather,rows=12,columns=48))
        for s in (-.006,.054):
            cuff.append(cord("WristBoundEdge",[cuff_profile(s,math.tau*i/64) for i in range(65)],.00065,edge))
        export_parts(parts,side)


def main():
    if "--blender-stage" in sys.argv:
        blender_stage()
        return
    GENERATED.mkdir(parents=True, exist_ok=True)
    if "--splice-only" not in sys.argv:
        subprocess.run(["/Applications/Blender.app/Contents/MacOS/Blender", "--background", "--factory-startup",
                        "--python", str(Path(__file__).resolve()), "--", "--blender-stage"], check=True)
    report = {"contract": "Rigid geometry only; original skin binary and 16 bones preserved exactly",
              "fit_endpoints_godot_z": {"forearm": [0,.26], "upper_arm": [.26,.60]},
              "arms": [splice_sleeves(side) for side in ("left", "right")]}
    (GENERATED / "sleeve_build_report.json").write_text(json.dumps(report, indent=2)+"\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
