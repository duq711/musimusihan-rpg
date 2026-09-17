"""Render v9 with suspect shoulder/cowl objects isolated or hidden."""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v9.blend"))
scene = bpy.context.scene
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for obj in scene.objects:
    if obj.type == "ARMATURE":
        obj.hide_render = True
camera = scene.camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.95
camera.location = (0.0, 0.0, 5.0)
look_at(camera, (0.0, 0.0, 0.92))
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1400
scene.render.resolution_y = 900


def render(name):
    scene.render.filepath = str(PREVIEWS / name)
    bpy.ops.render.render(write_still=True)


render("diagnostic_v9_top_all.png")
cowl.hide_render = True
render("diagnostic_v9_top_no_clean_cowl.png")
cowl.hide_render = False
donor.hide_render = True
render("diagnostic_v9_top_no_donor.png")
donor.hide_render = False
yoke.hide_render = True
render("diagnostic_v9_top_no_yoke.png")
yoke.hide_render = False

for obj in [candidate for candidate in scene.objects if candidate.type == "MESH"]:
    obj.hide_render = obj not in {cowl}
render("diagnostic_v9_top_cowl_only.png")
for obj in [candidate for candidate in scene.objects if candidate.type == "MESH"]:
    obj.hide_render = obj not in {donor}
render("diagnostic_v9_top_donor_only.png")
for obj in [candidate for candidate in scene.objects if candidate.type == "MESH"]:
    obj.hide_render = obj not in {yoke}
render("diagnostic_v9_top_yoke_only.png")
