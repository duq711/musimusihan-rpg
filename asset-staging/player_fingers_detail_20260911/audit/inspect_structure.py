"""Read the approved proportion source without modifying or saving it."""
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

DIGITS = ("thumb", "index", "middle", "ring", "little")

workspace = Path(__file__).resolve().parents[3]
source = workspace / "asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend"
support = workspace / "asset-staging/player_hands_realism_20260911/tools/verify_hands_realistic.py"
digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
before = digest(source)
spec = importlib.util.spec_from_file_location("finger_structure_support", support)
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)
assert bpy.app.background
bpy.ops.wm.open_mainfile(filepath=str(source))
scene = bpy.data.scenes["Bilateral_Realistic_Review"]
legacy.core.activate(scene)
rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: legacy.core.wrist_world(o).x)
report = {"source": str(source), "source_sha256": before, "scene": scene.name,
          "native_axes": {"fingers": "+Y", "dorsum": "+Z", "forearm": "-Y"}, "hands": {}}
for side, rig in zip(("left", "right"), rigs):
    native = legacy.native_matrix(rig, rig)
    parts = legacy.parts_for(scene, rig)
    row = {"bones": {b.name: {"parent": b.parent.name if b.parent else None,
            "head_native_m": list(native @ b.head_local), "tail_native_m": list(native @ b.tail_local),
            "local_x_native": list((native.to_3x3() @ b.matrix_local.to_3x3().col[0]).normalized())} for b in rig.data.bones}, "parts": {}}
    for label, obj in parts.items():
        mesh = obj.data
        mesh.calc_loop_triangles()
        points = np.asarray([legacy.native_matrix(obj, rig) @ v.co for v in mesh.vertices])
        weights = [{obj.vertex_groups[g.group].name: float(g.weight) for g in v.groups} for v in mesh.vertices]
        roles = [legacy.role(m) for m in mesh.materials]
        by_material = {}
        for role in roles:
            faces = [p for p in mesh.polygons if roles[p.material_index] == role]
            vertices = set(v for p in faces for v in p.vertices)
            by_material[role] = {"polygons": len(faces), "triangles": sum(len(p.vertices)-2 for p in faces), "vertices": len(vertices)}
        keys = {}
        if mesh.shape_keys:
            base = np.asarray([p.co for p in mesh.shape_keys.key_blocks[0].data])
            for key in mesh.shape_keys.key_blocks[1:]:
                delta = np.asarray([p.co for p in key.data]) - base
                lengths = np.linalg.norm(delta, axis=1)
                keys[key.name] = {"relative_key": key.relative_key.name, "value": key.value,
                    "nonzero_vertices": int(np.count_nonzero(lengths)), "max_delta_m": float(lengths.max()),
                    "active_gt_1um_vertices": int(np.count_nonzero(lengths >= 1e-6))}
        entry = {"object": obj.name, "vertices": len(mesh.vertices), "polygons": len(mesh.polygons),
            "triangles": len(mesh.loop_triangles), "materials": by_material,
            "bounds_native_m": [points.min(axis=0).tolist(), points.max(axis=0).tolist()],
            "uv_layers": [u.name for u in mesh.uv_layers],
            "active_uv": mesh.uv_layers.active.name if mesh.uv_layers.active else None,
            "shape_keys": keys, "modifiers": [{"type": m.type, "name": m.name} for m in obj.modifiers],
            "weight_bones": sorted({n for w in weights for n,v in w.items() if v > 0}),
            "metadata": {k: obj[k] for k in obj.keys() if str(k).startswith("wrist_flex_")}}
        if label == "hand":
            entry["physical_vertices"] = 12036
            entry["appended_original_glove_trim_vertices"] = len(mesh.vertices)-12036
            entry["physical_weighted_digit_counts"] = {d: sum(any(n.startswith(d) and w > 0 for n,w in weights[i].items()) for i in range(12036)) for d in legacy.core.FINGERS} if hasattr(legacy.core,"FINGERS") else {}
            entry["vertex_attributes"] = [(a.name, a.domain, a.data_type) for a in mesh.attributes]
        if label.startswith("nail_"):
            digit = label.removeprefix("nail_")
            entry["rigid_distal_weights_exact"] = all(w == {digit+"2": 1.0} for w in weights)
        row["parts"][label] = entry
    hand = parts["hand"]
    transform = legacy.native_matrix(hand, rig)
    skin_points = [transform @ v.co for v in hand.data.vertices[:12036]]
    groups = {g.index: g.name for g in hand.vertex_groups}
    own = [{d: sum(g.weight for g in v.groups if groups[g.group].startswith(d)) for d in DIGITS} for v in hand.data.vertices[:12036]]
    physical_faces = [list(p.vertices) for p in hand.data.polygons if max(p.vertices) < 12036]
    landmarks = {}
    for digit in DIGITS:
        selected = [f for f in physical_faces if sum(own[v][digit] for v in f) / len(f) > .6]
        digit_row = {}
        for joint in range(3):
            bone = rig.data.bones[digit + str(joint)]
            frame = native @ bone.matrix_local
            origin, axis = frame.translation, frame.to_3x3().col[1].normalized()
            cross = axis.cross(Vector((0,0,1))).normalized()
            dorsal = cross.cross(axis).normalized()
            hits = []
            for f in selected:
                for a,b in zip(f,f[1:]+f[:1]):
                    pa,pb = skin_points[a],skin_points[b]
                    da,db = (pa-origin).dot(axis),(pb-origin).dot(axis)
                    if (da < 0) != (db < 0): hits.append(pa+(pb-pa)*(da/(da-db)))
            entry = {"bone_head_native_m": list(origin), "bone_axis_native": list(axis), "plane_edge_intersections": len(hits)}
            if hits:
                u = [(p-origin).dot(cross) for p in hits]
                v = [(p-origin).dot(dorsal) for p in hits]
                center = origin+cross*((min(u)+max(u))*.5)+dorsal*((min(v)+max(v))*.5)
                entry.update({"surface_section_center_native_m":list(center), "width_m": max(u)-min(u), "depth_m": max(v)-min(v),
                    "dorsal_surface_native_m": list(center+dorsal*((max(v)-min(v))*.5)),
                    "palm_surface_native_m":list(center-dorsal*((max(v)-min(v))*.5)),
                    "bone_head_to_surface_center_m":(center-origin).length})
            digit_row[str(joint)] = entry
        nail = parts["nail_" + digit]
        nail_points = np.asarray([legacy.native_matrix(nail,rig) @ v.co for v in nail.data.vertices])
        digit_row["nail"] = {"centroid_native_m": nail_points.mean(axis=0).tolist(), "bounds_native_m": [nail_points.min(axis=0).tolist(),nail_points.max(axis=0).tolist()]}
        landmarks[digit] = digit_row
    row["landmarks"] = landmarks
    report["hands"][side] = row
materials = {m for obj in scene.objects if obj.type == "MESH" for m in obj.data.materials}
report["materials"] = {}
for material in materials:
    images = []
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            im = node.image
            images.append({"node": node.name, "image": im.name, "size": list(im.size), "colorspace": im.colorspace_settings.name,
                "packed_sha256": [hashlib.sha256(p.packed_file.data).hexdigest() for p in im.packed_files]})
    report["materials"][material.name] = {"images": images, "links": [(l.from_node.name, l.from_socket.name, l.to_node.name, l.to_socket.name) for l in material.node_tree.links]}
assert digest(source) == before
report["source_unchanged"] = True
target = Path(__file__).with_name("source_structure.json")
target.write_text(json.dumps(report, indent=2)+"\n")
print("FINGER_SOURCE_STRUCTURE_READ_ONLY_PASS", target, flush=True)
