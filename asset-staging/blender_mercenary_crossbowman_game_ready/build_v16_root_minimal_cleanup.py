"""V16 diagnostic: keep the useful reconstructed scarf, remove added ring/plate clutter."""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16_minimal_cleanup.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# These are the visibly artificial additions in v15: three torus rings plus
# shoulder pads/gussets.  Removing them leaves the original three asymmetric
# reconstructed scarf folds, which already cover the neck opening.
for name in (
    "Mercenary_InnerCowl_RolledCollar_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)

# A single wool material prevents front/back photo projections from fighting
# on the top-facing scarf surfaces.
cowl_material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
for name in (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.data.materials.clear()
    obj.data.materials.append(cowl_material)
    for poly in obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16_minimal_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
character_meshes = [obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None]
print("V16_MINIMAL_TRIANGLES", sum(triangle_count(obj) for obj in character_meshes))
print("V16_MINIMAL_MESHES", len(character_meshes))
print("V16_MINIMAL_OUTPUT", OUTPUT)
