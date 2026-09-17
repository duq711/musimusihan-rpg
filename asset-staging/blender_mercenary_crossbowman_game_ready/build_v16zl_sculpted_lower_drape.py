"""Sculpt the existing one-piece cowl lower rim to cover the donor interface.

No extra bib, ring, bridge, or shoulder panel is added. Isolated candidate only.
"""

from __future__ import annotations

from collections import defaultdict, deque
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16ze_integrated_upper_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zl_sculpted_lower_drape.blend"
REPORT = STAGING / "v16zl_sculpted_lower_drape_report.json"


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj):
    edge_faces = defaultdict(list)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        verts = list(poly.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            edge_faces[tuple(sorted((a, b)))].append(poly.index)
            adjacency[a].add(b)
            adjacency[b].add(a)
    bad = sum(len(linked) != 2 for linked in edge_faces.values())
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        seed = unseen.pop()
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for neighbour in adjacency[current]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    queue.append(neighbour)
    return bad, components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_IntegratedDrapedCowl_v16ze_LOD0"]
cowl.name = "Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"
cowl.data.name = "Mercenary_SculptedLowerDrapeCowl_v16zl_Mesh"

# Pull only the low central front rim down in a rounded U.  This turns the
# cowl's own cloth into the gap cover, avoiding a separate turtleneck/bib.
front_moved = 0
back_moved = 0
for vertex in cowl.data.vertices:
    x, y, z = vertex.co
    frontness = smoothstep((-y - 0.035) / 0.085)
    central = 1.0 - smoothstep((abs(x) - 0.045) / 0.115)
    low = 1.0 - smoothstep((z - 1.425) / 0.075)
    influence = frontness * central * low
    if influence > 0.001:
        vertex.co.z -= 0.064 * influence
        vertex.co.y -= 0.004 * influence
        front_moved += 1

    # The original hood already has a narrow rear tail, but it sits too far
    # behind the torso. Ease that existing cloth inward instead of adding a
    # flat back patch.
    back_low = (1.0 - smoothstep((z - 1.305) / 0.105))
    backness = smoothstep((y - 0.155) / 0.095)
    back_central = 1.0 - smoothstep((abs(x) - 0.050) / 0.105)
    back_influence = back_low * backness * back_central
    if back_influence > 0.001:
        vertex.co.y -= 0.066 * back_influence
        vertex.co.z += 0.010 * back_influence * abs(x) / 0.155
        back_moved += 1

cowl.data.update()

# Preserve the source UV and material. Rebuild only the three local Rigify
# weights because the low front rim moved several centimeters.
for modifier in list(cowl.modifiers):
    if modifier.type == "ARMATURE":
        cowl.modifiers.remove(modifier)
cowl.vertex_groups.clear()
groups = {name: cowl.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006")}
for vertex in cowl.data.vertices:
    z = vertex.co.z
    upper = smoothstep((z - 1.495) / 0.075)
    mid = smoothstep((z - 1.365) / 0.095)
    w006 = upper
    remaining = 1.0 - w006
    w004 = remaining * (0.58 * (1.0 - mid) + 0.16 * mid)
    w005 = remaining - w004
    groups["DEF-spine.004"].add([vertex.index], w004, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], w005, "REPLACE")
    groups["DEF-spine.006"].add([vertex.index], w006, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16ZL original one-piece cowl with its lower front rim sculpted into a short drape"

bad_edges, components = topology(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
if bad_edges or components != 1:
    raise RuntimeError(f"Cowl topology invalid: {bad_edges=}, {components=}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights invalid: {min(weight_sums)}..{max(weight_sums)}")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
camera = scene.camera


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zl_sculpted_lower_drape_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top_close": render("top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.46), 86),
    "upper_three_quarter": render("upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.43), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "front_vertices_moved": front_moved,
    "back_vertices_moved": back_moved,
    "cowl_bounds": {
        "min": [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16zl_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZL_REPORT=" + json.dumps(report, sort_keys=True))
