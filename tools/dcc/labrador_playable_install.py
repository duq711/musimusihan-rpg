"""Install an accepted Labrador player with guarded, reversible app renames.

The caller owns geometry, visual and native acceptance. This tool binds those
receipts to the actual candidate and preserves the prior playable as a backup.
It does not delete either app, alter launch links, stop a process or control UI.
"""
import argparse
import datetime
import hashlib
import json
import plistlib
import subprocess
from pathlib import Path


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signature(app):
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)],
                   check=True, capture_output=True)


def install(args):
    root = Path(__file__).resolve().parents[2]
    builds = root / 'unity-game/Builds'
    current = builds / 'MusimusihanRPG.app'
    candidate = args.candidate.resolve()
    backup = args.backup.resolve()
    assert candidate.parent == backup.parent == builds.resolve()
    assert candidate != current and backup != current and candidate != backup
    assert current.is_dir() and candidate.is_dir() and not backup.exists()
    before = json.loads(args.before.read_text())
    assert Path(before['app']).resolve() == current.resolve()
    for name, digest in before['hashes'].items():
        assert sha(current / name) == digest, f'Current playable changed: {name}'
    signature(current)
    signature(candidate)
    for path, digest in json.loads(args.guards.read_text()).items():
        assert sha(Path(path)) == digest, f'Accepted artifact changed: {path}'
    native = json.loads(args.native.read_text())
    imported = json.loads(args.imported.read_text())
    assert native['result'] == imported['result'] == 'Passed'
    assert not native['errors'] and len(native['checks']) == 30
    assert sha(Path(imported['source_fbx'])) == imported['source_fbx_sha256']
    assert imported['post_import_preservation']['unexpected_changed_files'] == []
    assert imported['post_import_preservation']['changed_runtime_files'] == []
    info = plistlib.loads((candidate / 'Contents/Info.plist').read_bytes())
    executable = info['CFBundleExecutable']
    assert executable == 'MusimusihanRPG' and executable.isascii()
    running = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
    for app in [current, candidate]:
        path = str(app / 'Contents/MacOS' / executable)
        assert not any(path in command or Path(command.strip()).name == executable
                       for command in running), 'Player is running'
    link = Path.home() / 'Applications/무시무시한 RPG.app'
    assert link.is_symlink() and link.resolve() == current.resolve()
    dock_data = subprocess.check_output(['defaults', 'export', 'com.apple.dock', '-'])
    dock = plistlib.loads(dock_data)
    dock_strings = json.dumps(dock, default=str, ensure_ascii=False)
    assert 'MusimusihanRPG.app' in dock_strings or '무시무시한' in dock_strings
    files = list(before['hashes'])
    if 'Contents/_CodeSignature/CodeResources' not in files:
        files.append('Contents/_CodeSignature/CodeResources')
    accepted_hashes = {name: sha(candidate / name) for name in files}
    current.rename(backup)
    try:
        candidate.rename(current)
        signature(current)
        assert link.resolve() == current.resolve()
        for name, digest in accepted_hashes.items():
            assert sha(current / name) == digest
    except BaseException:
        if current.exists():
            current.rename(candidate)
        backup.rename(current)
        raise
    receipt = {'result': 'Passed', 'path': str(current),
               'prior_playable': str(backup), 'source_candidate': str(candidate),
               'hashes': accepted_hashes, 'native_acceptance_checks': len(native['checks']),
               'actual_import_checks': imported['checks'],
               'run_duration_s': imported['duration_s'],
               'signature': 'Deep strict codesign passed before and after reversible rename',
               'applications_symlink_preserved': str(link), 'dock_reference_preserved': True,
               'old_playable_guard': 'All before hashes and sealed resource manifest match',
               'accepted_artifact_guards_sha256': sha(args.guards),
               'native_acceptance_sha256': sha(args.native),
               'import_receipt_sha256': sha(args.imported),
               'installed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
               'scope': 'Caller-approved repair; no process interruption, desktop input or audio.'}
    args.receipt.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'result': 'Passed', 'installed': str(current)}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ['candidate', 'backup', 'before', 'guards', 'native', 'imported', 'receipt']:
        parser.add_argument('--' + name, type=Path, required=True)
    install(parser.parse_args())
