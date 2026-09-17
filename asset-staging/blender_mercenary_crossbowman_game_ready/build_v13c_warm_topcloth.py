"""Warm only the v13b top-facing under-cowl cloth material.

The original cowl front/back projection materials remain untouched.  The
shared safe top material keeps its 4K cowl weave/normal/ORM but replaces the
green-grey base colour with a medium warm charcoal-brown derivative so the
top-facing cowl, yoke, liner, gussets and tiny notch wedges read as one cloth.
"""

import math
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13b.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13c.blend"
OUTPUT_TEXTURE = STAGING / "textures/cowl_wool_basecolor_4k_warm_charcoal_v13.jpg"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera

source_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
warm_material = source_material.copy()
warm_material.name = "MAT_CowlTop_WarmCharcoal_PBR_4K_v13"
source_image = bpy.data.images["cowl_wool_basecolor_4k_charcoal_v11.jpg"]
pixels = np.empty(len(source_image.pixels), dtype=np.float32)
source_image.pixels.foreach_get(pixels)
rgba = pixels.reshape((-1, 4))

# Preserve the original cowl-weave contrast while shifting its average from
# neutral/green-grey to a readable, non-black dark brown.
rgba[:, :3] = np.clip(
    rgba[:, :3] * np.array((0.58, 0.40, 0.30), dtype=np.float32)
    + np.array((0.020, 0.010, 0.006), dtype=np.float32),
    0.0,
    1.0,
)
warm_image = bpy.data.images.get("cowl_wool_basecolor_4k_warm_charcoal_v13.jpg")
if warm_image is None:
    warm_image = bpy.data.images.new(
        "cowl_wool_basecolor_4k_warm_charcoal_v13.jpg",
        width=source_image.size[0],
        height=source_image.size[1],
        alpha=False,
    )
warm_image.colorspace_settings.name = source_image.colorspace_settings.name
warm_image.pixels.foreach_set(rgba.reshape(-1))
warm_image.filepath_raw = str(OUTPUT_TEXTURE)
warm_image.file_format = "JPEG"
warm_image.save()
warm_material.node_tree.nodes["BaseColor_4K"].image = warm_image
warm_material.diffuse_color = (0.18, 0.115, 0.075, 1.0)

replaced_slots = []
for obj in scene.objects:
    if obj.type != "MESH":
        continue
    for slot_index, material in enumerate(obj.data.materials):
        if material == source_material:
            obj.data.materials[slot_index] = warm_material
            replaced_slots.append((obj.name, slot_index))

expected_objects = {
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
}
if {name for name, _index in replaced_slots} != expected_objects:
    raise RuntimeError(f"Unexpected top-cloth replacement scope: {replaced_slots}")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13c_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
for degrees in (0, 45, 90, 180, 270):
    azimuth = math.radians(degrees)
    location = (
        radius * math.cos(elevation) * math.sin(azimuth),
        -radius * math.cos(elevation) * math.cos(azimuth),
        0.95 + radius * math.sin(elevation),
    )
    render(
        "failure" if degrees == 45 else f"high_{degrees:03d}",
        location,
        (0.0, 0.06, 1.02),
        lens=78,
        resolution=(1400, 1000) if degrees == 45 else (900, 700),
    )
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

camera.data.type = "PERSP"
camera.data.lens = 78
failure_azimuth = math.radians(45.0)
camera.location = (
    radius * math.cos(elevation) * math.sin(failure_azimuth),
    -radius * math.cos(elevation) * math.cos(failure_azimuth),
    0.95 + radius * math.sin(elevation),
)
look_at(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V13C_REPLACED_TOP_CLOTH_SLOTS", replaced_slots)
print("V13C_TEXTURE", OUTPUT_TEXTURE, tuple(warm_image.size))
print("V13C_ORIGINAL_COWL_FRONT_BACK_UNCHANGED", True)
print("WROTE", OUTPUT)
