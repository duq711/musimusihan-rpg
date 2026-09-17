"""Refine the v16 single shell into a compact, vertically bunched wool cowl.

This keeps the already validated one-component topology, UVs, Rigify weights,
and hair. Only the cowl vertex positions and wool response are adjusted.
"""

from __future__ import annotations

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
OUTPUT = STAGING / 'mercenary_crossbowman_game_ready_v16ah_compact_cowl_candidate.blend'
REPORT = STAGING / 'v16ah_compact_cowl_report.json'

ANGULAR_SEGMENTS = 176
DRAPE_SEGMENTS = 34
ROWS = DRAPE_SEGMENTS + 1
SURFACE_SIZE = ROWS * ANGULAR_SEGMENTS


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def shell_point(theta, u, inner=False):
    c = math.cos(theta)
    s = math.sin(theta)
    side = abs(c)
    front = max(0.0, -s)
    back = max(0.0, s)
    left = max(0.0, -c)
    right = max(0.0, c)

    # Compact neck opening, then a late localized flare over the trapezius.
    eased = smoothstep(u) ** 1.12
    shoulder = side ** 7.0
    top_rx = 0.118 + 0.004 * math.sin(3.0 * theta + 0.35)
    top_ry = 0.096 + 0.004 * math.sin(2.0 * theta - 0.55)
    bottom_rx = 0.185 + 0.145 * (side ** 11.0) + 0.006 * left
    bottom_ry = 0.145 + 0.025 * front + 0.125 * back
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # The hem tucks back under itself instead of projecting as a flat plate.
    hem = smoothstep((u - 0.84) / 0.16)
    rx -= (0.008 + 0.012 * (1.0 - shoulder)) * hem
    ry -= 0.010 * hem

    # Two broad folds meander strongly around the garment. They are relief in
    # one continuous shell, never separate rings or tubes.
    path_a = 0.285 + 0.145 * math.sin(theta + 0.48) + 0.042 * math.sin(3.0 * theta - 0.3)
    path_b = 0.650 + 0.165 * math.sin(theta - 0.90) - 0.035 * math.sin(3.0 * theta + 0.7)
    ridge_a = math.exp(-((u - path_a) / 0.105) ** 2)
    ridge_b = math.exp(-((u - path_b) / 0.125) ** 2)
    valley_a = math.exp(-((u - path_a - 0.135) / 0.095) ** 2)
    valley_b = math.exp(-((u - path_b - 0.155) / 0.105) ** 2)
    relief = 0.026 * ridge_a + 0.031 * ridge_b - 0.009 * valley_a - 0.010 * valley_b
    relief *= 0.84 + 0.16 * (front + side)
    relief += math.sin(math.pi * u) ** 1.3 * (
        0.0038 * math.sin(4.0 * theta + 0.8)
        + 0.0022 * math.sin(9.0 * theta - 0.4)
        + 0.0090 * math.sin(2.35 * math.pi * u + 1.15 * math.sin(theta + 0.35))
        + 0.0040 * math.sin(4.70 * math.pi * u - 1.35 * theta)
    )

    if inner:
        thickness = 0.0090 + 0.0010 * math.sin(3.0 * theta + 2.0 * u)
        rx -= thickness
        ry -= thickness * 0.88
        relief *= 0.72

    tangent = math.sin(math.pi * u) ** 1.4 * (
        0.0055 * math.sin(2.0 * theta + 1.8 * u)
        + 0.0025 * math.sin(5.0 * theta - 0.5)
    )
    x = -0.004 + (rx + relief) * c - tangent * s
    y = 0.010 + 0.010 * eased + (ry + 0.74 * relief) * s + tangent * c * 0.72

    # The cloth rises behind the neck and drops modestly at the front, giving
    # a wrapped scarf silhouette rather than a horizontal collar disc.
    top_z = (
        1.575 + 0.034 * back - 0.012 * front
        + 0.006 * side + 0.005 * math.sin(3.0 * theta + 0.2)
    )
    front_v = front ** 4.0
    bottom_z = (
        1.370 - 0.018 * shoulder - 0.012 * back - 0.024 * front_v
        - 0.004 * left + 0.003 * right
        + 0.006 * math.sin(5.0 * theta - 0.55)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += math.sin(math.pi * u) ** 1.3 * (
        0.013 * ridge_a + 0.016 * ridge_b
        + 0.0035 * math.sin(3.0 * theta + 2.0 * u)
        + 0.0018 * math.sin(8.0 * theta - 3.0 * u)
        + 0.0120 * math.sin(2.30 * math.pi * u + 1.10 * math.sin(theta + 0.40))
        + 0.0050 * math.sin(4.60 * math.pi * u - 1.25 * theta)
    )
    if inner:
        z -= 0.0015 * math.sin(math.pi * u)
    return x, y, z


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects['Mercenary_Rigify_Rig_v4']
donor = bpy.data.objects['Mercenary_Clothed_Donor_LOD0']
collection = donor.users_collection[0]
material_source = bpy.data.materials.get('MAT_CowlTop_SelectiveCharcoal_PBR_4K')
if material_source is None:
    material_source = bpy.data.materials['MAT_CowlWool_Side_PBR_4K']
material = material_source.copy()
for retired_name in (
    'Mercenary_Cowl_LayeredClean_LOD0',
    'Mercenary_UnderCowl_Yoke_LOD0',
    'Mercenary_ShoulderCowl_Gussets_LOD0',
    'Mercenary_RearShoulder_NotchPatches_LOD0',
    'Mercenary_InnerCowl_RolledCollar_LOD0',
):
    retired = bpy.data.objects.get(retired_name)
    if retired is None:
        continue
    retired_mesh = retired.data
    bpy.data.objects.remove(retired, do_unlink=True)
    if retired_mesh.users == 0:
        bpy.data.meshes.remove(retired_mesh)

vertices = []
parameters = []
for surface in (0, 1):
    for row in range(ROWS):
        u = row / DRAPE_SEGMENTS
        for angular in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular / ANGULAR_SEGMENTS
            vertices.append(shell_point(theta, u, inner=bool(surface)))
            parameters.append((surface, row, angular, u, theta))

settled_rear_vertices = 0
for vertex in donor.data.vertices:
    co = vertex.co
    radial = math.hypot(co.x, co.y - 0.010)
    if co.z <= 1.425 or co.y <= -0.055 or radial <= 0.098 or radial >= 0.415:
        continue
    height_gate = smoothstep((co.z - 1.425) / 0.055)
    rear_gate = smoothstep((co.y + 0.055) / 0.110)
    side_gate = 1.0 - smoothstep((abs(co.x) - 0.335) / 0.080)
    influence = height_gate * rear_gate * side_gate
    if influence <= 0.001:
        continue
    target_z = 1.382 + 0.012 * smoothstep((abs(co.x) - 0.245) / 0.130)
    target_y = 0.145 + 0.035 * smoothstep((abs(co.x) - 0.245) / 0.130)
    co.z = co.z * (1.0 - influence) + min(co.z, target_z) * influence
    if co.y > target_y:
        co.y = co.y * (1.0 - 0.65 * influence) + target_y * (0.65 * influence)
    settled_rear_vertices += 1
donor.data.update()
donor['v16_compact_cowl_hidden_rear_flap_settled'] = True
donor['v16_compact_cowl_hidden_rear_flap_vertex_count'] = settled_rear_vertices

faces = []
for row in range(DRAPE_SEGMENTS):
    for angular in range(ANGULAR_SEGMENTS):
        nxt = (angular + 1) % ANGULAR_SEGMENTS
        a = row * ANGULAR_SEGMENTS + angular
        b = (row + 1) * ANGULAR_SEGMENTS + angular
        c = (row + 1) * ANGULAR_SEGMENTS + nxt
        d = row * ANGULAR_SEGMENTS + nxt
        faces.append((a, b, c, d))
        faces.append((SURFACE_SIZE + d, SURFACE_SIZE + c, SURFACE_SIZE + b, SURFACE_SIZE + a))

bottom_start = DRAPE_SEGMENTS * ANGULAR_SEGMENTS
for angular in range(ANGULAR_SEGMENTS):
    nxt = (angular + 1) % ANGULAR_SEGMENTS
    faces.append((angular, nxt, SURFACE_SIZE + nxt, SURFACE_SIZE + angular))
    faces.append((
        bottom_start + angular,
        SURFACE_SIZE + bottom_start + angular,
        SURFACE_SIZE + bottom_start + nxt,
        bottom_start + nxt,
    ))

mesh = bpy.data.meshes.new('Mercenary_CompactWrappedCowl_LOD0_Mesh')
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

shell = bpy.data.objects.new('Mercenary_CompactWrappedCowl_LOD0', mesh)
collection.objects.link(shell)
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv = mesh.uv_layers.new(name='UVMap')
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        surface, row, angular, u, theta = parameters[vertex_index]
        uv.data[loop_index].uv = (angular / ANGULAR_SEGMENTS * 3.2, u * 2.0)

neck = shell.vertex_groups.new(name='DEF-spine.006')
upper = shell.vertex_groups.new(name='DEF-spine.005')
chest = shell.vertex_groups.new(name='DEF-spine.004')
left_arm = shell.vertex_groups.new(name='DEF-upper_arm.L')
right_arm = shell.vertex_groups.new(name='DEF-upper_arm.R')
for vertex, (_surface, _row, _angular, u, theta) in zip(mesh.vertices, parameters):
    side = abs(math.cos(theta))
    arm_weight = 0.20 * smoothstep((side - 0.76) / 0.24) * smoothstep((u - 0.76) / 0.24)
    torso = 1.0 - arm_weight
    neck_factor = 0.76 - 0.62 * smoothstep(u)
    chest_factor = 0.08 + 0.60 * smoothstep(u)
    upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
    normalizer = neck_factor + upper_factor + chest_factor
    neck.add([vertex.index], torso * neck_factor / normalizer, 'REPLACE')
    upper.add([vertex.index], torso * upper_factor / normalizer, 'REPLACE')
    chest.add([vertex.index], torso * chest_factor / normalizer, 'REPLACE')
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, 'REPLACE')

for selected in bpy.context.selected_objects:
    selected.select_set(False)
shell.select_set(True)
bpy.context.view_layer.objects.active = shell
bevel = shell.modifiers.new('SoftClothHem', 'BEVEL')
bevel.width = 0.0018
bevel.segments = 2
bevel.limit_method = 'ANGLE'
bevel.angle_limit = math.radians(42.0)
bpy.ops.object.modifier_apply(modifier=bevel.name)

armature = shell.modifiers.new('RigifyDeform', 'ARMATURE')
armature.object = rig
armature.use_deform_preserve_volume = True
shell.parent = rig
shell.matrix_parent_inverse = rig.matrix_world.inverted()
shell['game_asset'] = True
shell['part_category'] = 'ClothedBody'
shell['intentional_layer'] = True
shell['source'] = 'V16 compact one-piece vertically bunched cowl with two integrated asymmetric folds'
shell['no_tubes_stacks_patches'] = True

# Make the textile matte and charcoal instead of smooth black plastic.
for material in shell.data.materials:
    if not material or not material.use_nodes:
        continue
    material.name = 'MAT_CompactCowl_CharcoalWool_PBR_4K'
    principled = next((node for node in material.node_tree.nodes if node.type == 'BSDF_PRINCIPLED'), None)
    if principled:
        if principled.inputs.get('Roughness'):
            principled.inputs['Roughness'].default_value = 0.82
        if principled.inputs.get('Metallic'):
            principled.inputs['Metallic'].default_value = 0.0
        spec = principled.inputs.get('Specular IOR Level') or principled.inputs.get('Specular')
        if spec:
            spec.default_value = 0.28
    for node in material.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.name == 'BaseColor_4K':
            node.image = bpy.data.images.load(
                str(STAGING / 'textures' / 'cowl_wool_basecolor_4k_charcoal_v11.jpg'),
                check_existing=True,
            )
        if node.type == 'NORMAL_MAP' and node.inputs.get('Strength'):
            node.inputs['Strength'].default_value = min(node.inputs['Strength'].default_value, 0.55)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == 'MESH' and obj.get('part_category') is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)

for name in ('Mercenary_Rigify_Rig_v4', 'metarig_mercenary_v4'):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True
        obj.hide_set(True)

scene.render.engine = 'BLENDER_EEVEE'
scene.render.image_settings.file_format = 'PNG'
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=78, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = 'PERSP'
        camera.data.lens = lens
    else:
        camera.data.type = 'ORTHO'
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f'diagnostic_v16ah_compact_cowl_{key}.png'
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {
    'top_close': render('top_close', (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.84, resolution=(1200, 900)),
    'high_angle': render('high_angle', (1.58, -1.98, 3.18), (0.0, 0.01, 1.45), lens=76),
    'upper_three_quarter': render('upper_three_quarter', (0.86, -1.50, 2.10), (0.0, 0.0, 1.47), lens=80),
    'front': render('front', (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
    'back': render('back', (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06),
}

report = {
    'candidate': str(OUTPUT),
    'source': str(SOURCE),
    'visible_shell': shell.name,
    'topology_description': 'one continuous compact neck cowl; two asymmetric integrated folds; no separate rings or pads',
    'character_meshes': len(character_meshes),
    'character_triangles': total_triangles,
    'cowl_triangles': triangle_count(shell),
    'settled_hidden_rear_vertices': settled_rear_vertices,
    'deform_bones': sum(1 for bone in bpy.data.objects['Mercenary_Rigify_Rig_v4'].data.bones if bone.use_deform),
    'pose': 'T-pose unchanged',
    'production_modified': False,
    'previews': previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding='utf-8')

camera.data.type = 'PERSP'
camera.data.lens = 80
camera.location = (0.86, -1.50, 2.10)
look_at(camera, (0.0, 0.0, 1.47))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
