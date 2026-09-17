"""Read-only Blender validation of the reference-photo hand reconstruction.

This validates the new approved geometry, articulation and portable PBR data;
it does not certify photographic resemblance. Run once after geometry approval
and final baking. Original sources, the delivery and their hashes stay intact.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import platform
import struct
import sys
import traceback
from datetime import datetime, timezone
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

DIGITS = ("thumb", "index", "middle", "ring", "little")
SIDES = ("left", "right")
KEYS = ["Joint_" + digit + "_" + str(joint) for digit in DIGITS for joint in range(3)]
BONES = {"wrist"} | {digit + str(joint) for digit in DIGITS for joint in range(3)}
LIMITS = {digit: (60, 70, 80) if digit == "thumb" else (90, 110, 80) for digit in DIGITS}
PHYSICAL_VERTICES = 12036
ALLOWED_ROLES = {"Detailed_Skin", "Detailed_Nail", "Detailed_Sleeve", "Detailed_Trim", "Detailed_Glove"}
legacy = None
core = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_support(directory):
    global legacy, core
    path = directory / "verify_hands_realistic.py"
    spec = importlib.util.spec_from_file_location("reference_validation_support", path)
    legacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(legacy)
    core = legacy.core


def activate_delivery(name=None):
    if name:
        scene = bpy.data.scenes[name]
    else:
        candidates = [s for s in bpy.data.scenes if sum(o.type == "ARMATURE" for o in s.objects) == 2]
        assert len(candidates) == 1, "Ambiguous bilateral source scene"
        scene = candidates[0]
    core.activate(scene)
    rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda r: core.wrist_world(r).x)
    assert len(rigs) == 2
    return scene, dict(zip(SIDES, rigs))


def capture(scene, rig):
    result = legacy.snapshot(scene, rig)
    for label, obj in legacy.parts_for(scene, rig).items():
        uv = obj.data.uv_layers.active
        points = [set() for unused in obj.data.vertices]
        if uv:
            for loop in obj.data.loops:
                points[loop.vertex_index].add(tuple(uv.data[loop.index].uv))
        result["parts"][label]["uv"] = [list(values) for values in points]
        result["parts"][label]["face_materials"] = [obj.material_slots[p.material_index].material.name.split(".")[0] for p in obj.data.polygons]
    return result


def compare_new_authored(current, source, approved):
    result = {"parts": {}}
    for name, row in current["rest"].items():
        assert name in BONES and row["parent"] == source["rest"][name]["parent"]
        assert np.max(np.abs(np.asarray(row["matrix"]) - source["rest"][name]["matrix"])) < 2e-7, "Authored bone axes/pivot changed: " + name
    assert set(current["rest"]) == BONES
    for label, part in current["parts"].items():
        expected = approved["parts"][label]
        assert part["points"].shape == expected["points"].shape and part["faces"] == expected["faces"], "Bake changed approved topology: " + label
        position_error = float(np.linalg.norm(part["points"] - expected["points"], axis=1).max())
        assert position_error < 2e-7, "Bake changed approved model: " + label
        assert part["weights"] == expected["weights"] and part["deltas"].keys() == expected["deltas"].keys()
        delta_error = max((float(np.abs(part["deltas"][key] - expected["deltas"][key]).max()) for key in part["deltas"]), default=0.0)
        assert delta_error < 2e-7, "Bake changed approved corrective geometry: " + label
        result["parts"][label] = {"approved_position_error_m": position_error, "approved_corrective_error_m": delta_error}
    hand = current["parts"]["hand"]
    old_hand = source["parts"]["hand"]
    assert len(hand["points"]) == PHYSICAL_VERTICES
    assert hand["weights"] == old_hand["weights"][:PHYSICAL_VERTICES], "Original physical-skin weights or vertex order changed"
    physical_faces = [p for p in old_hand["faces"] if max(p) < PHYSICAL_VERTICES]
    assert hand["faces"] == physical_faces, "Bare skin lost original continuous anatomical faces"
    assert set(hand["face_materials"]) == {"Detailed_Skin"}, "Glove or trim faces remain on the bare hand"
    movement = np.linalg.norm(hand["points"] - old_hand["points"][:PHYSICAL_VERTICES], axis=1)
    result["original_skin"] = {"weights_exact_by_original_index": PHYSICAL_VERTICES,
        "changed_vertices_over_10um": int((movement > .00001).sum()), "maximum_reconstruction_displacement_m": float(movement.max()),
        "note": "The photograph-led silhouette may change; old exact-position, protected-trim and submillimetre-sculpt limits do not apply."}
    cuff, old_cuff = current["parts"]["WristCuff"], source["parts"]["WristCuff"]
    assert cuff["flex"] == old_cuff["flex"] and cuff["flex"]["wrist_flex_version"] == 1
    assert abs(cuff["flex"]["wrist_flex_start_z"] - .014) < 1e-8 and abs(cuff["flex"]["wrist_flex_end_z"] - .075) < 1e-8
    assert set(cuff["face_materials"]) == {"Detailed_Skin"}
    proximal = old_cuff["points"][:, 1] <= -.075 + 1e-8  # Godot +Z = Blender -Y.
    assert int(proximal.sum()) >= 64
    current_proximal = cuff["points"][:, 1] <= -.075 + 1e-8
    assert int(current_proximal.sum()) >= 64
    # The approved revision can remove the distal rolled lip and reindex the
    # cuff. Compare the unchanged proximal surface geometrically, both ways.
    def point_set_error(first, second):
        tree = KDTree(len(second))
        for index, point in enumerate(second):
            tree.insert(Vector(point), index)
        tree.balance()
        return max(tree.find(Vector(point))[2] for point in first)
    proximal_error = max(point_set_error(old_cuff["points"][proximal], cuff["points"][current_proximal]),
        point_set_error(cuff["points"][current_proximal], old_cuff["points"][proximal]))
    assert proximal_error < 2e-7, "The cuff's fully forearm-following proximal section changed"
    result["cuff"] = {"proximal_samples": int(proximal.sum()), "proximal_position_error_m": proximal_error, "metadata": cuff["flex"]}
    return result


def weight_groups(obj):
    names = {group.index: group.name for group in obj.vertex_groups}
    return [{names[g.group]: g.weight for g in vertex.groups} for vertex in obj.data.vertices]


def finite_points(points):
    assert all(all(math.isfinite(v) for v in point) for point in points), "Nonfinite evaluated skin/nail geometry"


def pose_nail_context(scene, rig, hand):
    weights = weight_groups(hand)
    baseline_hand = core.evaluated_points(hand)
    contexts = {}
    for digit in DIGITS:
        nails = [o for o in core.rigged_meshes(scene, rig) if o.name.startswith("Nail_" + digit)]
        assert len(nails) == 1
        nail = nails[0]
        assert nail.data.shape_keys is None and len(nail.data.polygons) >= 12
        assert all(abs(w.get(digit + "2", 0.0) - 1.0) < 1e-7 and sum(value for name, value in w.items() if name != digit + "2") < 1e-7 for w in weight_groups(nail)), "Nail is not rigidly assigned to its distal bone"
        nail_points = core.evaluated_points(nail)
        bone_world = rig.matrix_world @ rig.pose.bones[digit + "2"].matrix
        dorsal = bone_world.to_3x3().col[2].normalized()
        top_vertices, top_centers = set(), []
        # A curved quad's arithmetic centre need not lie on either rendered
        # triangle. Use Blender's actual tessellation for exposed-surface QA.
        nail.data.calc_loop_triangles()
        for triangle in nail.data.loop_triangles:
            ids = tuple(triangle.vertices)
            face = [nail_points[i] for i in ids]
            normal = (face[1] - face[0]).cross(face[2] - face[0])
            if normal.length > 1e-12 and normal.normalized().dot(dorsal) > .35:
                top_vertices.update(ids)
                top_centers.append(ids)
        assert len(top_vertices) >= 24 and len(top_centers) >= 12, "Nail lacks a correctly wound exposed upper surface"
        owned = {i for i, w in enumerate(weights) if sum(value for name, value in w.items() if name.startswith(digit)) > .25}
        nail_surface = BVHTree.FromPolygons(nail_points, top_centers, all_triangles=True)
        faces = []
        hand.data.calc_loop_triangles()
        for triangle in hand.data.loop_triangles:
            ids = tuple(triangle.vertices)
            if not all(i in owned for i in ids):
                continue
            points = [baseline_hand[i] for i in ids]
            normal = (points[1] - points[0]).cross(points[2] - points[0])
            if normal.length <= 1e-12 or normal.normalized().dot(dorsal) <= .02:
                continue
            # Keep the neutral nail-bed surface's identity through posing.
            # A full-fist ray can otherwise hit the curled proximal phalanx
            # before the actual distal bed and falsely report centimetres of
            # nail penetration. Eight millimetres includes the plate's rim.
            if min(nail_surface.find_nearest(p)[3] for p in points + [sum(points, Vector()) / 3]) <= .008:
                faces.append(ids)
        assert len(faces) >= 24, "Nail lacks a sufficiently sampled distal bed"
        contexts[digit] = {"nail": nail, "faces": faces, "top_vertices": sorted(top_vertices), "top_faces": top_centers,
            "bone_local": [bone_world.inverted() @ point for point in nail_points], "baseline": nail_points}
    finite_points(baseline_hand)
    return contexts


def nail_seating(rig, hand_points, digit, context):
    nail = context["nail"]
    points = core.evaluated_points(nail)
    finite_points(points)
    tree = BVHTree.FromPolygons(hand_points, context["faces"])
    bone_world = rig.matrix_world @ rig.pose.bones[digit + "2"].matrix
    dorsal = bone_world.to_3x3().col[2].normalized()
    local_error = max(((bone_world.inverted() @ point - original).length for point, original in zip(points, context["bone_local"])))
    assert local_error < .00002, digit + " nail detached or stretched"
    distances = [tree.find_nearest(point)[3] for point in points]
    assert all(value is not None for value in distances)
    maximum_gap = max(distances)
    assert maximum_gap < .0008, f"{digit} nail/skin gap is {maximum_gap * 1000:.3f} mm"
    # Test actual exposed vertices and face centres against the skin underneath.
    # The hidden bottom of the thin plate may seat slightly inside its nail bed.
    samples = [points[i] for i in context["top_vertices"]]
    samples += [sum((points[i] for i in ids), Vector()) / len(ids) for ids in context["top_faces"]]
    maximum_surface_gap = max(tree.find_nearest(point)[3] for point in samples)
    assert maximum_surface_gap < .0008, f"{digit} exposed nail surface floats {maximum_surface_gap * 1000:.3f} mm above its bed"
    signed = []
    for point in samples:
        hit = tree.ray_cast(point + dorsal * .04, -dorsal, .08)
        assert hit[0] is not None, digit + " exposed nail lacks supporting finger skin"
        signed.append((point - hit[0]).dot(dorsal))
    assert min(signed) >= -.00005, f"{digit} exposed nail is pierced by skin by {-min(signed) * 1000:.3f} mm"
    # Positive dorsal-ray distance is not a physical gap on the steep lateral
    # nail rim. The true nearest distance above applies to vertices and actual
    # triangle centres; the ray's sign independently catches skin penetration.
    return {"max_nearest_skin_gap_m": maximum_gap, "minimum_signed_exposed_clearance_m": min(signed),
        "maximum_signed_exposed_clearance_m": max(signed), "maximum_exposed_surface_gap_m": maximum_surface_gap,
        "exposed_samples": len(samples), "distal_bone_local_error_m": local_error}


def inspect_articulation(scene, rig):
    assert set(rig.data.bones.keys()) == BONES
    hand = next(o for o in core.rigged_meshes(scene, rig) if "anatomicalhand" in o.name.lower())
    keys = hand.data.shape_keys
    assert keys and keys.use_relative and [k.name for k in keys.key_blocks[1:]] == KEYS
    assert all(abs(k.value) < 1e-8 for k in keys.key_blocks[1:])
    # Original04 already contains 1.2–1.8e-7 float32 scale residue and sub-21nm
    # translations at zero Euler rotation; do not mistake those for a pose.
    assert all(float(np.abs(np.asarray(bone.matrix_basis) - np.eye(4)).max()) < 1e-6 for bone in rig.pose.bones), "Delivery pose is not neutral"
    original_pose = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
    weights = weight_groups(hand)
    assert all(.999 < sum(w.values()) < 1.001 for w in weights)
    baseline = core.evaluated_points(hand)
    wrist_before = core.wrist_world(rig)
    contexts = pose_nail_context(scene, rig, hand)
    result = {"neutral_nail_seating": {digit: nail_seating(rig, baseline, digit, context) for digit, context in contexts.items()}, "joints": {}}

    def reset():
        for bone in rig.pose.bones:
            bone.matrix_basis = original_pose[bone.name]
        for key in keys.key_blocks[1:]:
            key.value = 0.0
        bpy.context.view_layer.update()

    try:
        for digit in DIGITS:
            pure_other = [i for i, w in enumerate(weights) if not any(name.startswith(digit) and value > 1e-6 for name, value in w.items())]
            assert len(pure_other) > 100
            for joint in range(3):
                name = f"Joint_{digit}_{joint}"
                key = keys.key_blocks[name]
                delta = [a.co - b.co for a, b in zip(key.data, keys.key_blocks[0].data)]
                finite_points(delta)
                maximum = max(v.length for v in delta)
                changed = [i for i, v in enumerate(delta) if v.length > 1e-6]
                # Reconstruction may shrink/reshape the corrective. Use its
                # local phalanx scale, not the old exact 0.05–1 mm sculpt range.
                local_span = rig.data.bones[digit + str(joint)].length
                minimum_effect = max(.000005, local_span * .0002)
                maximum_effect = max(.001, local_span * .10)
                assert len(changed) >= 8 and minimum_effect < maximum < maximum_effect, name + " corrective is empty or exceeds its local anatomical scale"
                assert max((delta[i].length for i in pure_other), default=0.0) < .000002, name + " alters an unrelated digit/wrist"
                bone = rig.pose.bones[digit + str(joint)]
                bone.matrix_basis = original_pose[bone.name] @ Matrix.Rotation(-math.radians(LIMITS[digit][joint]), 4, "X")
                bpy.context.view_layer.update()
                flexed = core.evaluated_points(hand)
                finite_points(flexed)
                movement = max((a - b).length for a, b in zip(flexed, baseline))
                assert movement > .0005, name + " does not move its real skin"
                assert (core.wrist_world(rig) - wrist_before).length < 2e-6
                assert max(((flexed[i] - baseline[i]).length for i in pure_other), default=0.0) < .000003
                assert all(other.matrix_basis == original_pose[other.name] for other in rig.pose.bones if other != bone), "Independent joint changed another local rotation"
                key.value = 1.0
                bpy.context.view_layer.update()
                corrected = core.evaluated_points(hand)
                finite_points(corrected)
                visible = max((a - b).length for a, b in zip(corrected, flexed))
                assert visible > minimum_effect, name + " corrective does not survive skinning"
                seating = nail_seating(rig, corrected, digit, contexts[digit])
                nail_movement = max((a - b).length for a, b in zip(core.evaluated_points(contexts[digit]["nail"]), contexts[digit]["baseline"]))
                assert nail_movement > .0005
                result["joints"][name] = {"limit_degrees": LIMITS[digit][joint], "changed_corrective_vertices": len(changed),
                    "maximum_corrective_delta_m": maximum, "scale_relative_effect_bounds_m": [minimum_effect, maximum_effect],
                    "actual_skin_movement_m": movement, "corrective_after_skinning_m": visible, "nail_movement_m": nail_movement, "nail_seating": seating}
                reset()
        for digit in DIGITS:
            for joint in range(3):
                rig.pose.bones[digit + str(joint)].matrix_basis = original_pose[digit + str(joint)] @ Matrix.Rotation(-math.radians(LIMITS[digit][joint]), 4, "X")
                keys.key_blocks[f"Joint_{digit}_{joint}"].value = 1.0
        bpy.context.view_layer.update()
        full = core.evaluated_points(hand)
        finite_points(full)
        result["all_full_flex_nail_seating"] = {digit: nail_seating(rig, full, digit, context) for digit, context in contexts.items()}
    finally:
        reset()
    assert max((a - b).length for a, b in zip(core.evaluated_points(hand), baseline)) < .000002
    result["neutral_reset_passed"] = True
    return result


def inspect_materials(objects):
    used = {slot.material for obj in objects if obj.type == "MESH" for slot in obj.material_slots}
    assert None not in used and used
    roles = {legacy.role(m) for m in used}
    assert {"Detailed_Skin", "Detailed_Nail"} <= roles <= ALLOWED_ROLES
    legacy.ROLES = roles
    samples, uv_report = legacy.uv_samples(objects)
    result = {"uv": uv_report, "materials": {}, "images": {}}
    images = {}
    bindings = []
    for material in used:
        shaders = [node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"]
        assert len(shaders) == 1
        shader = shaders[0]
        assert shader.inputs["Metallic"].default_value < .001 and shader.inputs["Alpha"].default_value > .99
        row = {}
        for semantic, socket in (("basecolor", "Base Color"), ("normal", "Normal"), ("roughness", "Roughness")):
            textures = legacy.image_nodes(shader.inputs[socket])
            assert len(textures) == 1, "PBR socket lacks one connected baked atlas"
            image = next(iter(textures)).image
            assert image.packed_file and list(image.size) == [4096, 4096]
            assert image.colorspace_settings.is_data == (semantic != "basecolor")
            if semantic == "normal":
                normal_nodes = [n for n in material.node_tree.nodes if n.type == "NORMAL_MAP"]
                assert normal_nodes and all(n.space == "TANGENT" and n.inputs["Strength"].default_value > 0 for n in normal_nodes)
            images[image.name] = image
            bindings.append((legacy.role(material), semantic, image.name))
            row[semantic] = {"image": image.name, "colorspace": image.colorspace_settings.name, "resolution": list(image.size), "packed_bytes": image.packed_file.size}
        result["materials"][material.name] = row
    assert len(images) == 3, "Expected three shared portable PBR atlases"
    for name, image in images.items():
        array = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(array)
        pixels = array.reshape(4096, 4096, image.channels)[:, :, :3]
        assert np.isfinite(pixels).all()
        row = {}
        for role, semantic, image_name in bindings:
            if image_name != name:
                continue
            uv = samples[role]
            xs = np.clip((uv[:, 0] * 4096).astype(int), 0, 4095)
            ys = np.clip((uv[:, 1] * 4096).astype(int), 0, 4095)
            values = pixels[ys, xs]
            stats = legacy.pixel_statistics(values)
            if semantic == "normal":
                assert float(np.std(values[:, :2], axis=0).max()) > .00001, role + " normal atlas is flat on its actual surface"
                stats["godot_rg_decode"] = legacy.decoded_normal_statistics(values)
            elif semantic == "roughness":
                # The glTF packed image uses G for roughness; R/B may be constants.
                assert float(np.std(values[:, 1])) > .0001 and float(np.ptp(values[:, 1])) > .002
                assert float(values[:, 1].min()) > 0.0
            else:
                assert float(np.max(np.std(values, axis=0))) > .00001
                assert not np.any(np.all(values == 0.0, axis=1)), "Actual UV surface samples retain black atlas gaps"
            row[role + "/" + semantic] = stats
        result["images"][name] = row
    return result


def inspect_container(path):
    document, binary = legacy.glb_chunks(path)
    roles = {m["name"].split(".")[0] for m in document["materials"]}
    assert {"Detailed_Skin", "Detailed_Nail"} <= roles <= ALLOWED_ROLES
    legacy.ROLES = roles
    row = legacy.inspect_glb_container(path)
    assert len(document["images"]) == 3
    for image in document["images"]:
        view = document["bufferViews"][image["bufferView"]]
        offset = view.get("byteOffset", 0)
        png = binary[offset:offset + view["byteLength"]]
        assert png[:8] == b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II", png, 16) == (4096, 4096)
    assert len(document.get("skins", [])) == 1
    names = {document["nodes"][index]["name"] for index in document["skins"][0]["joints"]}
    assert names == BONES
    morphs = [mesh for mesh in document["meshes"] if mesh.get("extras", {}).get("targetNames")]
    assert len(morphs) == 1 and morphs[0]["extras"]["targetNames"] == KEYS
    assert all(len(p.get("targets", [])) == 15 and all("POSITION" in target and "NORMAL" in target for target in p["targets"]) for p in morphs[0]["primitives"])
    row["sixteen_joint_names_and_fifteen_position_normal_morphs"] = True
    return row


def uv_error(first, second):
    if not first or not second:
        return float("inf")
    return max(min(math.dist(a, b) for b in second) for a in first)


def compare_roundtrip(actual, expected):
    result = {}
    for label, part in actual["parts"].items():
        reference = expected["parts"][label]
        assert part["deltas"].keys() == reference["deltas"].keys()
        tree = KDTree(len(reference["points"]))
        for index, point in enumerate(reference["points"]):
            tree.insert(Vector(point), index)
        tree.balance()
        maximum_position = maximum_weight = maximum_uv = maximum_delta = 0.0
        expected_weights = reference["expected_export_weights"]
        for index, point in enumerate(part["points"]):
            candidates = tree.find_range(Vector(point), .000005)
            assert candidates, label + " imported vertex has no matching authored point"
            def errors(candidate):
                unused, other, distance = candidate
                weight = legacy.weight_error(part["weights"][index], expected_weights[other])
                shape = max((float(np.linalg.norm(part["deltas"][key][index] - reference["deltas"][key][other])) for key in part["deltas"]), default=0.0)
                return weight, shape, uv_error(part["uv"][index], reference["uv"][other]), distance
            weight, shape, uv, distance = min(errors(candidate) for candidate in candidates)
            maximum_position = max(maximum_position, distance)
            maximum_weight = max(maximum_weight, weight)
            maximum_uv = max(maximum_uv, uv)
            maximum_delta = max(maximum_delta, shape)
        assert maximum_weight < .000001, label + " exported weights differ from the previously used game weights"
        assert maximum_delta < .000002 and maximum_uv < .000002, label + " UV or corrective did not survive export"
        assert sum(len(p) - 2 for p in part["faces"]) == sum(len(p) - 2 for p in reference["faces"])
        if label == "WristCuff":
            assert part["flex"] == reference["flex"]
        result[label] = {"vertices": len(part["points"]), "position_error_m": maximum_position,
            "named_weight_error": maximum_weight, "morph_delta_error_m": maximum_delta, "uv_error": maximum_uv}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True, help="Previously delivered realism iteration04 directory")
    parser.add_argument("--geometry-report", type=Path, required=True, help="Approved geometry stage's geometry_report.json")
    parser.add_argument("--output-dir", type=Path, required=True, help="Final baked reference-hand delivery directory")
    parser.add_argument("--support-dir", type=Path, default=Path(__file__).resolve().parents[2] / "player_hands_realism_20260911/tools", help="Preserved independent snapshot/PBR/Blender helpers")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background, "Validation must not open an interactive Blender window"
    load_support(args.support_dir.resolve())
    source = args.source_dir.resolve()
    output = args.output_dir.resolve()
    geometry_report_path = args.geometry_report.resolve()
    geometry_report = json.loads(geometry_report_path.read_text())
    approved_path = geometry_report_path.parent / "bilateral_hands_reference_geometry.blend"
    source_path = source / "bilateral_hands_realistic.blend"
    final_path = output / "bilateral_hands_reference.blend"
    glbs = {side: output / f"{side}_hand_reference.glb" for side in SIDES}
    inputs = [source_path, approved_path, final_path, geometry_report_path, Path(__file__), args.support_dir / "verify_hands_realistic.py", args.support_dir / "joint_verification_core.py"]
    inputs += list(glbs.values()) + [source / f"{side}_hand_realistic.glb" for side in SIDES]
    hashes = {str(path): sha(path) for path in inputs}
    assert sha(source_path) == geometry_report["source_sha256"] and sha(approved_path) == geometry_report["geometry_blend_sha256"]
    report = {"status": "running", "utc": datetime.now(timezone.utc).isoformat(), "blender_binary": bpy.app.binary_path,
        "blender_version": bpy.app.version_string, "host": platform.platform(), "verified_sha256": hashes, "checks": {}, "errors": [],
        "limitations": ["This is functional/geometry/PBR verification; photographic resemblance requires direct visual approval.",
            "Finger correction size is evaluated relative to current phalanx scale; prior greybox/trim/exact-position limits are not applicable.",
            "Tiny influence removal is accepted only when new game weights match the actual prior exported weights; editable physical-skin weights remain exact.",
            "Actual Godot wrist deformation, camera, renderer and test-room restoration are tested separately."]}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source_path))
        scene, rigs = activate_delivery("Bilateral_Realistic_Review")
        originals = {side: capture(scene, rig) for side, rig in rigs.items()}
        for side in SIDES:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(source / f"{side}_hand_realistic.glb"), bone_heuristic="TEMPERANCE")
            rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
            prior = legacy.snapshot(bpy.context.scene, rig)
            report["checks"]["prior_export_weight_conversion_" + side] = legacy.attach_prior_export_weights(originals[side], prior)
        bpy.ops.wm.open_mainfile(filepath=str(approved_path))
        scene, rigs = activate_delivery("Bilateral_Reference_Review")
        approved = {side: capture(scene, rig) for side, rig in rigs.items()}
        bpy.ops.wm.open_mainfile(filepath=str(final_path))
        scene, rigs = activate_delivery("Bilateral_Reference_Review")
        assert not bpy.data.libraries
        expected = {side: capture(scene, rig) for side, rig in rigs.items()}
        report["checks"]["editable_materials"] = inspect_materials(scene.objects)
        for side, rig in rigs.items():
            row = {"rest": core.compare_rest(rig, originals[side]["rest"]),
                "authored": compare_new_authored(expected[side], originals[side], approved[side]), "articulation": inspect_articulation(scene, rig)}
            report["checks"]["editable_" + side] = row
            for label, part in expected[side]["parts"].items():
                if label == "hand":
                    part["expected_export_weights"] = originals[side]["parts"][label]["prior_export_weights"][:PHYSICAL_VERTICES]
                else:
                    # New nails have rigid distal=1 weights, and unskinned arm
                    # pieces have empty weights. Neither needs tiny-weight conversion.
                    assert all(not weights or (len(weights) == 1 and abs(next(iter(weights.values())) - 1.0) < 1e-7) for weights in part["weights"])
                    part["expected_export_weights"] = part["weights"]
        for side, path in glbs.items():
            row = {"container": inspect_container(path)}
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="TEMPERANCE")
            scene = bpy.context.scene
            rigs = [obj for obj in scene.objects if obj.type == "ARMATURE"]
            assert len(rigs) == 1
            rig = rigs[0]
            row["rest"] = core.compare_rest(rig, originals[side]["rest"])
            assert (core.wrist_world(rig) - Vector((0, -.05625, 0))).length < .00005
            row["roundtrip"] = compare_roundtrip(capture(scene, rig), expected[side])
            row["materials"] = inspect_materials(scene.objects)
            row["articulation"] = inspect_articulation(scene, rig)
            report["checks"][side + "_glb"] = row
    except Exception as error:
        report["errors"].append({"error": str(error), "traceback": traceback.format_exc()})
    assert all(sha(path) == value for path, value in hashes.items()), "Read-only verifier changed an input asset"
    report["status"] = "passed" if not report["errors"] else "failed"
    destination = output / "verification_report.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("REFERENCE_HANDS_VERIFICATION", report["status"], json.dumps(report["errors"]), destination, flush=True)
    if report["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
