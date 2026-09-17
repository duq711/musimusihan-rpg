"""Independent, read-only Blender verification of the realistic hand delivery.

Compares the prior wrist-refined source with the editable model and both GLB
round trips. Asset geometry is never saved by this verifier.
"""
import argparse
import hashlib
import importlib.util
import json
import math
import platform
import struct
import sys
import tempfile
import traceback
from datetime import datetime, timezone
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

spec = importlib.util.spec_from_file_location("realistic_joint_core", Path(__file__).with_name("joint_verification_core.py"))
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)
SIDES = ("left", "right")
DIGITS = ("thumb", "index", "middle", "ring", "little")
ROLES = {"Detailed_Skin", "Detailed_Glove", "Detailed_Sleeve", "Detailed_Nail", "Detailed_Trim"}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def role(material):
    return material.name.split(".")[0]


def activate_bilateral():
    scenes = [s for s in bpy.data.scenes if len([o for o in s.objects if o.type == "ARMATURE"]) == 2]
    assert len(scenes) == 1, "Delivery needs one unambiguous bilateral review scene"
    scene = scenes[0]
    core.activate(scene)
    rigs = sorted((o for o in scene.objects if o.type == "ARMATURE"), key=lambda o: core.wrist_world(o).x)
    return scene, rigs


def native_matrix(obj, rig):
    return Matrix.Translation((-core.wrist_world(rig).x, 0, 0)) @ obj.matrix_world


def parts_for(scene, rig):
    parts = {}
    for obj in core.rigged_meshes(scene, rig):
        if "anatomicalhand" in obj.name.lower():
            parts["hand"] = obj
        else:
            for digit in DIGITS:
                if obj.name.startswith("Nail_" + digit):
                    parts["nail_" + digit] = obj
    for prefix in ("WristCuff", "Forearm", "UpperArm"):
        candidates = [o for o in scene.objects if o.type == "MESH" and o.name.startswith(prefix)]
        assert candidates, f"Missing {prefix} surface"
        parts[prefix] = min(candidates, key=lambda o: abs(o.matrix_world.translation.x - rig.matrix_world.translation.x))
    assert len(parts) == 9, "Expected hand, five rigid nails, and three arm surfaces"
    return parts


def points_from(data):
    points = np.empty(len(data) * 3, dtype=np.float32)
    data.foreach_get("co", points)
    return points.reshape(-1, 3).astype(np.float64)


def snapshot(scene, rig):
    result = {"rest": core.rest_signature(rig), "parts": {}}
    for label, obj in parts_for(scene, rig).items():
        transform = np.asarray(native_matrix(obj, rig), dtype=np.float64)
        coords = points_from(obj.data.vertices)
        group_names = {g.index: g.name for g in obj.vertex_groups}
        keys = obj.data.shape_keys
        deltas = {}
        if keys:
            basis = points_from(keys.key_blocks[0].data)
            deltas = {k.name: (points_from(k.data) - basis) @ transform[:3, :3].T for k in keys.key_blocks[1:]}
        result["parts"][label] = {
            "points": coords @ transform[:3, :3].T + transform[:3, 3],
            "faces": [tuple(p.vertices) for p in obj.data.polygons],
            "weights": [{group_names[g.group]: g.weight for g in v.groups} for v in obj.data.vertices],
            "deltas": deltas,
            "flex": {key: obj.get(key) for key in ("wrist_flex_version", "wrist_flex_start_z", "wrist_flex_end_z")},
        }
    return result


def weight_error(first, second):
    names = set(first) | set(second)
    return max((abs(first.get(k, 0.0) - second.get(k, 0.0)) for k in names), default=0.0)


def attach_prior_export_weights(editable, exported):
    """Use actual previous game weights, not an assumed exporter threshold.

    Blender's glTF exporter has historically discarded sub-0.0001 influences.
    The editable weights must remain exact; new exported weights must equal the
    previous export. This records the old conversion without repeating it.
    """
    report = {}
    for label, source in editable["parts"].items():
        old_glb = exported["parts"][label]
        tree = KDTree(len(old_glb["points"]))
        for index, point in enumerate(old_glb["points"]): tree.insert(Vector(point), index)
        tree.balance()
        mapped, maximum, changed = [], 0.0, 0
        for index, point in enumerate(source["points"]):
            candidates = tree.find_range(Vector(point), .000005)
            assert candidates, f"Prior GLB does not represent {label} editable vertex {index}"
            selected = min(candidates, key=lambda row: weight_error(source["weights"][index], old_glb["weights"][row[1]]))[1]
            weights = old_glb["weights"][selected]
            error = weight_error(source["weights"][index], weights)
            maximum = max(maximum, error)
            changed += error > 1e-6
            mapped.append(weights)
        source["prior_export_weights"] = mapped
        report[label] = {"vertices": len(mapped), "prior_blend_to_glb_changed_weight_vertices": changed,
                         "prior_blend_to_glb_maximum_weight_difference": maximum,
                         "new_export_comparison": "Exact named-weight comparison with actual previous GLB, tolerance 1e-6"}
    return report


def compare_authored(scene, rig, before):
    after = snapshot(scene, rig)
    result = {"rest": core.compare_rest(rig, before["rest"]), "parts": {}}
    for label, old in before["parts"].items():
        new = after["parts"][label]
        assert old["points"].shape == new["points"].shape, f"{label} vertex topology changed"
        assert old["faces"] == new["faces"], f"{label} face topology changed"
        distances = np.linalg.norm(old["points"] - new["points"], axis=1)
        weight_max = max(weight_error(a, b) for a, b in zip(old["weights"], new["weights"]))
        assert weight_max < 1e-6, f"{label} source skin weights changed"
        assert old["deltas"].keys() == new["deltas"].keys(), f"{label} corrective names changed"
        delta_max = max((float(np.linalg.norm(old["deltas"][k] - new["deltas"][k], axis=1).max()) for k in old["deltas"]), default=0.0)
        assert delta_max < 2e-7, f"{label} original corrective deltas changed"
        row = {"vertices": len(distances), "faces": len(old["faces"]), "max_position_change_m": float(distances.max()),
               "max_weight_error": weight_max, "max_corrective_delta_error_m": delta_max}
        if label == "hand":
            changed = distances > .00001
            assert int(changed.sum()) >= 100 and .00003 < float(distances.max()) < .003, "Hand lacks restrained measurable anatomy refinement"
            protected = old["points"][:, 1] <= .010
            assert int(protected.sum()) >= 100 and float(distances[protected].max()) < 2e-7, "Protected wrist geometry changed"
            nail_points = np.concatenate([before["parts"]["nail_" + d]["points"] for d in DIGITS])
            tree = KDTree(len(nail_points))
            for i, p in enumerate(nail_points): tree.insert(Vector(p), i)
            tree.balance()
            nail_bed = np.array([tree.find(Vector(p))[2] < .0008 for p in old["points"]])
            assert int(nail_bed.sum()) >= 20, "Nail-bed protection audit has no real surface samples"
            assert float(distances[nail_bed].max()) < .00002, "Sculpting disturbed the protected nail contact bed"
            row.update({"changed_over_0_01_mm": int(changed.sum()), "protected_wrist_vertices": int(protected.sum()),
                        "max_protected_wrist_change_m": float(distances[protected].max()), "protected_nail_bed_vertices": int(nail_bed.sum()),
                        "max_protected_nail_bed_change_m": float(distances[nail_bed].max())})
        else:
            assert float(distances.max()) < 2e-7, f"Protected {label} geometry changed"
        if label == "WristCuff":
            assert old["flex"] == new["flex"], "Flexible cuff metadata changed"
            assert new["flex"]["wrist_flex_version"] == 1 and abs(new["flex"]["wrist_flex_start_z"] - .014) < 1e-8 and abs(new["flex"]["wrist_flex_end_z"] - .075) < 1e-8
        result["parts"][label] = row
    return result, after


def image_nodes(socket, visited=None):
    visited = set() if visited is None else visited
    found = set()
    for link in socket.links:
        node = link.from_node
        if node in visited:
            continue
        visited.add(node)
        if node.type == "TEX_IMAGE":
            assert node.image is not None, "Empty image texture node"
            found.add(node)
        else:
            for input_socket in node.inputs:
                found.update(image_nodes(input_socket, visited))
    return found


def uv_samples(objects):
    result = {name: [] for name in ROLES}
    area = {name: [] for name in ROLES}
    for obj in objects:
        if obj.type != "MESH": continue
        uv_layer = obj.data.uv_layers.active
        assert uv_layer is not None, f"{obj.name} has no UV map"
        for face in obj.data.polygons:
            material_role = role(obj.material_slots[face.material_index].material)
            assert material_role in ROLES
            uv = [np.asarray(uv_layer.data[i].uv, dtype=np.float64) for i in face.loop_indices]
            assert all(np.isfinite(p).all() for p in uv), "Nonfinite texture coordinates"
            result[material_role].append(np.mean(uv, axis=0))
            for i in range(1, len(uv) - 1):
                a, b = uv[i] - uv[0], uv[i + 1] - uv[0]
                area[material_role].append(abs(a[0] * b[1] - a[1] * b[0]) * .5)
    report = {}
    for name in ROLES:
        points = np.asarray(result[name], dtype=np.float64)
        assert len(points) >= 12, f"{name} has no actual UV sample coverage"
        nondegenerate = float(np.mean(np.asarray(area[name]) > 1e-12))
        assert nondegenerate > .95, f"{name} has degenerate texture UVs"
        assert np.ptp(points, axis=0).min() > .002, f"{name} UV distribution collapsed"
        report[name] = {"sampled_face_centers": len(points), "nondegenerate_triangles_fraction": nondegenerate,
                        "uv_min": points.min(axis=0).tolist(), "uv_max": points.max(axis=0).tolist()}
        result[name] = points
    return result, report


def pixel_statistics(values):
    assert np.isfinite(values).all(), "Texture contains nonfinite pixels"
    return {"minimum": values.min(axis=0).tolist(), "maximum": values.max(axis=0).tolist(),
            "standard_deviation": values.std(axis=0).tolist(), "mean": values.mean(axis=0).tolist()}


def inspect_materials(objects):
    objects = list(objects)
    materials = {slot.material for obj in objects if obj.type == "MESH" for slot in obj.material_slots}
    assert None not in materials and {role(m) for m in materials} == ROLES, "Five authored material roles must remain"
    samples, uv_report = uv_samples(objects)
    bindings, images, result = {}, {}, {"uv": uv_report, "materials": {}, "images": {}}
    for material in materials:
        assert material.use_nodes
        shaders = [n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"]
        assert len(shaders) == 1, "Expected one portable PBR surface shader"
        shader = shaders[0]
        if role(material) in {"Detailed_Skin", "Detailed_Nail"}:
            assert shader.inputs["Metallic"].default_value < .001, "Skin or nail was converted into a metallic surface"
            assert shader.inputs["Alpha"].default_value > .99, "Hand skin unexpectedly became transparent"
        row = {}
        for semantic, socket in (("base_color", "Base Color"), ("normal", "Normal"), ("roughness", "Roughness")):
            nodes = image_nodes(shader.inputs[socket])
            assert len(nodes) == 1, f"{material.name}/{semantic} needs one actually connected baked texture"
            node = next(iter(nodes))
            image = node.image
            assert image.packed_file is not None, f"{image.name} remains an external file dependency"
            assert image.size[0] >= 2048 and image.size[1] >= 2048, "Realistic maps need adequate hand detail resolution"
            if semantic != "base_color":
                assert image.colorspace_settings.is_data, f"{semantic} is being decoded as color"
            else:
                assert not image.colorspace_settings.is_data, "Base color lacks color decoding"
            if semantic == "normal":
                normal_maps = [n for n in material.node_tree.nodes if n.type == "NORMAL_MAP"]
                assert normal_maps and all(n.space == "TANGENT" for n in normal_maps), "Normals must use portable tangent space"
                assert any(n.inputs["Strength"].default_value > 0.0 for n in normal_maps), "Normal map is disabled"
            channel = None
            if semantic == "roughness" and shader.inputs[socket].links:
                link = shader.inputs[socket].links[0]
                if link.from_node.type in {"SEPARATE_COLOR", "SEPRGB"}:
                    channel = {"Red": 0, "Green": 1, "Blue": 2, "R": 0, "G": 1, "B": 2}.get(link.from_socket.name)
            bindings[(role(material), semantic)] = (image, channel)
            images[image.name] = image
            row[semantic] = {"image": image.name, "channel": channel, "colorspace": image.colorspace_settings.name,
                             "size": list(image.size), "packed_bytes": image.packed_file.size}
        result["materials"][material.name] = row
    for name, image in images.items():
        width, height = image.size
        pixels = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(pixels)
        pixels = pixels.reshape(height, width, image.channels)
        stride = max(1, min(width, height) // 512)
        image_row = {"global": pixel_statistics(pixels[::stride, ::stride, :3].reshape(-1, 3)), "used_surface": {}}
        for (material_role, semantic), (bound_image, channel) in bindings.items():
            if bound_image != image: continue
            uv = samples[material_role]
            x = np.clip((np.mod(uv[:, 0], 1.0) * width).astype(np.int64), 0, width - 1)
            y = np.clip((np.mod(uv[:, 1], 1.0) * height).astype(np.int64), 0, height - 1)
            used = pixels[y, x, :3]
            stats = pixel_statistics(used)
            if semantic == "base_color":
                # Dark leather has much smaller scene-linear RGB amplitudes
                # than exposed skin; still require genuine sampled variation.
                assert float(np.max(np.std(used, axis=0))) > .00005, f"{material_role} base color is flat on the actual UV surface"
                if material_role == "Detailed_Skin":
                    assert float(np.max(np.std(used, axis=0))) > .001, "Skin base-color detail is not measurable"
                    warm = used[(used[:, 0] > .03) & (used[:, 1] > .01)]
                    assert len(warm) > 50 and float(np.mean(warm[:, 0] - warm[:, 2])) > .02, "Skin lacks an actual warm, non-grey color texture"
            elif semantic == "roughness":
                values = used[:, channel] if channel is not None else used.mean(axis=1)
                assert float(np.std(values)) > .002 and float(np.ptp(values)) > .015, f"{material_role} roughness is flat on the actual UV surface"
            else:
                assert float(np.std(used[:, :2], axis=0).max()) > .0005, f"{material_role} normal map is flat on the actual UV surface"
                lengths = np.linalg.norm(used * 2.0 - 1.0, axis=1)
                assert np.percentile(lengths, 1) > .7 and np.percentile(lengths, 99) < 1.3, "Normal map does not contain tangent-space unit vectors"
                assert float(np.mean(used[:, 2])) > .75, "Normal texture has the wrong tangent-space convention"
            image_row["used_surface"][material_role + "/" + semantic] = stats
        result["images"][name] = image_row
        del pixels
    return result


def inspect_glb_container(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and version == 2 and length == len(data), "Invalid GLB container"
    json_size, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A
    doc = json.loads(data[20:20 + json_size])
    bin_size, bin_type = struct.unpack_from("<II", data, 20 + json_size)
    assert bin_type == 0x004E4942
    binary = data[28 + json_size:28 + json_size + bin_size]
    assert len(doc["buffers"]) == 1 and "uri" not in doc["buffers"][0]
    image_rows = []
    for image in doc.get("images", []):
        assert "uri" not in image and "bufferView" in image, "GLB texture depends on an external URI"
        view = doc["bufferViews"][image["bufferView"]]
        assert view.get("buffer", 0) == 0
        blob = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        assert len(blob) == view["byteLength"] and len(blob) > 1024
        assert image.get("mimeType") in {"image/png", "image/jpeg"}
        assert blob.startswith(b"\x89PNG\r\n\x1a\n") or blob.startswith(b"\xff\xd8\xff"), "Embedded image data is not portable PNG/JPEG"
        image_rows.append({"name": image.get("name", ""), "mime": image["mimeType"], "bytes": len(blob), "sha256": hashlib.sha256(blob).hexdigest()})
    assert len(image_rows) >= 3, "GLB lacks three actual PBR image payloads"
    materials = doc["materials"]
    assert {m["name"].split(".")[0] for m in materials} == ROLES
    uv_checks = 0
    white_color_checks = 0
    tangent_vertices = 0

    def accessor_values(index):
        accessor = doc["accessors"][index]
        assert "sparse" not in accessor, "Unexpected sparse texture/color accessor"
        view = doc["bufferViews"][accessor["bufferView"]]
        component = accessor["componentType"]
        dtype = np.dtype({5120: "i1", 5121: "u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[component])
        columns = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[accessor["type"]]
        stride = view.get("byteStride", dtype.itemsize * columns)
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        values = np.ndarray((accessor["count"], columns), dtype=dtype, buffer=binary, offset=offset, strides=(stride, dtype.itemsize)).astype(np.float64)
        if accessor.get("normalized") and component != 5126:
            values /= np.iinfo(dtype).max
        assert np.isfinite(values).all()
        return values

    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            assert "TANGENT" in primitive["attributes"] and "NORMAL" in primitive["attributes"], "Normal-mapped GLB must provide its authored UV tangent frame"
            tangents = accessor_values(primitive["attributes"]["TANGENT"])
            normals = accessor_values(primitive["attributes"]["NORMAL"])
            assert tangents.shape == (len(normals), 4)
            assert np.max(np.abs(np.linalg.norm(tangents[:, :3], axis=1) - 1.0)) < .003
            assert np.max(np.abs(np.linalg.norm(normals, axis=1) - 1.0)) < .003
            assert np.max(np.abs(np.sum(tangents[:, :3] * normals, axis=1))) < .003, "Normal and UV tangent are not orthogonal"
            assert np.max(np.abs(np.abs(tangents[:, 3]) - 1.0)) < .00001, "Tangent handedness was lost"
            tangent_vertices += len(tangents)
            if "COLOR_0" in primitive["attributes"]:
                colors = accessor_values(primitive["attributes"]["COLOR_0"])
                assert np.max(np.abs(colors - 1.0)) < .00001, "Exported pigment vertex colors multiply the baked base-color texture twice"
                white_color_checks += 1
            mat = materials[primitive["material"]]
            pbr = mat["pbrMetallicRoughness"]
            assert "baseColorTexture" in pbr and "metallicRoughnessTexture" in pbr and "normalTexture" in mat, "PBR maps did not survive GLB export"
            assert np.max(np.abs(np.asarray(pbr.get("baseColorFactor", [1, 1, 1, 1])) - 1.0)) < .00001, "A nonwhite material factor tints the fully baked base color again"
            assert mat.get("alphaMode", "OPAQUE") == "OPAQUE", "Opaque authored hand surfaces became transparent"
            assert mat["normalTexture"].get("scale", 1.0) > 0.0
            assert pbr.get("roughnessFactor", 1.0) > 0.0
            for texture in (pbr["baseColorTexture"], pbr["metallicRoughnessTexture"], mat["normalTexture"]):
                texture_object = doc["textures"][texture["index"]]
                assert "source" in texture_object and 0 <= texture_object["source"] < len(image_rows)
                transform = texture.get("extensions", {}).get("KHR_texture_transform", {})
                coordinate = transform.get("texCoord", texture.get("texCoord", 0))
                key = f"TEXCOORD_{coordinate}"
                assert key in primitive["attributes"], "Texture references a UV set absent from its primitive"
                accessor = doc["accessors"][primitive["attributes"][key]]
                positions = doc["accessors"][primitive["attributes"]["POSITION"]]
                assert accessor["type"] == "VEC2" and accessor["count"] == positions["count"]
                coordinates = accessor_values(primitive["attributes"][key])
                assert np.ptp(coordinates, axis=0).min() > .002, "Exported texture coordinate field collapsed"
                uv_checks += 1
    return {"embedded_images": image_rows, "primitive_texture_coordinate_checks": uv_checks,
            "white_vertex_color_accessors": white_color_checks, "baked_color_double_tint_absent": True,
            "authored_tangent_vertices": tangent_vertices,
            "portable_normal_and_metallic_roughness_textures": True}


def compare_roundtrip(scene, rig, reference):
    actual = snapshot(scene, rig)
    result = {}
    for label, expected in reference["parts"].items():
        current = actual["parts"][label]
        expected_weights = expected["prior_export_weights"]
        tree = KDTree(len(expected["points"]))
        for i, p in enumerate(expected["points"]): tree.insert(Vector(p), i)
        tree.balance()
        correspondence = np.empty(len(current["points"]), dtype=np.int64)
        maximum, weights_max, worst_weight = 0.0, 0.0, None
        for i, point in enumerate(current["points"]):
            _, nearest, distance = tree.find(Vector(point))
            maximum = max(maximum, distance)
            candidates = tree.find_range(Vector(point), .000005)
            if candidates:
                nearest = min(candidates, key=lambda c: weight_error(current["weights"][i], expected_weights[c[1]]))[1]
            correspondence[i] = nearest
            error = weight_error(current["weights"][i], expected_weights[nearest])
            if error > weights_max:
                weights_max = error
                worst_weight = {"imported_vertex": i, "reference_vertex": nearest, "distance_m": distance,
                                "point": point.tolist(), "imported_weights": current["weights"][i],
                                "prior_glb_weights": expected_weights[nearest], "editable_weights": expected["weights"][nearest], "candidate_count": len(candidates)}
        assert maximum < .000005, f"{label} GLB vertices diverge from the editable model"
        assert weights_max < .000001, f"{label} GLB skin weights changed from prior GLB: " + json.dumps(worst_weight)
        assert sum(len(p) - 2 for p in current["faces"]) == sum(len(p) - 2 for p in expected["faces"]), f"{label} GLB lost surface topology"
        assert current["deltas"].keys() == expected["deltas"].keys()
        delta_max = max((float(np.linalg.norm(current["deltas"][name] - expected["deltas"][name][correspondence], axis=1).max()) for name in current["deltas"]), default=0.0)
        assert delta_max < .000002, f"{label} GLB correctives changed"
        if label == "WristCuff":
            assert current["flex"] == expected["flex"], "GLB lost flexible cuff metadata"
        result[label] = {"vertices": len(current["points"]), "maximum_position_error_m": maximum,
                         "maximum_weight_error_from_prior_glb": weights_max, "maximum_corrective_error_m": delta_max}
    return result


def inspect_articulation(scene, rig, side, native=False):
    return {"rig": core.inspect_rig(scene, rig, side, [0, -.05625, 0] if native else None),
            "all_fifteen_joint_effects": core.inspect_joint_effects(scene, rig),
            "rigid_nails": core.inspect_nails(scene, rig),
            "full_flex_nail_seating": core.inspect_nail_seating(scene, rig)}


def stable_value(value):
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bpy.types.ID):
        return value.name_full
    if hasattr(value, "items"):
        return {str(k): stable_value(v) for k, v in value.items()}
    return [stable_value(v) for v in value]


def signature(value):
    return hashlib.sha256(json.dumps(stable_value(value), sort_keys=True, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def model_payload_signatures():
    """Inspect actual datablocks independently of the producer's signature file."""
    result = {}
    for mesh in bpy.data.meshes:
        prefix = "mesh/" + mesh.name + "/"
        result[prefix + "geometry"] = signature({"points": [list(v.co) for v in mesh.vertices],
            "edges": [list(e.vertices) for e in mesh.edges],
            "faces": [{"vertices": list(p.vertices), "material": p.material_index, "smooth": p.use_smooth} for p in mesh.polygons],
            "corner_normals": [list(n.vector) for n in mesh.corner_normals],
            "materials": [m.name if m else None for m in mesh.materials]})
        result[prefix + "uv"] = signature({"active": mesh.uv_layers.active_index,
            "layers": {layer.name: {"render": layer.active_render, "points": [list(v.uv) for v in layer.data]} for layer in mesh.uv_layers}})
        result[prefix + "colors"] = signature({a.name: {"type": a.data_type, "domain": a.domain,
            "values": [list(v.color) for v in a.data]} for a in mesh.color_attributes})
        if mesh.shape_keys:
            keys = mesh.shape_keys
            result[prefix + "key_settings"] = signature({"relative": keys.use_relative,
                "keys": [{"name": k.name, "relative": k.relative_key.name, "value": k.value,
                          "interpolation": k.interpolation, "vertex_group": k.vertex_group,
                          "slider_min": k.slider_min, "slider_max": k.slider_max} for k in keys.key_blocks]})
            for key in keys.key_blocks:
                result[prefix + "key/" + key.name] = hashlib.sha256(points_from(key.data).tobytes()).hexdigest()
    for obj in bpy.data.objects:
        if obj.type in {"CAMERA", "LIGHT"}: continue
        prefix = "object/" + obj.name + "/"
        result[prefix + "binding"] = signature({"type": obj.type, "parent": obj.parent, "parent_type": obj.parent_type,
            "parent_bone": obj.parent_bone, "matrix_basis": obj.matrix_basis, "parent_inverse": obj.matrix_parent_inverse,
            "data": obj.data, "custom": {k: obj[k] for k in obj.keys()},
            "modifiers": [{"name": m.name, "type": m.type, "viewport": m.show_viewport, "render": m.show_render,
                **{key: getattr(m, key) for key in ("object", "vertex_group", "invert_vertex_group", "use_deform_preserve_volume", "use_vertex_groups", "use_bone_envelopes", "use_multi_modifier") if hasattr(m, key)}} for m in obj.modifiers]})
        if obj.type == "MESH":
            names = {g.index: g.name for g in obj.vertex_groups}
            result[prefix + "weights"] = signature([{names[g.group]: g.weight for g in v.groups} for v in obj.data.vertices])
        if obj.type == "ARMATURE":
            result[prefix + "rest"] = signature({b.name: {"parent": b.parent.name if b.parent else None,
                "matrix": b.matrix_local, "head": b.head_local, "tail": b.tail_local, "deform": b.use_deform,
                "connect": b.use_connect, "inherit_scale": b.inherit_scale} for b in obj.data.bones})
            result[prefix + "pose"] = signature({b.name: {"matrix_basis": b.matrix_basis, "rotation_mode": b.rotation_mode,
                "constraints": [(c.name, c.type, c.influence, c.mute) for c in b.constraints]} for b in obj.pose.bones})
    for material in bpy.data.materials:
        nodes, links = {}, []
        if material.node_tree:
            for node in material.node_tree.nodes:
                nodes[node.name] = {"type": node.bl_idname,
                    "inputs": {s.identifier: stable_value(s.default_value) for s in node.inputs if hasattr(s, "default_value")},
                    **{key: stable_value(getattr(node, key)) for key in ("image", "operation", "blend_type", "data_type", "interpolation", "projection", "extension", "space", "uv_map", "attribute_name", "distribution", "subsurface_method") if hasattr(node, key)}}
            links = sorted((l.from_node.name, l.from_socket.identifier, l.to_node.name, l.to_socket.identifier) for l in material.node_tree.links)
        result["material/" + material.name] = signature({"nodes": nodes, "links": links,
            "diffuse": material.diffuse_color, "metallic": material.metallic, "roughness": material.roughness,
            "cull": material.use_backface_culling})
    for image in bpy.data.images:
        if image.source not in {"FILE", "GENERATED"}: continue
        result["image_settings/" + image.name] = signature({"size": list(image.size), "colorspace": image.colorspace_settings.name,
            "alpha_mode": image.alpha_mode, "channels": image.channels, "packed": image.packed_file is not None})
    return result


def atlas_arrays(scene):
    materials = {slot.material for obj in scene.objects if obj.type == "MESH" for slot in obj.material_slots}
    result = {}
    for semantic, socket in (("basecolor", "Base Color"), ("normal", "Normal"), ("roughness", "Roughness")):
        found = set()
        for mat in materials:
            shader = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            found.update(n.image for n in image_nodes(shader.inputs[socket]))
        assert len(found) == 1, "All eighteen meshes must use the same atlas for " + semantic
        image = next(iter(found))
        assert image.packed_file and list(image.size) == [4096, 4096]
        pixels = np.empty(len(image.pixels), dtype=np.float32)
        image.pixels.foreach_get(pixels)
        result[semantic] = pixels.reshape(image.size[1], image.size[0], image.channels)[:, :, :3].copy()
    return result


def rasterized_uv_coverage(scene, size=4096):
    coverage = np.zeros((size, size), dtype=np.bool_)
    triangles = 0
    for obj in scene.objects:
        if obj.type != "MESH": continue
        mesh = obj.data
        mesh.calc_loop_triangles()
        uv = mesh.uv_layers.active.data
        for triangle in mesh.loop_triangles:
            points = np.asarray([uv[i].uv for i in triangle.loops], dtype=np.float64) * size
            a, b, c = points
            determinant = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
            if abs(determinant) < 1e-10: continue
            lo = np.maximum(np.floor(points.min(axis=0) - .5).astype(int), 0)
            hi = np.minimum(np.ceil(points.max(axis=0) - .5).astype(int), size - 1)
            if np.any(lo > hi): continue
            x = np.arange(lo[0], hi[0] + 1, dtype=np.float64)[None, :] + .5
            y = np.arange(lo[1], hi[1] + 1, dtype=np.float64)[:, None] + .5
            first = ((b[0] - x) * (c[1] - y) - (b[1] - y) * (c[0] - x)) / determinant
            second = ((c[0] - x) * (a[1] - y) - (c[1] - y) * (a[0] - x)) / determinant
            inside = (first >= -1e-8) & (second >= -1e-8) & (first + second <= 1.0 + 1e-8)
            coverage[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1] |= inside
            triangles += 1
    assert int(coverage.sum()) > size * size * .2, "UV coverage audit did not rasterize the real atlas"
    return coverage, triangles


def decoded_normal_statistics(encoded):
    """Inspect Godot's actual RG normal contract; never modify an image.

    At 5b4e0cb0f, forward_clustered/scene_forward_clustered.glsl:1330-1334
    reconstructs positive Z from RG, ignores stored B, and normalizes after
    the tangent-frame transform. A filtered/baked RGB triplet need not itself
    encode a unit XYZ vector. The raw XYZ lengths remain diagnostic evidence.
    """
    assert np.isfinite(encoded).all() and float(encoded.min()) >= 0.0 and float(encoded.max()) <= 1.0
    raw = encoded * 2.0 - 1.0
    raw_lengths = np.linalg.norm(raw, axis=-1)
    xy_squared = np.sum(raw[..., :2] ** 2, axis=-1)
    decoded = raw.copy()
    decoded[..., 2] = np.sqrt(np.maximum(0.0, 1.0 - xy_squared))
    lengths = np.linalg.norm(decoded, axis=-1)
    assert np.isfinite(decoded).all() and float(lengths.min()) > 0.0
    decoded /= lengths[..., None]
    unit_error = float(np.max(np.abs(np.linalg.norm(decoded, axis=-1) - 1.0)))
    assert unit_error < 1e-6
    return {"raw_xyz_minimum_length": float(raw_lengths.min()), "raw_xyz_maximum_length": float(raw_lengths.max()),
            "raw_xyz_length_at_most_half_texels": int((raw_lengths <= .5).sum()),
            "rgb_black_texels": int(np.all(encoded == 0.0, axis=-1).sum()),
            "rg_outside_unit_disk_texels": int((xy_squared > 1.0).sum()),
            "decoded_minimum_length_before_normalize": float(lengths.min()), "decoded_unit_error_maximum": unit_error}


def normal_padding_provenance(before, after, seed):
    # The atlas is a packed 8-bit Non-Color PNG. Match complete RGB tuples,
    # not independent channel ranges, so every added tuple has a real source.
    def codes(values):
        rgb = np.rint(values * 255.0).astype(np.uint32)
        assert float(np.max(np.abs(values - rgb.astype(np.float32) / 255.0))) < 1e-6
        return rgb[..., 0] | (rgb[..., 1] << 8) | (rgb[..., 2] << 16)
    allowed = np.zeros(1 << 24, dtype=np.bool_)
    allowed[codes(before[seed])] = True
    target_codes = codes(after[~seed])
    absent = int((~allowed[target_codes]).sum())
    assert absent == 0, "Normal padding introduced a tuple absent from the original authored bake"
    return {"padding_texels_matched_to_original_seed_rgb8": int(target_codes.size),
            "padding_tuples_absent_from_original_seed": absent}


def padding_source_provenance(old_atlas, new_atlas, seed, field_path):
    # Treat the producer's field as a claim, then independently check every
    # referenced source and output pixel plus sampled exact nearest distances.
    height, width = seed.shape
    field = np.fromfile(field_path, dtype="<u4").reshape(height, width)[::-1]
    assert int(field.max()) < width * height
    source = (height - 1 - field // width) * width + field % width
    assert seed.reshape(-1)[source].all()
    for semantic, old in old_atlas.items():
        assert np.array_equal(old.reshape(-1, 3)[source], new_atlas[semantic]), f"{semantic} padding differs from its claimed original source pixel"
    # Independently enumerate all seeds within the claimed nearest radius;
    # anything closer must lie in this square, so the sampled proof is exact.
    background = np.argwhere(~seed)
    sample_indices = np.unique(np.linspace(0, len(background) - 1, 1024).astype(int))
    farthest_squared = 0
    for y, x in background[sample_indices]:
        sy, sx = divmod(int(source[y, x]), width)
        distance_squared = (sy - int(y)) ** 2 + (sx - int(x)) ** 2
        radius = int(math.ceil(math.sqrt(distance_squared)))
        x0, y0 = max(0, x - radius), max(0, y - radius)
        ys, xs = np.nonzero(seed[y0:min(height, y + radius + 1), x0:min(width, x + radius + 1)])
        actual_minimum = int(np.min((ys + y0 - y) ** 2 + (xs + x0 - x) ** 2))
        assert actual_minimum == distance_squared, "Claimed padding source is not the nearest authored pixel"
        farthest_squared = max(farthest_squared, distance_squared)
    return {"all_three_maps_source_pixel_exact": True, "all_source_pixels_authored": True,
            "pixels_compared_per_map": int(seed.size), "nearest_distance_independent_samples": len(sample_indices),
            "maximum_sample_distance_pixels": math.sqrt(farthest_squared), "field_sha256": sha(field_path)}


def inspect_embedded_padding_images(before_path, after_path, new_atlas):
    before_doc, before_binary = glb_chunks(before_path)
    after_doc, after_binary = glb_chunks(after_path)
    rows = {}

    def read_image(document, binary, image, directory, filename, semantic):
        view = document["bufferViews"][image["bufferView"]]
        blob = binary[view.get("byteOffset", 0):view.get("byteOffset", 0) + view["byteLength"]]
        path = Path(directory) / filename
        path.write_bytes(blob)
        loaded = bpy.data.images.load(str(path), check_existing=False)
        if semantic != "basecolor": loaded.colorspace_settings.name = "Non-Color"
        pixels = np.empty(len(loaded.pixels), dtype=np.float32)
        loaded.pixels.foreach_get(pixels)
        values = pixels.reshape(loaded.size[1], loaded.size[0], loaded.channels)[:, :, :3].copy()
        bpy.data.images.remove(loaded)
        return values

    with tempfile.TemporaryDirectory(prefix="hand_padding_verifier_") as directory:
        for index, image in enumerate(after_doc["images"]):
            semantic = next(key for key in new_atlas if image["name"].endswith(key))
            values = read_image(after_doc, after_binary, image, directory, f"new_{index}.png", semantic)
            expected = new_atlas[semantic]
            if semantic == "roughness":
                assert np.array_equal(values[:, :, 1], expected[:, :, 1]), "Embedded glTF roughness G differs from the packed editable atlas"
                original = read_image(before_doc, before_binary, before_doc["images"][index], directory, f"old_{index}.png", semantic)
                assert np.array_equal(values[:, :, (0, 2)], original[:, :, (0, 2)]), "Unchanged metallic/occlusion packing channels changed"
            else:
                assert np.array_equal(values, expected), f"Embedded {semantic} differs from the packed editable atlas"
            rows[semantic] = {"editable_atlas_matches_actual_embedded_payload": True,
                              "compared_channel": "G; R/B preserved from prior GLB" if semantic == "roughness" else "RGB"}
    return rows


def mip_diagnostics(atlas, coverage):
    result = []
    images = {key: value for key, value in atlas.items()}
    used = coverage
    for level in range(5):
        color = images["basecolor"][used]
        rough = images["roughness"][used].mean(axis=1)
        normal = images["normal"][used] * 2.0 - 1.0
        lengths = np.linalg.norm(normal, axis=1)
        assert np.isfinite(color).all() and np.isfinite(rough).all() and np.isfinite(normal).all()
        result.append({"level": level, "covered_texels": int(used.sum()), "black_color_texels": int(np.all(color == 0.0, axis=1).sum()),
            "minimum_roughness": float(rough.min()), "roughness_percentile_1": float(np.percentile(rough, 1)),
            "minimum_normal_vector_length": float(lengths.min()), "normal_length_percentile_1": float(np.percentile(lengths, 1)),
            "normal_z_percentile_1": float(np.percentile(normal[:, 2], 1)),
            "godot_rg_decode": decoded_normal_statistics(images["normal"][used])})
        if level == 4: break
        images = {key: (value[0::2, 0::2] + value[1::2, 0::2] + value[0::2, 1::2] + value[1::2, 1::2]) * .25 for key, value in images.items()}
        used = used[0::2, 0::2] | used[1::2, 0::2] | used[0::2, 1::2] | used[1::2, 1::2]
    return result


def glb_chunks(path):
    blob = path.read_bytes()
    length = struct.unpack_from("<I", blob, 12)[0]
    return json.loads(blob[20:20 + length]), blob[28 + length:]


def compare_glb_padding(before_path, after_path):
    before, before_bin = glb_chunks(before_path)
    after, after_bin = glb_chunks(after_path)
    image_views = {i["bufferView"] for i in before["images"]}
    assert image_views == {i["bufferView"] for i in after["images"]}
    assert len(before["bufferViews"]) == len(after["bufferViews"])
    nonimage = 0
    for index, (a, b) in enumerate(zip(before["bufferViews"], after["bufferViews"])):
        if index in image_views: continue
        first = before_bin[a.get("byteOffset", 0):a.get("byteOffset", 0) + a["byteLength"]]
        second = after_bin[b.get("byteOffset", 0):b.get("byteOffset", 0) + b["byteLength"]]
        assert first == second, f"Non-image GLB bufferView {index} changed"
        nonimage += 1
    for document in (before, after):
        document["buffers"][0].pop("byteLength", None)
        for index, view in enumerate(document["bufferViews"]):
            view.pop("byteOffset", None)
            if index in image_views: view.pop("byteLength", None)
    assert before == after, "GLB changed geometry, skins, morphs, material bindings, or texture coordinates"
    return {"nonimage_buffer_views_byte_identical": nonimage, "all_nonimage_document_fields_identical": True,
            "before_sha256": sha(before_path), "after_sha256": sha(after_path), "container": inspect_glb_container(after_path)}


def inspect_presentation(scene):
    from bpy_extras.object_utils import world_to_camera_view
    assert scene.camera and scene.render.resolution_x == 1600 and scene.render.resolution_y == 1300
    assert scene.render.resolution_percentage == 100 and scene.cycles.samples == 24 and scene.cycles.use_denoising
    hands = [o for o in scene.objects if o.type == "MESH" and "Anatomical" in o.name]
    assert len(hands) == 2
    bounds = {}
    for hand in hands:
        points = [world_to_camera_view(scene, scene.camera, hand.matrix_world @ v.co) for v in hand.data.vertices]
        lower = [min(p[i] for p in points) for i in range(3)]
        upper = [max(p[i] for p in points) for i in range(3)]
        assert lower[0] >= 0.0 and lower[1] >= 0.0 and upper[0] <= 1.0 and upper[1] <= 1.0 and lower[2] > 0.0, "Default camera crops a hand"
        bounds[hand.name] = {"minimum": lower, "maximum": upper}
    viewports = [{"screen": screen.name, "shading": area.spaces.active.shading.type,
                  "perspective": area.spaces.active.region_3d.view_perspective} for screen in bpy.data.screens for area in screen.areas if area.type == "VIEW_3D"]
    assert viewports and all(v["shading"] == "MATERIAL" for v in viewports), "Saved viewports do not show the actual PBR materials"
    return {"resolution": [1600, 1300], "samples": 24, "denoising": True, "camera": scene.camera.name,
            "hand_camera_bounds": bounds, "viewports": viewports,
            "hidden_render_meshes": [o.name for o in scene.objects if o.type == "MESH" and o.hide_render]}


def verify_padding(args):
    output = args.output_dir.resolve()
    baseline_dir = args.padding_baseline_dir.resolve()
    baseline_blend = args.verified_blend_baseline.resolve()
    prior_report_path = baseline_dir / "verification_report.json"
    prior_report = json.loads(prior_report_path.read_text())
    assert prior_report["status"] == "passed"
    expected_old_sha = next(value for name, value in prior_report["verified_asset_sha256"].items() if Path(name).name == "bilateral_hands_realistic.blend")
    assert sha(baseline_blend) == expected_old_sha, "Baseline is not the independently verified blend"
    current_blend = output / "bilateral_hands_realistic.blend"
    field_path = output / "padding_diagnostics" / "nearest_seed.u32"
    paths = [baseline_blend, current_blend, prior_report_path, field_path] + [directory / f"{side}_hand_realistic.glb" for directory in (baseline_dir, output) for side in SIDES]
    hashes = {str(path): sha(path) for path in paths}
    report = {"status": "running", "utc": datetime.now(timezone.utc).isoformat(), "host": platform.platform(),
              "blender_binary": bpy.app.binary_path, "blender_version": bpy.app.version_string, "background": bpy.app.background,
              "baseline_verification": {"path": str(prior_report_path), "sha256": sha(prior_report_path), "passed_blend_sha256": expected_old_sha},
              "verified_asset_sha256": hashes, "checks": {}, "errors": [], "verifier_sha256": sha(Path(__file__)),
              "limitations": ["Box-filter mip diagnostics are not a GPU renderer or visual-quality judgment.",
                              "Original fifteen-joint/full-flex checks are inherited only after exact payload equivalence."]}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(baseline_blend))
        scene, _ = activate_bilateral()
        old_signatures = model_payload_signatures()
        coverage, triangles = rasterized_uv_coverage(scene)
        old_atlas = atlas_arrays(scene)
        bpy.ops.wm.open_mainfile(filepath=str(current_blend))
        scene, _ = activate_bilateral()
        new_signatures = model_payload_signatures()
        assert old_signatures.keys() == new_signatures.keys(), "Model payload components were added or removed"
        changed = [key for key in old_signatures if old_signatures[key] != new_signatures[key]]
        assert not changed, "Model payload changed: " + json.dumps(changed)
        report["checks"]["payload"] = {"identical_components": len(old_signatures), "component_signatures": old_signatures,
            "geometry_rest_pose_shape_weight_uv_and_material_nodes_identical": True, "prior_full_joint_checks_remain_applicable": True}
        report["checks"]["presentation"] = inspect_presentation(scene)
        new_atlas = atlas_arrays(scene)
        seed = np.any(old_atlas["basecolor"] != 0.0, axis=2)
        assert np.array_equal(seed, np.any(old_atlas["roughness"] != 0.0, axis=2)), "Prior bake seed masks disagree"
        missing = int((coverage & ~seed).sum())
        holes = np.argwhere(coverage & ~seed)
        hole_report = [{"pixel_xy": [int(x), int(y)],
                        "before": {key: value[y, x].tolist() for key, value in old_atlas.items()},
                        "after": {key: value[y, x].tolist() for key, value in new_atlas.items()},
                        "prior_seed_neighbors_3x3": int(seed[max(0, y-1):y+2, max(0, x-1):x+2].sum())}
                       for y, x in holes]
        # Pixel-center triangle rasterization can expose small gaps in the old
        # bake's coverage. Preserve every authored nonzero seed, and require
        # these formerly empty texels to become valid rather than keep black.
        assert not np.any(np.all(new_atlas["basecolor"][coverage] == 0.0, axis=1)), "New atlas leaves an actual UV texel black"
        assert not np.any(np.all(new_atlas["roughness"][coverage] == 0.0, axis=1)), "New atlas leaves an actual UV texel at zero roughness"
        rows = {}
        for semantic in old_atlas:
            before, after = old_atlas[semantic], new_atlas[semantic]
            assert before.shape == after.shape and np.isfinite(after).all()
            assert np.array_equal(before[seed], after[seed]), f"Valid {semantic} baked pixels changed"
            changed = np.any(before != after, axis=2)
            rows[semantic] = {"changed_padding_texels": int(changed.sum()), "changed_valid_texels": int((changed & seed).sum()),
                              "valid_pixel_sha256": hashlib.sha256(after[seed].tobytes()).hexdigest()}
            if semantic in {"basecolor", "roughness"}:
                assert not np.any(np.all(after == 0.0, axis=2)), f"{semantic} retains black unused background"
        report["checks"]["atlas"] = {"rasterized_uv_triangles": triangles, "actual_uv_covered_texels": int(coverage.sum()),
            "preserved_bake_and_margin_texels": int(seed.sum()), "unused_padding_texels": int((~seed).sum()), "maps": rows,
            "previously_empty_uv_texels": missing, "previously_empty_uv_texel_samples": hole_report,
            "retained_low_roughness_seed_texels": int((seed & (old_atlas["roughness"].mean(axis=2) < 70.0 / 255.0)).sum())}
        atlas_report = report["checks"]["atlas"]
        atlas_report["normal_decode_contract"] = {
            "source": "https://raw.githubusercontent.com/godotengine/godot/5b4e0cb0f/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl",
            "lines": [1330, 1334], "stored_b_ignored": True,
            "description": "Decode RG to signed XY, reconstruct positive Z, then normalize in the tangent frame. Raw RGB XYZ lengths are diagnostics, not a per-pixel unit constraint."}
        atlas_report["old_normal_statistics"] = decoded_normal_statistics(old_atlas["normal"])
        atlas_report["new_normal_statistics"] = decoded_normal_statistics(new_atlas["normal"])
        assert atlas_report["new_normal_statistics"]["rgb_black_texels"] == 0
        atlas_report["normal_padding_provenance"] = normal_padding_provenance(old_atlas["normal"], new_atlas["normal"], seed)
        atlas_report["padding_source_provenance"] = padding_source_provenance(old_atlas, new_atlas, seed, field_path)
        atlas_report["old_mip_diagnostics"] = mip_diagnostics(old_atlas, coverage)
        atlas_report["new_mip_diagnostics"] = mip_diagnostics(new_atlas, coverage)
        for row in report["checks"]["atlas"]["new_mip_diagnostics"]:
            assert row["black_color_texels"] == 0 and row["minimum_roughness"] > 0.0
            assert row["godot_rg_decode"]["decoded_unit_error_maximum"] < 1e-6
        for side in SIDES:
            baseline_glb = baseline_dir / f"{side}_hand_realistic.glb"
            assert sha(baseline_glb) == prior_report["verified_glb_roles"][side]["sha256"], "Prior exported GLB is not the verified candidate"
            report["checks"][side + "_glb"] = compare_glb_padding(baseline_glb, output / f"{side}_hand_realistic.glb")
            report["checks"][side + "_glb"]["embedded_atlas_match"] = inspect_embedded_padding_images(baseline_glb, output / f"{side}_hand_realistic.glb", new_atlas)
    except Exception as error:
        report["errors"].append({"error": str(error), "traceback": traceback.format_exc()})
    assert all(sha(path) == value for path, value in hashes.items()), "Read-only padding validation changed an input"
    report["status"] = "passed" if not report["errors"] else "failed"
    destination = output / "padding_verification_report.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("REALISTIC_HANDS_PADDING_VERIFICATION", report["status"], json.dumps(report["errors"]), destination, flush=True)
    if report["errors"]: raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-dir", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--left-glb", type=Path, help="Read-only candidate override; its exact path and SHA are recorded")
    parser.add_argument("--right-glb", type=Path, help="Read-only candidate override; its exact path and SHA are recorded")
    parser.add_argument("--padding-baseline-dir", type=Path, help="Verify image-padding-only revision against a prior complete PASS")
    parser.add_argument("--verified-blend-baseline", type=Path, help="Exact blend used by that prior complete verification")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background, "Verifier must run without an interactive Blender window"
    if args.padding_baseline_dir:
        assert args.verified_blend_baseline
        verify_padding(args)
        return
    assert args.previous_dir, "Full verification requires --previous-dir"
    output = args.output_dir.resolve()
    previous = args.previous_dir.resolve() / "bilateral_hands_wrist_refined.blend"
    previous_glbs = {side: args.previous_dir.resolve() / f"{side}_hand_wrist_refined.glb" for side in SIDES}
    glbs = {side: (getattr(args, side + "_glb") or output / f"{side}_hand_realistic.glb").resolve() for side in SIDES}
    files = [output / "bilateral_hands_realistic.blend"] + list(glbs.values())
    hashes = {str(p): sha(p) for p in [previous] + list(previous_glbs.values()) + files}
    report = {"status": "running", "utc": datetime.now(timezone.utc).isoformat(), "host": platform.platform(),
              "blender_version": bpy.app.version_string, "blender_binary": bpy.app.binary_path, "background": True,
              "checks": {}, "errors": [], "verified_asset_sha256": hashes,
              "verified_glb_roles": {side: {"path": str(path), "sha256": sha(path)} for side, path in glbs.items()},
              "verifier_sha256": sha(Path(__file__)), "joint_core_sha256": sha(Path(__file__).with_name("joint_verification_core.py")),
              "limitations": ["Texture statistics and geometry checks do not establish visual quality.",
                              "Actual Godot wrist deformation, renderer, and test-room behavior are verified separately."]}
    references = {}
    bpy.ops.wm.open_mainfile(filepath=str(previous))
    scene, rigs = activate_bilateral()
    before = {side: snapshot(scene, rig) for side, rig in zip(SIDES, rigs)}
    for side in SIDES:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(previous_glbs[side]), bone_heuristic="TEMPERANCE")
        scene = bpy.context.scene
        rig = next(o for o in scene.objects if o.type == "ARMATURE")
        report["checks"]["prior_export_weights_" + side] = attach_prior_export_weights(before[side], snapshot(scene, rig))
    try:
        bpy.ops.wm.open_mainfile(filepath=str(files[0]))
        scene, rigs = activate_bilateral()
        assert not bpy.data.libraries, "Editable model contains linked external libraries"
        assert not [i.name for i in bpy.data.images if i.source == "FILE" and not i.packed_file], "Editable textures are not packed"
        references = {side: snapshot(scene, rig) for side, rig in zip(SIDES, rigs)}
        for side in SIDES:
            for label, part in references[side]["parts"].items():
                part["prior_export_weights"] = before[side]["parts"][label]["prior_export_weights"]
        for side, rig in zip(SIDES, rigs):
            row, _ = compare_authored(scene, rig, before[side])
            row["articulation"] = inspect_articulation(scene, rig, side)
            report["checks"]["editable_" + side] = row
        report["checks"]["editable_materials"] = inspect_materials(scene.objects)
    except Exception as error:
        report["errors"].append({"stage": "editable", "error": str(error), "traceback": traceback.format_exc()})
        print("REALISTIC_HANDS_CHECK_FAILED editable", repr(error), flush=True)
    for side in SIDES:
        try:
            path = glbs[side]
            container = inspect_glb_container(path)
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic="TEMPERANCE")
            scene = bpy.context.scene
            rigs = [o for o in scene.objects if o.type == "ARMATURE"]
            assert len(rigs) == 1, "Standalone GLB must contain exactly one hand rig"
            rig = rigs[0]
            row = {"container": container, "rest": core.compare_rest(rig, before[side]["rest"]),
                   "roundtrip": compare_roundtrip(scene, rig, references[side]),
                   "articulation": inspect_articulation(scene, rig, side, True),
                   "materials": inspect_materials(scene.objects)}
            report["checks"][side + "_glb"] = row
        except Exception as error:
            report["errors"].append({"stage": side + "_glb", "error": str(error), "traceback": traceback.format_exc()})
            print("REALISTIC_HANDS_CHECK_FAILED", side, repr(error), flush=True)
    assert all(sha(p) == expected for p, expected in hashes.items()), "Verifier changed a model or original source"
    report["status"] = "passed" if not report["errors"] else "failed"
    destination = output / "verification_report.json"
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print("REALISTIC_HANDS_VERIFICATION", report["status"], destination, flush=True)
    if report["errors"]: raise SystemExit(1)


if __name__ == "__main__":
    main()
