"""Reuse the accepted reverse cut's exact sword and arm poses in reverse order.

No spatial reflection, negative scale, new wrist pose, or new arm solve.
Authored windup/recovery are both .62s, so contact remains at .71s.
"""
import bpy
import copy
import hashlib
import json
import platform
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json'
OUT = ROOT / 'candidate_03'
assert platform.system() == 'Darwin'
OUT.mkdir(exist_ok=True)
original = json.loads(SOURCE.read_text())
manifest = copy.deepcopy(original)
reverse = original['clips']['left_reverse']
forehand = manifest['clips']['right_diagonal']
duration = reverse['duration_seconds']
assert duration == 1.42
assert reverse['timing'] == forehand['timing']
assert reverse['timing']['windup_seconds'] == reverse['timing']['recovery_seconds']

def reversed_rows(rows):
    result = []
    for entry in json.loads((ROOT / 'forehand_timeline.json').read_text()):
        new = copy.deepcopy(rows[entry['source_index']])
        new['time_seconds'] = entry['time_seconds']
        result.append(new)
    return result

forehand['tracks']['sword'] = reversed_rows(reverse['tracks']['sword'])
forehand['right_arm'] = reversed_rows(reverse['right_arm'])
# The v2 schema synchronizes all three channels. Retain the original shield
# curve at the new key times through Godot's actual sampler; never reverse it.
forehand['tracks']['shield'] = json.loads((ROOT / 'shield_samples.json').read_text())
assert all(abs(sword['time_seconds'] - shield['time_seconds']) < 1e-8 for sword, shield in zip(forehand['tracks']['sword'], forehand['tracks']['shield']))
for name, clip in original['clips'].items():
    if name != 'right_diagonal':
        assert manifest['clips'][name] == clip

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps = 120
controls = {}
for name in ('sword', 'shoulder', 'elbow', 'wrist'):
    obj = bpy.data.objects.new('forehand_from_reverse_' + name, None)
    bpy.context.collection.objects.link(obj)
    obj.rotation_mode = 'QUATERNION'
    controls[name] = obj
for row, arm in zip(forehand['tracks']['sword'], forehand['right_arm']):
    assert row['time_seconds'] == arm['time_seconds']
    frame = row['time_seconds'] * 120 + 1
    obj = controls['sword']
    obj.location = row['position']
    x, y, z, w = row['rotation_xyzw']
    obj.rotation_quaternion = (w, x, y, z)
    obj.keyframe_insert('location', frame=frame)
    obj.keyframe_insert('rotation_quaternion', frame=frame)
    for name in ('shoulder', 'elbow', 'wrist'):
        controls[name].location = arm[name]
        controls[name].keyframe_insert('location', frame=frame)

previous = manifest.pop('forehand_edge_alignment', None)
manifest['forehand_from_reverse'] = {
    'execution_os': platform.system(),
    'blender_version': bpy.app.version_string,
    'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
    'preserved_reverse_sha256': hashlib.sha256(json.dumps(reverse, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
    'changed': 'right_diagonal sword/right_arm sample order only; existing poses traversed in the opposite direction',
    'recovery': 'Omit the original reverse preparation hold; return through its original .341666667-to-0 poses over the unchanged .62s recovery.',
    'preserved': 'left_reverse and every other clip, right_diagonal timing, original meshes and hand grip',
    'shield': 'Original forehand shield curve sampled at the synchronized new key times using the production Godot sampler; not reversed.',
    'supersedes_forehand_edge_alignment': previous,
}
bpy.context.scene.frame_end = 172
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'Forehand_From_Restored_Reverse.blend'))
(OUT / 'motion_manifest.json').write_text(json.dumps(manifest, separators=(',', ':')))
print('FOREHAND AUTHOR PASS: reverse preserved; existing sword/arm poses retained; no spatial reflection')
