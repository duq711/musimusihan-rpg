"""Visual comparison: yoke5 geometry with one consistent dark charcoal cowl material."""

from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16_minimal_cowl_yoke5_gambeson_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16i_charcoal_cowl_test.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
cowl.data.materials.clear()
cowl.data.materials.append(material)
for poly in cowl.data.polygons:
    poly.material_index = 0
    poly.use_smooth = True

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100

def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16i_charcoal_{name}.png")
    bpy.ops.render.render(write_still=True)

render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("upper_three_quarter", (1.35, -2.0, 1.90), (0.0, 0.0, 1.42), lens=82)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V16I_OUTPUT", OUTPUT)
