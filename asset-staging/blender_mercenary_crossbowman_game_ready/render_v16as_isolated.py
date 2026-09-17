"""Render the V16AS sleeve object alone for boundary QA."""

from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
source = root / "asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16as_anatomical_upper_sleeves_candidate.blend"
output = root / "asset-staging/blender_mercenary_crossbowman_game_ready/previews/diagnostic_v16as_sleeves_isolated.png"
bpy.ops.wm.open_mainfile(filepath=str(source))
target = bpy.data.objects["Mercenary_AnatomicalGambesonUpperSleeves_v16as_LOD0"]
for obj in bpy.context.scene.objects:
    if obj.type == "MESH":
        obj.hide_render = obj is not target
    elif obj.type == "ARMATURE" or obj.name.startswith("WGT-"):
        obj.hide_render = True
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 800
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
camera = scene.camera
camera.location = (0.0, -2.2, 1.48)
camera.data.lens = 88
camera.rotation_euler = (Vector((0.0, 0.02, 1.40)) - camera.location).to_track_quat("-Z", "Y").to_euler()
data = bpy.data.lights.new("Isolated_Key_Data", "AREA")
data.energy = 90.0
data.size = 2.5
light = bpy.data.objects.new("Isolated_Key", data)
scene.collection.objects.link(light)
light.location = (-1.5, -1.7, 2.6)
light.rotation_euler = (Vector((0.0, 0.0, 1.4)) - light.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(output)
bpy.ops.render.render(write_still=True)
print("V16AS_ISOLATED=" + str(output))
