#!/usr/bin/env python3
"""Build a local, licensed Creep GLB with Blender; never download or publish assets.

Run with Blender --background --factory-startup --disable-autoexec --python
tools/build_creep_asset.py -- --fbx /path/Creep.fbx --textures /path/tex.rar
Only this conversion code is intended for the public repository.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import shutil
import struct
import subprocess
import sys
import tempfile

import bpy
from mathutils import Vector


CLIPS = {
    "Idle1_Action": "idle",
    "Idle2_Action": "idle_crouched",
    "Walk1_Action": "walk_calm",
    "Walk2_Action": "walk",
    "Crouch_Action": "walk_crouched",
    "Damage_Action": "hit",
    "Death_Action": "death",
    "Punch_Action": "punch",
    "Bite_Action": "bite",
    "Eating_Action": "eat",
    "Roar_Action": "roar",
    "Sniff_Action": "sniff",
    "JumpIn_Action": "spawn_jump",
    "JumpOut_Action": "despawn_jump",
    "Sleep_start_Action": "sleep_start",
    "Sleep_loop_Action": "sleep_loop",
    "Sleep_finish_Action": "sleep_finish",
}
TEXTURES = {
    "base_color": "Creep_BaseColor.png",
    "normal": "Creep_Normal_OpenGL.png",
    "roughness": "Creep_Roughness.png",
    "metallic": "Creep_Metallic.png",
    "occlusion": "occlusion.png",
}


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def preserve_source(source, destination):
    source = Path(source).resolve(strict=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha256(source) != sha256(destination):
            raise ValueError(f"Preserved source differs; choose a new staging directory: {destination}")
    else:
        shutil.copy2(source, destination)
    return destination


def extract_textures(archive, destination):
    """Inspect a RAR before extracting into a new, local temporary directory."""
    names = subprocess.check_output(["/usr/bin/tar", "-tf", str(archive)], text=True).splitlines()
    details = subprocess.check_output(["/usr/bin/tar", "-tvf", str(archive)], text=True).splitlines()
    if not names or len(names) > 128 or len(names) != len(details):
        raise ValueError("Unexpected texture archive listing")
    for name, detail in zip(names, details):
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or "\\" in name:
            raise ValueError(f"Unsafe archive member: {name}")
        if not detail or detail[0] not in "-d":
            raise ValueError(f"Archive links/special files are not accepted: {name}")
    # Even on repeated runs the archive is verified and extracted afresh.
    with tempfile.TemporaryDirectory(prefix="creep-textures-", dir=destination.parent) as temp:
        temp = Path(temp)
        subprocess.run(["/usr/bin/tar", "-xf", str(archive), "-C", str(temp)], check=True)
        for path in temp.rglob("*"):
            if path.is_symlink() or not path.resolve().is_relative_to(temp.resolve()):
                raise ValueError(f"Unsafe extracted path: {path}")
        for filename in TEXTURES.values():
            if len(list(temp.rglob(filename))) != 1:
                raise ValueError(f"Expected exactly one texture named {filename}")
        destination.mkdir(parents=True, exist_ok=True)
        for path in temp.rglob("*"):
            if path.is_file():
                target = destination / path.relative_to(temp)
                preserve_source(path, target)
    return {key: next(destination.rglob(name)) for key, name in TEXTURES.items()}


def make_material(source_images, derived_dir, resolution):
    material = bpy.data.materials.new("CreepOriginalSkin")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    principled = nodes.get("Principled BSDF")
    principled.inputs["Roughness"].default_value = 0.7
    images = {}
    for channel, source in source_images.items():
        image = bpy.data.images.load(str(source), check_existing=False)
        image.colorspace_settings.name = "sRGB" if channel == "base_color" else "Non-Color"
        width, height = image.size[:]
        if max(width, height) > resolution:
            ratio = resolution / max(width, height)
            image.scale(round(width * ratio), round(height * ratio))
        image.filepath_raw = str(derived_dir / source.name)
        image.file_format = "PNG"
        image.save()
        image.pack()
        tex = nodes.new("ShaderNodeTexImage")
        tex.name = "Creep_" + channel
        tex.image = image
        images[channel] = tex
    for channel, socket in [("base_color", "Base Color"), ("roughness", "Roughness"), ("metallic", "Metallic")]:
        links.new(images[channel].outputs["Color"], principled.inputs[socket])
    normal = nodes.new("ShaderNodeNormalMap")
    links.new(images["normal"].outputs["Color"], normal.inputs["Color"])
    links.new(normal.outputs["Normal"], principled.inputs["Normal"])
    # The glTF exporter explicitly recognizes this material-output socket.
    group = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    group.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    group_node = nodes.new("ShaderNodeGroup")
    group_node.node_tree = group
    links.new(images["occlusion"].outputs["Color"], group_node.inputs["Occlusion"])
    return material


def evaluated_bounds(meshes):
    graph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        try:
            points.extend(evaluated.matrix_world @ vertex.co for vertex in mesh.vertices)
        finally:
            evaluated.to_mesh_clear()
    return ([min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)])


def inspect_glb(path):
    with path.open("rb") as stream:
        magic, version, total = struct.unpack("<4sII", stream.read(12))
        assert magic == b"glTF" and version == 2 and total == path.stat().st_size
        length, chunk_type = struct.unpack("<II", stream.read(8))
        assert chunk_type == 0x4E4F534A
        document = json.loads(stream.read(length))
    animation_names = [entry["name"] for entry in document.get("animations", [])]
    if sorted(animation_names) != sorted(CLIPS.values()):
        raise RuntimeError(f"Animation export mismatch: {animation_names}")
    if not document.get("skins") or not document.get("meshes"):
        raise RuntimeError("Export did not retain a skinned mesh")
    if any("uri" in image for image in document.get("images", [])):
        raise RuntimeError("Textures must be embedded in the GLB")
    mat = document["materials"][0]
    pbr = mat.get("pbrMetallicRoughness", {})
    if not all([mat.get("normalTexture"), mat.get("occlusionTexture"), pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture")]):
        raise RuntimeError("One or more PBR texture channels were not exported")
    return document


def main():
    workspace = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fbx", required=True, type=Path)
    parser.add_argument("--textures", required=True, type=Path)
    parser.add_argument("--staging", type=Path, default=workspace / "exports/Creep_20260917")
    parser.add_argument("--output", type=Path, default=workspace / "godot-game/assets/licensed/creep/creep.glb")
    parser.add_argument("--height", type=float, default=1.95)
    parser.add_argument("--resolution", type=int, default=2048)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if args.height <= 0 or not 128 <= args.resolution <= 4096:
        raise ValueError("Invalid target dimensions")
    source_dir = args.staging / "source"
    source_dir.mkdir(parents=True, exist_ok=True)
    source_fbx = preserve_source(args.fbx, source_dir / "Creep.fbx")
    source_rar = preserve_source(args.textures, source_dir / "tex.rar")
    source_images = extract_textures(source_rar, source_dir / "textures")
    derived = args.staging / "derived_textures"
    derived.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=str(source_fbx), use_anim=True)
    scene = bpy.context.scene
    armatures = [obj for obj in scene.objects if obj.type == "ARMATURE"]
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    if len(armatures) != 1 or len(meshes) != 1:
        raise RuntimeError("Unexpected Creep source hierarchy")
    armature = armatures[0]
    source_actions = {}
    for action in list(bpy.data.actions):
        suffix = action.name.split("|")[-1]
        if suffix not in CLIPS:
            raise RuntimeError("Unknown action: " + action.name)
        source_actions[action.name] = {"name": CLIPS[suffix], "frame_range": list(action.frame_range)}
        action.name = CLIPS[suffix]
        action.use_fake_user = True
    if len(source_actions) != len(CLIPS):
        raise RuntimeError("Expected all 17 original actions")
    idle = bpy.data.actions["idle"]
    armature.animation_data.action = idle
    armature.animation_data.action_slot = idle.slots[0]
    scene.frame_set(round(idle.frame_range[0]))
    bpy.context.view_layer.update()
    before_min, before_max = evaluated_bounds(meshes)
    scale = args.height / (before_max[2] - before_min[2])
    wrapper = bpy.data.objects.new("CreepAsset", None)
    scene.collection.objects.link(wrapper)
    armature.parent = wrapper
    wrapper.scale = (scale, scale, scale)
    # Blender source faces -Y. Z rotation PI makes it +Y; Y-up glTF becomes -Z.
    wrapper.rotation_euler.z = math.pi
    wrapper.location.z = -before_min[2] * scale
    material = make_material(source_images, derived, args.resolution)
    for mesh in meshes:
        mesh.data.materials.clear()
        mesh.data.materials.append(material)
    bpy.context.view_layer.update()
    after_min, after_max = evaluated_bounds(meshes)
    if abs(after_min[2]) > 0.0001 or abs(after_max[2] - args.height) > 0.0001:
        raise RuntimeError("Ground/height normalization failed")
    weights = [sorted([group.weight for group in vertex.groups if group.weight > 0], reverse=True)
               for mesh in meshes for vertex in mesh.data.vertices]
    # Godot supports up to eight skin influences. Keep the source untouched;
    # the exporter retains and renormalizes the strongest eight in this copy.
    skin_report = {
        "source_max_influences": max(map(len, weights)), "runtime_max_influences": 8,
        "vertices_over_runtime_limit": sum(len(row) > 8 for row in weights),
        "max_discarded_weight": max(sum(row[8:]) for row in weights),
    }
    bpy.ops.export_scene.gltf(
        filepath=str(args.output), export_format="GLB", export_yup=True,
        export_image_format="AUTO", export_materials="EXPORT",
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_frame_range=False, export_frame_step=1, export_anim_slide_to_zero=True,
        export_skins=True,
        export_def_bones=False, export_influence_nb=8, export_all_influences=False,
        export_morph=False, export_optimize_animation_size=True,
        export_extras=True,
    )
    glb = inspect_glb(args.output)
    manifest = {
        "asset_page": "https://www.cgtrader.com/free-3d-models/character/fantasy-character/creep-creature",
        "license": "CGTrader Royalty Free License (no AI); reusable binaries are local-only",
        "blender": bpy.app.version_string,
        "source_sha256": {"Creep.fbx": sha256(source_fbx), "tex.rar": sha256(source_rar)},
        "output_sha256": sha256(args.output), "output_bytes": args.output.stat().st_size,
        "height_m": args.height, "uniform_scale": scale,
        "source_idle_bounds": [before_min, before_max], "normalized_blender_bounds": [after_min, after_max],
        "godot_front": "-Z", "godot_up": "+Y", "ground_y": 0,
        "source_fps": scene.render.fps / scene.render.fps_base,
        "skin_influences": skin_report,
        "clips": source_actions,
        "loop_in_runtime": ["idle", "idle_crouched", "walk", "walk_calm", "walk_crouched", "eat", "sniff", "sleep_loop"],
        "note": "glTF has no core loop flag: set runtime loop modes. Full source attack repetitions retained.",
        "materials": glb.get("materials"), "images": glb.get("images"),
        "skins": [{"name": skin.get("name"), "joint_count": len(skin["joints"])} for skin in glb["skins"]],
        "animation_names": [animation["name"] for animation in glb["animations"]],
    }
    (args.staging / "build_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2))
    (args.staging / "glb_structure.json").write_text(json.dumps(glb, indent=2))
    print("CREEP BUILD PASS:", args.output)
    print(json.dumps({"bytes": manifest["output_bytes"], "height_m": args.height, "godot_front": "-Z", "animations": manifest["animation_names"]}))


if __name__ == "__main__":
    main()
