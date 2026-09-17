"""Reshape the clean v16 upper into a softer, irregular bunched scarf."""

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zp_natural_draped_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zq_soft_bunched_cowl.blend"
REPORT = STAGING / "v16zq_soft_bunched_cowl_report.json"
COWL_SOURCE_NAME = "Mercenary_NaturalDrapedCowl_v16zp_LOD0"
COWL_NAME = "Mercenary_SoftBunchedCowl_v16zq_LOD0"
ANG = 192
ROWS = 42


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angular_delta(a, b):
    return (a - b + math.pi) % math.tau - math.pi


def ridge(theta, center, sigma):
    delta = angular_delta(theta, center)
    return math.exp(-0.5 * (delta / sigma) ** 2)


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
    return sum(value != 2 for value in edge_faces.values()), components


def cowl_point(theta, u, inner=False):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)

    # A soft upright bundle, locally opening toward the shoulders at its hem.
    top_rx = 0.134 + 0.008 * math.sin(3.0 * theta + 0.45) + 0.003 * left
    top_ry = 0.105 + 0.006 * math.sin(2.0 * theta - 0.35) + 0.005 * back
    skirt = smoothstep((u - 0.38) / 0.62)
    bottom_rx = 0.205 + 0.057 * side ** 3.2 * skirt + 0.010 * left
    bottom_ry = 0.170 + 0.054 * back ** 1.7 * skirt + 0.026 * front ** 1.5 * skirt
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # Three broken folds live on different sides instead of circling the neck.
    path_a = 0.25 + 0.105 * math.sin(theta + 0.30) + 0.020 * math.sin(3.0 * theta)
    path_b = 0.51 + 0.090 * math.sin(theta - 1.05) - 0.024 * math.sin(2.0 * theta)
    path_c = 0.77 + 0.070 * math.sin(theta + 1.50) + 0.018 * math.sin(4.0 * theta)
    crest_a = math.exp(-((u - path_a) / 0.095) ** 2)
    crest_b = math.exp(-((u - path_b) / 0.110) ** 2)
    crest_c = math.exp(-((u - path_c) / 0.105) ** 2)
    valley_a = math.exp(-((u - path_a - 0.12) / 0.070) ** 2)
    valley_b = math.exp(-((u - path_b - 0.13) / 0.075) ** 2)
    valley_c = math.exp(-((u - path_c - 0.11) / 0.070) ** 2)
    mask_a = clamp(0.10 + 0.67 * front + 0.31 * right)
    mask_b = clamp(0.12 + 0.64 * front + 0.30 * left)
    mask_c = clamp(0.10 + 0.68 * back + 0.23 * left)
    relief = mask_a * (0.014 * crest_a - 0.006 * valley_a)
    relief += mask_b * (0.019 * crest_b - 0.008 * valley_b)
    relief += mask_c * (0.014 * crest_c - 0.006 * valley_c)

    # Additional diagonal bunches keep the visible folds organic.
    fold_envelope = math.sin(math.pi * u) ** 1.25
    diagonal = 0.0
    for base, slope, width, amount in (
        (1.42 * math.pi, +0.72, 0.25, 0.014),
        (1.72 * math.pi, -0.48, 0.20, 0.010),
        (0.58 * math.pi, +0.54, 0.24, 0.011),
        (0.92 * math.pi, -0.50, 0.21, 0.009),
    ):
        diagonal += amount * ridge(theta, base + slope * (u - 0.5), width)
    relief += fold_envelope * diagonal
    relief += fold_envelope * (
        0.0025 * math.sin(5.0 * theta + 3.2 * u)
        + 0.0015 * math.sin(9.0 * theta - 2.1 * u)
    )

    thickness = 0.0095 + 0.0010 * math.sin(3.0 * theta + 2.0 * u)
    if inner:
        relief *= 0.55
        rx -= thickness
        ry -= 0.92 * thickness

    tangential = fold_envelope * (
        0.0050 * math.sin(2.0 * theta + 1.1 * u)
        + 0.0020 * math.sin(5.0 * theta - 0.7)
    )
    x = -0.006 * math.sin(math.pi * u) + (rx + relief) * c - tangential * s
    y = 0.012 + 0.012 * eased + (ry + 0.74 * relief) * s + 0.70 * tangential * c

    top_z = 1.568 + 0.028 * back - 0.014 * front + 0.006 * left
    bottom_z = (
        1.403
        + 0.020 * side ** 1.5
        - 0.039 * front ** 1.7
        - 0.072 * back ** 1.65
        - 0.004 * left
        + 0.007 * math.sin(theta + 0.60)
        + 0.004 * math.sin(4.0 * theta - 0.35)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += fold_envelope * (
        0.006 * mask_a * crest_a
        + 0.009 * mask_b * crest_b
        + 0.006 * mask_c * crest_c
        + 0.003 * math.sin(3.0 * theta + 2.2 * u)
    )
    if inner:
        z -= 0.0018 * fold_envelope
    return x, y, z


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects[COWL_SOURCE_NAME]
cowl.name = COWL_NAME
cowl.data.name = "Mercenary_SoftBunchedCowl_v16zq_Mesh"

expected = 2 * ANG * ROWS
if len(cowl.data.vertices) != expected:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)} != {expected}")
surface_size = ANG * ROWS
for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANG):
            theta = math.tau * angular / ANG
            index = surface * surface_size + row * ANG + angular
            cowl.data.vertices[index].co = cowl_point(theta, u, inner=bool(surface))
cowl.data.update()

# Rebuild normalized Rigify weights for the compact shape.
cowl.vertex_groups.clear()
names = (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
    "DEF-shoulder.L", "DEF-shoulder.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in names}
for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANG):
            index = surface * surface_size + row * ANG + angular
            vertex = cowl.data.vertices[index]
            side = smoothstep((abs(vertex.co.x) - 0.185) / 0.090) * smoothstep((u - 0.55) / 0.45)
            shoulder = 0.24 * side
            torso = 1.0 - shoulder
            neck = torso * (0.72 * (1.0 - smoothstep(u / 0.75)) + 0.08)
            chest = torso * (0.18 + 0.48 * smoothstep((u - 0.30) / 0.70))
            upper = max(0.0, torso - neck - chest)
            total = neck + chest + upper + shoulder
            weights = {
                "DEF-spine.004": chest / total,
                "DEF-spine.005": upper / total,
                "DEF-spine.006": neck / total,
                "DEF-shoulder.L": shoulder / total if vertex.co.x >= 0.0 else 0.0,
                "DEF-shoulder.R": shoulder / total if vertex.co.x < 0.0 else 0.0,
            }
            for name, weight in weights.items():
                if weight > 0.0:
                    groups[name].add([index], weight, "REPLACE")

cowl["source"] = "V16ZQ single soft bunched scarf with broken diagonal folds"
cowl["no_concentric_rings"] = True

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
    path = PREVIEWS / f"diagnostic_v16zq_soft_bunched_{key}.png"
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
print("V16ZQ_REPORT=" + json.dumps(report, sort_keys=True))
