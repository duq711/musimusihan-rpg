"""Independent v16 candidate using one natural sculpted cowl shell.

Only the broad lowest sculpted component of the original cowl is retained.
The two upper shells, three torus collars, and patch helpers are removed.  A
compact quilted closure stays below the visible scarf solely to hide donor
shoulder seams.  Production/viewer files remain untouched.
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
CLOSURE_SOURCE = STAGING / 'mercenary_crossbowman_game_ready_v16_minimal_cowl_yoke5_gambeson_candidate.blend'
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_single_sculpted_cowl_candidate.blend'
REPORT = STAGING / 'v16_single_sculpted_cowl_report.json'

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
source_cowl = bpy.data.objects['Mercenary_Cowl_LayeredClean_LOD0']


def connected_components(obj):
    adjacency = defaultdict(set)
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = []
    while unseen:
        seed = unseen.pop()
        component = {seed}
        stack = [seed]
        while stack:
            current = stack.pop()
            found = adjacency[current] & unseen
            unseen.difference_update(found)
            component.update(found)
            stack.extend(found)
        components.append(component)
    return components


components = connected_components(source_cowl)
outer_component = min(
    components,
    key=lambda component: sum(source_cowl.data.vertices[i].co.z for i in component) / len(component),
)

# Rebuild only the lowest broad sculpted shell while preserving its authored
# loops, UVs, and deform weights.  A gentle continuous warp breaks the perfect
# ellipse without compromising the original micro-fold detail.
old_to_new = {old_index: new_index for new_index, old_index in enumerate(sorted(outer_component))}
new_vertices = []
for old_index in sorted(outer_component):
    co = source_cowl.data.vertices[old_index].co.copy()
    theta = math.atan2(co.y - 0.006, co.x)
    front = max(0.0, -math.sin(theta))
    back = max(0.0, math.sin(theta))
    radius = math.sqrt(co.x * co.x + (co.y - 0.006) * (co.y - 0.006))
    radial_gate = max(0.0, min(1.0, (radius - 0.105) / 0.145))
    co.x *= 1.055 + 0.015 * math.sin(3.0 * theta + 0.3)
    co.y = 0.006 + (co.y - 0.006) * (1.015 + 0.025 * back)
    co.z += 0.0045 * math.sin(3.0 * theta + 0.65) * radial_gate
    co.z += 0.0028 * math.sin(7.0 * theta - 0.5) * radial_gate
    co.z -= 0.0065 * front * radial_gate
    co.z += 0.0040 * back * radial_gate
    new_vertices.append(tuple(co))

source_polygons = [
    polygon for polygon in source_cowl.data.polygons
    if all(vertex_index in outer_component for vertex_index in polygon.vertices)
]
new_faces = [tuple(old_to_new[index] for index in polygon.vertices) for polygon in source_polygons]

mesh = bpy.data.meshes.new('Mercenary_SingleSculptedCowl_LOD0_Mesh')
mesh.from_pydata(new_vertices, [], new_faces)
mesh.update()

scarf = bpy.data.objects.new('Mercenary_SingleSculptedCowl_LOD0', mesh)
collection.objects.link(scarf)
scarf['game_asset'] = True
scarf['part_category'] = 'ClothedBody'
scarf['intentional_layer'] = True
scarf['source'] = 'V16 one retained broad sculpted shell; upper rings and torus collars removed'
scarf['topology'] = 'one connected closed visible scarf shell'

material_source = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if material_source is None:
    material_source = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = material_source.copy()
material.name = 'MAT_SingleSculptedCowl_Wool_PBR_4K'
material.use_backface_culling = False
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Preserve the selected source component's UVs polygon-for-polygon.
source_uv = source_cowl.data.uv_layers.active
uv = mesh.uv_layers.new(name='UVMap')
for new_polygon, source_polygon in zip(mesh.polygons, source_polygons):
    for new_loop_index, source_loop_index in zip(new_polygon.loop_indices, source_polygon.loop_indices):
        uv.data[new_loop_index].uv = source_uv.data[source_loop_index].uv.copy()

# Copy and normalize all existing Rigify deform weights for retained vertices.
source_group_names = {group.index: group.name for group in source_cowl.vertex_groups}
group_cache = {}
weight_sums = []
for old_index, new_index in old_to_new.items():
    source_vertex = source_cowl.data.vertices[old_index]
    weights = [
        (source_group_names[item.group], item.weight)
        for item in source_vertex.groups
        if item.group in source_group_names and item.weight > 1.0e-6
    ]
    total = sum(weight for _name, weight in weights)
    if total <= 1.0e-8:
        weights = [('DEF-spine.005', 1.0)]
        total = 1.0
    for group_name, weight in weights:
        group = group_cache.get(group_name)
        if group is None:
            group = scarf.vertex_groups.new(name=group_name)
            group_cache[group_name] = group
        group.add([new_index], weight / total, 'REPLACE')
    weight_sums.append(sum(weight / total for _name, weight in weights))

modifier = scarf.modifiers.new('RigifyDeform', 'ARMATURE')
modifier.object = rig
modifier.use_deform_preserve_volume = True
scarf.parent = rig
scarf.matrix_parent_inverse = rig.matrix_world.inverted()

removed = []
removed_triangles = 0
for name in OLD_UPPER:
    obj = bpy.data.objects.get(name)
    if not obj:
        continue
    removed_triangles += sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)
    old_mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)
    removed.append(name)

# Reuse the compact, already-tested quilted seam closure.  It remains beneath
# the visible scarf and covers only donor shoulder/rear openings.
with bpy.data.libraries.load(str(CLOSURE_SOURCE), link=False) as (data_from, data_to):
    data_to.objects = [
        'Mercenary_HiddenGambesonSeamClosure_LOD0'
        if 'Mercenary_HiddenGambesonSeamClosure_LOD0' in data_from.objects else None
    ]
closure = next((obj for obj in data_to.objects if obj is not None), None)
if closure is None:
    raise RuntimeError('Could not append hidden gambeson closure')
collection.objects.link(closure)
closure_world = closure.matrix_world.copy()
closure.parent = rig
closure.matrix_parent_inverse = rig.matrix_world.inverted()
closure.matrix_world = closure_world
for armature_modifier in closure.modifiers:
    if armature_modifier.type == 'ARMATURE':
        armature_modifier.object = rig
closure.data.materials.clear()
closure.data.materials.append(bpy.data.materials['MAT_Gambeson_Side_PBR_4K'])
closure['game_asset'] = True
closure['part_category'] = 'ClothedBody'
closure['intentional_underlayer'] = True
closure['source'] = 'V16 compact quilted seam closure hidden under one sculpted scarf shell'

for obj in list(bpy.data.objects):
    if (
        obj.type == 'ARMATURE'
        and obj is not rig
        and obj.name.startswith('Mercenary_Rigify_Rig_v4')
    ):
        bpy.data.objects.remove(obj, do_unlink=True)


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
    return (min(sums), max(sums))


scarf_manifold = manifold_stats(scarf)
closure_manifold = manifold_stats(closure)
scarf_components = component_count(scarf)
scarf_weight_range = weight_sum_range(scarf)
closure_weight_range = weight_sum_range(closure)
scarf_rigified = any(mod.type == 'ARMATURE' and mod.object == rig for mod in scarf.modifiers)
closure_rigified = any(mod.type == 'ARMATURE' and mod.object == rig for mod in closure.modifiers)
if scarf_manifold['nonmanifold_edges'] or closure_manifold['nonmanifold_edges']:
    raise RuntimeError(f'Manifold failed: scarf={scarf_manifold}, closure={closure_manifold}')
if scarf_components != 1:
    raise RuntimeError(f'Visible scarf has {scarf_components} components')
if scarf_weight_range[0] < 0.999 or scarf_weight_range[1] > 1.001 or not scarf_rigified:
    raise RuntimeError(f'Scarf Rigify failed: {scarf_weight_range}, {scarf_rigified}')
if closure_weight_range[0] < 0.999 or closure_weight_range[1] > 1.001 or not closure_rigified:
    raise RuntimeError(f'Closure Rigify failed: {closure_weight_range}, {closure_rigified}')

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
    scene.render.filepath = str(PREVIEWS / f'diagnostic_v16_single_sculpted_cowl_{key}.png')
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
    'visible_scarf': scarf.name,
    'visible_scarf_triangles': triangle_count(scarf),
    'visible_scarf_components': scarf_components,
    'visible_scarf_manifold': scarf_manifold,
    'visible_scarf_weight_sum_range': list(scarf_weight_range),
    'hidden_closure': closure.name,
    'hidden_closure_triangles': triangle_count(closure),
    'hidden_closure_manifold': closure_manifold,
    'hidden_closure_weight_sum_range': list(closure_weight_range),
    'removed_upper_objects': removed,
    'removed_triangles': removed_triangles,
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'hair_preserved': bpy.data.objects.get('Mercenary_ThinShortHair_LOD0_v16j') is not None,
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'renders': [
        str(PREVIEWS / f'diagnostic_v16_single_sculpted_cowl_{key}.png')
        for key in ('top_close', 'high_angle', 'upper_three_quarter', 'front', 'back')
    ],
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
