"""Independent fixed-mask surface review of the Labrador sprint repair.

Run in Mac Blender in the background. Only the requested JSON receipt is saved.
Original failed Sprint defines topology, weights and all review masks. The two
historical mask selections are preserved separately, not silently narrowed.
Intersection counts are selected nonadjacent surface pairs, never full-mesh
penetration depth/volume. Skin area ratios are deformation diagnostics; actual
proximal shape and full-cycle readability require rendered visual review.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import intersect_ray_tri

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import set_action


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def array_digest(value):
    return hashlib.sha256(np.ascontiguousarray(value).tobytes()).hexdigest()


def select_scene(path):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    return bpy.data.objects['LabradorPet'], bpy.data.objects['LabradorPet_Mesh']


def bind_data(mesh):
    mesh.data.calc_loop_triangles()
    triangles = np.asarray([list(t.vertices) for t in mesh.data.loop_triangles], dtype=np.int32)
    weights = np.zeros((len(mesh.data.vertices), len(mesh.vertex_groups)), dtype=np.float32)
    for vertex in mesh.data.vertices:
        for group in vertex.groups:
            weights[vertex.index, group.group] = group.weight
    names = [group.name for group in mesh.vertex_groups]
    positions = np.asarray([list(vertex.co) for vertex in mesh.data.vertices], dtype=np.float32)
    signatures = {'triangles': array_digest(triangles), 'weights': array_digest(weights),
                  'rest_vertices': array_digest(positions),
                  'vertex_group_order': hashlib.sha256(json.dumps(names).encode()).hexdigest()}
    return triangles, weights, names, signatures


def fixed_masks(triangles, weights, names):
    def region(prefixes):
        ids = [i for i, name in enumerate(names) if name.startswith(prefixes)]
        return weights[:, ids].sum(axis=1)

    def faces(values, threshold=.55):
        return np.flatnonzero(values[triangles].mean(axis=1) > threshold)

    fore_names = [f'Front{part}.{side}_{number}' for side, numbers in
                  [('L', [18, 17, 16]), ('R', [21, 20, 19])]
                  for part, number in zip(['Shoulder', 'UpperLeg', 'LowerLeg'], numbers)]
    original = {name: faces(weights[:, names.index(name)]) for name in fore_names}
    mask = {'historical_exact_chest': faces(region(('Torso', 'Back_'))),
            'historical_bvh_body': faces(region(('Torso', 'Neck'))),
            'historical_bvh_fore': faces(region(('FrontUpperLeg', 'FrontLowerLeg'))),
            **original}
    body = region(('Torso', 'Back_', 'Neck', 'Head_', 'Mouth', 'Jaw', 'Nose', 'Muzzle'))
    mask['broader_body_head'] = faces(body)
    limbs = {
        'all_front.L': ['FrontShoulder.L_18', 'FrontUpperLeg.L_17', 'FrontLowerLeg.L_16', 'IKFrontLeg.L_47', 'FF.L_46'],
        'all_front.R': ['FrontShoulder.R_21', 'FrontUpperLeg.R_20', 'FrontLowerLeg.R_19', 'IKFrontLeg.R_51', 'FF.R_50'],
        'all_hind.L': ['BackShoulder.L_27', 'BackLeg.L_26', 'BackUpperLeg.L_25', 'BackLowerLeg.L_24', 'IKBackLeg.L_45', 'FFB.L_44'],
        'all_hind.R': ['BackShoulder.R_31', 'BackLeg.R_30', 'BackUpperLeg.R_29', 'BackLowerLeg.R_28', 'IKBackLeg.R_49', 'FFB.R_48'],
    }
    for key, groups in limbs.items():
        mask[key] = faces(weights[:, [names.index(n) for n in groups]].sum(axis=1))
    # Shoulder alone never reaches55% original weight. Add its original mixed
    # chest/upper-arm junction without changing either historical test region.
    for side in ['L', 'R']:
        ids = [names.index(n) for n in fore_names if f'.{side}_' in n and not 'Lower' in n]
        proximal = weights[:, ids].sum(axis=1)
        mixed = (proximal > .10) & (body > .05)
        mask[f'mixed_proximal.{side}'] = np.flatnonzero(mixed[triangles].sum(axis=1) >= 2)
    return mask, fore_names


def sample(rig, mesh, action, frame):
    set_action(rig, bpy.data.actions[action])
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    world = np.asarray([list(evaluated.matrix_world @ v.co) for v in data.vertices], dtype=np.float64)
    evaluated.to_mesh_clear()
    matrices = {b.name: rig.matrix_world @ b.matrix for b in rig.pose.bones}
    return world, matrices


def triangle_areas(world, triangles):
    points = world[triangles]
    return np.linalg.norm(np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0]), axis=1) / 2


def coplanar_overlap_area(a, b, epsilon=1e-7):
    """Projected clipped triangle area for coplanar candidates, separately reported."""
    normal = np.cross(a[1] - a[0], a[2] - a[0])
    size = np.linalg.norm(normal)
    if size < 1e-14:
        return 0.
    normal /= size
    other = np.cross(b[1] - b[0], b[2] - b[0])
    other_size = np.linalg.norm(other)
    if other_size < 1e-14 or abs(np.dot(normal, other / other_size)) < 1 - 1e-7:
        return 0.
    if np.max(np.abs((b - a[0]) @ normal)) > epsilon:
        return 0.
    drop = int(np.argmax(np.abs(normal)))
    aa = np.delete(a, drop, axis=1)
    bb = np.delete(b, drop, axis=1)
    cross = lambda x, y: x[0] * y[1] - x[1] * y[0]
    orientation = 1 if cross(bb[1] - bb[0], bb[2] - bb[0]) >= 0 else -1
    polygon = list(aa)
    for i in range(3):
        start, end = bb[i], bb[(i + 1) % 3]
        edge = end - start
        signed = lambda p: orientation * cross(edge, p - start)
        clipped = []
        if not polygon:
            return 0.
        previous = polygon[-1]
        previous_d = signed(previous)
        for point in polygon:
            point_d = signed(point)
            if (point_d >= 0) != (previous_d >= 0):
                fraction = previous_d / (previous_d - point_d)
                clipped.append(previous + fraction * (point - previous))
            if point_d >= 0:
                clipped.append(point)
            previous, previous_d = point, point_d
        polygon = clipped
    if len(polygon) < 3:
        return 0.
    area = abs(sum(cross(polygon[i], polygon[(i + 1) % len(polygon)])
                   for i in range(len(polygon)))) / 2
    return float(area / abs(normal[drop]))


def intersections(world, triangles, first, second, vectors, trees):
    if not len(first) or not len(second):
        return {'bvh_nonadjacent_pairs': 0, 'exact_crossing_pairs': 0,
                'coplanar_area_overlap_pairs': 0, 'examples': []}
    a, b = trees[id(first)], trees[id(second)]
    exact, coplanar, broad = [], [], 0
    for ia, ib in a.overlap(b):
        face_a, face_b = int(first[ia]), int(second[ib])
        aa, bb = triangles[face_a], triangles[face_b]
        if set(aa) & set(bb):
            continue  # intended shared-vertex junction/adjacency is excluded
        broad += 1
        points = []
        for source, target in ((aa, bb), (bb, aa)):
            for j in range(3):
                origin = vectors[source[j]]
                direction = vectors[source[(j + 1) % 3]] - origin
                if direction.length < 1e-8:
                    continue
                point = intersect_ray_tri(*(vectors[k] for k in target), direction, origin, True)
                if point is not None:
                    t = (point - origin).dot(direction) / direction.length_squared
                    # Original diagnosis policy retained: an interior segment
                    # crosses a triangle, with a nonzero crossing line length.
                    if .000001 < t < .999999:
                        points.append(point)
        if len(points) >= 2 and max((p - q).length for p in points for q in points) > 1e-5:
            exact.append((face_a, face_b))
        elif coplanar_overlap_area(world[aa], world[bb]) > 1e-10:
            coplanar.append((face_a, face_b))
    return {'bvh_nonadjacent_pairs': broad, 'exact_crossing_pairs': len(exact),
            'coplanar_area_overlap_pairs': len(coplanar),
            'examples': {'exact': exact[:3], 'coplanar': coplanar[:3]}}


def pose_metrics(matrices, neutral):
    result = {}
    for side, suffixes in [('L', [17, 16, 47]), ('R', [20, 19, 51])]:
        upper, lower, ankle = [f'{prefix}.{side}_{suffix}' for prefix, suffix in
                               zip(['FrontUpperLeg', 'FrontLowerLeg', 'IKFrontLeg'], suffixes)]
        shoulder = matrices[upper].translation
        elbow = matrices[lower].translation
        wrist = matrices[ankle].translation
        vector = elbow - shoulder
        neutral_vector = neutral[lower].translation - neutral[upper].translation
        result[side] = {'humerus_rotation_from_neutral_deg': math.degrees(vector.angle(neutral_vector)),
                        'elbow_above_shoulder_m': elbow.z - shoulder.z,
                        'humerus_length_m': vector.length, 'forearm_length_m': (wrist - elbow).length,
                        'humerus_unit_direction': list(vector.normalized()),
                        'elbow_internal_angle_deg': math.degrees((-vector).angle(wrist - elbow)),
                        'shoulder_world_m': list(shoulder), 'elbow_world_m': list(elbow),
                        'wrist_world_m': list(wrist)}
    return result


def surface_row(world, triangles, masks, area_reference, matrices, neutral, phase):
    vectors = [Vector(v) for v in world]
    used = {key for pair in PAIRS.values() for key in pair}
    trees = {id(masks[key]): BVHTree.FromPolygons(vectors, [list(triangles[i]) for i in masks[key]],
                                                   all_triangles=True, epsilon=0)
             for key in used if len(masks[key])}
    overlaps = {key: intersections(world, triangles, masks[a], masks[b], vectors, trees)
                for key, (a, b) in PAIRS.items()}
    areas = triangle_areas(world, triangles)
    deform = {}
    for key in AREA_REGIONS:
        indices = masks[key]
        if not len(indices):
            deform[key] = {'triangles': 0}
            continue
        ratio = areas[indices] / np.maximum(area_reference[indices], 1e-12)
        worst = int(indices[int(np.argmin(ratio))])
        compressed = indices[ratio < .2]
        deform[key] = {'triangles': len(indices), 'area_ratio_min': float(ratio.min()),
                       'area_ratio_p05': float(np.quantile(ratio, .05)),
                       'area_ratio_median': float(np.median(ratio)),
                       'triangles_under20pct_neutral_area': int((ratio < .2).sum()),
                       'compressed_triangles_total_neutral_area_m2': float(area_reference[compressed].sum()),
                       'compressed_triangles_total_current_area_m2': float(areas[compressed].sum()),
                       'worst_triangle_id': worst,
                       'worst_triangle_neutral_area_m2': float(area_reference[worst]),
                       'worst_triangle_current_area_m2': float(areas[worst]),
                       'worst_triangle_vertices': list(map(int, triangles[worst]))}
    return {'phase': phase, 'intersections': overlaps, 'skin_area': deform,
            'fore_pose': pose_metrics(matrices, neutral)}


def main():
    global PAIRS, AREA_REGIONS
    parser = argparse.ArgumentParser()
    parser.add_argument('--baseline', required=True, type=Path)
    parser.add_argument('--blend', required=True, type=Path)
    parser.add_argument('--report', required=True, type=Path)
    parser.add_argument('--hz', default=120., type=float)
    parser.add_argument('--baseline-only', action='store_true')
    parser.add_argument('--gltf', type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    baseline_sha_loaded = digest(args.baseline)
    candidate_sha_loaded = digest(args.blend)
    gltf_sha_loaded = digest(args.gltf) if args.gltf else None
    rig, mesh = select_scene(args.baseline)
    triangles, weights, names, signatures = bind_data(mesh)
    masks, fore_names = fixed_masks(triangles, weights, names)
    PAIRS = {f'original_exact:{name}': ('historical_exact_chest', name) for name in fore_names}
    PAIRS['original_combined_fore'] = ('historical_bvh_body', 'historical_bvh_fore')
    PAIRS.update({key: ('broader_body_head', key) for key in masks if key.startswith('all_')})
    AREA_REGIONS = fore_names + ['historical_bvh_fore', 'mixed_proximal.L', 'mixed_proximal.R']
    mask_receipt = {key: {'triangle_count': len(ids), 'fixed_original_id_sha256': array_digest(ids.astype(np.int32))}
                    for key, ids in masks.items()}
    assert len(masks['historical_bvh_body']) == 12401
    assert len(masks['historical_bvh_fore']) == 3971
    neutral_world, neutral_matrices = sample(rig, mesh, 'IdleFriendly', 1)
    reference_areas = triangle_areas(neutral_world, triangles)
    old_world, old_matrices = sample(rig, mesh, 'Run', 38.8)
    neutral_row = surface_row(neutral_world, triangles, masks, reference_areas,
                              neutral_matrices, neutral_matrices, None)
    old_row = surface_row(old_world, triangles, masks, reference_areas, old_matrices, neutral_matrices, .9)
    historical_exact = sum(old_row['intersections'][f'original_exact:{name}']['exact_crossing_pairs'] for name in fore_names)
    assert historical_exact == 198, f'Historical exact198 reproduction changed: {historical_exact}'
    assert old_row['intersections']['original_combined_fore']['bvh_nonadjacent_pairs'] == 232
    rows = []
    gltf_rows = []
    gltf_comparison = []
    export_skin = None
    regular_samples = authored_keys_included = 0
    candidate_signatures = signatures
    if not args.baseline_only:
        rig, mesh = select_scene(args.blend)
        _, _, _, candidate_signatures = bind_data(mesh)
        assert candidate_signatures == signatures, 'Rest vertices, topology or weights changed; fixed original masks cannot be silently rebuilt'
        set_action(rig, bpy.data.actions['Run'])
        start, end = bpy.data.actions['Run'].frame_range
        fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
        duration = (end - start) / fps
        assert math.isclose(duration, .7, abs_tol=1e-6)
        if args.gltf:
            from labrador_sprint_gltf_skin import ExportSkin
            export_skin = ExportSkin(args.gltf, mesh, weights, names)
        intervals = round(duration * args.hz)
        regular_phases = {i / intervals for i in range(intervals + 1)}
        key_phases = {(key - start) / (end - start) for key in range(math.ceil(start), math.floor(end) + 1)}
        phases = sorted(regular_phases | key_phases | {.9})
        regular_samples = len(regular_phases)
        authored_keys_included = len(key_phases)
        for i, phase in enumerate(phases):
            world, matrices = sample(rig, mesh, 'Run', start + (end - start) * phase)
            rows.append(surface_row(world, triangles, masks, reference_areas, matrices, neutral_matrices, phase))
            if export_skin:
                export_world, export_matrices, duplicate_error = export_skin.sample('Run', duration * phase)
                gltf_rows.append(surface_row(export_world, triangles, masks, reference_areas,
                                             export_matrices, neutral_matrices, phase))
                gltf_comparison.append({'phase': phase,
                                        'authored_key': abs(phase * (end - start) - round(phase * (end - start))) < 1e-6,
                                        'max_skin_error_vs_blender_m': float(np.linalg.norm(export_world - world, axis=1).max()),
                                        'duplicate_skin_error_m': duplicate_error,
                                        'full_skin_floor_m': float(export_world[:, 2].min())})
            if i % 14 == 0 or i + 1 == len(phases):
                print('SURFACE_PROGRESS', i + 1, len(phases), flush=True)
    report = {'scope': 'Independent fixed-original-mask full-cycle selected skin-surface and proximal shape diagnostics; no automatic naturalness approval.',
              'baseline_blend_sha256': baseline_sha_loaded, 'candidate_blend_sha256': candidate_sha_loaded,
              'binding_signatures': signatures, 'candidate_binding_signatures': candidate_signatures,
              'masks': mask_receipt, 'neutral': neutral_row, 'old_rejected_phase090': old_row,
              'sampling': {'hz': args.hz, 'regular_samples': regular_samples, 'explicit_previous_failed_phase': .9,
                           'actual_geometry_samples': len(rows), 'authored_keys_included': authored_keys_included},
              'samples': rows,
              'limits': ['Nonadjacent pairs exclude any shared vertex; selected geometry regions do not establish all-mesh collision freedom.',
                         'Historical exact mask and combined BVH mask remain separate; their counts must not be added.',
                         'Segment-triangle crossings require two interior edge hits separated by>10micrometres; projected coplanar overlaps>1e-10m² are separately reported.',
                         'Fixed region area ratios measure selected surface compression, not volume or anatomy; rendered proximal shape must still be reviewed.',
                         'The source rest positions, topology, vertex group order and all weights are bound and must match. No threshold/mask shrinking is allowed.']}
    if rows:
        def maxima(values):
            def area_maxima(key):
                if not len(masks[key]):
                    return {'triangles': 0, 'status': 'Unmeasured: original weight selection is empty',
                            'minimum_area_ratio': None, 'max_triangles_under20pct_neutral_area': None,
                            'worst_phase': None, 'max_compressed_count_phase': None,
                            'max_compressed_total_neutral_area_m2': None, 'max_compressed_area_phase': None}
                return {'triangles': len(masks[key]),
                        'minimum_area_ratio': min(r['skin_area'][key]['area_ratio_min'] for r in values),
                        'max_triangles_under20pct_neutral_area': max(r['skin_area'][key]['triangles_under20pct_neutral_area'] for r in values),
                        'worst_phase': min(values, key=lambda r: r['skin_area'][key]['area_ratio_min'])['phase'],
                        'max_compressed_count_phase': max(values, key=lambda r: r['skin_area'][key]['triangles_under20pct_neutral_area'])['phase'],
                        'max_compressed_total_neutral_area_m2': max(r['skin_area'][key]['compressed_triangles_total_neutral_area_m2'] for r in values),
                        'max_compressed_area_phase': max(values, key=lambda r: r['skin_area'][key]['compressed_triangles_total_neutral_area_m2'])['phase']}
            def fore_maxima(side):
                regular = [r for r in values if abs(r['phase'] * intervals - round(r['phase'] * intervals)) < 1e-6]
                direction_steps = []
                elbow_speeds = []
                for before, after in zip(regular, regular[1:]):
                    delta = duration * (after['phase'] - before['phase'])
                    a = before['fore_pose'][side]
                    b = after['fore_pose'][side]
                    direction_steps.append((math.degrees(Vector(a['humerus_unit_direction']).angle(Vector(b['humerus_unit_direction']))), before['phase'], after['phase']))
                    elbow_speeds.append(((Vector(b['elbow_world_m']) - Vector(a['elbow_world_m'])).length / delta, before['phase'], after['phase']))
                angle, begin, finish = max(direction_steps)
                speed, speed_begin, speed_finish = max(elbow_speeds)
                return {'humerus_rotation_from_neutral_deg_range': [min(r['fore_pose'][side]['humerus_rotation_from_neutral_deg'] for r in values), max(r['fore_pose'][side]['humerus_rotation_from_neutral_deg'] for r in values)],
                        'elbow_above_shoulder_m_range': [min(r['fore_pose'][side]['elbow_above_shoulder_m'] for r in values), max(r['fore_pose'][side]['elbow_above_shoulder_m'] for r in values)],
                        'max_humerus_direction_step_deg': angle,
                        'humerus_direction_step_phase_interval': [begin, finish],
                        'max_elbow_speed_m_s': speed, 'elbow_speed_phase_interval': [speed_begin, speed_finish],
                        'sample_dt_s': duration / intervals}
            return {
            'intersections': {key: {'max_exact_crossing_pairs': max(r['intersections'][key]['exact_crossing_pairs'] for r in values),
                                    'max_coplanar_area_overlap_pairs': max(r['intersections'][key]['coplanar_area_overlap_pairs'] for r in values),
                                    'worst_phase': max(values, key=lambda r: r['intersections'][key]['exact_crossing_pairs'])['phase']}
                              for key in PAIRS},
            'skin_area': {key: area_maxima(key) for key in AREA_REGIONS},
            'fore_pose': {side: fore_maxima(side) for side in ['L', 'R']}}
        report['maxima'] = maxima(rows)
        if gltf_rows:
            report['actual_gltf_export_review'] = {
                'file_sha256': gltf_sha_loaded, 'mapping': export_skin.mapping_receipt,
                'actual_skin_samples': len(gltf_rows), 'maxima': maxima(gltf_rows),
                'maximum_skin_difference_at_keys_m': max(v['max_skin_error_vs_blender_m'] for v in gltf_comparison if v['authored_key']),
                'maximum_skin_difference_between_keys_m': max(v['max_skin_error_vs_blender_m'] for v in gltf_comparison if not v['authored_key']),
                'full_skin_floor_min_m': min(v['full_skin_floor_m'] for v in gltf_comparison),
                'comparison': gltf_comparison, 'samples': gltf_rows,
                'scope': f'Actual delivered glTF LINEAR/STEP skin with original fixed triangle IDs/masks, including {authored_keys_included} authored keys and {args.hz:g} Hz regular samples plus former phase .9. Not inferred from Blender BEZIER or FBX.'}
    assert digest(args.baseline) == baseline_sha_loaded, 'Baseline changed during read-only review'
    assert digest(args.blend) == candidate_sha_loaded, 'Candidate changed during read-only review; do not bind measurements to another file'
    if args.gltf:
        assert digest(args.gltf) == gltf_sha_loaded, 'glTF changed during actual export review'
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('SURFACE_REVIEW_COMPLETE', args.report, 'samples', len(rows), flush=True)


if __name__ == '__main__':
    main()
