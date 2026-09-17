"""Build an organic, flattened cowl candidate on top of the v16j hair scene.

This is a visual candidate only.  It replaces the six round collar/cowl shells
with three broad, irregular cloth ribbons and a low hidden gambeson closure.
The canonical Godot and web-viewer assets are deliberately untouched.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16l_soft_loop_cowl_candidate.blend"
REPORT = STAGING / "v16l_soft_loop_cowl_report.json"

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
asset_collection = donor.users_collection[0]
cowl_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]

for name in OLD_UPPER:
    old = bpy.data.objects.get(name)
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def recalc_outside(mesh: bpy.types.Mesh) -> None:
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def assign_rig_weights(obj: bpy.types.Object, mode: str) -> None:
    spine_4 = obj.vertex_groups.new(name="DEF-spine.004")
    spine_5 = obj.vertex_groups.new(name="DEF-spine.005")
    spine_6 = obj.vertex_groups.new(name="DEF-spine.006")
    arm_l = obj.vertex_groups.new(name="DEF-upper_arm.L")
    arm_r = obj.vertex_groups.new(name="DEF-upper_arm.R")
    for vertex in obj.data.vertices:
        x, _y, z = vertex.co
        if mode == "cowl":
            neck = smoothstep((z - 1.48) / 0.09)
            chest = (1.0 - neck) * 0.34
            upper = (1.0 - neck) - chest
            head = neck
            arm = 0.22 * smoothstep((abs(x) - 0.24) / 0.11) * (1.0 - neck)
        else:
            head = 0.0
            arm = 0.28 * smoothstep((abs(x) - 0.235) / 0.105)
            upper = (1.0 - arm) * 0.56
            chest = (1.0 - arm) - upper
        torso_scale = 1.0 - arm
        if mode == "cowl":
            chest *= torso_scale
            upper *= torso_scale
            head *= torso_scale
        if chest:
            spine_4.add([vertex.index], chest, "REPLACE")
        if upper:
            spine_5.add([vertex.index], upper, "REPLACE")
        if head:
            spine_6.add([vertex.index], head, "REPLACE")
        if arm:
            (arm_l if x >= 0.0 else arm_r).add([vertex.index], arm, "REPLACE")

    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


# Each entry describes one casually wound length of heavy cloth.  The section
# is a soft, flattened oval (wide radially, shallow vertically), not a round
# hose.  Different center offsets, drape and Fourier phases keep the three
# folds from forming mechanically concentric rings.
BANDS = (
    {
        "radius": (0.158, 0.104),
        "section": (0.039, 0.024),
        "z": 1.548,
        "phase": 0.35,
        "center": (-0.007, 0.002),
        "front_sag": 0.010,
    },
    {
        "radius": (0.205, 0.132),
        "section": (0.047, 0.027),
        "z": 1.493,
        "phase": 2.15,
        "center": (0.007, 0.008),
        "front_sag": 0.014,
    },
    {
        "radius": (0.265, 0.166),
        "section": (0.052, 0.029),
        "z": 1.438,
        "phase": 4.20,
        "center": (-0.004, 0.015),
        "front_sag": 0.018,
    },
)
ANGULAR_SEGMENTS = 176
CROSS_SEGMENTS = 20
vertices = []
faces = []

for band_index, band in enumerate(BANDS):
    band_start = len(vertices)
    for angular_index in range(ANGULAR_SEGMENTS):
        theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
        cosine = math.cos(theta)
        sine = math.sin(theta)
        front = max(0.0, -sine)
        back = max(0.0, sine)
        radial_noise = (
            0.0090 * math.sin(3.0 * theta + band["phase"])
            + 0.0040 * math.sin(7.0 * theta - 0.45 * band["phase"])
            + 0.0020 * math.cos(11.0 * theta + 0.8)
        )
        rx = band["radius"][0] + radial_noise
        ry = band["radius"][1] + radial_noise * 0.58
        center_x = band["center"][0] + rx * cosine
        center_y = band["center"][1] + ry * sine
        center_z = (
            band["z"]
            - band["front_sag"] * front
            + 0.004 * back
            + 0.0080 * math.sin(2.0 * theta + band["phase"])
            + 0.0035 * math.sin(5.0 * theta - 0.6)
        )
        # Outward radial direction of the ellipse, normalized in XY.
        radial = Vector((cosine / max(rx, 1.0e-6), sine / max(ry, 1.0e-6), 0.0)).normalized()
        section_depth = band["section"][0] * (
            1.0 + 0.13 * math.sin(4.0 * theta + band["phase"])
        )
        section_height = band["section"][1] * (
            1.0 + 0.16 * math.sin(3.0 * theta - 0.7 * band["phase"])
        )
        for cross_index in range(CROSS_SEGMENTS):
            phi = 2.0 * math.pi * cross_index / CROSS_SEGMENTS
            # A little harmonic asymmetry makes the fold look compressed and
            # creased instead of like a mathematically perfect ellipse.
            radial_offset = section_depth * math.cos(phi)
            radial_offset *= 1.0 + 0.08 * math.sin(3.0 * phi + theta)
            vertical_offset = section_height * math.sin(phi)
            vertical_offset += 0.0022 * math.sin(2.0 * phi - 3.0 * theta + band["phase"])
            vertices.append((
                center_x + radial.x * radial_offset,
                center_y + radial.y * radial_offset,
                center_z + vertical_offset,
            ))

    for angular_index in range(ANGULAR_SEGMENTS):
        next_angular = (angular_index + 1) % ANGULAR_SEGMENTS
        for cross_index in range(CROSS_SEGMENTS):
            next_cross = (cross_index + 1) % CROSS_SEGMENTS
            a = band_start + angular_index * CROSS_SEGMENTS + cross_index
            b = band_start + next_angular * CROSS_SEGMENTS + cross_index
            c = band_start + next_angular * CROSS_SEGMENTS + next_cross
            d = band_start + angular_index * CROSS_SEGMENTS + next_cross
            faces.append((a, b, c, d))

cowl_mesh = bpy.data.meshes.new("Mercenary_SoftLoopCowl_LOD0_Mesh")
cowl_mesh.from_pydata(vertices, [], faces)
cowl_mesh.update()
recalc_outside(cowl_mesh)
cowl = bpy.data.objects.new("Mercenary_SoftLoopCowl_LOD0", cowl_mesh)
asset_collection.objects.link(cowl)
cowl_mesh.materials.append(cowl_material)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16 three asymmetric soft cloth loops with flattened creased sections"
cowl["intentional_layer"] = True

for polygon in cowl_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv_layer = cowl_mesh.uv_layers.new(name="UVMap")
for polygon in cowl_mesh.polygons:
    normal = polygon.normal
    for loop_index in polygon.loop_indices:
        co = cowl_mesh.vertices[cowl_mesh.loops[loop_index].vertex_index].co
        theta = math.atan2(co.y, co.x) / (2.0 * math.pi) + 0.5
        uv_layer.data[loop_index].uv = (theta * 2.5, (co.z - 1.35) * 8.0)
assign_rig_weights(cowl, "cowl")


# A low, closed underlayer fills the real donor shoulder/neck opening but stays
# beneath the visible scarf.  It is sloped down at the outer edge so it cannot
# read as a hovering plate in front or side views.
YOKE_ANGULAR = 128
YOKE_RADIAL = 10
YOKE_THICKNESS = 0.009
yoke_vertices = []
for surface in (0, 1):
    for radial_index in range(YOKE_RADIAL + 1):
        v = radial_index / YOKE_RADIAL
        eased = smoothstep(v)
        rx = 0.120 * (1.0 - eased) + 0.338 * eased
        ry = 0.087 * (1.0 - eased) + 0.102 * eased
        center_y = 0.012 * (1.0 - eased) + 0.092 * eased
        for angular_index in range(YOKE_ANGULAR):
            theta = 2.0 * math.pi * angular_index / YOKE_ANGULAR
            cosine = math.cos(theta)
            sine = math.sin(theta)
            side = abs(cosine)
            back = max(0.0, sine)
            x = rx * cosine
            y = center_y + ry * sine
            z_inner = 1.446 + 0.004 * back
            z_outer = 1.396 + 0.022 * side ** 1.7 + 0.006 * back
            z = z_inner * (1.0 - eased) + z_outer * eased
            z += 0.0018 * math.sin(4.0 * theta + 0.3) * math.sin(math.pi * v) ** 2
            if surface == 1:
                z -= YOKE_THICKNESS
            yoke_vertices.append((x, y, z))

yoke_faces = []
yoke_surface = (YOKE_RADIAL + 1) * YOKE_ANGULAR
for radial_index in range(YOKE_RADIAL):
    for angular_index in range(YOKE_ANGULAR):
        nxt = (angular_index + 1) % YOKE_ANGULAR
        a = radial_index * YOKE_ANGULAR + angular_index
        b = (radial_index + 1) * YOKE_ANGULAR + angular_index
        c = (radial_index + 1) * YOKE_ANGULAR + nxt
        d = radial_index * YOKE_ANGULAR + nxt
        yoke_faces.append((a, b, c, d))
        yoke_faces.append((yoke_surface + d, yoke_surface + c,
                           yoke_surface + b, yoke_surface + a))
outer_start = YOKE_RADIAL * YOKE_ANGULAR
for angular_index in range(YOKE_ANGULAR):
    nxt = (angular_index + 1) % YOKE_ANGULAR
    yoke_faces.append((outer_start + angular_index,
                       yoke_surface + outer_start + angular_index,
                       yoke_surface + outer_start + nxt,
                       outer_start + nxt))
    yoke_faces.append((angular_index, nxt, yoke_surface + nxt,
                       yoke_surface + angular_index))

yoke_mesh = bpy.data.meshes.new("Mercenary_HiddenGambesonSeamClosure_LOD0_Mesh")
yoke_mesh.from_pydata(yoke_vertices, [], yoke_faces)
yoke_mesh.update()
recalc_outside(yoke_mesh)
yoke = bpy.data.objects.new("Mercenary_HiddenGambesonSeamClosure_LOD0", yoke_mesh)
asset_collection.objects.link(yoke)
yoke_mesh.materials.append(gambeson_material)
yoke["game_asset"] = True
yoke["part_category"] = "ClothedBody"
yoke["intentional_underlayer"] = True
yoke["source"] = "V16 low hidden gambeson closure beneath draped cowl"
for polygon in yoke_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
yoke_uv = yoke_mesh.uv_layers.new(name="UVMap")
for polygon in yoke_mesh.polygons:
    for loop_index in polygon.loop_indices:
        co = yoke_mesh.vertices[yoke_mesh.loops[loop_index].vertex_index].co
        yoke_uv.data[loop_index].uv = (0.5 + co.x * 2.2, 0.5 + (co.y - 0.04) * 2.2)
assign_rig_weights(yoke, "yoke")


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj: bpy.types.Object) -> dict[str, int]:
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def component_count(obj: bpy.types.Object) -> int:
    adjacency = defaultdict(set)
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            current = stack.pop()
            linked = adjacency[current] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return components


def weight_sum_range(obj: bpy.types.Object) -> tuple[float, float]:
    values = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return min(values), max(values)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True

for obj in scene.objects:
    if obj.type == "MESH" and obj.get("part_category") is not None:
        for material in obj.data.materials:
            if material is not None:
                material.use_backface_culling = False

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
previews = {}


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
    output = PREVIEWS / f"diagnostic_v16l_soft_loop_cowl_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    previews[key] = str(output)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49), lens=76, resolution=(1200, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back_head", (0.0, 1.55, 1.83), (0.0, 0.015, 1.67), lens=82, resolution=(1100, 1000))

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
cowl_stats = manifold_stats(cowl)
yoke_stats = manifold_stats(yoke)
cowl_weights = weight_sum_range(cowl)
yoke_weights = weight_sum_range(yoke)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Unexpected deform bone count: {deform_bones}")
if cowl_stats["nonmanifold_edges"] or yoke_stats["nonmanifold_edges"]:
    raise RuntimeError(f"Open cowl/closure: {cowl_stats}, {yoke_stats}")
if cowl_weights[0] < 0.999 or cowl_weights[1] > 1.001:
    raise RuntimeError(f"Cowl weight sums invalid: {cowl_weights}")
if yoke_weights[0] < 0.999 or yoke_weights[1] > 1.001:
    raise RuntimeError(f"Yoke weight sums invalid: {yoke_weights}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "character_meshes": len(character_meshes),
    "character_triangles": total_triangles,
    "deform_bones": deform_bones,
    "cowl_object": cowl.name,
    "cowl_components": component_count(cowl),
    "cowl_triangles": triangle_count(cowl),
    "cowl_manifold": cowl_stats,
    "cowl_weight_sum_range": list(cowl_weights),
    "closure_object": yoke.name,
    "closure_triangles": triangle_count(yoke),
    "closure_manifold": yoke_stats,
    "closure_weight_sum_range": list(yoke_weights),
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

print("V16L_CHARACTER_TRIANGLES", total_triangles)
print("V16L_CHARACTER_MESHES", len(character_meshes))
print("V16L_COWL_TRIANGLES", triangle_count(cowl))
print("V16L_COWL_COMPONENTS", component_count(cowl))
print("V16L_COWL_MANIFOLD", cowl_stats)
print("V16L_COWL_WEIGHT_RANGE", cowl_weights)
print("V16L_CLOSURE_MANIFOLD", yoke_stats)
print("V16L_CLOSURE_WEIGHT_RANGE", yoke_weights)
print("WROTE", OUTPUT)
print("WROTE", REPORT)
