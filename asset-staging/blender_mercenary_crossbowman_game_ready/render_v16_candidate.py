"""Render consistent upper-body and turnaround QA views for a supplied blend.

Usage after ``--``: input.blend output_prefix
"""

import sys
from pathlib import Path

import bpy
from mathutils import Vector


args = sys.argv[sys.argv.index("--") + 1 :]
if len(args) != 2:
    raise SystemExit("Expected: input.blend output_prefix")
source = Path(args[0]).resolve()
prefix = Path(args[1]).resolve()
prefix.parent.mkdir(parents=True, exist_ok=True)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(source))
scene = bpy.context.scene
for obj in scene.objects:
    if obj.type == "ARMATURE" or obj.name.startswith("WGT-") or obj.name.startswith("PREVIEW_"):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world is None:
    scene.world = bpy.data.worlds.new("V16_QA_World")
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs[0].default_value = (0.018, 0.021, 0.027, 1.0)
background.inputs[1].default_value = 0.18

for name, location, energy, size, color in (
    ("QA_Key", (-2.2, -2.6, 3.3), 700.0, 2.5, (1.0, 0.82, 0.68)),
    ("QA_Fill", (2.4, -1.5, 2.5), 380.0, 2.2, (0.62, 0.76, 1.0)),
    ("QA_Rim", (0.3, 2.4, 2.7), 520.0, 2.0, (0.72, 0.82, 1.0)),
    ("QA_Top", (0.0, 0.0, 4.0), 260.0, 2.0, (1.0, 0.92, 0.82)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.35))

camera = scene.camera
if camera is None:
    data = bpy.data.cameras.new("QA_Camera_Data")
    camera = bpy.data.objects.new("QA_Camera", data)
    scene.collection.objects.link(camera)
    scene.camera = camera


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = prefix.parent / f"{prefix.name}_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    print(f"V16_QA_{key.upper()}={path}")


render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49))
render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46))
render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88)
render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200))
render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200))
