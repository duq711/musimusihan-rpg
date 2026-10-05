"""Recover the captured canine gallop silhouette on the preserved Labrador.

Run-only revision: preserves the previous production, rest mesh/weights/morphs,
care actions and Walk keys. Full captured paw paths replace the earlier shared
sin-squared return arc. Anatomical IK fits the model's unusually short humerus
and long tibia; scapular glide and measured spinal/pelvis movement participate.
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
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import (LIMBS,MAPPING,MODEL_SCALE,SOURCE_SHA,aim,basis_snapshot,
                         channels,key_pose,loop_close,pad_indices,restore_basis,set_action,update)
from labrador_pet_bvh import read_bvh
from labrador_pet_locomotion import basis,closed_samples,normalized,evaluated_floor
from labrador_pet_retarget import set_world_pose
from labrador_pet_preview import stage

FPS=60
INTERVALS=30
WORLD_FACTOR=.85
SPEC=dict(name='Run',file='dog_fast_run_02_006.bvh',start=2944,end=2992,intervals=INTERVALS)
CONTACTS={'front.L':(.333,.563),'front.R':(.604,.854),'hind.L':(.917,1.188),'hind.R':(.083,.354)}


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def action_hash(action):
    values=[(c.data_path,c.array_index,[list(k.co) for k in c.keyframe_points]) for c in channels(action)]
    return hashlib.sha256(json.dumps(values,separators=(',',':')).encode()).hexdigest()


def two_bone(a,goal,l1,l2,pole_sign,min_angle=12,max_angle=174):
    v=goal-a;d=v.length;axis=v.normalized()
    minimum=math.sqrt(l1*l1+l2*l2-2*l1*l2*math.cos(math.radians(min_angle)))
    maximum=math.sqrt(l1*l1+l2*l2-2*l1*l2*math.cos(math.radians(max_angle)))
    reach=min(max(d,minimum),maximum)
    pole=Vector((0,pole_sign,0));pole-=axis*pole.dot(axis)
    if pole.length<1e-7:pole=Vector((1,0,0))
    pole.normalize();along=(l1*l1-l2*l2+reach*reach)/(2*reach)
    knee=a+axis*along+pole*math.sqrt(max(0,l1*l1-along*along))
    return [a,knee,a+axis*reach],abs(reach-d)


def fit_limb(rig,limb,neutral,goal,paw_q,meta_angle=None):
    bones=[rig.pose.bones[n] for n in limb['chain']];ankle=rig.pose.bones[limb['ankle']]
    refs={b.name:neutral[b.name].copy() for b in bones}
    old=[neutral[b.name].translation for b in bones]+[neutral[ankle.name].translation]
    lengths=[(old[i+1]-old[i]).length for i in range(len(bones))]
    a=bones[0].matrix.translation.copy()
    if len(bones)==2:
        solved,error=two_bone(a,goal,*lengths,1,min_angle=18,max_angle=174)
        actual_angle=None
    else:
        # Follow captured hock flex, while selecting only reachable, positive-
        # bend hock positions. The third segment rotates with a real running
        # limb, rather than remaining fixed in its standing metatarsal angle.
        desired=meta_angle;best=None
        rest_cross=(old[2]-old[1]).cross(old[3]-old[2]).x
        for angle in np.linspace(-100,100,801):
            meta=Vector((0,math.sin(math.radians(float(angle))),-math.cos(math.radians(float(angle)))))*lengths[2]
            hock=goal-meta;upper,error=two_bone(a,hock,lengths[0],lengths[1],-1,min_angle=30,max_angle=172)
            tibia=upper[2]-upper[1]
            cross=tibia.cross(meta).x
            hock_internal=math.degrees((-tibia).angle(meta))
            if cross*rest_cross<=1e-5 or not 28<hock_internal<156:continue
            score=error*500+(float(angle)-desired)**2*.00001
            if best is None or score<best[0]:best=(score,upper,meta,error,float(angle))
        if best is None:raise RuntimeError('No anatomical hock solution')
        _,upper,meta,error,actual_angle=best
        solved=[upper[0],upper[1],upper[2],upper[2]+meta]
    for i,bone in enumerate(bones):
        set_world_pose(bone,aim(refs[bone.name],old[i+1]-old[i],solved[i+1]-solved[i],solved[i]))
    # Actual endpoint and skin wrist are connected. An unreachable target is
    # reported and never hidden by separating the paw from the lower leg.
    set_world_pose(ankle,Matrix.LocRotScale(solved[-1],paw_q,neutral[ankle.name].to_scale()))
    return error*MODEL_SCALE,actual_angle


def periodic_interp(values,t):
    n=len(values)-1;x=(t%1)*n;i=int(math.floor(x));u=x-i
    a=values[(i-1)%n];b=values[i%n];c=values[(i+1)%n];d=values[(i+2)%n]
    return b+.5*u*(c-a+u*(2*a-5*b+4*c-d+u*(3*(b-c)+d-a)))


def align_quaternions(action):
    """Keep q/-q equivalent poses in one hemisphere before component sampling.

    Matrix reconstruction can change quaternion sign between keys. Linear
    component animation otherwise goes through zero and creates a skin pop
    that is invisible at the authored keyframes. This touches Run only.
    """
    grouped={}
    for c in channels(action):
        if c.data_path.endswith('.rotation_quaternion'):
            grouped.setdefault(c.data_path,{})[c.array_index]=c
    for path,curves in grouped.items():
        if len(curves)!=4:raise RuntimeError('Incomplete quaternion '+path)
        previous=None
        for i in range(len(curves[0].keyframe_points)):
            values=np.asarray([curves[j].keyframe_points[i].co.y for j in range(4)])
            if previous is not None and float(np.dot(previous,values))<0:
                values=-values
                for j in range(4):
                    k=curves[j].keyframe_points[i];k.co.y=-k.co.y
                    k.handle_left.y=-k.handle_left.y;k.handle_right.y=-k.handle_right.y
            previous=values


def support(t,key):
    start,end=CONTACTS[key];p=(t-start)%1
    return p<=end-start,p,end-start


def prepare_foot_profiles(poses,neutral,source_idle,duration,speed):
    profiles={};factor=WORLD_FACTOR/100/MODEL_SCALE
    for key,limb in LIMBS.items():
        rel=[p[limb['source_ankle']].translation-p['b_Hips'].translation for p in poses]
        mean=sum(rel[:-1],Vector())/INTERVALS
        floors=[p[limb['source_paw']].translation.z for p in poses]
        floor=min(floors)
        values=[]
        for i,p in enumerate(poses):
            v=neutral[limb['ankle']].translation.copy();delta=rel[i]-mean
            v.x+=delta.x*factor*.4;v.y+=delta.y*factor
            lift=max(0,(floors[i]-floor)*WORLD_FACTOR/100)
            # The source toe marker rotates through the pad. Preserve its
            # actual nonuniform lift waveform; actual skin is fitted below.
            values.append(dict(goal=v,lift=lift))
        # Model paw endpoints: literal source forward reach remains visible.
        # Only stance is reconciled to the declared constant translation.
        ys=[x['goal'].y for x in values]
        start,end=CONTACTS[key];length=end-start
        anchor=periodic_interp(ys,start)
        travel=speed*duration/MODEL_SCALE
        for i,value in enumerate(values):
            t=i/INTERVALS;planted,p,_=support(t,key)
            if planted:
                value['goal'].y=anchor+travel*p
                value['lift']=0
            else:
                # Blend discrepancy at liftoff/touchdown over the swing. The
                # source's large early reach/late tuck survive this correction.
                u=(p-length)/(1-length)
                old_lift=periodic_interp(ys,end);old_touch=anchor
                desired_lift=anchor+travel*length
                correction=(desired_lift-old_lift)*(1-u)
                value['goal'].y+=correction
                # Boundary ramp affects only the first/last few swing percent.
                value['lift']*=min(1,u/.08,(1-u)/.08)
            if key.startswith('front'):
                # Photo reference has forward extension well off the floor.
                # Add a small carpal-clearance allowance only during reach.
                reach=max(0,(neutral[limb['ankle']].translation.y-value['goal'].y)*MODEL_SCALE)
                if not planted:
                    value['lift']+=min(.027,max(0,reach-.08)*.18)
                    # Reference refinement: forelimb reaches the muzzle line
                    # during late swing. Keep stance intact and support the
                    # additional reach with real scapular glide below.
                    extension=max(0,min(1,(reach-.08)/.15))
                    extension=extension*extension*(3-2*extension)
                    u=(p-length)/(1-length)
                    fade=max(0,min(1,u/.12,(1-u)/.18))
                    extension*=fade*fade*(3-2*fade)
                    value['goal'].y-=.065*extension/MODEL_SCALE
        profiles[key]=values
    return profiles


def author(oldbase,base,preview_only=False):
    base.mkdir(parents=True,exist_ok=True);(base/'production').mkdir(exist_ok=True);(base/'export/Locomotion').mkdir(parents=True,exist_ok=True)
    original_paths=['production/LabradorPet_Animations.blend','production/LabradorPet_Locomotion.blend',
                    'export/LabradorPet_Locomotion.glb','export/Locomotion/Run.fbx','export/Locomotion/Walk.fbx']
    preserved={p:sha(oldbase/p) for p in original_paths}
    bpy.ops.wm.open_mainfile(filepath=str(oldbase/'production/LabradorPet_Locomotion.blend'))
    scene=bpy.context.scene;scene.render.fps=FPS
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    kept={n:action_hash(bpy.data.actions[n]) for n in ('IdleFriendly','PetEnjoy','Walk')}
    set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1);update()
    neutral_basis=basis_snapshot(rig);neutral={b.name:b.matrix.copy() for b in rig.pose.bones}
    set_action(rig,None)
    old_action=bpy.data.actions['Run'];bpy.data.actions.remove(old_action)
    capture=read_bvh(oldbase/'source/raw_bvh_data'/SPEC['file']);poses,coord=closed_samples(capture,SPEC)
    idle=read_bvh(oldbase/'source/raw_bvh_data/dog_idle_002.bvh');source_idle=normalized(idle,8,basis(idle,8))
    height_factor=neutral['Back_38'].translation.z/source_idle['b_Hips'].translation.z
    start=capture.world_pose(SPEC['start'])['b_Hips'].translation;end=capture.world_pose(SPEC['end'])['b_Hips'].translation
    displacement=end-start;displacement.y=0;duration=INTERVALS/FPS
    speed=displacement.length*WORLD_FACTOR/100/duration
    profiles=prepare_foot_profiles(poses,neutral,source_idle,duration,speed)
    hip_mean=sum(p['b_Hips'].translation.z for p in poses[:-1])/INTERVALS
    pads={}
    for k,v in LIMBS.items():
        groups={mesh.vertex_groups[n].index for n in (v['paw'],v['ankle'])}
        pads[k]=[vertex.index for vertex in mesh.data.vertices if sum(g.weight for g in vertex.groups if g.group in groups)>.65]
    action=bpy.data.actions.new('Run');action.use_fake_user=True;receipt=[]
    for i,source in enumerate(poses):
        t=i/INTERVALS;set_action(rig,None);scene.frame_set(i+1);restore_basis(rig,neutral_basis)
        root=rig.pose.bones['Body_43'];m=neutral[root.name].copy()
        m.translation.z+=(source['b_Hips'].translation.z-hip_mean)*height_factor-.008/MODEL_SCALE
        set_world_pose(root,m)
        for name in sorted(MAPPING,key=lambda n:len(rig.pose.bones[n].parent_recursive)):
            if name.startswith(('FrontUpper','FrontLower','BackLeg','BackUpper','BackLower','Tail')):continue
            bone=rig.pose.bones[name];sn=MAPPING[name]
            dq=source[sn].to_quaternion() @ source_idle[sn].to_quaternion().inverted()
            weight=1.0 if name.startswith(('Back_','Torso')) else .82
            if name.startswith(('Neck','Head')):weight=.72
            dq=Quaternion((1,0,0,0)).slerp(dq,weight)
            matrix=Matrix.LocRotScale(bone.matrix.translation,dq @ neutral[name].to_quaternion(),neutral[name].to_scale())
            set_world_pose(bone,matrix)
        goals={};qs={};metas={};clearance={};stance={}
        for key,limb in LIMBS.items():
            value=profiles[key][i];goal=value['goal'].copy();clearance[key]=value['lift'];stance[key]=support(t,key)[0]
            goal.z+=value['lift']/MODEL_SCALE
            dq=source[limb['source_ankle']].to_quaternion() @ source_idle[limb['source_ankle']].to_quaternion().inverted()
            dq=Quaternion((1,0,0,0)).slerp(dq,.65 if not stance[key] else .12)
            q=dq @ neutral[limb['ankle']].to_quaternion()
            if key.startswith('front'):
                # The capture wrist's world axes do not match this model's
                # carpus. Use a calibrated sagittal pitch: neutral support,
                # slightly down-pointing toes in extension, folded recovery.
                rear=(goal.y-neutral[limb['ankle']].translation.y)*MODEL_SCALE
                fold=max(0,min(1,(rear+.015)/.14))
                pitch=(6+49*fold)*min(1,value['lift']/.035)
                q=Quaternion((1,0,0),math.radians(pitch)) @ neutral[limb['ankle']].to_quaternion()
            else:
                # The source ankle's 3D world rotation crosses a shortest-arc
                # branch in this segment and is incompatible with the model's
                # wrist axes. Keep measured translation/timing, and author a
                # continuous sagittal toe pitch with zero yaw/roll copying.
                trailing=(goal.y-neutral[limb['ankle']].translation.y)*MODEL_SCALE
                drive=max(0,min(1,trailing/.22))
                height=max(0,min(1,value['lift']/.055))
                height=height*height*(3-2*height)
                pitch=(16+54*drive)*height
                q=Quaternion((1,0,0),math.radians(pitch)) @ neutral[limb['ankle']].to_quaternion()
            set_world_pose(rig.pose.bones[limb['ankle']],Matrix.LocRotScale(goal,q,neutral[limb['ankle']].to_scale()))
            goal.z+=(.0004+value['lift']-evaluated_floor(mesh,pads[key]))/MODEL_SCALE
            if key.startswith('front'):
                shoulder=rig.pose.bones[next(n for n in MAPPING if n.startswith('FrontShoulder.'+key[-1]+'_'))]
                slide=max(-.063,min(.025,(goal.y-neutral[limb['ankle']].translation.y)*MODEL_SCALE*.25))
                sm=shoulder.matrix.copy();sm.translation.y+=slide/MODEL_SCALE;set_world_pose(shoulder,sm)
                metas[key]=None
            else:
                sn='b_LeftLeg1' if key.endswith('L') else 'b_RightLeg1'
                vector=source[limb['source_ankle']].translation-source[sn].translation
                rest=source_idle[limb['source_ankle']].translation-source_idle[sn].translation
                angle=math.degrees(math.atan2(vector.y,-vector.z))-math.degrees(math.atan2(rest.y,-rest.z))-28
                metas[key]=max(-95,min(95,angle))
            goals[key]=goal;qs[key]=q
        # Chest placement is fitted to the real shorter forelimbs per pose.
        # This removes the previous permanent5.5cm crouch: the body recovers
        # measured height in airborne phases and lowers during loaded stance.
        lower=0
        for key in ('front.L','front.R'):
            limb=LIMBS[key];a=rig.pose.bones[limb['chain'][0]].matrix.translation
            old=[neutral[n].translation for n in limb['chain']]+[neutral[limb['ankle']].translation]
            lengths=[(old[j+1]-old[j]).length for j in range(2)]
            maxreach=math.sqrt(sum(x*x for x in lengths)-2*lengths[0]*lengths[1]*math.cos(math.radians(172)))
            horizontal=math.hypot(goals[key].x-a.x,goals[key].y-a.y)
            if horizontal<maxreach:
                allowable=goals[key].z+math.sqrt(max(0,maxreach*maxreach-horizontal*horizontal))
                lower=max(lower,a.z-allowable)
        if lower>0:
            m=root.matrix.copy();m.translation.z-=lower+.005/MODEL_SCALE;set_world_pose(root,m)
        feet={}
        for key,limb in LIMBS.items():
            error,angle=fit_limb(rig,limb,neutral,goals[key],qs[key],metas[key])
            for correction in range(2):
                floor=evaluated_floor(mesh,pads[key]);goals[key].z+=(.0004+clearance[key]-floor)/MODEL_SCALE
                e,angle=fit_limb(rig,limb,neutral,goals[key],qs[key],metas[key]);error=max(error,e)
            feet[key]={'stance':stance[key],'clearance_m':clearance[key],'floor_m':evaluated_floor(mesh,pads[key]),
                       'reach_residual_m':error,'metatarsal_angle_deg':angle,
                       'wrist_world_m':list((rig.matrix_world @ rig.pose.bones[limb['ankle']].matrix).translation)}
        for side in ('L','R'):
            for j in range(1,5):
                b=next(b for b in rig.pose.bones if b.name.startswith(f'Ear{j}.{side}_'))
                b.rotation_quaternion=b.rotation_quaternion @ Quaternion((1,0,0),math.radians((2+j)*math.sin(2*math.pi*t-j*.45)))
        for j,n in enumerate(('Tail1_37','Tail2_36','Tail3_35','Tail4_34','Tail5_33','Tail6_32')):
            b=rig.pose.bones[n];b.rotation_quaternion=b.rotation_quaternion @ Quaternion((0,0,1),math.radians(2*math.sin(2*math.pi*t-j*.3)))
        update();key_pose(rig,action,i+1);receipt.append({'frame':i+1,'feet':feet,'adaptive_body_lower_m':lower*MODEL_SCALE})
    loop_close(rig,action,INTERVALS+1)
    align_quaternions(action)
    for c in channels(action):
        for k in c.keyframe_points:k.interpolation='LINEAR'
    for n,h in kept.items():assert action_hash(bpy.data.actions[n])==h,n
    set_action(rig,action);scene.frame_start=1;scene.frame_end=INTERVALS+1;scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(base/'production/LabradorPet_Gallop.blend'))
    manifest={'fps':FPS,'rigRoot':'LabradorPet','modelScale':.3,'forward':'Blender -Y; Unity/glTF +Z',
              'clips':[{'name':'IdleFriendly','frames':[1,314],'fps':30,'duration':313/30,'loop':True},
                       {'name':'PetEnjoy','frames':[1,121],'fps':30,'duration':4,'loop':True},
                       {'name':'Walk','frames':[1,47],'fps':60,'duration':46/60,'loop':True,'speed_m_s':.7151154096607382},
                       {'name':'Run','frames':[1,INTERVALS+1],'fps':60,'duration':duration,'loop':True,'speed_m_s':speed,
                        'root_motion':'in-place; captured vertical-body/pelvis/spine motion',
                        'source_capture':str((oldbase/'source/raw_bvh_data'/SPEC['file']).resolve()),
                        'source_raw_frames':[SPEC['start'],SPEC['end']], 'source_fps':capture.fps,
                        'retimed_from_duration_s':48/capture.fps,'paw_world_scale':WORLD_FACTOR,
                        'contact_phases':{k:list(v) for k,v in CONTACTS.items()},
                        'source':'Captured large nonuniform paw translations, footfall timing and body motion; anatomical model IK with original-rest bend directions, contact/heel polish, scapular glide, calibrated authored sagittal carpal/toe pitch and ear/tail follow-through. Original 3D ankle rotations are not copied.'}],
              'run_export':'Locomotion/Run.fbx','preserved_original_files_sha256':preserved,
              'preserved_action_sha256':kept,'scope':'Run-only gallop revision. Prior source, rest data, care and Walk unchanged.'}
    (base/'export/gallop-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (base/'gallop-authoring-contact.json').write_text(json.dumps({'frames':receipt},indent=2)+'\n')
    (base/'gallop-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    if not preview_only:export(base,oldbase,manifest,neutral_basis)
    for p,h in preserved.items():assert sha(oldbase/p)==h,p
    preview(base)
    print('GALLOP_AUTHOR_COMPLETE',speed,flush=True)


def export(base,oldbase,manifest,neutral_basis):
    scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    for o in scene.objects:o.select_set(False)
    for o in [rig,*rig.children_recursive]:o.select_set(True)
    bpy.context.view_layer.objects.active=rig
    run=next(c for c in manifest['clips'] if c['name']=='Run');set_action(rig,bpy.data.actions['Run'])
    scene.frame_start=1;scene.frame_end=run['frames'][1];scene.frame_set(1)
    bpy.ops.export_scene.fbx(filepath=str(base/'export/Locomotion/Run.fbx'),use_selection=True,
                            object_types={'ARMATURE','MESH','EMPTY'},add_leaf_bones=False,axis_forward='-Z',axis_up='Y',
                            apply_scale_options='FBX_SCALE_UNITS',use_armature_deform_only=False,
                            bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,
                            path_mode='RELATIVE',colors_type='LINEAR',bake_anim=True,bake_anim_force_startend_keying=True,bake_anim_step=1)
    combined=[];temps=[]
    for c in manifest['clips']:
        a=bpy.data.actions[c['name']]
        if c['fps']==30:
            a=a.copy();a.name='Bundle_'+c['name'];temps.append(a)
            for f in channels(a):
                for k in f.keyframe_points:
                    k.co.x=1+(k.co.x-1)*2;k.handle_left.x=1+(k.handle_left.x-1)*2;k.handle_right.x=1+(k.handle_right.x-1)*2
        combined.append((c,a,1+(c['frames'][1]-1)*FPS/c['fps']))
    set_action(rig,None);restore_basis(rig,neutral_basis)
    for t in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(t)
    for c,a,end in combined:
        track=rig.animation_data.nla_tracks.new();track.name=c['name'];strip=track.strips.new(c['name'],1,a)
        strip.action_slot=a.slots[0];strip.frame_end=end;strip.extrapolation='NOTHING';strip.blend_type='REPLACE';track.mute=True
    mesh.data.shape_keys.animation_data_clear()
    for k in mesh.data.shape_keys.key_blocks:k.value=0
    scene.frame_start=1;scene.frame_end=round(max(x[2] for x in combined));scene.frame_set(1)
    path=base/'export/LabradorPet_Gallop.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,
                             export_animation_mode='NLA_TRACKS',export_anim_slide_to_zero=True,export_force_sampling=True,
                             export_frame_step=1,export_morph=True,export_morph_animation=False,export_vertex_color='ACTIVE',
                             export_all_vertex_colors=False,export_yup=True,export_image_format='AUTO',export_cameras=False,
                             export_lights=False,export_extras=True)
    raw=path.read_bytes();size,kind=struct.unpack_from('<II',raw,12);assert kind==0x4e4f534a;data=json.loads(raw[20:20+size])
    assert sorted(x['name'] for x in data['animations'])==sorted(x['name'] for x in manifest['clips'])
    timings={}
    for a in data['animations']:
        acc=[data['accessors'][s['input']] for s in a['samplers']]
        t0=min(x['min'][0] for x in acc);t1=max(x['max'][0] for x in acc)
        c=next(c for c in manifest['clips'] if c['name']==a['name']);assert abs(t0)<1e-6 and abs(t1-c['duration'])<1e-5
        timings[a['name']]={'start_s':t0,'duration_s':t1}
    (base/'gallop-gltf-summary.json').write_text(json.dumps({'passed':True,'clip_timings':timings,'bytes':len(raw),'sha256':sha(path)},indent=2)+'\n')
    for t in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(t)
    for a in temps:bpy.data.actions.remove(a)


def preview(base):
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Gallop.blend'))
    scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];camera=stage(scene)
    camera.location=(2.1,.0,.53);camera.rotation_euler=(Vector((0,0,.40))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=2.3;scene.render.resolution_x=720;scene.render.resolution_y=440
    scene.eevee.taa_render_samples=16
    out=base/'review/side';out.mkdir(parents=True,exist_ok=True)
    set_action(rig,bpy.data.actions['Run'])
    for frame in [1,4,7,10,13,16,19,22,25,28]:
        scene.frame_set(frame);update();scene.render.filepath=str(out/f'Run_{frame:03}.png');bpy.ops.render.render(write_still=True)
    print('GALLOP_SIDE_PREVIEW_READY',str(out),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--old-base',type=Path,required=True);p.add_argument('--base',type=Path,required=True)
    p.add_argument('--preview-only',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    author(a.old_base.resolve(),a.base.resolve(),a.preview_only)
