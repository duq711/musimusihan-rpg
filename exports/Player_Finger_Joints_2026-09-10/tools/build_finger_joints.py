"""Add 15 localized finger-flex corrective morphs to each delivered detailed hand.

Mac background production is explicitly authorized for this task. Input files are
never written. The editable output and GLBs are saved in the neutral bind pose.
"""
import argparse
import hashlib
import json
import math
import platform
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

DIGITS = ("thumb", "index", "middle", "ring", "little")
KEYS = [f"Joint_{digit}_{joint}" for digit in DIGITS for joint in range(3)]
LIMITS = {digit: ([60, 70, 80] if digit == "thumb" else [90, 110, 80]) for digit in DIGITS}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def activate(scene):
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()


def descendants(parent):
    output = []
    for child in parent.children:
        output.append(child)
        output.extend(descendants(child))
    return output


def bone_signature(rig):
    return {bone.name: {"parent": bone.parent.name if bone.parent else None,
                        "matrix": [list(row) for row in bone.matrix_local]}
            for bone in rig.data.bones}


def mesh_signature(obj):
    h = hashlib.sha256()
    for vertex in obj.data.vertices:
        h.update(struct.pack("<3f", *vertex.co))
        for group in vertex.groups:
            h.update(struct.pack("<If", group.group, group.weight))
    for polygon in obj.data.polygons:
        h.update(struct.pack(f"<{len(polygon.vertices)}I", *polygon.vertices))
    return h.hexdigest()


def glb_morph_report(path):
    data = path.read_bytes()
    size, kind = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20:20 + size])
    assert kind == 0x4E4F534A
    morph_meshes = []
    for mesh in document["meshes"]:
        names = mesh.get("extras", {}).get("targetNames", [])
        if names:
            assert names == KEYS, f"Exported shape names/order changed: {names}"
            rows = []
            for primitive in mesh["primitives"]:
                targets = primitive.get("targets", [])
                assert len(targets) == 15, "Primitive lost corrective targets"
                assert all("POSITION" in target and "NORMAL" in target for target in targets), "Position/normal morph missing"
                rows.append({"vertices": document["accessors"][primitive["attributes"]["POSITION"]]["count"],
                             "target_count": len(targets), "position_and_normal": True})
            assert all(value == 0 for value in mesh.get("weights", [])), "Exported corrective is active in neutral asset"
            morph_meshes.append({"mesh": mesh.get("name"), "target_names": names, "primitives": rows})
    assert len(morph_meshes) == 1, "Only the anatomical hand mesh should have corrective morphs"
    assert len(document.get("skins", [])) == 1 and len(document["skins"][0]["joints"]) == 16
    for mesh in document["meshes"]:
        if "Nail_" in mesh.get("name", ""):
            assert not mesh.get("extras", {}).get("targetNames"), "Nail unexpectedly has corrective targets"
    return {"sha256": digest(path), "bytes": path.stat().st_size, "morph_meshes": morph_meshes,
            "skin_joints": [document["nodes"][j]["name"] for j in document["skins"][0]["joints"]]}


def stabilize_nailbeds(skin, rig, nails):
    """Keep skin beneath each rigid nail on the same distal phalanx at high flex."""
    names = {group.index: group.name for group in skin.vertex_groups}
    protect, report = {}, {}
    for digit in DIGITS:
        bone_name = digit + "2"
        matrix = rig.matrix_world @ rig.data.bones[bone_name].matrix_local
        anchor, axis = matrix.translation, matrix.to_3x3().col[1].normalized()
        dorsal = matrix.to_3x3().col[2].normalized()
        nail = next(obj for obj in nails if obj.name.startswith("Nail_" + digit))
        proximal = min((nail.matrix_world @ vertex.co - anchor).dot(axis) for vertex in nail.data.vertices)
        full_start, transition_start = proximal - .0015, proximal - .0055
        target = skin.vertex_groups[bone_name]
        changed, pinned, maximum = 0, 0, 0.0
        protection = {}
        for vertex in skin.data.vertices:
            old = {group.group: group.weight for group in vertex.groups}
            dominant = max(old, key=old.get)
            if not names[dominant].startswith(digit):
                continue
            along = (skin.matrix_world @ vertex.co - anchor).dot(axis)
            t = max(0.0, min(1.0, (along - transition_start) / (full_start - transition_start)))
            alpha = t * t * (3 - 2 * t)
            if alpha <= 0:
                continue
            new = {index: weight * (1 - alpha) for index, weight in old.items()}
            new[target.index] = new.get(target.index, 0) + alpha
            difference = sum(abs(new.get(index, 0) - old.get(index, 0)) for index in set(old) | set(new))
            if difference > 1e-8:
                for index in old:
                    skin.vertex_groups[index].remove([vertex.index])
                for index, weight in new.items():
                    if weight > 1e-8:
                        skin.vertex_groups[index].add([vertex.index], weight, "REPLACE")
                changed += 1
                maximum = max(maximum, difference)
            pinned += alpha > .99999
            # Normal directions identify the nail-bearing half of the section.
            normal = (skin.matrix_world.to_3x3() @ vertex.normal).normalized()
            protection[vertex.index] = alpha * max(0, min(1, (normal.dot(dorsal) + .05) / .50))
        protect[digit] = protection
        report[digit] = {"changed_weight_vertices": changed, "rigid_distal_vertices": pinned,
                         "target_bone": bone_name, "transition_length_m": .004,
                         "nail_proximal_axis_m": proximal, "rigid_section_start_axis_m": full_start,
                         "maximum_weight_l1_change": maximum, "neutral_coordinates_unchanged": True}
    return protect, report


def add_correctives(skin, rig, original_vertex_count, nail_protection):
    assert skin.data.shape_keys is None, "Expected the unchanged detailed mesh without prior morphs"
    before = mesh_signature(skin)
    source = [vertex.co.copy() for vertex in skin.data.vertices]
    world = [skin.matrix_world @ point for point in source]
    normals = [(skin.matrix_world.to_3x3() @ vertex.normal).normalized() for vertex in skin.data.vertices]
    inverse = skin.matrix_world.to_3x3().inverted()
    group_names = {group.index: group.name for group in skin.vertex_groups}
    owners = []
    for vertex in skin.data.vertices:
        dominant = max(vertex.groups, key=lambda group: group.weight)
        name = group_names[dominant.group]
        owners.append(next((digit for digit in DIGITS if name.startswith(digit)), "wrist"))
    skin.shape_key_add(name="Basis", from_mix=False)
    skin.data.shape_keys.use_relative = True
    reports = {}
    for digit in DIGITS:
        owned = [i for i, owner in enumerate(owners) if owner == digit]
        physical = [i for i in owned if i < original_vertex_count]
        for joint in range(3):
            name = f"Joint_{digit}_{joint}"
            matrix = rig.matrix_world @ rig.data.bones[digit + str(joint)].matrix_local
            anchor = matrix.translation.copy()
            axis = matrix.to_3x3().col[1].normalized()
            dorsal = matrix.to_3x3().col[2].normalized()
            cross = axis.cross(dorsal).normalized()
            # Use the actual owned skin section, not the off-center authored
            # motion pivot, to locate the center and radius of this joint volume.
            candidates = [i for i in physical if abs((world[i] - anchor).dot(axis)) < .004]
            axial_adjustment = 0.0
            if len(candidates) < 8:
                nearest = sorted(physical, key=lambda i: abs((world[i] - anchor).dot(axis)))[:40]
                axial_adjustment = sum((world[i] - anchor).dot(axis) for i in nearest) / len(nearest)
                axial_adjustment = max(-.018, min(.018, axial_adjustment))
                anchor += axis * axial_adjustment
                candidates = [i for i in physical if abs((world[i] - anchor).dot(axis)) < .005]
            if len(candidates) < 8:
                raise RuntimeError(f"Cannot locate owned skin section for {name}")
            center = anchor.copy()
            for basis in (cross, dorsal):
                values = sorted((world[i] - anchor).dot(basis) for i in candidates)
                low, high = values[int(len(values) * .05)], values[min(len(values) - 1, int(len(values) * .95))]
                center += basis * ((low + high) / 2)
            section_radius = max((world[i] - center - axis * (world[i] - center).dot(axis)).length for i in candidates)
            radial_limit = min(.036 if joint == 0 else .029, max(.012, section_radius * 1.55))
            width = (.0060, .0055, .0046)[joint]
            amplitude = (.00030, .00075, .00055)[joint]
            block = skin.shape_key_add(name=name, from_mix=False)
            block.slider_min, block.slider_max, block.value = 0.0, 1.0, 0.0
            changed, physical_changed, maximum, maximum_radius = 0, 0, 0.0, 0.0
            for index in owned:
                delta = world[index] - center
                along = delta.dot(axis)
                radial = (delta - axis * along).length
                if abs(along) > width * 2.35 or radial >= radial_limit:
                    continue
                normal = normals[index]
                facing = normal.dot(dorsal)
                outside, inside = max(0.0, facing) ** 1.4, max(0.0, -facing) ** 1.4
                axial_gate = math.exp(-(along / width) ** 2)
                radial_gate = max(0.0, 1 - (radial / radial_limit) ** 4)
                outer_volume = .93 * axial_gate * outside
                inner_fold = .55 * inside * (math.exp(-(along / .00125) ** 2)
                             + .24 * math.exp(-((along + .0032) / .00095) ** 2))
                side_volume = .12 * axial_gate * (1 - abs(facing)) ** 2
                amount = amplitude * radial_gate * (outer_volume - inner_fold + side_volume)
                amount *= 1 - nail_protection[digit].get(index, 0.0)
                if abs(amount) < 1e-8:
                    continue
                block.data[index].co = source[index] + inverse @ (normal * amount)
                changed += 1
                physical_changed += index < original_vertex_count
                maximum = max(maximum, abs(amount))
                maximum_radius = max(maximum_radius, delta.length)
            assert physical_changed >= 15 and 0.00005 < maximum <= .0009, f"Ineffective or excessive corrective {name}: {physical_changed}, {maximum}"
            assert all(block.data[i].co == source[i] for i, owner in enumerate(owners) if owner != digit), f"Foreign digit/wrist changed in {name}"
            reports[name] = {"digit": digit, "joint": joint, "full_flex_degrees": LIMITS[digit][joint],
                             "deformed_vertices": changed, "physical_skin_vertices": physical_changed,
                             "maximum_displacement_m": maximum, "maximum_influence_radius_m": maximum_radius,
                             "skin_section_center_world_m": list(center), "bone_anchor_world_m": list(matrix.translation),
                             "axial_section_adjustment_m": axial_adjustment, "section_samples": len(candidates),
                             "foreign_digit_and_wrist_displacement_m": 0.0, "default_value": block.value}
    assert before == mesh_signature(skin), "Basis topology, coordinates or weights changed"
    assert all(a.co == b for a, b in zip(skin.data.shape_keys.key_blocks["Basis"].data, source))
    return {"basis_geometry_weights_sha256": before, "key_count": 15, "keys": reports,
            "ownership_mask": "maximum individual bone weight must belong to this digit; wrist and other digits remain exact"}


def export_native(scene, side_objects, holder, output_path):
    temporary = bpy.data.scenes.new("Articulated_Export_Native")
    roots = [obj for obj in side_objects if obj.parent == holder]
    for obj in side_objects:
        temporary.collection.objects.link(obj)
        scene.collection.objects.unlink(obj)
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = None
        obj.matrix_basis = basis
    activate(temporary)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in side_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    options = {"filepath": str(output_path), "export_format": "GLB", "use_selection": True,
               "use_active_scene": True, "export_yup": True, "export_materials": "EXPORT",
               "export_skins": True, "export_influence_nb": 8, "export_animations": False,
               "export_apply": False, "export_extras": True, "export_cameras": False,
               "export_lights": False, "export_morph": True, "export_morph_normal": True,
               "export_morph_tangent": False}
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    assert "export_morph" in props and "export_morph_normal" in props
    bpy.ops.export_scene.gltf(**{key: value for key, value in options.items() if key in props})
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = holder
        obj.matrix_basis = basis
    for obj in side_objects:
        scene.collection.objects.link(obj)
        temporary.collection.objects.unlink(obj)
    activate(scene)
    bpy.data.scenes.remove(temporary)
    return glb_morph_report(output_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background, "Use a separate background Blender process"
    source, output = args.input_dir.resolve(), args.output_dir.resolve()
    paths = {name: source / name for name in ("bilateral_hands_detailed.blend", "left_hand_detailed.glb", "right_hand_detailed.glb", "build_report.json")}
    assert all(path.is_file() for path in paths.values()), "Detailed source package is incomplete"
    assert output != source and source not in output.parents, "Use a separate staging output directory"
    assert not output.exists() or (output.is_dir() and not any(output.iterdir())), "Output must be new or empty"
    source_hashes = {name: digest(path) for name, path in paths.items()}
    source_report = json.loads(paths["build_report.json"].read_text())
    output.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(paths["bilateral_hands_detailed.blend"]))
    scene = bpy.data.scenes["Bilateral_Detailed_Review"]
    scene.name = "Bilateral_Articulated_Review"
    activate(scene)
    report = {"status": "building", "created_utc": datetime.now(timezone.utc).isoformat(),
              "host": {"platform": platform.platform(), "blender_binary": bpy.app.binary_path,
                       "blender_version": bpy.app.version_string, "background": bpy.app.background},
              "source_sha256": source_hashes, "shape_names": KEYS, "full_flex_degrees": LIMITS,
              "morph_export": "relative POSITION and NORMAL deltas; default weights zero",
              "hands": {}, "renders": {},
              "limits": "Submillimeter pose corrections support the unchanged 16-bone rig; no nail morphs or topology edits."}
    hands = {}
    for side in ("left", "right"):
        holder = next(obj for obj in scene.objects if obj.name == side.upper() + "_PreviewTranslationOnly")
        objects = descendants(holder)
        rig = next(obj for obj in objects if obj.type == "ARMATURE")
        skin = next(obj for obj in objects if obj.type == "MESH" and "anatomicalhand" in obj.name.lower())
        before_bones = bone_signature(rig)
        nail_hashes = {obj.name: mesh_signature(obj) for obj in objects if obj.name.startswith("Nail_")}
        original_count = next(row["before"]["vertices"] for row in source_report["hands"][side]["meshes"] if "anatomicalhand" in row["source_name"].lower())
        source_skin_signature = mesh_signature(skin)
        nail_protection, attachment_report = stabilize_nailbeds(skin, rig, [obj for obj in objects if obj.name.startswith("Nail_")])
        morphs = add_correctives(skin, rig, original_count, nail_protection)
        assert bone_signature(rig) == before_bones
        assert nail_hashes == {obj.name: mesh_signature(obj) for obj in objects if obj.name.startswith("Nail_")}
        exported = export_native(scene, objects, holder, output / f"{side}_hand_articulated.glb")
        report["hands"][side] = {"correctives": morphs, "export": exported,
                                 "source_skin_geometry_weights_sha256": source_skin_signature,
                                 "nailbed_attachment_weights": attachment_report,
                                 "rest_bones": before_bones, "nail_geometry_weights_sha256": nail_hashes,
                                 "native_wrist_m": source_report["hands"][side]["wrist_origin"]}
        hands[side] = (holder, objects, rig, skin)
    # Save the actual editable delivery neutral; review poses are never saved over it.
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "bilateral_hands_articulated.blend"))
    camera = scene.camera
    scene.cycles.samples = 32
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
    scene.render.resolution_percentage = 100
    left_holder, left_objects, left_rig, left_skin = hands["left"]
    for obj in hands["right"][1]:
        obj.hide_render = True
    neutral_pose = {side: {bone.name: bone.matrix_basis.copy() for bone in data[2].pose.bones}
                    for side, data in hands.items()}
    points = [left_skin.matrix_world @ vertex.co for vertex in left_skin.data.vertices[:original_count]]
    center = Vector([(min(p[i] for p in points) + max(p[i] for p in points)) / 2 for i in range(3)])
    span = max(max(p[i] for p in points) - min(p[i] for p in points) for i in range(3))
    camera.data.ortho_scale = span * 1.50
    for pose_name, direction in (("open_dorsum", (0, -.16, 1)), ("open_palm", (0, .12, -1)),
                                 ("flex_dorsum", (0, -.65, 1)), ("flex_palm", (0, .60, -1)),
                                 ("independent_index_1", (1, -.25, .45))):
        for side, data in hands.items():
            for bone in data[2].pose.bones:
                bone.matrix_basis = neutral_pose[side][bone.name]
            for key in data[3].data.shape_keys.key_blocks:
                key.value = 0
        if pose_name.startswith("flex"):
            for digit in DIGITS:
                for joint in range(3):
                    bone = left_rig.pose.bones[digit + str(joint)]
                    bone.matrix_basis = neutral_pose["left"][bone.name] @ Matrix.Rotation(-math.radians(LIMITS[digit][joint]), 4, "X")
                    left_skin.data.shape_keys.key_blocks[f"Joint_{digit}_{joint}"].value = 1
        elif pose_name.startswith("independent"):
            bone = left_rig.pose.bones["index1"]
            bone.matrix_basis = neutral_pose["left"][bone.name] @ Matrix.Rotation(-math.radians(95), 4, "X")
            left_skin.data.shape_keys.key_blocks["Joint_index_1"].value = 95 / 110
        bpy.context.view_layer.update()
        camera.location = center + Vector(direction).normalized() * 1.4
        camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = str(output / f"joints_{pose_name}.png")
        bpy.ops.render.render(write_still=True)
        report["renders"][pose_name] = {"file": Path(scene.render.filepath).name,
                                       "pose": pose_name, "requires_visual_review": True}
    for side, data in hands.items():
        for bone in data[2].pose.bones:
            bone.matrix_basis = neutral_pose[side][bone.name]
        for key in data[3].data.shape_keys.key_blocks:
            key.value = 0
    assert source_hashes == {name: digest(path) for name, path in paths.items()}
    report["status"] = "built_pending_independent_pose_and_runtime_verification"
    report["outputs"] = {path.name: {"bytes": path.stat().st_size, "sha256": digest(path)}
                         for path in output.iterdir() if path.is_file()}
    (output / "build_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("FINGER_JOINTS_BUILD_COMPLETE", output)


if __name__ == "__main__":
    main()
