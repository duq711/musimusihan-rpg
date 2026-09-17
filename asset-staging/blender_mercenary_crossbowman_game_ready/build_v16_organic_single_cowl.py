"""Create an independent v16 candidate with one organic draped cowl.

The six closed circular shells and patch helpers from v15 are removed.  A
single connected, closed annular cloth volume slopes from the neck opening to
an irregular shoulder/back hem.  Local radial ridges provide cloth folds
without recreating stacked torus rings.  Production GLBs and viewer files are
intentionally untouched.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_organic_single_cowl_candidate.blend'
REPORT = STAGING / 'v16_organic_single_cowl_report.json'

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
asset_collection = donor.users_collection[0]

removed = []
removed_triangles = 0
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    removed_triangles += sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    removed.append(name)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def angle_delta(a: float, b: float) -> float:
    return (a - b + math.pi) % (2.0 * math.pi) - math.pi


def gaussian_angle(theta: float, center: float, width: float) -> float:
    delta = angle_delta(theta, center)
    return math.exp(-0.5 * (delta / width) ** 2)


# One broad closed cloth volume.  The inner edge follows the neck while the
# irregular outer hem rests on the chest, shoulders, and collapsed rear hood.
ANGLE_SEGMENTS = 192
RADIAL_SEGMENTS = 36
THICKNESS = 0.0085
SURFACES = 2

# Local fold directions are intentionally irregular.  Positive entries form
# soft raised ridges and negative entries form shallow cloth valleys.  Each one
# fades before both boundaries, so no circumferential hose can appear.
FOLDS = (
    (-2.72, 0.20, 0.0100),
    (-2.05, 0.17, -0.0070),
    (-1.63, 0.24, 0.0150),
    (-1.10, 0.16, -0.0060),
    (-0.58, 0.19, 0.0110),
    (0.05, 0.16, -0.0060),
    (0.52, 0.22, 0.0130),
    (1.06, 0.18, -0.0060),
    (1.43, 0.23, 0.0140),
    (1.98, 0.16, -0.0055),
    (2.38, 0.20, 0.0105),
)


def cowl_top(theta: float, t: float) -> tuple[float, float, float]:
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)
    eased = smoothstep(t)
    radius = 0.105 * (1.0 - eased) + 0.315 * eased

    # The back is intentionally shorter and tucks below the existing collapsed
    # donor hood.  The front and sides spread farther over the chest/shoulders,
    # giving the garment a crescent-like drape instead of a circular disc.
    back_tuck = 1.0 - 0.35 * back * eased
    front_taper = 1.0 - 0.045 * front * eased
    irregular = 0.010 * math.sin(3.0 * theta + 4.2 * t + 0.35)
    irregular += 0.006 * math.sin(7.0 * theta - 2.7 * t)
    irregular *= math.sin(math.pi * t)
    rx = radius * (1.02 + 0.030 * side * eased) * back_tuck + irregular
    ry = radius * (0.72 + 0.030 * front * eased) * back_tuck * front_taper
    ry += irregular * 0.62
    center_y = 0.008 + 0.012 * eased + 0.006 * back * eased

    # Slight tangential meander prevents mechanically nested ellipses.
    tangential = 0.0055 * math.sin(5.0 * theta + 3.1 * t)
    tangential *= math.sin(math.pi * t) ** 1.2
    x = cosine * rx - sine * tangential
    y = center_y + sine * ry + cosine * tangential * 0.70

    inner_z = 1.555 + 0.045 * back - 0.016 * front
    outer_z = 1.425 + 0.040 * back + 0.006 * side - 0.036 * front
    z = inner_z * (1.0 - eased) + outer_z * eased

    # A collapsed hood crown keeps volume close to the neck, while the outer
    # half slopes downward as cloth rather than projecting horizontally.
    z += 0.022 * math.sin(math.pi * min(1.0, t / 0.48)) * (1.0 - smoothstep((t - 0.30) / 0.30))
    z += 0.0040 * math.sin(3.0 * theta + 3.8 * t + 0.3) * math.sin(math.pi * t)

    # Directional cloth ridges and valleys.  These are localized in angle and
    # therefore read as drape lines radiating from the neck, not stacked loops.
    radial_envelope = math.sin(math.pi * t) ** 1.15
    for center, width, amplitude in FOLDS:
        ridge = gaussian_angle(theta, center, width) * radial_envelope
        z += amplitude * 0.72 * ridge
        x += math.cos(theta) * amplitude * 0.22 * ridge
        y += math.sin(theta) * amplitude * 0.16 * ridge

    # Small secondary wrinkles, strongest in the loose middle of the cloth.
    wrinkle_envelope = math.sin(math.pi * t) ** 2
    z += 0.0038 * math.sin(7.0 * theta + 2.3 * t) * wrinkle_envelope
    z += 0.0023 * math.sin(13.0 * theta - 3.7 * t) * wrinkle_envelope
    z += 0.0090 * math.sin(2.35 * math.pi * t + 1.65 * theta + 0.25 * math.sin(3.0 * theta)) * wrinkle_envelope

    # One loose front drape and two compressed rear folds create a natural
    # scarf silhouette while keeping the surface a single connected volume.
    z += 0.015 * gaussian_angle(theta, -math.pi / 2.0, 0.34) * math.sin(math.pi * t) ** 2
    z += 0.010 * gaussian_angle(theta, 1.18, 0.22) * math.sin(math.pi * t) ** 1.5
    z += 0.008 * gaussian_angle(theta, 1.92, 0.18) * math.sin(math.pi * t) ** 1.5

    return x, y, z


vertices = []
parameters = []
for surface in range(SURFACES):
    for angular_index in range(ANGLE_SEGMENTS):
        theta = 2.0 * math.pi * angular_index / ANGLE_SEGMENTS
        for radial_index in range(RADIAL_SEGMENTS + 1):
            t = radial_index / RADIAL_SEGMENTS
            x, y, z = cowl_top(theta, t)
            if surface == 1:
                z -= THICKNESS
            vertices.append((x, y, z))
            parameters.append((surface, angular_index, radial_index, t, theta))


PER_SURFACE = ANGLE_SEGMENTS * (RADIAL_SEGMENTS + 1)


def index(surface: int, angular_index: int, radial_index: int) -> int:
    return (
        surface * PER_SURFACE
        + (angular_index % ANGLE_SEGMENTS) * (RADIAL_SEGMENTS + 1)
        + radial_index
    )


faces = []
for angular_index in range(ANGLE_SEGMENTS):
    nxt = (angular_index + 1) % ANGLE_SEGMENTS
    for radial_index in range(RADIAL_SEGMENTS):
        faces.append((
            index(0, angular_index, radial_index),
            index(0, angular_index, radial_index + 1),
            index(0, nxt, radial_index + 1),
            index(0, nxt, radial_index),
        ))
        faces.append((
            index(1, angular_index, radial_index),
            index(1, nxt, radial_index),
            index(1, nxt, radial_index + 1),
            index(1, angular_index, radial_index + 1),
        ))
    # Closed inner neck boundary.
    faces.append((
        index(0, angular_index, 0),
        index(0, nxt, 0),
        index(1, nxt, 0),
        index(1, angular_index, 0),
    ))
    # Closed irregular outer hem.
    faces.append((
        index(0, angular_index, RADIAL_SEGMENTS),
        index(1, angular_index, RADIAL_SEGMENTS),
        index(1, nxt, RADIAL_SEGMENTS),
        index(0, nxt, RADIAL_SEGMENTS),
    ))


mesh = bpy.data.meshes.new('Mercenary_OrganicSingleCowl_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()

# Ensure consistent outward normals across the closed volume.
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

cowl = bpy.data.objects.new('Mercenary_OrganicSingleCowl_LOD0', mesh)
asset_collection.objects.link(cowl)
cowl['game_asset'] = True
cowl['part_category'] = 'ClothedBody'
cowl['intentional_layer'] = True
cowl['source'] = 'V16 one-piece asymmetric draped cowl with localized radial folds'
cowl['topology'] = 'single connected closed annular cloth volume; no torus stack'

base_material = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if base_material is None:
    base_material = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = base_material.copy()
material.name = 'MAT_OrganicDrapedCowl_Wool_PBR_4K'
material.use_backface_culling = False
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Seam-aware tiled UVs.  Four repeats around the cowl and roughly two from the
# neck opening to the outer hem preserve the existing wool scale.
uv_layer = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    angle_indices = []
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % PER_SURFACE
        angular_index = within // (RADIAL_SEGMENTS + 1)
        angle_indices.append(angular_index)
    crosses_seam = 0 in angle_indices and (ANGLE_SEGMENTS - 1) in angle_indices
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % PER_SURFACE
        angular_index = within // (RADIAL_SEGMENTS + 1)
        radial_index = within % (RADIAL_SEGMENTS + 1)
        u = angular_index / ANGLE_SEGMENTS * 4.0
        if crosses_seam and angular_index == 0:
            u = 4.0
        v = radial_index / RADIAL_SEGMENTS * 2.1
        uv_layer.data[loop_index].uv = (u, v)

# Torso-dominant normalized Rigify weights; only the extreme outer sides blend
# gently into the upper arms to avoid sleeve dragging or duplicated shoulders.
spine_upper = cowl.vertex_groups.new(name='DEF-spine.005')
spine_chest = cowl.vertex_groups.new(name='DEF-spine.004')
left_arm = cowl.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = cowl.vertex_groups.new(name='DEF-upper_arm.R')
weight_sums = []
arm_weights = []
for vertex, (_surface, _angle_index, _radial_index, t, _theta) in zip(mesh.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.255) / 0.105)
    outer_gate = smoothstep((t - 0.63) / 0.37)
    arm_weight = 0.26 * side_gate * outer_gate
    torso_weight = 1.0 - arm_weight
    upper_share = torso_weight * (0.72 - 0.24 * smoothstep(t))
    chest_share = torso_weight - upper_share
    spine_upper.add([vertex.index], upper_share, 'REPLACE')
    spine_chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add(
            [vertex.index], arm_weight, 'REPLACE'
        )
    weight_sums.append(upper_share + chest_share + arm_weight)
    arm_weights.append(arm_weight)

armature = cowl.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()


def triangle_count(obj) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def manifold_stats(obj) -> dict[str, int]:
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


def component_count(obj) -> int:
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
            found = adjacency[current] & unseen
            unseen.difference_update(found)
            stack.extend(found)
    return components


cowl_manifold = manifold_stats(cowl)
cowl_components = component_count(cowl)
cowl_weight_range = (min(weight_sums), max(weight_sums))
cowl_rigified = any(mod.type == 'ARMATURE' and mod.object == rig for mod in cowl.modifiers)
if cowl_manifold['nonmanifold_edges'] != 0:
    raise RuntimeError(f'Cowl is not closed manifold: {cowl_manifold}')
if cowl_components != 1:
    raise RuntimeError(f'Expected one connected cowl component, got {cowl_components}')
if cowl_weight_range[0] < 0.999 or cowl_weight_range[1] > 1.001 or not cowl_rigified:
    raise RuntimeError(
        f'Cowl Rigify validation failed: weights={cowl_weight_range}, rig={cowl_rigified}'
    )

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
    scene.render.filepath = str(PREVIEWS / f'diagnostic_v16_organic_cowl_{key}.png')
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
    'new_cowl': cowl.name,
    'new_cowl_triangles': triangle_count(cowl),
    'new_cowl_components': cowl_components,
    'new_cowl_manifold': cowl_manifold,
    'new_cowl_weight_sum_range': list(cowl_weight_range),
    'new_cowl_max_arm_weight': max(arm_weights),
    'rigify_modifier': cowl_rigified,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'hair_preserved': bpy.data.objects.get('Mercenary_ThinShortHair_LOD0_v16j') is not None,
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'renders': [
        str(PREVIEWS / f'diagnostic_v16_organic_cowl_{key}.png')
        for key in ('top_close', 'high_angle', 'upper_three_quarter', 'front', 'back')
    ],
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
