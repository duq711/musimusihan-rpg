"""Create a clean two-fold wool cowl from the structurally sound v16zm file."""

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zr_two_fold_cowl.blend"
REPORT = STAGING / "v16zr_two_fold_cowl_report.json"
SOURCE_COWL = "Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"
NEW_COWL = "Mercenary_TwoFoldWoolCowl_v16zr_LOD0"
ANG = 168
ROWS = 41


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angular_delta(a, b):
    return (a - b + math.pi) % math.tau - math.pi


def ridge(theta, center, width):
    return math.exp(-0.5 * (angular_delta(theta, center) / width) ** 2)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj):
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            linked = adjacency[stack.pop()] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return sum(count != 2 for count in edge_faces.values()), components


def cowl_point(theta, u, inner=False):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)

    top_rx = 0.128 + 0.010 * math.sin(3.0 * theta + 0.42) + 0.003 * left
    top_ry = 0.100 + 0.008 * math.sin(2.0 * theta - 0.38) + 0.004 * back
    skirt = smoothstep((u - 0.42) / 0.58)
    bottom_rx = 0.192 + 0.068 * side ** 3.4 * skirt + 0.010 * left
    bottom_ry = 0.160 + 0.087 * back ** 1.7 * skirt + 0.025 * front * skirt
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # Two uneven, wandering folds.  Each is strong only over part of the cowl,
    # so neither becomes a complete circular band in top view.
    path_upper = 0.34 + 0.095 * math.sin(theta + 0.25) + 0.025 * math.sin(3.0 * theta)
    path_lower = 0.68 + 0.085 * math.sin(theta - 1.10) - 0.022 * math.sin(2.0 * theta)
    upper = math.exp(-((u - path_upper) / 0.105) ** 2)
    lower = math.exp(-((u - path_lower) / 0.120) ** 2)
    upper_valley = math.exp(-((u - path_upper - 0.13) / 0.070) ** 2)
    lower_valley = math.exp(-((u - path_lower - 0.14) / 0.080) ** 2)
    upper_mask = clamp(0.08 + 0.74 * front + 0.28 * right + 0.16 * back)
    lower_mask = clamp(0.08 + 0.67 * front + 0.34 * left + 0.28 * back)
    relief = upper_mask * (0.025 * upper - 0.009 * upper_valley)
    relief += lower_mask * (0.030 * lower - 0.011 * lower_valley)

    envelope = math.sin(math.pi * u) ** 1.25
    # Diagonal bunches cross the two primary folds and break their outlines.
    diagonal = (
        0.015 * ridge(theta, 1.43 * math.pi + 0.68 * (u - 0.5), 0.24)
        + 0.010 * ridge(theta, 0.62 * math.pi - 0.52 * (u - 0.5), 0.23)
        + 0.008 * ridge(theta, 0.98 * math.pi + 0.43 * (u - 0.5), 0.19)
    )
    relief += envelope * diagonal
    relief += envelope * (
        0.0030 * math.sin(5.0 * theta + 2.2 * u)
        + 0.0017 * math.sin(9.0 * theta - 2.8 * u)
    )

    thickness = 0.0102 + 0.0012 * math.sin(3.0 * theta + 2.0 * u)
    if inner:
        relief *= 0.58
        rx -= thickness
        ry -= thickness * 0.92

    tangential = envelope * (
        0.0055 * math.sin(2.0 * theta + 1.3 * u)
        + 0.0025 * math.sin(5.0 * theta - 0.7)
    )
    x = -0.007 * math.sin(math.pi * u) + (rx + relief) * c - tangential * s
    y = 0.012 + 0.015 * eased + (ry + 0.74 * relief) * s + 0.70 * tangential * c

    top_z = 1.594 + 0.025 * back - 0.018 * front + 0.006 * left
    bottom_z = (
        1.405
        + 0.014 * side
        - 0.039 * front ** 1.7
        - 0.096 * back ** 1.7
        - 0.005 * left
        + 0.009 * math.sin(theta + 0.62)
        + 0.004 * math.sin(4.0 * theta - 0.32)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += envelope * (
        0.011 * upper_mask * upper
        + 0.014 * lower_mask * lower
        + 0.0035 * math.sin(3.0 * theta + 2.4 * u)
    )
    # A rounded lower-front dip covers the chest interface without a point.
    z -= 0.018 * front ** 2.2 * smoothstep((u - 0.76) / 0.24)
    if inner:
        z -= 0.0018 * envelope
    return x, y, z


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects[SOURCE_COWL]
cowl.name = NEW_COWL
cowl.data.name = "Mercenary_TwoFoldWoolCowl_v16zr_Mesh"

surface_size = ANG * ROWS
if len(cowl.data.vertices) != 2 * surface_size:
    raise RuntimeError(f"Unexpected vertex count: {len(cowl.data.vertices)}")
for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANG):
            theta = math.tau * angular / ANG
            index = surface * surface_size + row * ANG + angular
            cowl.data.vertices[index].co = cowl_point(theta, u, inner=bool(surface))
cowl.data.update()

cowl.vertex_groups.clear()
group_names = ("DEF-spine.004", "DEF-spine.005", "DEF-spine.006")
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        neck = 0.12 + 0.72 * (1.0 - smoothstep(u / 0.78))
        chest = 0.18 + 0.47 * smoothstep((u - 0.28) / 0.72)
        upper = max(0.0, 1.0 - neck - chest)
        total = neck + chest + upper
        for angular in range(ANG):
            index = surface * surface_size + row * ANG + angular
            groups["DEF-spine.004"].add([index], chest / total, "REPLACE")
            groups["DEF-spine.005"].add([index], upper / total, "REPLACE")
            groups["DEF-spine.006"].add([index], neck / total, "REPLACE")

cowl["source"] = "V16ZR one-piece medieval wool cowl with two broken asymmetrical folds"
cowl["single_connected_sheet"] = True
cowl["separate_cowl_rings"] = 0

bad_edges, components = topology(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
if bad_edges or components != 1:
    raise RuntimeError(f"Topology failed: {bad_edges=}, {components=}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Weights failed: {min(weight_sums)}..{max(weight_sums)}")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
camera = scene.camera


def render(key, location, target, lens=84, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zr_two_fold_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top_close": render("top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "upper_three_quarter": render("upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "mesh_count": len(character_meshes),
    "deform_bones": sum(bone.use_deform for bone in rig.data.bones),
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZR_REPORT=" + json.dumps(report, sort_keys=True))
