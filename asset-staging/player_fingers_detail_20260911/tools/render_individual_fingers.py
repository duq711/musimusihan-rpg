"""Render one real left-hand digit and one side per PNG without saving the blend.

Run with Blender --background --threads 2 --python this_file -- --source BLEND
--output-dir NEW_DIRECTORY. Defaults: all five digits, dorsal/palmar, 1024x1536,
32 CPU Cycles samples. For a quick check use --digits index --samples 4
--width 512 --height 768. Reuse the resulting render_report.json with
--camera-manifest for exactly the same native camera/light frames on a candidate.

Only a new scene and static review mesh copies are rendered. UVs, material slots,
corner normals and evaluated neutral coordinates come from the actual source.
Faces outside the selected digit are omitted; no anatomical geometry is invented.
The digit continues below the image crop, so the isolated review is not a severed
finger asset. This script never saves or edits the source scene, rig or meshes.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


DIGITS = ("thumb", "index", "middle", "ring", "little")
VIEWS = ("dorsal", "palmar")


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def descendants(obj):
    return [obj] + [child for item in obj.children for child in descendants(item)]


def vec(value):
    return [float(v) for v in value]


def matrix(value):
    return [vec(row) for row in value]


def json_digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def source_signature(objects):
    """Verify in-memory source geometry/UV/keys/weights/rig as well as disk bytes."""
    result = {}
    for obj in objects:
        item = {"matrix_world": matrix(obj.matrix_world), "hide_render": obj.hide_render}
        if obj.type == "MESH":
            mesh = obj.data
            item.update(
                vertices=[vec(v.co) for v in mesh.vertices],
                polygons=[list(p.vertices) for p in mesh.polygons],
                weights=[[(g.group, g.weight) for g in v.groups] for v in mesh.vertices],
                uv={layer.name: [vec(loop.uv) for loop in layer.data] for layer in mesh.uv_layers},
                normals=[vec(c.vector) for c in mesh.corner_normals],
                material_slots=[m.name if m else None for m in mesh.materials],
                face_materials=[p.material_index for p in mesh.polygons],
                keys={} if not mesh.shape_keys else {
                    key.name: {"value": key.value, "points": [vec(v.co) for v in key.data]}
                    for key in mesh.shape_keys.key_blocks
                },
            )
        elif obj.type == "ARMATURE":
            item["bones"] = {
                b.name: {"rest": matrix(b.matrix_local), "head": vec(b.head_local),
                         "tail": vec(b.tail_local), "parent": b.parent.name if b.parent else None,
                         "pose": matrix(obj.pose.bones[b.name].matrix_basis)}
                for b in obj.data.bones
            }
        result[obj.name] = json_digest(item)
    return result


def neutral_source(objects, rig):
    identity = Matrix.Identity(4)
    for pose in rig.pose.bones:
        assert max(abs(pose.matrix_basis[r][c] - identity[r][c])
                   for r in range(4) for c in range(4)) < 1e-6, "Source must be neutral"
    for obj in objects:
        if obj.type == "MESH" and obj.data.shape_keys:
            assert all(abs(key.value) < 1e-8 for key in obj.data.shape_keys.key_blocks), "Nonzero source key"


def weight_rows(obj):
    names = {group.index: group.name for group in obj.vertex_groups}
    result = []
    for vertex in obj.data.vertices:
        row = {digit: 0.0 for digit in DIGITS}
        row["wrist"] = 0.0
        for group in vertex.groups:
            name = names[group.group]
            owner = next((digit for digit in DIGITS if name.startswith(digit)), None)
            if name == "wrist": owner = "wrist"
            if owner: row[owner] += group.weight
        result.append(row)
    return result


def face_ids(obj, digit):
    rows = weight_rows(obj)
    ids = []
    for polygon in obj.data.polygons:
        weights = {owner: sum(rows[i][owner] for i in polygon.vertices) / len(polygon.vertices)
                   for owner in (*DIGITS, "wrist")}
        if weights[digit] >= 0.4 and weights[digit] >= max(weights.values()):
            ids.append(polygon.index)
    assert len(ids) > 100, (digit, "Too few actual digit-owned faces")
    return ids


def static_copy(obj, ids, scene, depsgraph, label):
    """Extract selected evaluated faces, preserving each original loop's UV/normal."""
    evaluated = obj.evaluated_get(depsgraph)
    source = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    try:
        assert len(source.vertices) == len(obj.data.vertices), "Topology-changing modifiers need an explicit mapping"
        faces = [source.polygons[i] for i in ids]
        used = sorted({i for face in faces for i in face.vertices})
        remap = {old: new for new, old in enumerate(used)}
        mesh = bpy.data.meshes.new(label + "_Mesh")
        mesh.from_pydata([source.vertices[i].co for i in used], [],
                         [[remap[i] for i in face.vertices] for face in faces])
        for material in source.materials: mesh.materials.append(material)
        original_loops = []
        for new_face, old_face in zip(mesh.polygons, faces):
            new_face.material_index = old_face.material_index
            new_face.use_smooth = old_face.use_smooth
            original_loops.extend(old_face.loop_indices)
        for old_uv in source.uv_layers:
            new_uv = mesh.uv_layers.new(name=old_uv.name)
            for loop, original in zip(new_uv.data, original_loops): loop.uv = old_uv.data[original].uv
        if source.uv_layers.active:
            mesh.uv_layers.active_index = source.uv_layers.active_index
        mesh.update()
        mesh.normals_split_custom_set([source.corner_normals[i].vector for i in original_loops])
        duplicate = bpy.data.objects.new(label, mesh)
        scene.collection.objects.link(duplicate)
        duplicate.matrix_world = obj.matrix_world.copy()
        return duplicate, {"source_object": obj.name, "selected_faces": len(ids),
                           "selected_vertices": len(used), "source_face_ids_sha256": json_digest(ids),
                           "native_evaluated_geometry": True, "UV_and_materials_copied": True}
    finally:
        evaluated.to_mesh_clear()


def digit_frame(holder, rig, skin, ids, digit):
    to_native = holder.matrix_world.inverted()
    rig_native = to_native @ rig.matrix_world
    base = rig_native @ rig.data.bones[digit + ("1" if digit == "thumb" else "0")].head_local
    tip = rig_native @ rig.data.bones[digit + "2"].tail_local
    axis = (tip - base).normalized()
    dorsal = rig_native.to_3x3() @ rig.data.bones[digit + "2"].matrix_local.to_3x3().col[2]
    dorsal = (dorsal - axis * dorsal.dot(axis)).normalized()
    if dorsal.z < 0: dorsal = -dorsal
    across = axis.cross(dorsal).normalized()
    skin_native = to_native @ skin.matrix_world
    owned_vertices = {i for face in ids for i in skin.data.polygons[face].vertices}
    points = [skin_native @ skin.data.vertices[i].co for i in owned_vertices]
    exposed = set()
    for face in ids:
        polygon = skin.data.polygons[face]
        material = skin.data.materials[polygon.material_index]
        if material.name.startswith("Detailed_Skin"):
            exposed.update(polygon.vertices)
    assert len(exposed) > 50, (digit, "Missing visible skin region")
    exposed_points = [skin_native @ skin.data.vertices[i].co for i in exposed]
    # Native skin landmarks determine the bottom crop; enough authored glove is
    # retained below it that the extraction boundary is outside the image.
    axial = sorted((p - base).dot(axis) for p in exposed_points)
    skin_bottom = axial[max(0, int(len(axial) * 0.01))]
    bottom = skin_bottom - 0.0035
    top = max((p - base).dot(axis) for p in points)
    cross_values = [(p - base).dot(across) for p in exposed_points]
    depth_values = [(p - base).dot(dorsal) for p in exposed_points]
    center = base + across * ((min(cross_values) + max(cross_values)) * 0.5)
    center += dorsal * ((min(depth_values) + max(depth_values)) * 0.5)
    height = (top - bottom) / 0.94
    center += axis * (bottom + height * 0.5)
    frames = {}
    for view, sign in (("dorsal", 1), ("palmar", -1)):
        outward = dorsal * sign
        right = axis.cross(outward).normalized()
        up = outward.cross(right).normalized()
        rotation = Matrix((right, up, outward)).transposed()
        lights = []
        # Camera-relative key stays at upper-left for both reference photographs.
        for name, offset, power, size in (
            ("SoftRakingKey", (-0.10, 0.085, 0.075), 1.2, 0.13),
            ("SoftFill", (0.09, 0.018, 0.12), 0.32, 0.18),
        ):
            location = center + right * offset[0] + up * offset[1] + outward * offset[2]
            lights.append({"name": name, "location_native": vec(location), "target_native": vec(center),
                           "energy_w": power, "size_m": size, "color": [1.0, 1.0, 1.0]})
        frames[digit + "_" + view] = {
            "digit": digit, "view": view, "center_native": vec(center),
            "location_native": vec(center + outward * 0.35), "rotation_native": matrix(rotation),
            "ortho_scale_m": height, "axis_native": vec(axis), "dorsal_native": vec(dorsal),
            "base_native": vec(base), "tip_bone_native": vec(tip),
            "skin_bottom_axis_m": skin_bottom, "crop_bottom_axis_m": bottom,
            "skin_tip_axis_m": top, "lights": lights,
        }
    return frames


def new_scene(width, height, samples, threads):
    scene = bpy.data.scenes.new("Individual_Finger_Review_Transient")
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.view_settings.exposure = 0
    world = bpy.data.worlds.new("Individual_Finger_Charcoal")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.035, 0.035, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3
    # A constant visible charcoal background is independent of illumination.
    # These are renderer nodes, not a postprocess or an alteration of materials.
    camera_background = world.node_tree.nodes.new("ShaderNodeBackground")
    camera_background.inputs["Color"].default_value = (0.04, 0.04, 0.04, 1)
    camera_background.inputs["Strength"].default_value = 1
    light_path = world.node_tree.nodes.new("ShaderNodeLightPath")
    mix = world.node_tree.nodes.new("ShaderNodeMixShader")
    world.node_tree.links.new(light_path.outputs["Is Camera Ray"], mix.inputs[0])
    world.node_tree.links.new(world.node_tree.nodes["Background"].outputs[0], mix.inputs[1])
    world.node_tree.links.new(camera_background.outputs[0], mix.inputs[2])
    world.node_tree.links.new(mix.outputs[0], world.node_tree.nodes["World Output"].inputs["Surface"])
    scene.world = world
    return scene


def place_frame(scene, holder, frame):
    camera_data = bpy.data.cameras.new("Individual_Finger_Camera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = frame["ortho_scale_m"]
    camera_data.clip_start = 0.001
    camera_data.clip_end = 10
    camera = bpy.data.objects.new("Individual_Finger_Camera", camera_data)
    scene.collection.objects.link(camera)
    native = Matrix(frame["rotation_native"]).to_4x4()
    native.translation = Vector(frame["location_native"])
    camera.matrix_world = holder.matrix_world @ native
    scene.camera = camera
    objects = [camera]
    for spec in frame["lights"]:
        data = bpy.data.lights.new(spec["name"], "AREA")
        data.energy = spec["energy_w"]
        data.shape = "DISK"
        data.size = spec["size_m"]
        data.color = spec["color"]
        light = bpy.data.objects.new(spec["name"], data)
        scene.collection.objects.link(light)
        light.location = holder.matrix_world @ Vector(spec["location_native"])
        target = holder.matrix_world @ Vector(spec["target_native"])
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()
        objects.append(light)
    return objects


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--digits", nargs="+", choices=DIGITS, default=list(DIGITS))
    parser.add_argument("--views", nargs="+", choices=VIEWS, default=list(VIEWS))
    parser.add_argument("--width", type=int, default=1024)
    parser.add_argument("--height", type=int, default=1536)
    parser.add_argument("--samples", type=int, default=32)
    parser.add_argument("--threads", type=int, default=2)
    parser.add_argument("--camera-manifest", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background, "Use background Blender only"
    assert args.width > 0 and args.height > 0 and args.samples > 0 and args.threads > 0
    assert abs(args.width / args.height - 2 / 3) < 1e-6, "Keep the reference portrait aspect ratio 2:3"
    source, output = args.source.resolve(), args.output_dir.resolve()
    assert source.is_file() and source.suffix == ".blend"
    assert not output.exists(), "Use a new output directory; existing evidence is never overwritten"
    source_hash = sha(source)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    source_scene = bpy.data.scenes["Bilateral_Realistic_Review"]
    bpy.context.window.scene = source_scene
    holder = source_scene.objects["LEFT_PreviewTranslationOnly"]
    objects = descendants(holder)
    rig = next(obj for obj in objects if obj.type == "ARMATURE")
    skin = next(obj for obj in objects if obj.type == "MESH" and "Anatomical" in obj.name)
    nails = {digit: next(obj for obj in objects if obj.type == "MESH" and obj.name.startswith("Nail_" + digit)) for digit in DIGITS}
    neutral_source(objects, rig)
    original_signature = source_signature(objects)
    selections = {digit: face_ids(skin, digit) for digit in DIGITS}
    frames = {}
    for digit in DIGITS: frames.update(digit_frame(holder, rig, skin, selections[digit], digit))
    if args.camera_manifest:
        reference = json.loads(args.camera_manifest.read_text())
        assert set(reference["frames"]) == set(frames), "Reference must contain all ten views"
        frames = reference["frames"]
    output.mkdir(parents=True)
    report = {
        "status": "rendering", "source": str(source), "source_sha256": source_hash,
        "script_sha256": sha(Path(__file__)), "blender_version": bpy.app.version_string,
        "source_scene": source_scene.name, "native_holder_matrix_world": matrix(holder.matrix_world),
        "camera_manifest": str(args.camera_manifest.resolve()) if args.camera_manifest else None,
        "camera_manifest_sha256": sha(args.camera_manifest) if args.camera_manifest else None,
        "frames": frames, "frames_sha256": json_digest(frames),
        "render": {"engine": "CYCLES", "device": "CPU", "samples": args.samples, "threads": args.threads,
                   "width": args.width, "height": args.height, "view_transform": "AgX", "look": "AgX - Medium High Contrast",
                   "world_illumination_linear_rgb": [0.035, 0.035, 0.035], "world_illumination_strength": 0.3,
                   "camera_background_linear_rgb": [0.04, 0.04, 0.04], "camera_background_strength": 1.0},
        "renders": {}, "scope": "One real digit and side per PNG, neutral source, native coordinates, static face extraction only",
    }
    path = output / "render_report.json"
    scene = new_scene(args.width, args.height, args.samples, args.threads)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    try:
        for digit in args.digits:
            hand_copy, extraction = static_copy(skin, selections[digit], scene, depsgraph, "Review_" + digit)
            nail_copy, nail_extraction = static_copy(nails[digit], list(range(len(nails[digit].data.polygons))), scene, depsgraph, "Review_Nail_" + digit)
            for view in args.views:
                name = digit + "_" + view
                transient = place_frame(scene, holder, frames[name])
                filename = output / (name + ".png")
                scene.render.filepath = str(filename)
                bpy.ops.render.render(write_still=True, scene=scene.name)
                assert filename.is_file()
                report["renders"][name] = {"file": filename.name, "sha256": sha(filename), "digit": digit,
                                           "view": view, "frame_sha256": json_digest(frames[name]),
                                           "skin_extraction": extraction, "nail_extraction": nail_extraction,
                                           "actual_blender_geometry": True}
                for obj in transient: bpy.data.objects.remove(obj, do_unlink=True)
                path.write_text(json.dumps(report, indent=2))
                print("INDIVIDUAL_FINGER_RENDER", name, flush=True)
            bpy.data.objects.remove(hand_copy, do_unlink=True)
            bpy.data.objects.remove(nail_copy, do_unlink=True)
        assert source_signature(objects) == original_signature, "Source datablocks changed in memory"
        assert sha(source) == source_hash, "Source blend file changed on disk"
        report["source_datablocks_unchanged"] = True
        report["source_file_unchanged"] = True
        report["status"] = "complete"
        path.write_text(json.dumps(report, indent=2))
        print("INDIVIDUAL_FINGERS_COMPLETE", str(path), flush=True)
    finally:
        assert sha(source) == source_hash, "Source blend changed"


if __name__ == "__main__":
    main()
