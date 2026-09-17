"""Fit only the standalone FPV leather cuffs around supplied wrist sections.

Public API: fit_cuff(hands) -> JSON-serializable report. Call after assembling
the actual supplied body/nails and reusing the old sleeve/cuff objects, before
export. No source file is opened or saved by this helper. The original hand,
shape keys, rig, character, cuff topology, UVs and node extras remain unchanged.
"""
import hashlib
import json

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _smooth(a, b, value):
    t = float(np.clip((value - a) / (b - a), 0., 1.))
    return t * t * (3. - 2. * t)


def _points(obj, holder):
    points = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get('co', points)
    points = points.reshape(-1, 3).astype(np.float64)
    transform = np.asarray(holder.matrix_world.inverted() @ obj.matrix_world)
    return points @ transform[:3, :3].T + transform[:3, 3]


def _bounds(points):
    return [[float(np.min(points[:, i])), float(np.max(points[:, i]))] for i in range(3)]


def _digest(values):
    return hashlib.sha256(np.asarray(values).tobytes()).hexdigest()


def _section(triangles, y):
    """Exact triangle/plane intersections in native x/z, including source cap."""
    rows = triangles[(triangles[:, :, 1].min(axis=1) <= y) &
                     (triangles[:, :, 1].max(axis=1) >= y)]
    result = []
    for i, j in ((0, 1), (1, 2), (2, 0)):
        a, b = rows[:, i], rows[:, j]
        valid = ((a[:, 1] - y) * (b[:, 1] - y) <= 0) & (np.abs(a[:, 1] - b[:, 1]) > 1e-10)
        a, b = a[valid], b[valid]
        t = (y - a[:, 1]) / (b[:, 1] - a[:, 1])
        result.extend((a + t[:, None] * (b - a))[:, (0, 2)])
    return np.asarray(result, dtype=np.float64).reshape(-1, 2)


def _data_signature(mesh):
    return {'topology': hashlib.sha256(json.dumps([list(p.vertices) for p in mesh.polygons]).encode()).hexdigest(),
        'uv': {u.name: hashlib.sha256(np.asarray([list(v.uv) for v in u.data], dtype=np.float32).tobytes()).hexdigest() for u in mesh.uv_layers},
        'materials': [m.name if m else None for m in mesh.materials],
        'face_materials': [p.material_index for p in mesh.polygons]}


def fit_cuff(hands):
    """Preserve axial rings and use a smooth enclosing ellipse for each section.

    All geometry at native y <= -.075 m stays byte-for-byte in place so the
    previous forearm seam and its fully following deformer region are retained.
    The distal rim stays at y=-.01 m (before wrist flex begins at Godot z=.014).
    Inner and outer shell offsets are retained, with 2.4 mm outer clearance
    over measured skin; the original ~1.2 mm wall leaves >1 mm inner clearance.
    """
    report = {'scope': 'Only standalone FPV WristCuff_Surface vertex positions and computed normals',
        'method': 'Exact supplied-body plane sections, smoothed center/radii, enclosing ellipses',
        'protected_native_y_max': -.075, 'outer_skin_clearance_m': .0024,
        'hand_geometry_and_all_character_objects_unchanged': True,
        'runtime_assumption': 'Existing unskinned cuff deformer reads positions and UV-derived export tangents; topology, y stations and node extras remain identical.',
        'hands': {}}
    for side, h in hands.items():
        holder = h['holder']; body = h['body']
        cuff = next(o for o in holder.children_recursive if o.type == 'MESH' and o.name == 'WristCuff_Surface_' + side)
        assert not cuff.data.shape_keys and not cuff.vertex_groups
        assert not any(m.type == 'ARMATURE' for m in cuff.modifiers)
        mesh = cuff.data
        assert mesh.users == 1, 'Cuff mesh must be a standalone copy before fitting'
        original = _points(cuff, holder)
        skin = _points(body, holder); skin_before = _digest(skin)
        protected = _data_signature(mesh)
        extras = {k: cuff.parent[k] for k in cuff.parent.keys()}
        assert extras.get('wrist_flex_version') == 1
        assert abs(float(extras['wrist_flex_start_z']) - .014) < 1e-6
        assert abs(float(extras['wrist_flex_end_z']) - .075) < 1e-6
        body.data.calc_loop_triangles()
        triangles = skin[np.asarray([list(t.vertices) for t in body.data.loop_triangles], dtype=np.int32)]
        stations = sorted(set(float(y) for y in original[:, 1]))
        profiles = []
        for y in stations:
            ids = np.flatnonzero(np.abs(original[:, 1] - y) < 1e-8)
            row = original[ids][:, (0, 2)]
            old_center = (row.min(axis=0) + row.max(axis=0)) / 2
            old_radii = (row.max(axis=0) - row.min(axis=0)) / 2
            section = _section(triangles, y) if y > -.075 else np.empty((0, 2))
            center = old_center.copy(); radii = old_radii.copy()
            if len(section) >= 6:
                skin_center = (section.min(axis=0) + section.max(axis=0)) / 2
                skin_radii = (section.max(axis=0) - section.min(axis=0)) / 2
                weight = _smooth(-.075, -.025, y)
                center = old_center * (1 - weight) + skin_center * weight
                radii = old_radii * (1 - weight) + (skin_radii + .0024) * weight
            profiles.append({'y': y, 'ids': ids, 'old_center': old_center,
                'old_radii': old_radii, 'center': center, 'radii': radii, 'section': section})
        # Gentle profile fairing suppresses tessellation-related section bumps.
        # The immutable forearm stations are excluded. Enclosure is rechecked
        # below after fairing, rather than allowing smoothing to intersect skin.
        for _ in range(2):
            updates = {}
            for i in range(1, len(profiles) - 1):
                p = profiles[i]
                if p['y'] <= -.075: continue
                updates[i] = tuple(.2 * profiles[i-1][field] + .6 * p[field] + .2 * profiles[i+1][field]
                                   for field in ('center', 'radii'))
            for i, (center, radii) in updates.items():
                profiles[i]['center'] = center; profiles[i]['radii'] = radii
        result = original.copy(); evidence = []
        for p in profiles:
            y = p['y']; ids = p['ids']
            if y <= -.075: continue
            center = p['center']; radii = p['radii']
            section = p['section']
            if len(section):
                # Fit the inner ellipse to every exact cross-section point,
                # then add the reserved shell/skin clearance outside it.
                inner = np.maximum(radii - .0024, .004)
                factor = max(1., float(np.linalg.norm((section - center) / inner, axis=1).max()))
                radii = inner * factor + .0024
            q = original[ids][:, (0, 2)] - p['old_center']
            old_distance = np.linalg.norm(q, axis=1)
            directions = q / old_distance[:, None]
            old_outer_distance = 1 / np.sqrt(np.sum((directions / p['old_radii']) ** 2, axis=1))
            shell_offset = old_distance - old_outer_distance
            new_outer_distance = 1 / np.sqrt(np.sum((directions / radii) ** 2, axis=1))
            result[np.ix_(ids, (0, 2))] = center + directions * (new_outer_distance + shell_offset)[:, None]
            evidence.append({'native_y': y, 'section_intersection_count': len(section),
                'center_xz': center.tolist(), 'outer_ellipse_radii_xz': radii.tolist(),
                'minimum_original_shell_offset_m': float(shell_offset.min())})
        transform = holder.matrix_world.inverted() @ cuff.matrix_world
        to_local = transform.inverted()
        for i, vertex in enumerate(mesh.vertices):
            if original[i, 1] > -.075:
                vertex.co = to_local @ Vector(result[i])
        mesh.update()
        # The old custom normals describe the previous radial taper. Zeros ask
        # Blender to recompute smooth corner normals from the fitted surface.
        mesh.normals_split_custom_set([(0., 0., 0.)] * len(mesh.loops))
        actual = _points(cuff, holder)
        immutable = original[:, 1] <= -.075
        assert np.array_equal(actual[immutable], original[immutable]), 'Forearm seam moved'
        assert np.max(np.abs(actual[:, 1] - original[:, 1])) < 1e-8
        assert _data_signature(mesh) == protected, 'Cuff topology, UVs or materials changed'
        assert {k: cuff.parent[k] for k in cuff.parent.keys()} == extras
        assert _digest(_points(body, holder)) == skin_before, 'Supplied skin changed'
        report['hands'][side] = {'object': cuff.name, 'vertices': len(mesh.vertices),
            'faces': len(mesh.polygons), 'before_bounds_native': _bounds(original),
            'after_bounds_native': _bounds(actual), 'maximum_vertex_shift_m': float(np.linalg.norm(actual-original, axis=1).max()),
            'immutable_forearm_vertices': int(immutable.sum()), 'unchanged_y_rings': len(stations),
            'topology_uv_material_signature': protected, 'preserved_deformer_extras': extras,
            'supplied_skin_vertices_sha256': skin_before, 'profiles': evidence}
    bpy.context.view_layer.update()
    return report


def audit_cuff_clearance(hands, *, section_count=48):
    """Read-only radial clearance to the inner cuff wall in the CURRENT pose.

    This samples the entire concealed skin between y=-.067 and -.011 m. Rays
    originate inside the cuff cavity and hit its inner surface first. Positive
    clearance seats the skin inside that wall; negative values expose a fit
    failure. It does not replace visual review or prove arbitrary pose safety.
    """
    report = {'method': 'Exact evaluated skin plane sections; radial BVH rays to actual cuff inner wall',
        'native_y_band': [-.067, -.011], 'section_count': section_count,
        'sampling_limitation': 'Finite axial sections and triangle intersection points in the current pose; not a continuous collision proof.',
        'hands': {}}
    dg = bpy.context.evaluated_depsgraph_get()
    for side, h in hands.items():
        holder = h['holder']; body = h['body']
        cuff = next(o for o in holder.children_recursive if o.type == 'MESH' and o.name == 'WristCuff_Surface_' + side)
        cuff_points = _points(cuff, holder)
        tree = BVHTree.FromPolygons([Vector(p) for p in cuff_points],
            [list(p.vertices) for p in cuff.data.polygons], all_triangles=False, epsilon=1e-9)
        evaluated = body.evaluated_get(dg); mesh = evaluated.to_mesh()
        try:
            transform = holder.matrix_world.inverted() @ body.matrix_world
            skin = np.asarray([list(transform @ v.co) for v in mesh.vertices])
            mesh.calc_loop_triangles()
            triangles = skin[np.asarray([list(t.vertices) for t in mesh.loop_triangles])]
        finally:
            evaluated.to_mesh_clear()
        cuff.data.calc_loop_triangles()
        cuff_triangles = cuff_points[np.asarray([list(t.vertices) for t in cuff.data.loop_triangles])]
        minimum = float('inf'); checked = 0; missing = 0; penetrations = 0; worst = None
        for y in np.linspace(-.067, -.011, section_count):
            surface = _section(triangles, y)
            shell = _section(cuff_triangles, y)
            center = (shell.max(axis=0) + shell.min(axis=0)) / 2
            origin = Vector((center[0], y, center[1]))
            for point in surface:
                delta = point - center; radius = float(np.linalg.norm(delta))
                if radius < 1e-8: continue
                direction = Vector((delta[0] / radius, 0, delta[1] / radius))
                hit, normal, face, distance = tree.ray_cast(origin, direction, .3)
                if hit is None: missing += 1; continue
                clearance = float(distance - radius); checked += 1
                if clearance < -1e-5: penetrations += 1
                if clearance < minimum:
                    minimum = clearance
                    worst = {'skin_point_native': [float(point[0]), float(y), float(point[1])],
                             'inner_cuff_hit_native': list(hit)}
        report['hands'][side] = {'tested_skin_section_points': checked,
            'missing_inner_wall_rays': missing, 'penetrating_sample_count': penetrations,
            'minimum_radial_clearance_m': minimum, 'worst_sample': worst,
            'sampled_clearance_pass': checked > 0 and missing == 0 and minimum >= -1e-5}
    return report
