"""Minimal v16 candidate: retain the original three sculpted cowl shells.

The flat/torus repair helpers are retired.  Every face of the original cowl is
assigned one tiled neutral-charcoal wool PBR, eliminating the projection and
patchwork material seams that made the top look fragmented.  Production files
are untouched; this writes only a versioned candidate and diagnostics.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16_minimal_cowl_yoke5_gambeson_candidate.blend"
REPORT = STAGING / "v16_minimal_cowl_yoke5_gambeson_report.json"

RETIRED = (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
cloth = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
gambeson = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]
asset_collection = cowl.users_collection[0]

# One consistent tiled wool material across all three closed sculpted shells.
cowl.data.materials.clear()
cowl.data.materials.append(cloth)
for polygon in cowl.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
cowl["source"] = "V16 minimal: original three sculpted shells, unified tiled wool"
cowl["v16_material_strategy"] = "single neutral-charcoal wool PBR; no projection slots"

retired = []
for name in RETIRED:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.hide_render = True
    obj.hide_viewport = True
    obj.hide_set(True)
    obj["retired_by_v16_minimal_cowl"] = True
    obj["part_category_before_retirement"] = obj.get("part_category")
    if "part_category" in obj:
        del obj["part_category"]
    obj["game_asset"] = False
    retired.append(name)


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def recalc_outside(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


# A single low gambeson underlayer closes only the donor shoulder/rear voids.
# It remains below the three visible cowl shells, slopes down toward its hem,
# and uses the same quilted material as the sleeves so it cannot read as a new
# floating cape, collar ring, or armour plate.
ANGULAR_SEGMENTS = 96
RADIAL_SEGMENTS = 12
THICKNESS = 0.010
vertices = []
parameters = []

for surface in (0, 1):
    for radial_index in range(RADIAL_SEGMENTS + 1):
        v = radial_index / RADIAL_SEGMENTS
        eased = smoothstep(v)
        rx = 0.125 * (1.0 - eased) + 0.340 * eased
        # The closure expands mainly rearward.  Its outer front edge stays at
        # y~=0 behind the chest/sleeves, so it cannot appear as a front plate.
        ry = 0.090 * (1.0 - eased) + 0.095 * eased
        center_y = 0.015 * (1.0 - eased) + 0.095 * eased
        for angular_index in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
            cosine = math.cos(theta)
            sine = math.sin(theta)
            side = abs(cosine)
            back = max(0.0, sine)
            x = rx * cosine
            y = center_y + ry * sine
            inner_z = 1.445 + 0.006 * back
            outer_z = 1.397 + 0.023 * side ** 1.7 + 0.008 * back
            z = inner_z * (1.0 - eased) + outer_z * eased
            # Millimetric quilt settlement, not visible radial rolls.
            z += 0.0022 * math.sin(4.0 * theta + 0.5) * math.sin(math.pi * v) ** 2
            if surface == 1:
                z -= THICKNESS
            vertices.append((x, y, z))
            parameters.append((surface, radial_index, angular_index, v, theta))

RING = ANGULAR_SEGMENTS
SURFACE_SIZE = (RADIAL_SEGMENTS + 1) * RING
faces = []
for radial_index in range(RADIAL_SEGMENTS):
    for angular_index in range(ANGULAR_SEGMENTS):
        nxt = (angular_index + 1) % ANGULAR_SEGMENTS
        a = radial_index * RING + angular_index
        b = (radial_index + 1) * RING + angular_index
        c = (radial_index + 1) * RING + nxt
        d = radial_index * RING + nxt
        faces.append((a, b, c, d))
        faces.append((SURFACE_SIZE + d, SURFACE_SIZE + c, SURFACE_SIZE + b, SURFACE_SIZE + a))

outer_start = RADIAL_SEGMENTS * RING
for angular_index in range(ANGULAR_SEGMENTS):
    nxt = (angular_index + 1) % ANGULAR_SEGMENTS
    faces.append((
        outer_start + angular_index,
        SURFACE_SIZE + outer_start + angular_index,
        SURFACE_SIZE + outer_start + nxt,
        outer_start + nxt,
    ))
    faces.append((
        angular_index,
        nxt,
        SURFACE_SIZE + nxt,
        SURFACE_SIZE + angular_index,
    ))

yoke_mesh = bpy.data.meshes.new("Mercenary_HiddenGambesonSeamClosure_LOD0_Mesh")
yoke_mesh.from_pydata(vertices, [], faces)
yoke_mesh.update()
recalc_outside(yoke_mesh)
yoke = bpy.data.objects.new("Mercenary_HiddenGambesonSeamClosure_LOD0", yoke_mesh)
asset_collection.objects.link(yoke)
yoke_mesh.materials.append(gambeson)
yoke["game_asset"] = True
yoke["part_category"] = "ClothedBody"
yoke["intentional_underlayer"] = True
yoke["source"] = "V16 compact low gambeson seam closure hidden below original three-shell cowl"

yoke_uv = yoke_mesh.uv_layers.new(name="UVMap")
for polygon in yoke_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = yoke_mesh.vertices[yoke_mesh.loops[loop_index].vertex_index].co
        yoke_uv.data[loop_index].uv = (0.5 + co.x * 2.2, 0.5 + (co.y - 0.04) * 2.2)

spine_upper = yoke.vertex_groups.new(name="DEF-spine.005")
spine_chest = yoke.vertex_groups.new(name="DEF-spine.004")
left_arm = yoke.vertex_groups.new(name="DEF-upper_arm.L")
right_arm = yoke.vertex_groups.new(name="DEF-upper_arm.R")
yoke_weight_sums = []
for vertex, (_surface, _r, _a, v, _theta) in zip(yoke_mesh.vertices, parameters):
    arm_weight = 0.28 * smoothstep((abs(vertex.co.x) - 0.235) / 0.125) * smoothstep((v - 0.55) / 0.45)
    torso_weight = 1.0 - arm_weight
    upper_share = torso_weight * (1.0 - 0.58 * smoothstep(v))
    chest_share = torso_weight - upper_share
    spine_upper.add([vertex.index], upper_share, "REPLACE")
    spine_chest.add([vertex.index], chest_share, "REPLACE")
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, "REPLACE")
    yoke_weight_sums.append(upper_share + chest_share + arm_weight)

yoke_armature = yoke.modifiers.new("RigifyDeform", "ARMATURE")
yoke_armature.object = rig
yoke_armature.use_deform_preserve_volume = True
yoke.parent = rig
yoke.matrix_parent_inverse = rig.matrix_world.inverted()


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def component_count(obj):
    adjacency = defaultdict(set)
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    count = 0
    while unseen:
        count += 1
        stack = [unseen.pop()]
        while stack:
            current = stack.pop()
            connected = adjacency[current] & unseen
            unseen.difference_update(connected)
            stack.extend(connected)
    return count


def weight_sum_range(obj):
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return min(sums), max(sums)


stats = manifold_stats(cowl)
components = component_count(cowl)
weight_range = weight_sum_range(cowl)
has_rig = any(mod.type == "ARMATURE" and mod.object == rig for mod in cowl.modifiers)
yoke_stats = manifold_stats(yoke)
yoke_weight_range = (min(yoke_weight_sums), max(yoke_weight_sums))
yoke_has_rig = any(mod.type == "ARMATURE" and mod.object == rig for mod in yoke.modifiers)
if stats["nonmanifold_edges"] != 0:
    raise RuntimeError(f"Original cowl shells are not closed: {stats}")
if components != 3:
    raise RuntimeError(f"Expected the original three sculpted components, got {components}")
if weight_range[0] < 0.999 or weight_range[1] > 1.001 or not has_rig:
    raise RuntimeError(f"Cowl Rigify validation failed: weights={weight_range}, rig={has_rig}")
if yoke_stats["nonmanifold_edges"] != 0:
    raise RuntimeError(f"Hidden yoke is not closed: {yoke_stats}")
if yoke_weight_range[0] < 0.999 or yoke_weight_range[1] > 1.001 or not yoke_has_rig:
    raise RuntimeError(f"Hidden yoke Rigify validation failed: weights={yoke_weight_range}, rig={yoke_has_rig}")

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f"diagnostic_v16_minimal_cowl_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {}
previews["top_close"] = render(
    "top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49),
    ortho_scale=0.95, resolution=(1200, 900),
)
previews["failure_view"] = render(
    "failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02),
    lens=78, resolution=(1400, 1000),
)
previews["front"] = render(
    "front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06,
)
previews["back"] = render(
    "back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06,
)
previews["three_quarter"] = render(
    "three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72,
)
previews["upper_three_quarter"] = render(
    "upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49),
    lens=76, resolution=(1200, 1000),
)

report = {
    "source": str(SOURCE),
    "candidate_blend": str(OUTPUT),
    "visible_cowl": cowl.name,
    "retired_helpers": retired,
    "cowl_components": components,
    "cowl_vertices": len(cowl.data.vertices),
    "cowl_triangles": triangle_count(cowl),
    "cowl_materials": [material.name for material in cowl.data.materials],
    "cowl_manifold": stats,
    "cowl_weight_sum_range": list(weight_range),
    "cowl_has_rigify_modifier": has_rig,
    "hidden_yoke": yoke.name,
    "hidden_yoke_vertices": len(yoke_mesh.vertices),
    "hidden_yoke_triangles": triangle_count(yoke),
    "hidden_yoke_manifold": yoke_stats,
    "hidden_yoke_weight_sum_range": list(yoke_weight_range),
    "hidden_yoke_has_rigify_modifier": yoke_has_rig,
    "character_meshes": len(character_meshes),
    "character_triangles": total_triangles,
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = "PERSP"
camera.data.lens = 76
camera.location = (1.15, -1.55, 2.05)
look_at(camera, (0.0, 0.0, 1.49))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V16_MINIMAL_COWL_COMPONENTS", components)
print("V16_MINIMAL_COWL_MANIFOLD", stats)
print("V16_MINIMAL_COWL_WEIGHT_RANGE", weight_range)
print("V16_MINIMAL_COWL_MATERIAL", cowl.data.materials[0].name)
print("V16_HIDDEN_YOKE_MANIFOLD", yoke_stats)
print("V16_HIDDEN_YOKE_WEIGHT_RANGE", yoke_weight_range)
print("V16_HIDDEN_YOKE_TRIANGLES", triangle_count(yoke))
print("V16_MINIMAL_CHARACTER_TRIANGLES", total_triangles)
print("WROTE", OUTPUT)
print("WROTE", REPORT)
