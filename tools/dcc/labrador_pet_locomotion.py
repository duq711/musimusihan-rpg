"""Retarget captured canine walk/gallop to the preserved Labrador on Mac Blender.

The authoring copy keeps the acquired rest mesh, audited weights, eye morphs and
coat mask. Captured spine/head and four separate paw paths drive a length-
preserving limb fit; scalar strides are fitted to this long-bodied Labrador.
There are no procedural single-bone pendulum legs and no stretched bones.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from labrador_pet import (LIMBS, MAPPING, MODEL_SCALE, SOURCE_SHA, aim,
                         basis_snapshot, channels, fabrik, key_pose, loop_close,
                         pad_indices, restore_basis, set_action, update)
from labrador_pet_bvh import read_bvh
from labrador_pet_retarget import set_world_pose

FPS = 60
SPECS = [
    dict(name='Walk', file='dog_quad_walk_002.bvh', start=14132, end=14224,
         intervals=46, planar_factor=.62, vertical_factor=1.0,
         body_lower_m=.040, rotation_weight=.65),
    dict(name='Run', file='dog_fast_run_02_006.bvh', start=2944, end=2992,
         intervals=24, planar_factor=.52, vertical_factor=.80,
         body_lower_m=.055, rotation_weight=.75),
]
CONTACTS = {
    'Walk':{'front.L':(0.0,.55),'front.R':(.50,1.0),'hind.L':(.826,1.337),'hind.R':(.315,.880)},
    'Run':{'front.L':(.333,.563),'front.R':(.604,.854),'hind.L':(.917,1.188),'hind.R':(.083,.354)},
}


def basis(capture, frame):
    raw=capture.world_pose(frame);hips=raw['b_Hips'].translation
    f=raw['b_Spine3'].translation-hips;f.y=0;f.normalize()
    up=Vector((0,1,0));right=up.cross(f).normalized()
    return Matrix((right,-f,up)).to_4x4()


def normalized(capture, frame, coordinate):
    raw=capture.world_pose(frame);hips=raw['b_Hips'].translation
    origin=Vector((hips.x,0,hips.z));result={}
    for name,m in raw.items():
        value=coordinate @ m
        value.translation=coordinate.to_3x3() @ (m.translation-origin)
        result[name]=value
    return result


def closed_samples(capture,spec):
    count=spec['intervals'];coordinate=basis(capture,(spec['start']+spec['end'])/2)
    poses=[normalized(capture,spec['start']+(spec['end']-spec['start'])*i/count,coordinate)
           for i in range(count+1)]
    # Remove tiny heading/pose loop drift over the whole captured cycle. A
    # smooth polynomial prevents the correction from introducing a velocity
    # jump at the loop boundary. Final basis closure is checked after skinning.
    for name in poses[0]:
        q0=poses[0][name].to_quaternion();q1=poses[-1][name].to_quaternion();q1.make_compatible(q0)
        drift_q=q1 @ q0.inverted();drift_p=poses[-1][name].translation-poses[0][name].translation
        for i,p in enumerate(poses):
            t=i/count;s=t*t*(3-2*t)
            q=Quaternion((1,0,0,0)).slerp(drift_q.inverted(),s) @ p[name].to_quaternion()
            p[name]=Matrix.LocRotScale(p[name].translation-drift_p*s,q,Vector((1,1,1)))
    return poses,coordinate


def evaluated_floor(mesh,indices):
    update();o=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=o.to_mesh()
    value=min((o.matrix_world @ data.vertices[i].co).z for i in indices)
    o.to_mesh_clear();return value


def solve_limb(rig,limb,neutral,goal,paw_q,source_pole=None,swing=0):
    ankle=rig.pose.bones[limb['ankle']];paw=rig.pose.bones[limb['paw']]
    bones=[rig.pose.bones[n] for n in limb['chain']]
    refs={b.name:b.matrix.copy() for b in bones}
    points=[b.matrix.translation.copy() for b in bones]
    # This model uses independent root-parented wrist/paw controls, not a
    # terminal child of the lower-leg bone. Fit the anatomical endpoint anyway.
    rest_end=neutral[ankle.name].translation-neutral[bones[-1].name].translation
    dq=refs[bones[-1].name].to_quaternion() @ neutral[bones[-1].name].to_quaternion().inverted()
    points.append(points[-1]+dq @ rest_end)
    lengths=[(points[i+1]-points[i]).length for i in range(len(bones))]
    def two(a,goal,l1,l2,pole_sign):
        v=goal-a;d=v.length;axis=v.normalized()
        # Avoid the straight/folded singularities: acquired Labrador elbow and
        # stifle retain explicit anatomical pole directions in sagittal space.
        minimum=math.sqrt(l1*l1+l2*l2-2*l1*l2*math.cos(math.radians(30)))
        maximum=math.sqrt(l1*l1+l2*l2-2*l1*l2*math.cos(math.radians(155)))
        reachable=min(max(d,minimum),maximum)
        pole=Vector((0,pole_sign,0));pole-=axis*pole.dot(axis);pole.normalize()
        along=(l1*l1-l2*l2+reachable*reachable)/(2*reachable)
        knee=a+axis*along+pole*math.sqrt(max(0,l1*l1-along*along))
        return [a,knee,a+axis*reachable],(a+axis*reachable-goal).length
    if len(bones)==2:
        solved,error=two(points[0],goal,*lengths,1)
    else:
        # The hind hock is an anatomical metatarsal, not a free FABRIK hinge.
        # Retain its acquired 28-degree forward/down vector and exact length,
        # then fit the femur/tibia with the stifle always toward the muzzle.
        angle=math.radians(28+27*swing)
        meta=Vector((0,-math.sin(angle),-math.cos(angle)))*lengths[2]
        hock=goal-meta
        upper,error=two(points[0],hock,lengths[0],lengths[1],-1)
        solved=[upper[0],upper[1],upper[2],upper[2]+meta]
    for i,bone in enumerate(bones):
        set_world_pose(bone,aim(refs[bone.name],points[i+1]-points[i],solved[i+1]-solved[i],solved[i]))
    a=Matrix.LocRotScale(goal,paw_q,neutral[ankle.name].to_scale());set_world_pose(ankle,a)
    # Toe keeps its acquired offset and measured wrist rotation. No long paw
    # translations or arbitrary paw flattening are baked into the skin.
    return error*MODEL_SCALE


def foot_path(spec,key,t,neutral,source,source_means,height_factor,speed):
    """Cyclic C1 stance/swing path with the recorded four-foot contact timing.

    Stance velocity exactly compensates the declared forward travel. Recorded
    contact timing drives a bounded swing arc fitted to the source clearance
    range and this Labrador's proportions; Hermite return has the same
    touchdown/liftoff velocity and therefore no seam tug of a planted paw.
    """
    start,end=CONTACTS[spec['name']][key];stance=end-start
    phase=(t-start)%1;duration=spec['intervals']/FPS
    travel=speed*duration/MODEL_SCALE
    goal=neutral.copy();goal.y-=travel*stance*.5
    if phase<=stance:
        goal.y+=travel*phase
        return goal,0.0,0.0,True
    swing=1-stance;u=(phase-stance)/swing
    h00=2*u**3-3*u**2+1;h10=u**3-2*u**2+u
    h01=-2*u**3+3*u**2;h11=u**3-u**2
    ahead=goal.y;behind=ahead+travel*stance
    goal.y=h00*behind+h10*travel*swing+h01*ahead+h11*travel*swing
    envelope=math.sin(math.pi*u)**2
    # Clearance limits use the measured canine lift range, fitted to the
    # target's short forelimbs. The original source is preserved unchanged.
    clearance=(.052 if key.startswith('front') else .055) if spec['name']=='Walk' else .075
    goal.x+=max(-.020,min(.020,(source.x-source_means.x)*height_factor*.30))*envelope
    return goal,clearance*envelope,envelope,False


def export_bundle(base,manifest,neutral_basis):
    scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    directory=base/'export/Locomotion';directory.mkdir(parents=True,exist_ok=True)
    selected=[rig,*rig.children_recursive]
    for o in scene.objects:o.select_set(False)
    for o in selected:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    flags=dict(use_selection=True,object_types={'ARMATURE','MESH','EMPTY'},add_leaf_bones=False,
               axis_forward='-Z',axis_up='Y',apply_scale_options='FBX_SCALE_UNITS',
               use_armature_deform_only=False,bake_anim_use_all_actions=False,
               bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,
               path_mode='RELATIVE',colors_type='LINEAR')
    for clip in manifest['clips']:
        set_action(rig,bpy.data.actions[clip['name']]);scene.frame_start=1;scene.frame_end=clip['frames'][1]
        scene.frame_set(1)
        bpy.ops.export_scene.fbx(filepath=str(directory/(clip['name']+'.fbx')),bake_anim=True,
                                bake_anim_force_startend_keying=True,bake_anim_step=1,**flags)
    care=json.loads((base/'export/animation-manifest.json').read_text())['clips']
    # Care actions were authored at 30 fps. Their timing must remain exact in a
    # combined 60 fps bundle; duplicate the action and scale keys only here.
    combined=[];temps=[]
    for clip in care:
        action=bpy.data.actions[clip['name']].copy();action.name='Bundle_'+clip['name'];temps.append(action)
        for curve in channels(action):
            for k in curve.keyframe_points:
                k.co.x=1+(k.co.x-1)*2;k.handle_left.x=1+(k.handle_left.x-1)*2;k.handle_right.x=1+(k.handle_right.x-1)*2
        combined.append((clip['name'],action,1+2*(clip['frames'][1]-1),clip['duration']))
    combined.extend((c['name'],bpy.data.actions[c['name']],c['frames'][1],c['duration']) for c in manifest['clips'])
    set_action(rig,None);restore_basis(rig,neutral_basis)
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    for name,action,end,duration in combined:
        track=rig.animation_data.nla_tracks.new();track.name=name
        strip=track.strips.new(name,1,action);strip.action_slot=action.slots[0]
        strip.frame_end=end;strip.extrapolation='NOTHING';strip.blend_type='REPLACE';track.mute=True
    if mesh.data.shape_keys:
        mesh.data.shape_keys.animation_data_clear()
        for key in mesh.data.shape_keys.key_blocks:key.value=0
    scene.frame_start=1;scene.frame_end=max(x[2] for x in combined);scene.frame_set(1)
    output=base/'export/LabradorPet_Locomotion.glb'
    bpy.ops.export_scene.gltf(filepath=str(output),export_format='GLB',use_selection=True,
                             export_animations=True,export_animation_mode='NLA_TRACKS',
                             export_anim_slide_to_zero=True,export_force_sampling=True,
                             export_frame_step=1,export_morph=True,export_morph_animation=False,
                             export_vertex_color='ACTIVE',export_all_vertex_colors=False,
                             export_yup=True,export_image_format='AUTO',export_cameras=False,
                             export_lights=False,export_extras=True)
    binary=output.read_bytes();length,kind=struct.unpack_from('<II',binary,12)
    assert kind==0x4e4f534a;data=json.loads(binary[20:20+length]);timings={}
    assert sorted(a['name'] for a in data['animations'])==sorted(x[0] for x in combined)
    for a in data['animations']:
        ins=[data['accessors'][s['input']] for s in a['samplers']]
        start=min(v['min'][0] for v in ins);end=max(v['max'][0] for v in ins)
        expected=next(x[3] for x in combined if x[0]==a['name'])
        assert abs(start)<1e-6 and abs(end-expected)<1e-5,(a['name'],start,end,expected)
        timings[a['name']]={'start_seconds':start,'duration_seconds':end}
    morphs=[n for m in data['meshes'] for n in m.get('extras',{}).get('targetNames',[])]
    assert 'target_1' in morphs and sum('COLOR_0' in p['attributes'] for m in data['meshes'] for p in m['primitives'])>0
    receipt={'pass':True,'file':str(output.relative_to(base)),'bytes':len(binary),
             'sha256':hashlib.sha256(binary).hexdigest(),'clip_timings':timings,
             'morph_targets':morphs,'coat_mask_preserved':True,'care_clips_timing_preserved':True}
    (base/'locomotion-gltf-summary.json').write_text(json.dumps(receipt,indent=2)+'\n')
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    for a in temps:bpy.data.actions.remove(a)


def author(base):
    original=base/'source/LabradorDog_kenchoo_2k.glb'
    assert hashlib.sha256(original.read_bytes()).hexdigest()==SOURCE_SHA
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Animations.blend'))
    scene=bpy.context.scene;scene.render.fps=FPS
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1);update()
    neutral_basis=basis_snapshot(rig);neutral={b.name:b.matrix.copy() for b in rig.pose.bones}
    set_action(rig,None)
    pad={k:pad_indices(mesh,v['paw']) for k,v in LIMBS.items()}
    idle=read_bvh(base/'source/raw_bvh_data/dog_idle_002.bvh');idlecoord=basis(idle,8)
    neutral_source=normalized(idle,8,idlecoord)
    # Uniform height scale transfers vertical body motion. Independent stride
    # calibration affects paw travel only, keeping actual bone lengths intact.
    height_factor=neutral['Back_38'].translation.z/neutral_source['b_Hips'].translation.z
    authored=[];frame_receipts=[]
    for spec in SPECS:
        capture=read_bvh(base/'source/raw_bvh_data'/spec['file']);poses,coordinate=closed_samples(capture,spec)
        action=bpy.data.actions.new(spec['name']);action.use_fake_user=True
        source_means={k:sum((p[v['source_ankle']].translation-p['b_Hips'].translation for p in poses[:-1]),Vector())/spec['intervals'] for k,v in LIMBS.items()}
        hip_mean=sum(p['b_Hips'].translation.z for p in poses[:-1])/spec['intervals']
        source_floors={k:min(p[v['source_paw']].translation.z for p in poses) for k,v in LIMBS.items()}
        start_raw=capture.world_pose(spec['start'])['b_Hips'].translation
        end_raw=capture.world_pose(spec['end'])['b_Hips'].translation
        travel=end_raw-start_raw;travel.y=0
        speed=travel.length/(spec['intervals']/FPS)*height_factor*spec['planar_factor']*MODEL_SCALE
        for i,source in enumerate(poses):
            set_action(rig,None);scene.frame_set(i+1);restore_basis(rig,neutral_basis)
            root=rig.pose.bones['Body_43'];m=neutral[root.name].copy()
            m.translation.z+=(source['b_Hips'].translation.z-hip_mean)*height_factor*spec['vertical_factor']-spec['body_lower_m']/MODEL_SCALE
            set_world_pose(root,m)
            for name in sorted(MAPPING,key=lambda n:len(rig.pose.bones[n].parent_recursive)):
                if name.startswith(('FrontUpper','FrontLower','BackLeg','BackUpper','BackLower','Tail')):continue
                bone=rig.pose.bones[name];sn=MAPPING[name]
                dq=source[sn].to_quaternion() @ neutral_source[sn].to_quaternion().inverted()
                weight=spec['rotation_weight']
                if name.startswith(('Neck','Head')):weight=.55
                dq=Quaternion((1,0,0,0)).slerp(dq,weight)
                desired=Matrix.LocRotScale(bone.matrix.translation,dq @ neutral[name].to_quaternion(),neutral[name].to_scale())
                set_world_pose(bone,desired)
            current={b.name:b.matrix.copy() for b in rig.pose.bones};feet={}
            for key,limb in LIMBS.items():
                name=limb['ankle'];ankle=rig.pose.bones[name];paw=rig.pose.bones[limb['paw']]
                raw_relative=source[limb['source_ankle']].translation-source['b_Hips'].translation
                goal,clearance,envelope,stance=foot_path(spec,key,i/spec['intervals'],neutral[name].translation,
                                                        raw_relative,source_means[key],height_factor,speed)
                # Preserve captured foot lifting and relative ankle/toe arc;
                # actual evaluated skin is corrected to the floor below.
                lift=max(0,source[limb['source_paw']].translation.z-source_floors[key])
                goal.z+=clearance/MODEL_SCALE
                dq=source[limb['source_ankle']].to_quaternion() @ neutral_source[limb['source_ankle']].to_quaternion().inverted()
                dq=Quaternion((1,0,0,0)).slerp(dq,(.32 if spec['name']=='Walk' else .42)*envelope)
                paw_q=dq @ neutral[name].to_quaternion()
                set_world_pose(ankle,Matrix.LocRotScale(goal,paw_q,neutral[name].to_scale()))
                # Toe rotation relative wrist kept at original rest; animated
                # wrist delivers the captured push-off/tuck without shear.
                target_floor=.00015+clearance
                floor=evaluated_floor(mesh,pad[key]);goal.z+=(target_floor-floor)/MODEL_SCALE
                error=solve_limb(rig,limb,neutral,goal,paw_q,swing=envelope)
                # Upper/lower-leg blending influences a few sole vertices.
                # Re-evaluate after the anatomical fit, then converge the
                # independent wrist position while refitting unchanged limbs.
                for correction in range(2):
                    floor=evaluated_floor(mesh,pad[key]);goal.z+=(target_floor-floor)/MODEL_SCALE
                    error=max(error,solve_limb(rig,limb,neutral,goal,paw_q,swing=envelope))
                feet[key]={'floor_m':evaluated_floor(mesh,pad[key]),'target_floor_m':target_floor,
                           'reach_residual_m':error,'source_lift_cm':lift,'ankle_m':list(rig.matrix_world @ goal),'stance':stance}
            t=i/spec['intervals']
            # Inertial, low-amplitude secondary motion follows the acquired
            # floppy ears and tail; body cadence is measured, not invented.
            for side in ('L','R'):
                for j in range(1,5):
                    bone=next(b for b in rig.pose.bones if b.name.startswith(f'Ear{j}.{side}_'))
                    amp=(.7 if spec['name']=='Walk' else 2.3)*j/4
                    bone.rotation_quaternion=bone.rotation_quaternion @ Quaternion((1,0,0),math.radians(amp*math.sin(2*math.pi*t-j*.34)))
            for j,name in enumerate(('Tail1_37','Tail2_36','Tail3_35','Tail4_34','Tail5_33','Tail6_32')):
                bone=rig.pose.bones[name]
                bone.rotation_quaternion=bone.rotation_quaternion @ Quaternion((0,0,1),math.radians((1.0 if spec['name']=='Walk' else 1.8)*math.sin(2*math.pi*t-j*.25)))
            update();key_pose(rig,action,i+1)
            frame_receipts.append({'clip':spec['name'],'frame':i+1,'feet':feet})
        loop_close(rig,action,spec['intervals']+1)
        for curve in channels(action):
            for k in curve.keyframe_points:k.interpolation='LINEAR'
        authored.append({'name':spec['name'],'frames':[1,spec['intervals']+1],
                         'duration':spec['intervals']/FPS,'loop':True,'speed_m_s':speed,
                         'root_motion':'in-place; measured vertical motion only',
                         'source_capture':'source/raw_bvh_data/'+spec['file'],
                         'source_raw_frames':[spec['start'],spec['end']],
                         'source_fps':capture.fps,'stride_factor':spec['planar_factor'],
                         'source_height_scale_m_per_cm':height_factor*MODEL_SCALE,
                         'body_lower_m':spec['body_lower_m'],
                         'contact_phases':{k:list(v) for k,v in CONTACTS[spec['name']].items()},
                         'gait':'captured four-beat walk' if spec['name']=='Walk' else 'captured fast canine gallop',
                         'source':'Captured canine body and four-footfall timing; anatomically fitted C1 planted/swing paw paths and length-preserving IK; authored ear/tail follow-through'})
        print('LABRADOR_LOCOMOTION_AUTHORED',spec['name'],speed,flush=True)
    manifest={'fps':FPS,'rigRoot':'LabradorPet','modelScale':MODEL_SCALE,
              'forward':'Same prior model: Blender -Y, FBX -Z forward/Y up, Unity +Z forward/Y up',
              'source_sha256':SOURCE_SHA,'clips':authored,
              'scope':'Walk and Run added; original two care clips and acquired rest mesh unchanged.',
              'root_motion_policy':'Root joint and armature stay fixed. Body vertical cadence/spine motion preserved.',
              'contact_policy':'Captured contact timing; authored C1 planted/swing paw paths, evaluated-skin floor correction; unchanged limb segment lengths.'}
    (base/'locomotion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (base/'export/locomotion-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    qa=base/'validation/locomotion';qa.mkdir(parents=True,exist_ok=True)
    (qa/'authoring-contact.json').write_text(json.dumps({'frames':frame_receipts},indent=2)+'\n')
    set_action(rig,bpy.data.actions['Walk']);scene.frame_set(1);scene.frame_start=1;scene.frame_end=47
    bpy.ops.wm.save_as_mainfile(filepath=str(base/'production/LabradorPet_Locomotion.blend'))
    export_bundle(base,manifest,neutral_basis)
    assert hashlib.sha256(original.read_bytes()).hexdigest()==SOURCE_SHA
    print('LABRADOR_LOCOMOTION_EXPORTED',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);author(args.base.resolve())
