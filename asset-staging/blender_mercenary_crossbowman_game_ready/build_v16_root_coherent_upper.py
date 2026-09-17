"""Root candidate: replace the fragmented upper cowl with two coherent cloth volumes."""

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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16_root_hood.blend"

OLD_UPPER = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
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


# Snapshot nearby deform weights before removing the fragmented cowl pieces.
weight_sources = [donor] + [bpy.data.objects[name] for name in OLD_UPPER if bpy.data.objects.get(name)]
samples = []
for source_obj in weight_sources:
    group_names = {group.index: group.name for group in source_obj.vertex_groups}
    for vertex in source_obj.data.vertices:
        world = source_obj.matrix_world @ vertex.co
        if world.z < 1.34:
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

for name in OLD_UPPER:
    old = bpy.data.objects.get(name)
    if old is None:
        continue
    mesh = old.data
    bpy.data.objects.remove(old, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def make_object(name, vertices, faces, uv_builder, description):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    obj["game_asset"] = True
    obj["part_category"] = "ClothedBody"
    obj["intentional_layer"] = True
    obj["source"] = description
    mesh.materials.append(cowl_material)
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        poly.material_index = 0
        poly.use_smooth = True
        for loop_index in poly.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            uv.data[loop_index].uv = uv_builder(vertex_index)

    group_cache = {}
    for vertex in mesh.vertices:
        _co, sample_index, _distance = tree.find(obj.matrix_world @ vertex.co)
        raw = samples[sample_index][1]
        ranked = sorted(raw.items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(weight for _group, weight in ranked)
        if total <= 1.0e-8:
            ranked = [("DEF-spine.004", 1.0)]
            total = 1.0
        for group_name, weight in ranked:
            group = group_cache.get(group_name)
            if group is None:
                group = obj.vertex_groups.new(name=group_name)
                group_cache[group_name] = group
            group.add([vertex.index], weight / total, "REPLACE")

    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    return obj


# ---------------------------------------------------------------------------
# Shoulder capelet: a gently draped, closed annular shell rather than a plate.
# ---------------------------------------------------------------------------
ANGLE_SEGMENTS = 160
RADIAL_SEGMENTS = 12
cape_vertices = []
cape_faces = []


def cape_top(theta, t):
    c, s = math.cos(theta), math.sin(theta)
    smooth = t * t * (3.0 - 2.0 * t)
    inner_rx = 0.112 + 0.004 * math.sin(3.0 * theta + 0.3)
    inner_ry = 0.078 + 0.003 * math.sin(4.0 * theta - 0.5)
    # The cowl opens toward the back like a collapsed hood.  Its front edge
    # stays close to the neck, avoiding the horizontal "hat brim" silhouette.
    outer_rx = 0.230 + 0.040 * max(0.0, s)
    outer_rx += 0.006 * math.sin(3.0 * theta + 1.0)
    outer_ry = 0.170 + 0.006 * math.sin(2.0 * theta - 0.7)
    rx = inner_rx + (outer_rx - inner_rx) * smooth
    ry = inner_ry + (outer_ry - inner_ry) * smooth
    x = c * rx + 0.004 * math.sin(5.0 * theta) * smooth
    center_y = 0.012 + 0.073 * smooth
    y = center_y + s * ry
    outer_z = (
        1.445
        - 0.012 * max(0.0, s)
        + 0.015 * max(0.0, -s)
    )
    z = 1.503 + (outer_z - 1.503) * smooth
    z += 0.0045 * math.sin(4.0 * theta + 0.4) * math.sin(math.pi * t)
    z += 0.0025 * math.sin(9.0 * theta - 0.8) * (0.25 + 0.75 * t)
    z += 0.0020 * math.sin(3.0 * math.pi * t + 2.0 * theta)
    return (x, y, z)


for layer in range(2):
    for angle_index in range(ANGLE_SEGMENTS):
        theta = 2.0 * math.pi * angle_index / ANGLE_SEGMENTS
        for radial_index in range(RADIAL_SEGMENTS + 1):
            t = radial_index / RADIAL_SEGMENTS
            x, y, z = cape_top(theta, t)
            if layer == 1:
                z -= 0.011
            cape_vertices.append((x, y, z))


def cape_index(layer, angle_index, radial_index):
    ring = ANGLE_SEGMENTS * (RADIAL_SEGMENTS + 1)
    return layer * ring + (angle_index % ANGLE_SEGMENTS) * (RADIAL_SEGMENTS + 1) + radial_index


for angle_index in range(ANGLE_SEGMENTS):
    nxt = (angle_index + 1) % ANGLE_SEGMENTS
    for radial_index in range(RADIAL_SEGMENTS):
        a = cape_index(0, angle_index, radial_index)
        b = cape_index(0, angle_index, radial_index + 1)
        c = cape_index(0, nxt, radial_index + 1)
        d = cape_index(0, nxt, radial_index)
        cape_faces.append((a, b, c, d))
        cape_faces.append(
            (
                cape_index(1, angle_index, radial_index),
                cape_index(1, nxt, radial_index),
                cape_index(1, nxt, radial_index + 1),
                cape_index(1, angle_index, radial_index + 1),
            )
        )
    cape_faces.append(
        (
            cape_index(0, angle_index, 0),
            cape_index(0, nxt, 0),
            cape_index(1, nxt, 0),
            cape_index(1, angle_index, 0),
        )
    )
    cape_faces.append(
        (
            cape_index(0, angle_index, RADIAL_SEGMENTS),
            cape_index(1, angle_index, RADIAL_SEGMENTS),
            cape_index(1, nxt, RADIAL_SEGMENTS),
            cape_index(0, nxt, RADIAL_SEGMENTS),
        )
    )

cape_ring_size = ANGLE_SEGMENTS * (RADIAL_SEGMENTS + 1)


def cape_uv(vertex_index):
    within = vertex_index % cape_ring_size
    angle_index = within // (RADIAL_SEGMENTS + 1)
    radial_index = within % (RADIAL_SEGMENTS + 1)
    return (angle_index / ANGLE_SEGMENTS * 4.0, radial_index / RADIAL_SEGMENTS * 1.5)


capelet = make_object(
    "Mercenary_Cowl_CoherentCapelet_LOD0",
    cape_vertices,
    cape_faces,
    cape_uv,
    "V16 continuous draped shoulder capelet replacing fragmented repair pieces",
)


# ---------------------------------------------------------------------------
# Neck wrap: one closed lofted cloth volume with irregular folds, not toruses.
# ---------------------------------------------------------------------------
HEIGHT_SPECS = (
    (1.444, 0.195, 0.140, 0.015),
    (1.468, 0.173, 0.126, 0.012),
    (1.492, 0.184, 0.119, 0.008),
    (1.515, 0.150, 0.108, 0.008),
    (1.537, 0.156, 0.100, 0.009),
    (1.558, 0.132, 0.090, 0.010),
)
COLLAR_THICKNESS = 0.021
collar_vertices = []
collar_faces = []

for surface in range(2):
    for height_index, (z_base, rx_base, ry_base, center_y) in enumerate(HEIGHT_SPECS):
        for angle_index in range(ANGLE_SEGMENTS):
            theta = 2.0 * math.pi * angle_index / ANGLE_SEGMENTS
            phase = 0.75 * height_index
            fold = 0.0060 * math.sin(5.0 * theta + phase)
            fold += 0.0028 * math.sin(11.0 * theta - 0.4 * height_index)
            rx = rx_base + fold
            ry = ry_base + fold * 0.72
            if surface == 1:
                rx -= COLLAR_THICKNESS
                ry -= COLLAR_THICKNESS * 0.72
            z = z_base + 0.0025 * math.sin(4.0 * theta + phase)
            collar_vertices.append((math.cos(theta) * rx, center_y + math.sin(theta) * ry, z))


def collar_index(surface, height_index, angle_index):
    per_surface = len(HEIGHT_SPECS) * ANGLE_SEGMENTS
    return surface * per_surface + height_index * ANGLE_SEGMENTS + (angle_index % ANGLE_SEGMENTS)


for height_index in range(len(HEIGHT_SPECS) - 1):
    for angle_index in range(ANGLE_SEGMENTS):
        nxt = (angle_index + 1) % ANGLE_SEGMENTS
        collar_faces.append(
            (
                collar_index(0, height_index, angle_index),
                collar_index(0, height_index, nxt),
                collar_index(0, height_index + 1, nxt),
                collar_index(0, height_index + 1, angle_index),
            )
        )
        collar_faces.append(
            (
                collar_index(1, height_index, angle_index),
                collar_index(1, height_index + 1, angle_index),
                collar_index(1, height_index + 1, nxt),
                collar_index(1, height_index, nxt),
            )
        )

top_height = len(HEIGHT_SPECS) - 1
for angle_index in range(ANGLE_SEGMENTS):
    nxt = (angle_index + 1) % ANGLE_SEGMENTS
    collar_faces.append(
        (
            collar_index(0, top_height, angle_index),
            collar_index(0, top_height, nxt),
            collar_index(1, top_height, nxt),
            collar_index(1, top_height, angle_index),
        )
    )
    collar_faces.append(
        (
            collar_index(0, 0, angle_index),
            collar_index(1, 0, angle_index),
            collar_index(1, 0, nxt),
            collar_index(0, 0, nxt),
        )
    )

collar_per_surface = len(HEIGHT_SPECS) * ANGLE_SEGMENTS


def collar_uv(vertex_index):
    within = vertex_index % collar_per_surface
    height_index = within // ANGLE_SEGMENTS
    angle_index = within % ANGLE_SEGMENTS
    return (
        angle_index / ANGLE_SEGMENTS * 4.0,
        height_index / (len(HEIGHT_SPECS) - 1) * 1.5,
    )


collar = make_object(
    "Mercenary_Cowl_CoherentNeckWrap_LOD0",
    collar_vertices,
    collar_faces,
    collar_uv,
    "V16 single lofted neck wrap replacing concentric torus collars",
)

for obj in (capelet, collar):
    if nonmanifold_edges(obj):
        raise RuntimeError(f"{obj.name} is not closed manifold")
    sums = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    if min(sums) < 0.999 or max(sums) > 1.001:
        raise RuntimeError(f"{obj.name} has invalid weight sums")


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16_root_hood_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
print("V16_ROOT_TRIANGLES", total_triangles)
print("V16_ROOT_MESHES", len(character_meshes))
print("V16_ROOT_CAPELET", len(cape_vertices), len(cape_faces), triangle_count(capelet))
print("V16_ROOT_COLLAR", len(collar_vertices), len(collar_faces), triangle_count(collar))
print("V16_ROOT_NONMANIFOLD", nonmanifold_edges(capelet), nonmanifold_edges(collar))
print("V16_ROOT_OUTPUT", OUTPUT)
