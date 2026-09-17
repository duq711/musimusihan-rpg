"""Render the untouched donor upper body after hiding only obsolete patch objects."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

for name in (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or obj.name.startswith("PREVIEW_"):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1200
scene.render.resolution_y = 1000
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        bg.inputs[1].default_value = 0.14

for name, location, energy, size, color in (
    ("Native_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("Native_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("Native_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)

for key, location, target, lens in (
    ("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
    ("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    ("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    ("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90),
    ("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90),
):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    if key in {"front", "back"}:
        scene.render.resolution_y = 1200
    else:
        scene.render.resolution_y = 1000
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16j_native_clean_{key}.png")
    bpy.ops.render.render(write_still=True)

