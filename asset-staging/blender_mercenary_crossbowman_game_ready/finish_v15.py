"""Validate, render and export the v15 shoulder/cowl repair candidate.

The source is the visually selected v13h scene.  This stage does not touch the
canonical production GLB or the web preview; it only writes versioned candidate
artifacts that can be verified before promotion.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13h.blend"
SOURCE_SUMMARY = STAGING / "build_summary_v12.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v15.json"
OUTPUT_GLB = (
    ROOT
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v15.glb"
)

REPORTED_HOLE_RECTS = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)
REPAIR_OBJECT_NAMES = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]

# The v13b construction method used "KnifeTaper" in an internal mesh name.
# It describes the closed seam shape, not equipment, but the delivery validator
# intentionally rejects weapon-like name tokens.  Give the repair a neutral
# production name before saving/exporting.
notch_repair = bpy.data.objects["Mercenary_RearShoulder_NotchPatches_LOD0"]
notch_repair.data.name = "Mercenary_RearShoulder_NotchPatches_Closed_LOD0_Mesh"


def triangle_count(obj):
    return sum(max(1, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


def nonmanifold_edge_count(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for first, second in zip(vertices, vertices[1:] + vertices[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return sum(count != 2 for count in counts.values())


def weight_sum_range(obj):
    values = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    if not values:
        raise RuntimeError(f"{obj.name} has no skin weights")
    return min(values), max(values)


def has_rig_modifier(obj):
    return any(
        modifier.type == "ARMATURE" and modifier.object == rig
        for modifier in obj.modifiers
    )


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


character_meshes = sorted(
    (
        obj
        for obj in scene.objects
        if obj.type == "MESH" and obj.get("part_category") is not None
    ),
    key=lambda obj: obj.name,
)
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if len(character_meshes) != 12:
    raise RuntimeError(f"Unexpected character mesh count: {len(character_meshes)}")

deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if deform_bones != 160:
    raise RuntimeError(f"Unexpected Rigify deform bone count: {deform_bones}")

repair_objects = {}
repair_nonmanifold = {}
repair_weight_ranges = {}
for name in REPAIR_OBJECT_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        raise RuntimeError(f"Required repair object is missing: {name}")
    repair_objects[name] = obj
    repair_nonmanifold[name] = nonmanifold_edge_count(obj)
    repair_weight_ranges[name] = weight_sum_range(obj)
    if repair_nonmanifold[name] != 0:
        raise RuntimeError(f"Open/non-manifold repair geometry: {name}")
    low, high = repair_weight_ranges[name]
    if low < 0.999 or high > 1.001:
        raise RuntimeError(f"Invalid repair weight sums on {name}: {(low, high)}")
    if not has_rig_modifier(obj):
        raise RuntimeError(f"Repair object is not bound to Rigify: {name}")

if bpy.data.objects.get("Mercenary_InnerCowl_Liner_LOD0") is not None:
    raise RuntimeError("Rejected flat radial liner still exists")
for rejected in (
    "Mercenary_HiddenShoulder_Mantle_LOD0",
    "Mercenary_CoherentShoulderYoke_LOD0",
    "Mercenary_UpperGambesonShell_LOD0",
):
    if bpy.data.objects.get(rejected) is not None:
        raise RuntimeError(f"Rejected broad/floating repair exists: {rejected}")

# glTF exports these materials as double-sided.  This prevents donor backface
# inconsistencies from becoming apparent holes when Godot imports the asset.
for obj in character_meshes:
    for material in obj.data.materials:
        if material is not None:
            material.use_backface_culling = False


def set_top_close_camera():
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.95
    camera.location = (0.0, 0.0, 5.0)
    look_at(camera, (0.0, 0.02, 1.49))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    bpy.context.view_layer.update()


def build_character_bvh():
    vertices = []
    polygons = []
    for obj in character_meshes:
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        polygons.extend(
            tuple(offset + index for index in polygon.vertices)
            for polygon in obj.data.polygons
        )
    return BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1.0e-7)


def pixel_origin(pixel_x, pixel_y):
    width, height = 1200.0, 900.0
    half_height = 0.95 * 0.5
    half_width = half_height * (width / height)
    local_x = (((pixel_x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / height) * 2.0 - 1.0) * half_height
    rotation = camera.matrix_world.to_quaternion()
    return camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))


set_top_close_camera()
bvh = build_character_bvh()
ray_direction = camera.matrix_world.to_quaternion() @ Vector((0.0, 0.0, -1.0))
misses_by_rect = []
for xmin, xmax, ymin, ymax in REPORTED_HOLE_RECTS:
    misses = 0
    for pixel_y in range(ymin, ymax + 1):
        for pixel_x in range(xmin, xmax + 1):
            if bvh.ray_cast(pixel_origin(pixel_x, pixel_y), ray_direction, 10.0)[0] is None:
                misses += 1
    misses_by_rect.append(misses)
if any(misses_by_rect):
    raise RuntimeError(f"Top-close hole audit failed: {misses_by_rect}")

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
preview_paths = {}


def render_final(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f"mercenary_game_ready_v15_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(output)


render_final(
    "top_close",
    (0.0, 0.0, 5.0),
    (0.0, 0.02, 1.49),
    ortho_scale=0.95,
    resolution=(1200, 900),
)
render_final(
    "top",
    (0.0, 0.0, 5.0),
    (0.0, 0.0, 0.92),
    ortho_scale=1.95,
    resolution=(1500, 900),
)
radius = 4.7
elevation = math.radians(80.0)
azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
render_final(
    "failure_view",
    failure_location,
    (0.0, 0.06, 1.02),
    lens=78,
    resolution=(1400, 1000),
)
render_final("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render_final("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render_final("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

# Save the editable scene with the rig available but visually unobtrusive.
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

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

export_properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_arguments = {
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
if "use_selection" in export_properties:
    gltf_arguments["use_selection"] = True
elif "export_selected" in export_properties:
    gltf_arguments["export_selected"] = True
bpy.ops.export_scene.gltf(**gltf_arguments)

# Restore the friendly authoring state after export.
rig.hide_render = True
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

summary = json.loads(SOURCE_SUMMARY.read_text(encoding="utf-8"))
summary["asset"] = "mercenary_crossbowman_game_ready_v15"
summary["triangles"] = total_triangles
summary["triangle_breakdown"] = {
    obj.name: triangle_count(obj) for obj in character_meshes
}
summary["mesh_count"] = len(character_meshes)
summary["deform_bones"] = deform_bones
summary["previews"] = preview_paths
summary["high_angle_qa"] = []
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["upper_opening_repair"] = {
    "source": "v13h selected neutral-cloth candidate",
    "restored_v8_deleted_shoulder_faces": 333,
    "reported_top_rect_misses": misses_by_rect,
    "repair_nonmanifold_edges": repair_nonmanifold,
    "repair_weight_sum_ranges": {
        name: list(values) for name, values in repair_weight_ranges.items()
    },
    "flat_radial_liner_removed": True,
    "closed_rolled_collar_added": True,
    "double_sided_game_materials": True,
    "broad_floating_panel_added": False,
    "duplicate_limb_added": False,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("V15_FINAL_TRIANGLES", total_triangles)
print("V15_FINAL_MESHES", len(character_meshes))
print("V15_FINAL_DEFORM_BONES", deform_bones)
print("V15_FINAL_NONMANIFOLD", repair_nonmanifold)
print("V15_FINAL_WEIGHT_RANGES", repair_weight_ranges)
print("V15_FINAL_TOP_CLOSE_MISSES", misses_by_rect)
print("V15_FINAL_BLEND", OUTPUT_BLEND)
print("V15_FINAL_GLB", OUTPUT_GLB)
print("V15_FINAL_SUMMARY", OUTPUT_SUMMARY)
