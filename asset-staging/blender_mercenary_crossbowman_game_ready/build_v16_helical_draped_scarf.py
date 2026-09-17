"""Independent v16 candidate: one continuous wrapped scarf ribbon.

This replaces the six detached circular shells with one broad, capped ribbon
that winds a little more than once around the neck.  Its upper edge hugs the
neck, its lower edge fans over the chest/shoulders, and the two ends finish at
different heights near the front.  The helical topology makes the visible
folds one piece of cloth rather than stacked torus hoses.
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

OLD_UPPER = (
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
collection = donor.users_collection[0]

removed = []
removed_triangles = 0
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if not obj:
        continue
    removed_triangles += sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    removed.append(name)


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def angle_delta(a, b):
    return (a - b + math.pi) % (2.0 * math.pi) - math.pi


def angle_gaussian(theta, center, width):
    return math.exp(-0.5 * (angle_delta(theta, center) / width) ** 2)


LONG_SEGMENTS = 288
WIDTH_SEGMENTS = 24
THICKNESS = 0.0075
THETA_START = -2.25
THETA_END = -0.89 + 2.0 * math.pi
TURN_SPAN = THETA_END - THETA_START

# A few local creases interrupt the main wrap and prevent an even, synthetic
# ring.  Their phases differ between the upper and lower width of the scarf.
CREASES = (
    (-2.00, 0.18, 0.008),
    (-1.42, 0.22, -0.006),
    (-0.72, 0.16, 0.010),
    (0.18, 0.21, -0.006),
    (0.92, 0.18, 0.009),
    (1.58, 0.24, -0.006),
    (2.30, 0.19, 0.009),
)


def scarf_point(u, width_parameter, surface):
    theta = THETA_START + TURN_SPAN * u
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)

    start_end = 1.0 - smoothstep(u / 0.14)
    finish_end = 1.0 - smoothstep((1.0 - u) / 0.14)
    end_strength = max(start_end, finish_end)

    # The band is one shallow helix, so the overlapping front portion has a
    # natural vertical separation.  Both capped ends relax downward and flare
    # slightly forward like the ends of a real wrapped scarf.
    center_z = 1.485 + 0.045 * u + 0.010 * back
    center_z -= 0.030 * start_end + 0.036 * finish_end
    center_y = 0.012 - 0.038 * end_strength

    # A broad sloped cross-section: the top edge hugs the neck while the lower
    # edge fans over the upper chest and shoulders.  It is a cloth ribbon, not
    # a round tube.
    radial = 0.195 - 0.160 * width_parameter
    radial += 0.028 * end_strength * (0.55 - width_parameter)
    radial += 0.006 * math.sin(5.0 * theta + 3.0 * width_parameter + 1.2 * u)
    radial += 0.003 * math.sin(11.0 * theta - 2.0 * width_parameter)

    width_height = 0.130 * width_parameter
    z = center_z + width_height
    lower = smoothstep((-width_parameter + 0.5) / 1.0)
    z -= 0.014 * front * lower
    z += 0.008 * back * lower

    # Swirling cloth compression crosses the band diagonally, which breaks up
    # horizontal contour lines without introducing disconnected geometry.
    width_envelope = math.sin(math.pi * (width_parameter + 0.5)) ** 1.35
    z += 0.0075 * math.sin(5.2 * theta + 2.8 * width_parameter + 1.4 * u) * width_envelope
    z += 0.0030 * math.sin(12.0 * theta - 4.1 * width_parameter) * width_envelope
    for center, spread, amplitude in CREASES:
        z += amplitude * angle_gaussian(theta, center, spread) * width_envelope

    # Irregular hem and two asymmetric front ends.
    radial += 0.010 * lower * math.sin(3.0 * theta + 0.8)
    radial += 0.007 * lower * math.sin(7.0 * theta - 0.4)
    x = cosine * radial
    y = center_y + sine * radial * 0.73

    # The cloth thickness follows the radial normal closely enough for this
    # sloped band and keeps both visible sides consistently separated.
    offset = (0.5 if surface == 0 else -0.5) * THICKNESS
    x += cosine * offset
    y += sine * offset * 0.73

    # A small tangential drift stops the two ends from lining up mechanically.
    tangent = 0.006 * math.sin(3.0 * math.pi * u) * width_envelope
    x -= sine * tangent
    y += cosine * tangent * 0.72
    return (x, y, z)


vertices = []
parameters = []
for surface in range(2):
    for long_index in range(LONG_SEGMENTS + 1):
        u = long_index / LONG_SEGMENTS
        for width_index in range(WIDTH_SEGMENTS + 1):
            width_parameter = width_index / WIDTH_SEGMENTS - 0.5
            vertices.append(scarf_point(u, width_parameter, surface))
            parameters.append((surface, long_index, width_index, u, width_parameter))


PER_SURFACE = (LONG_SEGMENTS + 1) * (WIDTH_SEGMENTS + 1)


def index(surface, long_index, width_index):
    return (
        surface * PER_SURFACE
        + long_index * (WIDTH_SEGMENTS + 1)
        + width_index
    )


faces = []
for long_index in range(LONG_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        faces.append((
            index(0, long_index, width_index),
            index(0, long_index + 1, width_index),
            index(0, long_index + 1, width_index + 1),
            index(0, long_index, width_index + 1),
        ))
        faces.append((
            index(1, long_index, width_index),
            index(1, long_index, width_index + 1),
            index(1, long_index + 1, width_index + 1),
            index(1, long_index + 1, width_index),
        ))

# Close the upper and lower long hems.
for long_index in range(LONG_SEGMENTS):
    for width_index in (0, WIDTH_SEGMENTS):
        a = index(0, long_index, width_index)
        b = index(0, long_index + 1, width_index)
        c = index(1, long_index + 1, width_index)
        d = index(1, long_index, width_index)
        faces.append((a, b, c, d) if width_index == WIDTH_SEGMENTS else (d, c, b, a))

# Cap both visible scarf ends.
for long_index in (0, LONG_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        a = index(0, long_index, width_index)
        b = index(0, long_index, width_index + 1)
        c = index(1, long_index, width_index + 1)
        d = index(1, long_index, width_index)
        faces.append((a, b, c, d) if long_index == LONG_SEGMENTS else (d, c, b, a))


mesh = bpy.data.meshes.new('Mercenary_HelicalDrapedScarf_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

scarf = bpy.data.objects.new('Mercenary_HelicalDrapedScarf_LOD0', mesh)
collection.objects.link(scarf)
scarf['game_asset'] = True
scarf['part_category'] = 'ClothedBody'
scarf['intentional_layer'] = True
scarf['source'] = 'V16 one-piece helical scarf ribbon replacing six detached cowl rings'
scarf['topology'] = 'single connected closed ribbon with two capped ends'

source_material = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if source_material is None:
    source_material = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = source_material.copy()
material.name = 'MAT_HelicalScarf_Wool_PBR_4K'
material.use_backface_culling = False
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % PER_SURFACE
        long_index = within // (WIDTH_SEGMENTS + 1)
        width_index = within % (WIDTH_SEGMENTS + 1)
        uv.data[loop_index].uv = (
            long_index / LONG_SEGMENTS * 5.0,
            width_index / WIDTH_SEGMENTS * 1.8,
        )

# Normalized torso-dominant Rigify weights with restrained arm influence only
# along the flared lower side corners.
spine_upper = scarf.vertex_groups.new(name='DEF-spine.005')
spine_chest = scarf.vertex_groups.new(name='DEF-spine.004')
left_arm = scarf.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = scarf.vertex_groups.new(name='DEF-upper_arm.R')
weight_sums = []
arm_weights = []
for vertex, (_surface, _li, _wi, _u, width_parameter) in zip(mesh.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.235) / 0.095)
    lower_gate = smoothstep((-width_parameter + 0.10) / 0.60)
    arm_weight = 0.24 * side_gate * lower_gate
    torso_weight = 1.0 - arm_weight
    upper_share = torso_weight * (0.68 + 0.16 * width_parameter)
    chest_share = torso_weight - upper_share
    spine_upper.add([vertex.index], upper_share, 'REPLACE')
    spine_chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add(
            [vertex.index], arm_weight, 'REPLACE'
        )
    weight_sums.append(upper_share + chest_share + arm_weight)
    arm_weights.append(arm_weight)

modifier = scarf.modifiers.new('RigifyDeform', 'ARMATURE')
modifier.object = rig
modifier.use_deform_preserve_volume = True
scarf.parent = rig
scarf.matrix_parent_inverse = rig.matrix_world.inverted()


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


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
            found = adjacency[current] & unseen
            unseen.difference_update(found)
            stack.extend(found)
    return count


manifold = manifold_stats(scarf)
components = component_count(scarf)
weight_range = (min(weight_sums), max(weight_sums))
rigified = any(mod.type == 'ARMATURE' and mod.object == rig for mod in scarf.modifiers)
if manifold['nonmanifold_edges'] != 0 or components != 1:
    raise RuntimeError(f'Scarf topology failed: manifold={manifold}, components={components}')
if weight_range[0] < 0.999 or weight_range[1] > 1.001 or not rigified:
    raise RuntimeError(f'Scarf Rigify validation failed: weights={weight_range}, rig={rigified}')

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
    scene.render.filepath = str(PREVIEWS / f'diagnostic_v16_helical_scarf_{key}.png')
    bpy.ops.render.render(write_still=True)


render('top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render('high_angle', (1.75, -2.20, 3.28), (0.0, 0.02, 1.46), lens=74)
render('upper_three_quarter', (0.82, -1.42, 2.10), (0.0, 0.0, 1.49), lens=78)
render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render('back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

report = {
    'candidate': str(OUTPUT),
    'source': str(SOURCE),
    'removed_upper_objects': removed,
    'removed_triangles': removed_triangles,
    'new_scarf': scarf.name,
    'new_scarf_triangles': triangle_count(scarf),
    'new_scarf_components': components,
    'new_scarf_manifold': manifold,
    'new_scarf_weight_sum_range': list(weight_range),
    'new_scarf_max_arm_weight': max(arm_weights),
    'rigify_modifier': rigified,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'hair_preserved': bpy.data.objects.get('Mercenary_ThinShortHair_LOD0_v16j') is not None,
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'renders': [
        str(PREVIEWS / f'diagnostic_v16_helical_scarf_{key}.png')
        for key in ('top_close', 'high_angle', 'upper_three_quarter', 'front', 'back')
    ],
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
