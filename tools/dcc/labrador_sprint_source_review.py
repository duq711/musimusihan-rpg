"""Read-only source cycle and prior core review for the temporal sprint revision.

Mac Blender CLI. Actual mocap markers and rig joints are diagnostic proxies;
neither source-marker height nor a snapshot proves contact pressure/naturalness.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh
from labrador_pet import set_action

parser = argparse.ArgumentParser()
parser.add_argument('--source-base', type=Path, required=True)
parser.add_argument('--previous-blend', type=Path, required=True)
parser.add_argument('--report', type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
raw = args.source_base / 'source/raw_bvh_data'
FOOT = ['b__LeftFinger', 'b_RightFinger', 'b_LeftToe', 'b_RightToe']
ANKLE = ['b_LeftHand', 'b_RightHand', 'b_LeftAnkle', 'b_RightAnkle']
SPINE = ['b_Hips', 'b_Spine1', 'b_Spine2', 'b_Spine3']
FORE = ['b_LeftArm', 'b_RightArm']
HIND = ['b_LeftLegUpper', 'b_RightLegUpper']
captures = {}
caches = {}

def pose(file, frame):
    if file not in captures:
        captures[file] = read_bvh(raw / file)
        caches[file] = {}
    if frame not in caches[file]:
        caches[file][frame] = captures[file].world_pose(frame)
    return caches[file][frame]

def normalized_feature(p):
    origin = p['b_Hips'].translation
    forward = p['b_Spine3'].translation - origin
    forward.y = 0
    forward.normalize()
    right = Vector((forward.z, 0, -forward.x))
    values = []
    for name in FOOT + ANKLE + SPINE[1:]:
        v = p[name].translation - origin
        values.extend((v.dot(right), v.dot(forward), v.y))
    return np.array(values), forward

def pitch(v, forward, up):
    return math.degrees(math.atan2(v.dot(up), v.dot(forward)))

def core_metrics(points, forward, up):
    vectors = [b - a for a, b in zip(points, points[1:])]
    chord = (points[-1] - points[0]).length
    arc = sum(v.length for v in vectors)
    caudal = pitch(vectors[0], forward, up)
    cranial = pitch(vectors[-1], forward, up)
    return {'chord_cm': chord, 'arc_cm': arc, 'chord_arc_ratio': chord / arc,
            'sagittal_curve_deg': cranial - caudal,
            'whole_body_pitch_deg': pitch(points[-1] - points[0], forward, up)}

def value_range(rows, key):
    values = [r[key] for r in rows]
    return [min(values), max(values)]

def intervals(mask):
    n = len(mask)
    if all(mask):
        return [[0, 1]]
    starts = [i for i, active in enumerate(mask) if active and not mask[(i - 1) % n]]
    found = []
    for start in starts:
        end = start
        while end < start + n and mask[end % n]:
            end += 1
        found.append([start / n, end / n])
    return found

def review_segment(file, start, end):
    poses = [pose(file, i) for i in range(start, end + 1)]
    cap = captures[file]
    duration = (end - start) * cap.frame_time
    first, last = poses[0]['b_Hips'].translation, poses[-1]['b_Hips'].translation
    displacement = last - first
    displacement.y = 0
    forward = displacement.normalized()
    up = Vector((0, 1, 0))
    body = [core_metrics([p[n].translation for n in SPINE], forward, up) for p in poses]
    floor = {n: min(p[n].translation.y for p in poses) for n in FOOT}
    heights = [[p[n].translation.y - floor[n] for n in FOOT] for p in poses]
    airborne = [all(v > 2 for v in h) for h in heights[:-1]]
    spread = []
    collection = []
    fore_reach = []
    hind_drive = []
    for p in poses:
        positions = [(p[n].translation - p['b_Hips'].translation).dot(forward) for n in FOOT]
        spread.append(max(positions) - min(positions))
        collection.append(min(positions[2:]))
        fore_reach.append(max((p[f].translation - p[s].translation).dot(forward) for f, s in zip(FOOT[:2], FORE)))
        hind_drive.append(max(-(p[f].translation - p[s].translation).dot(forward) for f, s in zip(FOOT[2:], HIND)))
    features = [normalized_feature(p)[0] for p in poses]
    delta = features[-1] - features[0]
    curve = value_range(body, 'sagittal_curve_deg')
    result = {
        'file': file, 'raw_frames_zero_based': [start, end], 'duration_s': duration,
        'root_planar_displacement_speed_m_s': displacement.length / 100 / duration,
        'pose_loop_feature_rms_cm': float(np.sqrt(np.mean(delta * delta))),
        'root_height_cm': [min(p['b_Hips'].translation.y for p in poses), max(p['b_Hips'].translation.y for p in poses)],
        'spine_whole_pitch_deg': value_range(body, 'whole_body_pitch_deg'),
        'spine_sagittal_curve_deg': curve, 'spine_curve_excursion_deg': curve[1] - curve[0],
        'spine_chord_cm': value_range(body, 'chord_cm'),
        'spine_chord_arc_ratio': value_range(body, 'chord_arc_ratio'),
        'all_paw_span_cm': [min(spread), max(spread)],
        'max_both_hind_paws_forward_of_hips_cm': max(collection),
        'leading_fore_reach_cm': max(fore_reach), 'rear_hind_drive_cm': max(hind_drive),
        'marker_suspension_proxy': {
            'method': 'All four toe/finger markers exceed their segment minimum height by 2 cm; not actual skinned sole/force contact.',
            'fraction': sum(airborne) / len(airborne), 'phase_intervals': intervals(airborne),
            'max_common_clearance_cm': max(min(h) for h in heights),
        },
    }
    return result

file = 'dog_fast_run_02_006.bvh'
pose(file, 0)
cap = captures[file]
coarse = {}
for frame in range(0, len(cap.frames), 4):
    p = pose(file, frame)
    feature, heading = normalized_feature(p)
    coarse[frame] = (feature, heading, p['b_Hips'].translation.copy())
ranked = []
for start, (feature, heading, root) in coarse.items():
    for count in range(32, 65, 4):
        end = start + count
        if end not in coarse:
            continue
        other, direction, destination = coarse[end]
        delta = destination - root
        delta.y = 0
        speed = delta.length / 100 / (count * cap.frame_time)
        if speed < 3.8:
            continue
        angle = math.degrees(heading.angle(direction))
        rms = float(np.sqrt(np.mean((other - feature) ** 2)))
        if rms > 4.0 or angle > 6.0:
            continue
        ranked.append((rms + angle * .08, start, end, speed, rms, angle))
ranked.sort()
selected = []
for row in ranked:
    if any(abs(row[1] - old[1]) < 36 for old in selected):
        continue
    selected.append(row)
    if len(selected) == 8:
        break
segments = [review_segment(file, 2944, 2992)]
for _, start, end, speed, rms, angle in selected:
    if (start, end) == (2944, 2992):
        continue
    result = review_segment(file, start, end)
    result['coarse_search_heading_closure_deg'] = angle
    segments.append(result)
for start, end in [(1824, 1868), (1412, 1452), (852, 896)]:
    segments.append(review_segment('dog_fast_run_02_005.bvh', start, end))

bpy.ops.wm.open_mainfile(filepath=str(args.previous_blend))
rig = bpy.data.objects['LabradorPet']
set_action(rig, bpy.data.actions['Run'])
target_spine = ['Back_38', 'Torso_23', 'Torso2_22', 'Torso3_15']
target_paws = ['FF.L_46', 'FF.R_50', 'FFB.L_44', 'FFB.R_48']
target_rows = []
for i in range(61):
    frame = 1 + i / 2
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
    bpy.context.view_layer.update()
    points = [rig.matrix_world @ rig.pose.bones[n].matrix.translation for n in target_spine]
    core = core_metrics([p * 100 for p in points], Vector((0, -1, 0)), Vector((0, 0, 1)))
    core['hip_m'] = list(points[0])
    core['chest_m'] = list(points[-1])
    fore = Vector((0, -1, 0))
    paws = [rig.matrix_world @ rig.pose.bones[n].matrix.translation for n in target_paws]
    relative = [(p - points[0]).dot(fore) * 100 for p in paws]
    core['paw_marker_span_cm'] = max(relative) - min(relative)
    core['both_hind_markers_forward_of_hip_cm'] = min(relative[2:])
    core['phase'] = i / 60
    target_rows.append(core)
dt = 1 / 120
velocities = [(Vector(b['hip_m']) - Vector(a['hip_m'])) / dt for a, b in zip(target_rows, target_rows[1:])]
acceleration = [(b - a) / dt for a, b in zip(velocities, velocities[1:])]
peak_v = max(range(len(velocities)), key=lambda i: abs(velocities[i].z))
peak_a = max(range(len(acceleration)), key=lambda i: abs(acceleration[i].z))
prior = {
    'blend_sha256': hashlib.sha256(args.previous_blend.read_bytes()).hexdigest(),
    'sample_hz': 120, 'samples': 61, 'spine_whole_pitch_deg': value_range(target_rows, 'whole_body_pitch_deg'),
    'spine_sagittal_curve_deg': value_range(target_rows, 'sagittal_curve_deg'),
    'spine_chord_cm': value_range(target_rows, 'chord_cm'),
    'spine_chord_arc_ratio': value_range(target_rows, 'chord_arc_ratio'),
    'paw_marker_span_cm': value_range(target_rows, 'paw_marker_span_cm'),
    'max_both_hind_markers_forward_of_hip_cm': max(r['both_hind_markers_forward_of_hip_cm'] for r in target_rows),
    'peak_hip_vertical_velocity_m_s': velocities[peak_v].z,
    'peak_hip_velocity_phase_interval': [peak_v / 60, (peak_v + 1) / 60],
    'peak_discrete_hip_vertical_acceleration_m_s2': acceleration[peak_a].z,
    'peak_hip_acceleration_phase': (peak_a + 1) / 60,
    'hip_phase_dip_samples': [r for r in target_rows if .78 <= r['phase'] <= .96],
    'derivative_limit': 'Linear key interpolation causes ordinary acceleration impulses at keys; this read-only diagnostic locates the much larger global adaptive-body correction dip, not a force measurement.',
}
source_rest = pose(file, 2944)
source_chains = {'fore': ['b_LeftArm', 'b_LeftForeArm', 'b_LeftHand'],
                 'hind': ['b_LeftLegUpper', 'b_LeftLeg', 'b_LeftLeg1', 'b_LeftAnkle'],
                 'spine': SPINE}
target_chains = {'fore': ['FrontUpperLeg.L_17', 'FrontLowerLeg.L_16', 'IKFrontLeg.L_47'],
                 'hind': ['BackLeg.L_26', 'BackUpperLeg.L_25', 'BackLowerLeg.L_24', 'IKBackLeg.L_45'],
                 'spine': target_spine}
source_lengths = {key: [(source_rest[b].translation - source_rest[a].translation).length
                        for a, b in zip(names, names[1:])]
                  for key, names in source_chains.items()}
target_lengths = {key: [(rig.matrix_world.to_3x3() @ (rig.data.bones[b].head_local - rig.data.bones[a].head_local)).length * 100
                        for a, b in zip(names, names[1:])]
                  for key, names in target_chains.items()}
proportions = {'source_segment_lengths_cm': source_lengths,
               'target_bind_segment_lengths_cm': target_lengths,
               'source_segment_shares': {k: [v / sum(values) for v in values] for k, values in source_lengths.items()},
               'target_segment_shares': {k: [v / sum(values) for v in values] for k, values in target_lengths.items()},
               'target_to_source_total_length_ratio': {k: sum(target_lengths[k]) / sum(source_lengths[k]) for k in source_lengths},
               'interpretation': 'The same model has a longer torso, shorter fore upper segment and longer hind tibial segment than the capture. Independent neutral-centred paw profiles widen collection; equal bone scaling or source world ankle quaternion copying cannot preserve the captured silhouette.'}
out = {
    'scope': 'New temporal sprint source/core diagnostics. Previous photo silhouette acceptance is not reused as naturalness acceptance.',
    'source_units': 'BVH centimetres/Y up; source-body feature comparison removes planar root movement and instantaneous heading.',
    'source_search': {'file': file, 'step_frames': 4, 'period_frame_range': [32, 64], 'minimum_planar_speed_m_s': 3.8, 'max_pose_feature_rms_cm': 4, 'max_heading_closure_deg': 6, 'qualifying_windows': len(ranked)},
    'segments': segments, 'previous_gallop_core': prior, 'bone_proportions': proportions,
    'limits': ['Source-marker suspension is a proxy and must be re-evaluated on the actual Labrador sole skin.', 'Low loop discrepancy does not prove a high-speed extended/collected rhythm.', 'Reference video rhythm is defined by root UI observation; its media is not downloaded by this tool.'],
}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(out, ensure_ascii=False, indent=2) + '\n')
print('SPRINT_SOURCE_CORE_REVIEW', args.report)
