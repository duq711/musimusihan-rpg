"""Fit the CC0 MakeHuman Monk's Hood Off asset to the v16j mercenary.

This is an isolated visual candidate. It never overwrites the production files.
"""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
CANDIDATE = STAGING / "cc0_makehuman_suits02_candidate"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OBJ = CANDIDATE / "clothes" / "donitz_monk_robe_hood_down" / "Monks_Hood_Down.obj"
DIFFUSE = CANDIDATE / "clothes" / "donitz_monk_robe_hood_down" / "robe_brown__diffuse.png"
NORMAL = CANDIDATE / "clothes" / "donitz_monk_robe_hood_down" / "robe__normal_gl.png"
OUTPUT = CANDIDATE / "mercenary_v16j_cc0_monk_hood_down_compact_v3_candidate.blend"
PREVIEWS = CANDIDATE / "previews"


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def create_material():
    material = bpy.data.materials.new("CC0_Monk_Hood_Off_Dark_Wool")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()

    output = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    color = nodes.new("ShaderNodeTexImage")
    color.image = bpy.data.images.load(str(DIFFUSE), check_existing=True)
    color.image.colorspace_settings.name = "sRGB"
    normal = nodes.new("ShaderNodeTexImage")
    normal.image = bpy.data.images.load(str(NORMAL), check_existing=True)
    normal.image.colorspace_settings.name = "Non-Color"
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.48

    # Darken the source brown into the charcoal wool seen in the reference.
    mix = nodes.new("ShaderNodeMixRGB")
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0
    mix.inputs[2].default_value = (0.22, 0.20, 0.18, 1.0)

    bsdf.inputs["Roughness"].default_value = 0.77
    bsdf.inputs["Specular IOR Level"].default_value = 0.25
    links.new(color.outputs["Color"], mix.inputs[1])
    links.new(mix.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(normal.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], bsdf.inputs["Normal"])
    links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    return material


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

for name in (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.wm.obj_import(filepath=str(OBJ))
hood = bpy.context.active_object
hood.name = "Mercenary_CC0_MonkHoodDown_CompactCowl_Candidate"

# MakeHuman OBJ coordinates are X width, Y vertical, Z depth. The target is
# X width, Y depth (front is negative), Z vertical. Non-uniform scaling trims
# the tall monk hood into a compact shoulder cowl while preserving its folds.
for vertex in hood.data.vertices:
    x, y, z = vertex.co
    vertex.co = (x * 0.22, z * 0.115, y * 0.075 + 0.89)
hood.rotation_euler = (0.0, 0.0, 0.0)
hood.scale = (1.0, 1.0, 1.0)

hood.data.materials.clear()
hood.data.materials.append(create_material())
for polygon in hood.data.polygons:
    polygon.use_smooth = True

bevel = hood.modifiers.new("Soft_Fabric_Edge", "BEVEL")
bevel.width = 0.0022
bevel.segments = 2
bevel.limit_method = "ANGLE"
bevel.angle_limit = 0.70

rig = bpy.data.objects.get("Mercenary_Rigify_Rig_v4")
if rig:
    hood.parent = rig
    armature = hood.modifiers.new("Mercenary_Rigify_Deform", "ARMATURE")
    armature.object = rig
    group = hood.vertex_groups.new(name="DEF-spine.004")
    group.add(range(len(hood.data.vertices)), 1.0, "REPLACE")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or obj.name.startswith("PREVIEW_"):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1200
scene.render.resolution_y = 1000
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        bg.inputs[1].default_value = 0.15

for name, location, energy, size, color in (
    ("CC0_Key", (-2.2, -2.6, 3.3), 76.0, 2.5, (1.0, 0.82, 0.68)),
    ("CC0_Fill", (2.4, -1.5, 2.5), 42.0, 2.2, (0.62, 0.76, 1.0)),
    ("CC0_Rim", (0.3, 2.4, 2.7), 56.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))

PREVIEWS.mkdir(parents=True, exist_ok=True)
camera = scene.camera
for key, location, target, lens in (
    ("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
    ("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    ("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    ("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90),
    ("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90),
):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_y = 1200 if key in {"front", "back"} else 1000
    scene.render.filepath = str(PREVIEWS / f"cc0_monk_hood_down_compact_v3_{key}.png")
    bpy.ops.render.render(write_still=True)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("SAVED", OUTPUT)
print("HOOD_VERTICES", len(hood.data.vertices), "POLYGONS", len(hood.data.polygons))
