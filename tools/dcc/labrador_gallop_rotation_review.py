"""Read-only Run foot rotation probe. Blender CLI; no production data is changed."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

parser = argparse.ArgumentParser()
parser.add_argument('--blend', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
parser.add_argument('--hz', type=int, default=120)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(args.blend))
sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import set_action

rig = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
action = bpy.data.actions['Run']
set_action(rig, action)
fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
start, end = action.frame_range
duration = (end - start) / fps
count = round(duration * args.hz)
names = ['IKFrontLeg.L_47', 'IKFrontLeg.R_51', 'IKBackLeg.L_45',
         'IKBackLeg.R_49', 'FF.L_46', 'FF.R_50', 'FFB.L_44', 'FFB.R_48']
samples = []
for index in range(count + 1):
    frame = start + (end - start) * index / count
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    samples.append({name: rig.pose.bones[name].matrix.to_quaternion().normalized()
                    for name in names})

def rotation_degrees(before, after):
    delta = after @ before.inverted()
    delta.normalize()
    if delta.w < 0:
        delta.negate()
    return math.degrees(2 * math.atan2(Vector((delta.x, delta.y, delta.z)).length, delta.w))

results = {}
for name in names:
    steps = [rotation_degrees(a[name], b[name]) for a, b in zip(samples, samples[1:])]
    peak = max(steps)
    index = steps.index(peak)
    results[name] = {
        'max_world_rotation_step_deg': peak,
        'phase_range': [index / count, (index + 1) / count],
        'peak_world_rotation_deg_s': peak * args.hz,
        'loop_rotation_delta_deg': rotation_degrees(samples[-1][name], samples[0][name]),
    }
report = {
    'scope': 'New Run foot/wrist/ankle rotation only, actual evaluated pose at 120 Hz; shortest signed quaternion log avoids acos precision and q/-q ambiguity.',
    'blend_sha256': hashlib.sha256(args.blend.read_bytes()).hexdigest(),
    'duration_s': duration,
    'sample_hz': args.hz,
    'samples': count + 1,
    'results': results,
    'limits': ['Angular bounds diagnose abrupt rotations but do not establish visual naturalness or contact pressure.'],
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(report, indent=2) + '\n')
print('FOOT_ROTATION_REVIEW', json.dumps(results))
