"""Compact one-piece wound scarf for v16.

The garment is a single broad vertical cloth strip wound a little over twice
around the neck.  Successive passes overlap down the chest and sit slightly
farther outward, so the top view sees only a thin irregular cloth edge instead
of an annular cap.  The surface carries diagonal valleys and localized bunches;
there are no torus tubes, closed circular shelves, or shoulder-width plates.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_single_wound_scarf_candidate.blend'
REPORT = STAGING / 'v16_single_wound_scarf_report.json'

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
cloth_material.name = 'MAT_CowlWool_SingleWoundScarf_PBR_4K'
gambeson_material = bpy.data.materials['MAT_Gambeson_Side_PBR_4K']


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angular_delta(a, b):
    return (a - b + math.pi) % (2.0 * math.pi) - math.pi


def localized(theta, center, sigma):
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
    return sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)


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
    obj['retired_by_v16_single_wound_scarf'] = True
    obj['part_category_before_retirement'] = obj.get('part_category')
    if 'part_category' in obj:
        del obj['part_category']
    obj['game_asset'] = False
    retired.append(name)


# Remove only the old rear projected collar from the volume occupied by the
# new fabric bundle.  The broad fade prevents hard shoulder cliffs.
settled_donor_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.02) * 1.10) ** 2)
    influence = (
        smoothstep((radial - 0.080) / 0.045)
        * (1.0 - smoothstep((radial - 0.245) / 0.170))
        * smoothstep((co.y + 0.005) / 0.085)
        * smoothstep((co.z - 1.400) / 0.085)
    )
    if influence <= 0.002:
        continue
    target_z = 1.392 + 0.020 * smoothstep((abs(co.x) - 0.185) / 0.165)
    lowered = min(co.z, target_z)
    settled_donor_vertices.append((vertex.index, co.z, lowered, influence))
    co.z = co.z * (1.0 - influence) + lowered * influence
donor.data.update()
donor['v16_hidden_rear_collar_settled'] = True
donor['v16_hidden_rear_collar_settled_vertex_count'] = len(settled_donor_vertices)


LENGTH_SEGMENTS = 240
WIDTH_SEGMENTS = 16
LENGTH_ROWS = LENGTH_SEGMENTS + 1
WIDTH_ROWS = WIDTH_SEGMENTS + 1
START_THETA = 0.20 * math.pi
TURNS = 1.95
THICKNESS = 0.0045


def scarf_point(s, v, surface):
    """Point on a broad vertical strip; surface 0 is outward, 1 inward."""
    theta = START_THETA + TURNS * 2.0 * math.pi * s
    cosine = math.cos(theta)
    sine = math.sin(theta)
    turn = TURNS * s
    front = max(0.0, -sine)
    back = max(0.0, sine)
    left = max(0.0, -cosine)
    side_left = localized(theta, math.pi, 0.48)
    side_right = localized(theta, 0.0, 0.48)
    shoulder_drape = side_left + side_right
    end_taper = smoothstep(s / 0.075) * smoothstep((1.0 - s) / 0.075)

    # Each later/lower pass sits just outside the previous pass.  This makes
    # genuine cloth overlap without producing stacked horizontal shelves.
    layer_out = 0.0042 * turn
    rx = 0.151 + layer_out
    ry = 0.116 + 0.78 * layer_out
    rx += 0.008 * math.sin(1.65 * theta + 0.30) + 0.004 * math.sin(4.7 * theta)
    ry += 0.006 * math.sin(1.35 * theta - 0.55) + 0.003 * math.sin(5.1 * theta)

    # Only the lowest wrap grows a localized shoulder drape.  The rest stays
    # compact and vertical around the neck (|x| remains below about 0.27 m).
    lower = smoothstep((s - 0.66) / 0.34)
    left_drape = localized(theta, 0.78 * math.pi, 0.33)
    rear_drape = localized(theta, 0.48 * math.pi, 0.32)
    front_drop = localized(theta, 1.49 * math.pi, 0.42)
    rx += lower * (
        0.043 * left_drape
        + 0.018 * rear_drape
    )
    ry += lower * (0.020 * rear_drape + 0.026 * front_drop)
    # Both loose ends finish behind the right shoulder and are tucked inward.
    rx -= 0.020 * (1.0 - end_taper)
    ry -= 0.014 * (1.0 - end_taper)

    # Diagonal folds live in the strip surface itself.  Their paths wander
    # across the width so they cannot read as circular rings.
    crease_a = 0.25 + 0.13 * math.sin(0.72 * theta + 0.35)
    crease_b = 0.69 + 0.12 * math.sin(0.91 * theta - 0.60)
    valley_a = math.exp(-((v - crease_a) / 0.065) ** 2)
    valley_b = math.exp(-((v - crease_b) / 0.075) ** 2)
    ridge_a = math.exp(-((v - crease_a - 0.095) / 0.080) ** 2)
    ridge_b = math.exp(-((v - crease_b + 0.105) / 0.085) ** 2)
    bunch = (
        0.010 * localized(theta, 1.30 * math.pi + 0.20 * math.sin(2.0 * math.pi * s), 0.25)
        + 0.008 * localized(theta, 0.83 * math.pi - 0.28 * (v - 0.5), 0.22)
        + 0.006 * localized(theta, 0.12 * math.pi + 0.25 * (v - 0.5), 0.19)
    )
    radial_fold = (
        -0.013 * valley_a - 0.011 * valley_b
        + 0.009 * ridge_a + 0.008 * ridge_b
        + bunch
        + 0.0045 * math.sin(3.7 * theta + 5.0 * v)
        + 0.0025 * math.sin(8.3 * theta - 4.0 * v)
    )

    radial = radial_fold + (THICKNESS * 0.5 if surface == 0 else -THICKNESS * 0.5)
    x = (rx + radial) * cosine - 0.003 * lower
    y = 0.012 + 0.008 * lower + (ry + 0.76 * radial) * sine

    # The broad strip descends only 6.2 cm per turn while remaining about
    # 11 cm wide, so successive passes visibly overlap like a wrapped scarf.
    mid_z = 1.515 - 0.067 * turn
    # Non-periodic long-wave sag makes the visible overlaps slope differently
    # on each pass instead of forming repeated horizontal circles.
    mid_z += 0.021 * math.sin(0.63 * theta + 0.45) + 0.009 * math.sin(1.37 * theta - 0.20)
    width = 0.116 + 0.016 * lower + 0.009 * math.sin(0.77 * theta + 0.25)
    width *= 0.38 + 0.62 * end_taper
    z = mid_z + (v - 0.5) * width
    edge = abs(2.0 * v - 1.0) ** 3
    z += edge * (0.014 * math.sin(0.92 * theta + 0.8) + 0.006 * math.sin(2.4 * theta))
    z += 0.009 * math.sin(math.pi * v) * math.sin(1.65 * theta + 1.1)
    z -= lower * front_drop * (0.012 + 0.010 * (1.0 - v))
    z += (1.0 - lower) * back * 0.005
    return x, y, z, theta


vertices = []
parameters = []
for surface in (0, 1):
    for length_index in range(LENGTH_ROWS):
        s = length_index / LENGTH_SEGMENTS
        for width_index in range(WIDTH_ROWS):
            v = width_index / WIDTH_SEGMENTS
            x, y, z, theta = scarf_point(s, v, surface)
            vertices.append((x, y, z))
            parameters.append((surface, length_index, width_index, s, v, theta))

surface_size = LENGTH_ROWS * WIDTH_ROWS
faces = []
for length_index in range(LENGTH_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        a = length_index * WIDTH_ROWS + width_index
        b = (length_index + 1) * WIDTH_ROWS + width_index
        c = (length_index + 1) * WIDTH_ROWS + width_index + 1
        d = length_index * WIDTH_ROWS + width_index + 1
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

# Close the entire perimeter of the one continuous cloth strip.
for length_index in range(LENGTH_SEGMENTS):
    a = length_index * WIDTH_ROWS
    b = (length_index + 1) * WIDTH_ROWS
    faces.append((a, surface_size + a, surface_size + b, b))
    a = length_index * WIDTH_ROWS + WIDTH_SEGMENTS
    b = (length_index + 1) * WIDTH_ROWS + WIDTH_SEGMENTS
    faces.append((a, b, surface_size + b, surface_size + a))
for width_index in range(WIDTH_SEGMENTS):
    a = width_index
    b = width_index + 1
    faces.append((a, b, surface_size + b, surface_size + a))
    a = LENGTH_SEGMENTS * WIDTH_ROWS + width_index
    b = a + 1
    faces.append((a, surface_size + a, surface_size + b, b))

mesh = bpy.data.meshes.new('Mercenary_SingleWoundScarf_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
cowl = bpy.data.objects.new('Mercenary_SingleWoundScarf_LOD0', mesh)
asset_collection.objects.link(cowl)
mesh.materials.append(cloth_material)
cowl['game_asset'] = True
cowl['part_category'] = 'ClothedBody'
cowl['intentional_layer'] = True
cowl['source'] = 'V16 one-piece broad vertical wool strip wound 2.1 turns with overlapping passes'
cowl['no_concentric_folds'] = True
cowl['no_torus_or_poncho_plate'] = True
cowl['open_top_without_annular_cap'] = True
cowl['replaces'] = ', '.join(RETIRED_NAMES)

uv_layer = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vi = mesh.loops[loop_index].vertex_index
        _surface, _li, _wi, s, v, _theta = parameters[vi]
        uv_layer.data[loop_index].uv = (s * TURNS * 2.3, v * 1.8)

neck = cowl.vertex_groups.new(name='DEF-spine.006')
upper = cowl.vertex_groups.new(name='DEF-spine.005')
chest = cowl.vertex_groups.new(name='DEF-spine.004')
left_arm = cowl.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = cowl.vertex_groups.new(name='DEF-upper_arm.R')
for vertex, (_surface, _li, _wi, s, v, _theta) in zip(mesh.vertices, parameters):
    lower = smoothstep((s - 0.60) / 0.40)
    arm_weight = 0.10 * smoothstep((abs(vertex.co.x) - 0.220) / 0.055) * lower
    torso = 1.0 - arm_weight
    vertical = clamp((1.555 - vertex.co.z) / 0.245)
    neck_factor = 0.18 + 0.68 * (1.0 - smoothstep(vertical / 0.78))
    chest_factor = 0.08 + 0.46 * smoothstep((vertical - 0.30) / 0.70)
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
bevel.width = 0.0012
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


# Compact under-scarf seam closures.  These are two upright curved fabric
# curtains following the left and right shoulder openings.  They have only a
# thin radial thickness, so the top view sees short arcs rather than pads.
CLOSURE_HEIGHT_SEGMENTS = 14
CLOSURE_ANGULAR_SEGMENTS = 28
CLOSURE_HROWS = CLOSURE_HEIGHT_SEGMENTS + 1
CLOSURE_AROWS = CLOSURE_ANGULAR_SEGMENTS + 1
closure_vertices = []
closure_parameters = []
closure_faces = []

for patch_index, center_theta in enumerate((0.0, math.pi)):
    patch_base = len(closure_vertices)
    for surface in (0, 1):
        radial_offset = 0.0035 if surface == 0 else -0.0035
        for height_index in range(CLOSURE_HROWS):
            t = height_index / CLOSURE_HEIGHT_SEGMENTS
            eased = smoothstep(t)
            for angular_index in range(CLOSURE_AROWS):
                qn = angular_index / CLOSURE_ANGULAR_SEGMENTS
                q = (qn - 0.5) * 1.30
                theta = center_theta + q
                radius = 0.270 - 0.040 * eased
                radius += 0.005 * math.sin(2.8 * q + 2.1 * t + 0.5 * patch_index) * math.sin(math.pi * t)
                radius += radial_offset
                x = radius * math.cos(theta)
                y = 0.010 + 0.76 * radius * math.sin(theta)
                z = 1.325 + 0.178 * t
                z += 0.007 * math.cos(math.pi * q / 1.30) * math.sin(math.pi * t)
                z += 0.003 * math.sin(4.2 * q + 2.0 * t)
                closure_vertices.append((x, y, z))
                closure_parameters.append((patch_index, surface, t, qn))

    patch_surface_size = CLOSURE_HROWS * CLOSURE_AROWS
    for height_index in range(CLOSURE_HEIGHT_SEGMENTS):
        for angular_index in range(CLOSURE_ANGULAR_SEGMENTS):
            a = patch_base + height_index * CLOSURE_AROWS + angular_index
            b = patch_base + (height_index + 1) * CLOSURE_AROWS + angular_index
            c = b + 1
            d = a + 1
            closure_faces.append((a, b, c, d))
            closure_faces.append((
                a + patch_surface_size,
                d + patch_surface_size,
                c + patch_surface_size,
                b + patch_surface_size,
            ))

    # Close lower/upper and front/rear perimeter edges of each curved curtain.
    for angular_index in range(CLOSURE_ANGULAR_SEGMENTS):
        a = patch_base + angular_index
        b = a + 1
        closure_faces.append((a, b, b + patch_surface_size, a + patch_surface_size))
        a = patch_base + CLOSURE_HEIGHT_SEGMENTS * CLOSURE_AROWS + angular_index
        b = a + 1
        closure_faces.append((a, a + patch_surface_size, b + patch_surface_size, b))
    for height_index in range(CLOSURE_HEIGHT_SEGMENTS):
        a = patch_base + height_index * CLOSURE_AROWS
        b = patch_base + (height_index + 1) * CLOSURE_AROWS
        closure_faces.append((a, a + patch_surface_size, b + patch_surface_size, b))
        a = patch_base + height_index * CLOSURE_AROWS + CLOSURE_ANGULAR_SEGMENTS
        b = patch_base + (height_index + 1) * CLOSURE_AROWS + CLOSURE_ANGULAR_SEGMENTS
        closure_faces.append((a, b, b + patch_surface_size, a + patch_surface_size))

closure_mesh = bpy.data.meshes.new('Mercenary_ScarfShoulderSeamClosure_LOD0_Mesh')
closure_mesh.from_pydata(closure_vertices, [], closure_faces)
closure_mesh.update()
recalc_outside(closure_mesh)
closure = bpy.data.objects.new('Mercenary_ScarfShoulderSeamClosure_LOD0', closure_mesh)
asset_collection.objects.link(closure)
closure_mesh.materials.append(gambeson_material)
closure['game_asset'] = True
closure['part_category'] = 'ClothedBody'
closure['intentional_layer'] = True
closure['source'] = 'V16 compact localized quilted gambeson shoulder seam closures under wound scarf'
closure['not_annular'] = True

closure_uv = closure_mesh.uv_layers.new(name='UVMap')
for polygon in closure_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vi = closure_mesh.loops[loop_index].vertex_index
        patch_index, _surface, t, qn = closure_parameters[vi]
        closure_uv.data[loop_index].uv = (patch_index * 1.15 + qn, t)

closure_chest = closure.vertex_groups.new(name='DEF-spine.004')
closure_upper = closure.vertex_groups.new(name='DEF-spine.005')
closure_left = closure.vertex_groups.new(name='DEF-upper_arm.L')
closure_right = closure.vertex_groups.new(name='DEF-upper_arm.R')
for vertex, (patch_index, _surface, t, _qn) in zip(closure_mesh.vertices, closure_parameters):
    arm_share = 0.18 + 0.62 * smoothstep((t - 0.22) / 0.78)
    upper_share = 0.20 * (1.0 - arm_share)
    chest_share = 1.0 - arm_share - upper_share
    closure_chest.add([vertex.index], chest_share, 'REPLACE')
    closure_upper.add([vertex.index], upper_share, 'REPLACE')
    (closure_left if patch_index == 0 else closure_right).add([vertex.index], arm_share, 'REPLACE')

for selected in bpy.context.selected_objects:
    selected.select_set(False)
closure.select_set(True)
bpy.context.view_layer.objects.active = closure
closure_bevel = closure.modifiers.new('ClothPanelEdgeSoftening', 'BEVEL')
closure_bevel.width = 0.0012
closure_bevel.segments = 2
closure_bevel.limit_method = 'ANGLE'
closure_bevel.angle_limit = math.radians(35.0)
bpy.ops.object.modifier_apply(modifier=closure_bevel.name)
closure.select_set(False)
closure_armature = closure.modifiers.new('RigifyDeform', 'ARMATURE')
closure_armature.object = rig
closure_armature.use_deform_preserve_volume = True
closure.parent = rig
closure.matrix_parent_inverse = rig.matrix_world.inverted()

stats = manifold_stats(cowl)
components = component_count(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
weight_range = [min(weight_sums), max(weight_sums)]
has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in cowl.modifiers)
if stats['nonmanifold_edges'] != 0 or components != 1:
    raise RuntimeError(f'Cowl topology failed: {stats}, components={components}')
if weight_range[0] < 0.99999 or weight_range[1] > 1.00001 or not has_rig:
    raise RuntimeError(f'Cowl Rigify failed: weights={weight_range}, rig={has_rig}')

closure_stats = manifold_stats(closure)
closure_components = component_count(closure)
closure_weight_sums = [sum(item.weight for item in vertex.groups) for vertex in closure.data.vertices]
closure_weight_range = [min(closure_weight_sums), max(closure_weight_sums)]
closure_has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in closure.modifiers)
if closure_stats['nonmanifold_edges'] != 0 or closure_components != 2:
    raise RuntimeError(f'Closure topology failed: {closure_stats}, components={closure_components}')
if closure_weight_range[0] < 0.99999 or closure_weight_range[1] > 1.00001 or not closure_has_rig:
    raise RuntimeError(f'Closure Rigify failed: weights={closure_weight_range}, rig={closure_has_rig}')

character_meshes = [obj for obj in scene.objects if obj.type == 'MESH' and obj.get('part_category') is not None and not obj.hide_render]
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
    output = PREVIEWS / f'diagnostic_v16_single_wound_scarf_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render('top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.50), ortho_scale=0.88, resolution=(1200, 900)),
    'failure_view': render('failure_view', (0.57, -0.57, 5.58), (0.0, 0.055, 1.03), lens=78, resolution=(1400, 1000)),
    'upper_three_quarter': render('upper_three_quarter', (1.15, -1.55, 2.05), (0.0, 0.0, 1.49), lens=76, resolution=(1200, 1000)),
    'front': render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06),
    'back': render('back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06),
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
    'single_wound_scarf': cowl.name,
    'shoulder_seam_closure': closure.name,
    'single_cowl_material': cloth_material.name,
    'closure_material': gambeson_material.name,
    'cowl_vertices': len(cowl.data.vertices),
    'cowl_triangles': triangle_count(cowl),
    'cowl_components': components,
    'cowl_manifold': stats,
    'cowl_weight_sum_range': weight_range,
    'cowl_rigify_modifier': has_rig,
    'cowl_bounds': bounds,
    'closure_triangles': triangle_count(closure),
    'closure_components': closure_components,
    'closure_manifold': closure_stats,
    'closure_weight_sum_range': closure_weight_range,
    'closure_rigify_modifier': closure_has_rig,
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

print('V16_SINGLE_WOUND_SCARF', cowl.name)
print('V16_SINGLE_WOUND_SCARF_TRIANGLES', triangle_count(cowl))
print('V16_SINGLE_WOUND_CLOSURE_TRIANGLES', triangle_count(closure))
print('V16_SINGLE_WOUND_CHARACTER_TRIANGLES', total_triangles)
print('V16_SINGLE_WOUND_VALIDATION', stats, weight_range, components, bounds)
print('V16_SINGLE_WOUND_CLOSURE_VALIDATION', closure_stats, closure_weight_range, closure_components)
print('WROTE', OUTPUT)
print('WROTE', REPORT)
