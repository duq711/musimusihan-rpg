"""Render object/material ID views for the v9 high-angle black patches."""

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


def diagnostic_material(name, color):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*color, 1.0)
    emission.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


palette = [
    (0.92, 0.16, 0.18),
    (0.14, 0.74, 0.22),
    (0.18, 0.38, 0.95),
    (0.95, 0.78, 0.10),
    (0.74, 0.18, 0.88),
    (0.08, 0.80, 0.82),
    (1.00, 0.42, 0.08),
]

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
for object_index, obj in enumerate(character_meshes):
    original_count = max(1, len(obj.data.materials))
    original_indices = [polygon.material_index for polygon in obj.data.polygons]
    obj.data.materials.clear()
    for material_index in range(original_count):
        base = palette[material_index % len(palette)]
        factor = 0.48 + 0.52 * ((object_index % 4) / 3.0)
        color = tuple(min(1.0, component * factor + 0.08 * object_index) for component in base)
        obj.data.materials.append(
            diagnostic_material(f"ID_{obj.name}_{material_index}", color)
        )
    for polygon, material_index in zip(obj.data.polygons, original_indices):
        polygon.material_index = material_index
    print("ID_OBJECT", object_index, obj.name, "slots", original_count)

for obj in scene.objects:
    if obj.type == "ARMATURE":
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1500
scene.render.resolution_y = 1000
scene.world.color = (0.08, 0.08, 0.08)

camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.95
camera.location = (0.0, 0.0, 5.0)
look_at(camera, (0.0, 0.0, 0.92))
scene.render.filepath = str(PREVIEWS / "diagnostic_v9_top_material_ids.png")
bpy.ops.render.render(write_still=True)

# Approximate model-viewer camera-orbit theta=45deg, phi=10deg: high-angle
# view, 45 degrees around the vertical axis.
azimuth = math.radians(45.0)
elevation = math.radians(80.0)
radius = 4.7
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
look_at(camera, (0.0, 0.06, 1.02))
scene.render.filepath = str(PREVIEWS / "diagnostic_v9_failure_material_ids.png")
bpy.ops.render.render(write_still=True)
