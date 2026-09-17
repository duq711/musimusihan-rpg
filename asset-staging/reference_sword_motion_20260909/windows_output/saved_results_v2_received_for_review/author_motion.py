"""Build a separate rigid sword/shield motion draft in background Blender.

No source file is saved. The latest right-hand grip is never deformed. The
left hand is evaluated at its existing pose into new meshes, then moves rigidly.
Eight layered Actions each contain Sword_Control and Shield_Control slots.

First draft (explicitly noncanonical):
  blender --background --factory-startup --disable-autoexec --python-exit-code 1
    --python author_motion.py -- --preview-only --idle-layout video

Production adaptation requires --contract-root with the received documents and
an explicit authoring_adapter.json, documented in load_contract(). Merely
finding a folder does not establish that a schema/pivot contract was applied.
Import this module and call activate_action(name, seconds=...) for rendering.
"""
import argparse
import bisect
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import time

import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

ROOT = Path('C:/Users/duq71/Documents/Codex/2026-09-08/d')
BASE = ROOT / 'outputs/reference_sword_motion_20260909'
NAMES = ('idle', 'run', 'takeoff', 'air', 'land', 'right_diagonal', 'left_reverse', 'overhead')
CONTROLS = {'sword': 'Sword_Control', 'shield': 'Shield_Control'}
CONTRACT_FILES = ('INTEGRATION_PLAN.md', 'motion_manifest.schema.json', 'delivery_requirements.json')

def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def matrix_list(value):
    return [[float(x) for x in row] for row in value]

def vertex_hash(obj):
    return hashlib.sha256(np.asarray([v.co[:] for v in obj.data.vertices], dtype='<f4').tobytes()).hexdigest()

def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    authorization = parser.add_mutually_exclusive_group(required=True)
    authorization.add_argument('--preview-only', action='store_true', help='Explicit permission to author an independent noncanonical draft')
    authorization.add_argument('--contract-root', type=Path)
    parser.add_argument('--geometry', type=Path, default=BASE / 'preparation/authoring_geometry.json')
    parser.add_argument('--keyposes', type=Path, default=BASE / 'preparation/motion_keyposes.json')
    parser.add_argument('--out', type=Path, default=BASE / 'output/iteration_01')
    parser.add_argument('--idle-layout', choices=('source', 'video'), default='source')
    parser.add_argument('--grip-screen', type=float, nargs=2, default=(.8, .96), metavar=('X', 'Y'))
    parser.add_argument('--shield-screen', type=float, nargs=2, default=(.20, .93), metavar=('X', 'Y'))
    parser.add_argument('--sword-depth', type=float, default=.60)
    parser.add_argument('--blade-lean-deg', type=float, default=2.0)
    parser.add_argument('--sample-hz', type=int, default=120)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    if args.sample_hz != 120:
        parser.error('This handoff currently requires 120 Hz samples.')
    if not .10 < args.sword_depth < 2:
        parser.error('Sword depth must be between .10 and 2 metres.')
    args.out = args.out.resolve()
    if not args.out.is_relative_to(BASE.resolve()):
        parser.error('Output must be a new directory below this delivery root.')
    if args.out.exists() and any(args.out.iterdir()):
        parser.error('Output directory is nonempty; select a new iteration path.')
    return args

def load_contract(args):
    """Validate an explicit coordinator-authored mapping, never execute document text.

    authoring_adapter.json schema 1:
      coordinate_system: camera_x_right_y_up_z_back
      contract_sha256: {each CONTRACT_FILES filename: matching SHA256}
      pivots_camera_m: {sword:[x,y,z], shield:[x,y,z]}
      rest_controls: {sword:{position_m:[x,y,z], quaternion_wxyz:[w,x,y,z]}, shield:...}
    This adapter maps the receiving canonical contract into this script's camera
    frame. Its presence is recorded; the final receiving manifest still requires
    external validation against motion_manifest.schema.json.
    """
    if args.preview_only:
        return {'status': 'NONCANONICAL_PREVIEW', 'received_schema_validated': False,
                'reason': 'Explicit --preview-only. Measured local grip anchors; Mac contracts unavailable or unapplied.'}, None
    folder = args.contract_root.resolve()
    paths = [folder / name for name in CONTRACT_FILES + ('authoring_adapter.json',)]
    missing = [str(p) for p in paths if not p.is_file()]
    if missing:
        raise ValueError('Missing explicit contract/adapter files: ' + ', '.join(missing))
    adapter = read_json(folder / 'authoring_adapter.json')
    if adapter.get('schema_version') != 1 or adapter.get('coordinate_system') != 'camera_x_right_y_up_z_back':
        raise ValueError('Unsupported explicit authoring adapter.')
    hashes = {name: digest(folder / name) for name in CONTRACT_FILES}
    if adapter.get('contract_sha256') != hashes:
        raise ValueError('Adapter must reference the exact hashes of all three received contracts.')
    for role in CONTROLS:
        pivot = np.asarray(adapter['pivots_camera_m'][role], dtype=float)
        rest = adapter['rest_controls'][role]
        pos = np.asarray(rest['position_m'], dtype=float)
        quat = np.asarray(rest['quaternion_wxyz'], dtype=float)
        if pivot.shape != (3,) or pos.shape != (3,) or quat.shape != (4,) or not all(np.isfinite(v).all() for v in (pivot,pos,quat)):
            raise ValueError('Adapter contains invalid transform arrays.')
        if abs(float(np.linalg.norm(quat)) - 1) > 1e-5:
            raise ValueError('Adapter quaternion must have unit length.')
    return {'status': 'EXPLICIT_CONTRACT_ADAPTER_APPLIED', 'contract_root': str(folder),
            'contract_sha256': hashes, 'adapter_sha256': digest(folder / 'authoring_adapter.json'),
            'received_schema_validated': False}, adapter

def validate_keys(data):
    clips = data.get('clips', [])
    if tuple(c['name'] for c in clips) != NAMES:
        raise ValueError('Expected exactly the eight ordered, named clips.')
    for clip in clips:
        keys = clip['keyposes']; ts = [float(k['time_s']) for k in keys]
        duration = float(clip['duration_s'])
        if len(keys) < 2 or ts[0] != 0 or abs(ts[-1] - duration) > 1e-8 or duration <= 0:
            raise ValueError('Invalid clip endpoints: ' + clip['name'])
        if any(b <= a for a,b in zip(ts,ts[1:])):
            raise ValueError('Keys must be strictly increasing.')
        for key in keys:
            for role in CONTROLS:
                for field in ('position_delta_m','rotation_delta_xyz_deg'):
                    value = np.asarray(key[role][field], dtype=float)
                    if value.shape != (3,) or not np.isfinite(value).all():
                        raise ValueError('Invalid numeric pose data.')
    return clips

def pchip_slopes(times, values, loop=False):
    """Shape-preserving Hermite slopes: monotone components have no overshoot."""
    h = np.diff(times); d = np.diff(values,axis=0) / h[:,None]
    m = np.zeros_like(values)
    if len(times) == 2:
        m[:] = d[0]; return m
    for k in range(1,len(times)-1):
        same = d[k-1] * d[k] > 0
        w1 = 2*h[k]+h[k-1]; w2 = h[k]+2*h[k-1]
        m[k,same] = (w1+w2)/(w1/d[k-1,same]+w2/d[k,same])
    for i,near,far,h0,h1 in ((0,0,1,h[0],h[1]),(-1,-1,-2,h[-1],h[-2])):
        slope = ((2*h0+h1)*d[near]-h0*d[far])/(h0+h1)
        slope[slope*d[near] <= 0] = 0
        mask = (d[near]*d[far] <= 0) & (np.abs(slope)>3*np.abs(d[near]))
        slope[mask] = 3*d[near,mask]
        m[i] = slope
    if loop:
        # One shared seam derivative makes the periodic Hermite path C1.
        seam = np.zeros(values.shape[1]); same = d[0]*d[-1] > 0
        w1 = 2*h[0]+h[-1]; w2 = h[0]+2*h[-1]
        seam[same] = (w1+w2)/(w1/d[-1,same]+w2/d[0,same])
        m[0] = seam; m[-1] = seam
    return m

def interpolate(times, values, slopes, t):
    i = min(len(times)-2, max(0,bisect.bisect_right(times,t)-1))
    h = times[i+1]-times[i]; u = min(1,max(0,(t-times[i])/h))
    return ((2*u**3-3*u*u+1)*values[i]+(u**3-2*u*u+u)*h*slopes[i]
            +(-2*u**3+3*u*u)*values[i+1]+(u**3-u*u)*h*slopes[i+1])

def reparent_world(obj, parent):
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_world = world

def camera_screen_position(scene, camera, screen, depth):
    aspect = scene.render.resolution_x*scene.render.pixel_aspect_x / (scene.render.resolution_y*scene.render.pixel_aspect_y)
    extent = depth * math.tan(camera.data.angle_y/2)
    return Vector(((2*screen[0]-1)*extent*aspect, (1-2*screen[1])*extent, -depth))

def import_left_static(geometry, scene):
    """Append only selected source objects and evaluate copies, preserving source pose."""
    record = geometry['left_shield_source']; names = set(record['append_object_names'])
    with bpy.data.libraries.load(record['source'], link=False) as (available, target):
        if not names.issubset(set(available.objects)):
            raise ValueError('Original left-side objects changed.')
        target.objects = sorted(names)
    imported = [o for o in target.objects if o is not None]
    for obj in imported:
        if scene.collection.objects.get(obj.name) is None:
            scene.collection.objects.link(obj)
    # Library-appended objects report identity matrix_world until the first
    # dependency-graph update. Reading earlier destroys the source root pose.
    bpy.context.view_layer.update()
    expected_roots = {item['name']:Matrix(item['matrix_world'])
                      for item in record['objects'] if item['parent'] is None}
    for obj in imported:
        if obj.parent is None:
            expected = expected_roots[obj.name]
            error = max(abs(obj.matrix_world[i][j]-expected[i][j]) for i in range(4) for j in range(4))
            if error > 1e-5:
                raise ValueError('Appended source root pose differs from geometry audit: '+obj.name)
    delta = Matrix(record['source_world_to_latest_world'])
    for obj in imported:
        if obj.parent is None:
            obj.matrix_world = delta @ obj.matrix_world
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    meshes = []
    for obj in imported:
        if obj.type != 'MESH' or obj.hide_render:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
        new = bpy.data.objects.new('LeftStatic_' + obj.name.removeprefix('ready__'), mesh)
        scene.collection.objects.link(new); new.matrix_world = evaluated.matrix_world.copy()
        meshes.append(new)
    for obj in imported:
        bpy.data.objects.remove(obj,do_unlink=True)
    if not meshes:
        raise ValueError('No evaluated left hand/shield meshes were imported.')
    return meshes

def make_control(role, pivot, root, scene):
    obj = bpy.data.objects.new(CONTROLS[role],None); scene.collection.objects.link(obj)
    obj.parent = root; obj.rotation_mode = 'QUATERNION'; obj.location = pivot
    obj.empty_display_type = 'ARROWS'; obj.empty_display_size = .06
    obj['track_role'] = role; obj['rest_pivot_camera_m'] = list(pivot)
    bpy.context.view_layer.update()
    return obj

def activate_action(name, seconds=0.0, scene=None):
    """Activate both slots for a saved draft; root can import this helper for previews."""
    scene = scene or bpy.context.scene
    mapping = json.loads(scene['motion_action_control_map'])
    entry = mapping[name]; action = bpy.data.actions[name]
    for control_name, slot_id in entry['slots'].items():
        obj = bpy.data.objects[control_name]; obj.animation_data_create()
        for track in obj.animation_data.nla_tracks:
            track.mute = True
        obj.animation_data.action = action
        obj.animation_data.action_slot = action.slots[slot_id]
    scene.frame_start = 1; scene.frame_end = math.ceil(entry['duration_s']*scene.render.fps)+1
    frame = 1+min(max(float(seconds),0),entry['duration_s'])*scene.render.fps
    scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame))
    bpy.context.view_layer.update()

def build_action(clip, samples, controls, hz):
    action = bpy.data.actions.new(clip['name']); action.use_fake_user = True
    action['duration_s'] = clip['duration_s']; action['loop'] = clip['loop']
    action['sample_rate_hz'] = hz
    layer = action.layers.new('Rigid camera-space controls')
    strip = layer.strips.new(type='KEYFRAME')
    slot_map = {}
    for role,obj in controls.items():
        slot = action.slots.new('OBJECT',obj.name); bag = strip.channelbags.new(slot)
        slot_map[obj.name] = slot.identifier
        for path,field,count in (('location','position_m',3),('rotation_quaternion','quaternion_wxyz',4)):
            for axis in range(count):
                curve = bag.fcurves.new(data_path=path,index=axis)
                points = [(1+s['time_s']*hz,s['tracks'][role][field][axis]) for s in samples]
                curve.keyframe_points.add(len(points)); curve.keyframe_points.foreach_set('co',[v for p in points for v in p])
                for point in curve.keyframe_points:
                    point.interpolation = 'LINEAR'
                curve.update()
        obj.animation_data_create()
        track = obj.animation_data.nla_tracks.new(); track.name = clip['name']; track.mute = True
        nla = track.strips.new(clip['name'],1,action); nla.action_slot = slot
        nla.action_frame_start = 1; nla.action_frame_end = 1+clip['duration_s']*hz
        nla.extrapolation = 'NOTHING'; nla.blend_type = 'REPLACE'; nla.mute = False
    action.use_frame_range = True; action.frame_start = 1; action.frame_end = 1+clip['duration_s']*hz
    return {'duration_s':clip['duration_s'],'loop':clip['loop'],'slots':slot_map}

def inspect_glb(path):
    raw = path.read_bytes(); length,kind = struct.unpack_from('<II',raw,12)
    if raw[:4] != b'glTF' or kind != 0x4e4f534a:
        raise ValueError('Invalid exported GLB.')
    doc = json.loads(raw[20:20+length]); animations = doc.get('animations',[])
    names = [a.get('name') for a in animations]
    if len(names) != 8 or set(names) != set(NAMES):
        raise ValueError('GLB action count/names mismatch: '+repr(names))
    nodes = doc.get('nodes',[]); checks = []
    for anim in animations:
        tracks = {(nodes[c['target']['node']].get('name'),c['target']['path']) for c in anim['channels']}
        required = {(name,path) for name in CONTROLS.values() for path in ('translation','rotation')}
        if not required.issubset(tracks):
            raise ValueError('Missing control channels in '+anim['name']+': '+repr(required-tracks))
        checks.append({'name':anim['name'],'channels':len(anim['channels']),'tracks':[list(t) for t in sorted(tracks)]})
    if doc.get('skins'):
        raise ValueError('Unexpected skin in rigid assembly export.')
    if any('uri' in im for im in doc.get('images',[])):
        raise ValueError('GLB image was not embedded.')
    return {'animation_count':8,'animations':checks,'meshes':len(doc.get('meshes',[])),
            'skins':0,'embedded_images':len(doc.get('images',[])),'sha256':digest(path)}

def close_sampled_loop(samples, rests):
    """Make the actual linear-baked seam symmetric, not only the source spline."""
    if len(samples) < 4:
        return
    dt_start = samples[1]['time_s'] - samples[0]['time_s']
    dt_end = samples[-1]['time_s'] - samples[-2]['time_s']
    if abs(dt_start-dt_end) > 1e-7:
        raise ValueError('Loop duration must contain an integral number of 120Hz steps.')
    for role in CONTROLS:
        first = samples[0]['tracks'][role]
        head = samples[1]['tracks'][role]
        tail = samples[-2]['tracks'][role]
        p0 = Vector(first['position_m'])
        step = ((Vector(head['position_m'])-p0)+(p0-Vector(tail['position_m'])))*.5
        q0 = Quaternion(first['quaternion_wxyz'])
        qhead = Quaternion(head['quaternion_wxyz'])
        qtail = Quaternion(tail['quaternion_wxyz'])
        exponential = (q0.rotation_difference(qhead).to_exponential_map()
                       +qtail.rotation_difference(q0).to_exponential_map())*.5
        qstep = Quaternion(exponential.normalized(), exponential.length) if exponential.length > 1e-10 else Quaternion()
        for target, sign in [(head,1),(tail,-1)]:
            position = p0+step*sign
            quat = (q0 @ (qstep if sign == 1 else qstep.conjugated())).normalized()
            if quat.dot(q0) < 0: quat.negate()
            target['position_m'] = list(position)
            target['quaternion_wxyz'] = list(quat)
            target['matrix_camera'] = matrix_list(Matrix.Translation(position)@quat.to_matrix().to_4x4())
            target['position_delta_m'] = list(position-Vector(rests[role]['position_m']))
            target['rotation_delta_quaternion_wxyz'] = list(quat@Quaternion(rests[role]['quaternion_wxyz']).conjugated())

def main():
    started = time.monotonic(); args = parse_args(); contract,adapter = load_contract(args)
    geometry = read_json(args.geometry); keydoc = read_json(args.keyposes); clips = validate_keys(keydoc)
    source = Path(geometry['latest']['source']); left_source = Path(geometry['left_shield_source']['source'])
    before = {str(p):digest(p) for p in (source,left_source)}
    if before[str(source)] != geometry['latest']['sha256'] or before[str(left_source)] != geometry['left_shield_source']['sha256']:
        raise ValueError('Source hashes differ from the read-only geometry audit.')
    bpy.ops.wm.open_mainfile(filepath=str(source),load_ui=False,use_scripts=False)
    scene = bpy.context.scene; scene.frame_set(1); camera = scene.camera
    camera_world = camera.matrix_world.copy(); camera_inverse = camera_world.inverted()
    right = [bpy.data.objects[n] for n in geometry['latest']['mesh_names']]
    right_hashes = {o.name:vertex_hash(o) for o in right}
    old_parent = bpy.data.objects['SwordHold_Static']
    for obj in right: reparent_world(obj,None)
    bpy.data.objects.remove(old_parent,do_unlink=True)
    left = import_left_static(geometry,scene)
    source_pivots = {'sword':Vector(geometry['latest']['grip_anchor_camera_m'])}
    leftroot = next(o for o in geometry['left_shield_source']['objects'] if o['name']=='ready__LeftHand')
    source_pivots['shield'] = Matrix(leftroot['matrix_camera']).translation
    pivots = {role:Vector(adapter['pivots_camera_m'][role]) if adapter else p for role,p in source_pivots.items()}
    root = bpy.data.objects.new('Motion_CameraSpace',None); scene.collection.objects.link(root)
    root.matrix_world = camera_world; root['coordinate_system'] = 'camera_x_right_y_up_z_back'
    controls = {role:make_control(role,pivot,root,scene) for role,pivot in pivots.items()}
    for obj in right: reparent_world(obj,controls['sword'])
    for obj in left: reparent_world(obj,controls['shield'])
    rests = {role:{'position_m':list(pivot),'quaternion_wxyz':[1,0,0,0]} for role,pivot in pivots.items()}
    if adapter:
        rests = adapter['rest_controls']
    elif args.idle_layout == 'video':
        current_axis = Vector(geometry['latest']['blade_axis_camera_grip_towards_tip'])
        lean = math.radians(args.blade_lean_deg)
        target_axis = Vector((math.sin(lean),math.cos(lean),.10)).normalized()
        rests['sword'] = {'position_m':list(camera_screen_position(scene,camera,args.grip_screen,args.sword_depth)),
                          'quaternion_wxyz':list(current_axis.rotation_difference(target_axis))}
        rests['shield']['position_m'] = list(camera_screen_position(scene,camera,args.shield_screen,abs(pivots['shield'].z)))
    scene.render.fps = args.sample_hz; scene.render.fps_base = 1
    scene.name = 'Reference_Sword_Motion_Draft'
    scene['motion_contract_status'] = contract['status']; scene['motion_author_script'] = str(Path(__file__).resolve())
    scene['motion_geometry_unchanged'] = True; scene['motion_idle_layout'] = args.idle_layout
    output = {'schema_version':'camera_pose_draft_1','contract':contract,'sample_rate_hz':args.sample_hz,
        'coordinate_system':'camera_x_right_y_up_z_back','units':'meters','quaternion_order':'wxyz',
        'matrix_storage':'row_major; local control to fixed camera frame',
        'source_sha256':before,'source_keyposes_sha256':digest(args.keyposes),'source_geometry_sha256':digest(args.geometry),
        'evidence':keydoc.get('evidence',{}),'idle_layout':args.idle_layout,
        'source_idle':{'pivots_camera_m':{r:list(p) for r,p in source_pivots.items()},'blade_axis_camera':geometry['latest']['blade_axis_camera_grip_towards_tip']},
        'tracks':{r:{'control':CONTROLS[r],'pivot_camera_m':list(pivots[r]),'rest':rests[r]} for r in CONTROLS},
        'camera_matrix_world':matrix_list(camera_world),'camera_fov_y_degrees':math.degrees(camera.data.angle_y),
        'clips':[],'limitations':['Rigid parent animation; no new finger or arm deformation.',
            'Left hand uses the existing fingerless glove, right hand uses the latest full glove.',
            'This sampling format is independent of the receiving manifest schema until explicitly adapted and validated.']}
    mapping = {}
    for clip in clips:
        times = np.asarray([k['time_s'] for k in clip['keyposes']],dtype=float)
        curves = {}
        for role in CONTROLS:
            positions = np.asarray([k[role]['position_delta_m'] for k in clip['keyposes']],dtype=float)
            angles = np.unwrap(np.radians([k[role]['rotation_delta_xyz_deg'] for k in clip['keyposes']]),axis=0)
            if clip['loop']:
                q0 = Euler(angles[0],'XYZ').to_quaternion(); q1 = Euler(angles[-1],'XYZ').to_quaternion()
                if np.max(np.abs(positions[0]-positions[-1])) > 1e-7 or abs(q0.dot(q1)) < 1-1e-6:
                    raise ValueError('Loop endpoints must match: '+clip['name']+'/'+role)
            curves[role] = (positions,pchip_slopes(times,positions,clip['loop']),angles,pchip_slopes(times,angles,clip['loop']))
        duration = float(clip['duration_s']); sample_times = list(np.arange(0,duration-1e-10,1/args.sample_hz))+[duration]
        samples = []; previous_quat = {}
        for t in sample_times:
            sample = {'time_s':float(t),'tracks':{}}
            for role in CONTROLS:
                positions,ps,angles,rs = curves[role]
                pdelta = Vector(interpolate(times,positions,ps,t))
                rdelta = Euler(interpolate(times,angles,rs,t),'XYZ').to_quaternion()
                rest = rests[role]; position = Vector(rest['position_m'])+pdelta
                quat = (rdelta@Quaternion(rest['quaternion_wxyz'])).normalized()
                if role in previous_quat and quat.dot(previous_quat[role]) < 0: quat.negate()
                previous_quat[role] = quat.copy()
                transform = Matrix.Translation(position)@quat.to_matrix().to_4x4()
                sample['tracks'][role] = {'position_m':list(position),'quaternion_wxyz':list(quat),
                    'matrix_camera':matrix_list(transform),'position_delta_m':list(pdelta),'rotation_delta_quaternion_wxyz':list(rdelta)}
            samples.append(sample)
        if clip['loop']:
            close_sampled_loop(samples,rests)
        mapping[clip['name']] = build_action(clip,samples,controls,args.sample_hz)
        output['clips'].append({'name':clip['name'],'duration_s':duration,'loop':clip['loop'],
            'source_window_s':clip.get('source_window_s'),'source_events':clip.get('source_events',[]),
            'samples':samples})
    scene['motion_action_control_map'] = json.dumps(mapping)
    scene['motion_rest_controls_json'] = json.dumps(rests)
    if len(bpy.data.actions) != 8 or any(len(a.slots)!=2 for a in bpy.data.actions):
        raise ValueError('Expected eight layered Actions with two slots each.')
    if any(vertex_hash(bpy.data.objects[name])!=value for name,value in right_hashes.items()):
        raise ValueError('Right-hand/sword local geometry changed.')
    if any(o.type=='ARMATURE' or o.modifiers for o in [*right,*left]):
        raise ValueError('Unexpected deformation in exported rigid meshes.')
    for image in bpy.data.images:
        if image.type not in ('RENDER_RESULT','COMPOSITING') and image.source!='VIEWER' and not image.packed_file:
            image.pack()
    args.out.mkdir(parents=True,exist_ok=True)
    samples_path = args.out/'motion_samples_120hz.json'
    samples_path.write_text(json.dumps(output,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root,*controls.values(),*right,*left]: obj.select_set(True)
    bpy.context.view_layer.objects.active = controls['sword']
    # Active Actions must be cleared during export because the same Actions are
    # already stashed on NLA tracks; otherwise glTF can duplicate the idle slot.
    for role,obj in controls.items():
        obj.animation_data.action = None; obj.location = rests[role]['position_m']; obj.rotation_quaternion = rests[role]['quaternion_wxyz']
    scene.frame_start = 1; scene.frame_end = math.ceil(max(c['duration_s'] for c in clips)*args.sample_hz)+1
    bpy.context.view_layer.update()
    glb = args.out/'Reference_Sword_Motion.glb'
    options = dict(filepath=str(glb),export_format='GLB',use_selection=True,use_active_scene=True,
        export_animations=True,export_animation_mode='ACTIONS',export_merge_animation='ACTION',
        export_frame_range=False,export_force_sampling=False,export_optimize_animation_size=False,
        export_anim_slide_to_zero=True,export_skins=False,export_cameras=False,export_lights=False,
        export_extras=True,export_yup=True)
    available = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    unsupported = [k for k in options if k not in available]
    if unsupported: raise ValueError('Required exporter options unsupported: '+repr(unsupported))
    bpy.ops.export_scene.gltf(**options)
    glb_check = inspect_glb(glb)
    activate_action('idle',scene=scene)
    blend = args.out/'Reference_Sword_Motion.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
    after = {path:digest(path) for path in before}
    if before != after: raise ValueError('A source hash changed during authoring.')
    report = {'status':'authored_preview' if args.preview_only else 'authored_with_explicit_adapter',
        'contract':contract,'blender_version':bpy.app.version_string,'elapsed_seconds':round(time.monotonic()-started,3),
        'source_hashes_unchanged':True,'right_geometry_hashes_unchanged':True,
        'actions':mapping,'glb':glb_check,'outputs':{'blend':str(blend),'glb':str(glb),'samples':str(samples_path)},
        'independent_reopen_and_render_validation':'pending coordinator checks'}
    (args.out/'authoring_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    (args.out/'README.md').write_text(
        '# Rigid first-person sword motion draft\n\n'+contract['status']+'\n\n'
        'Eight Blender Actions each contain Sword_Control and Shield_Control slots. '
        'The camera is fixed; all finger/hand shapes remain in their source grip. '
        'The left hand comes from the earlier game reference and still uses a fingerless glove.\n\n'
        'Use author_motion.activate_action(name, seconds) after loading this blend to activate both slots. '
        'The saved scene custom property motion_action_control_map records slot identifiers. '
        'NLA tracks are muted for preview, with idle assigned actively; this is intentional.\n\n'
        'motion_samples_120hz.json is a named camera-space draft format, not an assertion of Mac manifest-schema compliance. '
        'Original idle pivots and selected draft rest controls are recorded separately. '
        'Reopen, render and Godot integration checks are pending the coordinating task.\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=True),flush=True)

if __name__ == '__main__':
    main()
