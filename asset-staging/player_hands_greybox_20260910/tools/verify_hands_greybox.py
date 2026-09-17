"""Background Blender roundtrip check; never saves or edits the delivered assets."""
import argparse
import hashlib
import json
import math
import platform
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

EXPECTED = {"wrist"} | {f"{finger}{i}" for finger in ("thumb", "index", "middle", "ring", "little") for i in range(3)}


def activate(scene):
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()


def rigged_meshes(scene, armature):
    return [obj for obj in scene.objects if obj.type == "MESH" and any(
        mod.type == "ARMATURE" and mod.object == armature for mod in obj.modifiers)]


def evaluated_points(obj):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        return [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
    finally:
        evaluated.to_mesh_clear()


def wrist_world(armature):
    evaluated = armature.evaluated_get(bpy.context.evaluated_depsgraph_get())
    return evaluated.matrix_world @ evaluated.pose.bones["wrist"].head


def inspect_rig(scene, armature, side, native_wrist=None):
    assert set(armature.data.bones.keys()) == EXPECTED, "Expected exactly 16 named hand bones"
    assert all(b.parent is not None for b in armature.data.bones if b.name != "wrist"), "Disconnected finger hierarchy"
    meshes = rigged_meshes(scene, armature)
    assert meshes, "No meshes bound to this hand rig"
    row = {"rig": armature.name, "bones": sorted(EXPECTED), "meshes": {}, "finger_pose_checks": {}}
    wrist_before = wrist_world(armature)
    row["wrist_world_m"] = list(wrist_before)
    if native_wrist is not None:
        error = (wrist_before - Vector(native_wrist)).length
        row["native_wrist_error_m"] = error
        assert error < 0.00005, "Native wrist moved from authored source offset"
    thumb = armature.matrix_world @ armature.data.bones["thumb0"].head_local
    middle = armature.matrix_world @ armature.data.bones["middle0"].head_local
    row["thumb_minus_middle_x_m"] = thumb.x - middle.x
    assert (thumb.x - middle.x) * (1 if side == "left" else -1) > .015, "Unexpected hand chirality"
    wrist_vertices = {}
    for obj in meshes:
        group_ids = {g.index for g in obj.vertex_groups if g.name in EXPECTED}
        wrist_group = obj.vertex_groups.get("wrist")
        sums = [sum(g.weight for g in v.groups if g.group in group_ids) for v in obj.data.vertices]
        assert sums and all(math.isfinite(s) and .98 <= s <= 1.02 for s in sums), "Invalid skin weight coverage"
        wrist_vertices[obj] = [v.index for v in obj.data.vertices if wrist_group and any(
            g.group == wrist_group.index and g.weight > .99999 for g in v.groups)]
        row["meshes"][obj.name] = {"vertices": len(sums), "weight_sum_min": min(sums),
                                  "weight_sum_max": max(sums), "wrist_only_vertices": len(wrist_vertices[obj])}
    baseline = {obj: evaluated_points(obj) for obj in meshes}
    for finger in ("thumb", "index", "middle", "ring", "little"):
        bone = armature.pose.bones[f"{finger}0"]
        saved = bone.matrix_basis.copy()
        try:
            bone.matrix_basis = saved @ Matrix.Rotation(.40, 4, "X")
            bpy.context.view_layer.update()
            moved, maximum, wrist_mesh_error = 0, 0.0, 0.0
            for obj in meshes:
                after = evaluated_points(obj)
                assert len(after) == len(baseline[obj]), "Pose unexpectedly changed vertex count"
                distances = [(a - b).length for a, b in zip(after, baseline[obj])]
                moved += sum(distance > .00001 for distance in distances)
                maximum = max(maximum, max(distances))
                wrist_mesh_error = max(wrist_mesh_error, max((distances[i] for i in wrist_vertices[obj]), default=0.0))
            wrist_error = (wrist_world(armature) - wrist_before).length
            row["finger_pose_checks"][finger] = {"local_x_rotation_radians": .40,
                "moved_vertices": moved, "max_displacement_m": maximum,
                "wrist_bone_error_m": wrist_error, "wrist_only_mesh_error_m": wrist_mesh_error}
            assert moved >= 5 and maximum > .001, f"{finger} pose does not deform hand vertices"
            assert wrist_error < .00001 and wrist_mesh_error < .00001, f"{finger} pose moved wrist"
        finally:
            bone.matrix_basis = saved
            bpy.context.view_layer.update()
    return row


def inspect_materials(objects):
    materials = {slot.material for obj in objects if obj.type == "MESH" for slot in obj.material_slots}
    assert None not in materials and materials, "Missing material"
    result = {}
    for mat in materials:
        assert mat.use_nodes, "Expected node-based grey material"
        assert not any(node.type == "TEX_IMAGE" for node in mat.node_tree.nodes), "Texture remains"
        shaders = [node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED"]
        assert len(shaders) == 1, "Expected one simple grey shader"
        shader = shaders[0]
        color = list(shader.inputs["Base Color"].default_value)
        assert max(color[:3]) - min(color[:3]) < .00001, "Material is not neutral grey"
        assert shader.inputs["Metallic"].default_value < .00001, "Material is metallic"
        result[mat.name] = {"base_color": color, "roughness": shader.inputs["Roughness"].default_value}
    assert len(materials) == 3, "Expected hand/glove, cuff, and sleeve greys"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background, "Verifier must run in background mode"
    output = args.output_dir.resolve()
    report = {"status": "running", "utc": datetime.now(timezone.utc).isoformat(),
              "host": platform.platform(), "blender_binary": bpy.app.binary_path,
              "blender_version": bpy.app.version_string, "background": bpy.app.background,
              "checks": {}, "errors": [],
              "limitations": ["Five isolated finger bends verify deformation, not an animation or game capture.",
                              "No visual quality, hand contact, renderer or Godot runtime claim.",
                              "Wrist is compared to the authored source offset, not forced to absolute zero."]}
    files = [output / "bilateral_hands_greybox.blend"] + [output / f"{s}_hand_greybox.glb" for s in ("left", "right")]
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    build = json.loads((output / "build_report.json").read_text(encoding="utf-8"))
    try:
        bpy.ops.wm.open_mainfile(filepath=str(files[0]))
        scene = bpy.data.scenes["Bilateral_Greybox_Review"]
        activate(scene)
        rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: wrist_world(o).x)
        assert len(rigs) == 2, "Editable bilateral scene should contain two hand rigs"
        report["checks"]["editable_blend"] = {side: inspect_rig(scene, rig, side) for side, rig in zip(("left", "right"), rigs)}
        report["checks"]["editable_materials"] = inspect_materials(scene.objects)
    except Exception as error:
        report["errors"].append({"stage": "editable_blend", "error": str(error)})
    for side in ("left", "right"):
        try:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            scene = bpy.context.scene
            bpy.ops.import_scene.gltf(filepath=str(output / f"{side}_hand_greybox.glb"), bone_heuristic="TEMPERANCE")
            bpy.context.view_layer.update()
            rigs = [o for o in scene.objects if o.type == "ARMATURE"]
            assert len(rigs) == 1, "Standalone asset should contain one hand rig"
            row = inspect_rig(scene, rigs[0], side, build["hands"][side]["wrist_origin"])
            row["materials"] = inspect_materials(scene.objects)
            row["triangles"] = sum(len(p.vertices) - 2 for o in scene.objects if o.type == "MESH" for p in o.data.polygons)
            assert row["triangles"] > 1000, "Missing reduced hand geometry"
            report["checks"][f"{side}_glb_roundtrip"] = row
        except Exception as error:
            report["errors"].append({"stage": f"{side}_glb_roundtrip", "error": str(error)})
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, "Verification modified an asset"
    report["verified_asset_sha256"] = hashes
    report["status"] = "passed" if not report["errors"] else "failed"
    destination = output / "verification_report.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("GREYBOX_VERIFICATION", report["status"], destination)
    if report["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
