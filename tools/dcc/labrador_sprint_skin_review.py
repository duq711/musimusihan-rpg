"""Independent evaluated skin/core review of the new temporal sprint only.

Mac Blender CLI. No authoring/import changes. Reference-based visual acceptance
is separate; this report does not automatically mark naturalness as passed.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import set_action

p = argparse.ArgumentParser()
p.add_argument('--blend', type=Path, required=True)
p.add_argument('--manifest', type=Path, required=True)
p.add_argument('--report', type=Path, required=True)
p.add_argument('--clip', default='Run')
p.add_argument('--hz', type=int, default=120)
a = p.parse_args(sys.argv[sys.argv.index('--') + 1:])
bpy.ops.wm.open_mainfile(filepath=str(a.blend))
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
mesh = next(o for o in bpy.data.objects if o.type == 'MESH' and 'FF.L_46' in o.vertex_groups)
manifest = json.loads(a.manifest.read_text())
spec = next(c for c in manifest['clips'] if c['name'] == a.clip)
action = bpy.data.actions[a.clip]
set_action(rig, action)
fps = bpy.context.scene.render.fps / bpy.context.scene.render.fps_base
start, end = action.frame_range
duration = (end - start) / fps
assert math.isclose(duration, spec['duration'], abs_tol=1e-6), 'Action/manifest duration mismatch'
assert math.isclose(fps, spec['fps'], abs_tol=1e-6), 'Action/manifest fps mismatch'
assert list(action.frame_range) == spec['frames'], 'Action/manifest frame range mismatch'
n = round(duration * a.hz)
feet = {'LF': ('IKFrontLeg.L_47', 'FF.L_46', 'front.L'),
        'RF': ('IKFrontLeg.R_51', 'FF.R_50', 'front.R'),
        'LH': ('IKBackLeg.L_45', 'FFB.L_44', 'hind.L'),
        'RH': ('IKBackLeg.R_49', 'FFB.R_48', 'hind.R')}
chains = {'LF': ['FrontUpperLeg.L_17', 'FrontLowerLeg.L_16', 'IKFrontLeg.L_47'],
          'RF': ['FrontUpperLeg.R_20', 'FrontLowerLeg.R_19', 'IKFrontLeg.R_51'],
          'LH': ['BackLeg.L_26', 'BackUpperLeg.L_25', 'BackLowerLeg.L_24', 'IKBackLeg.L_45'],
          'RH': ['BackLeg.R_30', 'BackUpperLeg.R_29', 'BackLowerLeg.R_28', 'IKBackLeg.R_49']}
cores = ['Back_38', 'Torso3_15', 'Head_1']
indices = {}
soles = {}
rest_sign = {}
for key, (ankle, toe, _) in feet.items():
    group = {mesh.vertex_groups[name].index for name in (ankle, toe)}
    indices[key] = [v.index for v in mesh.data.vertices if sum(g.weight for g in v.groups if g.group in group) >= .65]
    low = min(mesh.data.vertices[i].co.z for i in indices[key])
    soles[key] = [i for i in indices[key] if mesh.data.vertices[i].co.z <= low + .10]
for names in chains.values():
    points = [rig.data.bones[name].head_local for name in names]
    for i in range(1, len(points) - 1):
        rest_sign[names[i]] = (points[i - 1] - points[i]).cross(points[i + 1] - points[i]).x

def set_frame(frame):
    bpy.context.scene.frame_set(math.floor(frame), subframe=frame % 1)
    bpy.context.view_layer.update()

def core_pose(frame):
    set_frame(frame)
    return {name: rig.matrix_world @ rig.pose.bones[name].matrix.translation for name in cores}

def log_rotation(before, after, dt):
    q = after @ before.inverted()
    q.normalize()
    if q.w < 0:
        q.negate()
    v = Vector((q.x, q.y, q.z))
    if v.length < 1e-14:
        return Vector()
    return v * (2 * math.atan2(v.length, q.w) / v.length / dt)

def sample_skin(frame):
    set_frame(frame)
    ev = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = ev.to_mesh()
    world = ev.matrix_world
    foot = {}
    for key, ids in indices.items():
        points = [world @ data.vertices[i].co for i in ids]
        centroid = sum(points, Vector()) / len(points)
        sole = sum((world @ data.vertices[i].co for i in soles[key]), Vector()) / len(soles[key])
        foot[key] = {'floor_m': min(v.z for v in points), 'centroid': centroid, 'sole_centroid': sole}
    row = {'frame': frame, 'phase': (frame - start) / (end - start),
           'body_floor_m': min((world @ vertex.co).z for vertex in data.vertices),
           'feet': foot, 'bend': {},
           'core': {name: rig.matrix_world @ rig.pose.bones[name].matrix.translation for name in cores},
           'quaternions': {name: rig.pose.bones[name].matrix.to_quaternion().normalized() for pair in feet.values() for name in pair[:2]}}
    for names in chains.values():
        points = [rig.pose.bones[name].matrix.translation for name in names]
        for i in range(1, len(points) - 1):
            u, v = points[i - 1] - points[i], points[i + 1] - points[i]
            row['bend'][names[i]] = {'internal_angle_deg': math.degrees(u.angle(v)),
                                     'sagittal_sign': u.cross(v).x,
                                     'rest_sign_matches': u.cross(v).x * rest_sign[names[i]] > 0}
    ev.to_mesh_clear()
    return row

rows = [sample_skin(start + (end - start) * i / n) for i in range(n + 1)]
# Evaluate actual skin near each authored key as well as the regular 120 Hz grid.
probe_frames = sorted({round(frame, 8) for key in range(math.ceil(start), math.floor(end) + 1)
                       for frame in (key - .05, key + .05) if start <= frame <= end})
extra = [sample_skin(frame) for frame in probe_frames]
all_rows = rows + extra
epsilon_dt = .05 / fps
seam_start = next(row for row in extra if abs(row['frame'] - (start + .05)) < 1e-7)
seam_end = next(row for row in extra if abs(row['frame'] - (end - .05)) < 1e-7)
foot_report = {}
forward = (rig.matrix_world.to_3x3() @ Vector((0, -1, 0))).normalized()
dt = duration / n
for key, (ankle, toe, limb) in feet.items():
    regular = [r['feet'][key] for r in rows]
    steps = [(b['centroid'] - c['centroid']).length for c, b in zip(regular, regular[1:])]
    max_index = steps.index(max(steps))
    qsteps = [(math.degrees(log_rotation(c['quaternions'][ankle], b['quaternions'][ankle], dt).length) * dt)
              for c, b in zip(rows, rows[1:])]
    qindex = qsteps.index(max(qsteps))
    first, last = regular[0], regular[-1]
    foot_report[key] = {
        'skin_floor_range_m': [min(r['feet'][key]['floor_m'] for r in all_rows), max(r['feet'][key]['floor_m'] for r in all_rows)],
        'maximum_centroid_step_m': max(steps), 'centroid_step_phase_interval': [max_index / n, (max_index + 1) / n],
        'maximum_rotation_step_deg': max(qsteps), 'rotation_step_phase_interval': [qindex / n, (qindex + 1) / n],
        'loop_position_delta_m': (last['centroid'] - first['centroid']).length,
        'loop_velocity_delta_m_s': ((regular[1]['centroid'] - first['centroid']) - (last['centroid'] - regular[-2]['centroid'])).length / dt,
        'loop_one_sided_skin_velocity_delta_m_s': ((seam_start['feet'][key]['centroid'] - first['centroid']) - (last['centroid'] - seam_end['feet'][key]['centroid'])).length / epsilon_dt,
        'loop_one_sided_angular_velocity_delta_deg_s': math.degrees((log_rotation(rows[0]['quaternions'][ankle], seam_start['quaternions'][ankle], epsilon_dt) - log_rotation(seam_end['quaternions'][ankle], rows[-1]['quaternions'][ankle], epsilon_dt)).length),
    }
    begin, finish = spec['contact_phases'][limb]
    supported = []
    for step in range(math.ceil(begin * n + 1), math.floor(finish * n)):
        row = rows[step % n]
        position = row['feet'][key]['sole_centroid'] + forward * spec['speed_m_s'] * duration * step / n
        supported.append((position, row, step / n))
    if supported:
        drift = [(position - supported[0][0]).length for position, _, _ in supported]
        speeds = []
        for before, after in zip(supported, supported[1:]):
            delta = after[0] - before[0]
            delta.z = 0
            speeds.append(delta.length / dt)
        index = speeds.index(max(speeds)) if speeds else 0
        worst = supported[min(index + 1, len(supported) - 1)]
        foot_report[key]['supported_skin'] = {
            'stance_phase': [begin, finish], 'interior_samples': len(supported),
            'nominal_speed_m_s': spec['speed_m_s'], 'fixed_sole_centroid_max_drift_m': max(drift),
            'max_fixed_sole_planar_residual_speed_m_s': max(speeds) if speeds else 0,
            'worst_residual_speed_phase': worst[2], 'worst_phase_skin_floor_m': worst[1]['feet'][key]['floor_m'],
            'worst_phase_chain_bends': {name: worst[1]['bend'][name] for name in chains[key][1:-1]},
            'skin_floor_range_m': [min(r['feet'][key]['floor_m'] for _, r, _ in supported), max(r['feet'][key]['floor_m'] for _, r, _ in supported)],
        }

core_report = {}
for name in cores:
    positions = [r['core'][name] for r in rows]
    velocities = [(b - c) / dt for c, b in zip(positions, positions[1:])]
    acceleration = [(b - c) / dt for c, b in zip(velocities, velocities[1:])]
    vi = max(range(len(velocities)), key=lambda i: velocities[i].length)
    ai = max(range(len(acceleration)), key=lambda i: acceleration[i].length)
    boundary = []
    epsilon = .05
    for key in range(math.ceil(start) + 1, math.floor(end)):
        points = [core_pose(key + offset)[name] for offset in (-epsilon, 0, epsilon)]
        before, after = (points[1] - points[0]) / (epsilon / fps), (points[2] - points[1]) / (epsilon / fps)
        boundary.append({'frame': key, 'phase': (key - start) / (end - start),
                         'velocity_jump_m_s': (after - before).length,
                         'before_velocity_m_s': list(before), 'after_velocity_m_s': list(after)})
    seam_positions = [core_pose(frame)[name] for frame in (start, start + epsilon, end - epsilon, end)]
    seam_before = (seam_positions[3] - seam_positions[2]) / (epsilon / fps)
    seam_after = (seam_positions[1] - seam_positions[0]) / (epsilon / fps)
    core_report[name] = {
        'vertical_range_m': [min(v.z for v in positions), max(v.z for v in positions)],
        'max_speed_m_s': velocities[vi].length, 'max_speed_phase_interval': [vi / n, (vi + 1) / n],
        'max_discrete_acceleration_m_s2': acceleration[ai].length, 'max_acceleration_phase': (ai + 1) / n,
        'loop_position_delta_m': (positions[-1] - positions[0]).length,
        'loop_velocity_delta_m_s': (velocities[0] - velocities[-1]).length,
        'loop_one_sided_velocity_delta_m_s': (seam_after - seam_before).length,
        'largest_key_boundary_velocity_jumps': sorted(boundary, key=lambda r: -r['velocity_jump_m_s'])[:5],
    }

floor = min(r['body_floor_m'] for r in all_rows)
report = {
    'scope': 'New sprint evaluated skin/core kinematics. Prior photo-based pass and previous QA results are not reused as naturalness evidence.',
    'blend_sha256': hashlib.sha256(a.blend.read_bytes()).hexdigest(),
    'manifest_sha256': hashlib.sha256(a.manifest.read_bytes()).hexdigest(),
    'clip': a.clip, 'fps': fps, 'duration_s': duration, 'regular_sample_hz': a.hz,
    'regular_samples': len(rows), 'extra_actual_skin_key_boundary_samples': len(extra), 'total_actual_skin_samples': len(all_rows),
    'foot_region': 'Ankle plus toe influence >=65%, including heel. Fixed sole vertices from the same anatomical region are followed.',
    'unchanged_floor_margin_m': .003, 'whole_body_skin_floor_min_m': floor, 'whole_body_floor_within_margin': floor >= -.003,
    'bends': {name: {'internal_angle_range_deg': [min(r['bend'][name]['internal_angle_deg'] for r in all_rows), max(r['bend'][name]['internal_angle_deg'] for r in all_rows)],
                     'sagittal_sign_range': [min(r['bend'][name]['sagittal_sign'] for r in all_rows), max(r['bend'][name]['sagittal_sign'] for r in all_rows)],
                     'original_rest_sign_matches_all': all(r['bend'][name]['rest_sign_matches'] for r in all_rows)} for name in rest_sign},
    'feet': foot_report, 'core_kinematics': core_report,
    'actual_skin_flight': {'clearance_threshold_m': .005,
                           'regular_phases': [r['phase'] for r in rows[:-1] if all(v['floor_m'] > .005 for v in r['feet'].values())],
                           'max_four_paw_clearance_m': max(min(v['floor_m'] for v in r['feet'].values()) for r in all_rows)},
    'status': 'Read-only numerical review; reference-based actual rendered skin/movie acceptance must be reported separately.',
    'limits': ['Fixed sole centroid residual motion includes rolling and deformation, not a measured pressure centre.',
               'Finite differences include delivered interpolation effects and do not measure impact force.',
               'The unchanged 3 mm floor margin is a penetration bound; other numerical values are reported without silently relaxing acceptance limits.',
               'Uniform 120 Hz plus near-key skin samples do not replace reference visual flow review.'],
}
a.report.parent.mkdir(parents=True, exist_ok=True)
a.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print('SPRINT_INDEPENDENT_SKIN_CORE', a.report)
