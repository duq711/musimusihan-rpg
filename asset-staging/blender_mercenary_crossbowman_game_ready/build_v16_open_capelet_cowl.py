"""Independent v16 candidate: one open-front organic capelet/cowl shell.

Unlike an annular collar, this is a C-shaped cloth pattern with a front slit.
The surface follows the donor shoulders, rises into a collapsed rear hood, and
contains localized nonconcentric folds.  It is one connected closed volume,
with no rings, hoses, stacked plates, or helper patches.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_open_capelet_cowl_candidate.blend'
REPORT = STAGING / 'v16_open_capelet_cowl_report.json'

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


def angular_ridge(theta, center, width):
    delta = angle_delta(theta, center)
    return math.exp(-0.5 * (delta / width) ** 2)


ANGLE_SEGMENTS = 176
RADIAL_SEGMENTS = 36
THICKNESS = 0.010
FRONT_GAP = 0.29
THETA_START = -math.pi / 2.0 + FRONT_GAP
THETA_END = -math.pi / 2.0 + 2.0 * math.pi - FRONT_GAP

# Directional folds fan from the neckline toward different parts of the hem.
# Their unequal widths and signs make a cloth field, not concentric contours.
FOLDS = (
    (-2.78, 0.18, 0.018),
    (-2.21, 0.24, -0.013),
    (-1.76, 0.15, 0.015),
    (-1.05, 0.21, -0.012),
    (-0.44, 0.17, 0.017),
    (0.16, 0.22, -0.011),
    (0.72, 0.18, 0.015),
    (1.16, 0.24, -0.010),
    (1.62, 0.18, 0.019),
    (2.08, 0.20, -0.011),
    (2.58, 0.17, 0.016),
)


def capelet_point(theta, radial_parameter, surface, angular_parameter):
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)
    eased = smoothstep(radial_parameter)

    # Inner neckline and outer donor-shoulder boundary.  The rear hem is short
    # enough to sit over the existing hood, while the sides span the damaged
    # shoulder joins and the open front falls onto the chest.
    inner_rx = 0.108 + 0.004 * math.sin(3.0 * theta + 0.35)
    inner_ry = 0.076 + 0.003 * math.sin(4.0 * theta - 0.4)
    outer_rx = 0.342 + 0.014 * math.sin(3.0 * theta + 0.5)
    outer_rx += 0.009 * math.sin(7.0 * theta - 0.8)
    outer_ry = 0.210 + 0.028 * back + 0.010 * front
    outer_ry += 0.009 * math.sin(2.0 * theta + 0.9)
    # Tuck the capelet under the existing rear hood and narrow the two front
    # lapels.  The widest points remain over the shoulder seams, matching the
    # donor rather than forming a circular brim.
    back_tuck = 1.0 - 0.42 * back ** 1.45
    front_tuck = 1.0 - 0.20 * front ** 1.30
    outer_rx *= back_tuck * front_tuck
    outer_ry *= (1.0 - 0.30 * back ** 1.40) * (1.0 - 0.13 * front ** 1.25)

    rx = inner_rx * (1.0 - eased) + outer_rx * eased
    ry = inner_ry * (1.0 - eased) + outer_ry * eased
    center_y = 0.010 + 0.024 * eased + 0.010 * back * eased

    # Organic edge and cross-grain drift.  This shifts the geometry tangentially
    # as well as vertically, preventing a regular polar-grid appearance.
    cloth_envelope = math.sin(math.pi * radial_parameter) ** 1.25
    tangential = 0.008 * math.sin(4.0 * theta + 2.6 * radial_parameter)
    tangential += 0.004 * math.sin(9.0 * theta - 3.0 * radial_parameter)
    tangential *= cloth_envelope
    x = cosine * rx - sine * tangential
    y = center_y + sine * ry + cosine * tangential * 0.72

    inner_z = 1.548 + 0.050 * back - 0.015 * front
    outer_z = 1.416 + 0.050 * back + 0.008 * side - 0.034 * front
    z = inner_z * (1.0 - eased) + outer_z * eased

    # A collapsed hood pocket at the nape and a loose front drop make the
    # silhouette read as cloth hanging from the shoulders instead of a plate.
    z += 0.034 * back * (1.0 - eased) ** 1.5
    z -= 0.020 * front * smoothstep((radial_parameter - 0.52) / 0.48)

    # An integrated soft inner fold is strongest at the rear and disappears at
    # the open front, so it cannot form a ring.
    front_open_factor = 1.0 - angular_ridge(theta, -math.pi / 2.0, 0.50)
    neckline_fold = math.exp(-0.5 * ((radial_parameter - 0.16) / 0.085) ** 2)
    z += 0.020 * neckline_fold * (0.35 + 0.65 * back) * front_open_factor

    # Localized shoulder-to-hem ridges and valleys.
    for center, width, amplitude in FOLDS:
        # The fold center drifts sideways as it runs toward the hem, producing
        # curved cloth channels rather than straight polar spokes.
        shifted_center = center + 0.30 * (radial_parameter - 0.46) * math.sin(1.7 * center)
        ridge = angular_ridge(theta, shifted_center, width) * cloth_envelope
        z += amplitude * 1.55 * ridge
        x += cosine * amplitude * 0.68 * ridge
        y += sine * amplitude * 0.48 * ridge

    # Fine diagonal wrinkles make the fold flow nonconcentric.
    wrinkle = math.sin(math.pi * radial_parameter) ** 2
    z += 0.0050 * math.sin(5.5 * theta + 7.0 * radial_parameter + 0.4) * wrinkle
    z += 0.0028 * math.sin(12.0 * theta - 5.0 * radial_parameter) * wrinkle
    z += 0.0110 * math.sin(3.2 * theta + 6.4 * radial_parameter + 0.6) * wrinkle

    # A soft rolled hem thickens only the irregular outer edge.  Because the
    # garment is open at the front and tucked at the back, this is never a
    # closed circumferential ring.
    hem_fold = math.exp(-0.5 * ((radial_parameter - 0.89) / 0.075) ** 2)
    z += 0.013 * hem_fold * (0.55 + 0.45 * side)

    # The two front slit edges deliberately finish at different heights and
    # depths.  This produces overlapping medieval cowl lapels rather than a
    # symmetric cut-out or a closed donut.
    seam_distance = min(angular_parameter, 1.0 - angular_parameter)
    seam_strength = 1.0 - smoothstep(seam_distance / 0.11)
    seam_side = -1.0 if angular_parameter < 0.5 else 1.0
    x += seam_side * 0.010 * seam_strength * eased
    y -= (0.010 + 0.008 * seam_side) * seam_strength * eased
    z += (0.010 * seam_side - 0.008) * seam_strength * eased

    if surface == 1:
        local_thickness = THICKNESS * (0.65 + 1.15 * eased)
        z -= local_thickness
    return (x, y, z)


vertices = []
parameters = []
for surface in range(2):
    for angle_index in range(ANGLE_SEGMENTS + 1):
        angular_parameter = angle_index / ANGLE_SEGMENTS
        theta = THETA_START + (THETA_END - THETA_START) * angular_parameter
        for radial_index in range(RADIAL_SEGMENTS + 1):
            radial_parameter = radial_index / RADIAL_SEGMENTS
            vertices.append(capelet_point(theta, radial_parameter, surface, angular_parameter))
            parameters.append((surface, angle_index, radial_index, angular_parameter, radial_parameter))


PER_SURFACE = (ANGLE_SEGMENTS + 1) * (RADIAL_SEGMENTS + 1)


def index(surface, angle_index, radial_index):
    return (
        surface * PER_SURFACE
        + angle_index * (RADIAL_SEGMENTS + 1)
        + radial_index
    )


faces = []
for angle_index in range(ANGLE_SEGMENTS):
    for radial_index in range(RADIAL_SEGMENTS):
        faces.append((
            index(0, angle_index, radial_index),
            index(0, angle_index, radial_index + 1),
            index(0, angle_index + 1, radial_index + 1),
            index(0, angle_index + 1, radial_index),
        ))
        faces.append((
            index(1, angle_index, radial_index),
            index(1, angle_index + 1, radial_index),
            index(1, angle_index + 1, radial_index + 1),
            index(1, angle_index, radial_index + 1),
        ))

# Inner neckline and irregular outer hem walls.
for angle_index in range(ANGLE_SEGMENTS):
    for radial_index in (0, RADIAL_SEGMENTS):
        a = index(0, angle_index, radial_index)
        b = index(0, angle_index + 1, radial_index)
        c = index(1, angle_index + 1, radial_index)
        d = index(1, angle_index, radial_index)
        faces.append((a, b, c, d) if radial_index == RADIAL_SEGMENTS else (d, c, b, a))

# Close both front slit edges.  They are part of the same volume but remain
# visually separate, giving the cowl its essential non-annular topology.
for angle_index in (0, ANGLE_SEGMENTS):
    for radial_index in range(RADIAL_SEGMENTS):
        a = index(0, angle_index, radial_index)
        b = index(0, angle_index, radial_index + 1)
        c = index(1, angle_index, radial_index + 1)
        d = index(1, angle_index, radial_index)
        faces.append((a, b, c, d) if angle_index == ANGLE_SEGMENTS else (d, c, b, a))


mesh = bpy.data.meshes.new('Mercenary_OpenCapeletCowl_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

cowl = bpy.data.objects.new('Mercenary_OpenCapeletCowl_LOD0', mesh)
collection.objects.link(cowl)
cowl['game_asset'] = True
cowl['part_category'] = 'ClothedBody'
cowl['intentional_layer'] = True
cowl['source'] = 'V16 one-piece open-front shoulder capelet and collapsed cowl'
cowl['topology'] = 'single connected closed C-shaped cloth volume; no annulus or torus'

source_material = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if source_material is None:
    source_material = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = source_material.copy()
material.name = 'MAT_OpenCapeletCowl_Wool_PBR_4K'
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
        angle_index = within // (RADIAL_SEGMENTS + 1)
        radial_index = within % (RADIAL_SEGMENTS + 1)
        uv.data[loop_index].uv = (
            angle_index / ANGLE_SEGMENTS * 4.0,
            radial_index / RADIAL_SEGMENTS * 2.0,
        )

# Torso-dominant Rigify weights with a restrained upper-arm blend only at the
# outermost side hem.
spine_upper = cowl.vertex_groups.new(name='DEF-spine.005')
spine_chest = cowl.vertex_groups.new(name='DEF-spine.004')
left_arm = cowl.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = cowl.vertex_groups.new(name='DEF-upper_arm.R')
weight_sums = []
arm_weights = []
for vertex, (_surface, _ai, _ri, _a, radial_parameter) in zip(mesh.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.250) / 0.105)
    outer_gate = smoothstep((radial_parameter - 0.62) / 0.38)
    arm_weight = 0.24 * side_gate * outer_gate
    torso_weight = 1.0 - arm_weight
    upper_share = torso_weight * (0.72 - 0.24 * smoothstep(radial_parameter))
    chest_share = torso_weight - upper_share
    spine_upper.add([vertex.index], upper_share, 'REPLACE')
    spine_chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add(
            [vertex.index], arm_weight, 'REPLACE'
        )
    weight_sums.append(upper_share + chest_share + arm_weight)
    arm_weights.append(arm_weight)

modifier = cowl.modifiers.new('RigifyDeform', 'ARMATURE')
modifier.object = rig
modifier.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()


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


manifold = manifold_stats(cowl)
components = component_count(cowl)
weight_range = (min(weight_sums), max(weight_sums))
rigified = any(mod.type == 'ARMATURE' and mod.object == rig for mod in cowl.modifiers)
if manifold['nonmanifold_edges'] or components != 1:
    raise RuntimeError(f'Cowl topology failed: {manifold}, components={components}')
if weight_range[0] < 0.999 or weight_range[1] > 1.001 or not rigified:
    raise RuntimeError(f'Cowl Rigify failed: {weight_range}, rig={rigified}')

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
    scene.render.filepath = str(PREVIEWS / f'diagnostic_v16_open_capelet_{key}.png')
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
    'cowl': cowl.name,
    'cowl_triangles': triangle_count(cowl),
    'cowl_components': components,
    'cowl_manifold': manifold,
    'cowl_weight_sum_range': list(weight_range),
    'cowl_max_arm_weight': max(arm_weights),
    'rigify_modifier': rigified,
    'removed_upper_objects': removed,
    'removed_triangles': removed_triangles,
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'hair_preserved': bpy.data.objects.get('Mercenary_ThinShortHair_LOD0_v16j') is not None,
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'topology_description': 'one closed C-shaped open-front cloth volume; nonconcentric radial folds',
    'renders': [
        str(PREVIEWS / f'diagnostic_v16_open_capelet_{key}.png')
        for key in ('top_close', 'high_angle', 'upper_three_quarter', 'front', 'back')
    ],
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
