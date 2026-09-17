"""V16 organic helical scarf candidate.

This candidate replaces every concentric cowl/torus repair with one continuous
2.25-turn scarf strip.  The strip is a broad, flattened, closed cloth volume
with tapered overlapping ends, a continuously changing radius/height, and
strong front/back drape.  It therefore reads as one wrapped textile rather
than repeated circular hoses or annular plates.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_helical_scarf_candidate.blend'
REPORT = STAGING / 'v16_helical_scarf_report.json'

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

# Neutral charcoal retains the accepted 4K wool normal/ORM response while
# exposing the new fold silhouette clearly in the diagnostic lighting.
cloth_material = bpy.data.materials['MAT_CowlTop_SelectiveCharcoal_PBR_4K'].copy()
cloth_material.name = 'MAT_CowlWool_HelicalScarf_PBR_4K'


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


retired = []
for name in RETIRED_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.hide_render = True
    obj.hide_viewport = True
    obj.hide_set(True)
    obj['retired_by_v16_helical_scarf'] = True
    obj['part_category_before_retirement'] = obj.get('part_category')
    if 'part_category' in obj:
        del obj['part_category']
    obj['game_asset'] = False
    retired.append(name)


# Settle only the obsolete rear projected collar beneath the scarf.  A wide
# smooth falloff avoids the hard shoulder cliffs produced by an abrupt mask.
settled_donor_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.02) * 1.10) ** 2)
    inner_falloff = smoothstep((radial - 0.082) / 0.045)
    outer_falloff = 1.0 - smoothstep((radial - 0.275) / 0.130)
    rear_falloff = smoothstep((co.y - 0.005) / 0.075)
    height_falloff = smoothstep((co.z - 1.410) / 0.075)
    influence = inner_falloff * outer_falloff * rear_falloff * height_falloff
    if influence <= 0.002:
        continue
    target_z = (
        1.400
        + 0.019 * smoothstep((abs(co.x) - 0.205) / 0.145)
        + 0.004 * smoothstep((co.y - 0.16) / 0.12)
    )
    lowered = min(co.z, target_z)
    settled_donor_vertices.append((vertex.index, co.z, lowered, influence))
    co.z = co.z * (1.0 - influence) + lowered * influence
donor.data.update()
donor['v16_hidden_rear_collar_settled'] = True
donor['v16_hidden_rear_collar_settled_vertex_count'] = len(settled_donor_vertices)


def make_helical_scarf():
    turns = 2.25
    length_segments = 288
    width_segments = 12
    rows = width_segments + 1
    cols = length_segments + 1
    thickness = 0.009
    theta_start = 0.25 * math.pi  # tucked behind the character's right side

    vertices = []
    parameters = []
    for surface in (0, 1):
        radial_thickness = thickness * (0.5 if surface == 0 else -0.5)
        for length_index in range(cols):
            s = length_index / length_segments
            theta = theta_start + turns * 2.0 * math.pi * s
            cosine = math.cos(theta)
            sine = math.sin(theta)
            front = max(0.0, -sine)
            back = max(0.0, sine)
            side = abs(cosine)
            left = max(0.0, -cosine)

            # One continuous spiral: radius grows and height descends with s.
            # Different harmonics bend the center line away from a perfect
            # ellipse and make adjacent passes overlap at changing angles.
            base_rx = 0.132 + 0.120 * smoothstep(s)
            base_ry = 0.102 + 0.076 * smoothstep(s)
            radius_wave = (
                0.014 * math.sin(1.70 * theta + 1.15 * s + 0.35)
                + 0.007 * math.sin(4.30 * theta - 2.10 * s - 0.60)
            )
            center_x = (
                0.006 * math.sin(2.6 * math.pi * s)
                + (base_rx + radius_wave) * cosine
            )
            center_y = (
                0.010 + 0.014 * s
                + (base_ry + 0.72 * radius_wave) * sine
            )
            center_z = (
                1.582 - 0.094 * smoothstep(s)
                - (0.022 + 0.025 * s) * front ** 1.45
                + (0.013 - 0.006 * s) * back
                + 0.014 * s * side ** 1.7
                + 0.010 * math.sin(0.82 * theta + 3.3 * s + 0.5)
                + 0.005 * math.sin(3.1 * theta - 2.0 * s)
            )

            # Both ends taper and tuck below the neighboring pass, hiding the
            # caps while preserving an unmistakable spiral in exact top view.
            start_taper = 0.46 + 0.54 * smoothstep(s / 0.085)
            end_taper = 0.64 + 0.36 * smoothstep((1.0 - s) / 0.105)
            taper = min(start_taper, end_taper)
            end_tuck = smoothstep((s - 0.92) / 0.08)
            start_tuck = 1.0 - smoothstep(s / 0.07)
            center_x -= (0.018 * start_tuck + 0.013 * end_tuck) * cosine
            center_y -= (0.018 * start_tuck + 0.013 * end_tuck) * sine
            center_z -= 0.014 * start_tuck + 0.010 * end_tuck

            width = (0.076 + 0.040 * smoothstep(s)) * taper
            spread = 0.026 + 0.040 * smoothstep(s)
            # The outer pass hangs deeper at front/back; side sections stay
            # shorter and rest naturally over the trapezius.
            width += s * (0.028 * front ** 1.7 + 0.020 * back ** 1.7)

            for width_index in range(rows):
                u = width_index / width_segments  # upper/inner -> lower/outer
                eased = smoothstep(u)
                fold_envelope = math.sin(math.pi * u) ** 1.4
                broad_fold = fold_envelope * (
                    0.0055 * math.sin(2.0 * math.pi * u + 1.25 * math.sin(theta + 4.0 * s))
                    + 0.0030 * math.sin(4.0 * math.pi * u + 1.7 * theta - 1.2 * s)
                )
                radial_offset = spread * eased + broad_fold + radial_thickness
                x = center_x + radial_offset * cosine
                y = center_y + radial_offset * sine
                z = center_z + width * (0.5 - u)
                z -= eased * (0.006 + 0.009 * front + 0.005 * back) * s
                z += fold_envelope * (
                    0.0045 * math.sin(2.2 * theta + 5.2 * s)
                    + 0.0025 * math.sin(6.0 * theta - 1.4 * s)
                )
                if surface == 1:
                    z -= 0.0012
                vertices.append((x, y, z))
                parameters.append((surface, length_index, width_index, s, u, theta))

    surface_size = cols * rows
    faces = []
    for length_index in range(length_segments):
        for width_index in range(width_segments):
            a = length_index * rows + width_index
            b = (length_index + 1) * rows + width_index
            c = (length_index + 1) * rows + width_index + 1
            d = length_index * rows + width_index + 1
            faces.append((a, b, c, d))
            faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

    # Close the two long ribbon rims.
    for length_index in range(length_segments):
        a = length_index * rows
        b = (length_index + 1) * rows
        faces.append((a, surface_size + a, surface_size + b, b))
        a = length_index * rows + width_segments
        b = (length_index + 1) * rows + width_segments
        faces.append((a, b, surface_size + b, surface_size + a))

    # Close the tucked start/end caps.
    for width_index in range(width_segments):
        a = width_index
        b = width_index + 1
        faces.append((a, b, surface_size + b, surface_size + a))
        a = length_segments * rows + width_index
        b = length_segments * rows + width_index + 1
        faces.append((a, surface_size + a, surface_size + b, b))

    mesh = bpy.data.meshes.new('Mercenary_HelicalWrappedScarf_LOD0_Mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_outside(mesh)
    scarf = bpy.data.objects.new('Mercenary_HelicalWrappedScarf_LOD0', mesh)
    asset_collection.objects.link(scarf)
    mesh.materials.append(cloth_material)
    scarf['game_asset'] = True
    scarf['part_category'] = 'ClothedBody'
    scarf['intentional_layer'] = True
    scarf['source'] = 'V16 one-piece continuous 2.25-turn broad helical wool scarf'
    scarf['continuous_scarf_turns'] = turns
    scarf['not_torus_or_annular_plate'] = True
    scarf['replaces'] = ', '.join(RETIRED_NAMES)

    uv_layer = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            _surface, _li, _wi, s, u, _theta = parameters[vertex_index]
            uv_layer.data[loop_index].uv = (s * 7.0, u * 1.7)

    neck = scarf.vertex_groups.new(name='DEF-spine.006')
    upper = scarf.vertex_groups.new(name='DEF-spine.005')
    chest = scarf.vertex_groups.new(name='DEF-spine.004')
    left_arm = scarf.vertex_groups.new(name='DEF-upper_arm.L')
    right_arm = scarf.vertex_groups.new(name='DEF-upper_arm.R')
    for vertex, (_surface, _li, _wi, s, u, _theta) in zip(mesh.vertices, parameters):
        arm_weight = (
            0.18 * smoothstep((abs(vertex.co.x) - 0.235) / 0.110)
            * smoothstep((s - 0.58) / 0.42)
            * smoothstep((u - 0.48) / 0.52)
        )
        torso = 1.0 - arm_weight
        neck_factor = 0.76 * (1.0 - smoothstep(s)) + 0.14 * (1.0 - smoothstep(u))
        chest_factor = 0.10 + 0.52 * smoothstep(s) * smoothstep(u)
        upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
        norm = neck_factor + upper_factor + chest_factor
        neck_share = torso * neck_factor / norm
        upper_share = torso * upper_factor / norm
        chest_share = torso * chest_factor / norm
        neck.add([vertex.index], neck_share, 'REPLACE')
        upper.add([vertex.index], upper_share, 'REPLACE')
        chest.add([vertex.index], chest_share, 'REPLACE')
        if arm_weight > 0.0:
            (left_arm if vertex.co.x >= 0.0 else right_arm).add(
                [vertex.index], arm_weight, 'REPLACE'
            )

    # Round the four cloth borders without inflating the broad strip into a
    # hose.  The wide faces themselves remain flat and readable.
    for selected in bpy.context.selected_objects:
        selected.select_set(False)
    scarf.select_set(True)
    bpy.context.view_layer.objects.active = scarf
    bevel = scarf.modifiers.new('ClothEdgeSoftening', 'BEVEL')
    bevel.width = 0.0025
    bevel.segments = 2
    bevel.limit_method = 'ANGLE'
    bevel.angle_limit = math.radians(35.0)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    scarf.select_set(False)

    modifier = scarf.modifiers.new('RigifyDeform', 'ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    scarf.parent = rig
    scarf.matrix_parent_inverse = rig.matrix_world.inverted()
    return scarf


def make_hidden_foundation():
    """Compact low wool seam closure, fully beneath the wrapped scarf."""
    angular_segments = 104
    radial_segments = 9
    thickness = 0.007
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
                rx = 0.114 * (1.0 - eased) + 0.255 * eased
                ry = 0.088 * (1.0 - eased) + (0.170 + 0.040 * back - 0.020 * front) * eased
                x = rx * (1.0 + 0.018 * eased * math.sin(5.0 * theta + 0.4)) * cosine
                y = 0.012 + 0.024 * eased + ry * (1.0 + 0.014 * math.sin(7.0 * theta)) * sine
                inner_z = 1.446 + 0.006 * back
                outer_z = 1.397 + 0.022 * side + 0.006 * back - 0.004 * front
                z = inner_z * (1.0 - eased) + outer_z * eased
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

    mesh = bpy.data.meshes.new('Mercenary_HiddenScarfFoundation_LOD0_Mesh')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    recalc_outside(mesh)
    obj = bpy.data.objects.new('Mercenary_HiddenScarfFoundation_LOD0', mesh)
    asset_collection.objects.link(obj)
    mesh.materials.append(cloth_material)
    obj['game_asset'] = True
    obj['part_category'] = 'ClothedBody'
    obj['intentional_underlayer'] = True
    obj['source'] = 'V16 compact low wool seam closure below helical scarf'

    uv_layer = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (0.5 + co.x * 2.5, 0.5 + (co.y - 0.02) * 2.5)

    upper = obj.vertex_groups.new(name='DEF-spine.005')
    chest = obj.vertex_groups.new(name='DEF-spine.004')
    left_arm = obj.vertex_groups.new(name='DEF-upper_arm.L')
    right_arm = obj.vertex_groups.new(name='DEF-upper_arm.R')
    for vertex, (_surface, _ri, _ai, v, _theta) in zip(mesh.vertices, parameters):
        arm_weight = 0.18 * smoothstep((abs(vertex.co.x) - 0.210) / 0.090) * smoothstep((v - 0.55) / 0.45)
        torso = 1.0 - arm_weight
        upper_share = torso * (0.62 - 0.22 * smoothstep(v))
        chest_share = torso - upper_share
        upper.add([vertex.index], upper_share, 'REPLACE')
        chest.add([vertex.index], chest_share, 'REPLACE')
        if arm_weight > 0.0:
            (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')

    modifier = obj.modifiers.new('RigifyDeform', 'ARMATURE')
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    return obj


scarf = make_helical_scarf()
foundation = make_hidden_foundation()

new_validation = {}
for obj in (scarf, foundation):
    stats = manifold_stats(obj)
    components = component_count(obj)
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    weight_range = [min(sums), max(sums)]
    has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers)
    if stats['nonmanifold_edges'] != 0 or components != 1:
        raise RuntimeError(f'{obj.name} topology failed: {stats}, components={components}')
    if weight_range[0] < 0.99999 or weight_range[1] > 1.00001 or not has_rig:
        raise RuntimeError(f'{obj.name} Rigify failed: weights={weight_range}, rig={has_rig}')
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
    output = PREVIEWS / f'diagnostic_v16_helical_scarf_{key}.png'
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
    'continuous_scarf': scarf.name,
    'continuous_turns': scarf['continuous_scarf_turns'],
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

print('V16_HELICAL_SCARF', scarf.name)
print('V16_HELICAL_CHARACTER_TRIANGLES', total_triangles)
print('V16_HELICAL_VALIDATION', json.dumps(new_validation))
print('WROTE', OUTPUT)
print('WROTE', REPORT)
