"""Build a clean, single-piece medieval wool cowl for v16.

The replacement is one closed annular cloth sheet.  It rises softly behind
the neck, falls over the clavicles and shoulder roots, and uses diagonal
pleats instead of concentric tube-like rings.  This is an isolated candidate:
production GLBs and the interactive viewer are not touched.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zp_natural_draped_cowl.blend"
REPORT = STAGING / "v16zp_natural_draped_cowl_report.json"

OLD_COWL = "Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"
NEW_COWL = "Mercenary_NaturalDrapedCowl_v16zp_LOD0"


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
        vertices = list(poly.vertices)
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
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


def recalc_outside(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
old_cowl = bpy.data.objects[OLD_COWL]
asset_collection = donor.users_collection[0]

# Preserve the proven 4K wool shader, then remove the old ring-like geometry.
material = old_cowl.data.materials[0].copy()
material.name = "MAT_Cowl_NaturalCharcoalWool_v16zp_4K"
old_data = old_cowl.data
bpy.data.objects.remove(old_cowl, do_unlink=True)
if old_data.users == 0:
    bpy.data.meshes.remove(old_data)

# The new cowl overlaps this entire zone.  Removing the remaining torn scan
# collar prevents its sharp silhouette from reappearing at grazing angles.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    if abs(center.x) < 0.475 and center.z > 1.345:
        remove_faces.append(face)
removed_donor_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zp_removed_hidden_torn_upper_faces"] = removed_donor_faces


# One compact annular sheet with a single neckline opening.  Its dominant
# creases travel diagonally from the neck to the hem, not around the neck.
ANG = 192
ROWS = 42
THICKNESS = 0.009
vertices = []
parameters = []


def surface_point(theta, u):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)

    eased = smoothstep(u)

    # Compact neckline; the back sits a little farther from the neck like a
    # real loose cowl.  The hem spreads over shoulder roots and clavicles.
    inner_rx = 0.119 + 0.004 * math.sin(3.0 * theta + 0.35)
    inner_ry = 0.099 + 0.007 * back + 0.003 * math.sin(2.0 * theta - 0.50)
    outer_rx = (
        0.318
        + 0.019 * left
        - 0.006 * right
        + 0.008 * math.sin(3.0 * theta + 0.40)
    )
    outer_ry = (
        0.202
        + 0.047 * front
        + 0.033 * back
        + 0.008 * math.sin(2.0 * theta - 0.35)
    )

    # Most of the widening happens close to the shoulders.  A small broken
    # roll near the neckline provides cloth volume without making a tube.
    spread = smoothstep(u ** 1.12)
    neck_roll = math.exp(-0.5 * ((u - 0.16) / 0.095) ** 2)
    neck_roll *= 0.35 + 0.50 * back + 0.30 * left
    rx = inner_rx * (1.0 - spread) + outer_rx * spread
    ry = inner_ry * (1.0 - spread) + outer_ry * spread
    rx += 0.012 * neck_roll
    ry += 0.010 * neck_roll

    center_x = -0.005 * eased + 0.004 * math.sin(theta + 0.5) * eased
    center_y = 0.010 + 0.014 * eased + 0.004 * math.sin(2.0 * theta - 0.3) * eased

    # Irregular hem, broad enough to hide the scan seam but not a flat disc.
    hem_warp = eased ** 1.6 * (
        0.018 * math.sin(3.0 * theta + 0.20)
        + 0.010 * math.sin(7.0 * theta - 0.80)
    )
    x = center_x + rx * (1.0 + hem_warp) * c
    y = center_y + ry * (1.0 + 0.75 * hem_warp) * s

    inner_z = (
        1.535
        + 0.052 * back ** 1.35
        - 0.016 * front
        + 0.008 * left
        - 0.003 * right
        + 0.004 * math.sin(2.0 * theta + 0.25)
    )
    # U-shaped fall over the chest/back; shoulder edges remain higher.
    outer_z = (
        1.397
        + 0.046 * side ** 1.45
        - 0.092 * front ** 1.60
        - 0.056 * back ** 1.35
        - 0.006 * left
        + 0.006 * math.sin(5.0 * theta + 0.45)
    )
    z = inner_z * (1.0 - eased) + outer_z * eased

    # One broken neckline roll and six long diagonal cloth folds.  Each fold
    # has a neighbouring valley, giving a real crease rather than an embossed
    # stripe or another concentric ring.
    z += 0.014 * neck_roll
    radial_bulge = math.sin(math.pi * u) ** 1.25
    fold_specs = (
        (1.42 * math.pi, +0.62, 0.24, 0.026, 0.015),
        (1.72 * math.pi, -0.44, 0.19, 0.018, 0.010),
        (0.56 * math.pi, +0.48, 0.23, 0.022, 0.012),
        (0.88 * math.pi, -0.55, 0.20, 0.018, 0.010),
        (0.10 * math.pi, +0.36, 0.18, 0.014, 0.008),
        (1.08 * math.pi, -0.32, 0.17, 0.013, 0.007),
    )
    for base, slope, sigma, height, outward in fold_specs:
        center = base + slope * (u - 0.46)
        crest = ridge(theta, center, sigma)
        valley = ridge(theta, center + 1.35 * sigma, 0.70 * sigma)
        fold = radial_bulge * (crest - 0.66 * valley)
        z += height * fold
        x += outward * fold * c
        y += outward * fold * s

    # Low-amplitude cross-grain breakup; deliberately too small to form rows.
    z += radial_bulge * (
        0.0040 * math.sin(3.0 * theta + 5.2 * u)
        + 0.0022 * math.sin(7.0 * theta - 3.4 * u)
    )
    return x, y, z


for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANG):
            theta = math.tau * angular / ANG
            x, y, z = surface_point(theta, u)
            if surface == 1:
                z -= THICKNESS
            vertices.append((x, y, z))
            parameters.append((surface, row, angular, u, theta))

surface_size = ANG * ROWS
faces = []
for row in range(ROWS - 1):
    for angular in range(ANG):
        nxt = (angular + 1) % ANG
        a = row * ANG + angular
        b = (row + 1) * ANG + angular
        c = (row + 1) * ANG + nxt
        d = row * ANG + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c,
                      surface_size + b, surface_size + a))

outer = (ROWS - 1) * ANG
for angular in range(ANG):
    nxt = (angular + 1) % ANG
    faces.append((angular, nxt, surface_size + nxt, surface_size + angular))
    faces.append((outer + angular, surface_size + outer + angular,
                  surface_size + outer + nxt, outer + nxt))

mesh = bpy.data.meshes.new("Mercenary_NaturalDrapedCowl_v16zp_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
cowl = bpy.data.objects.new(NEW_COWL, mesh)
asset_collection.objects.link(cowl)
mesh.materials.append(material)
for poly in mesh.polygons:
    poly.use_smooth = True

# Predictable tiled UVs preserve the existing 4K woven-wool maps.
uv = mesh.uv_layers.new(name="UVMap")
for poly in mesh.polygons:
    for loop_index in poly.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        _surface, _row, angular, u, _theta = parameters[vertex_index]
        uv.data[loop_index].uv = (angular / ANG * 3.0, u * 1.75)

# Rigify-compatible normalized weights.
group_names = (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
    "DEF-shoulder.L", "DEF-shoulder.R",
    "DEF-upper_arm.L", "DEF-upper_arm.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
for vertex, (_surface, _row, _angular, u, _theta) in zip(mesh.vertices, parameters):
    x, _y, _z = vertex.co
    side = smoothstep((abs(x) - 0.205) / 0.120)
    hem = smoothstep((u - 0.56) / 0.44)
    arm = 0.10 * side * hem
    shoulder = 0.28 * side * hem
    torso = 1.0 - arm - shoulder
    neck_share = torso * (0.68 * (1.0 - smoothstep(u / 0.72)) + 0.08)
    chest_share = torso * (0.18 + 0.45 * smoothstep((u - 0.30) / 0.70))
    upper_share = max(0.0, torso - neck_share - chest_share)
    total = neck_share + chest_share + upper_share + shoulder + arm
    weights = {
        "DEF-spine.004": chest_share / total,
        "DEF-spine.005": upper_share / total,
        "DEF-spine.006": neck_share / total,
        "DEF-shoulder.L": shoulder / total if x >= 0.0 else 0.0,
        "DEF-shoulder.R": shoulder / total if x < 0.0 else 0.0,
        "DEF-upper_arm.L": arm / total if x >= 0.0 else 0.0,
        "DEF-upper_arm.R": arm / total if x < 0.0 else 0.0,
    }
    for name, weight in weights.items():
        if weight > 0.0:
            groups[name].add([vertex.index], weight, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16ZP one-piece natural shoulder-draped medieval wool cowl"
cowl["single_neck_opening"] = True
cowl["no_concentric_rings"] = True

# Validation before saving or rendering.
bad_edges, components = topology(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in mesh.vertices]
if bad_edges or components != 1:
    raise RuntimeError(f"Cowl topology failed: {bad_edges=}, {components=}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights failed: {min(weight_sums)}..{max(weight_sums)}")

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
    path = PREVIEWS / f"diagnostic_v16zp_natural_draped_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
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
total_triangles = sum(triangles(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "removed_hidden_donor_faces": removed_donor_faces,
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "deform_bones": sum(bone.use_deform for bone in rig.data.bones),
    "previews": previews,
}
cowl["v16zp_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZP_REPORT=" + json.dumps(report, sort_keys=True))
