"""Render a false-colour material/object ID view of the v9 shoulder area."""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
BLEND = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUT = STAGING / "previews" / "diagnostic_v9_material_ids_top.png"

bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene


def emission_material(name, colour):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (*colour, 1.0)
    emission.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


colours = [
    (1.0, 0.0, 0.8),  # front projection
    (0.0, 0.8, 1.0),  # back projection
    (1.0, 0.45, 0.25),  # skin
    (0.2, 1.0, 0.2),  # gambeson
    (1.0, 0.1, 0.1),  # outer wool
    (0.15, 0.25, 1.0),  # cowl
    (1.0, 0.9, 0.05),  # leather
]
id_materials = [emission_material(f"ID_{index}", colour) for index, colour in enumerate(colours)]
yoke_material = emission_material("ID_YOKE", (1.0, 0.35, 0.0))

for obj in scene.objects:
    if obj.type != "MESH":
        continue
    if obj.name == "Mercenary_UnderCowl_Yoke_LOD0":
        obj.data.materials.clear()
        obj.data.materials.append(yoke_material)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
        continue
    for index, slot in enumerate(obj.material_slots):
        slot.material = id_materials[min(index, len(id_materials) - 1)]

for obj_name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(obj_name)
    if obj:
        obj.hide_render = True

camera = scene.camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.42
camera.location = (0.0, 0.0, 5.0)
camera.rotation_euler = (0.0, 0.0, 0.0)
camera.rotation_euler = (Vector((0.0, 0.0, 0.95)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 1500
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.filepath = str(OUT)
scene.world.color = (0.02, 0.02, 0.02)
bpy.ops.render.render(write_still=True)
print("WROTE", OUT)
