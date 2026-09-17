"""Hide v12 rear patch seams using the same back-projection material/UVs."""

from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v12.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13a.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
patches = bpy.data.objects["Mercenary_RearShoulder_NotchPatches_LOD0"]
back_material = bpy.data.materials["MAT_ReferenceProjection_Back_4K"]
patches.data.materials.append(back_material)
back_index = len(patches.data.materials) - 1
uv = patches.data.uv_layers.get("UVMap") or patches.data.uv_layers.new(name="UVMap")

rear_faces = []
for polygon in patches.data.polygons:
    if polygon.normal.y <= 0.50:
        continue
    polygon.material_index = back_index
    polygon.use_smooth = True
    rear_faces.append(polygon.index)
    for loop_index in polygon.loop_indices:
        coordinate = patches.data.vertices[patches.data.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = (
            -0.456181574643 * coordinate.x + 0.499691914338,
            0.495824920997 * coordinate.z + 0.05908203125,
        )

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"


def render(name, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13a_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
render("failure", failure_location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V13A_REAR_FACES", rear_faces)
print("WROTE", OUTPUT)
