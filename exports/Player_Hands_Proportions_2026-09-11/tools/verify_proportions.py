"""Read-only validation of the original gloved hands with proportions changed.

No rebake, nail redesign, bare-hand constraints or old fixed bone positions are
assumed. Visual proportion approval is separate from these functional checks.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import sys
import tempfile
import traceback
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

DIGITS = ("thumb", "index", "middle", "ring", "little")
KEYS = [f"Joint_{digit}_{joint}" for digit in DIGITS for joint in range(3)]
BONES = {"wrist"} | {digit + str(joint) for digit in DIGITS for joint in range(3)}
ROLES = {"Detailed_Skin", "Detailed_Glove", "Detailed_Nail", "Detailed_Sleeve", "Detailed_Trim"}
legacy = core = None


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scene_rigs(name):
    scene = bpy.data.scenes[name]
    core.activate(scene)
    rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: core.wrist_world(o).x)
    assert len(rigs) == 2
    return scene, dict(zip(("left", "right"), rigs))


def value(item):
    if item is None or isinstance(item, (str, bool, int, float)):
        return item
    if isinstance(item, bpy.types.ID):
        return [item.bl_rna.identifier, item.name]
    try:
        return [value(v) for v in item]
    except TypeError:
        return str(item)


def material_payload(scene):
    objects = [o for o in scene.objects if o.type == "MESH"]
    materials = {slot.material for o in objects for slot in o.material_slots}
    assert None not in materials
    assert {legacy.role(m) for m in materials} == ROLES
    result = {}
    for material in materials:
        assert material.use_nodes
        nodes, images = {}, {}
        for node in material.node_tree.nodes:
            nodes[node.name] = {"type": node.bl_idname,
                "inputs": [(s.identifier, value(getattr(s, "default_value", None))) for s in node.inputs],
                "outputs": [(s.identifier, value(getattr(s, "default_value", None))) for s in node.outputs],
                "image": getattr(getattr(node, "image", None), "name", None),
                "space": getattr(node, "space", None), "uv_map": getattr(node, "uv_map", None),
                "interpolation": getattr(node, "interpolation", None), "extension": getattr(node, "extension", None),
                "operation": getattr(node, "operation", None), "blend_type": getattr(node, "blend_type", None)}
            image = getattr(node, "image", None)
            if image:
                images[image.name] = {"size": list(image.size), "colorspace": image.colorspace_settings.name,
                    "packed": [hashlib.sha256(p.packed_file.data).hexdigest() for p in image.packed_files]}
                assert images[image.name]["packed"]
        result[material.name] = {"diffuse": list(material.diffuse_color), "roughness": material.roughness,
            "metallic": material.metallic, "nodes": nodes, "images": images,
            "links": sorted((l.from_node.name, l.from_socket.identifier, l.to_node.name, l.to_socket.identifier) for l in material.node_tree.links)}
    return result


def capture(scene, rig):
    result = legacy.snapshot(scene, rig)
    native = legacy.native_matrix(rig, rig)
    result["bone_points"] = {b.name: {"head": list(native @ b.head_local), "tail": list(native @ b.tail_local),
        "x": list((native.to_3x3() @ b.matrix_local.to_3x3().col[0]).normalized())} for b in rig.data.bones}
    for label, obj in legacy.parts_for(scene, rig).items():
        part = result["parts"][label]
        part["materials"] = [m.name for m in obj.data.materials]
        part["face_materials"] = [p.material_index for p in obj.data.polygons]
        part["uv_layers"] = {u.name: [tuple(p.uv) for p in u.data] for u in obj.data.uv_layers}
        per_vertex = [set() for unused in obj.data.vertices]
        if obj.data.uv_layers.active:
            for loop in obj.data.loops:
                per_vertex[loop.vertex_index].add(tuple(obj.data.uv_layers.active.data[loop.index].uv))
        part["uv_sets"] = [list(uv) for uv in per_vertex]
    return result


def compare_authored(current, source, expected_warp):
    assert set(current["rest"]) == set(source["rest"]) == BONES
    result = {"parts": {}, "bones": {}}
    for name, bone in current["rest"].items():
        assert bone["parent"] == source["rest"][name]["parent"]
        rotation = np.asarray(bone["matrix"])[:3, :3]
        assert np.max(np.abs(rotation.T @ rotation - np.eye(3))) < 2e-5 and np.linalg.det(rotation) > .9999
        target = expected_warp["bones"][name]
        error = max(math.dist(current["bone_points"][name][field], target[field]) for field in ("head", "tail"))
        assert error < 2e-6, "Rest head/tail does not follow proportion map: " + name
        result["bones"][name] = {"mapped_head_tail_error_m": error}
    assert math.dist(current["bone_points"]["wrist"]["head"], source["bone_points"]["wrist"]["head"]) < 2e-7
    assert len(current["parts"]["hand"]["points"]) == 14988, "The original glove, trim or skin was removed"
    for label, part in current["parts"].items():
        old = source["parts"][label]
        assert part["points"].shape == old["points"].shape and part["faces"] == old["faces"], "Topology changed: " + label
        assert part["weights"] == old["weights"], "Named weights changed: " + label
        assert part["materials"] == old["materials"] and part["face_materials"] == old["face_materials"]
        assert part["uv_layers"] == old["uv_layers"], "UVs changed: " + label
        assert part["flex"] == old["flex"], "Original cuff contract changed"
        assert list(part["deltas"]) == list(old["deltas"])
        target = expected_warp["parts"][label]
        position_error = float(np.linalg.norm(part["points"] - target["points"], axis=1).max())
        assert position_error < 2e-6, "Authored surface does not follow proportion map: " + label
        correction_error = 0.0
        for key, points in target["keys"].items():
            indices = points["indices"]
            actual = part["points"][indices] + part["deltas"][key][indices]
            correction_error = max(correction_error, float(np.linalg.norm(actual - points["points"], axis=1).max()))
            inactive = np.linalg.norm(old["deltas"][key], axis=1) == 0
            assert float(np.linalg.norm(part["deltas"][key][inactive], axis=1).max(initial=0)) < 2e-7
        assert correction_error < 2e-6
        result["parts"][label] = {"vertices": len(part["points"]), "topology_uv_material_weights_exact": True,
            "mapped_position_error_m": position_error, "sampled_mapped_corrective_error_m": correction_error}
        if label == "hand":
            result["corrective_support"] = inspect_support(current, source, expected_warp)
    return result


def inspect_support(current, source, expected):
    result = {}
    old, part = source["parts"]["hand"], current["parts"]["hand"]
    for key, delta in part["deltas"].items():
        digit, joint = key.split("_")[1:]
        name = digit + joint
        active = np.linalg.norm(delta, axis=1) >= 1e-6
        original_support = np.linalg.norm(old["deltas"][key], axis=1) > 0
        new_support = int(np.count_nonzero(active & ~original_support))
        assert new_support == 0, "Corrective gained a previously unaffected vertex: " + key
        def extent(snapshot, indices):
            bone = snapshot["bone_points"][name]
            head, tail = np.asarray(bone["head"]), np.asarray(bone["tail"])
            axis = (tail - head) / np.linalg.norm(tail - head)
            return float(np.abs((snapshot["parts"]["hand"]["points"][indices] - head) @ axis).max(initial=0))
        row = {"original_nonzero_support_vertices": int(original_support.sum()), "current_above_1um_vertices": int(active.sum()),
            "new_previously_unaffected_vertices": new_support, "original_support_axial_m": extent(source, original_support),
            "current_support_axial_m": extent(current, active)}
        if key in ("Joint_middle_1", "Joint_ring_1"):
            target = expected["parts"]["hand"]["keys"][key]
            indices = target["indices"]
            assert len(indices) == int(original_support.sum())
            error = float(np.linalg.norm(part["points"][indices] + delta[indices] - target["points"], axis=1).max())
            assert error < 2e-6
            row["all_original_active_vertices_follow_W"] = True
            row["all_active_W_error_m"] = error
            assert row["current_support_axial_m"] < .015
        result[key] = row
    return result


def expected_mapping(source, mapping):
    def digit_weights(weights):
        return {digit: sum(weight for name, weight in weights.items() if name.startswith(digit)) for digit in DIGITS}
    def mapped(points, weights):
        return np.asarray([mapping.warp(Vector(p), w) for p, w in zip(points, weights)], dtype=float)
    result = {"parts": {}, "bones": {}}
    for name, bone in source["bone_points"].items():
        weights = {} if name == "wrist" else {next(d for d in DIGITS if name.startswith(d)): 1.0}
        result["bones"][name] = {field: list(bone[field]) if name == "wrist" else list(mapping.warp(Vector(bone[field]), weights)) for field in ("head", "tail")}
    for label, part in source["parts"].items():
        weights = [digit_weights(w) for w in part["weights"]]
        row = {"points": mapped(part["points"], weights), "keys": {}}
        for key, delta in part["deltas"].items():
            active = np.flatnonzero(np.linalg.norm(delta, axis=1) > 0)
            assert len(active) >= 8
            indices = active if key in ("Joint_middle_1", "Joint_ring_1") else active[np.linspace(0, len(active) - 1, min(128, len(active)), dtype=int)]
            row["keys"][key] = {"indices": indices, "points": mapped(part["points"][indices] + delta[indices], [weights[i] for i in indices])}
        result["parts"][label] = row
    # This local derivative holds influences fixed. It checks the declared
    # section map, not a global no-self-intersection claim across skin weights.
    points = source["parts"]["hand"]["points"][::97]
    weights = [digit_weights(w) for w in source["parts"]["hand"]["weights"][::97]]
    step = 1e-6
    jac = np.stack([(mapped(points + np.eye(3)[axis] * step, weights) - mapped(points - np.eye(3)[axis] * step, weights)) / (2 * step) for axis in range(3)], axis=2)
    determinants = np.linalg.det(jac)
    assert np.isfinite(determinants).all() and float(determinants.min()) > 0
    result["sampled_minimum_map_jacobian"] = float(determinants.min())
    return result


def inspect_pose(scene, rig):
    assert set(rig.data.bones.keys()) == BONES
    hand = next(o for o in core.rigged_meshes(scene, rig) if "Anatomical" in o.name)
    keys = hand.data.shape_keys
    assert keys and [k.name for k in keys.key_blocks[1:]] == KEYS and keys.use_relative
    assert all(abs(k.value) < 1e-8 for k in keys.key_blocks[1:])
    saved = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    assert all(np.max(np.abs(np.asarray(m) - np.eye(4))) < 1e-6 for m in saved.values())
    weights = [{hand.vertex_groups[g.group].name: g.weight for g in p.groups} for p in hand.data.vertices]
    baseline = core.evaluated_points(hand)
    nails = {d: next(o for o in core.rigged_meshes(scene, rig) if o.name.startswith("Nail_" + d)) for d in DIGITS}
    local_nails = {d: [(rig.matrix_world @ rig.pose.bones[d + "2"].matrix).inverted() @ p for p in core.evaluated_points(n)] for d, n in nails.items()}
    result = {}
    def reset():
        for b in rig.pose.bones:
            b.matrix_basis = saved[b.name]
        for key in keys.key_blocks[1:]:
            key.value = 0
        bpy.context.view_layer.update()
    try:
        for digit in DIGITS:
            unrelated = [i for i, w in enumerate(weights) if not any(n.startswith(digit) and v > 0 for n, v in w.items())]
            for joint in range(3):
                name = digit + str(joint)
                limit = (60, 70, 80)[joint] if digit == "thumb" else (90, 110, 80)[joint]
                rig.pose.bones[name].matrix_basis = saved[name] @ Matrix.Rotation(-math.radians(limit), 4, "X")
                bpy.context.view_layer.update()
                flexed = core.evaluated_points(hand)
                movement = max((a - b).length for a, b in zip(flexed, baseline))
                assert movement > .001
                assert max(((flexed[i] - baseline[i]).length for i in unrelated), default=0) < 3e-6
                assert all(b.matrix_basis == saved[b.name] for b in rig.pose.bones if b.name != name)
                keys.key_blocks[f"Joint_{digit}_{joint}"].value = 1
                bpy.context.view_layer.update()
                corrected = core.evaluated_points(hand)
                effect = max((a - b).length for a, b in zip(corrected, flexed))
                assert effect > 1e-6 and all(math.isfinite(v) for p in corrected for v in p)
                bone_inverse = (rig.matrix_world @ rig.pose.bones[digit + "2"].matrix).inverted()
                nail_error = max(((bone_inverse @ p - q).length for p, q in zip(core.evaluated_points(nails[digit]), local_nails[digit])))
                assert nail_error < 2e-5
                result[name] = {"limit_degrees": limit, "actual_skin_movement_m": movement,
                    "actual_corrective_effect_m": effect, "nail_bone_local_error_m": nail_error}
                reset()
    finally:
        reset()
    assert max((a - b).length for a, b in zip(core.evaluated_points(hand), baseline)) < 2e-6
    return {"joints": result, "neutral_reset": True}


def inspect_glb_unchanged_materials(path, original):
    current, binary = legacy.glb_chunks(path)
    old, old_binary = legacy.glb_chunks(original)
    assert current["materials"] == old["materials"], "glTF material definitions changed"
    assert current.get("textures") == old.get("textures") and current.get("samplers") == old.get("samplers")
    def images(document, data):
        result = []
        for image in document["images"]:
            view = document["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            raw = data[start:start + view["byteLength"]]
            result.append((image.get("name", ""), raw, hashlib.sha256(raw).hexdigest()))
        return result
    def decoded_rgba(raw):
        with tempfile.NamedTemporaryFile(suffix=".png") as temporary:
            temporary.write(raw)
            temporary.flush()
            image = bpy.data.images.load(temporary.name, check_existing=False)
            try:
                image.colorspace_settings.name = "Non-Color"
                assert tuple(image.size) == (4096, 4096)
                pixels = np.empty(4096 * 4096 * 4, dtype=np.float32)
                image.pixels.foreach_get(pixels)
                assert np.isfinite(pixels).all()
                rgba = np.rint(pixels * 255).astype(np.uint8)
                assert np.max(np.abs(pixels - rgba.astype(np.float32) / 255)) < 1e-6
                return rgba.reshape(4096, 4096, 4)
            finally:
                bpy.data.images.remove(image)
    embedded = []
    for new, prior in zip(images(current, binary), images(old, old_binary)):
        assert new[0] == prior[0]
        row = {"name": new[0], "original_blob_sha256": prior[2], "output_blob_sha256": new[2], "blob_exact": new[2] == prior[2]}
        if not row["blob_exact"]:
            assert "roughness" in new[0].lower(), "Only lossless roughness PNG re-encoding is permitted"
            a, b = decoded_rgba(new[1]), decoded_rgba(prior[1])
            mismatch = int(np.count_nonzero(np.any(a != b, axis=2)))
            assert mismatch == 0, "Embedded roughness pixel data changed"
            row.update({"lossless_reencoded_png": True, "rgba_pixel_sha256_bottom_up": hashlib.sha256(a.tobytes()).hexdigest(),
                "rgba_pixels": 4096 * 4096, "mismatched_pixels": mismatch})
        embedded.append(row)
    assert len(embedded) == len(current["images"]) == len(old["images"]) == 3
    legacy.ROLES = ROLES
    return {"container": legacy.inspect_glb_container(path), "material_json_exact": True,
        "embedded_original_images": embedded}


def roundtrip(actual, expected):
    result = {}
    assert set(actual["rest"]) == set(expected["rest"])
    rest_error = max(np.max(np.abs(np.asarray(actual["rest"][n]["matrix"]) - expected["rest"][n]["matrix"])) for n in actual["rest"])
    assert rest_error < 5e-5
    for label, part in actual["parts"].items():
        source = expected["parts"][label]
        assert list(part["deltas"]) == list(source["deltas"])
        tree = KDTree(len(source["points"]))
        for index, point in enumerate(source["points"]):
            tree.insert(Vector(point), index)
        tree.balance()
        errors = [0.0] * 4
        for index, point in enumerate(part["points"]):
            candidates = tree.find_range(Vector(point), 5e-6)
            assert candidates, "Exported vertex lacks an authored match: " + label
            def measures(row):
                unused, match, distance = row
                weight = legacy.weight_error(part["weights"][index], source["prior_export_weights"][match])
                morph = max((float(np.linalg.norm(part["deltas"][key][index] - source["deltas"][key][match])) for key in part["deltas"]), default=0)
                uv = max((min(math.dist(a, b) for b in source["uv_sets"][match]) for a in part["uv_sets"][index]), default=float("inf"))
                return weight, morph, uv, distance
            candidate = min(measures(row) for row in candidates)
            errors = [max(a, b) for a, b in zip(errors, candidate)]
        assert errors[0] < 1e-6 and errors[1] < 2e-6 and errors[2] < 2e-6
        assert sum(len(f) - 2 for f in part["faces"]) == sum(len(f) - 2 for f in source["faces"])
        result[label] = dict(zip(("named_weight_error", "morph_error_m", "uv_error", "position_error_m"), errors))
    return {"parts": result, "rest_matrix_error": float(rest_error)}


def main():
    global legacy, core
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--warp-module", type=Path, required=True)
    parser.add_argument("--scene", default="Bilateral_Realistic_Review")
    parser.add_argument("--blend-name", default="bilateral_hands_proportions.blend")
    parser.add_argument("--support-dir", type=Path, default=Path(__file__).resolve().parents[2] / "player_hands_realism_20260911/tools")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background
    legacy = load_module(args.support_dir / "verify_hands_realistic.py", "proportion_legacy_support")
    core = legacy.core
    warp_module = load_module(args.warp_module, "proportion_warp_contract")
    source, output = args.source_dir.resolve(), args.output_dir.resolve()
    source_blend, final_blend = source / "bilateral_hands_realistic.blend", output / args.blend_name
    glbs = {s: output / f"{s}_hand_proportions.glb" for s in ("left", "right")}
    inputs = [source_blend, final_blend, *glbs.values(), args.warp_module, Path(__file__), args.support_dir / "verify_hands_realistic.py", args.support_dir / "joint_verification_core.py"]
    inputs += [source / f"{side}_hand_realistic.glb" for side in glbs]
    hashes = {str(p.resolve()): sha(p) for p in inputs}
    report = {"status": "running", "verified_sha256": hashes, "checks": {}, "errors": [],
        "limitations": ["Visual similarity is decided from matched-view original/proportion renders, not numeric PASS.", "All basis vertices and bone endpoints are compared to the declared W; corrective W consistency uses all active middle1/ring1 vertices and up to128 active samples for other keys plus unchanged inactive support.", "The supplied pure W implementation is used only for map consistency; preservation, actual articulation and GLB comparisons are independent."]}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source_blend))
        scene, rigs = scene_rigs("Bilateral_Realistic_Review")
        original_materials = material_payload(scene)
        originals = {s: capture(scene, rig) for s, rig in rigs.items()}
        expected = {}
        for side, rig in rigs.items():
            hand = legacy.parts_for(scene, rig)["hand"]
            expected[side] = expected_mapping(originals[side], warp_module.ProportionMap(rig.parent, rig, hand))
        for side in glbs:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(source / f"{side}_hand_realistic.glb"), bone_heuristic="TEMPERANCE")
            rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
            legacy.attach_prior_export_weights(originals[side], legacy.snapshot(bpy.context.scene, rig))
        bpy.ops.wm.open_mainfile(filepath=str(final_blend))
        scene, rigs = scene_rigs(args.scene)
        assert material_payload(scene) == original_materials, "Original material graphs or packed images changed"
        current = {side: capture(scene, rig) for side, rig in rigs.items()}
        for side, rig in rigs.items():
            report["checks"]["editable_" + side] = {"preservation": compare_authored(current[side], originals[side], expected[side]),
                "map_minimum_sampled_jacobian": expected[side]["sampled_minimum_map_jacobian"], "articulation": inspect_pose(scene, rig)}
            for label, part in current[side]["parts"].items():
                part["prior_export_weights"] = originals[side]["parts"][label]["prior_export_weights"]
        for side, path in glbs.items():
            row = inspect_glb_unchanged_materials(path, source / f"{side}_hand_realistic.glb")
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="TEMPERANCE")
            scene = bpy.context.scene
            rig = next(o for o in scene.objects if o.type == "ARMATURE")
            row["roundtrip"] = roundtrip(capture(scene, rig), current[side])
            row["articulation"] = inspect_pose(scene, rig)
            report["checks"][side + "_glb"] = row
    except Exception as error:
        report["errors"].append({"error": str(error), "traceback": traceback.format_exc()})
    assert all(sha(path) == value for path, value in hashes.items()), "A read-only validation input changed"
    report["status"] = "failed" if report["errors"] else "passed"
    (output / "verification_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("PROPORTION_HANDS_VERIFICATION", report["status"], json.dumps(report["errors"]), flush=True)
    if report["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
