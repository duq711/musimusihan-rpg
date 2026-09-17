"""Localized wrist remodeling and a section-preserving flexible cuff surface."""
import math
import bpy
import bmesh
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree

FLEX_START, FLEX_END = .014, .075
MIN_Z, MAX_Z = .010, .090
LIP_RADIUS = .0006
AXIAL_RINGS, SIDES = 33, 64


def smoothstep(a, b, value):
    t = max(0, min(1, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)


def native_points(obj, holder):
    matrix = holder.matrix_world.inverted() @ obj.matrix_world
    return [matrix @ vertex.co for vertex in obj.data.vertices]


def physical_vertex_ids(obj, minimum_component=1000):
    points = obj.data.vertices
    graph = [set() for unused in points]
    for edge in obj.data.edges:
        a, b = edge.vertices
        graph[a].add(b); graph[b].add(a)
    remaining, main = set(range(len(points))), set()
    while remaining:
        seed = remaining.pop()
        pending, ids = [seed], [seed]
        while pending:
            index = pending.pop()
            for neighbor in graph[index]:
                if neighbor in remaining:
                    remaining.remove(neighbor); ids.append(neighbor); pending.append(neighbor)
        if len(ids) >= minimum_component:
            main.update(ids)
    return main


def main_surface_tree(obj, holder, minimum_component=1000):
    points = native_points(obj, holder)
    main = physical_vertex_ids(obj, minimum_component)
    polygons = [list(p.vertices) for p in obj.data.polygons if all(i in main for i in p.vertices)]
    assert polygons, f"No physical main surface in {obj.name}"
    return BVHTree.FromPolygons(points, polygons, all_triangles=False)


def radial_hit(tree, y, angle, center_z=.001):
    direction = Vector((math.cos(angle), 0, math.sin(angle)))
    center = Vector((0, y, center_z))
    point, normal, face, distance = tree.ray_cast(center + direction * .13, -direction, .26)
    if point is None:
        return None
    return point, normal.normalized(), direction, (point - center).length


def refine_hand(skin, holder):
    tree = main_surface_tree(skin, holder)
    points = native_points(skin, holder)
    physical_ids = physical_vertex_ids(skin)
    native_to_local = skin.matrix_world.inverted() @ holder.matrix_world
    basis = skin.data.shape_keys.key_blocks['Basis']
    names = {group.index: group.name for group in skin.vertex_groups}
    changed, displacements, preserved = [], [], []
    for vertex in skin.data.vertices:
        dominant = max(vertex.groups, key=lambda group: group.weight)
        point = points[vertex.index]
        if names[dominant.group] != 'wrist' or point.y >= .010:
            preserved.append(vertex.index)
            continue
        angle = math.atan2(point.z - .001, point.x)
        direction = Vector((math.cos(angle), 0, math.sin(angle)))
        if vertex.index in physical_ids:
            # The open terminal cut is not star-shaped: its ray may hit the
            # far wall. Physical vertices must use their own radial position.
            original_radius = Vector((point.x, 0, point.z - .001)).length
        else:
            hit = radial_hit(tree, max(point.y, -.0195), angle)
            if hit is None:
                continue
            original_radius = hit[3]
        t = smoothstep(-.021, .010, point.y)
        radius_x, radius_z = .0355 + .0095 * t, .0235 + .0070 * t
        target_radius = 1 / math.sqrt((math.cos(angle) / radius_x) ** 2 + (math.sin(angle) / radius_z) ** 2)
        amount = (target_radius - original_radius) * (1 - smoothstep(-.0207, .010, point.y))
        if abs(amount) < 1e-7:
            continue
        new_point = native_to_local @ (point + direction * amount)
        original = basis.data[vertex.index].co.copy()
        deltas = [key.data[vertex.index].co - original for key in skin.data.shape_keys.key_blocks]
        skin.data.vertices[vertex.index].co = new_point
        for key, delta in zip(skin.data.shape_keys.key_blocks, deltas):
            key.data[vertex.index].co = new_point + delta
        changed.append(vertex.index)
        displacements.append(abs(amount))
    skin.data.update()
    bpy.context.view_layer.update()
    return {'changed_vertex_indices': changed, 'preserved_vertex_indices': preserved,
            'changed_vertices': len(changed), 'maximum_displacement_m': max(displacements, default=0),
            'native_blender_y_max': .010, 'ownership': 'wrist is the maximum bone weight',
            'method': 'smooth taper against original physical surface; all relative morph deltas retained'}


def build_profiles(skin, forearm, holder):
    hand_tree = main_surface_tree(skin, holder)
    arm_tree = main_surface_tree(forearm, holder, 2000)
    distal, proximal = [], []
    for j in range(SIDES):
        angle = math.tau * j / SIDES
        hand = radial_hit(hand_tree, -(MIN_Z + LIP_RADIUS), angle)
        arm = radial_hit(arm_tree, -(MAX_Z - LIP_RADIUS), angle)
        assert hand and arm, f"Physical cuff attachment section missing at angle {angle}"
        hand_point, unused, direction, unused2 = hand
        arm_point, unused, unused2, unused3 = arm
        distal.append(hand_point + direction * .00055)
        proximal.append(arm_point - direction * .00055)
    return distal, proximal, arm_tree


def cuff_profile(distal, proximal, angle, z):
    u = (angle % math.tau) / math.tau * SIDES
    a, b, fraction = int(u) % SIDES, (int(u) + 1) % SIDES, u % 1
    hand_point, arm_point = distal[a].lerp(distal[b], fraction), proximal[a].lerp(proximal[b], fraction)
    t = max(0, min(1, (z - MIN_Z - LIP_RADIUS) / (MAX_Z - MIN_Z - 2 * LIP_RADIUS)))
    point = hand_point.lerp(arm_point, t)
    point.y = -z
    # Fine leather irregularity remains restrained and vanishes at both contacts.
    radial = Vector((point.x, 0, point.z - .001)).normalized()
    wrinkle = .00024 * math.sin(math.pi * t) ** 2 * math.sin(t * 13 + angle * 2)
    return point + radial * wrinkle


def taper_forearm(forearm, holder, distal, proximal, original_tree):
    points = native_points(forearm, holder)
    native_to_local = forearm.matrix_world.inverted() @ holder.matrix_world
    physical_ids = physical_vertex_ids(forearm, 2000)
    changed, amounts, preserved = [], [], []
    old_start, new_start, end = .025, .077, .100
    # Positive, continuous axial derivative: 0.1 at the lip, 1 at .100 m.
    mean_slope = (end - new_start) / (end - old_start)
    power = .9 / (mean_slope - .1)
    for vertex, point in zip(forearm.data.vertices, points):
        z = -point.y
        if z >= end:
            preserved.append(vertex.index)
            continue
        t = max(0, min(1, (z - old_start) / (end - old_start)))
        new_z = new_start + (end - old_start) * (.1 * t + .9 * t ** power / power)
        angle = math.atan2(point.z - .001, point.x)
        radial = Vector((math.cos(angle), 0, math.sin(angle)))
        if vertex.index in physical_ids:
            old_radius = Vector((point.x, 0, point.z - .001)).length
        else:
            hit = radial_hit(original_tree, min(point.y, -.0255), angle)
            old_radius = hit[3] if hit else Vector((point.x, 0, point.z - .001)).length
        profile = cuff_profile(distal, proximal, angle, new_z)
        target_radius = Vector((profile.x, 0, profile.z - .001)).length + .0010
        amount = (target_radius - old_radius) * (1 - smoothstep(.079, end, new_z))
        new_point = point + radial * amount
        new_point.y = -new_z
        vertex.co = native_to_local @ new_point
        changed.append(vertex.index); amounts.append((new_point - point).length)
    forearm.data.update()
    after = native_points(forearm, holder)
    preservation_error = max(((after[i] - points[i]).length for i in preserved), default=0.0)
    assert preservation_error == 0.0
    return {'changed_vertex_indices': changed, 'preserved_vertex_indices': preserved,
            'changed_vertices': len(changed), 'preserved_vertices': len(preserved),
            'preserved_z_ge_100mm_max_error_m': preservation_error,
            'maximum_displacement_m': max(amounts, default=0),
            'native_godot_z_max': end, 'original_distal_z': old_start,
            'new_distal_z': new_start, 'overlap_with_full_follow_cuff_m': .013,
            'method': 'shorten rigid bracer locally to z=.077; positive smooth axial remap ends at .100; match cuff plus 1 mm clearance'}


def replace_cuff(cuff, holder, distal, proximal):
    native_to_local = cuff.matrix_world.inverted() @ holder.matrix_world
    points, faces = [], []
    levels = []
    z0, z1 = MIN_Z + LIP_RADIUS, MAX_Z - LIP_RADIUS
    for i in range(AXIAL_RINGS):
        levels.append((z0 + (z1 - z0) * i / (AXIAL_RINGS - 1), 0.0))
    for i in range(1, 5):
        angle = math.pi * i / 4
        levels.append((z1 + LIP_RADIUS * math.sin(angle), LIP_RADIUS * (math.cos(angle) - 1)))
    for i in range(AXIAL_RINGS - 2, -1, -1):
        levels.append((z0 + (z1 - z0) * i / (AXIAL_RINGS - 1), -2 * LIP_RADIUS))
    for i in range(1, 4):
        angle = math.pi + math.pi * i / 4
        levels.append((z0 + LIP_RADIUS * math.sin(angle), LIP_RADIUS * (math.cos(angle) - 1)))
    for z, inset in levels:
        for j in range(SIDES):
            angle = math.tau * j / SIDES
            point = cuff_profile(distal, proximal, angle, z)
            radial = Vector((point.x, 0, point.z - .001)).normalized()
            points.append(point + radial * inset)
    for i in range(len(levels)):
        for j in range(SIDES):
            a, b = i * SIDES + j, i * SIDES + (j + 1) % SIDES
            c, d = ((i + 1) % len(levels)) * SIDES + (j + 1) % SIDES, ((i + 1) % len(levels)) * SIDES + j
            faces.append((a, b, c, d))
    material = cuff.data.materials[0]
    mesh = bpy.data.meshes.new('WristTransitionMesh_v1')
    mesh.from_pydata([native_to_local @ point for point in points], [], faces)
    mesh.materials.append(material)
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    uv = mesh.uv_layers.new(name='WristLeather')
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        for index in polygon.loop_indices:
            vertex_id = mesh.loops[index].vertex_index
            level, around = divmod(vertex_id, SIDES)
            uv.data[index].uv = (around / SIDES, level / len(levels))
    mesh.update()
    cuff.data = mesh
    for target in (cuff, cuff.parent):
        target['wrist_flex_version'] = 1
        target['wrist_flex_start_z'] = FLEX_START
        target['wrist_flex_end_z'] = FLEX_END
    fixed = [i for i, point in enumerate(points) if -point.y <= FLEX_START]
    follow = [i for i, point in enumerate(points) if -point.y >= FLEX_END]
    return {'mesh_data': mesh.name, 'vertices': len(points), 'triangles': len(faces) * 2,
            'outer_axial_rings': AXIAL_RINGS, 'radial_samples': SIDES, 'wall_thickness_m': 2 * LIP_RADIUS,
            'native_godot_z_bounds': [MIN_Z, MAX_Z], 'flex_start_z': FLEX_START, 'flex_end_z': FLEX_END,
            'fixed_vertex_indices': fixed, 'forearm_follow_vertex_indices': follow,
            'outer_distal_vertex_indices': list(range(SIDES)),
            'outer_proximal_vertex_indices': list(range((AXIAL_RINGS - 1) * SIDES, AXIAL_RINGS * SIDES)),
            'surface_fit': 'distal 0.55 mm outside remodeled hand; proximal 0.55 mm inside original forearm main surface',
            'pose_contract': 'section center lerps to ForearmFit center; section rotation quaternion slerps from identity'}


def deform_preview_point(point, elbow_godot, flexible=False):
    """Match runtime section-rotation cuff contract in native Blender coordinates."""
    elbow = Vector((elbow_godot[0], -elbow_godot[2], elbow_godot[1]))
    rotation = Vector((0, -1, 0)).rotation_difference(elbow.normalized())
    scale = elbow.length / .26
    z = -point.y
    center = Vector((0, -z, 0))
    fitted_center = rotation @ (center * scale)
    radial = Vector((point.x, 0, point.z))
    if not flexible:
        return fitted_center + rotation @ radial
    weight = smoothstep(FLEX_START, FLEX_END, z)
    return center.lerp(fitted_center, weight) + Quaternion().slerp(rotation, weight) @ radial
