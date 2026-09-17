"""Independent v16 candidate: one compact, soft, front-open scarf.

The visible garment is a single connected, manifold cloth volume.  Its body is
nearly vertical around the neck, with two asymmetric front ends and diagonal
folds sculpted into the same surface.  It deliberately avoids torus loops,
annular shoulder plates, stacked shells, and separate patch meshes.
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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_soft_open_scarf_agent_candidate.blend'
REPORT = STAGING / 'v16_soft_open_scarf_agent_report.json'

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
authored_cowl_mesh = bpy.data.objects['Mercenary_Cowl_LayeredClean_LOD0'].data.copy()
authored_cowl_mesh.name = 'Mercenary_SoftOpenScarf_LOD0_Mesh'


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
            linked = adjacency[current] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return count


def weight_sum_range(obj):
    values = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return min(values), max(values)


# Remove the old multi-shell stack completely in this independent candidate.
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


# Reuse the authored micro-folded surfaces, but collapse their three different
# radii onto one compact neck radius.  The components overlap vertically and
# are then fused, turning concentric rings into one crumpled cloth body.
mesh = authored_cowl_mesh
scarf = bpy.data.objects.new('Mercenary_SoftOpenScarf_LOD0', mesh)
collection.objects.link(scarf)

adjacency = defaultdict(set)
for edge in mesh.edges:
    a, b = edge.vertices
    adjacency[a].add(b)
    adjacency[b].add(a)
unseen = set(range(len(mesh.vertices)))
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
components.sort(key=lambda component: sum(mesh.vertices[i].co.z for i in component) / len(component))

radial_scales = (0.845, 0.935, 1.145)
vertical_offsets = (0.007, 0.000, -0.009)
phases = (0.35, 2.05, 4.20)
x_shifts = (0.005, -0.004, 0.002)
y_shifts = (0.003, -0.002, 0.004)
for component_index, component in enumerate(components):
    scale = radial_scales[component_index]
    phase = phases[component_index]
    for vertex_index in component:
        co = mesh.vertices[vertex_index].co
        centered_y = co.y - 0.006
        theta = math.atan2(centered_y, co.x)
        cosine = math.cos(theta)
        sine = math.sin(theta)
        front = max(0.0, -sine)
        back = max(0.0, sine)
        radial = math.sqrt(co.x * co.x + centered_y * centered_y)
        warped_radius = radial * scale
        warped_radius += 0.0065 * math.sin(3.0 * theta + phase)
        warped_radius += 0.0035 * math.sin(7.0 * theta - 0.6 * phase)
        co.x = warped_radius * cosine + x_shifts[component_index]
        co.y = 0.006 + warped_radius * sine * 0.86 + y_shifts[component_index]
        co.z += vertical_offsets[component_index]
        co.z += 0.0055 * math.sin(2.0 * theta + phase)
        co.z += 0.0035 * math.sin(5.0 * theta - phase)
        co.z -= 0.008 * front * (0.45 + 0.25 * component_index)
        co.z += 0.004 * back
mesh.update()
recalc_outside(mesh)

# The authored shells taper apart beneath the donor hood.  A single flattened
# rear cloth bunch joins that hidden gap before remeshing, so the open-front
# cut still leaves one continuous scarf running around the nape.
bpy.ops.mesh.primitive_uv_sphere_add(
    segments=48,
    ring_count=24,
    location=(0.0, 0.128, 1.500),
    scale=(0.158, 0.042, 0.088),
)
rear_bridge = bpy.context.object
rear_bridge.name = 'TEMP_RearScarfBunch'
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
scarf.select_set(True)
rear_bridge.select_set(True)
bpy.context.view_layer.objects.active = scarf
bpy.ops.object.join()
mesh = scarf.data
recalc_outside(mesh)

# Fuse the overlapping authored shells into one manifold skin.
for selected in bpy.context.selected_objects:
    selected.select_set(False)
scarf.select_set(True)
bpy.context.view_layer.objects.active = scarf
mesh.remesh_voxel_size = 0.0066
mesh.remesh_voxel_adaptivity = 0.0
mesh.use_remesh_fix_poles = True
mesh.use_remesh_preserve_volume = True
mesh.use_remesh_preserve_attributes = False
bpy.ops.object.voxel_remesh()
mesh = scarf.data
recalc_outside(mesh)
print('DEBUG_AFTER_VOXEL', len(mesh.vertices), len(mesh.polygons), component_count(scarf), tuple(round(value, 4) for value in scarf.dimensions))

# Cut one clear front opening through the already fused body.  Removing the
# central front voxels yields two cross-section loops; filling those loops caps
# the scarf ends robustly without a fragile Boolean operation.
bm = bmesh.new()
bm.from_mesh(mesh)
front_cut = [
    vertex for vertex in bm.verts
    if abs(vertex.co.x) < 0.082 and vertex.co.y < -0.018 and vertex.co.z > 1.490
]
bmesh.ops.delete(bm, geom=front_cut, context='VERTS')
boundary_edges = [edge for edge in bm.edges if edge.is_boundary]
bmesh.ops.holes_fill(bm, edges=boundary_edges, sides=0)
bm.to_mesh(mesh)
bm.free()
mesh.update()
recalc_outside(mesh)
print('DEBUG_AFTER_FRONT_CUT', len(mesh.vertices), len(mesh.polygons), component_count(scarf), tuple(round(value, 4) for value in scarf.dimensions))

# Round only the new cut lips; the authored wrinkles remain intact.
bevel = scarf.modifiers.new('FrontLipSoftening', 'BEVEL')
bevel.width = 0.0025
bevel.segments = 2
bevel.limit_method = 'ANGLE'
bevel.angle_limit = math.radians(48.0)
bpy.context.view_layer.objects.active = scarf
bpy.ops.object.modifier_apply(modifier=bevel.name)
mesh = scarf.data
recalc_outside(mesh)

material_source = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if material_source is None:
    material_source = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = material_source.copy()
material.name = 'MAT_SoftOpenScarf_CharcoalWool_PBR_4K'
material.use_backface_culling = False
mesh.materials.clear()
mesh.materials.append(material)
scarf['game_asset'] = True
scarf['part_category'] = 'ClothedBody'
scarf['intentional_layer'] = True
scarf['source'] = 'V16 one-piece compact front-open scarf with integrated diagonal folds'
scarf['no_ring_hose_plate'] = True

uv = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vi = mesh.loops[loop_index].vertex_index
        co = mesh.vertices[vi].co
        theta = math.atan2(co.y - 0.010, co.x)
        s = (theta + math.pi) / (2.0 * math.pi)
        height_v = clamp((co.z - 1.385) / 0.205)
        uv.data[loop_index].uv = (s * 3.0, height_v * 1.8)

# Compact Rigify weights: neck dominates the top, chest the lower drape, with
# only a small upper-arm share at the two clavicle lobes.
neck = scarf.vertex_groups.new(name='DEF-spine.006')
upper = scarf.vertex_groups.new(name='DEF-spine.005')
chest = scarf.vertex_groups.new(name='DEF-spine.004')
left_arm = scarf.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = scarf.vertex_groups.new(name='DEF-upper_arm.R')
for vertex in mesh.vertices:
    theta = math.atan2(vertex.co.y - 0.010, vertex.co.x)
    u = clamp((1.585 - vertex.co.z) / 0.205)
    side = abs(math.cos(theta))
    arm_weight = 0.105 * smoothstep((side - 0.80) / 0.20) * smoothstep((u - 0.65) / 0.35)
    torso = 1.0 - arm_weight
    neck_share = torso * (0.76 - 0.48 * smoothstep(u))
    chest_share = torso * (0.10 + 0.42 * smoothstep(u))
    upper_share = torso - neck_share - chest_share
    neck.add([vertex.index], neck_share, 'REPLACE')
    upper.add([vertex.index], upper_share, 'REPLACE')
    chest.add([vertex.index], chest_share, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')

for selected in bpy.context.selected_objects:
    selected.select_set(False)
scarf.select_set(True)
bpy.context.view_layer.objects.active = scarf
smooth = scarf.modifiers.new('VoxelClothSmoothing', 'SMOOTH')
smooth.factor = 0.24
smooth.iterations = 2
bpy.ops.object.modifier_apply(modifier=smooth.name)
scarf.select_set(False)

armature = scarf.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
scarf.parent = rig
scarf.matrix_parent_inverse = rig.matrix_world.inverted()


# Reuse the tested quilted closure only below the visible scarf.  It is not a
# visible ring or patch helper; it quietly restores the donor shoulder fabric.
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
for modifier in closure.modifiers:
    if modifier.type == 'ARMATURE':
        modifier.object = rig
closure.data.materials.clear()
closure.data.materials.append(bpy.data.materials['MAT_Gambeson_Side_PBR_4K'])
closure['game_asset'] = True
closure['part_category'] = 'ClothedBody'
closure['intentional_underlayer'] = True
closure['source'] = 'V16 low quilted shoulder seam closure below compact open scarf'

for obj in list(bpy.data.objects):
    if obj.type == 'ARMATURE' and obj is not rig and obj.name.startswith('Mercenary_Rigify_Rig_v4'):
        bpy.data.objects.remove(obj, do_unlink=True)


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
    output = PREVIEWS / f'diagnostic_v16_soft_open_scarf_agent_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render('top_close', (0.0, 0.0, 5.0), (0.0, 0.01, 1.49), 0.82, resolution=(1200, 900)),
    'high_angle': render('high_angle', (1.52, -1.92, 3.08), (0.0, 0.0, 1.47), lens=76),
    'upper_three_quarter': render('upper_three_quarter', (0.84, -1.48, 2.08), (0.0, 0.0, 1.48), lens=80),
    'front': render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
    'back': render('back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
}

bounds = {
    'min': [min(v.co[i] for v in scarf.data.vertices) for i in range(3)],
    'max': [max(v.co[i] for v in scarf.data.vertices) for i in range(3)],
}
report = {
    'candidate': str(OUTPUT),
    'source': str(SOURCE),
    'visible_scarf': scarf.name,
    'topology_description': 'one compact, front-open, near-vertical fabric volume with asymmetric ends and integrated diagonal folds',
    'visible_scarf_triangles': triangle_count(scarf),
    'visible_scarf_components': scarf_components,
    'visible_scarf_manifold': scarf_manifold,
    'visible_scarf_weight_sum_range': list(scarf_weight_range),
    'visible_scarf_bounds': bounds,
    'max_arm_weight': max((group.weight for vertex in scarf.data.vertices for group in vertex.groups if scarf.vertex_groups[group.group].name.startswith('DEF-upper_arm')), default=0.0),
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
    'previews': previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')

rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = 'PERSP'
camera.data.lens = 80
camera.location = (0.84, -1.48, 2.08)
look_at(camera, (0.0, 0.0, 1.48))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print(json.dumps(report, indent=2))
