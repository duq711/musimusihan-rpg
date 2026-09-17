"""Independent v16 candidate: one continuous draped cowl shell.

All prior cowl/yoke/gusset/patch/rolled-collar objects are removed.  The only
replacement is one connected manifold cloth volume flowing from neck to
shoulders.  Two broad, nonconcentric ridges are sculpted into that same shell;
there are no torus tubes, stacked rings, floating pieces, or hidden patches.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_single_draped_shell_v6_agent_candidate.blend'
REPORT = STAGING / 'v16_single_draped_shell_v6_agent_report.json'

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


def weight_sum_range(obj):
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return min(sums), max(sums)


removed = []
removed_triangles = 0
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    removed_triangles += triangle_count(obj)
    old_mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    removed.append(name)


# Settle only the obsolete projected rear collar peaks below the new shell.
# This changes no topology and leaves face, torso, and visible sleeves intact.
settled_vertices = []
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.sqrt(co.x * co.x + ((co.y - 0.018) * 1.08) ** 2)
    influence = (
        smoothstep((radial - 0.090) / 0.045)
        * (1.0 - smoothstep((radial - 0.340) / 0.100))
        * (1.0 - smoothstep((abs(co.x) - 0.290) / 0.060))
        * smoothstep((co.y - 0.012) / 0.078)
        * smoothstep((co.z - 1.390) / 0.050)
        * (1.0 - smoothstep((co.z - 1.565) / 0.030))
    )
    if influence <= 0.002:
        continue
    target_z = 1.286 + 0.014 * smoothstep((abs(co.x) - 0.190) / 0.120)
    lowered = min(co.z, target_z)
    settled_vertices.append((vertex.index, co.z, lowered, influence))
    # Pull the obsolete rear hood projection under the new garment as well as
    # lowering it.  This prevents a second brown halo from appearing in top
    # views without adding a hidden plate or helper object.
    co.x = co.x * (1.0 - 0.48 * influence)
    co.y = co.y * (1.0 - 0.55 * influence) + 0.012 * (0.55 * influence)
    co.z = co.z * (1.0 - influence) + lowered * influence
donor.data.update()
donor['v16_single_shell_hidden_rear_collar_settled'] = True
donor['v16_single_shell_settled_vertex_count'] = len(settled_vertices)


ANGULAR_SEGMENTS = 176
DRAPE_SEGMENTS = 34
ROWS = DRAPE_SEGMENTS + 1


def shell_point(theta, u, inner=False):
    cosine = math.cos(theta)
    sine = math.sin(theta)
    side = abs(cosine)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    left = max(0.0, -cosine)

    # The body of the scarf stays nearly vertical and close to the neck.  Only
    # two localized lower side drapes reach the shoulder seams; this avoids the
    # broad horizontal disc silhouette of the first candidate.
    eased = smoothstep(u) ** 1.08
    top_rx = 0.128 + 0.004 * math.sin(3.0 * theta + 0.3)
    top_ry = 0.103 + 0.003 * math.sin(2.0 * theta - 0.2)
    side_drape = side ** 6.0
    bottom_rx = 0.166 + 0.106 * side_drape + 0.005 * left
    bottom_ry = 0.170 + 0.078 * back + 0.038 * front
    # Shoulder reach comes in early only at the two sides, so the cloth covers
    # the broken sleeve junctions while the front/back remain a compact cowl.
    side_reach = 0.030 * side_drape * smoothstep(u / 0.52)
    rx = top_rx * (1.0 - eased) + bottom_rx * eased + side_reach
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # A slight inward tuck at the hem makes the cloth read as a hanging bundle
    # instead of a sheet projecting from the shoulders.
    hem_tuck = smoothstep((u - 0.88) / 0.12)
    rx -= (0.006 + 0.010 * (1.0 - side_drape)) * hem_tuck
    ry -= 0.008 * hem_tuck

    # Two meandering broad ridges are relief in this surface, not separate
    # geometry.  Their paths and widths differ around the garment.
    ridge_path_a = 0.285 + 0.125 * math.sin(theta + 0.55) + 0.030 * math.sin(3.0 * theta)
    ridge_path_b = 0.655 + 0.145 * math.sin(theta - 0.82) - 0.025 * math.sin(3.0 * theta)
    ridge_a = math.exp(-((u - ridge_path_a) / 0.105) ** 2)
    ridge_b = math.exp(-((u - ridge_path_b) / 0.125) ** 2)
    ridge_relief = 0.0350 * ridge_a + 0.0430 * ridge_b
    ridge_relief *= 0.82 + 0.18 * (side + front)

    # Shallow flanking valleys make the two folds legible without tube shapes.
    valley_a = math.exp(-((u - ridge_path_a - 0.125) / 0.080) ** 2)
    valley_b = math.exp(-((u - ridge_path_b - 0.145) / 0.095) ** 2)
    radial_relief = ridge_relief - 0.0140 * valley_a - 0.0120 * valley_b
    radial_relief += math.sin(math.pi * u) ** 1.2 * (
        0.0040 * math.sin(4.0 * theta + 0.6)
        + 0.0022 * math.sin(9.0 * theta - 0.4)
    )

    if inner:
        thickness = 0.0105 + 0.0015 * math.sin(3.0 * theta + 2.0 * u)
        rx -= thickness
        ry -= thickness * 0.90
        radial_relief *= 0.70

    tangential = math.sin(math.pi * u) ** 1.35 * (
        0.0060 * math.sin(2.0 * theta + 1.3 * u)
        + 0.0030 * math.sin(5.0 * theta - 0.7)
    )
    x = -0.005 * math.sin(math.pi * u) + (rx + radial_relief) * cosine - tangential * sine
    y = 0.010 + 0.012 * eased + (ry + 0.72 * radial_relief) * sine + 0.70 * tangential * cosine

    top_z = (
        1.574
        + 0.034 * back
        - 0.018 * front
        + 0.008 * side
        + 0.006 * math.sin(3.0 * theta + 0.25)
    )
    bottom_z = (
        1.350
        + 0.086 * side_drape
        - 0.060 * front
        + 0.016 * back
        - 0.006 * left
        + 0.007 * math.sin(5.0 * theta - 0.55)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += math.sin(math.pi * u) ** 1.25 * (
        0.0110 * ridge_a
        + 0.0130 * ridge_b
        + 0.0040 * math.sin(3.0 * theta + 2.2 * u)
        + 0.0020 * math.sin(8.0 * theta - 3.1 * u)
    )
    if inner:
        z -= 0.0020 * math.sin(math.pi * u)
    return x, y, z


vertices = []
parameters = []
for surface in (0, 1):
    for drape_index in range(ROWS):
        u = drape_index / DRAPE_SEGMENTS
        for angular_index in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
            vertices.append(shell_point(theta, u, inner=bool(surface)))
            parameters.append((surface, drape_index, angular_index, u, theta))

surface_size = ROWS * ANGULAR_SEGMENTS
faces = []
for drape_index in range(DRAPE_SEGMENTS):
    for angular_index in range(ANGULAR_SEGMENTS):
        nxt = (angular_index + 1) % ANGULAR_SEGMENTS
        a = drape_index * ANGULAR_SEGMENTS + angular_index
        b = (drape_index + 1) * ANGULAR_SEGMENTS + angular_index
        c = (drape_index + 1) * ANGULAR_SEGMENTS + nxt
        d = drape_index * ANGULAR_SEGMENTS + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

bottom_start = DRAPE_SEGMENTS * ANGULAR_SEGMENTS
for angular_index in range(ANGULAR_SEGMENTS):
    nxt = (angular_index + 1) % ANGULAR_SEGMENTS
    faces.append((angular_index, nxt, surface_size + nxt, surface_size + angular_index))
    faces.append((
        bottom_start + angular_index,
        surface_size + bottom_start + angular_index,
        surface_size + bottom_start + nxt,
        bottom_start + nxt,
    ))

mesh = bpy.data.meshes.new('Mercenary_SingleDrapedCowlShell_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
shell = bpy.data.objects.new('Mercenary_SingleDrapedCowlShell_LOD0', mesh)
collection.objects.link(shell)

material_source = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if material_source is None:
    material_source = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = material_source.copy()
material.name = 'MAT_SingleDrapedCowl_CharcoalWool_PBR_4K'
material.use_backface_culling = False
mesh.materials.append(material)
shell['game_asset'] = True
shell['part_category'] = 'ClothedBody'
shell['intentional_layer'] = True
shell['source'] = 'V16 single continuous neck-to-shoulder cloth shell with two integrated meandering ridges'
shell['no_tubes_stacks_patches'] = True

uv = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vi = mesh.loops[loop_index].vertex_index
        _surface, _drape, angular_index, u, _theta = parameters[vi]
        uv.data[loop_index].uv = (angular_index / ANGULAR_SEGMENTS * 3.2, u * 2.0)

neck = shell.vertex_groups.new(name='DEF-spine.006')
upper = shell.vertex_groups.new(name='DEF-spine.005')
chest = shell.vertex_groups.new(name='DEF-spine.004')
left_arm = shell.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = shell.vertex_groups.new(name='DEF-upper_arm.R')
for vertex, (_surface, _drape, _angular, u, theta) in zip(mesh.vertices, parameters):
    side = abs(math.cos(theta))
    arm_weight = 0.23 * smoothstep((side - 0.70) / 0.30) * smoothstep((u - 0.68) / 0.32)
    torso = 1.0 - arm_weight
    neck_factor = 0.74 - 0.60 * smoothstep(u)
    chest_factor = 0.09 + 0.62 * smoothstep(u)
    upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
    normalizer = neck_factor + upper_factor + chest_factor
    neck_share = torso * neck_factor / normalizer
    upper_share = torso * upper_factor / normalizer
    chest_share = torso * chest_factor / normalizer
    neck.add([vertex.index], neck_share, 'REPLACE')
    upper.add([vertex.index], upper_share, 'REPLACE')
    chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')

for selected in bpy.context.selected_objects:
    selected.select_set(False)
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
bevel = shell.modifiers.new('SoftClothHem', 'BEVEL')
bevel.width = 0.0022
bevel.segments = 2
bevel.limit_method = 'ANGLE'
bevel.angle_limit = math.radians(38.0)
bpy.ops.object.modifier_apply(modifier=bevel.name)
shell.select_set(False)

armature = shell.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
shell.parent = rig
shell.matrix_parent_inverse = rig.matrix_world.inverted()

stats = manifold_stats(shell)
components = component_count(shell)
weight_range = weight_sum_range(shell)
has_rig = any(mod.type == 'ARMATURE' and mod.object == rig for mod in shell.modifiers)
if stats['nonmanifold_edges'] or components != 1:
    raise RuntimeError(f'Shell topology failed: {stats}, components={components}')
if weight_range[0] < 0.999 or weight_range[1] > 1.001 or not has_rig:
    raise RuntimeError(f'Shell Rigify failed: {weight_range}, rig={has_rig}')

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


def render(key, location, target, ortho_scale=None, lens=74, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = 'PERSP'
        camera.data.lens = lens
    else:
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f'diagnostic_v16_single_draped_shell_v6_agent_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render('top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.90, resolution=(1200, 900)),
    'high_angle': render('high_angle', (1.58, -1.98, 3.18), (0.0, 0.01, 1.45), lens=76),
    'upper_three_quarter': render('upper_three_quarter', (0.86, -1.50, 2.10), (0.0, 0.0, 1.47), lens=80),
    'front': render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
    'back': render('back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
}

bounds = {
    'min': [min(vertex.co[i] for vertex in shell.data.vertices) for i in range(3)],
    'max': [max(vertex.co[i] for vertex in shell.data.vertices) for i in range(3)],
}
report = {
    'candidate': str(OUTPUT),
    'source': str(SOURCE),
    'visible_shell': shell.name,
    'topology_description': 'one continuous annular neck-to-shoulder cloth shell; exactly two broad integrated nonconcentric ridges',
    'visible_objects': [shell.name],
    'separate_cowl_helpers': [],
    'triangles': triangle_count(shell),
    'components': components,
    'manifold': stats,
    'weight_sum_range': list(weight_range),
    'max_arm_weight': max((item.weight for vertex in shell.data.vertices for item in vertex.groups if shell.vertex_groups[item.group].name.startswith('DEF-upper_arm')), default=0.0),
    'bounds': bounds,
    'removed_upper_objects': removed,
    'removed_triangles': removed_triangles,
    'settled_hidden_donor_vertices': len(settled_vertices),
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'hair_preserved': bpy.data.objects.get('Mercenary_ThinShortHair_LOD0_v16j') is not None,
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'previews': previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')

rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = 'PERSP'
camera.data.lens = 80
camera.location = (0.86, -1.50, 2.10)
look_at(camera, (0.0, 0.0, 1.47))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print(json.dumps(report, indent=2))
