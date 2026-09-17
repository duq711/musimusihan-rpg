"""Selective cowl-top repair and a fitted inner-neck cloth liner prototype."""

from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v11c.blend"
LIFTED_TEXTURE = STAGING / "textures" / "cowl_wool_basecolor_4k_lifted.jpg"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
asset_collection = cowl.users_collection[0]

# Retain the original cowl material on front/back/side faces.  Only surfaces
# aimed upward receive a lifted charcoal version of the same 4K wool set.
source_material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
top_material = source_material.copy()
top_material.name = "MAT_CowlTop_LiftedCharcoal_PBR_4K"
lifted_image = bpy.data.images.load(str(LIFTED_TEXTURE), check_existing=True)
lifted_image.name = "cowl_wool_basecolor_4k_lifted.jpg"
top_material.node_tree.nodes["BaseColor_4K"].image = lifted_image
top_material.diffuse_color = (0.18, 0.16, 0.14, 1.0)
cowl.data.materials.append(top_material)
top_index = len(cowl.data.materials) - 1

uv = cowl.data.uv_layers.get("UVMap") or cowl.data.uv_layers.new(name="UVMap")
top_faces = []
for polygon in cowl.data.polygons:
    if polygon.normal.z <= 0.34:
        continue
    polygon.material_index = top_index
    polygon.use_smooth = True
    top_faces.append(polygon)
    per_loop = []
    for loop_index in polygon.loop_indices:
        co = cowl.data.vertices[cowl.data.loops[loop_index].vertex_index].co
        angle_u = math.atan2(co.y - 0.005, co.x) / (2.0 * math.pi) + 0.5
        vertical_v = (co.z - 1.43) * 9.0
        per_loop.append([loop_index, angle_u, vertical_v])
    us = [item[1] for item in per_loop]
    if max(us) - min(us) > 0.5:
        for item in per_loop:
            if item[1] < 0.5:
                item[1] += 1.0
    for loop_index, u, v in per_loop:
        uv.data[loop_index].uv = (u * 2.2, v)

# Slightly enlarge the existing hidden shoulder gussets and use the same wool.
for vertex in yoke.data.vertices:
    side = 1.0 if vertex.co.x >= 0.0 else -1.0
    cx = side * 0.245
    vertex.co.x = cx + (vertex.co.x - cx) * 1.12
    vertex.co.y = 0.105 + (vertex.co.y - 0.105) * 1.18
    vertex.co.z += 0.004
yoke.data.update()
yoke.data.materials.clear()
yoke.data.materials.append(top_material)
for polygon in yoke.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# The head side material inherited the near-black cowl texture, creating the
# apparent black scalp cap in overhead views.  Keep the projected face/hair
# detail and replace only those side-classified faces with a brown hair cloth
# material that reuses the existing 4K normal/roughness set.
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
hair_material = source_material.copy()
hair_material.name = "MAT_HairSide_DarkBrown_PBR"
hair_nodes = hair_material.node_tree.nodes
hair_links = hair_material.node_tree.links
hair_principled = hair_nodes["Principled BSDF"]
for link in list(hair_links):
    if link.to_node == hair_principled and link.to_socket.name == "Base Color":
        hair_links.remove(link)
hair_principled.inputs["Base Color"].default_value = (0.012, 0.0045, 0.0018, 1.0)
hair_principled.inputs["Roughness"].default_value = 0.62
head.data.materials.append(hair_material)
hair_index = len(head.data.materials) - 1
for polygon in head.data.polygons:
    if polygon.material_index == 5:
        polygon.material_index = hair_index
        polygon.use_smooth = True

liner_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"].copy()
liner_material.name = "MAT_InnerCowl_WarmLining_PBR_4K"
liner_material.diffuse_color = (0.24, 0.17, 0.12, 1.0)
liner_nodes = liner_material.node_tree.nodes
liner_links = liner_material.node_tree.links
liner_principled = liner_nodes["Principled BSDF"]
for link in list(liner_links):
    if link.to_node == liner_principled and link.to_socket.name == "Base Color":
        liner_links.remove(link)
liner_principled.inputs["Base Color"].default_value = (0.070, 0.040, 0.020, 1.0)
liner_principled.inputs["Roughness"].default_value = 0.82

# Add a shallow closed annular underscarf just below the head/neck boundary.
# It replaces the deep empty well without appearing in ordinary front views.
segments = 96
center_y = 0.008
inner_rx, inner_ry = 0.082, 0.056
outer_rx, outer_ry = 0.204, 0.142
inner_z, outer_z = 1.494, 1.462
thickness = 0.009
vertices = []
faces = []

for layer in (0, 1):
    dz = -thickness if layer else 0.0
    for ring in (0, 1):
        rx, ry = (inner_rx, inner_ry) if ring == 0 else (outer_rx, outer_ry)
        z = (inner_z if ring == 0 else outer_z) + dz
        for index in range(segments):
            angle = 2.0 * math.pi * index / segments
            vertices.append((rx * math.cos(angle), center_y + ry * math.sin(angle), z))


def vid(layer, ring, index):
    return (layer * 2 + ring) * segments + index % segments


for index in range(segments):
    following = index + 1
    faces.append((vid(0, 0, index), vid(0, 1, index), vid(0, 1, following), vid(0, 0, following)))
    faces.append((vid(1, 0, following), vid(1, 1, following), vid(1, 1, index), vid(1, 0, index)))
    faces.append((vid(0, 1, index), vid(1, 1, index), vid(1, 1, following), vid(0, 1, following)))
    faces.append((vid(0, 0, following), vid(1, 0, following), vid(1, 0, index), vid(0, 0, index)))

mesh = bpy.data.meshes.new("Mercenary_InnerCowl_Liner_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
liner = bpy.data.objects.new("Mercenary_InnerCowl_Liner_LOD0", mesh)
asset_collection.objects.link(liner)
liner["game_asset"] = True
liner["part_category"] = "ClothedBody"
liner["intentional_layer"] = True
mesh.materials.append(liner_material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

liner_uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        liner_uv.data[loop_index].uv = (co.x * 7.0, co.y * 7.0)

group = liner.vertex_groups.new(name="DEF-spine.004")
group.add([vertex.index for vertex in mesh.vertices], 1.0, "REPLACE")
armature = liner.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
liner.parent = rig
liner.matrix_parent_inverse = rig.matrix_world.inverted()

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v11c_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
render("failure", failure_location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("TOP_COWL_FACES", len(top_faces))
print("WROTE", OUTPUT)
