"""Read-only preservation, skin, loop and FBX round-trip locomotion QA."""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import SOURCE_SHA, channels, pad_indices, set_action
from labrador_pet_validate import coordinates, pose


def rotation_vector(a,b):
    # atan2 uses the quaternion vector for tiny differences. Blender's
    # float32 to_axis_angle/acos(w) can quantize .01-frame tangents to zero.
    q=a.to_quaternion().inverted() @ b.to_quaternion()
    values=np.asarray(tuple(q),dtype=np.float64)
    if values[0]<0:values=-values
    length=float(np.linalg.norm(values[1:]))
    return values[1:]*((2*math.atan2(length,values[0])/length) if length>1e-12 else 2)


def fingerprint(mesh,rig):
    def sha(values):return hashlib.sha256(np.asarray(values,dtype='<f4').tobytes()).hexdigest()
    return {'geometry':sha([v.co[:] for v in mesh.data.vertices]),
            'rest_matrices':sha([b.matrix_local[:] for b in rig.data.bones]),
            'mask':sha([v.color[:] for v in mesh.data.color_attributes['PetCoatMask'].data]),
            'morphs':{k.name:sha([v.co[:] for v in k.data]) for k in mesh.data.shape_keys.key_blocks},
            'weights':hashlib.sha256(repr([[(g.group,round(g.weight,7)) for g in v.groups] for v in mesh.data.vertices]).encode()).hexdigest()}


def validate(base):
    report={'passed':False,'checks':[],'clips':[],'fbx_roundtrips':[]};failures=[]
    def check(name,value,details=None):
        report['checks'].append({'name':name,'passed':bool(value),'details':details})
        if not value:failures.append(name)
    check('Downloaded source exact SHA256 preserved',hashlib.sha256((base/'source/LabradorDog_kenchoo_2k.glb').read_bytes()).hexdigest()==SOURCE_SHA)
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Animations.blend'))
    old=fingerprint(bpy.data.objects['LabradorPet_Mesh'],bpy.data.objects['LabradorPet'])
    old_actions={n:[[list(k.co) for k in c.keyframe_points] for c in channels(bpy.data.actions[n])] for n in ('IdleFriendly','PetEnjoy')}
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Locomotion.blend'))
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh']
    actual=fingerprint(mesh,rig)
    for key in old:check('Preserved '+key+' exact',old[key]==actual[key],actual[key])
    for n in old_actions:check(n+' original action keys preserved',old_actions[n]==[[list(k.co) for k in c.keyframe_points] for c in channels(bpy.data.actions[n])])
    manifest=json.loads((base/'locomotion-manifest.json').read_text())
    check('Exact requested two additional clips',[c['name'] for c in manifest['clips']]==['Walk','Run'])
    check('Same 53 joint armature and metre scale',len(rig.pose.bones)==53 and max(abs(v-.3) for v in rig.scale)<1e-6)
    receipts=json.loads((base/'validation/locomotion/authoring-contact.json').read_text())['frames']
    residual=max(f['reach_residual_m'] for x in receipts for f in x['feet'].values())
    check('Every fitted target reached without limb stretch',residual<.0002,{'max_residual_m':residual,'frames':len(receipts)})
    pads={name:np.asarray(pad_indices(mesh,name),dtype=int) for name in ('FF.L_46','FF.R_50','FFB.L_44','FFB.R_48')}
    samples={};frame_count=0
    for clip in manifest['clips']:
        name=clip['name'];end=clip['frames'][1];set_action(rig,bpy.data.actions[name]);frames=np.arange(1,end+.001,.5)
        check(name+' finite animation channels',all(math.isfinite(float(v)) for c in channels(bpy.data.actions[name]) for k in c.keyframe_points for v in k.co))
        root=[];low=100;minima={n:100 for n in pads};maxima={n:-100 for n in pads};finite=True
        for frame in frames:
            matrices=pose(rig,float(frame));world=coordinates(mesh);frame_count+=1
            finite=finite and bool(np.isfinite(world).all());low=min(low,float(world[:,2].min()))
            root.append(list(matrices['GLTF_created_0_rootJoint'].translation))
            for n,inds in pads.items():
                h=float(world[inds,2].min());minima[n]=min(minima[n],h);maxima[n]=max(maxima[n],h)
        check(name+' all 120Hz skin samples finite',finite,{'frames':len(frames)})
        check(name+' complete skin within 3mm floor tolerance',low>-.003,{'lowest_m':low,'penetration_tolerance_m':.003})
        check(name+' all paws support and swing',min(minima.values())>-.003 and max(minima.values())<.002 and min(maxima.values())>.02,
              {'minimum_m':minima,'maximum_m':maxima})
        check(name+' root remains in place',np.ptp(np.asarray(root),axis=0).max()<1e-6,{'root_range_m':np.ptp(np.asarray(root),axis=0).tolist()})
        ends=[pose(rig,f) for f in (1,1.01,end-.01,end)];seam_pos=seam_rot=seam_vel=seam_ang=0
        for b in ends[0]:
            m=[p[b] for p in ends]
            seam_pos=max(seam_pos,(m[0].translation-m[-1].translation).length)
            seam_rot=max(seam_rot,float(np.linalg.norm(rotation_vector(m[0],m[-1]))))
            v0=(m[1].translation-m[0].translation)*6000;vn=(m[-1].translation-m[-2].translation)*6000
            seam_vel=max(seam_vel,(v0-vn).length)
            w0=rotation_vector(m[0],m[1])*6000;wn=rotation_vector(m[-2],m[-1])*6000
            seam_ang=max(seam_ang,float(np.linalg.norm(w0-wn)))
        check(name+' exact loop pose continuity',seam_pos<.00001 and seam_rot<math.radians(.01),{'position_m':seam_pos,'rotation_deg':math.degrees(seam_rot)})
        check(name+' loop tangent continuity',seam_vel<.15 and seam_ang<math.radians(180),
              {'position_velocity_difference_m_s':seam_vel,'angular_velocity_difference_deg_s':math.degrees(seam_ang)})
        for frame in (1,round((end+1)/2),end):
            matrices=pose(rig,frame);samples[name,frame]={'joints':{n:m.translation.copy() for n,m in matrices.items()},'skin':coordinates(mesh)}
        report['clips'].append({'name':name,'fps':120,'frames_checked':len(frames),'floor_minimum_m':low,
                                'speed_m_s':clip['speed_m_s'],'duration_s':clip['duration']})
    for clip in manifest['clips']:
        bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=60
        bpy.ops.import_scene.fbx(filepath=str(base/'export/Locomotion'/(clip['name']+'.fbx')),anim_offset=0)
        rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and len(o.data.vertices)==26103)
        joint=skin=0;count=0
        for (name,frame),expected in samples.items():
            if name!=clip['name']:continue
            actual=pose(rig,frame);joint=max(joint,max((actual[n].translation-p).length for n,p in expected['joints'].items()))
            skin=max(skin,float(np.linalg.norm(coordinates(mesh)-expected['skin'],axis=1).max()));count+=1
        check(clip['name']+' FBX roundtrip same joints and skin',joint<.001 and skin<.001,{'joint_error_m':joint,'skin_error_m':skin,'samples':count})
        report['fbx_roundtrips'].append({'name':clip['name'],'samples':count,'max_joint_error_m':joint,'max_skin_error_m':skin})
    report.update(passed=not failures,failures=failures,checks_count=len(report['checks']),evaluated_skin_frames=frame_count)
    (base/'locomotion-animation-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LOCOMOTION_VALIDATION',report['passed'],report['checks_count'],frame_count,failures,flush=True)
    if failures:raise RuntimeError(', '.join(failures))


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);validate(args.base.resolve())
