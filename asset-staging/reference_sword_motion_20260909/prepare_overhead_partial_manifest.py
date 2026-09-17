#!/usr/bin/env python3
"""Package received Windows keys for Godot without authoring/resampling motion."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

RAW_SHA = '3c383aacbfb138a1c3ac19686f4a555d06ef2e311575aeefd7c2a529045254b0'
GLB_SHA = 'a0df768367d78a487573101e780b881869b52b17ddd6daeaaea9cbcf6b24f319'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(source, output):
    source = source.resolve()
    hashes = json.loads((source / 'FILE_HASHES.json').read_text())
    for name, entry in hashes.items():
        path = (source / name).resolve()
        assert path.is_relative_to(source) and path.is_file(), name
        assert path.stat().st_size == entry['bytes'] and sha(path) == entry['sha256'], name
    raw_path = source / 'arm_pose_samples.json'
    assert sha(raw_path) == RAW_SHA
    raw = json.loads(raw_path.read_text())
    review_path = source / 'overhead_review.json'
    review = json.loads(review_path.read_text())
    assert raw['status'] == 'authored_windows_surface_finished_output'
    assert len(raw['frames']) == 187 and raw['duration_seconds'] == 1.55
    assert review['provenance']['execution_os'] == 'Windows' and review['provenance']['exit_code'] == 0
    assert list(review['clips']) == ['overhead'] and len(review['right_arm']) == 187
    for index, frame in enumerate(raw['frames']):
        for track in ['sword', 'shield']:
            received = review['clips']['overhead']['tracks'][track][index]
            assert received['time_seconds'] == frame['time_seconds']
            for key in ['position', 'rotation_xyzw']:
                assert received[key] == frame[track][key]
        assert review['right_arm'][index]['time_seconds'] == frame['time_seconds']
        for joint in ['shoulder', 'elbow', 'wrist']:
            assert review['right_arm'][index][joint] == frame['right_arm'][joint]
    result = copy.deepcopy(review)
    result['schema_version'] = 2
    result['status'] = 'authored_windows_partial_output'
    result['delivered_clips'] = ['overhead']
    result['clips']['overhead']['right_arm'] = result.pop('right_arm')
    result['integration'] = {
        'operation': 'lossless_schema_repacking_of_received_windows_keys',
        'source_iteration': 'iteration_07',
        'raw_sidecar_sha256': RAW_SHA,
        'review_sha256': sha(review_path),
        'geometry_path': 'res://assets/animations/reference_sword_motion/Overhead_Final.glb',
        'geometry_sha256': GLB_SHA,
        'required_skin_count': 1, 'required_bone_count': 7, 'required_skinned_mesh_count': 3,
        'samples_resampled_or_authored_on_mac': False,
        'remaining_clips': 'Existing procedural game motions; no new Windows delivery for other actions.'
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({'status': 'pass', 'output': str(output.resolve()), 'sha256': sha(output),
                     'verified_files': len(hashes), 'delivered_clips': ['overhead'],
                     'unchanged_samples_per_track': 187, 'game_installation': 'separate after native GLB verification'}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    prepare(args.source, args.output)
