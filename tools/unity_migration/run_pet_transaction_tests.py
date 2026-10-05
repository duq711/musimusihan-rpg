#!/usr/bin/env python3
"""Test actual pet inventory transactions in a small, temporary Unity project."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--unity-app', default=str(Path.home() / 'Applications/RPG-Unity-6000.3.25f1/Unity/Unity.app'))
    parser.add_argument('--companion', action='store_true', help='Also test the production companion against explicit collision fixtures in PlayMode')
    parser.add_argument('--petting', action='store_true', help='Also test mouse petting, reaction bounds and pointer lifecycle in PlayMode')
    parser.add_argument('--locomotion', action='store_true', help='Also test authored gait mode clock, pause and side-view ownership in PlayMode')
    parser.add_argument('--timeout', type=int, default=600, help='Allow background compilation under concurrent Mac workloads')
    args = parser.parse_args()
    if args.locomotion:
        args.petting = True
    if args.petting:
        args.companion = True
    game = ROOT / 'unity-game'
    output = ROOT / 'asset-staging/labrador-pet-20261005'
    checks = output / 'validation'
    checks.mkdir(parents=True, exist_ok=True)
    name = 'locomotion' if args.locomotion else 'petting' if args.petting else 'companion' if args.companion else 'transactions'
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
            if args.petting:
                shutil.copy2(test.with_name('LabradorPettingTests.cs'), stage / 'Assets/PetTests/LabradorPettingTests.cs')
            if args.locomotion:
                shutil.copy2(test.with_name('LabradorLocomotionTests.cs'), stage / 'Assets/PetTests/LabradorLocomotionTests.cs')
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
            if args.petting:
                copied[test.with_name('LabradorPettingTests.cs')] = stage / 'Assets/PetTests/LabradorPettingTests.cs'
                for source_name in ('WorkshopPetting.cs', 'PlayerPresentation.cs', 'PlayerFrameInput.cs',
                             'WorkshopController.cs', 'DungeonInteractionController.cs', 'DungeonMotor.cs',
                             'NativeTrialMenu.cs', 'NativeGameFlow.cs'):
                    path = game / 'Assets/RPG/Gameplay' / source_name
                    copied[path] = stage / 'Assets/RPG/Gameplay' / source_name
            if args.locomotion:
                copied[test.with_name('LabradorLocomotionTests.cs')] = stage / 'Assets/PetTests/LabradorLocomotionTests.cs'
        tested_hashes = {str(original.relative_to(ROOT)): hashlib.sha256(copied_path.read_bytes()).hexdigest()
                         for original, copied_path in copied.items()}
        process = subprocess.Popen(['nice', '-n', '10', str(executable), '-batchmode', '-nographics',
                              '-projectPath', str(stage), '-runTests', '-testPlatform', 'PlayMode' if args.companion else 'EditMode',
                              '-testResults', str(results), '-logFile', str(log)], start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL); process.wait()
            raise RuntimeError(f'Pet tests exceeded {args.timeout}s; stopped their process group before removing the temporary project. See {log}')
        if not results.exists():
            raise RuntimeError(f'Pet transaction tests did not complete (exit {code}); see {log}')
        report = ET.parse(results).getroot()
        summary = {key: report.get(key) for key in ('result', 'total', 'passed', 'failed', 'skipped')}
        print(json.dumps(summary), flush=True)
        if code or report.get('result') != 'Passed' or int(report.get('failed', '0')):
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
        if args.petting:
            receipt['limitations'] = ['Production mouse petting and reaction lifecycle tested against explicit skeletal and skinned head fixtures.',
                                     'Real Labrador skin, authored transitions, rendering and native F2 acceptance are checked separately.']
        if args.locomotion:
            receipt['limitations'] = ['Production petting and gait view/clock lifecycle tested against explicit skeletal clip and skin fixtures.',
                                     'Real Labrador gait clips, paw support, rendered appearance and native F2 acceptance are checked separately.']
        receipt_name = 'locomotion-playmode-validation.json' if args.locomotion else name + '-validation.json'
        (output / receipt_name).write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
