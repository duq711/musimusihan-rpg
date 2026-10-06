"""Run-only sprint adaptation with captured paw profiles and a smooth body arc.

The reference movie was observed in the browser; it is neither downloaded nor
embedded. The new paired fore/hind rhythm and calibrated toe pitches are authored
adaptations, while the nonuniform paw trajectories originate in the cited BVH.
Previous sources, production assets, rest data and care/Walk keys are untouched.
"""
import argparse, hashlib, json, math, struct, sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix,Quaternion,Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import LIMBS,MAPPING,MODEL_SCALE,aim,basis_snapshot,channels,key_pose,restore_basis,set_action,update
from labrador_pet_bvh import read_bvh
from labrador_pet_locomotion import basis,normalized,evaluated_floor
from labrador_pet_retarget import set_world_pose
from labrador_pet_gallop import action_hash,align_quaternions,two_bone
from labrador_pet_preview import stage

FPS=60;INTERVALS=42;DURATION=INTERVALS/FPS
SPEC={'file':'dog_fast_run_02_006.bvh','start':856,'end':900}
CONTACTS={'front.R':(.32,.49),'front.L':(.42,.59),'hind.R':(.84,1.015),'hind.L':(.935,1.11)}
# These source timing windows are refined from marker velocities, separately
# from the video-inspired target rhythm. Source toe heights are not sole contact.
SOURCE_CONTACTS={'front.L':(.6136,.8182),'front.R':(.8636,1.0682),'hind.L':(.4091,.51),'hind.R':(.3182,.43)}
SCALE=.80

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def smooth(x):return x*x*x*(10+x*(-15+6*x))

class Fourier:
    """C-infinity periodic low-pass of a measured path, with exact derivatives."""
    def __init__(self,values,harmonics=6):
        self.coefficients=np.fft.rfft(np.asarray(values,dtype=float),axis=0)/len(values)
        self.coefficients=self.coefficients[:harmonics+1]
    def __call__(self,t,derivative=0):
        result=np.zeros_like(self.coefficients[0].real)
        if derivative==0:result+=self.coefficients[0].real
        for k,c in enumerate(self.coefficients[1:],1):
            result+=2*np.real(c*(2j*math.pi*k)**derivative*np.exp(2j*math.pi*k*t))
        return result

def periodic_curve(points):
    # Periodic cubic B-spline basis is C2 at every segment and at the cycle seam.
    values=np.asarray(points,dtype=float)
    def sample(t):
        x=(t%1)*len(values);i=int(x);u=x-i
        weights=((1-u)**3,(3*u**3-6*u*u+4),(-3*u**3+3*u*u+3*u+1),u**3)
        return sum(values[(i+j-1)%len(values)]*weights[j]/6 for j in range(4))
    return sample

def support(t,key):
    a,b=CONTACTS[key];p=(t-a)%1;length=b-a
    return p<=length,p,length

def quintic_match(y0,d0,a0,y1,d1,a1,u):
    c=np.array([y0,d0,a0/2,0.,0.,0.])
    c[3:]=np.linalg.solve(np.array([[1,1,1],[3,4,5],[6,12,20]],dtype=float),
                          np.array([y1-c[0]-c[1]-c[2],d1-c[1]-2*c[2],a1-2*c[2]]))
    return sum(c[i]*u**i for i in range(6))

def source_profiles(capture):
    n=240;coordinate=basis(capture,(SPEC['start']+SPEC['end'])/2)
    poses=[normalized(capture,SPEC['start']+(SPEC['end']-SPEC['start'])*i/n,coordinate) for i in range(n)]
    profile={}
    for key,limb in LIMBS.items():
        rel=np.asarray([list(p[limb['source_ankle']].translation-p['b_Hips'].translation) for p in poses])
        toe=np.asarray([p[limb['source_paw']].translation.z for p in poses]);toe-=toe.min()
        profile[key]={'relative':Fourier(rel),'height':Fourier(toe),'mean':rel.mean(axis=0)}
    # Use the more expressive source's sagittal lumbar curvature only after
    # smoothing its cycle; model rotations are adapted to its very long torso.
    return profile,poses

def foot_value(key,t,profile,neutral,travel):
    planted,p,length=support(t,key);old_a,old_b=SOURCE_CONTACTS[key];old_length=old_b-old_a
    neutral_pos=neutral[LIMBS[key]['ankle']].translation.copy();r=profile['relative'];factor=SCALE/100/MODEL_SCALE
    touch=float(r(old_a)[1]-profile['mean'][1])*factor+neutral_pos.y
    # Put the paired touchdown in front of each limb's shoulder/hip by a modest
    # amount, retaining the captured swing extremes between these boundaries.
    touch=neutral_pos.y-(.10 if key.startswith('front') else .09)/MODEL_SCALE
    if planted:
        return Vector((neutral_pos.x,touch+travel*p,neutral_pos.z)),0.,True,0.
    u=(p-length)/(1-length);s=old_b+u*(1-old_length)
    y=neutral_pos.y+(r(s)[1]-profile['mean'][1])*factor
    e0=neutral_pos.y+(r(old_b)[1]-profile['mean'][1])*factor
    e1=neutral_pos.y+(r(old_a+1)[1]-profile['mean'][1])*factor
    derivative_scale=(1-old_length)
    dy0=float(r(old_b,1)[1])*factor*derivative_scale
    dy1=float(r(old_a+1,1)[1])*factor*derivative_scale
    ddy0=float(r(old_b,2)[1])*factor*derivative_scale**2
    ddy1=float(r(old_a+1,2)[1])*factor*derivative_scale**2
    # Source shape plus a quintic endpoint discrepancy field. Its first two
    # derivatives join the exact translation-cancelling stance continuously.
    y+=quintic_match(touch+travel*length-e0,travel*(1-length)-dy0,-ddy0,
                     touch-e1,travel*(1-length)-dy1,-ddy1,u)
    gate=smooth(min(1,u/.13))*smooth(min(1,(1-u)/.15))
    lift=max(0,float(profile['height'](s)))*SCALE/100*gate
    x=neutral_pos.x+(float(r(s)[0])-profile['mean'][0])*factor*.22*gate
    if key.startswith('front'):
        reach=max(0,(neutral_pos.y-y)*MODEL_SCALE)
        extension=smooth(max(0,min(1,(reach-.07)/.17)))*gate
        y-=.060*extension/MODEL_SCALE
        lift+=(.04+.016*extension)*gate
        # This rig's radius is 2.4 times its humerus: a capture-sized high wrist
        # close to the shoulder would fold through the anatomical inner limit.
        # Fit clearance smoothly to the Labrador, preserving the measured shape.
        lift=.125*math.tanh(lift/.125)
    else:lift+=.026*gate
    return Vector((x,y,neutral_pos.z)),lift,False,u

def calibrated_pitch(key,u,stance):
    if stance:return 0.
    # Phase-defined C2 wrist curves, rather than height-threshold activation.
    # Front recovery curls below the chest, extension then aims toes forward/down.
    points=[0,20,53,65,55,24,8,4,0,0] if key.startswith('front') else [0,25,47,38,23,12,8,4,0,0]
    value=float(periodic_curve(points)(u))
    return value*smooth(min(1,u/.13))*smooth(min(1,(1-u)/.15))

def fit(rig,limb,neutral,goal,q,meta_desired=-35):
    bones=[rig.pose.bones[n] for n in limb['chain']];ankle=rig.pose.bones[limb['ankle']]
    old=[neutral[b.name].translation for b in bones]+[neutral[ankle.name].translation]
    lengths=[(old[j+1]-old[j]).length for j in range(len(bones))];a=bones[0].matrix.translation.copy()
    if len(bones)==2:
        solved,error=two_bone(a,goal,*lengths,1,min_angle=23,max_angle=174);angle=None
    else:
        rest_cross=(old[2]-old[1]).cross(old[3]-old[2]).x;best=None
        for angle0 in np.linspace(-98,75,347):
            meta=Vector((0,math.sin(math.radians(float(angle0))),-math.cos(math.radians(float(angle0)))))*lengths[2]
            upper,error0=two_bone(a,goal-meta,lengths[0],lengths[1],-1,min_angle=35,max_angle=171)
            tibia=upper[2]-upper[1];internal=math.degrees((-tibia).angle(meta))
            if tibia.cross(meta).x*rest_cross<=1e-5 or not 35<internal<151:continue
            score=error0*10000+(float(angle0)-meta_desired)**2*.000001
            if best is None or score<best[0]:best=(score,upper,meta,error0,float(angle0))
        if best is None:raise RuntimeError('No anatomical hock solution')
        _,upper,meta,error,angle=best;solved=[*upper,upper[2]+meta]
    for j,b in enumerate(bones):set_world_pose(b,aim(neutral[b.name],old[j+1]-old[j],solved[j+1]-solved[j],solved[j]))
    set_world_pose(ankle,Matrix.LocRotScale(solved[-1],q,neutral[ankle.name].to_scale()))
    return error*MODEL_SCALE,angle

def author(oldbase,base,preview_only=False):
    base.mkdir(parents=True,exist_ok=True);(base/'production').mkdir(exist_ok=True);(base/'export/Locomotion').mkdir(parents=True,exist_ok=True)
    preserved_paths=['production/LabradorPet_Animations.blend','production/LabradorPet_Locomotion.blend','export/LabradorPet_Locomotion.glb','export/Locomotion/Run.fbx','export/Locomotion/Walk.fbx']
    preserved={p:sha(oldbase/p) for p in preserved_paths}
    gallop=oldbase.parent/'labrador-gallop-20261006';previous={p:sha(gallop/p) for p in ['production/LabradorPet_Gallop.blend','export/LabradorPet_Gallop.glb','export/Locomotion/Run.fbx']}
    bpy.ops.wm.open_mainfile(filepath=str(oldbase/'production/LabradorPet_Locomotion.blend'))
    scene=bpy.context.scene;scene.render.fps=FPS;rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    kept={n:action_hash(bpy.data.actions[n]) for n in ('IdleFriendly','PetEnjoy','Walk')}
    set_action(rig,bpy.data.actions['IdleFriendly']);scene.frame_set(1);update();neutral_basis=basis_snapshot(rig);neutral={b.name:b.matrix.copy() for b in rig.pose.bones}
    set_action(rig,None);bpy.data.actions.remove(bpy.data.actions['Run'])
    capture=read_bvh(oldbase/'source/raw_bvh_data'/SPEC['file']);profiles,poses=source_profiles(capture)
    raw0=capture.world_pose(SPEC['start'])['b_Hips'].translation;raw1=capture.world_pose(SPEC['end'])['b_Hips'].translation
    displacement=raw1-raw0;displacement.y=0;speed=displacement.length*SCALE/100/DURATION;travel=speed*DURATION/MODEL_SCALE
    pads={}
    for k,l in LIMBS.items():
        groups={mesh.vertex_groups[n].index for n in (l['paw'],l['ankle'])}
        pads[k]=[v.index for v in mesh.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.65]
    # [hip offset metres, pelvis angle, lumbar angle, thorax angle] at .1 phases.
    # The rounded collection is created by actual connected spine rotations;
    # no scaling of the original spine segment lengths or rest data occurs.
    core=periodic_curve([[0,1,-1,-2],[.018,2,-2,-3],[.01,2,-1,-3],[-.02,2,0,-1],[-.046,0,-5,8],[-.029,-14,-4,24],[.005,-26,-2,27],[.014,-29,1,24],[-.005,-18,0,12],[-.014,-3,-1,1]])
    scapular_height=periodic_curve([0,0,0,0,0,-.020,-.050,-.006,0,0])
    action=bpy.data.actions.new('Run');action.use_fake_user=True;receipt=[]
    for i in range(INTERVALS+1):
        t=(i%INTERVALS)/INTERVALS;set_action(rig,None);scene.frame_set(i+1);restore_basis(rig,neutral_basis)
        values=core(t);root=rig.pose.bones['Body_43'];m=neutral[root.name].copy();m.translation.z+=(float(values[0])-.027)/MODEL_SCALE;set_world_pose(root,m)
        for n,angle in zip(('Back_38','Torso_23','Torso2_22','Torso3_15'),(values[1],values[2],values[3],values[3]*.5)):
            b=rig.pose.bones[n];set_world_pose(b,Matrix.LocRotScale(b.matrix.translation,Quaternion((1,0,0),math.radians(float(angle))) @ neutral[n].to_quaternion(),neutral[n].to_scale()))
        # The neck absorbs body flex while retaining its segment attachment.
        for n,lean in zip(('Neck1_14','Neck2_13','Neck3_12','Head_1','Neck3.001_11'),(27,24,18,12,12)):
            b=rig.pose.bones[n];pitch=lean-float(values[3])*.04
            set_world_pose(b,Matrix.LocRotScale(b.matrix.translation,Quaternion((1,0,0),math.radians(pitch)) @ neutral[n].to_quaternion(),neutral[n].to_scale()))
        feet={}
        for key,limb in LIMBS.items():
            goal,lift,stance,u=foot_value(key,t,profiles[key],neutral,travel)
            pitch=calibrated_pitch(key,u,stance);q=Quaternion((1,0,0),math.radians(pitch)) @ neutral[limb['ankle']].to_quaternion()
            goal.z+=lift/MODEL_SCALE
            if key.startswith('front'):
                shoulder=rig.pose.bones[next(n for n in MAPPING if n.startswith('FrontShoulder.'+key[-1]+'_'))]
                sm=shoulder.matrix.copy();fore=(goal.y-neutral[limb['ankle']].translation.y)*MODEL_SCALE
                glide=.078*math.tanh(fore/.15)-.027;sm.translation.y+=glide/MODEL_SCALE
                sm.translation.z+=float(scapular_height(t))/MODEL_SCALE
                set_world_pose(shoulder,sm);meta=None
            else:
                meta=-30-25*math.sin(math.pi*u)**2 if not stance else -29
            # Skin wrist orientation is set before measuring its actual pad.
            set_world_pose(rig.pose.bones[limb['ankle']],Matrix.LocRotScale(goal,q,neutral[limb['ankle']].to_scale()))
            goal.z+=(.0006+lift-evaluated_floor(mesh,pads[key]))/MODEL_SCALE
            error,angle=fit(rig,limb,neutral,goal,q,meta)
            for j in range(2):
                floor=evaluated_floor(mesh,pads[key]);goal.z+=(.0006+lift-floor)/MODEL_SCALE
                e,angle=fit(rig,limb,neutral,goal,q,meta)
            feet[key]={'stance':stance,'clearance_m':lift,'floor_m':evaluated_floor(mesh,pads[key]),'reach_residual_m':e,'initial_reach_adjustment_m':error,'metatarsal_angle_deg':angle,'pitch_deg':pitch,'goal':list(goal*MODEL_SCALE),'shoulder':list(rig.pose.bones[limb['chain'][0]].matrix.translation*MODEL_SCALE)}
        for side in ('L','R'):
            for j in range(1,5):
                b=next(b for b in rig.pose.bones if b.name.startswith(f'Ear{j}.{side}_'));b.rotation_quaternion=b.rotation_quaternion @ Quaternion((1,0,0),math.radians((2+j)*math.sin(2*math.pi*t-j*.45)))
        for j,n in enumerate(('Tail1_37','Tail2_36','Tail3_35','Tail4_34','Tail5_33','Tail6_32')):
            b=rig.pose.bones[n];b.rotation_quaternion=b.rotation_quaternion @ Quaternion((0,0,1),math.radians(2*math.sin(2*math.pi*t-j*.3)))
        update();key_pose(rig,action,i+1);receipt.append({'frame':i+1,'phase':t,'feet':feet,'body_envelope':list(values)})
    align_quaternions(action)
    for c in channels(action):
        for k in c.keyframe_points:k.interpolation='BEZIER';k.handle_left_type='AUTO';k.handle_right_type='AUTO'
        # Periodic cyclic handle slopes at duplicate first/last samples.
        ks=c.keyframe_points
        if len(ks)>2:
            slope=(ks[1].co.y-ks[-2].co.y)/2
            ks[0].handle_left_type=ks[0].handle_right_type=ks[-1].handle_left_type=ks[-1].handle_right_type='FREE'
            for k in (ks[0],ks[-1]):k.handle_left=(k.co.x-1/3,k.co.y-slope/3);k.handle_right=(k.co.x+1/3,k.co.y+slope/3)
    for n,h in kept.items():assert action_hash(bpy.data.actions[n])==h,n
    set_action(rig,action);scene.frame_start=1;scene.frame_end=INTERVALS+1;scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(base/'production/LabradorPet_Sprint.blend'))
    manifest={'fps':FPS,'rigRoot':'LabradorPet','modelScale':.3,'forward':'Blender -Y; Unity/glTF +Z','clips':[{'name':'IdleFriendly','frames':[1,314],'fps':30,'duration':313/30,'loop':True},{'name':'PetEnjoy','frames':[1,121],'fps':30,'duration':4,'loop':True},{'name':'Walk','frames':[1,47],'fps':60,'duration':46/60,'loop':True,'speed_m_s':.7151154096607382},{'name':'Run','frames':[1,INTERVALS+1],'fps':FPS,'duration':DURATION,'loop':True,'speed_m_s':speed,'root_motion':'in-place; smoothly authored vertical body and spinal flex','source_capture':str((oldbase/'source/raw_bvh_data'/SPEC['file']).resolve()),'source_raw_frames':[SPEC['start'],SPEC['end']],'source_fps':capture.fps,'retimed_from_duration_s':(SPEC['end']-SPEC['start'])/capture.fps,'paw_world_scale':SCALE,'contact_phases':{k:list(v) for k,v in CONTACTS.items()},'source':'Captured nonuniform paw profile, filtered periodic and phase-warped for paired fore/hind reference rhythm. Body envelope, scapular glide, calibrated phase carpal/toe pitch and source boundary contact correction are authored. Video display timing is a visual pacing guide; overlay speed and source marker flight are not physical ground truth.'}],'run_export':'Locomotion/Run.fbx','preserved_original_files_sha256':preserved,'preserved_previous_gallop_sha256':previous,'preserved_action_sha256':kept,'scope':'Run-only sprint revision; previous files and source/rest geometry, weights, morphs, care and Walk unchanged.'}
    (base/'export/sprint-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');(base/'sprint-authoring-contact.json').write_text(json.dumps({'frames':receipt},indent=2)+'\n')
    if not preview_only:export(base,manifest,neutral_basis)
    for p,h in preserved.items():assert sha(oldbase/p)==h,p
    for p,h in previous.items():assert sha(gallop/p)==h,p
    preview(base);print('SPRINT_AUTHOR_COMPLETE',speed,flush=True)

def export(base,manifest,neutral_basis):
    scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    for o in scene.objects:o.select_set(False)
    for o in [rig,*rig.children_recursive]:o.select_set(True)
    bpy.context.view_layer.objects.active=rig;set_action(rig,bpy.data.actions['Run']);scene.frame_start=1;scene.frame_end=INTERVALS+1;scene.frame_set(1)
    bpy.ops.export_scene.fbx(filepath=str(base/'export/Locomotion/Run.fbx'),use_selection=True,object_types={'ARMATURE','MESH','EMPTY'},add_leaf_bones=False,axis_forward='-Z',axis_up='Y',apply_scale_options='FBX_SCALE_UNITS',use_armature_deform_only=False,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,path_mode='RELATIVE',colors_type='LINEAR',bake_anim=True,bake_anim_force_startend_keying=True,bake_anim_step=1)
    temps=[];combined=[]
    for c in manifest['clips']:
        a=bpy.data.actions[c['name']]
        if c['fps']==30:
            a=a.copy();a.name='Bundle_'+c['name'];temps.append(a)
            for f in channels(a):
                for k in f.keyframe_points:k.co.x=1+(k.co.x-1)*2;k.handle_left.x=1+(k.handle_left.x-1)*2;k.handle_right.x=1+(k.handle_right.x-1)*2
        combined.append((c,a,1+(c['frames'][1]-1)*FPS/c['fps']))
    set_action(rig,None);restore_basis(rig,neutral_basis)
    for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
    for c,a,end in combined:
        track=rig.animation_data.nla_tracks.new();track.name=c['name'];strip=track.strips.new(c['name'],1,a);strip.action_slot=a.slots[0];strip.frame_end=end;strip.extrapolation='NOTHING';strip.blend_type='REPLACE';track.mute=True
    mesh.data.shape_keys.animation_data_clear()
    for k in mesh.data.shape_keys.key_blocks:k.value=0
    scene.frame_start=1;scene.frame_end=round(max(x[2] for x in combined));scene.frame_set(1)
    path=base/'export/LabradorPet_Sprint.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='NLA_TRACKS',export_anim_slide_to_zero=True,export_force_sampling=True,export_frame_step=1,export_morph=True,export_morph_animation=False,export_vertex_color='ACTIVE',export_all_vertex_colors=False,export_yup=True,export_image_format='AUTO',export_cameras=False,export_lights=False,export_extras=True)
    raw=path.read_bytes();size,kind=struct.unpack_from('<II',raw,12);data=json.loads(raw[20:20+size]);timings={}
    assert sorted(a['name'] for a in data['animations'])==sorted(c['name'] for c in manifest['clips'])
    for a in data['animations']:
        acc=[data['accessors'][s['input']] for s in a['samplers']];lo=min(x['min'][0] for x in acc);hi=max(x['max'][0] for x in acc);c=next(c for c in manifest['clips'] if c['name']==a['name']);assert abs(lo)<1e-6 and abs(hi-c['duration'])<1e-5;timings[a['name']]={'start_s':lo,'duration_s':hi}
    (base/'sprint-gltf-summary.json').write_text(json.dumps({'passed':True,'clip_timings':timings,'bytes':len(raw),'sha256':sha(path)},indent=2)+'\n')

def preview(base):
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Sprint.blend'));scene=bpy.context.scene;rig=bpy.data.objects['LabradorPet'];camera=stage(scene)
    camera.location=(2.1,0,.53);camera.rotation_euler=(Vector((0,0,.40))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=2.3;scene.render.resolution_x=720;scene.render.resolution_y=440;scene.eevee.taa_render_samples=16
    out=base/'review/side';out.mkdir(parents=True,exist_ok=True);set_action(rig,bpy.data.actions['Run'])
    for phase in np.arange(0,1,.1):
        frame=1+float(phase)*INTERVALS;scene.frame_set(int(frame),subframe=frame-int(frame));update();scene.render.filepath=str(out/f'Run_phase_{round(phase*100):03}.png');bpy.ops.render.render(write_still=True)
    print('SPRINT_SIDE_PREVIEW_READY',out,flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--old-base',type=Path,required=True);p.add_argument('--base',type=Path,required=True);p.add_argument('--preview-only',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);author(a.old_base.resolve(),a.base.resolve(),a.preview_only)
