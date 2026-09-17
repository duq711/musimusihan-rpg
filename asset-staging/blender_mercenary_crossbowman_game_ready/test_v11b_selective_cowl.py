"""Prototype v11: repair only exposed dark cowl faces and add fitted cloth underlayers."""

from __future__ import annotations

from pathlib import Path
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v11b.blend"
LIFTED_TEXTURE = STAGING / "textures" / "cowl_wool_basecolor_4k_charcoal_v11.jpg"
HAIR_SOURCE_TEXTURE = STAGING / "textures" / "hair_cards_2k.png"
HAIR_SCALP_TEXTURE = STAGING / "textures" / "hair_scalp_darkbrown_2k_v11.png"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
asset_collection = cowl.users_collection[0]

# The side classifier also assigned the head's scalp/ear/neck side faces to
# the almost-black cowl material.  Front/back projection is deliberately not
# used here: the crown coordinates fall on the white reference background.
# Instead, restore the lower side faces to the existing skin PBR and map only
# the upper scalp to the project's 2K strand texture.  Geometry and weights are
# unchanged, and the original projected face/hair detail remains on mat0/1.
hair_source_image = bpy.data.images.load(str(HAIR_SOURCE_TEXTURE), check_existing=True)
hair_pixels = np.empty(len(hair_source_image.pixels), dtype=np.float32)
hair_source_image.pixels.foreach_get(hair_pixels)
hair_rgba = hair_pixels.reshape((-1, 4))
# The source RGB is intentionally very dark because it was authored for
# alpha-blended cards.  On an opaque scalp shell that reads as a flat cap.
# Reuse its alpha strand mask as colour/height contrast while keeping every
# output pixel opaque, so no new holes can appear in Godot.
strand_mask = hair_rgba[:, 3:4].copy()
hair_rgba[:, :3] = np.clip(
    np.array((0.022, 0.012, 0.006), dtype=np.float32)
    + strand_mask * np.array((0.120, 0.065, 0.028), dtype=np.float32)
    + hair_rgba[:, :3] * 0.40,
    0.0,
    1.0,
)
hair_rgba[:, 3] = 1.0
hair_image = bpy.data.images.get("hair_scalp_darkbrown_2k_v11.png")
if hair_image is None:
    hair_image = bpy.data.images.new(
        "hair_scalp_darkbrown_2k_v11.png",
        width=hair_source_image.size[0],
        height=hair_source_image.size[1],
        alpha=False,
    )
hair_image.colorspace_settings.name = hair_source_image.colorspace_settings.name
hair_image.pixels.foreach_set(hair_rgba.reshape(-1))
hair_image.filepath_raw = str(HAIR_SCALP_TEXTURE)
hair_image.file_format = "PNG"
hair_image.save()

hair_material = bpy.data.materials.new("MAT_ScalpHair_DarkBrown_PBR_2K_v11")
hair_material.use_nodes = True
hair_material.diffuse_color = (0.085, 0.052, 0.033, 1.0)
hair_material.roughness = 0.68
nodes = hair_material.node_tree.nodes
nodes.clear()
output_node = nodes.new("ShaderNodeOutputMaterial")
hair_shader = nodes.new("ShaderNodeBsdfPrincipled")
hair_texture = nodes.new("ShaderNodeTexImage")
hair_texture.name = "HairStrands_2K"
hair_texture.image = hair_image
hair_texture.extension = "REPEAT"
hair_bump = nodes.new("ShaderNodeBump")
hair_bump.inputs["Strength"].default_value = 0.20
hair_bump.inputs["Distance"].default_value = 0.003
hair_shader.inputs["Roughness"].default_value = 0.66
hair_shader.inputs["Metallic"].default_value = 0.0
if "Anisotropic IOR Level" in hair_shader.inputs:
    hair_shader.inputs["Anisotropic IOR Level"].default_value = 0.22
elif "Anisotropic" in hair_shader.inputs:
    hair_shader.inputs["Anisotropic"].default_value = 0.22
hair_material.node_tree.links.new(hair_texture.outputs["Color"], hair_shader.inputs["Base Color"])
hair_material.node_tree.links.new(hair_texture.outputs["Color"], hair_bump.inputs["Height"])
hair_material.node_tree.links.new(hair_bump.outputs["Normal"], hair_shader.inputs["Normal"])
hair_material.node_tree.links.new(hair_shader.outputs["BSDF"], output_node.inputs["Surface"])

head.data.materials.append(hair_material)
hair_material_index = len(head.data.materials) - 1
skin_material_index = 2
head_scalp_faces = 0
head_skin_restored_faces = 0
for polygon in head.data.polygons:
    if polygon.material_index != 5:
        continue
    is_scalp = polygon.center.z >= 1.66
    polygon.material_index = hair_material_index if is_scalp else skin_material_index
    # Preserve the source v9 side UVs: top-like faces already use XY tiling and
    # side-like faces use YZ tiling.  That mapping suits both the seamless skin
    # PBR and the opaque strand tile without introducing a crown singularity.
    if is_scalp:
        head_scalp_faces += 1
    else:
        head_skin_restored_faces += 1
head.data.update()

# Duplicate the original cowl PBR set.  This preserves its normal/ORM weave;
# only the base colour is replaced with a lifted charcoal derivative.
source_material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
top_material = source_material.copy()
top_material.name = "MAT_CowlTop_SelectiveCharcoal_PBR_4K"
source_image = bpy.data.images["cowl_wool_basecolor_4k.jpg"]
pixels = np.empty(len(source_image.pixels), dtype=np.float32)
source_image.pixels.foreach_get(pixels)
rgba = pixels.reshape((-1, 4))
rgba[:, :3] = np.clip(rgba[:, :3] * 5.5 + 0.060, 0.0, 1.0)
lifted_image = bpy.data.images.get("cowl_wool_basecolor_4k_charcoal_v11.jpg")
if lifted_image is None:
    lifted_image = bpy.data.images.new(
        "cowl_wool_basecolor_4k_charcoal_v11.jpg",
        width=source_image.size[0],
        height=source_image.size[1],
        alpha=False,
    )
lifted_image.colorspace_settings.name = source_image.colorspace_settings.name
lifted_image.pixels.foreach_set(rgba.reshape(-1))
lifted_image.filepath_raw = str(LIFTED_TEXTURE)
lifted_image.file_format = "JPEG"
lifted_image.save()
top_material.node_tree.nodes["BaseColor_4K"].image = lifted_image
top_material.diffuse_color = (0.23, 0.225, 0.215, 1.0)
cowl.data.materials.append(top_material)
top_index = len(cowl.data.materials) - 1

# A face is eligible only when it was originally the nearly-black cowl PBR,
# it faces upward, and it is the first cowl face hit by a true vertical ray.
# Projection faces and every side/front/back face retain the v9 material/UV.
bm = bmesh.new()
bm.from_mesh(cowl.data)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
bvh = BVHTree.FromBMesh(bm, epsilon=1.0e-7)
selected = []
for face in bm.faces:
    if face.material_index != 5 or face.normal.z <= 0.50:
        continue
    center = face.calc_center_median()
    _location, _normal, hit_index, _distance = bvh.ray_cast(
        Vector((center.x, center.y, 2.4)), Vector((0.0, 0.0, -1.0))
    )
    if hit_index != face.index:
        continue
    selected.append(face)
    face.material_index = top_index
    face.smooth = True
    for loop in face.loops:
        co = loop.vert.co
        loop[uv_layer].uv = (co.x * 4.0, co.y * 4.0)
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()

# Extend only each gusset's outer tip by at most 15 mm and lift it 2 mm.  The
# neck-side footprint remains untouched, preventing a broad shoulder pad.
for vertex in yoke.data.vertices:
    side = 1.0 if vertex.co.x >= 0.0 else -1.0
    outward = max(0.0, abs(vertex.co.x) - 0.245) / 0.086
    vertex.co.x += side * 0.015 * min(1.0, outward)
    vertex.co.z += 0.002
yoke.data.update()
yoke.data.materials.clear()
yoke.data.materials.append(top_material)
for polygon in yoke.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Two closed, seam-sized gussets cover the measured outer/front notches only.
# They overlap the original yoke and sleeve by a few millimetres and remain
# fully inside the existing shoulder silhouette.
gusset_vertices = []
gusset_faces = []
for side, tip_y in ((-1.0, 0.010), (1.0, 0.005)):
    start = len(gusset_vertices)
    top = [
        (side * 0.318, 0.037, 1.448),
        (side * 0.355, tip_y, 1.442),
        (side * 0.368, 0.038, 1.435),
    ]
    gusset_vertices.extend(top)
    gusset_vertices.extend((x, y, z - 0.008) for x, y, z in top)
    gusset_faces.extend(
        [
            (start + 0, start + 1, start + 2),
            (start + 5, start + 4, start + 3),
            (start + 0, start + 3, start + 4, start + 1),
            (start + 1, start + 4, start + 5, start + 2),
            (start + 2, start + 5, start + 3, start + 0),
        ]
    )
gusset_mesh = bpy.data.meshes.new("Mercenary_ShoulderCowl_Gussets_LOD0_Mesh")
gusset_mesh.from_pydata(gusset_vertices, [], gusset_faces)
gusset_mesh.update()
gussets = bpy.data.objects.new("Mercenary_ShoulderCowl_Gussets_LOD0", gusset_mesh)
asset_collection.objects.link(gussets)
gussets["game_asset"] = True
gussets["part_category"] = "ClothedBody"
gussets["intentional_layer"] = True
gussets["source"] = "V11 closed sewn gussets for measured outer/front seam notches"
gusset_mesh.materials.append(top_material)
gusset_uv = gusset_mesh.uv_layers.new(name="UVMap")
for polygon in gusset_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = gusset_mesh.vertices[gusset_mesh.loops[loop_index].vertex_index].co
        gusset_uv.data[loop_index].uv = (co.x * 4.0, co.y * 4.0)
for side in ("L", "R"):
    spine_group = gussets.vertex_groups.get("DEF-spine.004") or gussets.vertex_groups.new(name="DEF-spine.004")
    arm_group = gussets.vertex_groups.get("DEF-upper_arm." + side) or gussets.vertex_groups.new(name="DEF-upper_arm." + side)
    indices = [vertex.index for vertex in gusset_mesh.vertices if (vertex.co.x >= 0.0) == (side == "L")]
    spine_group.add(indices, 0.38, "REPLACE")
    arm_group.add(indices, 0.62, "REPLACE")
gusset_armature = gussets.modifiers.new("RigifyDeform", "ARMATURE")
gusset_armature.object = rig
gusset_armature.use_deform_preserve_volume = True
gussets.parent = rig
gussets.matrix_parent_inverse = rig.matrix_world.inverted()

# Closed sloped annular liner.  Its inner edge slightly overlaps the existing
# head/neck base, eliminating the empty well while remaining behind the cowl
# in standard character views.
segments = 96
radial_segments = 4
inner_center_y, outer_center_y = 0.050, 0.008
inner_rx, inner_ry = 0.100, 0.055
outer_rx, outer_ry = 0.190, 0.130
inner_z, outer_z = 1.488, 1.447
thickness = 0.007
vertices = []
faces = []
for layer in (0, 1):
    dz = -thickness if layer else 0.0
    for ring in range(radial_segments + 1):
        t = ring / radial_segments
        smooth_t = t * t * (3.0 - 2.0 * t)
        rx = inner_rx * (1.0 - smooth_t) + outer_rx * smooth_t
        ry = inner_ry * (1.0 - smooth_t) + outer_ry * smooth_t
        center_y = inner_center_y * (1.0 - smooth_t) + outer_center_y * smooth_t
        for index in range(segments):
            angle = 2.0 * math.pi * index / segments
            fold = 0.0045 * math.sin(math.pi * t) * math.cos(3.0 * angle + 0.35)
            z = inner_z * (1.0 - smooth_t) + outer_z * smooth_t + fold + dz
            vertices.append((rx * math.cos(angle), center_y + ry * math.sin(angle), z))


def vid(layer, ring, index):
    return (layer * (radial_segments + 1) + ring) * segments + index % segments


for index in range(segments):
    following = index + 1
    for ring in range(radial_segments):
        faces.append((vid(0, ring, index), vid(0, ring + 1, index), vid(0, ring + 1, following), vid(0, ring, following)))
        faces.append((vid(1, ring, following), vid(1, ring + 1, following), vid(1, ring + 1, index), vid(1, ring, index)))
    faces.append((vid(0, radial_segments, index), vid(1, radial_segments, index), vid(1, radial_segments, following), vid(0, radial_segments, following)))
    faces.append((vid(0, 0, following), vid(1, 0, following), vid(1, 0, index), vid(0, 0, index)))

mesh = bpy.data.meshes.new("Mercenary_InnerCowl_Liner_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
liner = bpy.data.objects.new("Mercenary_InnerCowl_Liner_LOD0", mesh)
asset_collection.objects.link(liner)
liner["game_asset"] = True
liner["part_category"] = "ClothedBody"
liner["intentional_layer"] = True
liner["source"] = "V11 fitted closed annular under-scarf; no empty neck well"
mesh.materials.append(top_material)
liner_uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        liner_uv.data[loop_index].uv = (co.x * 7.0, co.y * 7.0)

# The source head/neck base is weighted entirely to DEF-spine.006.
group = liner.vertex_groups.new(name="DEF-spine.006")
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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v11b_{name}.png")
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
render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
for direction_index in range(8):
    ring_azimuth = math.radians(direction_index * 45.0)
    ring_location = (
        radius * math.cos(elevation) * math.sin(ring_azimuth),
        -radius * math.cos(elevation) * math.cos(ring_azimuth),
        0.95 + radius * math.sin(elevation),
    )
    render(
        f"high_{direction_index * 45:03d}",
        ring_location,
        (0.0, 0.06, 1.02),
        lens=78,
        resolution=(900, 700),
    )
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("SELECTED_TOP_DARK_COWL_FACES", len(selected))
print("WROTE", OUTPUT)
