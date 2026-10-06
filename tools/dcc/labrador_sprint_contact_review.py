"""Read-only selected BVH contact/reach proxies for sprint authoring (Mac Blender)."""
import argparse
import json
import math
import sys
from pathlib import Path

from mathutils import Vector
sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh

p = argparse.ArgumentParser()
p.add_argument('--capture', type=Path, required=True)
p.add_argument('--start', type=int, required=True)
p.add_argument('--end', type=int, required=True)
p.add_argument('--report', type=Path, required=True)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
capture = read_bvh(a.capture)
poses = [capture.world_pose(i) for i in range(a.start, a.end + 1)]
n = a.end - a.start
names = {'LF': ('b__LeftFinger', 'b_LeftHand', 'b_LeftArm'),
         'RF': ('b_RightFinger', 'b_RightHand', 'b_RightArm'),
         'LH': ('b_LeftToe', 'b_LeftAnkle', 'b_LeftLegUpper'),
         'RH': ('b_RightToe', 'b_RightAnkle', 'b_RightLegUpper')}
forward = poses[-1]['b_Hips'].translation - poses[0]['b_Hips'].translation
forward.y = 0
forward.normalize()

def planar_speed(values, i):
    left, right = max(0, i - 1), min(n, i + 1)
    delta = values[right] - values[left]
    delta.y = 0
    return delta.length / 100 / ((right - left) * capture.frame_time)

def bands(mask):
    mask = mask[:-1]
    result = []
    for begin in range(n):
        if not mask[begin] or mask[(begin - 1) % n]:
            continue
        end = begin
        while end < begin + n and mask[end % n]:
            end += 1
        result.append([begin / n, end / n])
    return result

out = {'capture': str(a.capture), 'source_raw_frames_zero_based': [a.start, a.end],
       'source_duration_s': n * capture.frame_time, 'limbs': {},
       'limits': ['Low marker height plus low planar marker velocity is a support proxy, not pad pressure.',
                  'Finger/toe markers can roll through the pad; ankle and toe velocities are both retained.',
                  'Threshold sweeps expose contact-band uncertainty; final anatomical skin support must be checked independently.']}
for key, (paw, ankle, proximal) in names.items():
    paw_positions = [pose[paw].translation for pose in poses]
    ankle_positions = [pose[ankle].translation for pose in poses]
    floor = min(p.y for p in paw_positions)
    rows = []
    for i, pose in enumerate(poses):
        rows.append({'raw_frame': a.start + i, 'phase': i / n,
                     'paw_height_above_segment_min_cm': paw_positions[i].y - floor,
                     'paw_planar_speed_m_s': planar_speed(paw_positions, i),
                     'ankle_planar_speed_m_s': planar_speed(ankle_positions, i),
                     'paw_forward_to_hip_cm': (paw_positions[i] - pose['b_Hips'].translation).dot(forward),
                     'paw_forward_to_proximal_cm': (paw_positions[i] - pose[proximal].translation).dot(forward)})
    reach = max(rows, key=lambda r: r['paw_forward_to_proximal_cm'])
    rear = min(rows, key=lambda r: r['paw_forward_to_proximal_cm'])
    low_slow = sorted(rows[:-1], key=lambda r: r['paw_planar_speed_m_s'] + r['paw_height_above_segment_min_cm'] * .3)[:8]
    out['limbs'][key] = {'marker_min_height_cm': floor,
                         'max_reach_phase': reach['phase'], 'max_reach_cm': reach['paw_forward_to_proximal_cm'],
                         'max_rear_phase': rear['phase'], 'max_rear_cm': rear['paw_forward_to_proximal_cm'],
                         'height_only_bands_2cm': bands([r['paw_height_above_segment_min_cm'] <= 2 for r in rows]),
                         'low_height_slow_paw_bands': {str(speed): bands([r['paw_height_above_segment_min_cm'] <= 3 and r['paw_planar_speed_m_s'] <= speed for r in rows]) for speed in [.8, 1.2, 1.8]},
                         'low_slow_candidate_samples': sorted(low_slow, key=lambda r: r['phase']),
                         'phase_samples': rows}
spans = []
for i, pose in enumerate(poses):
    positions = [(pose[names[key][0]].translation - pose['b_Hips'].translation).dot(forward) for key in names]
    spans.append({'phase': i / n, 'raw_frame': a.start + i,
                  'all_paw_span_cm': max(positions) - min(positions),
                  'both_hind_forward_of_hips_cm': min(positions[2:])})
out['maximum_extension'] = max(spans, key=lambda r: r['all_paw_span_cm'])
out['deepest_collection'] = min(spans, key=lambda r: r['all_paw_span_cm'])
out['maximum_hind_collection'] = max(spans, key=lambda r: r['both_hind_forward_of_hips_cm'])
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(out, indent=2) + '\n')
print('SPRINT_CONTACT_PROXY', a.report)
