"""Visual-only v13g: extend the existing hidden gambeson yoke rearward.

The v13f rolled collar removes the flat neck annulus.  This test changes no
silhouette-facing garment: it only stretches the rear half of the existing
under-cowl yoke into the two remaining top-view cavities, while lowering its
rear lip so it stays behind the back coat in standard views.
"""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13f.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13g.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]

rear_start = 0.095
original_rear = max(vertex.co.y for vertex in yoke.data.vertices)
target_rear = 0.252
for vertex in yoke.data.vertices:
    if vertex.co.y <= rear_start:
        continue
    t = min(1.0, (vertex.co.y - rear_start) / (original_rear - rear_start))
    smooth_t = t * t * (3.0 - 2.0 * t)
    vertex.co.y += (target_rear - original_rear) * smooth_t
    vertex.co.z -= 0.014 * smooth_t
yoke.data.update()

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13g_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure", (0.577, -0.577, 5.578), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V13G_YOKE_REAR", original_rear, max(vertex.co.y for vertex in yoke.data.vertices))
print("WROTE", OUTPUT)
