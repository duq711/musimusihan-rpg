"""Hidden Blender QA renders of individual kit assets; does not edit source .blend."""
import bpy
import math
from mathutils import Vector
from pathlib import Path

ROOT = Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(ROOT / "hideout_ruins_kit.blend"))
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 20
scene.cycles.use_denoising = True
scene.render.threads_mode = "FIXED"
scene.render.threads = 4
scene.render.resolution_x = 720
scene.render.resolution_y = 720
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.use_nodes = True
scene.world.node_tree.nodes.get("Background").inputs[0].default_value = (.15, .18, .21, 1)
scene.world.node_tree.nodes.get("Background").inputs[1].default_value = .45
scene.view_settings.view_transform = "AgX"
models = [obj for obj in scene.objects if obj.type == "MESH"]
for obj in models:
    obj.hide_render = True
bpy.ops.object.camera_add(location=(6, -8, 6))
camera = bpy.context.object
camera.data.type = "ORTHO"
camera.data.lens = 45
scene.camera = camera
for name, position, energy, color, size in (
        ("SoftWindow", (0, -4, 7), 850, (0.80, .89, 1.0), 5),
        ("WarmBounce", (4, 2, 3), 400, (1.0, .81, .58), 4)):
    bpy.ops.object.light_add(type="AREA", location=position)
    lamp = bpy.context.object
    lamp.name = name
    lamp.data.energy = energy
    lamp.data.color = color
    lamp.data.shape = "DISK"
    lamp.data.size = size
    lamp.rotation_euler = (-lamp.location).to_track_quat("-Z", "Y").to_euler()
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.05))
ground = bpy.context.object
mat = bpy.data.materials.new("QA_Backdrop")
mat.diffuse_color = (.095, .104, .105, 1)
ground.data.materials.append(mat)
output = ROOT / "qa"
output.mkdir(exist_ok=True)
for obj in models:
    obj.hide_render = False
    corners = [obj.matrix_world @ Vector(v) for v in obj.bound_box]
    low = Vector(tuple(min(v[i] for v in corners) for i in range(3)))
    high = Vector(tuple(max(v[i] for v in corners) for i in range(3)))
    center = (low + high) * .5
    dimension = max(high.x-low.x, high.y-low.y, high.z-low.z)
    if obj.name == "hanging_roots":
        camera.location = center + Vector((3,-8,2))
        ground.location.z = low.z - .10
    else:
        camera.location = center + Vector((5,-8,5))
        ground.location.z = low.z - .03
    camera.rotation_euler = (center-camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = dimension * 1.35
    scene.render.filepath = str(output / (obj.name + ".png"))
    bpy.ops.render.render(write_still=True)
    obj.hide_render = True
print("HIDEOUT RUINS BLENDER QA PASS: 7 individual images")
