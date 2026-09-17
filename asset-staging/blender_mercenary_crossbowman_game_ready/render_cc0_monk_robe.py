"""Normalize and render the CC0 MakeHuman monk robe for sleeve QA."""

from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
obj_path = root / "asset-staging/blender_mercenary_crossbowman_game_ready/cc0_makehuman_suits02_candidate/clothes/donitz_monk_robe/Monks_Robe.obj"
preview = root / "asset-staging/blender_mercenary_crossbowman_game_ready/previews"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(obj_path), forward_axis="NEGATIVE_Z", up_axis="Y")
objects = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
points = [obj.matrix_world @ vertex.co for obj in objects for vertex in obj.data.vertices]
minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
scale = 1.78 / (maximum.z - minimum.z)
center = 0.5 * (minimum + maximum)
for obj in objects:
    obj.scale *= scale
    obj.location.x -= center.x * scale
    obj.location.y -= center.y * scale
    obj.location.z -= minimum.z * scale
    for poly in obj.data.polygons:
        poly.use_smooth = True
mat = bpy.data.materials.new("MonkRobe_QA_Clay")
mat.diffuse_color = (0.38, 0.26, 0.16, 1.0)
for obj in objects:
    obj.data.materials.clear()
    obj.data.materials.append(mat)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
if scene.world is None:
    scene.world = bpy.data.worlds.new("QA_World")
scene.world.color = (0.015, 0.015, 0.015)
camera_data = bpy.data.cameras.new("Camera_Data")
camera = bpy.data.objects.new("Camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.lens = 72
for name, loc in (("Key", (-2.0, -2.4, 3.0)), ("Fill", (2.0, -1.2, 2.4))):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = 750.0 if name == "Key" else 380.0
    data.size = 2.6
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = loc
    light.rotation_euler = (Vector((0.0, 0.0, 1.0)) - light.location).to_track_quat("-Z", "Y").to_euler()
for key, location, target in (
    ("front", (0.0, -4.0, 1.0), (0.0, 0.0, 0.9)),
    ("three_quarter", (2.2, -3.2, 1.6), (0.0, 0.0, 1.1)),
    ("top", (0.0, -0.02, 3.0), (0.0, 0.0, 1.25)),
):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(preview / f"diagnostic_cc0_monk_robe_{key}.png")
    bpy.ops.render.render(write_still=True)
print("MONK_ROBE_DIMS=" + repr(tuple((maximum - minimum) * scale)))
