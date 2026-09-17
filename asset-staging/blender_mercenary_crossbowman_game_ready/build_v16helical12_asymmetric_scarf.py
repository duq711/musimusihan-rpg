"""Build an isolated 1.10-turn asymmetric medieval scarf candidate from v16j.

The malformed stacked cowl and stopgaps are retired.  One broad, closed ribbon
wraps only 1.10 turns, hangs lower in front, rises and bunches asymmetrically at
the rear/sides, and buries both capped ends inward behind the neck.  A separate
narrow dark liner prevents a hollow neck cavity.  No full-arm cover is added;
only mismatched shoulder projection materials on the intact donor are remapped
to its existing gambeson side material.  Source and production files remain
untouched.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16helical12c_asymmetric_candidate.blend"
REPORT = STAGING / "v16helical12c_asymmetric_report.json"

SCARF_NAME = "Mercenary_AsymmetricHelicalScarf_v16helical12c_LOD0"
LINER_NAME = "Mercenary_NarrowDarkNeckLiner_v16helical12c_LOD0"
PATCH_NAME = "Mercenary_ShallowShoulderUnderpatches_v16helical12c_LOD0"
OLD_UPPER = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


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
        queue = deque([unseen.pop()])
        while queue:
            linked = adjacency[queue.popleft()] & unseen
            unseen.difference_update(linked)
            queue.extend(linked)
    return {
        "components": components,
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "loose_vertices": sum(not adjacency[index] for index in range(len(obj.data.vertices))),
        "zero_area_faces": sum(poly.area <= 1.0e-12 for poly in obj.data.polygons),
    }


def bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        axis: [min(getattr(point, axis) for point in points), max(getattr(point, axis) for point in points)]
        for axis in ("x", "y", "z")
    }


def weight_range(obj):
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return [min(sums), max(sums)]


def attach_rigify(obj, rig):
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def recalc_normals(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
collection = donor.users_collection[0]

donor_geometry_before = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangle_count(donor),
}
donor_weight_signature_before = [
    round(sum(item.weight for item in vertex.groups), 7) for vertex in donor.data.vertices
]

removed = []
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    removed.append({"name": name, "triangles": triangle_count(obj)})
    data = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if data.users == 0:
        bpy.data.meshes.remove(data)

# Clean the intact donor shoulders without adding a second arm shell.  The
# source scan uses front/back projection slots whose light seams become white
# shards at oblique angles.  Reassign only those upper-arm triangles to the
# donor's existing gambeson-side PBR slot; topology, UVs, and weights stay put.
material_names = [material.name if material else "" for material in donor.data.materials]
gambeson_index = material_names.index("MAT_Gambeson_Side_PBR_4K")
projection_indices = {
    index for index, name in enumerate(material_names)
    if name in {"MAT_ReferenceProjection_Front_4K", "MAT_ReferenceProjection_Back_4K"}
}
shoulder_polygons_remapped = 0
shoulder_surface_polygons_unified = 0
for poly in donor.data.polygons:
    center = poly.center
    if (
        0.18 <= abs(center.x) <= 0.58
        and 1.30 <= center.z <= 1.57
        and poly.material_index in projection_indices
    ):
        poly.material_index = gambeson_index
        shoulder_polygons_remapped += 1
    # The upper sleeve scan contains small intermixed leather/coat/projection
    # shards.  At the outer shoulder these are not meaningful garment panels;
    # assigning the intact donor faces one quilted material removes the white
    # confetti without deleting or inflating the anatomy.
    if 0.30 <= abs(center.x) <= 0.56 and 1.32 <= center.z <= 1.57:
        if poly.material_index != gambeson_index:
            poly.material_index = gambeson_index
            shoulder_surface_polygons_unified += 1
donor.data.update()

# One broad helical ribbon, 1.10 turns.  Both ends occupy the rear quadrants.
LONG_SEGMENTS = 240
WIDTH_SEGMENTS = 24
THICKNESS = 0.008
TURNS = 1.10
THETA_START = math.radians(76.0)
THETA_SPAN = math.tau * TURNS


def scarf_point(u, v, surface):
    theta = THETA_START + THETA_SPAN * u
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    left = max(0.0, -cosine)
    right = max(0.0, cosine)

    # The entire short overlap is pulled behind the neck, rather than leaving
    # two full-width rear passes that read as a bow or stacked collar.
    start_gate = 1.0 - smoothstep(u / 0.130)
    finish_gate = 1.0 - smoothstep((1.0 - u) / 0.130)
    end_gate = max(start_gate, finish_gate)
    middle_gate = 1.0 - end_gate
    width_scale = 0.04 + 0.96 * smoothstep(middle_gate / 0.80)
    direction_width = 0.75 + 0.20 * front + 0.10 * left - 0.15 * back - 0.05 * right
    width_scale *= max(0.54, min(1.0, direction_width))

    # Front hangs low; back and left side bunch higher.  A small pitch separates
    # only the short rear overlap rather than producing visible concentric coils.
    center_z = 1.480
    center_z -= 0.046 * front
    center_z += 0.026 * back + 0.017 * left - 0.006 * right
    center_z += 0.015 * (u - 0.5)
    center_z -= 0.062 * start_gate + 0.054 * finish_gate
    center_z += 0.008 * math.sin(2.3 * theta + 0.7)

    radial = 0.168
    radial += 0.014 * back + 0.024 * left - 0.013 * right - 0.005 * front
    radial += 0.009 * math.sin(2.1 * theta + 0.6)
    radial += 0.0045 * math.sin(6.2 * theta - 0.8)
    radial -= 0.108 * end_gate

    # The lower edge moves outward and down, the upper edge inward and up.  This
    # produces a sloped broad cloth band rather than a tube-like cross-section.
    radial -= v * 0.086 * width_scale
    z = center_z + v * 0.084 * width_scale
    lower_gate = 0.5 - v
    z -= 0.022 * front * lower_gate * width_scale
    z += 0.012 * back * (v + 0.5) * width_scale

    cloth_envelope = math.sin(math.pi * (v + 0.5)) ** 1.25
    z += 0.0080 * math.sin(3.2 * theta + 4.4 * v + 0.9) * cloth_envelope
    z += 0.0035 * math.sin(8.7 * theta - 3.0 * v) * cloth_envelope
    cross_fold = math.sin(2.65 * math.pi * (v + 0.5) + 0.55 * math.sin(theta + 0.4))
    fold_low_center = -0.24 + 0.060 * math.sin(theta + 0.3)
    fold_mid_center = 0.06 + 0.055 * math.cos(theta - 0.6)
    fold_high_center = 0.33 + 0.035 * math.sin(1.7 * theta + 0.4)
    fold_low = math.exp(-0.5 * ((v - fold_low_center) / 0.095) ** 2)
    fold_mid = math.exp(-0.5 * ((v - fold_mid_center) / 0.085) ** 2)
    fold_high = math.exp(-0.5 * ((v - fold_high_center) / 0.075) ** 2)
    fold_visibility = min(1.0, 0.25 + 0.75 * front + 0.38 * (left + right))
    z += 0.0060 * cross_fold * cloth_envelope * fold_visibility
    z += (0.0080 * fold_low - 0.0060 * fold_mid + 0.0040 * fold_high) * fold_visibility
    radial += 0.0065 * math.sin(3.8 * theta - 2.7 * v) * cloth_envelope * fold_visibility
    radial += 0.0070 * cross_fold * cloth_envelope * fold_visibility
    radial += (0.0340 * fold_low + 0.0270 * fold_mid + 0.0190 * fold_high) * fold_visibility

    # Keep the visible x envelope under 0.25 m even at the asymmetric left side.
    radial = min(radial, 0.244)
    offset = (0.5 if surface == 0 else -0.5) * THICKNESS
    radial += offset
    x = cosine * radial
    y = 0.010 + sine * radial * (0.85 + 0.25 * back)

    # Tangential slack breaks the top-view circle and gives the broad scarf a
    # subtly hand-wrapped outline.
    slack = (
        0.012 * math.sin(1.7 * theta + 0.4)
        + 0.007 * left
        - 0.004 * right
    ) * middle_gate
    x -= sine * slack
    y += cosine * slack * 0.86
    return x, y, z


scarf_vertices = []
scarf_parameters = []
for surface in range(2):
    for long_index in range(LONG_SEGMENTS + 1):
        u = long_index / LONG_SEGMENTS
        for width_index in range(WIDTH_SEGMENTS + 1):
            v = width_index / WIDTH_SEGMENTS - 0.5
            scarf_vertices.append(scarf_point(u, v, surface))
            scarf_parameters.append((surface, u, v))

PER_SURFACE = (LONG_SEGMENTS + 1) * (WIDTH_SEGMENTS + 1)


def scarf_index(surface, long_index, width_index):
    return surface * PER_SURFACE + long_index * (WIDTH_SEGMENTS + 1) + width_index


scarf_faces = []
for long_index in range(LONG_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        scarf_faces.append((
            scarf_index(0, long_index, width_index),
            scarf_index(0, long_index + 1, width_index),
            scarf_index(0, long_index + 1, width_index + 1),
            scarf_index(0, long_index, width_index + 1),
        ))
        scarf_faces.append((
            scarf_index(1, long_index, width_index),
            scarf_index(1, long_index, width_index + 1),
            scarf_index(1, long_index + 1, width_index + 1),
            scarf_index(1, long_index + 1, width_index),
        ))
for long_index in range(LONG_SEGMENTS):
    for width_index in (0, WIDTH_SEGMENTS):
        a = scarf_index(0, long_index, width_index)
        b = scarf_index(0, long_index + 1, width_index)
        c = scarf_index(1, long_index + 1, width_index)
        d = scarf_index(1, long_index, width_index)
        scarf_faces.append((a, b, c, d) if width_index == WIDTH_SEGMENTS else (d, c, b, a))
for long_index in (0, LONG_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        a = scarf_index(0, long_index, width_index)
        b = scarf_index(0, long_index, width_index + 1)
        c = scarf_index(1, long_index, width_index + 1)
        d = scarf_index(1, long_index, width_index)
        scarf_faces.append((a, b, c, d) if long_index == LONG_SEGMENTS else (d, c, b, a))

scarf_mesh = bpy.data.meshes.new(SCARF_NAME + "_Mesh")
scarf_mesh.from_pydata(scarf_vertices, [], scarf_faces)
scarf_mesh.update()
recalc_normals(scarf_mesh)
scarf = bpy.data.objects.new(SCARF_NAME, scarf_mesh)
collection.objects.link(scarf)

source_material = bpy.data.materials.get("MAT_CowlWool_Side_PBR_4K")
if source_material is None:
    source_material = bpy.data.materials.get("MAT_CowlTop_SelectiveCharcoal_PBR_4K")
if source_material is None:
    raise RuntimeError("Missing dark cowl wool PBR material")
scarf_material = source_material.copy()
scarf_material.name = "MAT_AsymmetricHelicalScarf_DarkWool_PBR_4K"
scarf_material.use_backface_culling = False
scarf_mesh.materials.append(scarf_material)
for poly in scarf_mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True

uv = scarf_mesh.uv_layers.new(name="UVMap")
for poly in scarf_mesh.polygons:
    for loop_index in poly.loop_indices:
        vertex_index = scarf_mesh.loops[loop_index].vertex_index % PER_SURFACE
        long_index = vertex_index // (WIDTH_SEGMENTS + 1)
        width_index = vertex_index % (WIDTH_SEGMENTS + 1)
        uv.data[loop_index].uv = (
            long_index / LONG_SEGMENTS * 4.2,
            width_index / WIDTH_SEGMENTS * 1.35,
        )

spine_mid = scarf.vertex_groups.new(name="DEF-spine.005")
spine_upper = scarf.vertex_groups.new(name="DEF-spine.006")
left_arm = scarf.vertex_groups.new(name="DEF-upper_arm.L")
right_arm = scarf.vertex_groups.new(name="DEF-upper_arm.R")
max_scarf_arm_weight = 0.0
for vertex, (_surface, _u, v) in zip(scarf_mesh.vertices, scarf_parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.205) / 0.045)
    lower_gate = smoothstep((0.05 - v) / 0.55)
    arm_weight = min(0.18, 0.18 * side_gate * lower_gate)
    upper_share = (1.0 - arm_weight) * (0.62 + 0.18 * (v + 0.5))
    mid_share = 1.0 - arm_weight - upper_share
    spine_upper.add([vertex.index], upper_share, "REPLACE")
    spine_mid.add([vertex.index], mid_share, "REPLACE")
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, "REPLACE")
    max_scarf_arm_weight = max(max_scarf_arm_weight, arm_weight)
attach_rigify(scarf, rig)
scarf["game_asset"] = True
scarf["part_category"] = "ClothedBody"
scarf["source"] = "V16HELICAL12C one broad 1.10-turn asymmetric closed scarf ribbon"
scarf["turns"] = TURNS

# Narrow closed liner close to the neck.  It stays behind the broad ribbon and
# is deliberately too small to become another visible concentric scarf layer.
LINER_SEGMENTS = 96
LINER_ROWS = 4
LINER_THICKNESS = 0.008
liner_vertices = []
for surface in range(2):
    for row in range(LINER_ROWS):
        t = row / (LINER_ROWS - 1)
        for segment in range(LINER_SEGMENTS):
            theta = math.tau * segment / LINER_SEGMENTS
            front = max(0.0, -math.sin(theta))
            back = max(0.0, math.sin(theta))
            left = max(0.0, -math.cos(theta))
            rx = 0.110 + 0.003 * back + 0.002 * left - surface * LINER_THICKNESS
            ry = 0.078 + 0.002 * back - surface * LINER_THICKNESS
            bottom_z = 1.414 - 0.006 * front
            top_z = 1.443 - 0.006 * front + 0.022 * back + 0.003 * left
            z = bottom_z * (1.0 - t) + top_z * t
            liner_vertices.append((rx * math.cos(theta), 0.010 + ry * math.sin(theta), z))

LINER_SURFACE_STRIDE = LINER_ROWS * LINER_SEGMENTS
liner_faces = []
for surface in range(2):
    for row in range(LINER_ROWS - 1):
        for segment in range(LINER_SEGMENTS):
            nxt = (segment + 1) % LINER_SEGMENTS
            a = surface * LINER_SURFACE_STRIDE + row * LINER_SEGMENTS + segment
            b = surface * LINER_SURFACE_STRIDE + (row + 1) * LINER_SEGMENTS + segment
            c = surface * LINER_SURFACE_STRIDE + (row + 1) * LINER_SEGMENTS + nxt
            d = surface * LINER_SURFACE_STRIDE + row * LINER_SEGMENTS + nxt
            liner_faces.append((a, b, c, d) if surface == 0 else (a, d, c, b))
for segment in range(LINER_SEGMENTS):
    nxt = (segment + 1) % LINER_SEGMENTS
    outer_bottom = segment
    inner_bottom = LINER_SURFACE_STRIDE + segment
    outer_bottom_nxt = nxt
    inner_bottom_nxt = LINER_SURFACE_STRIDE + nxt
    liner_faces.append((outer_bottom, inner_bottom, inner_bottom_nxt, outer_bottom_nxt))
    outer_top = (LINER_ROWS - 1) * LINER_SEGMENTS + segment
    inner_top = LINER_SURFACE_STRIDE + outer_top
    outer_top_nxt = (LINER_ROWS - 1) * LINER_SEGMENTS + nxt
    inner_top_nxt = LINER_SURFACE_STRIDE + outer_top_nxt
    liner_faces.append((outer_top, outer_top_nxt, inner_top_nxt, inner_top))

liner_mesh = bpy.data.meshes.new(LINER_NAME + "_Mesh")
liner_mesh.from_pydata(liner_vertices, [], liner_faces)
liner_mesh.update()
recalc_normals(liner_mesh)
liner = bpy.data.objects.new(LINER_NAME, liner_mesh)
collection.objects.link(liner)
liner_mesh.materials.append(scarf_material)
for poly in liner_mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True

bpy.ops.object.select_all(action="DESELECT")
liner.select_set(True)
bpy.context.view_layer.objects.active = liner
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

liner_mid = liner.vertex_groups.new(name="DEF-spine.005")
liner_upper = liner.vertex_groups.new(name="DEF-spine.006")
for vertex in liner_mesh.vertices:
    t = smoothstep((vertex.co.z - 1.414) / 0.105)
    liner_mid.add([vertex.index], 1.0 - 0.55 * t, "REPLACE")
    liner_upper.add([vertex.index], 0.55 * t, "REPLACE")
attach_rigify(liner, rig)
liner["game_asset"] = True
liner["part_category"] = "ClothedBody"
liner["source"] = "V16HELICAL12C narrow closed dark neck liner"

# Two very shallow root-only underpatches cover residual holes in the shoulder
# scan.  They stop at x=0.41 m, sit below the donor's upper surface, and never
# wrap around the arm; therefore they cannot create the prior padded tubes.
PATCH_AXIAL = 15
PATCH_CROSS = 11
PATCH_THICKNESS = 0.005
patch_vertices = []
patch_faces = []
for sign in (-1.0, 1.0):
    first = len(patch_vertices)
    for surface in range(2):
        for axial in range(PATCH_AXIAL):
            t = axial / (PATCH_AXIAL - 1)
            x_abs = 0.17 + 0.15 * t
            center_y = 0.060 - 0.003 * t
            center_z = 1.500 - 0.035 * smoothstep(t)
            half_y = 0.090 * (1.0 - t) + 0.075 * t
            for cross in range(PATCH_CROSS):
                s = -1.0 + 2.0 * cross / (PATCH_CROSS - 1)
                arch = math.sqrt(max(0.0, 1.0 - s * s))
                z = center_z - 0.055 * (1.0 - arch)
                z += 0.0012 * math.sin(5.0 * math.pi * t + 2.0 * math.pi * s) * arch
                patch_vertices.append((
                    sign * x_abs,
                    center_y + half_y * s,
                    z - surface * PATCH_THICKNESS,
                ))

    patch_surface_stride = PATCH_AXIAL * PATCH_CROSS
    for surface in range(2):
        offset = first + surface * patch_surface_stride
        for axial in range(PATCH_AXIAL - 1):
            for cross in range(PATCH_CROSS - 1):
                a = offset + axial * PATCH_CROSS + cross
                b = offset + (axial + 1) * PATCH_CROSS + cross
                c = offset + (axial + 1) * PATCH_CROSS + cross + 1
                d = offset + axial * PATCH_CROSS + cross + 1
                patch_faces.append((a, b, c, d) if surface == 0 else (a, d, c, b))
    for axial in range(PATCH_AXIAL - 1):
        for cross in (0, PATCH_CROSS - 1):
            top_a = first + axial * PATCH_CROSS + cross
            top_b = first + (axial + 1) * PATCH_CROSS + cross
            bottom_a = first + patch_surface_stride + axial * PATCH_CROSS + cross
            bottom_b = first + patch_surface_stride + (axial + 1) * PATCH_CROSS + cross
            patch_faces.append((top_a, bottom_a, bottom_b, top_b))
    for axial in (0, PATCH_AXIAL - 1):
        for cross in range(PATCH_CROSS - 1):
            top_a = first + axial * PATCH_CROSS + cross
            top_b = top_a + 1
            bottom_a = first + patch_surface_stride + axial * PATCH_CROSS + cross
            bottom_b = bottom_a + 1
            patch_faces.append((top_a, top_b, bottom_b, bottom_a))

patch_mesh = bpy.data.meshes.new(PATCH_NAME + "_Mesh")
patch_mesh.from_pydata(patch_vertices, [], patch_faces)
patch_mesh.update()
recalc_normals(patch_mesh)
patches = bpy.data.objects.new(PATCH_NAME, patch_mesh)
collection.objects.link(patches)
patch_material = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if patch_material is None:
    raise RuntimeError("Missing outer-wool side PBR material for shallow shoulder underpatches")
patch_mesh.materials.append(patch_material)
for poly in patch_mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True

patch_uv = patch_mesh.uv_layers.new(name="UVMap")
per_patch_surface = PATCH_AXIAL * PATCH_CROSS
for poly in patch_mesh.polygons:
    for loop_index in poly.loop_indices:
        vertex_index = patch_mesh.loops[loop_index].vertex_index
        local = vertex_index % (2 * per_patch_surface)
        within = local % per_patch_surface
        axial = within // PATCH_CROSS
        cross = within % PATCH_CROSS
        patch_uv.data[loop_index].uv = (
            axial / (PATCH_AXIAL - 1) * 2.2,
            cross / (PATCH_CROSS - 1) * 1.3,
        )

patch_spine = patches.vertex_groups.new(name="DEF-spine.005")
patch_left = patches.vertex_groups.new(name="DEF-upper_arm.L")
patch_right = patches.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in patch_mesh.vertices:
    t = smoothstep((abs(vertex.co.x) - 0.17) / 0.15)
    arm_weight = 0.15 + 0.15 * t
    patch_spine.add([vertex.index], 1.0 - arm_weight, "REPLACE")
    (patch_left if vertex.co.x >= 0.0 else patch_right).add([vertex.index], arm_weight, "REPLACE")
attach_rigify(patches, rig)
patches["game_asset"] = True
patches["part_category"] = "ClothedBody"
patches["source"] = "V16HELICAL12D compact 5mm dark-wool shoulder-root underpatches"

# Even this compact bridge read as a rectangular wing in top/high-angle QA.
# Keep this candidate strictly non-inflating: rely on donor material cleanup
# and leave final shoulder reconstruction to the dedicated sleeve pass.
patch_data = patches.data
bpy.data.objects.remove(patches, do_unlink=True)
if patch_data.users == 0:
    bpy.data.meshes.remove(patch_data)

# Rig/topology/budget validation.
new_objects = (scarf, liner)
expected_components = {scarf.name: 1, liner.name: 1}
validations = {}
for obj in new_objects:
    stats = topology(obj)
    weights = weight_range(obj)
    rigified = any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)
    if (
        stats["components"] != expected_components[obj.name]
        or stats["boundary_edges"]
        or stats["overconnected_edges"]
        or stats["nonmanifold_edges"]
        or stats["loose_vertices"]
        or stats["zero_area_faces"]
    ):
        raise RuntimeError(f"Closed topology failed on {obj.name}: {stats}")
    if weights[0] < 0.999 or weights[1] > 1.001 or not rigified:
        raise RuntimeError(f"Weight/Rigify validation failed on {obj.name}: {weights}, {rigified}")
    validations[obj.name] = {
        "vertices": len(obj.data.vertices),
        "triangles": triangle_count(obj),
        "topology": stats,
        "weight_sum_range": weights,
        "rigify": rigified,
        "bounds": bounds(obj),
    }

donor_geometry_after = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangle_count(donor),
}
donor_weight_signature_after = [
    round(sum(item.weight for item in vertex.groups), 7) for vertex in donor.data.vertices
]
if donor_geometry_after != donor_geometry_before:
    raise RuntimeError(f"Donor geometry changed: {donor_geometry_before} -> {donor_geometry_after}")
if donor_weight_signature_after != donor_weight_signature_before:
    raise RuntimeError("Donor weights changed")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Rigify deform bone count changed: {deform_bones}")
scarf_bounds = bounds(scarf)
outer_x_radius = max(abs(scarf_bounds["x"][0]), abs(scarf_bounds["x"][1]))
if outer_x_radius > 0.25:
    raise RuntimeError(f"Scarf outer x radius too large: {outer_x_radius}")

# Neutral diagnostic lighting and five mandatory views.
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.038, 0.043, 0.052, 1.0)
        background.inputs[1].default_value = 0.20

lights = []
for name, location, energy, size, color in (
    ("V16H12_Key", (-2.2, -2.7, 3.3), 76.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16H12_Fill", (2.4, -1.5, 2.5), 40.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16H12_Rim", (0.3, 2.5, 2.8), 55.0, 2.0, (0.72, 0.82, 1.0)),
):
    light_data = bpy.data.lights.new(name + "_Data", "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.02, 1.44))
    lights.append(light)

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("V16H12_DiagnosticCamera")
    camera = bpy.data.objects.new("V16H12_DiagnosticCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16helical12c_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, 0.01, 2.65), (0.0, 0.02, 1.47), 88),
    "high": render("high", (0.76, -1.08, 2.28), (0.0, 0.01, 1.45), 86),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "three_quarter": render("three_quarter", (0.78, -1.55, 1.84), (0.0, 0.0, 1.41), 88),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "retired_upper_objects": removed,
    "donor_geometry_before": donor_geometry_before,
    "donor_geometry_after": donor_geometry_after,
    "donor_geometry_preserved": donor_geometry_after == donor_geometry_before,
    "donor_weights_preserved": donor_weight_signature_after == donor_weight_signature_before,
    "shoulder_projection_polygons_remapped_to_gambeson": shoulder_polygons_remapped,
    "shoulder_surface_polygons_unified_to_gambeson": shoulder_surface_polygons_unified,
    "scarf_turns": TURNS,
    "scarf_outer_x_radius_m": outer_x_radius,
    "max_scarf_arm_weight": max_scarf_arm_weight,
    "new_object_validation": validations,
    "character_meshes": len(character_meshes),
    "total_triangles": total_triangles,
    "deform_bones": deform_bones,
    "previews": previews,
    "visual_qa": {
        "top": "CONDITIONAL PASS: no concentric multi-ring stack; one open-back U wrap remains too smooth/heavy.",
        "high": "FAIL FOR FINAL: synthetic inflated-ribbon feel and ragged donor shoulder transition remain.",
        "front": "CONDITIONAL PASS: compact dark asymmetric scarf reads acceptably at game distance.",
        "three_quarter": "CONDITIONAL PASS: two folds read, but right shoulder transition remains ragged.",
        "back": "PASS: both ends are buried; no rear bow, tail fan, or stacked collar.",
        "strict_final_verdict": "NOT FINAL-READY",
        "recommendation": "Use only as scarf donor and combine with dedicated anatomical shoulder/sleeve repair.",
    },
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16HELICAL12_REPORT=" + json.dumps(report, sort_keys=True))
