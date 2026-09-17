"""Render the CC0 realistic male base mesh to verify its anatomical source pose."""

from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
source = root / "asset-staging/blender_mercenary_crossbowman_photoreal/resources/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend"
output = root / "asset-staging/blender_mercenary_crossbowman_game_ready/previews/diagnostic_cc0_realistic_male_front.png"
bpy.ops.wm.open_mainfile(filepath=str(source))
body = bpy.data.objects["GEO-body_male_realistic"]
for obj in bpy.context.scene.objects:
    obj.hide_render = obj is not body

mat = bpy.data.materials.new("QA_Clay")
mat.diffuse_color = (0.38, 0.27, 0.20, 1.0)
body.data.materials.clear()
body.data.materials.append(mat)

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.world.color = (0.02, 0.02, 0.02)

camera_data = bpy.data.cameras.new("QA_Camera_Data")
camera = bpy.data.objects.new("QA_Camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 72
center_x = -2.2643826604
camera.location = (center_x, -3.65, 0.92)
camera.rotation_euler = (Vector((center_x, 0.0, 0.88)) - camera.location).to_track_quat("-Z", "Y").to_euler()

for name, loc, energy, size in (
    ("Key", (center_x - 2.0, -2.2, 3.0), 900.0, 3.0),
    ("Fill", (center_x + 2.0, -1.5, 2.2), 500.0, 2.5),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = loc
    light.rotation_euler = (Vector((center_x, 0.0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = str(output)
bpy.ops.render.render(write_still=True)
print("CC0_RENDER=" + str(output))
