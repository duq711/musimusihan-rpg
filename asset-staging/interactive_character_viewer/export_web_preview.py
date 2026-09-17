"""Export a fast orbit-viewer GLB without modifying the source .blend.

Geometry, skinning and all deform joints are preserved.  Only material
images are duplicated in memory, resized to 1024px and redirected to dedicated
preview copies before export.
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
VIEWER_DIR = WORKSPACE / "asset-staging" / "interactive_character_viewer"
TEXTURE_DIR = VIEWER_DIR / "preview_textures_1k"
OUTPUT_GLB = (
    WORKSPACE
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_web_preview.glb"
)
SUMMARY_PATH = VIEWER_DIR / "web_preview_summary.json"
MAX_EDGE = 1024

TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)


def image_nodes():
    for material in bpy.data.materials:
        if not material.use_nodes or material.node_tree is None:
            continue
        for node in material.node_tree.nodes:
            if node.type == "TEX_IMAGE" and node.image is not None:
                yield node


def linked_armatures(mesh):
    """Return armatures that directly deform or parent *mesh*."""
    armatures = {}
    for modifier in mesh.modifiers:
        target = modifier.object if modifier.type == "ARMATURE" else None
        if target is not None and target.type == "ARMATURE":
            armatures[target.as_pointer()] = target

    parent = mesh.parent
    while parent is not None:
        if parent.type == "ARMATURE":
            armatures[parent.as_pointer()] = parent
        parent = parent.parent
    return list(armatures.values())


def discover_character_rig(scene, tagged_meshes):
    """Choose the deform rig most strongly linked to the character meshes."""
    all_meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    armatures = [
        obj
        for obj in scene.objects
        if obj.type == "ARMATURE"
        and any(bone.use_deform for bone in obj.data.bones)
    ]
    if not armatures:
        raise RuntimeError("No deforming armature found in the scene")

    ranked = []
    for armature in armatures:
        tagged_links = sum(
            armature in linked_armatures(mesh) for mesh in tagged_meshes
        )
        all_links = sum(armature in linked_armatures(mesh) for mesh in all_meshes)
        deform_bones = sum(1 for bone in armature.data.bones if bone.use_deform)
        ranked.append(((tagged_links, all_links, deform_bones), armature))

    ranked.sort(key=lambda item: (item[0], item[1].name), reverse=True)
    best_score, rig = ranked[0]
    if len(ranked) > 1 and ranked[1][0] == best_score:
        tied_names = sorted(
            armature.name for score, armature in ranked if score == best_score
        )
        raise RuntimeError(
            "Ambiguous character rig candidates: " + ", ".join(tied_names)
        )
    return rig


source_images = []
seen = set()
for node in image_nodes():
    pointer = node.image.as_pointer()
    if pointer in seen:
        continue
    seen.add(pointer)
    source_images.append(node.image)

preview_images = {}
records = []
for source in source_images:
    if source.size[0] <= 0 or source.size[1] <= 0:
        source.reload()
    # Force lazy file-backed pixels to load before duplicating the data-block.
    _first_pixel = source.pixels[0]
    preview = source.copy()
    preview.name = "WEB_" + source.name + "_1K"
    width, height = source.size[:]
    scale = min(1.0, MAX_EDGE / max(width, height))
    target_width = max(1, round(width * scale))
    target_height = max(1, round(height * scale))
    if (target_width, target_height) != (width, height):
        preview.scale(target_width, target_height)

    lower_name = source.name.lower()
    is_base_color = "basecolor" in lower_name or "projection" in lower_name
    extension = ".jpg" if is_base_color else ".png"
    preview.file_format = "JPEG" if is_base_color else "PNG"
    preview.filepath_raw = str(TEXTURE_DIR / (preview.name + extension))
    preview.save()
    preview_images[source.as_pointer()] = preview
    records.append(
        {
            "source": source.name,
            "preview": preview.name,
            "source_size": [width, height],
            "preview_size": [target_width, target_height],
            "format": preview.file_format,
        }
    )

for node in image_nodes():
    replacement = preview_images.get(node.image.as_pointer())
    if replacement is not None:
        node.image = replacement

scene = bpy.context.scene
tagged_character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
]
if not tagged_character_meshes:
    raise RuntimeError("No meshes tagged with part_category were found")

rig = discover_character_rig(scene, tagged_character_meshes)
rig_linked_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH" and rig in linked_armatures(obj)
]
character_meshes_by_pointer = {
    obj.as_pointer(): obj for obj in tagged_character_meshes + rig_linked_meshes
}
character_meshes = sorted(
    character_meshes_by_pointer.values(), key=lambda obj: obj.name
)

bpy.ops.object.select_all(action="DESELECT")
rig.hide_viewport = False
rig.hide_set(False)
rig.select_set(True)
for obj in character_meshes:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig

properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
arguments = {
    "filepath": str(OUTPUT_GLB),
    "export_format": "GLB",
    "export_yup": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_animations": False,
    "export_skins": True,
    "export_def_bones": True,
    "export_armature_object_remove": False,
    "export_rest_position_armature": True,
    "export_all_influences": False,
    "export_influence_nb": 4,
    "export_leaf_bone": False,
    "export_texcoords": True,
    "export_normals": True,
    "export_apply": False,
    "export_morph": False,
    "export_tangents": True,
}
if "use_selection" in properties:
    arguments["use_selection"] = True
elif "export_selected" in properties:
    arguments["export_selected"] = True
if "export_image_quality" in properties:
    arguments["export_image_quality"] = 88

bpy.ops.export_scene.gltf(**arguments)

summary = {
    "source_blend": bpy.data.filepath,
    "output_glb": str(OUTPUT_GLB),
    "bytes": OUTPUT_GLB.stat().st_size,
    "texture_max_edge": MAX_EDGE,
    "image_count": len(records),
    "rig": rig.name,
    "mesh_count": len(character_meshes),
    "mesh_names": [obj.name for obj in character_meshes],
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "images": records,
    "source_blend_saved": False,
}
SUMMARY_PATH.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("WEB_PREVIEW_SUMMARY", json.dumps(summary))
