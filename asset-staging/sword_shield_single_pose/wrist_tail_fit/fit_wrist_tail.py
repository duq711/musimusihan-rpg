#!/usr/bin/env python3
"""Stage only the wrist extension; preserve every hand/contact/rig attribute.

The authored player hand-root is (0,0,0), fingers -Z, forearm +Z. The
Skeleton's wrist bone head at +56.25mm is NOT this equipment attachment origin.
Only attached skin/glove vertices with hand-root Z>0 receive z/(1+k*z).
No engine, production installation, or new geometry is invoked.
"""
from __future__ import annotations
import hashlib
import importlib.util
import json
import math
from pathlib import Path

STAGE = Path(__file__).resolve().parent
SOURCE = STAGE / "source_proportioned_hands"
spec = importlib.util.spec_from_file_location("hand_glb_math", STAGE.parent / "proportioned_hands/proportion_hands.py")
maths = importlib.util.module_from_spec(spec)
spec.loader.exec_module(maths)
GLB = maths.GLB
K = 30.5
DIGITS = ("little", "ring", "middle", "index", "thumb")
DISTAL_LENGTH = (.0176, .02104, .022, .02024, .025)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify_contact_patches(before, after, globals_, lookup):
    """Independently select real 20-vertex skin patches; no solver metadata."""
    node = before.doc["nodes"][lookup["ContinuousAnatomicalHand"]]
    primitive = before.doc["meshes"][node["mesh"]]["primitives"][0]
    attrs = primitive["attributes"]
    vertices, normals = before.read(attrs["POSITION"]), before.read(attrs["NORMAL"])
    joints, weights = before.read(attrs["JOINTS_0"]), before.read(attrs["WEIGHTS_0"])
    skin = before.doc["skins"][node["skin"]]
    names = [before.doc["nodes"][bone]["name"] for bone in skin["joints"]]
    records = []
    patches = []
    for digit, length in zip(DIGITS, DISTAL_LENGTH):
        distal = lookup[digit + "2"]
        patches.append((digit, digit + "2", maths.point(globals_[distal], (0, length * .82, -.006)), False))
        if digit != "thumb":
            middle = lookup[digit + "1"]
            child_length = maths.norm(before.doc["nodes"][distal]["translation"])
            patches.append((digit + "_middle", digit + "1", maths.point(globals_[middle], (0, child_length * .55, -.007)), False))
            proximal = lookup[digit + "0"]
            child_length = maths.norm(before.doc["nodes"][middle]["translation"])
            patches.append((digit + "_proximal", digit + "0", maths.point(globals_[proximal], (0, child_length * .85, -.007)), False))
            mcp = maths.point(globals_[proximal], (0, 0, 0))
            patches.append((digit + "_palm", "wrist", (mcp[0], -.016, mcp[2] + .018), True))
    for label, weighted_name, reference, palmar in patches:
        candidates = []
        for index, (point, normal, js, ws) in enumerate(zip(vertices, normals, joints, weights)):
            if palmar and normal[1] > -.3:
                continue
            influence = sum(w for j, w in zip(js, ws) if names[j] == weighted_name)
            if influence > .55:
                candidates.append((sum((point[k] - reference[k]) ** 2 for k in range(3)), index))
        selected = [i for _, i in sorted(candidates)[:20]]
        assert len(selected) == 20
        for i in selected:
            assert vertices[i][2] <= 0
            for accessor in attrs.values():
                assert before.raw(accessor, i) == after.raw(accessor, i)
        records.append({"patch": label, "weighted_bone": weighted_name, "sample_count": 20,
                        "indices": selected, "source_reference": reference,
                        "maximum_original_z_m": max(vertices[i][2] for i in selected),
                        "all_original_vertex_attributes_byte_exact": True})
    return records


def stage(side):
    source_path = SOURCE / f"{side}_arm.glb"
    if not source_path.exists():
        source_path.write_bytes((STAGE.parent / "proportioned_hands" / source_path.name).read_bytes())
    original = source_path.read_bytes()
    before, after = GLB(original), GLB(original)
    globals_ = maths.globals_for(before.doc)
    lookup = {node["name"].split(".")[0]: index for index, node in enumerate(before.doc["nodes"])}
    allowed_bytes = set()
    changed_accessors = set()
    records = []
    for label in ("ContinuousAnatomicalHand", "FingerlessLeatherGlove"):
        node_index = lookup[label]
        node = before.doc["nodes"][node_index]
        world, inverse_world = globals_[node_index], maths.inverse(globals_[node_index])
        old_points, new_points, modified_z = [], [], []
        changed_count, preserved_count = 0, 0
        max_formula_error, max_xy_error = 0., 0.
        for primitive in before.doc["meshes"][node["mesh"]]["primitives"]:
            attrs = primitive["attributes"]
            data = {key: before.read(accessor) for key, accessor in attrs.items()}
            for index, local_point in enumerate(data["POSITION"]):
                point = maths.point(world, local_point)
                old_points.append(point)
                new_point = point
                if point[2] > 0:
                    denominator = 1 + K * point[2]
                    new_point = (point[0], point[1], point[2] / denominator)
                    jacobian_world = maths.identity()
                    jacobian_world[2][2] = 1 / denominator ** 2
                    jacobian = maths.mm(maths.mm(inverse_world, jacobian_world), world)
                    normal = maths.unit(maths.vector(maths.transpose3(maths.inverse(jacobian)), data["NORMAL"][index]))
                    tangent = maths.vector(jacobian, data["TANGENT"][index][:3])
                    dot = sum(tangent[k] * normal[k] for k in range(3))
                    tangent = maths.unit(tuple(tangent[k] - normal[k] * dot for k in range(3)))
                    new_local = maths.point(inverse_world, new_point)
                    for semantic, value in (("POSITION", new_local), ("NORMAL", normal), ("TANGENT", tangent + (data["TANGENT"][index][3],))):
                        accessor = attrs[semantic]
                        after.write(accessor, index, value)
                        changed_accessors.add(accessor)
                        _, _, offset, stride, size = after.layout(accessor)
                        allowed_bytes.update(range(offset + index * stride, offset + index * stride + size))
                    changed_count += 1
                    modified_z.append(point[2])
                else:
                    for accessor in attrs.values():
                        assert before.raw(accessor, index) == after.raw(accessor, index)
                    preserved_count += 1
                new_points.append(new_point)
            for semantic, accessor in attrs.items():
                if semantic not in ("POSITION", "NORMAL", "TANGENT"):
                    assert before.raw(accessor) == after.raw(accessor)
            assert before.raw(primitive["indices"]) == after.raw(primitive["indices"])
            # Re-read actual stored float32 values, including normal/tangent.
            for index, (old, new, normal, tangent) in enumerate(zip(data["POSITION"], after.read(attrs["POSITION"]), after.read(attrs["NORMAL"]), after.read(attrs["TANGENT"]))):
                old, new = maths.point(world, old), maths.point(world, new)
                expected_z = old[2] / (1 + K * old[2]) if old[2] > 0 else old[2]
                max_formula_error = max(max_formula_error, abs(new[2] - expected_z))
                max_xy_error = max(max_xy_error, abs(new[0] - old[0]), abs(new[1] - old[1]))
                assert all(math.isfinite(v) for v in new + normal + tangent)
                assert abs(maths.norm(normal) - 1) < 1e-5
                if old[2] > 0:
                    assert abs(maths.norm(tangent[:3]) - 1) < 1e-5
                    assert abs(sum(normal[k] * tangent[k] for k in range(3))) < 1e-5
        assert max_formula_error < 1e-8 and max_xy_error < 1e-8
        records.append({"name": node["name"], "before_bounds": maths.bounds(old_points), "after_bounds": maths.bounds(new_points),
                        "affected_vertex_count": changed_count, "unaffected_vertex_count": preserved_count,
                        "affected_original_z_range_m": [min(modified_z), max(modified_z)],
                        "saved_float32_max_formula_error_m": max_formula_error, "saved_float32_max_xy_change_m": max_xy_error})
    assert len(before.bin) == len(after.bin)
    assert all(a == b or index in allowed_bytes for index, (a, b) in enumerate(zip(before.bin, after.bin)))
    for name in ("nodes", "skins", "meshes", "materials", "textures", "images", "samplers", "bufferViews"):
        assert before.doc.get(name) == after.doc.get(name)
    protected = []
    for node in before.doc["nodes"]:
        if "mesh" in node and "skin" not in node:
            digest = maths.mesh_hash(before, node)
            assert digest == maths.mesh_hash(after, node)
            protected.append({"name": node["name"], "unchanged_sha256": digest})
    for skin in before.doc["skins"]:
        assert before.raw(skin["inverseBindMatrices"]) == after.raw(skin["inverseBindMatrices"])
    patches = verify_contact_patches(before, after, globals_, lookup)
    for accessor in changed_accessors:
        after.refresh_bounds(accessor)
    output = after.encode()
    path = STAGE / f"{side}_arm.glb"
    path.write_bytes(output)
    saved = GLB(path.read_bytes())
    assert saved.bin == after.bin
    verify_contact_patches(before, saved, globals_, lookup)
    return {"side": side, "source": str(source_path.relative_to(STAGE)), "output": path.name,
            "source_sha256": sha(original), "output_sha256": sha(output), "k_per_metre": K,
            "coordinate_frame": "authored player hand-root; fingers -Z, forearm +Z; root origin is not the wrist bone head",
            "formula": "z_new = z/(1+30.5*z) only for z>0; x/y unchanged; z<=0 byte-exact",
            "continuity": "value and first derivative agree with identity at z=0; dz_new/dz=1/(1+30.5*z)^2>0",
            "normals_tangents": "inverse-transpose axial Jacobian; forward tangent Jacobian, orthogonalized and normalized; original tangent handedness retained",
            "meshes": records, "independent_real_skin_contact_patches": patches, "rigid_meshes": protected,
            "nodes_bones_rotations_inverse_binds_weights_uv_topology_materials_preserved": True,
            "all_unaffected_original_binary_bytes_preserved": True,
            "production_install_engine_import_and_render_validation": "pending; root only"}


def main():
    SOURCE.mkdir(parents=True, exist_ok=True)
    report = {"task": "Only shorten the exposed wrist tail; retain finger and palm contacts", "arms": [stage(side) for side in ("left", "right")]}
    (STAGE / "preservation_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps([{key: arm[key] for key in ("side", "output_sha256", "meshes")} for arm in report["arms"]], indent=2))


if __name__ == "__main__":
    main()
