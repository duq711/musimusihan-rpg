"""Compact integrated draped cowl candidate for v16.

All concentric cowl/torus helpers are retired.  One closed, connected textile
shell rises around the neck and hangs toward the chest/back.  Its folds run
radially and diagonally through the cloth; there are no repeated circular
silhouettes, stacked tubes, or broad horizontal poncho plate.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_organic_integrated_sheet_candidate.blend'
REPORT = STAGING / 'v16_organic_integrated_sheet_report.json'

RETIRED_NAMES = (
    'Mercenary_Cowl_LayeredClean_LOD0',
    'Mercenary_UnderCowl_Yoke_LOD0',
    'Mercenary_ShoulderCowl_Gussets_LOD0',
    'Mercenary_RearShoulder_NotchPatches_LOD0',
    'Mercenary_InnerCowl_RolledCollar_LOD0',
)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects['Mercenary_Rigify_Rig_v4']
donor = bpy.data.objects['Mercenary_Clothed_Donor_LOD0']
asset_collection = donor.users_collection[0]
cloth_material = bpy.data.materials['MAT_CowlTop_SelectiveCharcoal_PBR_4K'].copy()
cloth_material.name = 'MAT_CowlWool_OrganicIntegratedSheet_PBR_4K'
principled = cloth_material.node_tree.nodes.get('Principled BSDF')
if principled is not None:
    principled.inputs['Roughness'].default_value = 0.80
    base_links = list(principled.inputs['Base Color'].links)
    if base_links:
        source_socket = base_links[0].from_socket
        for link in base_links:
            cloth_material.node_tree.links.remove(link)
        charcoal_tone = cloth_material.node_tree.nodes.new('ShaderNodeHueSaturation')
        charcoal_tone.name = 'OrganicCowlCharcoalTone'
        charcoal_tone.inputs['Saturation'].default_value = 0.68
        charcoal_tone.inputs['Value'].default_value = 0.43
        cloth_material.node_tree.links.new(source_socket, charcoal_tone.inputs['Color'])
        cloth_material.node_tree.links.new(charcoal_tone.outputs['Color'], principled.inputs['Base Color'])


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angular_delta(a, b):
    return (a - b + math.pi) % (2.0 * math.pi) - math.pi


def ridge(theta, center, sigma):
    delta = angular_delta(theta, center)
    return math.exp(-0.5 * (delta / sigma) ** 2)


def recalc_outside(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
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


retired = []
for name in RETIRED_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.hide_render = True
    obj.hide_viewport = True
    obj.hide_set(True)
    obj['retired_by_v16_organic_integrated_sheet'] = True
    obj['part_category_before_retirement'] = obj.get('part_category')
    if 'part_category' in obj:
        del obj['part_category']
    obj['game_asset'] = False
    retired.append(name)


# Smoothly settle the donor's obsolete central/rear collar under the new cowl.
# A soft outer falloff keeps the sleeve/shoulder transition natural.
settled_donor_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.02) * 1.10) ** 2)
    influence = (
        smoothstep((radial - 0.080) / 0.045)
        * (1.0 - smoothstep((radial - 0.255) / 0.155))
        * smoothstep((co.y - 0.000) / 0.080)
        * smoothstep((co.z - 1.405) / 0.080)
    )
    if influence <= 0.002:
        continue
    target_z = (
        1.397
        + 0.018 * smoothstep((abs(co.x) - 0.195) / 0.155)
        + 0.004 * smoothstep((co.y - 0.16) / 0.12)
    )
    lowered = min(co.z, target_z)
    settled_donor_vertices.append((vertex.index, co.z, lowered, influence))
    co.z = co.z * (1.0 - influence) + lowered * influence
donor.data.update()
donor['v16_hidden_rear_collar_settled'] = True
donor['v16_hidden_rear_collar_settled_vertex_count'] = len(settled_donor_vertices)


ANGULAR_SEGMENTS = 168
RADIAL_SEGMENTS = 36
THICKNESS = 0.012


def surface_point(theta, v):
    """One thick, closed shoulder sheet with an organic raised neck wall.

    The cloth is deliberately *not* built from circular bands.  Its inner and
    outer outlines have different centres and aspect ratios, while every major
    fold travels diagonally through the sheet.  The result is a single piece of
    fabric that bunches at the neck and opens into short shoulder/front drapes.
    """
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)
    left = max(0.0, -cosine)
    right = max(0.0, cosine)
    eased = smoothstep(v)
    # Fold the radial profile back and forth like a compressed scarf.  The
    # theta-dependent phase makes the crests wander and join as offset arcs,
    # never as clean concentric rings.  Endpoints remain fixed at neck/hem.
    base_spread = smoothstep(v ** 1.48)
    fold_phase = (
        4.20 * math.pi * v
        + 0.66 * math.sin(theta - 0.38)
        + 0.25 * math.sin(3.0 * theta + 0.54)
        + 0.22 * v * math.sin(2.0 * theta - 0.15)
    )
    fold_amplitude = 0.112 * math.sin(math.pi * v) ** 1.12
    spread = base_spread + fold_amplitude * math.sin(fold_phase)

    # Compact non-concentric footprint.  The left shoulder and front-right
    # overlap extend locally, instead of forming a uniformly wide annulus.
    left_shoulder = ridge(theta, math.pi, 0.37)
    right_shoulder = ridge(theta, 0.0, 0.34)
    front_left_tail = ridge(theta, 1.37 * math.pi, 0.30)
    back_right_tuck = ridge(theta, 0.27 * math.pi, 0.30)
    outer_rx = (
        0.242
        + 0.033 * left_shoulder
        + 0.026 * right_shoulder
        + 0.010 * front_left_tail
    )
    outer_ry = (
        0.122
        + 0.029 * back
        + 0.014 * front_left_tail
        - 0.006 * back_right_tuck
    )
    inner_rx = 0.111 + 0.005 * math.sin(3.0 * theta + 0.62)
    inner_ry = 0.083 + 0.004 * math.sin(2.0 * theta - 0.45)
    rx = inner_rx * (1.0 - spread) + outer_rx * spread
    ry = inner_ry * (1.0 - spread) + outer_ry * spread

    # Organic hem and drifting centre.  The warp fades at the neckline so the
    # neck seal remains compact, but becomes visibly hand-draped at the hem.
    radial_warp = 1.0 + spread * (
        0.038 * math.sin(3.0 * theta + 0.28)
        + 0.022 * math.sin(7.0 * theta - 0.92)
        + 0.011 * math.sin(11.0 * theta + 0.51)
    )
    center_x = -0.004 * spread + 0.007 * math.sin(theta + 0.4) * spread
    center_y = 0.010 + 0.025 * spread + 0.008 * math.sin(2.0 * theta + 0.52) * spread
    x = center_x + rx * radial_warp * cosine
    y = center_y + ry * radial_warp * sine

    # High bundled inner wall and a short, irregular outer drape.  The front
    # overlap falls deepest; side shoulders stay high enough to cover donor
    # seams without producing a wide horizontal poncho plane.
    inner_z = (
        1.526
        + 0.035 * back ** 1.25
        - 0.011 * front ** 1.30
        + 0.013 * left
        - 0.006 * right
        + 0.004 * math.sin(2.0 * theta + 0.22)
    )
    outer_z = (
        1.405
        + 0.038 * side ** 1.55
        - 0.018 * front_left_tail
        - 0.006 * front
        + 0.008 * back
        - 0.008 * left_shoulder
        + 0.011 * math.sin(5.0 * theta + 0.31)
    )
    descent = smoothstep(v ** 0.73)
    z = inner_z * (1.0 - descent) + outer_z * descent
    # Radial accordion crests rise slightly as they push outward, creating
    # self-shadowing folds instead of one uninterrupted sloping plane.
    z += 0.024 * math.sin(fold_phase) * math.sin(math.pi * v) ** 1.08

    # One broken, asymmetrical neckline roll, strongest at the back-left.  Its
    # angular modulation prevents a clean circular ridge.
    neck_envelope = math.exp(-((v - 0.085) / 0.072) ** 2)
    z += neck_envelope * (
        0.009
        + 0.011 * ridge(theta, 0.72 * math.pi, 0.62)
        + 0.006 * math.sin(theta - 0.2)
    )

    # Three broad, broken pleats sculpted into the same sheet.  Each follows a
    # different drifting phase and fades over a different angular region.  In
    # front view they create the heavy U-shaped bunching of a scarf; in exact
    # top view they remain offset arcs rather than concentric circles.
    pleat_specs = (
        (0.22, +0.080, 0.060, 0.017, 0.036, clamp(0.14 + 0.78 * front + 0.18 * left)),
        (0.46, -0.072, 0.064, 0.022, 0.050, clamp(0.12 + 0.82 * front + 0.20 * right)),
        (0.70, +0.060, 0.068, 0.018, 0.042, clamp(0.08 + 0.88 * front_left_tail + 0.12 * back)),
    )
    for pleat_center, phase_amount, width, height, outward, angular_mask in pleat_specs:
        phase = v + phase_amount * math.sin(theta + 1.9 * v) + 0.022 * math.sin(3.0 * theta - 0.5)
        crest = math.exp(-0.5 * ((phase - pleat_center) / width) ** 2)
        trough = math.exp(-0.5 * ((phase - (pleat_center + 1.35 * width)) / (0.62 * width)) ** 2)
        pleat = angular_mask * (crest - 0.58 * trough)
        z += height * pleat
        x += outward * pleat * cosine
        y += outward * pleat * sine

    # Strong diagonal folds.  Every centre drifts with radial distance and has
    # an adjacent trough, giving broad creases rather than embossed stripes.
    fold_envelope = math.sin(math.pi * v) ** 0.82
    fold_specs = (
        (1.37 * math.pi, +0.68, 0.23, 0.021, 0.010),  # hanging front-left overlap
        (1.66 * math.pi, -0.48, 0.18, 0.016, 0.007),
        (0.86 * math.pi, +0.51, 0.22, 0.018, 0.008),  # broad rear-left bunch
        (0.42 * math.pi, -0.56, 0.18, 0.015, 0.007),
        (0.09 * math.pi, +0.40, 0.17, 0.012, 0.006),
        (1.05 * math.pi, -0.34, 0.14, 0.011, 0.005),
    )
    for base_angle, slope, sigma, height, outward in fold_specs:
        center = base_angle + slope * (v - 0.5)
        crest = ridge(theta, center, sigma)
        valley = ridge(theta, center + 1.48 * sigma, 0.78 * sigma)
        relief = fold_envelope * (crest - 0.69 * valley)
        z += height * relief
        x += outward * relief * cosine
        y += outward * relief * sine

    # Two broad helical settling waves tie the localized folds into a single
    # wound sheet; phase depends on both theta and v, never on v alone.
    z += fold_envelope * (
        0.012 * math.sin(2.15 * theta + 5.2 * v + 0.35)
        + 0.006 * math.sin(5.3 * theta - 3.1 * v)
    )
    z += smoothstep((v - 0.79) / 0.21) * (
        0.010 * math.sin(6.0 * theta + 0.4)
        + 0.005 * math.sin(10.0 * theta - 0.7)
    )
    return x, y, z


vertices = []
parameters = []
for surface in (0, 1):
    for radial_index in range(RADIAL_SEGMENTS + 1):
        v = radial_index / RADIAL_SEGMENTS
        for angular_index in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
            x, y, z = surface_point(theta, v)
            if surface == 1:
                z -= THICKNESS
            vertices.append((x, y, z))
            parameters.append((surface, radial_index, angular_index, v, theta))

ring = ANGULAR_SEGMENTS
surface_size = (RADIAL_SEGMENTS + 1) * ring
faces = []
for radial_index in range(RADIAL_SEGMENTS):
    for angular_index in range(ring):
        nxt = (angular_index + 1) % ring
        a = radial_index * ring + angular_index
        b = (radial_index + 1) * ring + angular_index
        c = (radial_index + 1) * ring + nxt
        d = radial_index * ring + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

outer_start = RADIAL_SEGMENTS * ring
for angular_index in range(ring):
    nxt = (angular_index + 1) % ring
    faces.append((
        outer_start + angular_index,
        surface_size + outer_start + angular_index,
        surface_size + outer_start + nxt,
        outer_start + nxt,
    ))
    faces.append((
        angular_index,
        nxt,
        surface_size + nxt,
        surface_size + angular_index,
    ))

mesh = bpy.data.meshes.new('Mercenary_OrganicIntegratedSheetCowl_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
cowl = bpy.data.objects.new('Mercenary_OrganicIntegratedSheetCowl_LOD0', mesh)
asset_collection.objects.link(cowl)
mesh.materials.append(cloth_material)
cowl['game_asset'] = True
cowl['part_category'] = 'ClothedBody'
cowl['intentional_layer'] = True
cowl['source'] = 'V16 one-piece thick closed shoulder sheet rising into an asymmetrical neck drape'
cowl['no_concentric_folds'] = True
cowl['no_torus_or_poncho_plate'] = True
cowl['replaces'] = ', '.join(RETIRED_NAMES)

uv_layer = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        _surface, _ri, angular_index, v, _theta = parameters[vertex_index]
        uv_layer.data[loop_index].uv = (angular_index / ANGULAR_SEGMENTS * 3.2, v * 1.9)

neck = cowl.vertex_groups.new(name='DEF-spine.006')
upper = cowl.vertex_groups.new(name='DEF-spine.005')
chest = cowl.vertex_groups.new(name='DEF-spine.004')
left_arm = cowl.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = cowl.vertex_groups.new(name='DEF-upper_arm.R')
for vertex, (_surface, _ri, _ai, v, _theta) in zip(mesh.vertices, parameters):
    arm_weight = (
        0.20 * smoothstep((abs(vertex.co.x) - 0.225) / 0.090)
        * smoothstep((v - 0.62) / 0.38)
    )
    torso = 1.0 - arm_weight
    neck_factor = 0.10 + 0.74 * (1.0 - smoothstep(v / 0.72))
    chest_factor = 0.12 + 0.46 * smoothstep((v - 0.35) / 0.65)
    upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
    norm = neck_factor + upper_factor + chest_factor
    neck_share = torso * neck_factor / norm
    upper_share = torso * upper_factor / norm
    chest_share = torso * chest_factor / norm
    neck.add([vertex.index], neck_share, 'REPLACE')
    upper.add([vertex.index], upper_share, 'REPLACE')
    chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')

for selected in bpy.context.selected_objects:
    selected.select_set(False)
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
bevel = cowl.modifiers.new('ClothEdgeSoftening', 'BEVEL')
bevel.width = 0.0025
bevel.segments = 2
bevel.limit_method = 'ANGLE'
bevel.angle_limit = math.radians(35.0)
bpy.ops.object.modifier_apply(modifier=bevel.name)
cowl.select_set(False)

armature = cowl.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()


stats = manifold_stats(cowl)
components = component_count(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
weight_range = [min(weight_sums), max(weight_sums)]
has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in cowl.modifiers)
if stats['nonmanifold_edges'] != 0 or components != 1:
    raise RuntimeError(f'Cowl topology failed: {stats}, components={components}')
if weight_range[0] < 0.99999 or weight_range[1] > 1.00001 or not has_rig:
    raise RuntimeError(f'Cowl Rigify failed: weights={weight_range}, rig={has_rig}')

character_meshes = [
    obj for obj in scene.objects
    if obj.type == 'MESH' and obj.get('part_category') is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f'Triangle budget failed: {total_triangles}')


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


for name in ('Mercenary_Rigify_Rig_v4', 'metarig_mercenary_v4'):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = 'BLENDER_EEVEE'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = 'PERSP'
        camera.data.lens = lens
    else:
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f'diagnostic_v16_organic_integrated_sheet_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render(
        'top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.49),
        ortho_scale=0.90, resolution=(1200, 900),
    ),
    'high_angle': render(
        'high_angle', (1.05, -1.30, 3.05), (0.0, 0.015, 1.39),
        lens=78, resolution=(1400, 1000),
    ),
    'failure_view': render(
        'failure_view', (0.57, -0.57, 5.58), (0.0, 0.055, 1.03),
        lens=78, resolution=(1400, 1000),
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

bounds = {
    'min': [min(v.co[i] for v in cowl.data.vertices) for i in range(3)],
    'max': [max(v.co[i] for v in cowl.data.vertices) for i in range(3)],
}
report = {
    'source': str(SOURCE),
    'candidate_blend': str(OUTPUT),
    'retired_objects': retired,
    'settled_donor_rear_collar_vertices': len(settled_donor_vertices),
    'organic_integrated_sheet_cowl': cowl.name,
    'single_cowl_material': cloth_material.name,
    'cowl_vertices': len(cowl.data.vertices),
    'cowl_triangles': triangle_count(cowl),
    'cowl_components': components,
    'cowl_manifold': stats,
    'cowl_weight_sum_range': weight_range,
    'cowl_rigify_modifier': has_rig,
    'cowl_bounds': bounds,
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'previews': previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')

rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = 'PERSP'
camera.data.lens = 76
camera.location = (1.15, -1.55, 2.05)
look_at(camera, (0.0, 0.0, 1.49))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print('V16_INTEGRATED_COWL', cowl.name)
print('V16_INTEGRATED_COWL_TRIANGLES', triangle_count(cowl))
print('V16_INTEGRATED_CHARACTER_TRIANGLES', total_triangles)
print('V16_INTEGRATED_VALIDATION', stats, weight_range, components, bounds)
print('WROTE', OUTPUT)
print('WROTE', REPORT)
