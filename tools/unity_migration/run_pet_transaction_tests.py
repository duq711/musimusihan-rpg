#!/usr/bin/env python3
"""Test actual pet inventory transactions in a small, temporary Unity project."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unity-app', default=str(Path.home() / 'Applications/RPG-Unity-6000.3.25f1/Unity/Unity.app'))
    parser.add_argument('--companion', action='store_true', help='Also test the production companion against explicit collision fixtures in PlayMode')
    args = parser.parse_args()
    game = ROOT / 'unity-game'
    output = ROOT / 'asset-staging/labrador-pet-20261005'
    checks = output / 'validation'
    checks.mkdir(parents=True, exist_ok=True)
    name = 'companion' if args.companion else 'transactions'
    results, log = checks / (name + '.xml'), checks / (name + '.log')
    if results.exists():
        results.unlink()
    test = game / 'Assets/RPG/GameplayTests/PlayMode/Pets/PetTransactionsTests.cs'
    production = game / 'Assets/RPG/Gameplay/Pets/PetTransactions.cs'
    with tempfile.TemporaryDirectory(prefix='rpg-labrador-transactions-') as temp:
        stage = Path(temp)
        shutil.copytree(game / 'Assets/RPG/Runtime', stage / 'Assets/RPG/Runtime')
        for folder in ('Assets/Pets', 'Assets/PetTests', 'Assets/Resources/Migration', 'Packages', 'ProjectSettings'):
            (stage / folder).mkdir(parents=True, exist_ok=True)
        if args.companion:
            shutil.copytree(game / 'Assets/RPG/Gameplay', stage / 'Assets/RPG/Gameplay')
            shutil.copytree(game / 'Assets/RPG/Shaders', stage / 'Assets/RPG/Shaders')
            shutil.copytree(game / 'Assets/RPG/Resources/Migration', stage / 'Assets/Resources/Migration', dirs_exist_ok=True)
            shutil.copy2(test.with_name('LabradorCompanionTests.cs'), stage / 'Assets/PetTests/LabradorCompanionTests.cs')
        else:
            shutil.copy2(production, stage / 'Assets/Pets/PetTransactions.cs')
        shutil.copy2(test, stage / 'Assets/PetTests/PetTransactionsTests.cs')
        if not args.companion:
            (stage / 'Assets/Pets/PetTransactions.asmdef').write_text(json.dumps({
                'name': 'Rpg.PetTransactions', 'references': ['Rpg.Core'],
                'overrideReferences': True, 'precompiledReferences': ['Newtonsoft.Json.dll']}))
        (stage / 'Assets/PetTests/PetTests.asmdef').write_text(json.dumps({
            'name': 'Rpg.PetTransaction.Tests', 'references': ['Rpg.Core', 'Rpg.Gameplay' if args.companion else 'Rpg.PetTransactions', 'Unity.ugui'],
            'optionalUnityReferences': ['TestAssemblies'],
            'overrideReferences': True, 'precompiledReferences': ['Newtonsoft.Json.dll', 'nunit.framework.dll']}))
        for catalog_name in ('inventory', 'body_health', 'survival', 'stress', 'spells', 'alchemy', 'cooking', 'smithing', 'test_room'):
            shutil.copy2(game / f'Assets/RPG/Resources/Migration/{catalog_name}.json', stage / f'Assets/Resources/Migration/{catalog_name}.json')
        shutil.copy2(game / 'ProjectSettings/ProjectVersion.txt', stage / 'ProjectSettings/ProjectVersion.txt')
        (stage / 'Packages/manifest.json').write_text(json.dumps({'dependencies': {
            'com.unity.nuget.newtonsoft-json': '3.2.2', 'com.unity.test-framework': '1.6.0',
            'com.unity.ugui': '2.0.0', 'com.unity.modules.ui': '1.0.0', 'com.unity.modules.imgui': '1.0.0',
            'com.unity.modules.physics': '1.0.0', 'com.unity.modules.animation': '1.0.0',
            'com.unity.modules.audio': '1.0.0', 'com.unity.modules.imageconversion': '1.0.0'}}))
        executable = Path(args.unity_app) / 'Contents/MacOS/Unity'
        copied = {production: stage / ('Assets/RPG/Gameplay/Pets/PetTransactions.cs' if args.companion else 'Assets/Pets/PetTransactions.cs'),
                  test: stage / 'Assets/PetTests/PetTransactionsTests.cs'}
        if args.companion:
            for path in (game / 'Assets/RPG/Gameplay/Pets').glob('*.cs'):
                copied[path] = stage / 'Assets/RPG/Gameplay/Pets' / path.name
            copied[test.with_name('LabradorCompanionTests.cs')] = stage / 'Assets/PetTests/LabradorCompanionTests.cs'
        tested_hashes = {str(original.relative_to(ROOT)): hashlib.sha256(copied_path.read_bytes()).hexdigest()
                         for original, copied_path in copied.items()}
        run = subprocess.run(['nice', '-n', '10', str(executable), '-batchmode', '-nographics',
                              '-projectPath', str(stage), '-runTests', '-testPlatform', 'PlayMode' if args.companion else 'EditMode',
                              '-testResults', str(results), '-logFile', str(log)], timeout=240)
        if run.returncode or not results.exists():
            raise RuntimeError(f'Pet transaction tests did not complete (exit {run.returncode}); see {log}')
        report = ET.parse(results).getroot()
        summary = {key: report.get(key) for key in ('result', 'total', 'passed', 'failed', 'skipped')}
        print(json.dumps(summary), flush=True)
        if report.get('result') != 'Passed' or int(report.get('failed', '0')):
            for case in report.iter('test-case'):
                if case.get('result') == 'Failed':
                    print(case.get('fullname'), case.findtext('failure/message'))
            raise RuntimeError('Pet transaction tests failed')
        receipt = {'schema_version': 1, 'unity_version': '6000.3.25f1', **summary,
                   'completed_utc': report.get('end-time'),
                   'tests': [case.get('fullname') for case in report.iter('test-case')],
                   'tested_files': tested_hashes,
                   'limitations': ['Inventory ownership, feeding reservation and contact-latch rules only.',
                                   'Actual Labrador model, motions, rendering, companion navigation and F2 integration are not verified.']}
        if args.companion:
            receipt['limitations'] = ['Production companion behavior with explicit collision-only model and clip fixtures.',
                                      'Actual Labrador model, authored motions, final rendering and native-game/F2 menu integration are not verified.']
        (output / (name + '-validation.json')).write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
