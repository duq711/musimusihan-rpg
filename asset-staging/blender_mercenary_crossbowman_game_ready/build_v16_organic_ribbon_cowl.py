"""Build an organic three-wrap cowl candidate on the accepted v16j hair source.

The v15 upper-body repair stack is retired.  It is replaced by three broad,
flattened scarf wraps plus one low, hidden foundation cloth.  Each visible
wrap is a closed, manifold, sloped ribbon rather than a torus/tube.  Their
profiles, height, width, and radius vary independently around the neck so the
result reads as hand-draped fabric from top and upper three-quarter views.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_organic_ribbon_cowl_candidate.blend'
REPORT = STAGING / 'v16_organic_ribbon_cowl_report.json'

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
# The accepted neutral-charcoal cowl material already uses the same 4K wool
# normal/ORM maps but avoids the near-black albedo of the old projected side
# material.  Give this candidate an explicit single-material name.
cloth_material = bpy.data.materials['MAT_CowlTop_SelectiveCharcoal_PBR_4K'].copy()
cloth_material.name = 'MAT_CowlWool_OrganicRibbon_PBR_4K'


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


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
            connected = adjacency[current] & unseen
            unseen.difference_update(connected)
            stack.extend(connected)
    return count


retired = []
for name in RETIRED_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.hide_render = True
    obj.hide_viewport = True
    obj.hide_set(True)
    obj['retired_by_v16_organic_ribbon_cowl'] = True
    obj['part_category_before_retirement'] = obj.get('part_category')
    if 'part_category' in obj:
        del obj['part_category']
    obj['game_asset'] = False
    retired.append(name)

# The donor contains an obsolete projected rear collar/hood surface under the
# retired cowl.  Its torn peaks were physically protruding through every new
# scarf solution.  Settle only that occluded central-rear region beneath the
# new foundation cloth; sleeves, chest, face, and visible outer shoulders are
# untouched and all original skin weights/topology remain intact.
settled_donor_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.02) * 1.10) ** 2)
    if not (0.095 < radial < 0.345 and co.y > 0.025 and co.z > 1.425):
        continue
    target_z = (
        1.402
        + 0.018 * smoothstep((abs(co.x) - 0.205) / 0.120)
        + 0.004 * smoothstep((co.y - 0.16) / 0.12)
    )
    settled_donor_vertices.append((vertex.index, co.z, target_z))
    co.z = min(co.z, target_z)
donor.data.update()
donor['v16_hidden_rear_collar_settled'] = True
donor['v16_hidden_rear_collar_settled_vertex_count'] = len(settled_donor_vertices)


@dataclass(frozen=True)
class WrapSpec:
    name: str
    rx: float
    ry: float
    center_y: float
    center_z: float
    width: float
    spread_x: float
    spread_y: float
    thickness: float
    phase: float
    front_drop: float
    rear_lift: float
    side_lift: float
    left_lift: float
    rear_extension: float
    rear_width_add: float
    radius_wave: float
    segments: int = 120
    width_segments: int = 12


WRAPS = (
    # A broad shoulder-hugging lower pass.  The lower edge opens out over the
    # trapezius, while its upper edge remains tucked beneath the next wrap.
    WrapSpec(
        name='Mercenary_Cowl_RibbonLower_LOD0',
        rx=0.230, ry=0.160, center_y=0.016, center_z=1.493,
        width=0.105, spread_x=0.085, spread_y=0.060, thickness=0.010,
        phase=0.55, front_drop=0.040, rear_lift=-0.010, side_lift=0.020,
        left_lift=0.010, rear_extension=0.080, rear_width_add=0.090,
        radius_wave=0.014,
    ),
    # The middle wrap crosses the chest on a different diagonal and has a
    # noticeably smaller footprint, preventing a stack of equal rings.
    WrapSpec(
        name='Mercenary_Cowl_RibbonMiddle_LOD0',
        rx=0.185, ry=0.134, center_y=0.005, center_z=1.525,
        width=0.088, spread_x=0.047, spread_y=0.040, thickness=0.009,
        phase=2.15, front_drop=0.030, rear_lift=0.008, side_lift=0.012,
        left_lift=-0.006, rear_extension=0.018, rear_width_add=0.022,
        radius_wave=0.012,
    ),
    # A soft upper pass lies close to the neck and rises behind it like the
    # reference scarf.  It is deliberately offset left/rear and not circular.
    WrapSpec(
        name='Mercenary_Cowl_RibbonUpper_LOD0',
        rx=0.140, ry=0.105, center_y=0.010, center_z=1.563,
        width=0.067, spread_x=0.028, spread_y=0.025, thickness=0.008,
        phase=4.35, front_drop=0.040, rear_lift=0.018, side_lift=0.002,
        left_lift=0.006, rear_extension=0.010, rear_width_add=0.006,
        radius_wave=0.009,
    ),
)


def make_closed_ribbon(spec: WrapSpec):
    """Create a broad closed cloth band with sloped, irregular outer surface."""
    vertices = []
    parameters = []
    ring = spec.segments
    rows = spec.width_segments + 1

    for surface in (0, 1):
        # surface=0 is the visible outer face; surface=1 is the hidden inner.
        radial_thickness = spec.thickness * (0.5 if surface == 0 else -0.5)
        for row in range(rows):
            u = row / spec.width_segments  # 0=top/inner edge, 1=lower/outward edge
            eased = smoothstep(u)
            for angular_index in range(ring):
                theta = 2.0 * math.pi * angular_index / ring
                cosine = math.cos(theta)
                sine = math.sin(theta)
                front = max(0.0, -sine)
                back = max(0.0, sine)
                left = max(0.0, -cosine)

                # The center path is an irregular ellipse, not a mathematical
                # ring.  Each wrap uses a different harmonic and phase.
                angular_warp = (
                    spec.radius_wave * math.sin(3.0 * theta + spec.phase)
                    + 0.45 * spec.radius_wave * math.sin(7.0 * theta - 0.55 * spec.phase)
                )
                center_x = 0.007 * math.sin(spec.phase) + (spec.rx + angular_warp) * cosine
                center_y = (
                    spec.center_y
                    + 0.006 * math.cos(2.0 * theta + spec.phase)
                    + (spec.ry + 0.72 * angular_warp) * sine
                )

                # Lower parts of a real wrap splay outward.  This broad slope
                # gives the top camera actual cloth surface instead of a tube.
                side_bias = 0.86 + 0.14 * abs(cosine)
                outward_x = spec.spread_x * eased * side_bias
                outward_y = (
                    spec.spread_y * eased * (0.88 + 0.12 * back)
                    + spec.rear_extension * eased * back
                )

                # Two wide longitudinal folds travel through the ribbon.  The
                # relief is shallow and broad, so it reads as fabric rather
                # than another set of torus rings.
                fold_envelope = math.sin(math.pi * u) ** 1.35
                fold = fold_envelope * (
                    0.0065 * math.sin(2.0 * math.pi * u + 1.6 * math.sin(theta + spec.phase))
                    + 0.0035 * math.sin(4.0 * math.pi * u + 2.0 * theta - spec.phase)
                )
                seam_wobble = 0.0025 * math.sin(5.0 * theta + 0.8 * spec.phase) * math.sin(math.pi * u)
                radial_offset = fold + seam_wobble + radial_thickness

                x = center_x + (outward_x + radial_offset) * cosine
                y = center_y + (outward_y + radial_offset) * sine

                width_here = spec.width * (
                    1.0
                    + 0.075 * math.sin(2.0 * theta + spec.phase)
                    + 0.035 * math.sin(5.0 * theta - spec.phase)
                )
                width_here += spec.rear_width_add * back ** 1.7
                center_z = (
                    spec.center_z
                    - spec.front_drop * front ** 1.45
                    + spec.rear_lift * back ** 1.25
                    + spec.side_lift * abs(cosine) ** 1.65
                    + spec.left_lift * left
                    + 0.007 * math.sin(theta + spec.phase)
                    + 0.004 * math.sin(4.0 * theta - 0.7 * spec.phase)
                )
                z = center_z + width_here * (0.5 - u)
                # Cloth weight settles the outer/lower edge, particularly at
                # the front, and breaks the silhouette into organic arcs.
                z -= eased * (0.008 + 0.009 * front + 0.003 * back)
                z += fold_envelope * (
                    0.0055 * math.sin(3.0 * theta + spec.phase)
                    + 0.0030 * math.sin(8.0 * theta - spec.phase)
                )
                if surface == 1:
                    z -= 0.0015

                vertices.append((x, y, z))
                parameters.append((surface, row, angular_index, u, theta))

    surface_size = rows * ring
    faces = []
    for row in range(spec.width_segments):
        for angular_index in range(ring):
            nxt = (angular_index + 1) % ring
            a = row * ring + angular_index
            b = (row + 1) * ring + angular_index
            c = (row + 1) * ring + nxt
            d = row * ring + nxt
            faces.append((a, b, c, d))
            faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

    lower_start = spec.width_segments * ring
    for angular_index in range(ring):
        nxt = (angular_index + 1) % ring
        faces.append((
            lower_start + angular_index,
            surface_size + lower_start + angular_index,
            surface_size + lower_start + nxt,
            lower_start + nxt,
        ))
        faces.append((
            angular_index,
            nxt,
            surface_size + nxt,
            surface_size + angular_index,
        ))

    mesh = bpy.data.meshes.new(f'{spec.name}_Mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_outside(mesh)
    obj = bpy.data.objects.new(spec.name, mesh)
    asset_collection.objects.link(obj)
    mesh.materials.append(cloth_material)
    obj['game_asset'] = True
    obj['part_category'] = 'ClothedBody'
    obj['intentional_layer'] = True
    obj['source'] = 'V16 organic broad flattened scarf ribbon; procedural closed manifold'
    obj['ribbon_not_torus'] = True
    obj['replaces'] = ', '.join(RETIRED_NAMES)

    uv_layer = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            _surface, _row, angular_index, u, _theta = parameters[vertex_index]
            uv_layer.data[loop_index].uv = (angular_index / ring * 3.0, u * 1.6)

    groups = {
        'neck': obj.vertex_groups.new(name='DEF-spine.006'),
        'upper': obj.vertex_groups.new(name='DEF-spine.005'),
        'chest': obj.vertex_groups.new(name='DEF-spine.004'),
        'left_arm': obj.vertex_groups.new(name='DEF-upper_arm.L'),
        'right_arm': obj.vertex_groups.new(name='DEF-upper_arm.R'),
    }
    weight_sums = []
    for vertex, (_surface, _row, _a, u, _theta) in zip(mesh.vertices, parameters):
        is_lower = spec.name.endswith('Lower_LOD0')
        arm_cap = 0.22 if is_lower else (0.10 if spec.name.endswith('Middle_LOD0') else 0.0)
        arm_weight = arm_cap * smoothstep((abs(vertex.co.x) - 0.235) / 0.105) * smoothstep((u - 0.55) / 0.45)
        torso_weight = 1.0 - arm_weight
        if is_lower:
            neck_factor = 0.08 + 0.24 * (1.0 - smoothstep(u))
            chest_factor = 0.45 + 0.30 * smoothstep(u)
        elif spec.name.endswith('Middle_LOD0'):
            neck_factor = 0.28 + 0.38 * (1.0 - smoothstep(u))
            chest_factor = 0.12 + 0.28 * smoothstep(u)
        else:
            neck_factor = 0.72 + 0.20 * (1.0 - smoothstep(u))
            chest_factor = 0.02 + 0.06 * smoothstep(u)
        upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
        normalizer = neck_factor + upper_factor + chest_factor
        neck_share = torso_weight * neck_factor / normalizer
        upper_share = torso_weight * upper_factor / normalizer
        chest_share = torso_weight * chest_factor / normalizer
        groups['neck'].add([vertex.index], neck_share, 'REPLACE')
        groups['upper'].add([vertex.index], upper_share, 'REPLACE')
        groups['chest'].add([vertex.index], chest_share, 'REPLACE')
        if arm_weight > 0.0:
            (groups['left_arm'] if vertex.co.x >= 0.0 else groups['right_arm']).add(
                [vertex.index], arm_weight, 'REPLACE'
            )
        weight_sums.append(neck_share + upper_share + chest_share + arm_weight)

    # Round only the sharp top/bottom rims.  This preserves the broad cloth
    # faces while eliminating the cardboard-sheet silhouette.
    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new('ClothEdgeSoftening', 'BEVEL')
    bevel.width = 0.0030
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(35.0)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)

    modifier = obj.modifiers.new('RigifyDeform', 'ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()

    return obj, weight_sums


def make_hidden_foundation():
    """A low wool underlayer closes the damaged donor shoulder/neck boundary."""
    angular_segments = 120
    radial_segments = 10
    thickness = 0.008
    vertices = []
    parameters = []
    for surface in (0, 1):
        for radial_index in range(radial_segments + 1):
            v = radial_index / radial_segments
            eased = smoothstep(v)
            for angular_index in range(angular_segments):
                theta = 2.0 * math.pi * angular_index / angular_segments
                cosine = math.cos(theta)
                sine = math.sin(theta)
                front = max(0.0, -sine)
                back = max(0.0, sine)
                side = abs(cosine)
                rx = 0.118 * (1.0 - eased) + 0.245 * eased
                ry = 0.090 * (1.0 - eased) + (0.202 + 0.025 * back - 0.018 * front) * eased
                y_center = 0.010 + 0.035 * eased
                irregular = 1.0 + eased * (
                    0.022 * math.sin(5.0 * theta + 0.4)
                    + 0.012 * math.sin(9.0 * theta - 0.8)
                )
                x = rx * irregular * cosine
                y = y_center + ry * irregular * sine
                inner_z = 1.452 + 0.010 * back
                outer_z = 1.404 + 0.025 * side + 0.010 * back - 0.006 * front
                z = inner_z * (1.0 - eased) + outer_z * eased
                z += 0.003 * math.sin(4.0 * theta + 0.3) * math.sin(math.pi * v) ** 2
                if surface == 1:
                    z -= thickness
                vertices.append((x, y, z))
                parameters.append((surface, radial_index, angular_index, v, theta))

    ring = angular_segments
    surface_size = (radial_segments + 1) * ring
    faces = []
    for radial_index in range(radial_segments):
        for angular_index in range(ring):
            nxt = (angular_index + 1) % ring
            a = radial_index * ring + angular_index
            b = (radial_index + 1) * ring + angular_index
            c = (radial_index + 1) * ring + nxt
            d = radial_index * ring + nxt
            faces.append((a, b, c, d))
            faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))
    outer_start = radial_segments * ring
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

    mesh = bpy.data.meshes.new('Mercenary_HiddenCowlFoundation_LOD0_Mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_outside(mesh)
    obj = bpy.data.objects.new('Mercenary_HiddenCowlFoundation_LOD0', mesh)
    asset_collection.objects.link(obj)
    mesh.materials.append(cloth_material)
    obj['game_asset'] = True
    obj['part_category'] = 'ClothedBody'
    obj['intentional_underlayer'] = True
    obj['source'] = 'V16 compact shoulder seam closure hidden under organic ribbon wraps'

    uv_layer = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (0.5 + co.x * 2.4, 0.5 + (co.y - 0.02) * 2.4)

    spine_upper = obj.vertex_groups.new(name='DEF-spine.005')
    spine_chest = obj.vertex_groups.new(name='DEF-spine.004')
    left_arm = obj.vertex_groups.new(name='DEF-upper_arm.L')
    right_arm = obj.vertex_groups.new(name='DEF-upper_arm.R')
    weight_sums = []
    for vertex, (_surface, _r, _a, v, _theta) in zip(mesh.vertices, parameters):
        arm_weight = 0.24 * smoothstep((abs(vertex.co.x) - 0.245) / 0.115) * smoothstep((v - 0.55) / 0.45)
        torso_weight = 1.0 - arm_weight
        upper_share = torso_weight * (0.58 - 0.25 * smoothstep(v))
        chest_share = torso_weight - upper_share
        spine_upper.add([vertex.index], upper_share, 'REPLACE')
        spine_chest.add([vertex.index], chest_share, 'REPLACE')
        if arm_weight > 0.0:
            (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')
        weight_sums.append(upper_share + chest_share + arm_weight)

    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new('FoundationEdgeSoftening', 'BEVEL')
    bevel.width = 0.0020
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(35.0)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)

    modifier = obj.modifiers.new('RigifyDeform', 'ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    return obj, weight_sums


ribbon_objects = []
weight_ranges = {}
for spec in WRAPS:
    obj, sums = make_closed_ribbon(spec)
    ribbon_objects.append(obj)
    weight_ranges[obj.name] = [min(sums), max(sums)]

foundation, foundation_sums = make_hidden_foundation()
weight_ranges[foundation.name] = [min(foundation_sums), max(foundation_sums)]

new_objects = [foundation] + ribbon_objects
new_validation = {}
for obj in new_objects:
    stats = manifold_stats(obj)
    components = component_count(obj)
    has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers)
    actual_weight_sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    weight_range = [min(actual_weight_sums), max(actual_weight_sums)]
    if stats['nonmanifold_edges'] != 0:
        raise RuntimeError(f'{obj.name} is not manifold: {stats}')
    if components != 1:
        raise RuntimeError(f'{obj.name} must be one connected component, got {components}')
    if weight_range[0] < 0.999999 or weight_range[1] > 1.000001 or not has_rig:
        raise RuntimeError(f'{obj.name} Rigify validation failed: weights={weight_range} rig={has_rig}')
    new_validation[obj.name] = {
        'vertices': len(obj.data.vertices),
        'triangles': triangle_count(obj),
        'components': components,
        'manifold': stats,
        'weight_sum_range': weight_range,
        'rigify_modifier': has_rig,
        'material': obj.data.materials[0].name,
        'bounds': {
            'min': [min(v.co[i] for v in obj.data.vertices) for i in range(3)],
            'max': [max(v.co[i] for v in obj.data.vertices) for i in range(3)],
        },
    }

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
    output = PREVIEWS / f'diagnostic_v16_organic_ribbon_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render(
        'top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.50),
        ortho_scale=0.96, resolution=(1200, 900),
    ),
    'failure_view': render(
        'failure_view', (0.57, -0.57, 5.58), (0.0, 0.055, 1.03),
        lens=78, resolution=(1400, 1000),
    ),
    'upper_three_quarter': render(
        'upper_three_quarter', (1.15, -1.55, 2.05), (0.0, 0.0, 1.50),
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
    'retired_objects': retired,
    'settled_donor_rear_collar_vertices': len(settled_donor_vertices),
    'visible_ribbons': [obj.name for obj in ribbon_objects],
    'hidden_foundation': foundation.name,
    'single_cowl_material': cloth_material.name,
    'new_object_validation': new_validation,
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
look_at(camera, (0.0, 0.0, 1.50))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print('V16_ORGANIC_RIBBONS', [obj.name for obj in ribbon_objects])
print('V16_ORGANIC_FOUNDATION', foundation.name)
print('V16_ORGANIC_CHARACTER_TRIANGLES', total_triangles)
print('V16_ORGANIC_VALIDATION', json.dumps(new_validation))
print('WROTE', OUTPUT)
print('WROTE', REPORT)
