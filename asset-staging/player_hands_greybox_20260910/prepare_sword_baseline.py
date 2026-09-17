from pathlib import Path
import difflib
import hashlib
import json
import re
import shutil

WORKSPACE = Path(__file__).resolve().parents[2]
SOURCE = WORKSPACE / 'godot-game'
BASE = Path(__file__).resolve().parent / 'baseline_without_greybox'
assert not BASE.exists(), 'Never overwrite an existing baseline.'
BASE.mkdir()
for child in SOURCE.iterdir():
    if child.is_file():
        shutil.copy2(child, BASE / child.name)
for folder in ['scripts', 'tests', 'shaders']:
    shutil.copytree(SOURCE / folder, BASE / folder)
(BASE / 'assets').symlink_to(SOURCE / 'assets', target_is_directory=True)
(BASE / 'artifacts').mkdir()
(BASE / '.godot').mkdir()
(BASE / '.godot' / 'imported').symlink_to(SOURCE / '.godot' / 'imported', target_is_directory=True)
for child in (SOURCE / '.godot').iterdir():
    if child.is_file():
        shutil.copy2(child, BASE / '.godot' / child.name)

changes = []
def replace_once(text, before, after=''):
    assert text.count(before) == 1, ('Expected one exact authored addition', before[:140], text.count(before))
    return text.replace(before, after, 1)

def remove_span(text, beginning, next_original):
    start = text.index(beginning)
    end = text.index(next_original, start)
    return text[:start] + text[end:]

def save(name, transform):
    path = BASE / 'scripts' / name
    current = path.read_text()
    reverted = transform(current)
    assert 'greybox' not in reverted.lower(), ('Unexpected greybox change remains', name)
    path.write_text(reverted)
    changes.append({'file': name, 'production_sha256': hashlib.sha256(current.encode()).hexdigest(), 'baseline_sha256': hashlib.sha256(reverted.encode()).hexdigest()})
    return ''.join(difflib.unified_diff(current.splitlines(True), reverted.splitlines(True), fromfile='production/scripts/' + name, tofile='baseline/scripts/' + name))

def arm(text):
    text = replace_once(text, 'var greybox_visual: Node3D\nvar greybox_enabled := false\nvar _arm_visible := true\n')
    for call in [
        'set_finger_curl", index, proximal_radians, distal_radians',
        'set_grip", amount, thumb_amount',
        'set_string_draw", grip_ratio, release_ratio',
        'set_relaxed_pose", openness',
        'fit_arm", shoulder_world, elbow_world',
        'set_arm_visible", enabled',
        'reset_pose"',
    ]:
        text = replace_once(text, '\tif greybox_enabled:\n\t\tgreybox_visual.call("' + call + ')\n\t\treturn\n')
    text = replace_once(text, '\t_arm_visible = enabled\n')
    text = replace_once(text, '\tif greybox_enabled:\n\t\treturn greybox_visual.call("get_source_meshes")\n')
    text = remove_span(text, '## Retain this exact wrist, parent contact and original source resources.\n', 'func _add_digit(')
    text = replace_once(text, '\tif is_instance_valid(greybox_visual):\n\t\tgreybox_visual.free()\n\tgreybox_visual = null\n\tgreybox_enabled = false\n\t_arm_visible = true\n')
    return text

def chest(text):
    text = replace_once(text, 'var greybox_enabled := false\n')
    text = remove_span(text, 'func set_greybox_enabled(', 'func _ensure_built(')
    return text

def player(text):
    text = replace_once(text, 'var hands_greybox_enabled := false\n')
    text = remove_span(text, '## An opt-in art review mode, owned by this player instance only. Gameplay\n', 'func _add_sword_shield_arm(')
    return text

def catalog(text):
    return replace_once(text, '\t\t_entry("player_hands_greybox", "기본", "캐릭터 그래픽 · 양손 그레이박스", "검·방패 보관과 횃불 소등 · 실제 양손·소매 비교 · 왼쪽 상자 E · I에서 활 장착 후 당기기", "player_hands_greybox"),\n')

def room(text):
    text = replace_once(text, '\tif feature_id != "player_hands_greybox":\n\t\tplayer.set_hands_greybox_enabled(false)\n')
    text = replace_once(text, '\t\t"player_hands_greybox":\n\t\t\tif _prepare_player_hands_greybox():\n\t\t\t\t_hide_test_panel()\n')
    text = remove_span(text, 'func _prepare_player_hands_greybox(', 'func _restock_camping_supplies(')
    text = replace_once(text, '\tsuspend_stress_effects()\n\tplayer.set_hands_greybox_enabled(false)\n\tTestRoomSandbox.reset_loadout()', '\tsuspend_stress_effects()\n\tTestRoomSandbox.reset_loadout()')
    text = replace_once(text, 'func leave_room() -> void:\n\tplayer.set_hands_greybox_enabled(false)\n', 'func leave_room() -> void:\n')
    text = remove_span(text, 'func _begin_scene_loading(', 'func _status(')
    return text

patch = ''
for name, transform in [('player_arm_visual.gd', arm), ('chest_hand_visuals.gd', chest), ('player.gd', player), ('test_room_catalog.gd', catalog), ('test_room.gd', room)]:
    patch += save(name, transform)
new_file = BASE / 'scripts' / 'greybox_arm_visual.gd'
new_file.unlink()
(BASE / 'scripts' / 'greybox_arm_visual.gd.uid').unlink(missing_ok=True)

# The original test and all unrelated scripts remain byte-for-byte copies.
for path in (BASE / 'scripts').glob('*.gd'):
    if path.name not in {c['file'] for c in changes}:
        assert path.read_bytes() == (SOURCE / 'scripts' / path.name).read_bytes()
test = 'tests/sword_long_grip_test.gd'
assert (BASE / test).read_bytes() == (SOURCE / test).read_bytes()

notes = {
    'baseline_project': str(BASE),
    'method': 'Copy current project, then reverse only every authored greybox addition in five existing scripts; remove new adapter. No pre-task Git baseline exists, so this is an explicit reverse-patch baseline, not a retrieved historical commit.',
    'production_files_modified': False,
    'large_resources': 'Read-only usage of symlinked production assets/imported cache; independent scripts, test runner, test source, project settings, user cache files, shader cache and output folder.',
    'reversed_scripts': changes,
    'unchanged_test_sha256': hashlib.sha256((BASE / test).read_bytes()).hexdigest(),
}
(BASE.parent / 'sword_baseline_reverse.patch').write_text(patch)
(BASE.parent / 'sword_baseline_manifest.json').write_text(json.dumps(notes, indent=2) + '\n')
print(json.dumps(notes, indent=2))
