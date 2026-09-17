"""Finalize the clean CC0-sleeved, baked-cowl mercenary V16 for Godot."""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = (
    STAGING
    / "cc0_makehuman_suits02_candidate"
    / "mercenary_v16aaj_cc0_monk_robe_clean_upper_v6_candidate.blend"
)
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v16.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v16.json"
OUTPUT_GLB = (
    ROOT
    / "godot-game/assets/3d/dark_fantasy"
    / "mercenary_crossbowman_game_ready_v16.glb"
)

RIG_NAME = "Mercenary_Rigify_Rig_v4"
DONOR_NAME = "Mercenary_Clothed_Donor_LOD0"
COWL_NAME = "Mercenary_CleanDrapedScarf_v16aaj_LOD0"
HAIR_NAME = "Mercenary_ThinShortHair_LOD0_v16j"
UPPER_NAME = "Mercenary_CC0_MonkRobe_CleanUpper_LOD0"
CC0_LICENSE = (
    STAGING
    / "cc0_makehuman_suits02_candidate/clothes/donitz_monk_robe"
    / "donitz_monk_robe.mhclo"
)
CC0_SOURCE = (
    STAGING
    / "cc0_makehuman_suits02_candidate/clothes/donitz_monk_robe"
    / "Monks_Robe.obj"
)


def triangle_count(obj):
    return sum(max(1, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


def topology(obj):
    edge_counts = defaultdict(int)
    adjacency = defaultdict(set)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            edge_counts[tuple(sorted((first, second)))] += 1
            adjacency[first].add(second)
            adjacency[second].add(first)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "boundary_edges": sum(value == 1 for value in edge_counts.values()),
        "nonmanifold_edges": sum(value != 2 for value in edge_counts.values()),
        "overconnected_edges": sum(value > 2 for value in edge_counts.values()),
    }


def weight_range(obj):
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    if not sums:
        raise RuntimeError(f"No skin weights on {obj.name}")
    return min(sums), max(sums), sum(value < 0.999 for value in sums)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def apply_modifier(obj, modifier_name):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier_name)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects[RIG_NAME]
donor = bpy.data.objects[DONOR_NAME]
cowl = bpy.data.objects[COWL_NAME]
hair = bpy.data.objects[HAIR_NAME]
upper = bpy.data.objects[UPPER_NAME]

# Remove candidate-only studio lights so the user receives a tidy authoring
# file. The persistent PREVIEW objects remain excluded from export.
for obj in list(scene.objects):
    if obj.name.startswith(("CC0Upper_", "QA_", "V16AAF_", "V16AS_QA_")):
        bpy.data.objects.remove(obj, do_unlink=True)

# Use established glTF-friendly 4K materials. Slot 0 is the authored sleeve
# pair; slot 1 is the small torso under-layer beneath the projected coat.
gambeson = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
outer_wool = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if gambeson is None or outer_wool is None:
    raise RuntimeError("Established 4K clothing materials are missing")
upper.data.materials.clear()
upper.data.materials.append(gambeson)
upper.data.materials.append(outer_wool)
for polygon in upper.data.polygons:
    polygon.use_smooth = True

# Give the imported garment real thickness and closed cuff/crop rims. This
# removes one-sided paper edges when viewed from above or behind.
for modifier in list(upper.modifiers):
    if modifier.type == "BEVEL":
        upper.modifiers.remove(modifier)
armature_modifier = next(
    (modifier for modifier in upper.modifiers if modifier.type == "ARMATURE"), None
)
if armature_modifier is None or armature_modifier.object != rig:
    raise RuntimeError("CC0 upper garment is not bound to the Rigify rig")
solidify = upper.modifiers.new("V16_ClothThickness", "SOLIDIFY")
solidify.thickness = 0.0045
solidify.offset = 0.0
solidify.use_rim = True
solidify.use_even_offset = True
bevel = upper.modifiers.new("V16_SoftClothEdges", "BEVEL")
bevel.width = 0.0008
bevel.segments = 2
bevel.limit_method = "ANGLE"
bevel.angle_limit = math.radians(52.0)
upper.modifiers.move(upper.modifiers.find(solidify.name), 0)
upper.modifiers.move(upper.modifiers.find(bevel.name), 1)
apply_modifier(upper, solidify.name)
apply_modifier(upper, bevel.name)

upper["game_asset"] = True
upper["part_category"] = "ClothedBody"
upper["source_asset"] = str(CC0_SOURCE)
upper["source_license"] = "CC0"
upper["source_license_file"] = str(CC0_LICENSE)
upper["construction"] = "CC0 authored monk robe sleeves fitted to Rigify T-pose"
upper["overlap_policy"] = "Shoulder tucked beneath cowl; cuff overlaps wrist only"
cowl["part_category"] = "ClothedBody"
cowl["material_export"] = "Baked 4K base colour plus 4K wool normal"

character_meshes = sorted(
    (
        obj
        for obj in scene.objects
        if obj.type == "MESH"
        and obj.get("part_category") is not None
        and not obj.name.startswith(("WGT-", "PREVIEW_"))
    ),
    key=lambda obj: obj.name,
)
if upper not in character_meshes:
    raise RuntimeError("Final CC0 upper garment was not tagged for export")
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if deform_bones != 160:
    raise RuntimeError(f"Unexpected Rigify deform bone count: {deform_bones}")

upper_checks = {}
for obj in (upper, cowl, hair):
    stats = topology(obj)
    minimum, maximum, low_count = weight_range(obj)
    rigged = any(
        modifier.type == "ARMATURE" and modifier.object == rig
        for modifier in obj.modifiers
    )
    if stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Non-manifold final upper object: {obj.name}: {stats}")
    if minimum < 0.998 or maximum > 1.002 or low_count or not rigged:
        raise RuntimeError(
            f"Rigging failed for {obj.name}: {minimum}..{maximum}, low={low_count}"
        )
    upper_checks[obj.name] = {
        "triangles": triangle_count(obj),
        "topology": stats,
        "weight_sum_range": [minimum, maximum],
        "rigified": rigged,
    }

for obj in character_meshes:
    obj.hide_render = False
    obj.hide_viewport = False
    obj.hide_set(False)
    for material in obj.data.materials:
        if material is not None:
            material.use_backface_culling = False

# Keep Rigify available while preventing the embedded helper from executing
# automatically when the user opens the file.
for text_block in bpy.data.texts:
    text_block.use_module = False

# Render the exact steep angles that exposed the v15 holes and duplicate arms.
PREVIEWS.mkdir(parents=True, exist_ok=True)
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world is None:
    scene.world = bpy.data.worlds.new("V16_Final_World")
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs[0].default_value = (0.018, 0.021, 0.027, 1.0)
background.inputs[1].default_value = 0.16

qa_objects = []
for name, location, energy, size, color in (
    ("V16_Final_Key", (-2.2, -2.6, 3.3), 520.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16_Final_Fill", (2.4, -1.5, 2.5), 270.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16_Final_Rim", (0.3, 2.4, 2.7), 390.0, 2.0, (0.72, 0.82, 1.0)),
    ("V16_Final_Top", (0.0, 0.0, 4.0), 220.0, 2.0, (1.0, 0.92, 0.82)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.33))
    qa_objects.append(light)

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("V16_Final_Camera_Data")
    camera = bpy.data.objects.new("V16_Final_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

preview_paths = {}


def render(key, location, target, *, ortho=None, lens=78, resolution=(1200, 1200)):
    if ortho is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"mercenary_game_ready_v16_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(path)


render("top_close", (0.0, -0.01, 2.75), (0.0, 0.02, 1.48), lens=82, resolution=(1400, 1000))
render("failure_view", (0.66, -0.72, 2.50), (0.0, 0.02, 1.41), lens=82, resolution=(1400, 1000))
render("upper_three_quarter", (0.82, -1.48, 2.05), (0.0, 0.0, 1.42), lens=84)
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho=2.06)
render("left", (-5.2, 0.0, 0.89), (0.0, 0.0, 0.89), ortho=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

for obj in qa_objects:
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

# Save a clean authoring file with the character visible and controls hidden.
for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.name.startswith("PREVIEW_") or obj.type == "ARMATURE":
        obj.hide_render = True
        obj.hide_viewport = True
        try:
            obj.hide_set(True)
        except RuntimeError:
            # Rigify widgets live in an excluded helper collection in some
            # saved view layers; viewport hiding is already sufficient.
            pass
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)

# Export only the deform rig plus production meshes; the GLB embeds textures.
bpy.ops.object.select_all(action="DESELECT")
rig.hide_viewport = False
rig.hide_set(False)
rig.hide_render = False
rig.select_set(True)
for obj in character_meshes:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig

OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
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
    "export_tangents": True,
    "export_apply": False,
    "export_morph": False,
}
if "use_selection" in properties:
    arguments["use_selection"] = True
elif "export_selected" in properties:
    arguments["export_selected"] = True
bpy.ops.export_scene.gltf(**arguments)

rig.hide_render = True
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND), check_existing=False)

summary = {
    "asset": "mercenary_crossbowman_game_ready_v16",
    "height_m": 1.78,
    "rest_pose": "T_POSE",
    "purpose": "Godot game character",
    "style": "photoreal medieval mercenary",
    "pose": "T-pose",
    "expression": "neutral",
    "triangles": total_triangles,
    "triangle_budget": [100000, 150000],
    "triangle_breakdown": {obj.name: triangle_count(obj) for obj in character_meshes},
    "mesh_count": len(character_meshes),
    "deform_bones": deform_bones,
    "rig": RIG_NAME,
    "blend": str(OUTPUT_BLEND),
    "glb": str(OUTPUT_GLB),
    "previews": preview_paths,
    "upper_rebuild_v16": {
        "cowl": COWL_NAME,
        "full_sleeves_and_torso": UPPER_NAME,
        "hair": HAIR_NAME,
        "old_rectangular_sleeves_absent": bpy.data.objects.get(
            "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
        ) is None,
        "donor_arm_triangles_removed": donor.get("v16mu_removed_donor_arm_faces", 7832),
        "cowl_material": cowl.data.materials[0].name,
        "cowl_basecolor_4k": cowl.get("baked_basecolor", ""),
        "upper_checks": upper_checks,
    },
    "license": {
        "cc0_garment_source": str(CC0_SOURCE),
        "cc0_license_file": str(CC0_LICENSE),
        "official_pack": "https://static.makehumancommunity.org/assets/assetpacks/suits02.html",
    },
    "excluded_equipment": ["crossbow", "sword", "dagger", "quiver", "pouches"],
    "textures": {
        "skin": "4K reference projection",
        "clothing": "4K gambeson/wool plus baked 4K cowl",
    },
}
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")

print("V16_FINAL_TRIANGLES", total_triangles)
print("V16_FINAL_MESHES", len(character_meshes))
print("V16_FINAL_DEFORM_BONES", deform_bones)
print("V16_FINAL_UPPER_CHECKS", json.dumps(upper_checks, sort_keys=True))
print("V16_FINAL_BLEND", OUTPUT_BLEND)
print("V16_FINAL_GLB", OUTPUT_GLB)
print("V16_FINAL_SUMMARY", OUTPUT_SUMMARY)
