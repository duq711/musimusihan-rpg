"""Record hash-checked final validation after the root's direct visual review."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-iteration', required=True)
    parser.add_argument('--preview-iteration', required=True)
    parser.add_argument('--test-log', required=True)
    parser.add_argument('--independent-report', required=True)
    parser.add_argument('--visually-reviewed', action='store_true')
    args = parser.parse_args()
    assert args.visually_reviewed, 'Actual images must first be inspected by the root.'
    stage = Path(__file__).resolve().parents[1]
    project = stage.parents[1]
    model = stage / 'mac_output' / args.model_iteration
    report = json.loads((model / args.independent_report).read_text())
    assert report['status'] == 'passed'
    padding = json.loads((model / 'atlas_padding_report.json').read_text())
    preservation = json.loads((model / 'padded_model_preservation_report.json').read_text())
    assert preservation['status'] == 'passed'
    assert digest(model / 'bilateral_hands_realistic.blend') == preservation['output_blend_sha256']
    for side in ('left', 'right'):
        sha = digest(model / f'{side}_hand_realistic.glb')
        assert sha == padding['glb'][side]['output_sha256']
        assert sha == digest(project / f'godot-game/assets/3d/player/hands_detailed/{side}_hand_detailed.glb')
    for channel, data in padding['textures'].items():
        assert data['authored_pixels_exact'] and data['changed_authored_pixels'] == 0
        assert digest(model / f'realistic_hands_{channel}.png') == data['output_sha256']
    test_log = (stage / args.test_log).read_text()
    assert 'Headless validation: 7 passed, 0 failed.' in test_log
    assert 'SCRIPT ERROR:' not in test_log and 'ERROR:' not in test_log
    preserved = json.loads((stage / 'baseline/preserved_artifacts.json').read_text())
    assert all(digest(project / name) == sha for name, sha in preserved.items())
    previews, wrists = {}, []
    for kind, count in [('player_finger_joints', 12), ('player_hands_detailed', 6)]:
        folder = project / 'godot-game/artifacts/visual_qa' / kind / args.preview_iteration
        manifest = json.loads((folder / 'capture_manifest.json').read_text())
        assert not manifest['failures'] and len(manifest['captures']) == count
        assert manifest['display_driver'] == 'embedded' and manifest['actual_renderer'] == 'vulkan'
        assert manifest['expedition_inventory_and_cursor_preserved'] and manifest['sources_unchanged_during_capture']
        for path, sha in manifest['source_sha256'].items():
            assert digest(project / 'godot-game' / path.removeprefix('res://')) == sha, path
        for capture in manifest['captures']:
            assert capture['passed'] and digest(folder / capture['image']) == capture['image_sha256']
            if 'wrist_gpu_buffers' in capture:
                assert capture['wrist_gpu_buffers']['passed']
                assert capture['actual_pbr_bindings']['passed']
                wrists.extend(capture['wrist_gpu_buffers']['wrists'])
        previews[kind] = {'captures': count, 'all_images_visually_reviewed': True,
            'all_inspections_passed': True, 'source_sha256': manifest['source_sha256'],
            'manifest': f'godot_preview/{kind}/capture_manifest.json',
            'world_inventory_cursor_preserved': True, 'renderer': 'Godot 4.7 Forward+ Vulkan, embedded, 1280x720'}
    assert wrists and all(w['passed'] for w in wrists)
    build = json.loads((model / 'build_report.json').read_text())
    render_review = {name: dict(build['renders'][name], sha256=digest(model / build['renders'][name]['file']),
        directly_visually_reviewed=True) for name in ('bilateral_dorsum', 'preview_finger_dorsum', 'finger_palm_closeup')}
    assert digest(model / 'realism_before_after_after.png') == digest(model / 'preview_finger_dorsum.png')
    logs = [args.test_log, 'godot_import_02.log', 'godot_realism_preview_final02.log',
        'godot_realism_gameplay_final02.log', 'padding_verification_iteration04_03.log',
        'verification_iteration03_02.log', 'mac_output/iteration_03/verification_report.json',
        'diagnostics/tangent_repair_report.json', 'diagnostics/tangent_zero_provenance.json',
        'diagnostics/material_diagnostic_summary03.json', 'diagnostics/atlas_background_stats03.json',
        'padding_04.log', 'package_04.log', 'review_04.log', 'review_setup_03.log']
    assert all((stage / name).is_file() for name in logs)
    summary = {'status': 'passed', 'completed_at': datetime.now(timezone.utc).isoformat(),
        'model_iteration': args.model_iteration, 'preview_iteration': args.preview_iteration,
        'model_sha256': {p.name: digest(p) for p in model.iterdir() if p.suffix in ('.blend', '.glb')},
        'blender_independent_validation': args.independent_report,
        'blender_independent_report_sha256': digest(model / args.independent_report),
        'blender_review': render_review,
        'blender_saved_presentation': preservation['presentation_preserved'],
        'headless': {'passed': 7, 'failed': 0, 'tests': ['player_finger_joints', 'player_hands_detailed',
            'player_hands_greybox', 'player_arm', 'weapon_hand_contacts', 'chest_hands', 'test_room_session']},
        'previews': previews, 'preserved_prior_files': len(preserved), 'all_prior_hashes_unchanged': True,
        'gpu_readback': {'capture_count': 12, 'wrist_vertex_samples': sum(w['vertex_count'] for w in wrists),
            'max_position_error_m': max(w['max_position_error_m'] for w in wrists),
            'max_normal_error': max(w['max_normal_error'] for w in wrists),
            'minimum_jacobian': min(w['minimum_jacobian_determinant'] for w in wrists),
            'invalid_tangents': sum(w['invalid_tangents'] for w in wrists),
            'invalid_vertices': sum(w['invalid_vertex_count'] for w in wrists), 'passed': True},
        'texture_review': {'actual_pbr_maps': ['basecolor', 'normal', 'roughness'], 'resolution': [4096,4096],
            'prior_distant_atlas_seams_rejected_and_fixed': True,
            'valid_texel_detail_preserved_in_padding_fix': True,
            'authored_pixels_preserved_per_map': padding['authored_pixels'],
            'blank_pixels_filled_per_atlas': padding['filled_pixels'],
            'neutral_closeups_are_separate_review_lighting': True},
        'validation_logs': logs,
        'limitations': ['Game initial appearance selection is unchanged; the updated asset is the detailed hand profile.',
            'Previous fixture ObjectDB exit warnings and non-failing debug script warnings remain.',
            'The full unrelated project test suite was not run.']}
    (stage / 'validation_summary.json').write_text(json.dumps(summary, indent=2))
    print(json.dumps({'status': 'passed', 'headless': 7, 'captures': 18, 'gpu': summary['gpu_readback']}))


if __name__ == '__main__':
    main()
