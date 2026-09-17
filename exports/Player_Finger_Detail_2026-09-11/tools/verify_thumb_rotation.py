"""Independent read-only thumb axial-rotation verification against iteration_08.

This script imports validation helpers, never the deformation implementation.
It measures rotation from actual vertices and evaluated nail geometry.
"""
import argparse
import json
import math
import sys
import traceback
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = Path(__file__).resolve().parent
detail = legacy = generic = core = None
DIGITS = ('thumb', 'index', 'middle', 'ring', 'little')
FIELDS = ('faces', 'weights', 'materials', 'face_materials', 'uv_layers',
          'uv_active', 'uv_render', 'smooth_faces', 'flex', 'relative_keys')


def unit(value):
    result = np.asarray(value, dtype=float)
    return result / np.linalg.norm(result)


def rotate(values, axis, angles):
    """Rodrigues rotation for independent vector-valued witnesses."""
    values = np.asarray(values)
    angles = np.asarray(angles)
    if angles.ndim == 0:
        angles = np.full(len(values), float(angles))
    cosine, sine = np.cos(angles)[:, None], np.sin(angles)[:, None]
    return values * cosine + np.cross(axis, values) * sine + (values @ axis)[:, None] * axis * (1 - cosine)


def nail_normal(part):
    triangles = np.asarray([t for t in part['triangles'] if max(t) < 161])
    points = part['points'][triangles]
    normal = unit(np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0]).sum(axis=0))
    shell = (part['points'][:161] - part['points'][161:]).mean(axis=0)
    if normal @ shell < 0:
        normal = -normal
    return normal


def skin_section_center(snapshot, axis):
    """Actual old IP skin-plane intersections, independently of reported pivot."""
    hand = snapshot['parts']['hand']
    origin = np.asarray(snapshot['bone_points']['thumb2']['head'])
    cross = unit(np.cross(axis, (0., 0., 1.)))
    dorsal = unit(np.cross(cross, axis))
    ownership = np.asarray([sum(v for k, v in w.items() if k.startswith('thumb')) for w in hand['weights']])
    hits = []
    for face in hand['faces']:
        if max(face) >= 12036 or np.mean(ownership[list(face)]) <= .6:
            continue
        for ia, ib in zip(face, face[1:] + face[:1]):
            a, b = hand['points'][ia], hand['points'][ib]
            da, db = (a - origin) @ axis, (b - origin) @ axis
            if (da < 0) != (db < 0):
                hits.append(a + (b - a) * da / (da - db))
    assert len(hits) >= 8
    offsets = np.asarray(hits) - origin
    return origin + cross * (np.min(offsets @ cross) + np.max(offsets @ cross)) * .5 + dorsal * (np.min(offsets @ dorsal) + np.max(offsets @ dorsal)) * .5


def inspect_surface(old, new, angles, axis):
    faces = [f for f in old['triangles'] if max(f) < 12036]
    triangles = np.asarray(faces, dtype=np.int64)
    changed = np.linalg.norm(new['points'] - old['points'], axis=1) > 1e-8
    touched = np.any(changed[triangles], axis=1)
    p, q = old['points'][triangles], new['points'][triangles]
    before = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    after = np.cross(q[:, 1] - q[:, 0], q[:, 2] - q[:, 0])
    size0, size1 = np.linalg.norm(before, axis=1), np.linalg.norm(after, axis=1)
    assert np.isfinite(q).all() and np.all(size1[touched] > 1e-14), 'Collapsed or invalid physical triangle'
    expected = rotate(before[touched], axis, angles[triangles[touched]].mean(axis=1))
    alignment = np.sum(expected * after[touched], axis=1) / (size0[touched] * size1[touched])
    assert float(alignment.min()) > 0., 'Actual surface reversed relative to its locally rotated frame'
    tree = BVHTree.FromPolygons([Vector(v) for v in new['points']], faces, all_triangles=True)
    candidates = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree) if a != b and (touched[a] or touched[b])}
    inherited, tested, new_hits = 0, 0, []
    for a, b in sorted(candidates):
        if set(faces[a]) & set(faces[b]):
            continue
        if any(np.linalg.norm(x-y) < 1e-7 for x in p[a] for y in p[b]):
            continue
        tested += 1
        if detail.triangle_hit(q[a], q[b]):
            if detail.triangle_hit(p[a], p[b]):
                inherited += 1
            else:
                new_hits.append([a, b])
    assert not new_hits, 'New true physical skin intersections: ' + str(new_hits[:8])
    return {'touched_triangles': int(touched.sum()), 'minimum_rotated_normal_alignment': float(alignment.min()),
            'minimum_area_ratio': float((size1[touched]/size0[touched]).min()),
            'actual_triangle_pairs_tested': tested, 'inherited_intersections': inherited, 'new_intersections': new_hits}


def inspect_changes(old, new, side, degrees):
    assert old['rest'] == new['rest'], 'Sixteen approved bone rest transforms changed'
    assert old['objects'] == new['objects'], 'Object/parent transforms changed'
    assert old['parts'].keys() == new['parts'].keys()
    bone = old['bone_points']['thumb2']
    axis = unit(np.asarray(bone['tail']) - np.asarray(bone['head']))
    pivot = skin_section_center(old, axis)
    angle = math.radians(degrees * (1 if side == 'left' else -1))
    rows = {'axis_native': axis.tolist(), 'independent_actual_ip_center_native': pivot.tolist(), 'signed_target_roll_degrees': math.degrees(angle)}
    for label, a in old['parts'].items():
        b = new['parts'][label]
        for field in FIELDS:
            assert a[field] == b[field], 'Protected ' + field + ' changed: ' + label
        assert a['points'].shape == b['points'].shape and list(a['deltas']) == list(b['deltas'])
        if label not in ('hand', 'nail_thumb'):
            assert np.array_equal(a['points'], b['points']), 'Unrelated geometry changed: ' + label
            assert all(np.array_equal(a['deltas'][k], b['deltas'][k]) for k in a['deltas'])
            rows[label] = {'geometry_topology_uv_weights_keys_exact': True}
            continue
        if label == 'nail_thumb':
            assert len(a['points']) == 322 and not b['deltas']
            assert all(w == {'thumb2': 1.0} for w in b['weights'])
            expected = pivot + rotate(a['points'] - pivot, axis, angle)
            error = float(np.linalg.norm(expected - b['points'], axis=1).max())
            assert error < 2e-7, 'Thumbnail is not rigidly rotated around actual skin centerline: ' + str(error)
            paired = rotate(a['points'][:161] - a['points'][161:], axis, angle)
            shell_error = float(np.linalg.norm(paired - (b['points'][:161] - b['points'][161:]), axis=1).max())
            assert shell_error < 8e-8
            normal = nail_normal(b)
            others = unit(sum(nail_normal(new['parts']['nail_' + d]) for d in DIGITS[1:]))
            separation = math.degrees(math.acos(float(np.clip(normal @ others, -1., 1.))))
            radial = unit(np.cross(axis, (0., 0., 1.))) * (1 if side == 'left' else -1)
            assert 65. <= separation <= 85., 'Thumbnail face still lacks expected anatomical separation: ' + str(separation)
            assert float(normal @ radial) > .80, 'Thumbnail points toward inner finger side'
            rows[label] = {'rigid_rotation_error_m': error, 'paired_shell_error_m': shell_error,
                'measured_top_area_normal_native': normal.tolist(), 'four_finger_dorsal_native': others.tolist(),
                'separation_from_four_nails_degrees': separation, 'outward_radial_normal_dot': float(normal @ radial),
                'topology_uv_rigid_weights_exact': True}
            continue
        exposed = np.zeros(len(a['points']), dtype=bool)
        protected = exposed.copy()
        for face, mi in zip(a['faces'], a['face_materials']):
            role = a['materials'][mi].split('.')[0]
            (exposed if role == 'Detailed_Skin' else protected)[list(face)] = True
        ownership = np.asarray([sum(v for k, v in w.items() if k.startswith('thumb')) for w in a['weights']])
        eligible = exposed & ~protected & (ownership > .95)
        eligible[12036:] = False
        delta = b['points'] - a['points']
        changed = np.linalg.norm(delta, axis=1) > 1e-8
        assert changed.sum() >= 100 and not np.any(changed & ~eligible), 'Rotation moved glove/shared, unrelated digit or non-thumb skin'
        assert np.array_equal(a['points'][~eligible], b['points'][~eligible]), 'Protected positions changed'
        p, q = a['points'] - pivot, b['points'] - pivot
        axial_error = float(np.abs((q-p) @ axis).max())
        pr, qr = p - (p @ axis)[:, None]*axis, q - (q @ axis)[:, None]*axis
        radial_error = float(np.abs(np.linalg.norm(pr, axis=1)-np.linalg.norm(qr, axis=1)).max())
        assert axial_error < 2e-7 and radial_error < 2e-7, 'Thumb roll altered length or radial distance'
        angles = np.arctan2(np.cross(pr, qr) @ axis, np.sum(pr*qr, axis=1))
        angles[~changed] = 0.
        signed = angles * (1 if side == 'left' else -1)
        assert float(signed.min()) > -1e-5 and float(signed.max()) < abs(angle)+1e-5, 'Reversed or excessive local roll'
        assert np.count_nonzero(np.abs(angles-angle) < 1e-5) > 80, 'No coherent fully rotated distal thumb region'
        boundary = np.flatnonzero(protected & (ownership > .5) & (np.arange(len(ownership)) < 12036))
        transition_start = float(((a['points'][boundary]-pivot) @ axis).max()) + .0008
        transition_end = -.002
        assert transition_end - transition_start > .010
        phase = np.clip(((a['points']-pivot) @ axis-transition_start)/(transition_end-transition_start), 0., 1.)
        expected_angles = angle * phase*phase*(3.-2.*phase)
        expected_angles[~eligible] = 0.
        # Rotated distal geometry must remain continuous across split skin seams.
        from mathutils.kdtree import KDTree
        seam_tree = KDTree(12036)
        for i, p0 in enumerate(a['points'][:12036]):
            seam_tree.insert(Vector(p0), i)
        seam_tree.balance()
        seen = set()
        for i in range(12036):
            if i in seen:
                continue
            group = {j for unused, j, unused_distance in seam_tree.find_range(Vector(a['points'][i]), 1e-6)}
            frontier = list(group)
            while frontier:
                j = frontier.pop()
                for unused, k, unused_distance in seam_tree.find_range(Vector(a['points'][j]), 1e-6):
                    if k not in group:
                        group.add(k)
                        frontier.append(k)
            seen.update(group)
            minimum_angle = min((expected_angles[j] for j in group), key=abs)
            expected_angles[list(group)] = minimum_angle
        gate_error = float(np.abs(angles-expected_angles).max())
        assert gate_error < 1e-5, 'Measured roll differs from independent glove-to-IP transition: ' + str(gate_error)
        seam_maximum, seam_pairs = 0., 0
        for i in np.flatnonzero(changed[:12036]):
            for unused, j, distance in seam_tree.find_range(Vector(a['points'][i]), 1e-6):
                if j <= i:
                    continue
                seam_pairs += 1
                enlargement = float(np.linalg.norm(b['points'][i]-b['points'][j])) - distance
                seam_maximum = max(seam_maximum, enlargement)
        assert seam_maximum < 2e-7, 'Thumb roll opened a preexisting split seam'
        corrections = {}
        for key, old_delta in a['deltas'].items():
            actual = b['deltas'][key]
            expected = rotate(old_delta, axis, angles)
            error = float(np.linalg.norm(actual-expected, axis=1).max())
            magnitude_error = float(np.abs(np.linalg.norm(actual, axis=1)-np.linalg.norm(old_delta, axis=1)).max())
            assert error < 8e-8 and magnitude_error < 8e-8, 'Corrective was translated or distorted instead of rotated: ' + key
            assert np.array_equal(actual[~changed], old_delta[~changed]), 'Unaffected corrective vector changed: ' + key
            corrections[key] = {'rotated_vector_error_m': error, 'magnitude_error_m': magnitude_error, 'untouched_exact': True}
        rows[label] = {'changed_vertices': int(changed.sum()), 'only_exposed_thumb_changed': True,
            'maximum_displacement_m': float(np.linalg.norm(delta, axis=1).max()), 'axial_error_m': axial_error,
            'radial_error_m': radial_error, 'maximum_roll_degrees': math.degrees(float(signed.max())),
            'independent_transition_start_m': transition_start, 'independent_transition_end_m': transition_end,
            'maximum_transition_angle_error_radians': gate_error,
            'split_seam_pairs': seam_pairs, 'maximum_split_seam_enlargement_m': seam_maximum,
            'correctives': corrections, 'surface': inspect_surface(a, b, angles, axis)}
    return rows


def nail_measurements(scene, rig):
    """All actual nail top face witnesses, with direction from geometric top area."""
    parts = legacy.parts_for(scene, rig)
    hand = parts['hand']
    groups = {g.index: g.name for g in hand.vertex_groups}
    targets, top_faces = {}, {}
    for digit in DIGITS:
        owned = {v.index for v in hand.data.vertices if sum(g.weight for g in v.groups if groups[g.group] == digit+'2') > .25}
        targets[digit] = [tuple(p.vertices) for p in hand.data.polygons if all(i in owned for i in p.vertices)
            and legacy.role(hand.data.materials[p.material_index]) in ('Detailed_Skin', 'Detailed_Glove')]
        nail = parts['nail_'+digit]
        nail.data.calc_loop_triangles()
        top_faces[digit] = [tuple(t.vertices) for t in nail.data.loop_triangles if max(t.vertices) < 161]
        assert targets[digit] and len(top_faces[digit]) >= 8
    saved = {b.name: b.matrix_basis.copy() for b in rig.pose.bones}
    saved_keys = {k.name: k.value for k in hand.data.shape_keys.key_blocks[1:]}
    cases = {'neutral': [], 'all_full_flex': [(d, j) for d in DIGITS for j in range(3)], 'thumb_middle_full': [('thumb', 1)]}
    cases.update({d+'_tip_full': [(d, 2)] for d in DIGITS})
    result = {}
    try:
        for label, selected in cases.items():
            for b in rig.pose.bones:
                b.matrix_basis = saved[b.name]
            for key in hand.data.shape_keys.key_blocks[1:]:
                key.value = 0.
            for digit, joint in selected:
                degrees = ((60, 70, 80) if digit == 'thumb' else (90, 110, 80))[joint]
                bone = rig.pose.bones[digit+str(joint)]
                bone.matrix_basis = saved[bone.name] @ Matrix.Rotation(-math.radians(degrees), 4, 'X')
                hand.data.shape_keys.key_blocks[f'Joint_{digit}_{joint}'].value = 1.
            bpy.context.view_layer.update()
            skin = core.evaluated_points(hand)
            result[label] = {}
            for digit in DIGITS:
                tree = BVHTree.FromPolygons(skin, targets[digit])
                nail = core.evaluated_points(parts['nail_'+digit])
                normal = sum(((nail[b]-nail[a]).cross(nail[c]-nail[a]) for a, b, c in top_faces[digit]), Vector()).normalized()
                shell = sum((nail[i]-nail[i+161] for i in range(161)), Vector())
                if normal.dot(shell) < 0:
                    normal = -normal
                distances = [tree.find_nearest(p)[3] for p in nail]
                signed, rays = [], []
                for a, b, c in top_faces[digit]:
                    a, b, c = nail[a], nail[b], nail[c]
                    for point in ((a+b+c)/3, a*.6+b*.2+c*.2, a*.2+b*.6+c*.2, a*.2+b*.2+c*.6):
                        hit, surface_normal, unused, distance = tree.find_nearest(point)
                        distances.append(distance)
                        signed.append((point-hit).dot(surface_normal))
                        ray = tree.ray_cast(point+normal*.002, -normal, .004)
                        rays.append((point-ray[0]).dot(normal) if ray[0] is not None else float('nan'))
                result[label][digit] = {'distances': np.asarray(distances), 'signed_top': np.asarray(signed),
                    'ray_top': np.asarray(rays), 'geometric_top_normal_world': list(normal)}
    finally:
        for b in rig.pose.bones:
            b.matrix_basis = saved[b.name]
        for key in hand.data.shape_keys.key_blocks[1:]:
            key.value = saved_keys[key.name]
        bpy.context.view_layer.update()
    return result


def compare_nails(current, original):
    """Compare the same geometric-normal metric on both immutable08 and current.

    The older 80um neutral threshold was defined along projected global +Z.
    A normal derived from the actual sloping nail plate has different projected
    clearance even before deformation (source08 thumb: 68.72um). Require positive
    neutral clearance and source-relative preservation with the original 20um
    intrusion tolerance; keep the absolute 0.8mm distance envelope unchanged.
    """
    result = {}
    for pose, digits in current.items():
        result[pose] = {}
        for digit, new in digits.items():
            old = original[pose][digit]
            assert new['distances'].shape == old['distances'].shape
            assert new['signed_top'].shape == old['signed_top'].shape
            assert np.isfinite(new['ray_top']).all(), f'Actual geometric nail ray misses skin: {pose}/{digit}'
            assert np.isfinite(old['ray_top']).all(), f'Baseline geometric nail ray misses skin: {pose}/{digit}'
            maximum = float(new['distances'].max())
            ray_loss = float((old['ray_top']-new['ray_top']).max())
            intrusion = float((old['signed_top']-new['signed_top']).max())
            required = max(0., min(.00008, float(old['ray_top'].min())-.00002)) if pose == 'neutral' else -.00002
            row = {'witnesses': len(new['distances']), 'source_maximum_gap_m': float(old['distances'].max()),
                'maximum_gap_m': maximum, 'maximum_added_gap_m': float((new['distances']-old['distances']).max()),
                'maximum_added_top_intrusion_m': intrusion,
                'source_minimum_signed_top_m': float(old['signed_top'].min()), 'minimum_signed_top_m': float(new['signed_top'].min()),
                'source_minimum_geometric_ray_clearance_m': float(old['ray_top'].min()),
                'minimum_geometric_ray_clearance_m': float(new['ray_top'].min()),
                'maximum_corresponding_geometric_ray_clearance_loss_m': ray_loss,
                'required_geometric_ray_clearance_m': required, 'all_geometric_rays_hit': True}
            result[pose][digit] = row
            assert maximum < .0008, f'Actual nail gap exceeds unchanged 0.8mm envelope: {pose}/{digit}: ' + json.dumps(row)
            assert float(new['ray_top'].min()) >= required, f'Actual geometric nail ray crosses skin: {pose}/{digit}: ' + json.dumps(row)
            if pose == 'neutral':
                assert float(new['ray_top'].min()) > 0., f'Neutral top surface lacks positive clearance: {digit}'
            assert ray_loss < .00002, f'Actual geometric ray clearance deteriorated beyond20um: {pose}/{digit}: ' + json.dumps(row)
            assert intrusion < .00002, f'Actual nail surface intrusion deteriorated beyond20um: {pose}/{digit}: ' + json.dumps(row)
            assert float(new['signed_top'].min()) >= -.00002, f'Actual top surface penetrates beyond20um: {pose}/{digit}: ' + json.dumps(row)
    return result


def main():
    global detail, legacy, generic, core
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--degrees', type=float, default=60.)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert bpy.app.background and 45. <= args.degrees <= 85.
    import importlib.util
    spec = importlib.util.spec_from_file_location('thumb_rotation_detail_helpers', HERE/'verify_finger_detail.py')
    detail = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(detail)
    support = HERE.parents[1]/'player_hands_realism_20260911/tools'
    generic_path = HERE.parents[1]/'player_hands_proportions_20260911/tools/verify_proportions.py'
    legacy = detail.module(support/'verify_hands_realistic.py', 'thumb_rotation_legacy')
    generic = detail.module(generic_path, 'thumb_rotation_generic')
    core = legacy.core
    generic.legacy, generic.core = legacy, core
    detail.legacy, detail.generic, detail.core = legacy, generic, core
    source, output = args.source_dir.resolve(), args.output_dir.resolve()
    source_blend, target_blend = [p/'bilateral_hands_finger_detail.blend' for p in (source, output)]
    glbs = {s: output/f'{s}_hand_finger_detail.glb' for s in ('left', 'right')}
    inputs = [source_blend, target_blend, output/'thumb_rotation_report.json', Path(__file__), HERE/'verify_finger_detail.py', generic_path,
        support/'verify_hands_realistic.py', support/'joint_verification_core.py', *glbs.values()]
    inputs += [source/f'{s}_hand_finger_detail.glb' for s in glbs]
    inputs += [p/f'realistic_hands_{semantic}.png' for p in (source, output) for semantic in ('basecolor', 'normal', 'roughness')]
    hashes = {str(p): detail.sha(p) for p in inputs}
    report = {'status': 'running', 'source_iteration': str(source), 'verified_sha256': hashes, 'checks': {}, 'errors': [],
        'limitations': ['This validates an authored thumb rest-mesh roll; unchanged joint rest axes do not constitute a new anatomical opposition rig.',
            'Nail seating uses all vertices and four interior points of every top triangle in eight evaluated poses per hand. It does not analytically prove every continuous point or whole-fist collision.',
            'Direct visual comparison and actual game rendering are separate acceptance work.']}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source_blend))
        scene, rigs = detail.activate()
        original = {s: detail.capture(scene, r) for s, r in rigs.items()}
        original_materials = generic.material_payload(scene)
        old_nails = {s: nail_measurements(scene, r) for s, r in rigs.items()}
        for side in glbs:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(source/f'{side}_hand_finger_detail.glb'), bone_heuristic='TEMPERANCE')
            rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
            legacy.attach_prior_export_weights(original[side], legacy.snapshot(bpy.context.scene, rig))
        bpy.ops.wm.open_mainfile(filepath=str(target_blend))
        scene, rigs = detail.activate()
        current = {s: detail.capture(scene, r) for s, r in rigs.items()}
        assert generic.material_payload(scene) == original_materials, 'Existing shader graph or packed image payload changed'
        report['checks']['materials_exact_iteration08'] = True
        for semantic in ('basecolor', 'normal', 'roughness'):
            name = f'realistic_hands_{semantic}.png'
            assert detail.sha(source/name) == detail.sha(output/name), 'Atlas differs from pre-roll iteration08: ' + semantic
        atlases, evidence = detail.packed_atlases(scene, output)
        report['checks']['packed_png_equivalence'] = evidence
        for side, rig in rigs.items():
            row = report['checks']['editable_'+side] = {}
            row['thumb_rotation'] = inspect_changes(original[side], current[side], side, args.degrees)
            row['actual_articulation'] = generic.inspect_pose(scene, rig)
            measurements = nail_measurements(scene, rig)
            row['actual_nail_seating'] = compare_nails(measurements, old_nails[side])
            row['nail_ray_direction'] = 'Area-weighted geometric top normal of the actual posed nail; no global +Z assumption.'
            row['nail_clearance_metric'] = 'Source-relative actual geometric ray clearance with20um maximum loss, positive neutral surface and unchanged0.8mm absolute gap. The former80um projected+Z threshold is not interchangeable with geometric-normal distance; immutable08 itself measures68.72um on the new thumb metric.'
            for pose, digits in measurements.items():
                for digit, value in digits.items():
                    row['actual_nail_seating'][pose][digit]['geometric_top_normal_world'] = value['geometric_top_normal_world']
            for label, part in current[side]['parts'].items():
                part['prior_export_weights'] = original[side]['parts'][label]['prior_export_weights']
        for side, path in glbs.items():
            row = report['checks'][side+'_glb'] = {'container': legacy.inspect_glb_container(path),
                'actual_embedded_pixels': detail.embedded_pixels(path, source/f'{side}_hand_finger_detail.glb', atlases)}
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic='TEMPERANCE')
            rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
            actual = detail.capture(bpy.context.scene, rig)
            row['roundtrip'] = generic.roundtrip(actual, current[side])
            row['actual_articulation'] = generic.inspect_pose(bpy.context.scene, rig)
    except Exception as error:
        report['errors'].append({'error': str(error), 'traceback': traceback.format_exc()})
    assert all(detail.sha(path) == value for path, value in hashes.items()), 'A read-only input changed during verification'
    report['status'] = 'failed' if report['errors'] else 'passed'
    (output/'thumb_rotation_verification.json').write_text(json.dumps(report, indent=2)+'\n')
    print('THUMB_ROTATION_VERIFICATION', report['status'], json.dumps(report['errors']), flush=True)
    if report['errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
