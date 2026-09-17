"""V16 narrow candidate: preserve the useful cowl, remove radial repair clutter."""

from __future__ import annotations

from collections import defaultdict
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16_narrow_cowl.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
cowl_material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
asset_collection = donor.users_collection[0]


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def nonmanifold_edges(obj):
    counts = defaultdict(int)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
    return sum(value != 2 for value in counts.values())


# The reconstructed cowl shape is useful, but front/back projection materials
# make its top look like torn overlapping images.  Keep its geometry and give
# every face the same real wool material.
cowl.data.materials.clear()
cowl.data.materials.append(cowl_material)
for poly in cowl.data.polygons:
    poly.material_index = 0
    poly.use_smooth = True

# Snapshot cowl/donor weights, then remove only the visibly artificial pieces.
samples = []
for source_obj in (cowl, donor):
    group_names = {group.index: group.name for group in source_obj.vertex_groups}
    for vertex in source_obj.data.vertices:
        world = source_obj.matrix_world @ vertex.co
        if world.z < 1.36:
            continue
        weights = {
            group_names[item.group]: item.weight
            for item in vertex.groups
            if item.group in group_names and item.weight > 1.0e-5
        }
        if weights:
            samples.append((world.copy(), weights))

tree = KDTree(len(samples))
for index, (position, _weights) in enumerate(samples):
    tree.insert(position, index)
tree.balance()

for name in (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)

# Keep the four tiny rear closures, but make them match the cowl rather than
# reading as pale radial plates.
patches = bpy.data.objects.get("Mercenary_RearShoulder_NotchPatches_LOD0")
if patches:
    patches.data.materials.clear()
    patches.data.materials.append(cowl_material)
    for poly in patches.data.polygons:
        poly.material_index = 0


ANGLE_SEGMENTS = 160
HEIGHT_SPECS = (
    (1.450, 0.178, 0.126, 0.006),
    (1.471, 0.165, 0.118, 0.003),
    (1.492, 0.178, 0.115, 0.000),
    (1.513, 0.149, 0.104, 0.002),
    (1.533, 0.158, 0.099, 0.005),
    (1.552, 0.136, 0.091, 0.008),
    (1.571, 0.128, 0.085, 0.010),
)
THICKNESS = 0.022
vertices = []
faces = []

for surface in range(2):
    for height_index, (z_base, rx_base, ry_base, center_y) in enumerate(HEIGHT_SPECS):
        for angle_index in range(ANGLE_SEGMENTS):
            theta = 2.0 * math.pi * angle_index / ANGLE_SEGMENTS
            phase = height_index * 0.68
            fold = 0.0055 * math.sin(5.0 * theta + phase)
            fold += 0.0022 * math.sin(11.0 * theta - phase * 0.5)
            rx = rx_base + fold
            ry = ry_base + fold * 0.70
            if surface:
                rx -= THICKNESS
                ry -= THICKNESS * 0.72
            z = z_base + 0.0024 * math.sin(4.0 * theta + phase)
            vertices.append((math.cos(theta) * rx, center_y + math.sin(theta) * ry, z))


def index(surface, height_index, angle_index):
    per_surface = len(HEIGHT_SPECS) * ANGLE_SEGMENTS
    return surface * per_surface + height_index * ANGLE_SEGMENTS + (angle_index % ANGLE_SEGMENTS)


for height_index in range(len(HEIGHT_SPECS) - 1):
    for angle_index in range(ANGLE_SEGMENTS):
        nxt = (angle_index + 1) % ANGLE_SEGMENTS
        faces.append((index(0, height_index, angle_index), index(0, height_index, nxt), index(0, height_index + 1, nxt), index(0, height_index + 1, angle_index)))
        faces.append((index(1, height_index, angle_index), index(1, height_index + 1, angle_index), index(1, height_index + 1, nxt), index(1, height_index, nxt)))

top = len(HEIGHT_SPECS) - 1
for angle_index in range(ANGLE_SEGMENTS):
    nxt = (angle_index + 1) % ANGLE_SEGMENTS
    faces.append((index(0, top, angle_index), index(0, top, nxt), index(1, top, nxt), index(1, top, angle_index)))
    faces.append((index(0, 0, angle_index), index(1, 0, angle_index), index(1, 0, nxt), index(0, 0, nxt)))

mesh = bpy.data.meshes.new("Mercenary_Cowl_NarrowNeckWrap_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
collar = bpy.data.objects.new("Mercenary_Cowl_NarrowNeckWrap_LOD0", mesh)
asset_collection.objects.link(collar)
collar["game_asset"] = True
collar["part_category"] = "ClothedBody"
collar["intentional_layer"] = True
collar["source"] = "V16 single narrow lofted neck wrap; no plates or torus stack"
mesh.materials.append(cowl_material)
uv = mesh.uv_layers.new(name="UVMap")
per_surface = len(HEIGHT_SPECS) * ANGLE_SEGMENTS
for poly in mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True
    for loop_index in poly.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index % per_surface
        height_index = vertex_index // ANGLE_SEGMENTS
        angle_index = vertex_index % ANGLE_SEGMENTS
        uv.data[loop_index].uv = (angle_index / ANGLE_SEGMENTS * 4.0, height_index / (len(HEIGHT_SPECS) - 1) * 1.5)

groups = {}
for vertex in mesh.vertices:
    _point, sample_index, _distance = tree.find(collar.matrix_world @ vertex.co)
    ranked = sorted(samples[sample_index][1].items(), key=lambda item: item[1], reverse=True)[:4]
    total = sum(weight for _name, weight in ranked)
    for group_name, weight in ranked:
        group = groups.get(group_name)
        if group is None:
            group = collar.vertex_groups.new(name=group_name)
            groups[group_name] = group
        group.add([vertex.index], weight / total, "REPLACE")

modifier = collar.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
collar.parent = rig
collar.matrix_parent_inverse = rig.matrix_world.inverted()

if nonmanifold_edges(collar):
    raise RuntimeError("Narrow collar is not closed manifold")


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16_narrow_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
character_meshes = [obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None]
print("V16_NARROW_TRIANGLES", sum(triangle_count(obj) for obj in character_meshes))
print("V16_NARROW_MESHES", len(character_meshes))
print("V16_NARROW_COLLAR", len(vertices), len(faces), triangle_count(collar))
print("V16_NARROW_NONMANIFOLD", nonmanifold_edges(collar))
print("V16_NARROW_OUTPUT", OUTPUT)
