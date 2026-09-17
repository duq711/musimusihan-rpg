"""Independent background Blender verification of fifteen articulated joints.

Reopens the editable file and each GLB, then compares every rest bone with the
authored source, exercises all fifteen joints, and evaluates real corrective
shape deformation. Never saves a delivered asset.
"""
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
from mathutils.bvhtree import BVHTree

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
    expected = {"Detailed_Skin", "Detailed_Glove", "Detailed_Sleeve", "Detailed_Nail", "Detailed_Trim"}
    assert {m.name.split(".")[0] for m in materials} == expected, "Expected the five detailed material roles"
    return result


def inspect_nails(scene, armature):
    """Nails must be attached to their own distal bone and follow finger flexion."""
    result = {}
    for finger in ("thumb", "index", "middle", "ring", "little"):
        nails = [o for o in rigged_meshes(scene, armature)
                 if o.name.startswith("Nail_" + finger)]
        assert len(nails) == 1, f"Missing or duplicate {finger} nail"
        nail = nails[0]
        assert len(nail.data.polygons) >= 12, "Nail should be a modeled curved plate"
        distal = armature.pose.bones[finger + "2"]
        group = nail.vertex_groups.get(finger + "2")
        assert group is not None, "Nail has no distal bone assignment"
        assert all(any(g.group == group.index and g.weight > .999 for g in v.groups)
                   for v in nail.data.vertices), "Nail must stay rigid on its distal phalanx"
        before = evaluated_points(nail)
        nail_surface = BVHTree.FromPolygons(before, [tuple(p.vertices) for p in nail.data.polygons])
        center = sum(before, Vector()) / len(before)
        axis = (armature.matrix_world @ armature.data.bones[finger + '2'].matrix_local).to_3x3().col[1].normalized()
        dorsal = (Vector((0, 0, 1)) - axis * axis.z).normalized()
        exposed_hit = nail_surface.ray_cast(center + dorsal * .035, -dorsal, .07)
        assert exposed_hit[0] is not None and exposed_hit[1].dot(dorsal) > .3, 'Exposed nail face winding points inward'
        bone_world = armature.matrix_world @ distal.matrix
        local_before = [bone_world.inverted() @ point for point in before]
        # Proximal rotation carries the entire distal chain. A missing armature
        # modifier or detached accessory cannot pass this evaluated-mesh check.
        proximal = armature.pose.bones[finger + "0"]
        saved = proximal.matrix_basis.copy()
        try:
            proximal.matrix_basis = saved @ Matrix.Rotation(.55, 4, "X")
            bpy.context.view_layer.update()
            after = evaluated_points(nail)
            bone_world_after = armature.matrix_world @ distal.matrix
            local_after = [bone_world_after.inverted() @ point for point in after]
            movement = max((a - b).length for a, b in zip(after, before))
            attachment_error = max((a - b).length for a, b in zip(local_after, local_before))
            assert movement > .001, "Nail did not follow its finger"
            assert attachment_error < .00002, "Nail detached or stretched during finger flexion"
            result[finger] = {"mesh": nail.name, "vertices": len(before),
                              "max_movement_m": movement, "bone_local_error_m": attachment_error,
                              "exposed_face_dorsal_dot": exposed_hit[1].dot(dorsal)}
        finally:
            proximal.matrix_basis = saved
            bpy.context.view_layer.update()
    return result


def rest_signature(armature):
    return {b.name: {"parent": b.parent.name if b.parent else None,
                     "matrix": [list(row) for row in b.matrix_local]}
            for b in armature.data.bones}


def compare_rest(armature, reference):
    actual = rest_signature(armature)
    assert set(actual) == set(reference), "Rest bone set changed"
    maximum = 0.0
    for name, row in actual.items():
        assert row["parent"] == reference[name]["parent"], f"{name} rest hierarchy changed"
        maximum = max(maximum, max(abs(a-b) for ar, br in zip(row["matrix"], reference[name]["matrix"])
                                   for a, b in zip(ar, br)))
    assert maximum < .00005, "Rest skeleton matrices changed"
    return {"all_16_bone_rest_matrices_max_error": maximum}


def inspect_sculpt(scene, reference_surface):
    """Ensure the base anatomy itself was refined, beyond attached accessories."""
    hand = next(o for o in scene.objects if o.type == "MESH" and "anatomicalhand" in o.name.lower())
    ids = set()
    for polygon in hand.data.polygons:
        material = hand.material_slots[polygon.material_index].material
        if material.name.split('.')[0] in {'Detailed_Skin', 'Detailed_Glove'}:
            ids.update(polygon.vertices)
    distances = []
    for index in sorted(ids)[::3]:
        point = hand.matrix_world @ hand.data.vertices[index].co
        nearest = reference_surface.find_nearest(point)
        if nearest[0] is not None:
            distances.append(nearest[3])
    changed = sum(d > .00002 for d in distances)
    assert changed >= 100 and max(distances) > .0001, 'Base hand surface has no measurable refinement'
    assert max(distances) < .01, 'Surface deviates more than 10 mm from authored hand proportions'
    return {'sampled_surface_vertices': len(distances), 'changed_over_0_02_mm': changed,
            'max_distance_from_original_surface_m': max(distances)}


def inspect_joint_effects(scene, armature):
    meshes = rigged_meshes(scene, armature)
    hand = next(o for o in meshes if 'anatomicalhand' in o.name.lower())
    keys = hand.data.shape_keys
    expected = {f'Joint_{finger}_{joint}' for finger in ('thumb', 'index', 'middle', 'ring', 'little') for joint in range(3)}
    assert keys is not None and len(keys.key_blocks) == 16, 'Expected Basis plus fifteen joint corrective shapes'
    assert set(k.name for k in keys.key_blocks[1:]) == expected, 'Joint shape names are incomplete'
    assert keys.use_relative, 'Joint correctives require relative shape keys'
    assert all(abs(k.value) < 1e-8 for k in keys.key_blocks[1:]), 'Delivered file must start at neutral morph values'
    basis = keys.key_blocks[0]
    groups = {g.index: g.name for g in hand.vertex_groups}
    baseline = evaluated_points(hand)
    wrist_before = wrist_world(armature)
    result, centers = {}, {}
    for finger in ('thumb', 'index', 'middle', 'ring', 'little'):
        pure_other = []
        for vertex in hand.data.vertices:
            active = [groups[g.group] for g in vertex.groups if g.weight > 1e-6 and groups[g.group] in EXPECTED]
            if not any(name.startswith(finger) for name in active):
                pure_other.append(vertex.index)
        for joint in range(3):
            name = f'Joint_{finger}_{joint}'
            key = keys.key_blocks[name]
            delta = [key.data[i].co - basis.data[i].co for i in range(len(basis.data))]
            assert all(all(math.isfinite(value) for value in d) for d in delta), 'Nonfinite corrective geometry'
            changed = [i for i, d in enumerate(delta) if d.length > .000001]
            maximum = max(d.length for d in delta)
            assert len(changed) >= 12 and .00005 < maximum <= .001, f'{name} needs restrained, measurable local geometry'
            assert max((delta[i].length for i in pure_other), default=0) < .000001, f'{name} changes an unrelated digit or wrist'
            center = sum((hand.matrix_world @ basis.data[i].co for i in changed), Vector()) / len(changed)
            centers[name] = center
            try:
                key.value = 1
                bpy.context.view_layer.update()
                corrected = evaluated_points(hand)
                visible_effect = max((a-b).length for a,b in zip(corrected, baseline))
                assert visible_effect > .00005, 'Shape values do not move the evaluated hand'
                key.value = 0
                bpy.context.view_layer.update()
                assert max((a-b).length for a,b in zip(evaluated_points(hand), baseline)) < .000001, 'Shape reset did not restore hand'
                bone = armature.pose.bones[finger + str(joint)]
                saved = bone.matrix_basis.copy()
                before_nail = {o: evaluated_points(o) for o in meshes if o.name.startswith('Nail_' + finger)}
                original_pose = {b.name: b.matrix_basis.copy() for b in armature.pose.bones}
                try:
                    bone.matrix_basis = saved @ Matrix.Rotation(-.55, 4, 'X')
                    bpy.context.view_layer.update()
                    flexed = evaluated_points(hand)
                    flex_movement = max((a-b).length for a,b in zip(flexed, baseline))
                    assert flex_movement > .0005, f'{name} joint cannot articulate its visible segment'
                    assert (wrist_world(armature)-wrist_before).length < .000001, 'Joint moved the wrist bone'
                    assert max(((flexed[i]-baseline[i]).length for i in pure_other), default=0) < .000002, 'Joint unexpectedly deformed an unrelated finger'
                    assert all(b.matrix_basis == original_pose[b.name] for b in armature.pose.bones if b != bone), 'Independent joint overwrote another local joint rotation'
                    key.value = 1
                    bpy.context.view_layer.update()
                    corrected_flex = evaluated_points(hand)
                    flex_correction = max((a-b).length for a,b in zip(corrected_flex, flexed))
                    assert flex_correction > .00004, 'Corrective did not survive actual armature skinning'
                    nail_movement = max((max((a-b).length for a,b in zip(evaluated_points(o), pts)) for o, pts in before_nail.items()), default=0)
                    assert nail_movement > .0005, 'Distal nail did not follow the tested joint chain'
                finally:
                    key.value = 0
                    bone.matrix_basis = saved
                    bpy.context.view_layer.update()
                result[name] = {'corrective_vertices': len(changed), 'max_corrective_delta_m': maximum,
                                'evaluated_correction_m': visible_effect, 'joint_flex_movement_m': flex_movement,
                                'correction_after_skinning_m': flex_correction, 'distal_nail_movement_m': nail_movement,
                                'affected_center_world_m': list(center)}
            finally:
                key.value = 0
                bpy.context.view_layer.update()
        for first, second in ((0,1),(1,2)):
            assert (centers[f'Joint_{finger}_{first}']-centers[f'Joint_{finger}_{second}']).length > .002, 'Different joints reuse the same effect location'
    assert max((a-b).length for a,b in zip(evaluated_points(hand), baseline)) < .000001, 'Joint audit failed to restore neutral hand'
    return result


def inspect_nail_seating(scene, armature):
    """A rigid nail alone is insufficient: its skin bed must follow at full flex."""
    meshes = rigged_meshes(scene, armature)
    hand = next(o for o in meshes if 'anatomicalhand' in o.name.lower())
    groups = {g.index: g.name for g in hand.vertex_groups}
    targets = {}
    for finger in ('thumb','index','middle','ring','little'):
        owned = set(v.index for v in hand.data.vertices if sum(g.weight for g in v.groups if groups[g.group].startswith(finger)) > .25)
        targets[finger] = [tuple(p.vertices) for p in hand.data.polygons
                           if all(i in owned for i in p.vertices)
                           and hand.material_slots[p.material_index].material.name.split('.')[0] in ('Detailed_Skin','Detailed_Glove')]
        assert targets[finger], 'No corresponding finger skin surface for nail seating check'
    originals = {b.name: b.matrix_basis.copy() for b in armature.pose.bones}
    limits = {f: ([60,70,80] if f == 'thumb' else [90,110,80]) for f in targets}
    cases = {'neutral': [], 'all_full_flex': [(f,j) for f in targets for j in range(3)],
             'thumb_middle_full': [('thumb',1)]}
    cases.update({f'{f}_tip_full': [(f,2)] for f in targets})
    result = {}
    try:
        for label, selected in cases.items():
            for bone in armature.pose.bones:
                bone.matrix_basis = originals[bone.name]
            for key in hand.data.shape_keys.key_blocks[1:]:
                key.value = 0
            for finger,joint in selected:
                name = finger + str(joint)
                armature.pose.bones[name].matrix_basis = originals[name] @ Matrix.Rotation(-math.radians(limits[finger][joint]),4,'X')
                hand.data.shape_keys.key_blocks[f'Joint_{finger}_{joint}'].value = 1
            bpy.context.view_layer.update()
            points = evaluated_points(hand)
            row = {}
            for finger, polygons in targets.items():
                target = BVHTree.FromPolygons(points, polygons)
                nail = next(o for o in meshes if o.name.startswith('Nail_' + finger))
                distances = [target.find_nearest(point)[3] for point in evaluated_points(nail)]
                maximum = max(distances)
                assert maximum < .0008, f'{label}/{finger} nail separates from skin by {maximum*1000:.3f} mm'
                row[finger] = {'max_skin_gap_m': maximum, 'mean_skin_gap_m': sum(distances)/len(distances)}
            result[label] = row
    finally:
        for bone in armature.pose.bones:
            bone.matrix_basis = originals[bone.name]
        for key in hand.data.shape_keys.key_blocks[1:]:
            key.value = 0
        bpy.context.view_layer.update()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--input-dir", type=Path, required=True)
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
    files = [output / "bilateral_hands_articulated.blend"] + [output / f"{s}_hand_articulated.glb" for s in ("left", "right")]
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    build = json.loads((output / "build_report.json").read_text(encoding="utf-8"))
    source_rest = {}
    source_wrists = {}
    source_surfaces = {}
    source_hashes = {}
    for side in ("left", "right"):
        original = args.input_dir.resolve() / f"{side}_arm.glb"
        source_hashes[str(original)] = hashlib.sha256(original.read_bytes()).hexdigest()
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(original), bone_heuristic="TEMPERANCE")
        source_rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
        source_rest[side] = rest_signature(source_rig)
        source_wrists[side] = list(wrist_world(source_rig))
        source_hand = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and 'anatomicalhand' in o.name.lower())
        source_surfaces[side] = BVHTree.FromPolygons(
            [source_hand.matrix_world @ v.co for v in source_hand.data.vertices],
            [tuple(p.vertices) for p in source_hand.data.polygons])
    try:
        bpy.ops.wm.open_mainfile(filepath=str(files[0]))
        unpacked = [im.name for im in bpy.data.images if im.source == 'FILE' and not im.packed_file]
        assert not unpacked and not bpy.data.libraries, 'Editable delivery has external image or library dependencies'
        report['checks']['portable_blend'] = {'external_images': unpacked, 'linked_libraries': len(bpy.data.libraries)}
        scene = bpy.data.scenes["Bilateral_Articulated_Review"]
        activate(scene)
        rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: wrist_world(o).x)
        assert len(rigs) == 2, "Editable bilateral scene should contain two hand rigs"
        report["checks"]["editable_blend"] = {side: inspect_rig(scene, rig, side) for side, rig in zip(("left", "right"), rigs)}
        report["checks"]["editable_nails"] = {side: inspect_nails(scene, rig) for side, rig in zip(("left", "right"), rigs)}
        report['checks']['editable_joint_effects'] = {side: inspect_joint_effects(scene, rig) for side, rig in zip(('left','right'), rigs)}
        report['checks']['editable_nail_seating'] = {side: inspect_nail_seating(scene, rig) for side, rig in zip(('left','right'), rigs)}
        report["checks"]["editable_rest"] = {side: compare_rest(rig, source_rest[side]) for side, rig in zip(("left", "right"), rigs)}
        report["checks"]["editable_materials"] = inspect_materials(scene.objects)
    except Exception as error:
        report["errors"].append({"stage": "editable_blend", "error": str(error)})
    for side in ("left", "right"):
        try:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            scene = bpy.context.scene
            bpy.ops.import_scene.gltf(filepath=str(output / f"{side}_hand_articulated.glb"), bone_heuristic="TEMPERANCE")
            bpy.context.view_layer.update()
            rigs = [o for o in scene.objects if o.type == "ARMATURE"]
            assert len(rigs) == 1, "Standalone asset should contain one hand rig"
            row = inspect_rig(scene, rigs[0], side, source_wrists[side])
            row["materials"] = inspect_materials(scene.objects)
            row["nails"] = inspect_nails(scene, rigs[0])
            row['joint_effects'] = inspect_joint_effects(scene, rigs[0])
            row['nail_seating'] = inspect_nail_seating(scene, rigs[0])
            row["rest"] = compare_rest(rigs[0], source_rest[side])
            row["sculpted_surface"] = inspect_sculpt(scene, source_surfaces[side])
            row["triangles"] = sum(len(p.vertices) - 2 for o in scene.objects if o.type == "MESH" for p in o.data.polygons)
            assert 35000 <= row["triangles"] <= 85000, "Detailed geometry outside review budget"
            report["checks"][f"{side}_glb_roundtrip"] = row
        except Exception as error:
            report["errors"].append({"stage": f"{side}_glb_roundtrip", "error": str(error)})
    assert hashes == {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}, "Verification modified an asset"
    assert source_hashes == {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in source_hashes}, "Verification modified an original"
    report["verified_asset_sha256"] = hashes
    report["status"] = "passed" if not report["errors"] else "failed"
    destination = output / "verification_report.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("FINGER_JOINTS_VERIFICATION", report["status"], destination)
    if report["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
