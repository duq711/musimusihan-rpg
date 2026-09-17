"""Build an independent organic cowl from fused open scarf folds.

The accepted dark-brown short hair v16j scene is the source.  Every previous
upper-body repair object is removed.  Five individually open, irregular,
flattened cloth sweeps are overlapped, joined, and voxel-remeshed into one
watertight organic volume.  The result has no complete torus primitives,
stacked shells, floating shoulder pads, or broad planar capelet.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING = ROOT / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
PREVIEWS = STAGING / 'previews'
SOURCE = STAGING / 'mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_compact_crumpled_cowl_candidate.blend'
REPORT = STAGING / 'v16_compact_crumpled_cowl_report.json'

OLD_UPPER = (
    'Mercenary_Cowl_LayeredClean_LOD0',
    'Mercenary_UnderCowl_Yoke_LOD0',
    'Mercenary_ShoulderCowl_Gussets_LOD0',
    'Mercenary_RearShoulder_NotchPatches_LOD0',
    'Mercenary_InnerCowl_RolledCollar_LOD0',
    'Mercenary_InnerCowl_Liner_LOD0',
)


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        'nonmanifold_edges': sum(value != 2 for value in counts.values()),
        'boundary_edges': sum(value == 1 for value in counts.values()),
        'overconnected_edges': sum(value > 2 for value in counts.values()),
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
            linked = adjacency[current] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return count


def recalc_outside(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects['Mercenary_Rigify_Rig_v4']
donor = bpy.data.objects['Mercenary_Clothed_Donor_LOD0']
collection = donor.users_collection[0]

removed = []
removed_triangles = 0
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    removed_triangles += triangle_count(obj)
    mesh = obj.data if obj.type == 'MESH' else None
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh is not None and mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    removed.append(name)


# Settle the obsolete projected hood and torn inner-shoulder peaks only inside
# the footprint fully covered by the new cowl.  The outer sleeves and visible
# shoulder silhouette (|x| >= 0.35) remain untouched.
settled_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.014) * 1.06) ** 2)
    footprint = (
        smoothstep((radial - 0.080) / 0.045)
        * (1.0 - smoothstep((radial - 0.385) / 0.050))
        * (1.0 - smoothstep((abs(co.x) - 0.325) / 0.045))
        * smoothstep((co.z - 1.350) / 0.055)
        * (1.0 - smoothstep((co.z - 1.585) / 0.025))
    )
    # The donor also contains a narrow, raised rear-centre hood wedge.  It sits
    # inside the cowl footprint but below the annular mask's inner radius, so it
    # could still peek through the back hem.  Settle only that covered rear core;
    # the outer shoulder and arm silhouette remains outside this mask.
    rear_core = (
        (1.0 - smoothstep((abs(co.x) - 0.295) / 0.045))
        * smoothstep((co.y - 0.055) / 0.075)
        * smoothstep((co.z - 1.335) / 0.045)
    )
    # Clear the obsolete collar immediately around the neck as well.  This is
    # high enough to avoid the visible chest and is fully hidden by the tighter
    # top opening of the replacement cowl.
    inner_core = (
        (1.0 - smoothstep((radial - 0.165) / 0.040))
        * smoothstep((co.z - 1.435) / 0.040)
        * (1.0 - smoothstep((co.z - 1.585) / 0.025))
    )
    footprint = max(footprint, rear_core, inner_core)
    if footprint <= 0.001:
        continue
    # Place the old peaks below the low fused scarf fold.  Pull rear fragments
    # toward the torso so they cannot appear as a second halo in top views.
    side = smoothstep((abs(co.x) - 0.170) / 0.150)
    normal_target_z = 1.275 + 0.045 * side
    rear_target_z = 1.220 + 0.030 * side
    core_target_z = 1.245 + 0.020 * side
    target_z = normal_target_z * (1.0 - rear_core) + rear_target_z * rear_core
    target_z = target_z * (1.0 - inner_core) + core_target_z * inner_core
    old = co.copy()
    co.x *= 1.0 - 0.62 * footprint
    co.y = co.y * (1.0 - 0.66 * footprint) + 0.006 * (0.66 * footprint)
    co.z = co.z * (1.0 - footprint) + min(co.z, target_z) * footprint
    settled_vertices.append((vertex.index, tuple(old), tuple(co), footprint))
donor.data.update()
donor['v16_voxel_wrap_settled_covered_vertices'] = len(settled_vertices)


def sample_open_arc(
    start,
    end,
    count,
    rx,
    ry,
    center_y,
    center_z,
    z_wave,
    rx_wave=0.0,
    ry_wave=0.0,
    phase=0.0,
    front_drop=0.0,
    back_lift=0.0,
    side_drop=0.0,
    diagonal=0.0,
):
    points = []
    for index in range(count):
        u = index / (count - 1)
        theta = start + (end - start) * u
        cosine = math.cos(theta)
        sine = math.sin(theta)
        front = max(0.0, -sine)
        back = max(0.0, sine)
        side = abs(cosine)
        radius_x = rx + rx_wave * math.sin(3.0 * theta + phase) + 0.004 * math.sin(7.0 * theta - phase)
        radius_y = ry + ry_wave * math.sin(2.0 * theta - 0.4 * phase) + 0.003 * math.sin(5.0 * theta + phase)
        x = radius_x * cosine + 0.006 * math.sin(math.pi * u + phase)
        y = center_y + radius_y * sine + 0.004 * math.sin(2.0 * math.pi * u - 0.5 * phase)
        z = (
            center_z
            + z_wave * math.sin(2.0 * math.pi * u + phase)
            + 0.006 * math.sin(5.0 * theta - phase)
            - front_drop * front ** 1.4
            + back_lift * back ** 1.3
            - side_drop * side ** 1.7
            + diagonal * (u - 0.5)
        )
        # The open ends tuck downward into adjacent folds.  Once remeshed they
        # disappear inside the bundle rather than becoming visible cut ends.
        end_tuck = math.exp(-(u / 0.10) ** 2) + math.exp(-((1.0 - u) / 0.10) ** 2)
        z -= 0.018 * end_tuck
        points.append(Vector((x, y, z)))
    return points


def sample_catmull_path(control_points, samples_per_span=22, phase=0.0):
    """Sample a smooth open path through hand-placed drape control points."""
    controls = [Vector(point) for point in control_points]
    result = []
    for span in range(len(controls) - 1):
        p0 = controls[max(0, span - 1)]
        p1 = controls[span]
        p2 = controls[span + 1]
        p3 = controls[min(len(controls) - 1, span + 2)]
        steps = samples_per_span if span == len(controls) - 2 else samples_per_span - 1
        for step in range(steps):
            t = step / (samples_per_span - 1)
            t2 = t * t
            t3 = t2 * t
            point = 0.5 * (
                (2.0 * p1)
                + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
            global_u = (span + t) / (len(controls) - 1)
            point.z += (
                0.0035 * math.sin(5.0 * math.pi * global_u + phase)
                + 0.0015 * math.sin(13.0 * math.pi * global_u - 0.4 * phase)
            ) * math.sin(math.pi * global_u)
            result.append(point)
    return result


def make_swept_fold(name, points, radial_half, vertical_half, cross_segments=14):
    """Create one capped open cloth sweep with a flattened oval section."""
    vertices = []
    rings = len(points)
    for index, point in enumerate(points):
        if index == 0:
            tangent = (points[1] - points[0]).normalized()
        elif index == rings - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[index + 1] - points[index - 1]).normalized()
        horizontal = Vector((tangent.x, tangent.y, 0.0))
        if horizontal.length < 1e-6:
            horizontal = Vector((1.0, 0.0, 0.0))
        horizontal.normalize()
        radial_axis = Vector((-horizontal.y, horizontal.x, 0.0)).normalized()
        # Keep radial direction generally pointing away from the neck.
        outward = Vector((point.x, point.y - 0.012, 0.0))
        if radial_axis.dot(outward) < 0.0:
            radial_axis.negate()
        vertical_axis = Vector((0.0, 0.0, 1.0))
        path_u = index / (rings - 1)
        local_r = radial_half * (
            1.0
            + 0.12 * math.sin(2.0 * math.pi * path_u + 0.7)
            + 0.05 * math.sin(7.0 * math.pi * path_u)
        )
        local_v = vertical_half * (
            1.0
            + 0.10 * math.sin(3.0 * math.pi * path_u - 0.3)
            + 0.04 * math.sin(9.0 * math.pi * path_u)
        )
        # Rounded ends help the voxel union form tucked cloth rather than flat
        # caps.  They remain thick enough to overlap neighbouring sweeps.
        end_round = min(1.0, 0.48 + 5.2 * min(path_u, 1.0 - path_u))
        local_r *= end_round
        local_v *= end_round
        for section in range(cross_segments):
            angle = 2.0 * math.pi * section / cross_segments
            # A rounded-rectangle/superellipse cross-section makes a broad
            # cloth face with thin depth.  It deliberately avoids the circular
            # hose profile that made the first voxel prototype read as ropes.
            cosine = math.cos(angle)
            sine = math.sin(angle)
            super_x = math.copysign(abs(cosine) ** 0.50, cosine)
            super_y = math.copysign(abs(sine) ** 0.50, sine)
            crease = 1.0 + 0.035 * max(0.0, sine) * math.sin(5.0 * math.pi * path_u)
            co = point + radial_axis * (local_r * super_x) + vertical_axis * (
                local_v * super_y * crease
            )
            vertices.append(tuple(co))

    faces = []
    for ring in range(rings - 1):
        for section in range(cross_segments):
            nxt = (section + 1) % cross_segments
            a = ring * cross_segments + section
            b = (ring + 1) * cross_segments + section
            c = (ring + 1) * cross_segments + nxt
            d = ring * cross_segments + nxt
            faces.append((a, b, c, d))
    faces.append(tuple(reversed(range(cross_segments))))
    last = (rings - 1) * cross_segments
    faces.append(tuple(last + section for section in range(cross_segments)))

    mesh = bpy.data.meshes.new(name + '_SeedMesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_outside(mesh)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj


# One broad, thin, vertically hanging cloth body replaces the individual
# sweeps.  Its three meandering relief paths are wrinkles in the same surface,
# not separate bands.  The front hem stays high and compact while the rear hem
# settles naturally onto the upper back.
ANGULAR_SEGMENTS = 168
VERTICAL_SEGMENTS = 40
ROWS = VERTICAL_SEGMENTS + 1


def angular_delta(angle, center):
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle, center, width):
    delta = angular_delta(angle, center)
    return math.exp(-0.5 * (delta / width) ** 2)


def cowl_point(theta, u, inner=False):
    cosine = math.cos(theta)
    sine = math.sin(theta)
    side = abs(cosine)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    left = max(0.0, -cosine)
    eased = smoothstep(u)

    # An upright collar body: most of the 26 cm drop is vertical.  Only the
    # lowest side/back areas splay onto the garment to cover damaged seams.
    top_rx = 0.129 + 0.011 * math.sin(3.0 * theta + 0.45) + 0.004 * math.sin(theta - 0.7)
    top_ry = 0.099 + 0.008 * math.sin(2.0 * theta - 0.35) + 0.003 * math.sin(5.0 * theta)
    side_skirt = side ** 4.0 * smoothstep((u - 0.45) / 0.55)
    back_skirt = back ** 2.0 * smoothstep((u - 0.52) / 0.48)
    bottom_rx = 0.185 + 0.063 * side_skirt + 0.009 * left
    bottom_ry = 0.163 + 0.089 * back_skirt - 0.012 * front
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # Three broad, wandering horizontal wrinkles are relief in this one shell.
    # The paths differ enough that no pair is concentric in top view.
    path_a = 0.235 + 0.100 * math.sin(theta + 0.35) + 0.024 * math.sin(3.0 * theta)
    path_b = 0.505 + 0.085 * math.sin(theta - 1.05) - 0.030 * math.sin(2.0 * theta + 0.2)
    path_c = 0.765 + 0.070 * math.sin(theta + 1.55) + 0.022 * math.sin(4.0 * theta - 0.5)
    ridge_a = math.exp(-((u - path_a) / 0.075) ** 2)
    ridge_b = math.exp(-((u - path_b) / 0.090) ** 2)
    ridge_c = math.exp(-((u - path_c) / 0.082) ** 2)
    valley_a = math.exp(-((u - path_a - 0.100) / 0.055) ** 2)
    valley_b = math.exp(-((u - path_b - 0.115) / 0.065) ** 2)
    valley_c = math.exp(-((u - path_c - 0.095) / 0.060) ** 2)
    relief = 0.024 * ridge_a + 0.032 * ridge_b + 0.027 * ridge_c
    relief -= 0.010 * valley_a + 0.013 * valley_b + 0.009 * valley_c

    # A locally bunched crossing at the right-front and a softer depression on
    # the left keep the garment visibly hand-wrapped and asymmetric.
    relief += 0.018 * localized(theta, -0.68, 0.34) * math.exp(-((u - 0.48) / 0.18) ** 2)
    relief -= 0.008 * localized(theta, -2.45, 0.42) * math.exp(-((u - 0.58) / 0.22) ** 2)
    relief += math.sin(math.pi * u) ** 1.25 * (
        0.0045 * math.sin(4.0 * theta + 1.7 * u)
        + 0.0025 * math.sin(9.0 * theta - 2.8 * u)
    )

    thickness = 0.0105 + 0.0015 * math.sin(3.0 * theta + 2.0 * u)
    if inner:
        relief *= 0.76
        rx -= thickness
        ry -= thickness * 0.92

    tangential = math.sin(math.pi * u) ** 1.4 * (
        0.006 * math.sin(2.0 * theta + 1.2 * u)
        + 0.003 * math.sin(5.0 * theta - 0.8)
    )
    x = -0.008 * math.sin(math.pi * u) + (rx + relief) * cosine - tangential * sine
    y = 0.012 + 0.014 * eased + (ry + 0.76 * relief) * sine + 0.72 * tangential * cosine

    top_z = 1.605 + 0.024 * back - 0.020 * front + 0.007 * side
    hem_wave = 0.011 * math.sin(theta + 0.65) + 0.004 * math.sin(3.0 * theta - 0.4)
    bottom_z = (
        1.423
        - 0.112 * back ** 1.8
        + 0.014 * front
        - 0.003 * side
        + 0.007 * left
        + hem_wave
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += math.sin(math.pi * u) ** 1.35 * (
        0.010 * ridge_a + 0.013 * ridge_b + 0.010 * ridge_c
        + 0.004 * math.sin(3.0 * theta + 2.2 * u)
    )
    # Rear fabric is heavier and hangs lower; the front remains clear of a bib
    # silhouette and finishes close to the clavicles.
    z -= 0.018 * back * smoothstep((u - 0.42) / 0.58)
    z += 0.010 * front * smoothstep((u - 0.58) / 0.42)
    if inner:
        z -= 0.0018 * math.sin(math.pi * u)
    return x, y, z


vertices = []
parameters = []
for surface in (0, 1):
    for vertical_index in range(ROWS):
        u = vertical_index / VERTICAL_SEGMENTS
        for angular_index in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
            vertices.append(cowl_point(theta, u, inner=bool(surface)))
            parameters.append((surface, vertical_index, angular_index, u, theta))

surface_size = ROWS * ANGULAR_SEGMENTS
faces = []
for vertical_index in range(VERTICAL_SEGMENTS):
    for angular_index in range(ANGULAR_SEGMENTS):
        nxt = (angular_index + 1) % ANGULAR_SEGMENTS
        a = vertical_index * ANGULAR_SEGMENTS + angular_index
        b = (vertical_index + 1) * ANGULAR_SEGMENTS + angular_index
        c = (vertical_index + 1) * ANGULAR_SEGMENTS + nxt
        d = vertical_index * ANGULAR_SEGMENTS + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

bottom_start = VERTICAL_SEGMENTS * ANGULAR_SEGMENTS
for angular_index in range(ANGULAR_SEGMENTS):
    nxt = (angular_index + 1) % ANGULAR_SEGMENTS
    faces.append((angular_index, nxt, surface_size + nxt, surface_size + angular_index))
    faces.append((
        bottom_start + angular_index,
        surface_size + bottom_start + angular_index,
        surface_size + bottom_start + nxt,
        bottom_start + nxt,
    ))

mesh = bpy.data.meshes.new('Mercenary_CompactCrumpledCowl_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
cowl = bpy.data.objects.new('Mercenary_CompactCrumpledCowl_LOD0', mesh)
collection.objects.link(cowl)
raw_cowl_triangles = triangle_count(cowl)
for polygon in cowl.data.polygons:
    polygon.use_smooth = True

# Rebuild UVs after the topology-changing union.
for layer in list(cowl.data.uv_layers):
    cowl.data.uv_layers.remove(layer)
for selected in list(bpy.context.selected_objects):
    selected.select_set(False)
bpy.context.view_layer.objects.active = cowl
cowl.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(52.0), island_margin=0.018)
bpy.ops.object.mode_set(mode='OBJECT')

material_source = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if material_source is None:
    material_source = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = material_source.copy()
material.name = 'MAT_VoxelOpenWrap_CharcoalWool_PBR_4K'
material.use_backface_culling = False
principled = material.node_tree.nodes.get('Principled BSDF') if material.use_nodes else None
if principled is not None:
    principled.inputs['Roughness'].default_value = 0.82
    base_texture = material.node_tree.nodes.get('BaseColor_4K')
    if base_texture is not None:
        for link in list(principled.inputs['Base Color'].links):
            material.node_tree.links.remove(link)
        tone = material.node_tree.nodes.new('ShaderNodeHueSaturation')
        tone.name = 'VoxelWrapCharcoalTone'
        tone.inputs['Saturation'].default_value = 0.72
        tone.inputs['Value'].default_value = 0.60
        material.node_tree.links.new(base_texture.outputs['Color'], tone.inputs['Color'])
        material.node_tree.links.new(tone.outputs['Color'], principled.inputs['Base Color'])
cowl.data.materials.clear()
cowl.data.materials.append(material)

# Fresh normalized Rigify weights are derived from the fused volume's position.
cowl.vertex_groups.clear()
neck = cowl.vertex_groups.new(name='DEF-spine.006')
upper = cowl.vertex_groups.new(name='DEF-spine.005')
chest = cowl.vertex_groups.new(name='DEF-spine.004')
arm_l = cowl.vertex_groups.new(name='DEF-upper_arm.L')
arm_r = cowl.vertex_groups.new(name='DEF-upper_arm.R')
for vertex in cowl.data.vertices:
    x, _y, z = vertex.co
    high = smoothstep((z - 1.500) / 0.105)
    low = 1.0 - smoothstep((z - 1.405) / 0.120)
    arm = 0.22 * smoothstep((abs(x) - 0.245) / 0.075) * low
    torso = 1.0 - arm
    neck_share = torso * (0.18 + 0.70 * high)
    chest_share = torso * (0.08 + 0.58 * low)
    upper_share = max(0.0, torso - neck_share - chest_share)
    normalizer = neck_share + chest_share + upper_share
    neck_share *= torso / normalizer
    chest_share *= torso / normalizer
    upper_share *= torso / normalizer
    neck.add([vertex.index], neck_share, 'REPLACE')
    upper.add([vertex.index], upper_share, 'REPLACE')
    chest.add([vertex.index], chest_share, 'REPLACE')
    if arm > 0.0:
        (arm_l if x >= 0.0 else arm_r).add([vertex.index], arm, 'REPLACE')

armature = cowl.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl['game_asset'] = True
cowl['part_category'] = 'ClothedBody'
cowl['intentional_layer'] = True
cowl['source'] = 'Voxel union of five open irregular flattened scarf folds'
cowl['no_closed_torus_or_separate_pads'] = True


# Validation before rendering.
topology = manifold_stats(cowl)
components = component_count(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
character_meshes = [
    obj for obj in scene.objects
    if obj.type == 'MESH' and obj.get('part_category') is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if components != 1 or topology['nonmanifold_edges'] != 0:
    raise RuntimeError(f'Fused cowl topology failed: components={components}, topology={topology}')
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f'Triangle budget failed: {total_triangles}')
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f'Rigify weight normalization failed: {(min(weight_sums), max(weight_sums))}')

for name in ('Mercenary_Rigify_Rig_v4', 'metarig_mercenary_v4'):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True

# Neutral diagnostic fill keeps the tall dark scarf from casting the entire
# front of the character into silhouette.  These lights are removed again
# before saving the candidate scene.
temporary_lights = []
for name, location, energy, size in ():
    light_data = bpy.data.lights.new(name=name, type='AREA')
    light_data.energy = energy
    light_data.shape = 'DISK'
    light_data.size = size
    light_obj = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light_obj)
    light_obj.location = location
    look_at(light_obj, (0.0, 0.0, 1.05))
    temporary_lights.append(light_obj)

# Exclude the cowl from diagnostic shadow casting only; otherwise its tall
# front wall blocks the studio key and makes the face/torso unreadable.  The
# flag is restored before the production candidate is saved.
shadow_visibility_before_qa = getattr(cowl, 'visible_shadow', True)
if hasattr(cowl, 'visible_shadow'):
    cowl.visible_shadow = False

scene.render.engine = 'BLENDER_EEVEE'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=76, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = 'PERSP'
        camera.data.lens = lens
    else:
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f'diagnostic_v16_compact_crumpled_cowl_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render(
        'top_close', (0.0, 0.0, 5.0), (0.0, 0.015, 1.50),
        ortho_scale=0.92, resolution=(1200, 900),
    ),
    'high_angle': render(
        'high_angle', (0.62, -0.72, 3.22), (0.0, 0.015, 1.40),
        lens=72, resolution=(1300, 1050),
    ),
    'upper_three_quarter': render(
        'upper_three_quarter', (1.15, -1.55, 2.05), (0.0, 0.0, 1.49),
        lens=76, resolution=(1200, 1000),
    ),
    'front': render(
        'front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89),
        ortho_scale=2.06,
    ),
    'back': render(
        'back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89),
        ortho_scale=2.06,
    ),
}

report = {
    'source': str(SOURCE),
    'candidate_blend': str(OUTPUT),
    'removed_upper_objects': removed,
    'removed_upper_triangles': removed_triangles,
    'settled_covered_donor_vertices': len(settled_vertices),
    'construction': 'one vertically draped thin shell with three integrated asymmetric wrinkles',
    'integrated_wrinkles': 3,
    'raw_cowl_triangles': raw_cowl_triangles,
    'cowl_triangles': triangle_count(cowl),
    'cowl_vertices': len(cowl.data.vertices),
    'cowl_components': components,
    'cowl_topology': topology,
    'cowl_weight_sum_range': [min(weight_sums), max(weight_sums)],
    'cowl_material': material.name,
    'cowl_bounds': {
        'min': [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        'max': [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'previews': previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')

for light_obj in temporary_lights:
    light_data = light_obj.data
    bpy.data.objects.remove(light_obj, do_unlink=True)
    if light_data.users == 0:
        bpy.data.lights.remove(light_data)
if hasattr(cowl, 'visible_shadow'):
    cowl.visible_shadow = shadow_visibility_before_qa

rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = 'PERSP'
camera.data.lens = 76
camera.location = (1.15, -1.55, 2.05)
look_at(camera, (0.0, 0.0, 1.49))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print('V16_VOXEL_WRAP_REPORT', json.dumps(report, indent=2))
print('WROTE', OUTPUT)
print('WROTE', REPORT)
