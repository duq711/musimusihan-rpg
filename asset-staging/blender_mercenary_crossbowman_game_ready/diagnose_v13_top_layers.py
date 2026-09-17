"""Render a temporary flat-colour top-close ownership map for v13b."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v13b.blend"))


def emission(name, color):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeEmission")
    shader.inputs["Color"].default_value = (*color, 1.0)
    shader.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(shader.outputs["Emission"], output.inputs["Surface"])
    return material


mapping = {
    "Mercenary_Cowl_LayeredClean_LOD0": (0.85, 0.12, 0.12),
    "Mercenary_UnderCowl_Yoke_LOD0": (0.10, 0.80, 0.18),
    "Mercenary_InnerCowl_Liner_LOD0": (0.12, 0.28, 0.95),
    "Mercenary_RearShoulder_NotchPatches_LOD0": (0.95, 0.10, 0.80),
    "Mercenary_ShoulderCowl_Gussets_LOD0": (0.95, 0.80, 0.05),
    "Mercenary_Clothed_Donor_LOD0": (0.35, 0.35, 0.35),
    "Mercenary_Male_HeadNeck_LOD0": (0.95, 0.55, 0.18),
}
for object_name, color in mapping.items():
    obj = bpy.data.objects[object_name]
    material = emission("ID_" + object_name, color)
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0

for obj in bpy.context.scene.objects:
    if obj.type == "MESH" and obj.name not in mapping:
        material = emission("ID_OTHER_" + obj.name, (0.05, 0.05, 0.05))
        obj.data.materials.clear()
        obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.material_index = 0

camera = bpy.context.scene.camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 0.95
camera.location = (0.0, 0.0, 5.0)
camera.rotation_euler = (Vector((0.0, 0.02, 1.49)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.filepath = str(STAGING / "previews/diagnostic_v13b_top_layer_ids.png")
bpy.ops.render.render(write_still=True)
