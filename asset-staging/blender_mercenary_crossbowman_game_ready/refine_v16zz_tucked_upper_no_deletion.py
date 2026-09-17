"""Tuck upper donor fins without deleting faces; soften cowl/sleeve junction."""

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zx_soft_irregular_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zz_tucked_upper_no_deletion.blend"
REPORT = STAGING / "v16zz_tucked_upper_no_deletion_report.json"
COWL_NAME = "Mercenary_SoftIrregularWoolCowl_v16zx_LOD0"
SLEEVES_NAME = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
ANGULAR_SEGMENTS = 192
VERTICAL_SEGMENTS = 48
ROWS = VERTICAL_SEGMENTS + 1
SURFACE_SIZE = ANGULAR_SEGMENTS * ROWS


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects[COWL_NAME]
sleeves = bpy.data.objects[SLEEVES_NAME]

# Compress the existing rear shoulder fringe beneath the cowl.  No faces are
# deleted, so the textured back panel remains completely closed and visible.
tucked_vertices = 0
for vertex in donor.data.vertices:
    co = vertex.co
    ax = abs(co.x)
    rear_gate = smoothstep((co.y - 0.055) / 0.145)
    high_gate = smoothstep((co.z - 1.235) / 0.220)
    side_gate = 1.0 - smoothstep((ax - 0.48) / 0.10)
    influence = rear_gate * high_gate * side_gate
    if influence <= 0.001:
        continue
    co.y = 0.050 + (co.y - 0.050) * (1.0 - 0.56 * influence)
    co.z -= 0.030 * influence
    co.x *= 1.0 - 0.035 * influence
    tucked_vertices += 1
donor.data.update()
donor["v16zz_tucked_upper_vertices"] = tucked_vertices
donor["v16zz_deleted_faces"] = 0

# Settle the inner sleeve caps only slightly over the shoulder roots.  This
# hides transitions while avoiding the oversized cushion profile of v16zy.
moved_sleeve_vertices = 0
for vertex in sleeves.data.vertices:
    co = vertex.co
    ax = abs(co.x)
    influence = 1.0 - smoothstep((ax - 0.10) / 0.20)
    if influence <= 0.001:
        continue
    center_y = 0.022 + 0.012 * clamp((ax - 0.10) / 0.41)
    rear = smoothstep((co.y - center_y) / 0.085)
    co.y += influence * (0.012 + 0.021 * rear)
    co.z += influence * rear * 0.003
    moved_sleeve_vertices += 1
sleeves.data.update()
sleeves["v16zz_settled_inner_sleeve_vertices"] = moved_sleeve_vertices

# Break the mathematically perfect neckline with low-amplitude cloth sag.  The
# paired inner/outer top rows move together, preserving the closed shell.
if len(cowl.data.vertices) != 2 * SURFACE_SIZE:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)}")
for surface in (0, 1):
    for row in range(ROWS):
        u = row / VERTICAL_SEGMENTS
        top_gate = 1.0 - smoothstep(u / 0.16)
        if top_gate <= 0.001:
            continue
        for angular in range(ANGULAR_SEGMENTS):
            theta = math.tau * angular / ANGULAR_SEGMENTS
            index = surface * SURFACE_SIZE + row * ANGULAR_SEGMENTS + angular
            co = cowl.data.vertices[index].co
            wave = 0.0060 * math.sin(3.0 * theta + 0.45) + 0.0035 * math.sin(5.0 * theta - 0.25)
            co.z += top_gate * wave
            radial = top_gate * (0.0025 * math.sin(2.0 * theta + 0.7))
            co.x += radial * math.cos(theta)
            co.y += radial * math.sin(theta)
cowl.data.update()
cowl["source"] = "V16ZZ soft irregular cowl; upper donor tucked without deletion"

checks = {}
for obj in (cowl, sleeves):
    stats = topology(obj)
    weights = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    expected_components = 2 if obj is sleeves else 1
    if stats["components"] != expected_components or stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Topology failed: {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weights failed: {obj.name}: {min(weights)}..{max(weights)}")
    checks[obj.name] = {
        "triangles": triangles(obj),
        "topology": stats,
        "weight_sum_range": [min(weights), max(weights)],
        "rigify": any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers),
    }

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        bg.inputs[1].default_value = 0.14

lights = []
for name, location, energy, size, color in (
    ("V16ZZ_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZZ_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZZ_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zz_tucked_upper_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "sleeves": sleeves.name,
    "deleted_faces": 0,
    "tucked_upper_vertices": tucked_vertices,
    "moved_sleeve_vertices": moved_sleeve_vertices,
    "checks": checks,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZZ_REPORT=" + json.dumps(report, sort_keys=True))
