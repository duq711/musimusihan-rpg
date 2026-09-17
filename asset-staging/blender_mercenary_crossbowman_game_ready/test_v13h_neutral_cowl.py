"""Visual-only v13h: neutralize the olive under-cowl cloth without darkening it."""

from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
TEXTURES = STAGING / "textures"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13f.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13h.blend"
OUTPUT_TEXTURE = TEXTURES / "cowl_wool_basecolor_4k_neutral_v15.jpg"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
source_image = material.node_tree.nodes["BaseColor_4K"].image

pixels = np.empty(len(source_image.pixels), dtype=np.float32)
source_image.pixels.foreach_get(pixels)
rgba = pixels.reshape((-1, 4))
luminance = (
    rgba[:, 0] * 0.2126
    + rgba[:, 1] * 0.7152
    + rgba[:, 2] * 0.0722
)
# Preserve the woven contrast while shifting the green cast toward a worn,
# neutral charcoal.  The floor keeps creases readable instead of black.
tone = np.clip(0.055 + luminance * 0.72, 0.055, 0.38)
rgba[:, 0] = tone * 1.02
rgba[:, 1] = tone * 0.98
rgba[:, 2] = tone * 0.94

image = bpy.data.images.get(OUTPUT_TEXTURE.name)
if image is None:
    image = bpy.data.images.new(
        OUTPUT_TEXTURE.name,
        width=source_image.size[0],
        height=source_image.size[1],
        alpha=False,
    )
image.colorspace_settings.name = source_image.colorspace_settings.name
image.pixels.foreach_set(rgba.reshape(-1))
image.filepath_raw = str(OUTPUT_TEXTURE)
image.file_format = "JPEG"
image.save()
material.node_tree.nodes["BaseColor_4K"].image = image
material.diffuse_color = (0.18, 0.17, 0.16, 1.0)

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13h_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure", (0.577, -0.577, 5.578), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("WROTE", OUTPUT)
