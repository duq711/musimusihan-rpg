"""Independent read-only verification of the photograph-reference finger pass.

Consumes frozen verification helpers only, never the geometry or bake builder.
This pass may reshape the nail plates and exposed finger skin. It must retain
the user-corrected thumb orientation, approved rig, UVs and unrelated geometry.
"""
import argparse
import json
import math
import sys
import traceback
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

HERE = Path(__file__).resolve().parent
STAGING = HERE.parents[1]
DIGITS = ('thumb', 'index', 'middle', 'ring', 'little')
KEYS = [f'Joint_{d}_{j}' for d in DIGITS for j in range(3)]
FIELDS = ('faces', 'weights', 'materials', 'face_materials', 'uv_layers',
          'uv_active', 'uv_render', 'smooth_faces', 'flex', 'relative_keys')
detail = rotation = legacy = generic = core = None


def load_helpers():
    global detail, rotation, legacy, generic, core
    import importlib.util
    path = STAGING / 'player_fingers_detail_20260911/tools/verify_finger_detail.py'
    spec = importlib.util.spec_from_file_location('photoref_detail_helpers', path)
    detail = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(detail)
    rotation = detail.module(path.with_name('verify_thumb_rotation.py'), 'photoref_rotation_helpers')
    legacy = detail.module(STAGING / 'player_hands_realism_20260911/tools/verify_hands_realistic.py', 'photoref_legacy')
    generic = detail.module(STAGING / 'player_hands_proportions_20260911/tools/verify_proportions.py', 'photoref_generic')
    core = legacy.core
    generic.legacy, generic.core = legacy, core
    detail.legacy, detail.generic, detail.core = legacy, generic, core
    rotation.detail, rotation.legacy, rotation.generic, rotation.core = detail, legacy, generic, core


def unit(values):
    values = np.asarray(values, dtype=float)
    length = np.linalg.norm(values)
    assert length > 1e-12
    return values / length


def inspect_split_seams(old, new, changed):
    tree = KDTree(12036)
    for i, p in enumerate(old['points'][:12036]):
        tree.insert(Vector(p), i)
    tree.balance()
    maximum, pairs = 0., 0
    for i in np.flatnonzero(changed[:12036]):
        for unused, j, before in tree.find_range(Vector(old['points'][i]), 1e-6):
            if j <= i:
                continue
            pairs += 1
            maximum = max(maximum, float(np.linalg.norm(new['points'][i] - new['points'][j])) - before)
    assert maximum < 2e-7, 'Detail opened a duplicated source skin seam: ' + str(maximum)
    return {'actual_source_seam_pairs': pairs, 'maximum_enlargement_m': maximum}


def inspect_nail_mesh(old, new, old_snapshot, digit):
    assert len(new['points']) == 322 and not new['deltas']
    assert all(w == {digit + '2': 1.0} for w in new['weights']), 'A nail is no longer rigidly bound to its distal phalanx'
    old_normal, normal = rotation.nail_normal(old), rotation.nail_normal(new)
    alignment = float(old_normal @ normal)
    assert alignment > .90, 'Rebuilt nail plate faces away from the approved orientation: ' + digit
    bone = old_snapshot['bone_points'][digit + '2']
    axis = unit(np.asarray(bone['tail']) - bone['head'])
    dorsal = unit(old_normal - axis * (old_normal @ axis))
    cross = unit(np.cross(axis, dorsal))
    delta = new['points'] - old['points']
    tangential = np.column_stack((delta @ axis, delta @ cross))
    maximum_footprint = float(np.linalg.norm(tangential, axis=1).max())
    assert maximum_footprint <= .002 + 3e-8, 'Nail footprint exceeds local 2 mm redesign envelope: ' + digit
    normal_offset = float(np.abs(delta @ dorsal).max())
    assert normal_offset <= .003 + 3e-8, 'Nail profile moved more than 3 mm from the approved plate: ' + digit
    shell = new['points'][:161] - new['points'][161:]
    thickness = np.linalg.norm(shell, axis=1)
    projected = shell @ normal
    assert .000025 <= float(thickness.min()) and float(thickness.max()) <= .0008
    assert float(projected.min()) > 0., 'Paired nail bottom lies above the exposed nail plate'
    triangles = np.asarray(new['triangles'], dtype=np.int64)
    p = new['points'][triangles]
    crosses = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    areas = np.linalg.norm(crosses, axis=1)
    assert np.isfinite(p).all() and float(areas.min()) > 1e-14, 'Nail contains collapsed or invalid triangle'
    top = np.max(triangles, axis=1) < 161
    top_alignment = (crosses[top] @ normal) / areas[top]
    # All authored top faces have an outward winding. Match the historical
    # triangulation sign, independently of handedness.
    old_tri = old['points'][np.asarray(old['triangles'])[top]]
    old_cross = np.cross(old_tri[:, 1] - old_tri[:, 0], old_tri[:, 2] - old_tri[:, 0])
    winding_sign = 1. if float(np.sum(old_cross @ old_normal)) > 0 else -1.
    top_alignment *= winding_sign
    assert float(top_alignment.min()) > .05, 'Nail plate folds underneath its outward surface: ' + digit
    faces = [tuple(t) for t in triangles]
    tree = BVHTree.FromPolygons([Vector(v) for v in new['points']], faces, all_triangles=True)
    intersections, tested = [], 0
    for a, b in sorted({(min(a, b), max(a, b)) for a, b in tree.overlap(tree) if a != b}):
        if set(faces[a]) & set(faces[b]):
            continue
        tested += 1
        if detail.triangle_hit(p[a], p[b]):
            intersections.append([a, b])
    assert not intersections, 'Nail shell self-intersects: ' + digit + '/' + str(intersections[:6])
    return {'vertices': 322, 'top_vertices': 161, 'top_triangles': int(top.sum()),
            'unchanged_topology_uv_rigid_weights': True, 'normal_alignment_to_source': alignment,
            'area_weighted_normal_native': normal.tolist(), 'maximum_footprint_shift_m': maximum_footprint,
            'maximum_dorsal_profile_shift_m': normal_offset,
            'shell_thickness_min_m': float(thickness.min()), 'shell_thickness_max_m': float(thickness.max()),
            'minimum_top_normal_alignment': float(top_alignment.min()),
            'actual_nonadjacent_triangle_pairs_tested': tested, 'shell_self_intersections': intersections}


def inspect_changes(old, new, side):
    assert old['rest'] == new['rest'], 'Approved sixteen bone rest transforms changed'
    assert old['objects'] == new['objects'], 'Existing object or parent transform changed'
    assert old['parts'].keys() == new['parts'].keys()
    rows = {}
    for label, a in old['parts'].items():
        b = new['parts'][label]
        for field in FIELDS:
            assert a[field] == b[field], 'Protected ' + field + ' changed: ' + label
        assert a['points'].shape == b['points'].shape and list(a['deltas']) == list(b['deltas'])
        if label.startswith('nail_'):
            rows[label] = inspect_nail_mesh(a, b, old, label.removeprefix('nail_'))
            continue
        if label != 'hand':
            assert np.array_equal(a['points'], b['points']), 'Unrelated geometry changed: ' + label
            assert all(np.array_equal(a['deltas'][k], b['deltas'][k]) for k in a['deltas'])
            rows[label] = {'positions_topology_uv_weights_keys_exact': True}
            continue
        assert len(a['points']) == 14988 and list(b['deltas']) == KEYS
        exposed = np.zeros(len(a['points']), dtype=bool)
        protected = exposed.copy()
        for face, mi in zip(a['faces'], a['face_materials']):
            (exposed if a['materials'][mi].split('.')[0] == 'Detailed_Skin' else protected)[list(face)] = True
        influence = np.asarray([[sum(w for k, w in weights.items() if k.startswith(d)) for d in DIGITS] for weights in a['weights']])
        eligible = exposed & ~protected & (np.max(influence, axis=1) > .8) & (a['points'][:, 1] > .010)
        eligible[12036:] = False
        delta = b['points'] - a['points']
        distance = np.linalg.norm(delta, axis=1)
        changed = distance > 0
        assert not np.any(changed & ~eligible), 'Moved glove, shared boundary, wrist, palm or unowned finger geometry'
        assert np.array_equal(a['points'][~eligible], b['points'][~eligible])
        # The approved thumb plate has a local dent of approximately 1.68 mm.
        # Rebuilding that cap also requires reshaping its immediately underlying
        # skin; restrict the enlarged envelope to its actual source nail bed.
        thumb = old['parts']['nail_thumb']
        thumbtree = BVHTree.FromPolygons([Vector(p) for p in thumb['points']], thumb['faces'])
        thumb_distance = np.asarray([thumbtree.find_nearest(Vector(p))[3] for p in a['points']])
        thumb_bed = eligible & (influence[:, 0] > .95) & (thumb_distance <= .004)
        limits = np.where(thumb_bed, .0018, .001)
        assert np.all(distance <= limits + 3e-8), 'Skin exceeds 1 mm, or 1.8 mm at the localized thumb nail bed'
        measurable = distance >= 1e-6
        owners = np.argmax(influence, axis=1)
        counts = {d: int(np.count_nonzero(measurable & (owners == i))) for i, d in enumerate(DIGITS)}
        assert all(n >= 5 for n in counts.values()), 'All five digits require measurable physical detail'
        correctives = {}
        for name, before in a['deltas'].items():
            actual = b['deltas'][name]
            maximum = float(np.linalg.norm(before - actual, axis=1).max())
            assert maximum < 4e-8, 'An existing joint corrective vector changed: ' + name
            assert np.array_equal(before[~changed], actual[~changed])
            correctives[name] = {'maximum_vector_preservation_error_m': maximum, 'untouched_exact': True}
        rows[label] = {'only_exposed_owned_finger_skin_moved': True, 'changed_vertices': int(changed.sum()),
            'changed_by_digit': counts, 'maximum_displacement_m': float(distance.max()),
            'localized_thumb_bed_eligible_vertices': int(thumb_bed.sum()),
            'maximum_thumb_bed_displacement_m': float(distance[thumb_bed].max()) if np.any(thumb_bed) else 0.,
            'maximum_other_exposed_skin_displacement_m': float(distance[~thumb_bed].max()),
            'corrective_vectors': correctives, 'split_seams': inspect_split_seams(a, b, changed),
            'physical_surface': detail.inspect_surface(a, b, changed)}
    normal = rotation.nail_normal(new['parts']['nail_thumb'])
    others = unit(sum(rotation.nail_normal(new['parts']['nail_' + d]) for d in DIGITS[1:]))
    separation = math.degrees(math.acos(float(np.clip(normal @ others, -1., 1.))))
    axis = unit(np.asarray(old['bone_points']['thumb2']['tail']) - old['bone_points']['thumb2']['head'])
    radial = unit(np.cross(axis, (0., 0., 1.))) * (1 if side == 'left' else -1)
    assert 65. <= separation <= 85., 'User-corrected thumb nail separation was lost: ' + str(separation)
    assert float(normal @ radial) > .80, 'Thumb nail faces inward toward the fingers'
    rows['thumb_orientation'] = {'separation_from_four_finger_nails_degrees': separation,
            'outward_radial_normal_dot': float(normal @ radial), 'preserved_user_correction': True}
    return rows


def inspect_seating(measurements, original):
    result = {}
    for pose, digits in measurements.items():
        result[pose] = {}
        for digit, row in digits.items():
            assert np.isfinite(row['distances']).all() and np.isfinite(row['signed_top']).all()
            misses = int(np.count_nonzero(~np.isfinite(row['ray_top'])))
            maximum = float(row['distances'].max())
            signed = float(row['signed_top'].min())
            ray = float(np.nanmin(row['ray_top']))
            evidence = {'actual_surface_witnesses': len(row['distances']), 'top_interior_witnesses': len(row['signed_top']),
                'maximum_gap_m': maximum, 'minimum_signed_top_m': signed,
                'minimum_geometric_ray_clearance_m': ray, 'geometric_ray_misses': misses,
                'geometric_top_normal_world': row['geometric_top_normal_world'],
                'source_maximum_gap_m': float(original[pose][digit]['distances'].max()),
                'source_minimum_signed_top_m': float(original[pose][digit]['signed_top'].min())}
            result[pose][digit] = evidence
            message = pose + '/' + digit + ': ' + json.dumps(evidence)
            assert misses == 0, 'Actual nail top ray misses distal skin bed: ' + message
            assert maximum < .0008, 'Actual nail gap exceeds 0.8 mm: ' + message
            assert signed >= -.00002, 'Nail top penetrates more than 20 micrometres: ' + message
            assert ray >= (0. if pose == 'neutral' else -.00002), 'Nail top ray crosses actual skin: ' + message
            if pose == 'neutral':
                assert ray > 0., 'Neutral nail top lacks positive surface clearance: ' + message
    return result


def main():
    load_helpers()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--blend-name', default='bilateral_hands_finger_detail.blend')
    parser.add_argument('--geometry-only', action='store_true', help='Geometry candidate before the new texture bake; texture refinement not accepted by this mode.')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    assert bpy.app.background
    source, output = args.source_dir.resolve(), args.output_dir.resolve()
    source_blend, target_blend = source / 'bilateral_hands_finger_detail.blend', output / args.blend_name
    glbs = {s: output / f'{s}_hand_finger_detail.glb' for s in ('left', 'right')}
    inputs = [source_blend, target_blend, Path(__file__), Path(detail.__file__), Path(rotation.__file__),
        Path(generic.__file__), Path(legacy.__file__), Path(core.__file__), *glbs.values()]
    inputs += [source / f'{s}_hand_finger_detail.glb' for s in glbs]
    inputs += [p / f'realistic_hands_{semantic}.png' for p in (source, output) for semantic in ('basecolor', 'normal', 'roughness')]
    hashes = {str(p): detail.sha(p) for p in inputs}
    report = {'status': 'running', 'scope': 'geometry_only' if args.geometry_only else 'full_geometry_and_textures',
        'source_iteration': str(source), 'verified_sha256': hashes, 'checks': {}, 'errors': [], 'limitations': [
            'Reference similarity and microtexture quality require direct visual inspection of separate finger views; structural checks do not prove photorealism.',
            'Nail seating uses every vertex and four interior witnesses per top triangle in eight evaluated poses per hand; it does not prove every continuous surface point or whole-fist collision.',
            'Neutral skin intersections distinguish newly introduced intersections from inherited source intersections.',
            'The inherited sixteen-bone rig is retained, including its existing thumb articulation axes. This is a surface refinement, not an anatomical rig redesign.']}
    try:
        bpy.ops.wm.open_mainfile(filepath=str(source_blend))
        scene, rigs = detail.activate()
        original = {s: detail.capture(scene, r) for s, r in rigs.items()}
        original_textures = detail.texture_surface_samples(scene)
        old_nails = {s: rotation.nail_measurements(scene, r) for s, r in rigs.items()}
        for side in glbs:
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(source / f'{side}_hand_finger_detail.glb'), bone_heuristic='TEMPERANCE')
            rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
            legacy.attach_prior_export_weights(original[side], legacy.snapshot(bpy.context.scene, rig))
        bpy.ops.wm.open_mainfile(filepath=str(target_blend))
        scene, rigs = detail.activate()
        current = {s: detail.capture(scene, r) for s, r in rigs.items()}
        report['checks']['materials'] = legacy.inspect_materials(scene.objects)
        changes = detail.compare_texture_surfaces(detail.texture_surface_samples(scene), original_textures)
        report['checks']['actual_uv_texture_changes'] = changes
        atlases, evidence = detail.packed_atlases(scene, output)
        report['checks']['packed_png_equivalence'] = evidence
        if not args.geometry_only:
            for role in ('Detailed_Skin', 'Detailed_Nail'):
                for semantic in ('normal', 'roughness'):
                    assert changes[semantic][role]['changed_samples'] >= 10, 'New detail map is not bound at actual surface UVs: ' + role + '/' + semantic
        for side, rig in rigs.items():
            row = report['checks']['editable_' + side] = {}
            row['source_preservation_and_surface'] = inspect_changes(original[side], current[side], side)
            row['actual_articulation'] = generic.inspect_pose(scene, rig)
            row['actual_nail_seating'] = inspect_seating(rotation.nail_measurements(scene, rig), old_nails[side])
            for label, part in current[side]['parts'].items():
                part['prior_export_weights'] = original[side]['parts'][label]['prior_export_weights']
        for side, path in glbs.items():
            row = report['checks'][side + '_glb'] = {'container': legacy.inspect_glb_container(path),
                'actual_embedded_pixels': detail.embedded_pixels(path, source / f'{side}_hand_finger_detail.glb', atlases)}
            bpy.ops.wm.read_factory_settings(use_empty=True)
            bpy.ops.import_scene.gltf(filepath=str(path), bone_heuristic='TEMPERANCE')
            rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
            actual = detail.capture(bpy.context.scene, rig)
            row['roundtrip'] = generic.roundtrip(actual, current[side])
            row['actual_articulation'] = generic.inspect_pose(bpy.context.scene, rig)
    except Exception as error:
        report['errors'].append({'error': str(error), 'traceback': traceback.format_exc()})
    assert all(detail.sha(path) == value for path, value in hashes.items()), 'A read-only verification input changed during the run'
    report['status'] = 'failed' if report['errors'] else 'passed'
    (output / 'verification_report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('PHOTOREF_FINGER_VERIFICATION', report['status'], json.dumps(report['errors']), flush=True)
    if report['errors']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
