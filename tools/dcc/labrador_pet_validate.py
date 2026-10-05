"""Measure the final standing Labrador and round-trip its delivered FBX clips.

This is read-only QA: evaluated skin, supported paws, loop positions/tangents,
the audited skin repairs and source preservation are checked on actual files.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import SOURCE_SHA, channels, pad_indices, set_action

GEOMETRY_SHA = '95268ac6bb56cb6f9e8ae6ddc8764f32ea248f7bba98e984f904fff743e32344'
PAWS = ('FF.L_46', 'FF.R_50', 'FFB.L_44', 'FFB.R_48')


def pose(rig, frame):
    integer = math.floor(frame)
    bpy.context.scene.frame_set(integer, subframe=frame-integer)
    bpy.context.view_layer.update()
    return {b.name: rig.matrix_world @ b.matrix for b in rig.pose.bones}


def coordinates(mesh):
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    values = np.empty(len(data.vertices)*3, dtype=np.float32)
    data.vertices.foreach_get('co', values)
    values = values.reshape(-1, 3)
    matrix = np.asarray(evaluated.matrix_world, dtype=float)
    world = values @ matrix[:3, :3].T + matrix[:3, 3]
    evaluated.to_mesh_clear()
    return world


def rotation_vector(a, b):
    value = a.to_quaternion().inverted() @ b.to_quaternion()
    if value.w < 0: value.negate()
    axis, angle = value.to_axis_angle()
    return axis*angle


def validate(base):
    manifest = json.loads((base/'export/animation-manifest.json').read_text())
    report = {'passed': False, 'checks': [], 'clips': [], 'fbx_roundtrips': []}
    failures = []
    def check(name, condition, details=None):
        report['checks'].append({'name': name, 'passed': bool(condition), 'details': details})
        if not condition: failures.append(name)

    source_sha = hashlib.sha256((base/'source/LabradorDog_kenchoo_2k.glb').read_bytes()).hexdigest()
    check('Original GLB exact SHA256 preserved', source_sha == SOURCE_SHA, source_sha)
    check('Final bundle has exactly two standing clips', [c['name'] for c in manifest['clips']] == ['IdleFriendly', 'PetEnjoy'])
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Animations.blend'))
    rig = bpy.data.objects['LabradorPet']; mesh = bpy.data.objects['LabradorPet_Mesh']
    geometry = b''.join(struct.pack('<3f', *v.co) for v in mesh.data.vertices)
    geometry_sha = hashlib.sha256(geometry).hexdigest()
    check('Original body geometry exact SHA256 preserved', geometry_sha == GEOMETRY_SHA, geometry_sha)
    check('Actual body mesh and 53-joint rig preserved', len(mesh.data.vertices) == 26103 and len(rig.pose.bones) == 53)
    check('Original eyelid morph preserved and runtime-controlled',
          'target_1' in mesh.data.shape_keys.key_blocks and not mesh.data.shape_keys.animation_data)
    repaired = 0; bad_repairs = []
    for repair in manifest['weight_repairs']:
        source_index = mesh.vertex_groups[repair['from']].index
        target_index = mesh.vertex_groups[repair['to']].index
        for index in repair['indices']:
            weights = {g.group: g.weight for g in mesh.data.vertices[index].groups}
            if weights.get(source_index, 0) > 1e-6 or weights.get(target_index, 0) < .999 or abs(sum(weights.values())-1) > 1e-5:
                bad_repairs.append(index)
            repaired += 1
    check('Only audited 796 claw/tooth vertices transferred', repaired == 796 and not bad_repairs,
          {'vertices': repaired, 'bad_vertices': bad_repairs})
    mask = mesh.data.color_attributes['PetCoatMask']
    eyes = json.loads((base/'qa/head-interaction-audit.json').read_text())['eye_fur_exclusion_vertex_indices']
    check('Coat mask preserves all 806 audited eye vertices', all(mask.data[i].color[0] == 0 for i in eyes),
          {'eye_vertices': len(eyes), 'coat_vertices': sum(v.color[0] > 1e-6 for v in mask.data)})
    set_action(rig, bpy.data.actions['IdleFriendly']); pose(rig, 1)
    socket = bpy.data.objects['MouthSocket']
    scale = list(socket.matrix_world.to_scale())
    check('MouthSocket is Head_1 child with metre attachment scale', socket.parent_bone == 'Head_1' and max(abs(s-1) for s in scale) < 1e-4,
          {'world_scale': scale, 'local_scale': list(socket.scale)})
    check('PetEnjoy shape keys neutral for runtime overlay', max(abs(k.value) for k in mesh.data.shape_keys.key_blocks) == 0)
    pads = {name: np.asarray(pad_indices(mesh, name), dtype=int) for name in PAWS}
    samples = {}
    frame_checks = 0
    for clip in manifest['clips']:
        action = bpy.data.actions[clip['name']]; set_action(rig, action)
        finite = all(math.isfinite(float(v)) for c in channels(action) for k in c.keyframe_points for v in k.co)
        check(clip['name']+' finite keyframes', finite)
        end = clip['frames'][1]
        ends = [pose(rig, f) for f in (1, 1.01, end-.01, end)]
        seam_position = seam_rotation = seam_velocity = seam_angular = 0
        for name in ends[0]:
            matrices = [p[name] for p in ends]
            seam_position = max(seam_position, (matrices[0].translation-matrices[3].translation).length)
            seam_rotation = max(seam_rotation, rotation_vector(matrices[0], matrices[3]).length)
            v0 = (matrices[1].translation-matrices[0].translation)*3000
            vn = (matrices[3].translation-matrices[2].translation)*3000
            seam_velocity = max(seam_velocity, (v0-vn).length)
            w0 = rotation_vector(matrices[0], matrices[1])*3000
            wn = rotation_vector(matrices[2], matrices[3])*3000
            seam_angular = max(seam_angular, (w0-wn).length)
        check(clip['name']+' loop pose continuity', seam_position < .001 and seam_rotation < math.radians(1),
              {'position_m': seam_position, 'rotation_degrees': math.degrees(seam_rotation)})
        check(clip['name']+' loop tangent continuity', seam_velocity < .05 and seam_angular < math.radians(30),
              {'position_velocity_difference_m_per_s': seam_velocity, 'angular_velocity_difference_degrees_per_s': math.degrees(seam_angular)})
        lowest = float('inf'); paw_min = {name: float('inf') for name in PAWS}
        paw_max = {name: -float('inf') for name in PAWS}
        minimum = np.full(3, float('inf')); maximum = -minimum
        reference_paws = None; paw_drift = 0
        choose = {1, round((end+1)/2), end}
        for frame in range(1, end+1):
            matrices = pose(rig, frame); world = coordinates(mesh); frame_checks += 1
            if not np.isfinite(world).all(): failures.append(clip['name']+' nonfinite evaluated skin'); break
            lowest = min(lowest, float(world[:,2].min()))
            minimum = np.minimum(minimum, world.min(axis=0)); maximum = np.maximum(maximum, world.max(axis=0))
            centroids = {}
            for name, indices in pads.items():
                points = world[indices]
                value = float(points[:,2].min()); paw_min[name] = min(paw_min[name], value); paw_max[name] = max(paw_max[name], value)
                centroids[name] = points.mean(axis=0)
            if reference_paws is None: reference_paws = centroids
            paw_drift = max(paw_drift, max(float(np.linalg.norm(centroids[name]-reference_paws[name])) for name in PAWS))
            if frame in choose:
                samples[(clip['name'],frame)] = {'bone_heads': {name: m.translation.copy() for name,m in matrices.items()},
                                               'skin': world.copy()}
        check(clip['name']+' complete evaluated skin stays above floor', lowest > -.002, {'lowest_m': lowest, 'frames': end})
        check(clip['name']+' four paws retain floor support', min(paw_min.values()) > -.002 and max(paw_max.values()) < .006,
              {'pad_minima_m': paw_min, 'pad_maxima_m': paw_max, 'max_paw_centroid_drift_m': paw_drift})
        if clip['name'] == 'PetEnjoy':
            check('PetEnjoy original standing paw positions retained', paw_drift < .002, {'maximum_paw_drift_m': paw_drift})
        report['clips'].append({'name': clip['name'], 'frames_checked': end, 'body_bounds_min_m': minimum.tolist(),
                                'body_bounds_max_m': maximum.tolist(), 'lowest_skin_m': lowest,
                                'paw_minima_m': paw_min, 'maximum_paw_drift_m': paw_drift})
    report['evaluated_skin_frames'] = frame_checks
    # FBX importer rebuilds bone rolls. Compare physical joint origins and
    # deformed skin instead of assuming the reconstructed rest axes are equal.
    for clip in manifest['clips']:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        # FBX stores seconds; use the manifest fps and disable the importer's
        # default additional one-frame offset for a true round-trip comparison.
        bpy.context.scene.render.fps = manifest['fps']
        bpy.ops.import_scene.fbx(filepath=str(base/'export/Animations'/f"{clip['name']}.fbx"), anim_offset=0)
        actual_rig = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
        actual_mesh = next(o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.vertices) == 26103)
        largest_position = largest_skin = 0; tested = 0
        for (name, frame), expected in samples.items():
            if name != clip['name']: continue
            matrices = pose(actual_rig, frame)
            largest_position = max(largest_position, max((matrices[b].translation-p).length for b,p in expected['bone_heads'].items()))
            world = coordinates(actual_mesh)
            largest_skin = max(largest_skin, float(np.linalg.norm(world-expected['skin'],axis=1).max()))
            tested += 1
        sockets = [o for o in bpy.context.scene.objects if o.name == 'MouthSocket']
        socket_scale = list(sockets[0].matrix_world.to_scale()) if sockets else None
        check(clip['name']+' delivered FBX preserves sampled joints/skin', largest_position < .001 and largest_skin < .001,
              {'joint_error_m': largest_position, 'skin_error_m': largest_skin, 'sample_frames': tested})
        check(clip['name']+' delivered FBX socket scale is one', socket_scale is not None and max(abs(s-1) for s in socket_scale) < 1e-4,
              {'world_scale': socket_scale})
        report['fbx_roundtrips'].append({'name': clip['name'], 'frames': tested, 'max_joint_error_m': largest_position,
                                         'max_skin_error_m': largest_skin, 'socket_world_scale': socket_scale})
    report['checks_count'] = len(report['checks']); report['failures'] = failures; report['passed'] = not failures
    (base/'animation-validation.json').write_text(json.dumps(report, indent=2)+'\n')
    print('LABRADOR_VALIDATION', report['passed'], report['checks_count'], frame_checks, failures, flush=True)
    if failures: raise RuntimeError('Labrador validation failed: '+', '.join(failures))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--base', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:]); validate(args.base.resolve())
