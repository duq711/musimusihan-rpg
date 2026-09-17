"""Tuck the wide v16zo hem inward so the cowl reads as bundled scarf cloth."""

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zo_realistic_singlepiece_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zs_tucked_hem_cowl.blend"
REPORT = STAGING / "v16zs_tucked_hem_cowl_report.json"
SOURCE_COWL = "Mercenary_RealisticSinglePieceCowl_v16zo_LOD0"
NEW_COWL = "Mercenary_TuckedHemWoolCowl_v16zs_LOD0"
ANG = 192
ROWS = 49


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


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


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects[SOURCE_COWL]
cowl.name = NEW_COWL
cowl.data.name = "Mercenary_TuckedHemWoolCowl_v16zs_Mesh"

surface_size = ANG * ROWS
if len(cowl.data.vertices) != 2 * surface_size:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)}")

# Preserve all of v16zo's local folds.  Only the lower quarter curls back
# toward the torso, while a softly billowed middle keeps the wool volume.
moved = 0
for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        tuck = smoothstep((u - 0.66) / 0.34)
        middle = math.exp(-((u - 0.61) / 0.19) ** 2)
        for angular in range(ANG):
            theta = math.tau * angular / ANG
            index = surface * surface_size + row * ANG + angular
            co = cowl.data.vertices[index].co
            c = math.cos(theta)
            s = math.sin(theta)
            front = max(0.0, -s)
            back = max(0.0, s)
            side = abs(c)

            # Rounded middle fullness followed by a compact under-tucked hem.
            mid_scale = 1.0 + 0.025 * middle * (
                0.65 + 0.25 * math.sin(theta + 0.7)
            )
            hem_scale_x = 1.0 - tuck * (
                0.205 - 0.035 * back + 0.020 * front
            )
            hem_scale_y = 1.0 - tuck * (
                0.145 + 0.025 * side - 0.020 * back
            )
            co.x = (co.x + 0.004) * mid_scale * hem_scale_x - 0.004
            co.y = (co.y - 0.022) * mid_scale * hem_scale_y + 0.022

            # The hem falls rather than projecting horizontally.  Broken
            # low-frequency waves keep it from becoming a straight shelf.
            co.z -= tuck * (
                0.021
                + 0.018 * front ** 1.6
                + 0.010 * back ** 1.4
                - 0.004 * side
            )
            co.z += tuck * (
                0.006 * math.sin(3.0 * theta + 0.55)
                + 0.003 * math.sin(7.0 * theta - 0.35)
            )
            moved += 1
cowl.data.update()
cowl["source"] = "V16ZS one-piece v16zo cowl with inward-curled hanging hem"
cowl["tucked_hem_vertices"] = moved
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
    path = PREVIEWS / f"diagnostic_v16zs_tucked_hem_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high": render("high", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "three_quarter": render("three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
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
    "moved_vertices": moved,
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "mesh_count": len(character_meshes),
    "deform_bones": sum(bone.use_deform for bone in rig.data.bones),
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZS_REPORT=" + json.dumps(report, sort_keys=True))
