"""Read-only Run revision preservation, evaluated skin and delivered FBX QA."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import LIMBS,SOURCE_SHA,channels,pad_indices,set_action
from labrador_pet_gallop import action_hash
from labrador_pet_locomotion_validate import fingerprint,rotation_vector
from labrador_pet_validate import coordinates,pose


def validate(oldbase,base):
    m=json.loads((base/'export/gallop-manifest.json').read_text())
    report={'passed':False,'checks':[],'failures':[]};checks=report['checks'];fail=report['failures']
    def check(n,v,d=None):
        checks.append({'name':n,'passed':bool(v),'details':d})
        if not v:fail.append(n)
    check('Original download SHA preserved',hashlib.sha256((oldbase/'source/LabradorDog_kenchoo_2k.glb').read_bytes()).hexdigest()==SOURCE_SHA)
    for p,h in m['preserved_original_files_sha256'].items():
        check('Prior final binary preserved '+p,hashlib.sha256((oldbase/p).read_bytes()).hexdigest()==h)
    bpy.ops.wm.open_mainfile(filepath=str(oldbase/'production/LabradorPet_Locomotion.blend'))
    before=fingerprint(bpy.data.objects['LabradorPet_Mesh'],bpy.data.objects['LabradorPet'])
    oldrig=bpy.data.objects['LabradorPet'];set_action(oldrig,bpy.data.actions['IdleFriendly']);reference=pose(oldrig,1)
    bend_reference={}
    for k,l in LIMBS.items():
        names=l['chain']+[l['ankle']]
        for j in range(1,len(names)-1):
            a,b,c=[reference[n].translation for n in names[j-1:j+2]]
            bend_reference[k,j]=(a-b).cross(c-b).x
    bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Gallop.blend'))
    rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh'];after=fingerprint(mesh,rig)
    for k,v in before.items():check('Exact preserved '+k,after[k]==v,after[k])
    for n,h in m['preserved_action_sha256'].items():check(n+' exact previous action keys',action_hash(bpy.data.actions[n])==h)
    run=next(c for c in m['clips'] if c['name']=='Run');end=run['frames'][1]
    check('Four named clips retained',[c['name'] for c in m['clips']]==['IdleFriendly','PetEnjoy','Walk','Run'])
    check('Same 53-joint .30 metre-scale rig',len(rig.pose.bones)==53 and max(abs(v-.3) for v in rig.scale)<1e-6)
    set_action(rig,bpy.data.actions['Run'])
    check('All Run keyframe values finite',all(math.isfinite(float(v)) for c in channels(bpy.data.actions['Run']) for k in c.keyframe_points for v in k.co))
    qcurves={}
    for c in channels(bpy.data.actions['Run']):
        if c.data_path.endswith('.rotation_quaternion'):qcurves.setdefault(c.data_path,{})[c.array_index]=c
    minimum_dot=1
    for curves in qcurves.values():
        q=np.asarray([[curves[j].keyframe_points[i].co.y for j in range(4)] for i in range(len(curves[0].keyframe_points))])
        minimum_dot=min(minimum_dot,float(np.sum(q[:-1]*q[1:],axis=1).min()))
    check('Run quaternion keys share adjacent hemispheres',minimum_dot>=0,{'minimum_adjacent_dot':minimum_dot})
    pad={}
    for k,l in LIMBS.items():
        groups={mesh.vertex_groups[n].index for n in (l['paw'],l['ankle'])}
        pad[k]=np.asarray([v.index for v in mesh.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.65],dtype=int)
    samples={};finite=True;low=100;mins={k:100 for k in pad};maxs={k:-100 for k in pad};root=[];flight=[];frame_count=0;worst=None
    previous_centroids=None;maximum_step=0;flips=[]
    for frame in np.arange(1,end+.001,.5):
        matrices=pose(rig,float(frame));world=coordinates(mesh);frame_count+=1
        finite=finite and bool(np.isfinite(world).all())
        index=int(np.argmin(world[:,2]));value=float(world[index,2])
        if value<low:
            low=value;worst={'frame':float(frame),'vertex':index,'world_m':world[index].tolist(),
                             'groups':{mesh.vertex_groups[g.group].name:g.weight for g in mesh.data.vertices[index].groups}}
        floors={}
        centroids={}
        for k,inds in pad.items():
            v=float(world[inds,2].min());mins[k]=min(mins[k],v);maxs[k]=max(maxs[k],v);floors[k]=v
            centroids[k]=world[inds].mean(axis=0)
            names=LIMBS[k]['chain']+[LIMBS[k]['ankle']]
            for j in range(1,len(names)-1):
                a,b,c=[matrices[n].translation for n in names[j-1:j+2]]
                if (a-b).cross(c-b).x*bend_reference[k,j]<=0:flips.append({'limb':k,'joint':j,'frame':float(frame)})
        if previous_centroids is not None:maximum_step=max(maximum_step,max(float(np.linalg.norm(centroids[k]-previous_centroids[k])) for k in centroids))
        previous_centroids=centroids
        if min(floors.values())>.003:flight.append(float(frame))
        root.append(list(matrices['GLTF_created_0_rootJoint'].translation))
        if frame in (1,7,16,25,end):samples[int(frame)]={'skin':world.copy(),'joints':{n:x.translation.copy() for n,x in matrices.items()}}
    check('Full Run skin finite at 120Hz',finite,{'skin_samples':frame_count})
    check('Full Run skin floor tolerance 3mm',low>-.003,{'minimum_z_m':low,'tolerance_m':.003,'worst_sample':worst})
    check('Each actual paw supports and lifts',min(mins.values())>-.003 and max(mins.values())<.003 and min(maxs.values())>.03,
          {'paw_minima_m':mins,'paw_maxima_m':maxs})
    check('Actual four-paw aerial frames present',bool(flight),{'frames':flight,'threshold_m':.003})
    check('Actual elbows stifles and hocks preserve rest bend directions',not flips,{'flipped_samples':flips})
    check('No 120Hz evaluated-paw interpolation pop',maximum_step<.06,{'maximum_foot_centroid_step_m':maximum_step,'sample_interval_s':1/120})
    check('Root fixed for runtime translation',np.ptp(np.asarray(root),axis=0).max()<1e-6)
    ends=[pose(rig,f) for f in (1,1.01,end-.01,end)];pos=rot=vel=ang=0
    for n in ends[0]:
        p=[x[n] for x in ends]
        pos=max(pos,(p[0].translation-p[-1].translation).length)
        rot=max(rot,float(np.linalg.norm(rotation_vector(p[0],p[-1]))))
        vel=max(vel,((p[1].translation-p[0].translation)-(p[-1].translation-p[-2].translation)).length*6000)
        ang=max(ang,float(np.linalg.norm(rotation_vector(p[0],p[1])-rotation_vector(p[-2],p[-1])))*6000)
    check('Run loop exact pose continuity',pos<.00001 and rot<math.radians(.01),{'position_m':pos,'rotation_deg':math.degrees(rot)})
    check('Run loop tangent continuity',vel<.15 and ang<math.radians(60),{'velocity_difference_m_s':vel,'angular_velocity_difference_deg_s':math.degrees(ang)})
    authored=json.loads((base/'gallop-authoring-contact.json').read_text())['frames']
    residual=max(v['reach_residual_m'] for f in authored for v in f['feet'].values())
    check('Paw endpoint connected to actual solved lower leg',residual<.0002,{'maximum_ik_endpoint_residual_m':residual})
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.context.scene.render.fps=60
    path=base/'export/Locomotion/Run.fbx';bpy.ops.import_scene.fbx(filepath=str(path),anim_offset=0)
    rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');mesh=next(o for o in bpy.context.scene.objects if o.type=='MESH' and len(o.data.vertices)==26103)
    joint=skin=0
    for frame,v in samples.items():
        actual=pose(rig,frame);joint=max(joint,max((actual[n].translation-p).length for n,p in v['joints'].items()))
        skin=max(skin,float(np.linalg.norm(coordinates(mesh)-v['skin'],axis=1).max()))
    check('Delivered Run FBX exact sampled joints and skin',joint<.001 and skin<.001,{'samples':len(samples),'joint_max_error_m':joint,'skin_max_error_m':skin})
    report.update(passed=not fail,checks_count=len(checks),evaluated_skin_frames=frame_count,
                  fbx_roundtrip_samples=len(samples),run_speed_m_s=run['speed_m_s'],duration_s=run['duration'],
                  production_sha256=hashlib.sha256((base/'production/LabradorPet_Gallop.blend').read_bytes()).hexdigest())
    (base/'gallop-animation-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('GALLOP_VALIDATION',report['passed'],len(checks),frame_count,fail,flush=True)
    if fail:raise RuntimeError(', '.join(fail))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--old-base',type=Path,required=True);p.add_argument('--base',type=Path,required=True)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);validate(a.old_base.resolve(),a.base.resolve())
