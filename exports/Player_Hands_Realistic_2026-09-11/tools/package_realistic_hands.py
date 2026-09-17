"""Package only a verified candidate and its captured, matching Godot state."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-iteration', required=True)
    parser.add_argument('--preview-iteration', required=True)
    args = parser.parse_args()
    stage = Path(__file__).resolve().parents[1]
    project = stage.parents[1]
    model = stage / 'mac_output' / args.model_iteration
    summary = json.loads((stage / 'validation_summary.json').read_text())
    assert summary['status'] == 'passed'
    assert summary['model_iteration'] == args.model_iteration
    assert summary['preview_iteration'] == args.preview_iteration
    assert all(digest(model / name) == sha for name, sha in summary['model_sha256'].items())
    assert digest(model / summary['blender_independent_validation']) == summary['blender_independent_report_sha256']
    preserved = json.loads((stage / 'baseline/preserved_artifacts.json').read_text())
    assert all(digest(project / path) == sha for path, sha in preserved.items())
    destination = project / 'exports/Player_Hands_Realistic_2026-09-11'
    archive = destination.with_suffix('.zip')
    assert not destination.exists() and not archive.exists()
    destination.mkdir()

    def copy(source, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    for source in model.iterdir():
        if source.is_file() and source.suffix in ('.blend', '.glb', '.png', '.json'):
            copy(source, destination / source.name)
    for source in (stage / 'tools').glob('*.py'):
        copy(source, destination / 'tools' / source.name)
    copy(stage / 'README.md', destination / 'WORK_RECORD.md')
    copy(stage / 'DELIVERY_README.md', destination / 'README.md')
    copy(stage / 'validation_summary.json', destination / 'validation_summary.json')
    for name in summary['validation_logs']:
        copy(stage / name, destination / 'validation' / name)
    copy(stage / 'baseline/preserved_artifacts.json', destination / 'validation/preserved_artifacts.json')
    runtime_sources = set()
    for kind in ('player_finger_joints', 'player_hands_detailed'):
        source_dir = project / 'godot-game/artifacts/visual_qa' / kind / args.preview_iteration
        manifest = json.loads((source_dir / 'capture_manifest.json').read_text())
        for path, sha in manifest['source_sha256'].items():
            relative = path.removeprefix('res://')
            assert digest(project / 'godot-game' / relative) == sha, relative
            runtime_sources.add(relative)
        shutil.copytree(source_dir, destination / 'godot_preview' / kind)
    runtime_sources.update(['README.md', 'TEST_ROOM.md', 'design/TEAM_ROLES.md',
        'assets/3d/player/hands_detailed/README.md', 'scripts/test_room_catalog.gd',
        'tests/player_hands_detailed_test.gd', 'tests/player_finger_joints_test.gd',
        'tests/run_embedded_preview.sh', 'tests/run_headless_tests.sh'])
    for relative in sorted(runtime_sources):
        copy(project / 'godot-game' / relative, destination / 'runtime_snapshot' / relative)
    files = {str(path.relative_to(destination)): {'bytes': path.stat().st_size, 'sha256': digest(path)}
        for path in sorted(destination.rglob('*')) if path.is_file()}
    (destination / 'FILE_MANIFEST.json').write_text(json.dumps(files, indent=2, ensure_ascii=False))
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as output:
        for path in sorted(destination.rglob('*')):
            if path.is_file(): output.write(path, str(path.relative_to(destination.parent)))
    with zipfile.ZipFile(archive) as output:
        assert output.testzip() is None
        for path in destination.rglob('*'):
            if path.is_file():
                assert output.read(str(path.relative_to(destination.parent))) == path.read_bytes()
    assert all(digest(project / path) == sha for path, sha in preserved.items())
    result = {'status': 'passed', 'package': str(destination.relative_to(project)),
        'files_including_manifest': len(files) + 1, 'zip_bytes': archive.stat().st_size,
        'zip_sha256': digest(archive), 'preserved_prior_files': len(preserved),
        'all_prior_hashes_unchanged': True, 'zip_crc_and_exact_content_verified': True}
    (stage / 'package_verification.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
