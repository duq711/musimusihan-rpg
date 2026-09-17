"""Independent checks of refined wrists and preserved articulated fingers.

Reads the previous Blender source, the new Blender source, and both new GLBs.
Never saves any model. Runtime connection deformation is verified in Godot.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
import bmesh
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

spec = importlib.util.spec_from_file_location("joint_core", Path(__file__).with_name("joint_verification_core.py"))
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def native_matrix(obj, rig):
    # Editable display holders use translation only; strip their lateral offset.
    return Matrix.Translation((-core.wrist_world(rig).x, 0, 0)) @ obj.matrix_world


def hand_for(scene, rig):
    return next(o for o in core.rigged_meshes(scene, rig) if "anatomicalhand" in o.name.lower())


def forearm_for(scene, rig):
    objects = [o for o in scene.objects if o.type == "MESH" and o.name.startswith("Forearm")]
    assert objects, "Missing forearm surface"
    return min(objects, key=lambda o: abs(o.matrix_world.translation.x - rig.matrix_world.translation.x))


def snapshot(scene, rig):
    hand = hand_for(scene, rig)
    basis = hand.data.shape_keys.key_blocks[0]
    transform = native_matrix(hand, rig)
    names = {g.index: g.name for g in hand.vertex_groups}
    weights = [{names[g.group]: g.weight for g in v.groups} for v in hand.data.vertices]
    return {
        "points": [transform @ v.co for v in hand.data.vertices],
        "weights": weights,
        "faces": [tuple(p.vertices) for p in hand.data.polygons],
        "deltas": {k.name: [transform.to_3x3() @ (v.co - basis.data[i].co) for i, v in enumerate(k.data)]
                   for k in hand.data.shape_keys.key_blocks[1:]},
        "rest": core.rest_signature(rig),
        "forearm_points": [native_matrix(forearm_for(scene, rig), rig) @ v.co
                           for v in forearm_for(scene, rig).data.vertices],
        "forearm_faces": [tuple(p.vertices) for p in forearm_for(scene, rig).data.polygons],
        "nails": {digit: [native_matrix(o, rig) @ v.co for v in o.data.vertices]
                  for digit in ("thumb", "index", "middle", "ring", "little")
                  for o in core.rigged_meshes(scene, rig) if o.name.startswith("Nail_" + digit)},
    }


def compare_authored_hand(scene, rig, before):
    after = snapshot(scene, rig)
    assert len(before["points"]) == len(after["points"]), "Wrist refinement changed hand vertex count"
    assert before["faces"] == after["faces"], "Hand topology changed outside the scoped shape refinement"
    maximum = 0.0
    changed = 0
    for index, (a, b) in enumerate(zip(before["points"], after["points"])):
        error = (b - a).length
        maximum = max(maximum, error)
        old_weights, new_weights = before["weights"][index], after["weights"][index]
        assert set(old_weights) == set(new_weights), f"Hand weight membership changed at {index}"
        assert max((abs(old_weights[k] - new_weights[k]) for k in old_weights), default=0) < 1e-6
        if error > 1e-6:
            changed += 1
            owner = max(old_weights, key=old_weights.get)
            assert owner == "wrist" and a.y < .011, f"Protected finger/palm vertex {index} changed"
    assert changed >= 100 and .0005 < maximum < .04, "No scoped, measurable wrist surface refinement"
    morph_max = 0.0
    assert before["deltas"].keys() == after["deltas"].keys()
    for name, old in before["deltas"].items():
        error = max((a - b).length for a, b in zip(old, after["deltas"][name]))
        morph_max = max(morph_max, error)
    assert morph_max < 2e-7, "Existing finger corrective deltas changed"
    nail_max = 0.0
    for digit, old in before["nails"].items():
        new = after["nails"][digit]
        assert len(old) == len(new)
        nail_max = max(nail_max, max((a-b).length for a,b in zip(old,new)))
    assert nail_max < 2e-7, "Existing nail geometry changed"
    assert len(before["forearm_points"]) == len(after["forearm_points"])
    assert before["forearm_faces"] == after["forearm_faces"], "Forearm topology changed"
    protected = [i for i, p in enumerate(before["forearm_points"]) if -p.y >= .1]
    assert protected
    forearm_protected_max = max((before["forearm_points"][i] - after["forearm_points"][i]).length for i in protected)
    assert forearm_protected_max < 2e-7, "Forearm beyond local wrist region changed"
    assert min(-p.y for p in after["forearm_points"]) >= .0749, "Rigid forearm still intrudes into flexing wrist span"
    return {"changed_wrist_vertices": changed, "max_wrist_refinement_m": maximum,
            "protected_finger_palm_vertices_unchanged": True, "skin_weights_unchanged": True,
            "hand_topology_unchanged": True, "max_corrective_delta_error_m": morph_max,
            "max_nail_position_error_m": nail_max,
            "protected_forearm_vertices": len(protected), "max_protected_forearm_error_m": forearm_protected_max}


def cuff_for(scene, rig):
    # Association uses each object's nearest lateral review holder position.
    cuffs = [o for o in scene.objects if o.type == "MESH" and o.name.startswith("WristCuff")]
    assert cuffs, "Missing actual wrist cuff mesh"
    return min(cuffs, key=lambda o: abs(o.matrix_world.translation.x - rig.matrix_world.translation.x))


def inspect_cuff(scene, rig):
    cuff = cuff_for(scene, rig)
    assert cuff.get("wrist_flex_version") == 1
    start, end = cuff.get("wrist_flex_start_z"), cuff.get("wrist_flex_end_z")
    assert start is not None and end is not None and .005 < start < end <= .09
    transform = native_matrix(cuff, rig)
    points = [transform @ v.co for v in cuff.data.vertices]
    assert all(math.isfinite(c) for p in points for c in p)
    assert len(points) >= 500, "Wrist connection lacks deformation subdivisions"
    bm = bmesh.new()
    bm.from_mesh(cuff.data)
    try:
        boundary = sum(e.is_boundary for e in bm.edges)
        nonmanifold = sum(not e.is_manifold for e in bm.edges)
        volume = bm.calc_volume(signed=True)
        degenerate = sum(f.calc_area() < 1e-12 for f in bm.faces)
    finally:
        bm.free()
    assert boundary == 0 and nonmanifold == 0, "New thin-walled wrist mesh must have closed rolled rims"
    assert volume > 0 and degenerate == 0, "Cuff has reversed volume or collapsed faces"
    native_z = [-p.y for p in points]  # Godot native Z = -Blender Y.
    stations = sorted(set(round(v, 5) for v in native_z))
    assert min(native_z) >= .005 and max(native_z) <= .105, "Cuff exceeds scoped wrist/forearm region"
    assert len(stations) >= 16, "Cuff lacks longitudinal support for smooth bending"
    assert min(native_z) < start and max(native_z) > end, "Cuff needs fixed end spans at both rims"
    return {"mesh": cuff.name, "vertices": len(points), "faces": len(cuff.data.polygons),
            "boundary_edges": boundary, "nonmanifold_edges": nonmanifold,
            "signed_volume_m3": volume, "degenerate_faces": degenerate,
            "native_godot_z_m": [min(native_z), max(native_z)], "axial_stations": len(stations),
            "flex_span_m": [start, end]}


def roundtrip_points(scene, rig, reference):
    result = {}
    for label, obj in [("hand", hand_for(scene, rig)), ("cuff", cuff_for(scene, rig))]:
        transform = native_matrix(obj, rig)
        points = [transform @ v.co for v in obj.data.vertices]
        expected = reference[label]
        kd = KDTree(len(expected))
        for i, p in enumerate(expected): kd.insert(p, i)
        kd.balance()
        maximum = max(kd.find(p)[2] for p in points)
        assert maximum < .000005, f"{label} GLB diverges from verified editable model"
        result[label] = {"vertices": len(points), "max_distance_to_editable_vertex_m": maximum}
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--previous-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--")+1:])
    assert bpy.app.background
    previous = args.previous_dir.resolve() / "bilateral_hands_articulated.blend"
    output = args.output_dir.resolve()
    files = [output/"bilateral_hands_wrist_refined.blend"] + [output/f"{s}_hand_wrist_refined.glb" for s in ("left","right")]
    hashes = {p.name: sha(p) for p in files}
    old_sha = sha(previous)
    report = {"status": "running", "utc": datetime.now(timezone.utc).isoformat(),
              "blender_version": bpy.app.version_string, "blender_binary": bpy.app.binary_path,
              "host": platform.platform(), "background": True, "checks": {}, "errors": [],
              "previous_blend_sha256": old_sha, "verified_asset_sha256": hashes,
              "limitations": ["Runtime flexible cuff deformation and contact are tested separately in Godot.",
                              "Numeric asset checks alone do not establish visual quality."]}
    bpy.ops.wm.open_mainfile(filepath=str(previous))
    scene = bpy.data.scenes["Bilateral_Articulated_Review"]
    core.activate(scene)
    rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: core.wrist_world(o).x)
    before = {s: snapshot(scene,r) for s,r in zip(("left","right"),rigs)}
    references = {}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(files[0]))
        scene = bpy.data.scenes["Bilateral_Wrist_Refined_Review"]
        core.activate(scene)
        assert not [im for im in bpy.data.images if im.source == "FILE" and not im.packed_file]
        assert not bpy.data.libraries
        rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: core.wrist_world(o).x)
        assert len(rigs) == 2
        for side, rig in zip(("left","right"),rigs):
            row = {"refinement": compare_authored_hand(scene,rig,before[side]),
                   "rest": core.compare_rest(rig,before[side]["rest"]),
                   "rig": core.inspect_rig(scene,rig,side), "cuff": inspect_cuff(scene,rig),
                   "joint_effects": core.inspect_joint_effects(scene,rig),
                   "nails": core.inspect_nails(scene,rig), "nail_seating": core.inspect_nail_seating(scene,rig)}
            report["checks"]["editable_"+side] = row
            references[side] = {label: [native_matrix(obj,rig) @ v.co for v in obj.data.vertices]
                                for label,obj in [("hand",hand_for(scene,rig)),("cuff",cuff_for(scene,rig))]}
    except Exception as error:
        report["errors"].append({"stage": "editable", "error": str(error)})
    for side in ("left","right"):
        try:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(output/f"{side}_hand_wrist_refined.glb"), bone_heuristic="TEMPERANCE")
            scene = bpy.context.scene
            rigs = [o for o in scene.objects if o.type == "ARMATURE"]
            assert len(rigs) == 1
            rig = rigs[0]
            row = {"rig": core.inspect_rig(scene,rig,side,[0,-.05625,0]),
                   "rest": core.compare_rest(rig,before[side]["rest"]),
                   "materials": core.inspect_materials(scene.objects),
                   "joint_effects": core.inspect_joint_effects(scene,rig),
                   "nails": core.inspect_nails(scene,rig), "nail_seating": core.inspect_nail_seating(scene,rig),
                   "roundtrip": roundtrip_points(scene,rig,references[side])}
            row["triangles"] = sum(len(p.vertices)-2 for o in scene.objects if o.type=="MESH" for p in o.data.polygons)
            assert 35000 <= row["triangles"] <= 85000
            report["checks"][side+"_glb"] = row
        except Exception as error:
            report["errors"].append({"stage": side+"_glb", "error": str(error)})
    assert sha(previous) == old_sha
    assert all(sha(p)==hashes[p.name] for p in files)
    report["status"] = "passed" if not report["errors"] else "failed"
    (output/"verification_report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print("WRIST_REFINEMENT_VERIFICATION",report["status"],json.dumps(report["errors"]))
    if report["errors"]: raise SystemExit(1)


if __name__ == "__main__":
    main()
