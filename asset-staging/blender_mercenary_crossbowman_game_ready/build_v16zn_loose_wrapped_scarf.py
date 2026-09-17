"""Build v16zn: a single continuous loose wrapped wool scarf/cowl.

The visible surface is one irregular annular cloth sheet that transitions from
a natural neck opening into a soft clavicle/shoulder drape.  It does not use
stacked rings, torus primitives, bibs, caps, or patch panels.  This script only
writes the unique isolated v16zn candidate and diagnostics.
"""

from __future__ import annotations

from collections import defaultdict, deque
import bmesh
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zn_loose_wrapped_scarf.blend"
REPORT = STAGING / "v16zn_loose_wrapped_scarf_report.json"


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


def recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
old_cowl = bpy.data.objects["Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"]
material = old_cowl.data.materials[0]
collection = old_cowl.users_collection[0]
bpy.data.objects.remove(old_cowl, do_unlink=True)

# One open annular mid-surface.  It is a gathered funnel-shaped sheet, not a
# stack of primitives: two fold crests wander diagonally around the neck and
# the low cloth eases over the clavicles before curling slightly inward.
N_THETA = 192
N_DRAPE = 48
vertices = []
faces = []
uv_values = []

for j in range(N_DRAPE):
    t = j / (N_DRAPE - 1)
    for i in range(N_THETA):
        theta = math.tau * i / N_THETA
        c, s = math.cos(theta), math.sin(theta)
        front = max(0.0, -s)
        back = max(0.0, s)
        side = abs(c)

        top_z = (
            1.552 + 0.050 * back ** 1.65 + 0.004 * side
            + 0.008 * math.sin(2.0 * theta - 0.35)
            + 0.004 * math.sin(5.0 * theta + 0.6)
        )
        lower_z = (
            1.376 + 0.050 * side ** 1.70 - 0.010 * front ** 1.8
            + 0.006 * back + 0.007 * math.sin(3.0 * theta + 0.45)
            + 0.004 * math.sin(7.0 * theta - 0.2)
        )

        spread = (
            0.23 * smoothstep(t / 0.42)
            + 0.77 * smoothstep((t - 0.28) / 0.72)
        )
        lower_curl = smoothstep((t - 0.82) / 0.18)
        rx = 0.114 + (0.245 - 0.114) * spread - 0.014 * lower_curl
        ry = 0.087 + (0.181 - 0.087) * spread - 0.010 * lower_curl
        rx += 0.005 * math.sin(theta + 1.8 * t) * math.sin(math.pi * t)
        ry += 0.005 * math.sin(2.0 * theta - 1.1 * t) * math.sin(math.pi * t)

        # A continuous pair of wandering fold waves creates alternating soft
        # crests and tucks.  Their large angular phase shift prevents level,
        # concentric bands while retaining the gathered scarf read.
        fold_envelope = math.sin(math.pi * t) ** 1.05
        phase = 1.18 * math.sin(theta - 0.35) + 0.52 * math.sin(2.0 * theta + 0.55)
        main_fold = 3.8 * math.pi * t + phase
        fine_fold = 7.1 * math.pi * t - 0.72 * math.sin(3.0 * theta - 0.20)
        radial_fold = 0.016 * math.sin(main_fold) * fold_envelope
        radial_fold += 0.0055 * math.sin(fine_fold) * fold_envelope ** 1.35
        radial_fold += 0.0030 * math.sin(5.0 * theta - 1.5 * t) * fold_envelope ** 1.5

        center_x = 0.006 * math.sin(math.pi * t) * math.sin(1.6 * math.pi * t + 0.5)
        center_y = 0.010 + 0.006 * math.sin(math.pi * t) * math.cos(1.3 * math.pi * t)
        x = center_x + (rx + radial_fold) * c
        y = center_y + (ry + radial_fold) * s
        z_blend = smoothstep(t ** 0.90)
        z = top_z * (1.0 - z_blend) + lower_z * z_blend
        z += 0.007 * math.cos(main_fold + 0.45) * fold_envelope
        z += 0.004 * math.sin(5.0 * theta + 2.4 * t) * fold_envelope ** 1.4
        vertices.append((x, y, z))
        uv_values.append((4.0 * i / N_THETA, 1.2 * t))

for j in range(N_DRAPE - 1):
    for i in range(N_THETA):
        nxt = (i + 1) % N_THETA
        a = j * N_THETA + i
        b = j * N_THETA + nxt
        c = (j + 1) * N_THETA + nxt
        d = (j + 1) * N_THETA + i
        faces.append((a, b, c, d))

mesh = bpy.data.meshes.new("Mercenary_LooseWrappedScarf_v16zn_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new("Mercenary_LooseWrappedScarf_v16zn_LOD0", mesh)
collection.objects.link(cowl)
mesh.materials.append(material)
for poly in mesh.polygons:
    poly.use_smooth = True

# Cylindrical UVs preserve wool texel aspect; four repeats avoid stretching the
# 4K textile around the long circumference.
uv_layer = mesh.uv_layers.new(name="UVMap")
for poly in mesh.polygons:
    for loop_index in poly.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        i = vertex_index % N_THETA
        j = vertex_index // N_THETA
        u = 4.0 * i / N_THETA
        if i == 0 and any((mesh.loops[k].vertex_index % N_THETA) == N_THETA - 1 for k in poly.loop_indices):
            u = 4.0
        uv_layer.data[loop_index].uv = (u, 1.2 * j / (N_DRAPE - 1))

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl

solidify = cowl.modifiers.new("HeavyWoolThickness", "SOLIDIFY")
solidify.thickness = 0.008
solidify.offset = 0.0
solidify.use_even_offset = False
solidify.use_quality_normals = True
bpy.ops.object.modifier_apply(modifier=solidify.name)

# Dense longitudinal sampling and smooth normals preserve soft fold arcs.  No
# bevel/subdivision is applied to the cut rims, preventing a tube-like rolled
# border or concave miter spikes.
recalc_normals(cowl)

# Keep cowl density inside the character budget while retaining fold arcs.
raw_triangles = triangles(cowl)
target_triangles = 29_500
if raw_triangles > target_triangles:
    decimate = cowl.modifiers.new("V16ZN_GameReadyDecimate", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = target_triangles / raw_triangles
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)
recalc_normals(cowl)
for poly in cowl.data.polygons:
    poly.use_smooth = True

# Rigify deformation: spine dominates the neck and clavicle. The far lower
# shoulders receive a deliberately capped 28% upper-arm influence.
group_names = (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
    "DEF-upper_arm.L", "DEF-upper_arm.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
for vertex in cowl.data.vertices:
    x, y, z = vertex.co
    side = smoothstep((abs(x) - 0.175) / 0.090)
    low = smoothstep((1.515 - z) / 0.120)
    arm_weight = 0.28 * side * low
    upper = smoothstep((z - 1.500) / 0.075)
    mid = smoothstep((z - 1.370) / 0.105)
    spine_total = 1.0 - arm_weight
    w006 = spine_total * upper
    remaining = spine_total - w006
    w004 = remaining * (0.60 * (1.0 - mid) + 0.15 * mid)
    w005 = remaining - w004
    groups["DEF-spine.004"].add([vertex.index], w004, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], w005, "REPLACE")
    groups["DEF-spine.006"].add([vertex.index], w006, "REPLACE")
    if x >= 0.0:
        groups["DEF-upper_arm.L"].add([vertex.index], arm_weight, "REPLACE")
    else:
        groups["DEF-upper_arm.R"].add([vertex.index], arm_weight, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16ZN single asymmetric annular wool sheet with loose diagonal gathers and shoulder drape"

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
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.018, 0.020, 0.024, 1.0)
        background.inputs[1].default_value = 0.22
camera = scene.camera


def render(key, location, target, lens=84, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zn_loose_wrapped_scarf_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.015, 1.47), 85),
    "high_angle": render("high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.43), 86),
    "upper_three_quarter": render("upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.40), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "construction": "one continuous annular mid-surface plus applied solidify",
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "max_upper_arm_weight": max(
        sum(g.weight for g in vertex.groups if cowl.vertex_groups[g.group].name.startswith("DEF-upper_arm"))
        for vertex in cowl.data.vertices
    ),
    "cowl_bounds": {
        "min": [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    "total_triangles": total_triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
cowl["v16zn_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZN_REPORT=" + json.dumps(report, sort_keys=True))
