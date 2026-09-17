"""Build a non-destructive clean hair candidate on top of v15.

The v15 head is preserved.  Its projected crown reads as a clipped vertical-
striped cap in overhead views, so this candidate adds a fitted, watertight,
dark-brown scalp shell plus short closed fringe clumps.  Everything is bound
only to Rigify's head deform bone and remains in the authored T-pose.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING = ROOT / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
PREVIEWS = STAGING / 'previews'
SOURCE = STAGING / 'mercenary_crossbowman_game_ready_v15.blend'
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16_hair_candidate.blend'
REPORT = STAGING / 'v16_hair_candidate_report.json'
HAIR_TEXTURE = STAGING / 'textures' / 'hair_scalp_darkbrown_2k_v11.png'


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects['Mercenary_Rigify_Rig_v4']
head = bpy.data.objects['Mercenary_Male_HeadNeck_LOD0']
asset_collection = head.users_collection[0]


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def nonmanifold_edge_count(obj):
    counts = defaultdict(int)
    for poly in obj.data.polygons:
        vs = list(poly.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            counts[tuple(sorted((a, b)))] += 1
    return sum(value != 2 for value in counts.values())


def weight_range(obj):
    sums = [sum(g.weight for g in v.groups) for v in obj.data.vertices]
    return min(sums), max(sums)


def bind_to_head(obj):
    group = obj.vertex_groups.new(name='DEF-spine.006')
    group.add([v.index for v in obj.data.vertices], 1.0, 'REPLACE')
    arm = obj.modifiers.new('RigifyDeform', 'ARMATURE')
    arm.object = rig
    arm.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def tag_hair(obj, source):
    obj['game_asset'] = True
    obj['part_category'] = 'Hair'
    obj['intentional_layer'] = True
    obj['source'] = source


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


# A simple image-based Principled material survives glTF export.  The source
# texture is the project's opaque dark-brown strand map; the new UVs follow
# crown-to-hairline flow rather than planar XY projection.
hair_image = bpy.data.images.load(str(HAIR_TEXTURE), check_existing=True)
hair_mat = bpy.data.materials.new('MAT_Hair_DarkBrown_Flow_2K_v16')
hair_mat.use_nodes = True
hair_mat.diffuse_color = (0.075, 0.035, 0.014, 1.0)
hair_mat.roughness = 0.62
hair_mat.use_backface_culling = False
nodes = hair_mat.node_tree.nodes
nodes.clear()
out = nodes.new('ShaderNodeOutputMaterial')
shader = nodes.new('ShaderNodeBsdfPrincipled')
tex = nodes.new('ShaderNodeTexImage')
tex.image = hair_image
tex.extension = 'REPEAT'
tex.interpolation = 'Linear'
shader.inputs['Roughness'].default_value = 0.62
shader.inputs['Metallic'].default_value = 0.0
if 'Anisotropic IOR Level' in shader.inputs:
    shader.inputs['Anisotropic IOR Level'].default_value = 0.28
elif 'Anisotropic' in shader.inputs:
    shader.inputs['Anisotropic'].default_value = 0.28
bump = nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value = 0.17
bump.inputs['Distance'].default_value = 0.0015
hair_mat.node_tree.links.new(tex.outputs['Color'], shader.inputs['Base Color'])
hair_mat.node_tree.links.new(tex.outputs['Color'], bump.inputs['Height'])
hair_mat.node_tree.links.new(bump.outputs['Normal'], shader.inputs['Normal'])
hair_mat.node_tree.links.new(shader.outputs['BSDF'], out.inputs['Surface'])


# Skull fit derived from v15 head bounds.  Front is -Y.  The front hairline is
# kept high and slightly behind the original projected fringe, while side/back
# hair extends lower.  Mild deterministic lobing breaks the helmet silhouette.
CX, CY, CZ = 0.0, 0.012, 1.646
RX, RY, RZ = 0.126, 0.117, 0.149
SEGMENTS = 64
RINGS = 18
THICKNESS = 0.0055


def theta_max(phi):
    s = math.sin(phi)
    if s < 0.0:  # front: stop above the brow
        theta = 1.50 + (-s) * (1.29 - 1.50)
    else:  # back: descend to the upper nape
        theta = 1.50 + s * (1.73 - 1.50)
    return theta + 0.025 * math.sin(3.0 * phi + 0.7) + 0.014 * math.sin(7.0 * phi - 0.9)


def scalp_point(phi, t, inner=False, extra=0.0):
    theta = t * theta_max(phi)
    shrink = THICKNESS if inner else 0.0
    # The irregularity fades at the crown so all radial strips meet cleanly.
    lobe = (0.020 * math.sin(5.0 * phi + 0.8) + 0.010 * math.sin(9.0 * phi - 0.2)) * min(1.0, t * 1.7)
    rx = (RX - shrink) * (1.0 + lobe)
    ry = (RY - shrink) * (1.0 + lobe * 0.65)
    rz = RZ - shrink
    return Vector((
        CX + (rx + extra) * math.sin(theta) * math.cos(phi),
        CY + (ry + extra) * math.sin(theta) * math.sin(phi),
        CZ + (rz + extra * 0.55) * math.cos(theta),
    ))


cap_vertices = []
cap_faces = []
cap_uv_hint = []

# Outer crown vertex, then outer rings.
outer_top = len(cap_vertices)
cap_vertices.append((CX, CY, CZ + RZ))
cap_uv_hint.append((0.5, 0.0))
outer_rings = []
for ring in range(1, RINGS + 1):
    t = ring / RINGS
    indices = []
    for seg in range(SEGMENTS):
        phi = -math.pi + (2.0 * math.pi * seg / SEGMENTS)
        indices.append(len(cap_vertices))
        cap_vertices.append(tuple(scalp_point(phi, t)))
        cap_uv_hint.append((seg / SEGMENTS, t))
    outer_rings.append(indices)

for seg in range(SEGMENTS):
    nxt = (seg + 1) % SEGMENTS
    cap_faces.append((outer_top, outer_rings[0][seg], outer_rings[0][nxt]))
for ring in range(RINGS - 1):
    a, b = outer_rings[ring], outer_rings[ring + 1]
    for seg in range(SEGMENTS):
        nxt = (seg + 1) % SEGMENTS
        cap_faces.append((a[seg], b[seg], b[nxt], a[nxt]))

# Inner surface, oriented inward.
inner_top = len(cap_vertices)
cap_vertices.append((CX, CY, CZ + RZ - THICKNESS))
cap_uv_hint.append((0.5, 0.0))
inner_rings = []
for ring in range(1, RINGS + 1):
    t = ring / RINGS
    indices = []
    for seg in range(SEGMENTS):
        phi = -math.pi + (2.0 * math.pi * seg / SEGMENTS)
        indices.append(len(cap_vertices))
        cap_vertices.append(tuple(scalp_point(phi, t, inner=True)))
        cap_uv_hint.append((seg / SEGMENTS, t))
    inner_rings.append(indices)

for seg in range(SEGMENTS):
    nxt = (seg + 1) % SEGMENTS
    cap_faces.append((inner_top, inner_rings[0][nxt], inner_rings[0][seg]))
for ring in range(RINGS - 1):
    a, b = inner_rings[ring], inner_rings[ring + 1]
    for seg in range(SEGMENTS):
        nxt = (seg + 1) % SEGMENTS
        cap_faces.append((a[seg], a[nxt], b[nxt], b[seg]))

# Sew outer and inner hairline boundaries into one closed shell.
for seg in range(SEGMENTS):
    nxt = (seg + 1) % SEGMENTS
    cap_faces.append((outer_rings[-1][seg], inner_rings[-1][seg], inner_rings[-1][nxt], outer_rings[-1][nxt]))

cap_mesh = bpy.data.meshes.new('Mercenary_CleanHairCap_LOD0_Mesh')
cap_mesh.from_pydata(cap_vertices, [], cap_faces)
cap_mesh.materials.append(hair_mat)
cap_uv = cap_mesh.uv_layers.new(name='UVMap')
for poly in cap_mesh.polygons:
    raw = [cap_uv_hint[cap_mesh.loops[i].vertex_index] for i in poly.loop_indices]
    us = [u for u, _v in raw]
    if max(us) - min(us) > 0.5:
        raw = [(u + 1.0 if u < 0.5 else u, v) for u, v in raw]
    # The source contains many thin vertical strands.  V follows the flow
    # direction; U wraps around the crown.
    for loop_index, (u, v) in zip(poly.loop_indices, raw):
        cap_uv.data[loop_index].uv = (u, v * 1.20)
    poly.use_smooth = True
cap_mesh.update()
cap = bpy.data.objects.new('Mercenary_CleanHairCap_LOD0', cap_mesh)
asset_collection.objects.link(cap)
tag_hair(cap, 'V16 fitted closed dark-brown scalp shell; original v15 face preserved')
bind_to_head(cap)


# Closed flattened locks overlap only the hairline.  They are short enough not
# to cover the eyes or alter the facial likeness, but their tapered tips remove
# the perfectly circular cap edge from top and three-quarter views.
lock_vertices = []
lock_faces = []
lock_uv_hint = []
LOCK_SECTIONS = 6
lock_count = 28
for lock_index in range(lock_count):
    phi0 = -math.pi + 2.0 * math.pi * (lock_index + 0.37 * math.sin(lock_index * 2.11)) / lock_count
    frontness = max(0.0, -math.sin(phi0))
    root_t = 0.62 + 0.05 * math.sin(lock_index * 1.73)
    tip_t = 1.035 + 0.055 * (0.5 + 0.5 * math.sin(lock_index * 2.47 + 0.4))
    sweep = 0.075 * math.sin(lock_index * 1.91)
    base_width = 0.010 + 0.0025 * (0.5 + 0.5 * math.sin(lock_index * 1.17))
    sections = []
    for section in range(LOCK_SECTIONS):
        s = section / (LOCK_SECTIONS - 1)
        smooth = s * s * (3.0 - 2.0 * s)
        t = root_t + (tip_t - root_t) * smooth
        phi = phi0 + sweep * math.sin(math.pi * s)
        center = scalp_point(phi, t, extra=0.0045 + 0.0015 * math.sin(math.pi * s))
        eps = 0.004
        tangent = (scalp_point(phi + eps, min(t, 1.04)) - scalp_point(phi - eps, min(t, 1.04))).normalized()
        outward = Vector((
            (center.x - CX) / RX,
            (center.y - CY) / RY,
            (center.z - CZ) / RZ,
        )).normalized()
        width = base_width * (0.92 + 0.18 * math.sin(math.pi * s)) * ((1.0 - s) ** 0.36)
        width = max(width, 0.0012)
        thickness = 0.0034 * (1.0 - 0.55 * s)
        left = center - tangent * width
        right = center + tangent * width
        indices = []
        for point in (left + outward * thickness, right + outward * thickness, right, left):
            indices.append(len(lock_vertices))
            lock_vertices.append(tuple(point))
            lock_uv_hint.append((0.15 + 0.70 * (len(indices) in (2, 3)), s * 1.35 + lock_index * 0.071))
        sections.append(indices)
    # Each section is [top-left, top-right, bottom-right, bottom-left].
    for section in range(LOCK_SECTIONS - 1):
        a, b = sections[section], sections[section + 1]
        lock_faces.extend((
            (a[0], b[0], b[1], a[1]),
            (a[3], a[2], b[2], b[3]),
            (a[0], a[3], b[3], b[0]),
            (a[1], b[1], b[2], a[2]),
        ))
    root, tip = sections[0], sections[-1]
    lock_faces.append((root[0], root[1], root[2], root[3]))
    lock_faces.append((tip[0], tip[3], tip[2], tip[1]))

lock_mesh = bpy.data.meshes.new('Mercenary_HairlineTufts_LOD0_Mesh')
lock_mesh.from_pydata(lock_vertices, [], lock_faces)
lock_mesh.materials.append(hair_mat)
lock_uv = lock_mesh.uv_layers.new(name='UVMap')
for poly in lock_mesh.polygons:
    for loop_index in poly.loop_indices:
        u, v = lock_uv_hint[lock_mesh.loops[loop_index].vertex_index]
        lock_uv.data[loop_index].uv = (u, v)
    poly.use_smooth = True
lock_mesh.update()
locks = bpy.data.objects.new('Mercenary_HairlineTufts_LOD0', lock_mesh)
asset_collection.objects.link(locks)
tag_hair(locks, 'V16 short closed perimeter hair clumps; no face coverage')
bind_to_head(locks)


# Validation before rendering.
new_objects = (cap, locks)
for obj in new_objects:
    nm = nonmanifold_edge_count(obj)
    wr = weight_range(obj)
    if nm != 0:
        raise RuntimeError(f'{obj.name}: nonmanifold edges={nm}')
    if wr[0] < 0.999 or wr[1] > 1.001:
        raise RuntimeError(f'{obj.name}: invalid weight sums={wr}')
    if not any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers):
        raise RuntimeError(f'{obj.name}: missing Rigify modifier')

character_meshes = [obj for obj in scene.objects if obj.type == 'MESH' and obj.get('part_category') is not None]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f'Triangle budget failed: {total_triangles}')

for name in ('Mercenary_Rigify_Rig_v4', 'metarig_mercenary_v4'):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True

scene.render.engine = 'BLENDER_EEVEE'
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'


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
    path = PREVIEWS / f'diagnostic_v16_hair_{key}.png'
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


render('top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render('three_quarter', (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)
render('head_three_quarter', (0.75, -1.35, 1.93), (0.0, 0.0, 1.69), lens=78, resolution=(1200, 1000))
render('back_head', (0.0, 1.55, 1.83), (0.0, 0.015, 1.67), lens=82, resolution=(1100, 1000))

rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

report = {
    'source': str(SOURCE),
    'candidate': str(OUTPUT),
    'objects': {
        obj.name: {
            'vertices': len(obj.data.vertices),
            'triangles': triangle_count(obj),
            'nonmanifold_edges': nonmanifold_edge_count(obj),
            'weight_sum_range': list(weight_range(obj)),
            'rigify_modifier': any(mod.type == 'ARMATURE' and mod.object == rig for mod in obj.modifiers),
        }
        for obj in new_objects
    },
    'character_mesh_count': len(character_meshes),
    'character_triangles': total_triangles,
    'deform_bones': sum(1 for bone in rig.data.bones if bone.use_deform),
    'original_head_preserved': bpy.data.objects.get('Mercenary_Male_HeadNeck_LOD0') is head,
    'pose': 'T-pose unchanged',
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
print('WROTE', OUTPUT)

