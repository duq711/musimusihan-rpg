"""Read-only skinned gallop stability audit; visual naturalness is accepted separately against the supplied photo. Run in Mac Blender."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy
from mathutils import Vector
p=argparse.ArgumentParser();p.add_argument('--blend',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--hz',type=int,default=120);p.add_argument('--manifest',type=Path)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:]);bpy.ops.wm.open_mainfile(filepath=str(a.blend))
sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet import set_action
rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
mesh=next(o for o in bpy.data.objects if o.type=='MESH' and 'FF.L_46' in o.vertex_groups)
feet={'LF':'FF.L_46','RF':'FF.R_50','LH':'FFB.L_44','RH':'FFB.R_48'}
ankles={'LF':'IKFrontLeg.L_47','RF':'IKFrontLeg.R_51','LH':'IKBackLeg.L_45','RH':'IKBackLeg.R_49'}
manifest=json.loads(a.manifest.read_text()) if a.manifest else {};specs={c['name']:c for c in manifest.get('clips',[])}
indices={};soles={};rigid_soles={}
for key,name in feet.items():
 groups={mesh.vertex_groups[n].index for n in [name,ankles[key]]};indices[key]=[v.index for v in mesh.data.vertices if sum(g.weight for g in v.groups if g.group in groups)>.65]
 low=min(mesh.data.vertices[i].co.z for i in indices[key]);soles[key]=[i for i in indices[key] if mesh.data.vertices[i].co.z <= low+.10]
 rigid_soles[key]=[i for i in soles[key] if sum(g.weight for g in mesh.data.vertices[i].groups if g.group in groups)>=.95]
chains={'front.L':['FrontUpperLeg.L_17','FrontLowerLeg.L_16','IKFrontLeg.L_47'],'front.R':['FrontUpperLeg.R_20','FrontLowerLeg.R_19','IKFrontLeg.R_51'],'hind.L':['BackLeg.L_26','BackUpperLeg.L_25','BackLowerLeg.L_24','IKBackLeg.L_45'],'hind.R':['BackLeg.R_30','BackUpperLeg.R_29','BackLowerLeg.R_28','IKBackLeg.R_49']}
fps=bpy.context.scene.render.fps/bpy.context.scene.render.fps_base
out={'scope':'Anatomical foot mask: ankle plus toe influence >65%, including heel. New Run-only read-only skin audit. This checks numerical geometry/contact only and is not a substitute for reference-based visual naturalness acceptance.','blend':str(a.blend),'blend_sha256':hashlib.sha256(a.blend.read_bytes()).hexdigest(),'manifest_sha256':hashlib.sha256(a.manifest.read_bytes()).hexdigest() if a.manifest else None,'fps':fps,'sample_hz':a.hz,'clips':[]}
for action in bpy.data.actions:
 if action.name != 'Run':continue
 set_action(rig,action);start,end=action.frame_range;duration=(end-start)/fps;n=round(duration*a.hz);rows=[]
 for j in range(n+1):
  frame=start+(end-start)*j/n;bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();ev=mesh.evaluated_get(dg);data=ev.to_mesh()
  world=ev.matrix_world;pos={k:[world@data.vertices[i].co for i in ids] for k,ids in indices.items()}
  row={'phase':j/n,'complete_body_floor_m':min((world@v.co).z for v in data.vertices),'feet':{k:{'floor':min(v.z for v in points),'centroid':list(sum(points,Vector())/len(points)),'sole_centroid':list(sum((world@data.vertices[i].co for i in soles[k]),Vector())/len(soles[k])),'rigid_sole_centroid':list(sum((world@data.vertices[i].co for i in rigid_soles[k]),Vector())/len(rigid_soles[k])) if rigid_soles[k] else None} for k,points in pos.items()},'angle':{},'sign':{},'lengths':{},'bones':{}}
  for key,names in chains.items():
   pts=[rig.pose.bones[name].matrix.translation.copy() for name in names]
   row['lengths'][key]=[(q-p).length for p,q in zip(pts,pts[1:])]
   for i in range(1,len(pts)-1):
    u=pts[i-1]-pts[i];v=pts[i+1]-pts[i];joint=names[i];row['angle'][joint]=math.degrees(u.angle(v));row['sign'][joint]=u.cross(v).x
  row['bones']={name:list(rig.matrix_world@rig.pose.bones[name].matrix.translation) for name in ['Back_38','Torso3_15','Head_1']}
  ev.to_mesh_clear();rows.append(row)
 entry={'name':action.name,'duration_s':duration,'samples':len(rows),'limb_angles_deg':{},'sagittal_bend_sign':{},'segment_length_max_variation_m':{},'skin_floor_m':{},'loop_delta':{},'phase_samples':[]}
 for name in rows[0]['angle']:
  values=[r['angle'][name] for r in rows];sgn=[r['sign'][name] for r in rows];entry['limb_angles_deg'][name]=[min(values),max(values)];entry['sagittal_bend_sign'][name]=[min(sgn),max(sgn)]
 for key,lens in rows[0]['lengths'].items():entry['segment_length_max_variation_m'][key]=[(max(r['lengths'][key][i] for r in rows)-min(r['lengths'][key][i] for r in rows))*sum(rig.matrix_world.to_scale())/3 for i in range(len(lens))]
 for key in feet:
  f=[r['feet'][key] for r in rows];c=[Vector(v['centroid']) for v in f];entry['skin_floor_m'][key]={'min':min(v['floor'] for v in f),'max':max(v['floor'] for v in f),'near_floor_fraction':sum(v['floor']<=.004 for v in f[:-1])/n}
  deltas=[(y-x).length for x,y in zip(c,c[1:])];worst=deltas.index(max(deltas));entry['loop_delta'][key]={'max_step_phase':[worst/n,(worst+1)/n],'centroid_m':(c[-1]-c[0]).length,'floor_m':abs(f[-1]['floor']-f[0]['floor']),'velocity_seam_m_s':((c[1]-c[0])-(c[-1]-c[-2])).length*a.hz,'max_step_m':max((y-x).length for x,y in zip(c,c[1:]))}
 spec=specs.get(action.name,{})
 if spec.get('contact_phases'):
  entry['supported_skin_slip']={}
  forward=(rig.matrix_world.to_3x3()@Vector((0,-1,0))).normalized();speed=spec['speed_m_s']
  for key,limb in [('LF','front.L'),('RF','front.R'),('LH','hind.L'),('RH','hind.R')]:
   begin,finish=spec['contact_phases'][limb];samples=[]
   for step in range(math.ceil(begin*n+1),math.floor(finish*n)):
    idx=step%n;r=rows[idx]['feet'][key];time=step/n*duration;samples.append((r,time))
   metrics={'stance_phase':[begin,finish],'samples':len(samples),'weighted_sole_vertices':len(soles[key]),'rigid_sole_vertices':len(rigid_soles[key]),'speed_m_s':speed,'method':f'Skin positions at {a.hz} Hz, interior support phases; translate model forward by declared speed. Same fixed sole vertices followed, avoiding lowest-point identity swaps.'}
   if samples:
    metrics['skin_floor_range_m']=[min(r['floor'] for r,t in samples),max(r['floor'] for r,t in samples)]
    for field in ['sole_centroid','rigid_sole_centroid']:
     if samples[0][0][field] is None:continue
     positions=[Vector(r[field])+forward*speed*t for r,t in samples];origin=positions[0];metrics[field+'_max_drift_m']=max((q-origin).length for q in positions);metrics[field+'_end_drift_m']=(positions[-1]-origin).length
   entry['supported_skin_slip'][key]=metrics
 def quaternion_pose(frame):
  bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update();return {b.name:b.matrix.to_quaternion().normalized() for b in rig.pose.bones}
 seam_frames=[start,start+.1,end-.1,end];quats=[quaternion_pose(f) for f in seam_frames]
 def angular_velocity(before,after,dt):
  dq=after@before.inverted();dq.normalize()
  if dq.w<0:dq.negate()
  v=Vector((dq.x,dq.y,dq.z));magnitude=v.length
  return v*(2*math.atan2(magnitude,dq.w)/magnitude/dt) if magnitude>1e-14 else Vector()
 dt=.1/fps;angular=[]
 for name in quats[0]:
  before=angular_velocity(quats[2][name],quats[3][name],dt);after=angular_velocity(quats[0][name],quats[1][name],dt)
  angular.append({'bone':name,'velocity_delta_deg_s':math.degrees((after-before).length),'before_deg_s':math.degrees(before.length),'after_deg_s':math.degrees(after.length)})
 entry['loop_angular_velocity_probe']={'method':'Signed quaternion delta log using2*atan2(length(xyz),w), normalized and hemisphere aligned. Sample0.1frame one-sided atbothseams.','max_delta_deg_s':max(r['velocity_delta_deg_s'] for r in angular),'worst_five':sorted(angular,key=lambda r:-r['velocity_delta_deg_s'])[:5]}
 entry['complete_body_floor_m']={'min':min(r['complete_body_floor_m'] for r in rows),'max':max(r['complete_body_floor_m'] for r in rows)}
 entry['skin_flight']={'threshold_m':.005,'phases':[r['phase'] for r in rows[:-1] if all(v['floor']>.005 for v in r['feet'].values())],'max_four_paw_clearance_m':max(min(v['floor'] for v in r['feet'].values()) for r in rows)}
 entry['contact_timeline']=[{'phase':r['phase'],'foot_floor_m':{k:v['floor'] for k,v in r['feet'].items()}} for r in rows]
 entry['body_vertical_m']={name:[min(r['bones'][name][2] for r in rows),max(r['bones'][name][2] for r in rows)] for name in rows[0]['bones']}
 entry['phase_samples']=[{k:v for k,v in rows[round(j*n/8)].items() if k!='lengths'} for j in range(9)]
 out['clips'].append(entry)
out['review_status']='Numerical geometry and supported-skin audit; rendered-skin visual review is reported separately.'
out['limits']=['Support timing follows inspected capture phases after proportion fitting; force/pressure is not measured.','Slip is tested at the manifest speed on level ground, independent of Unity or gameplay pathfinding.','Sole centroids are sampled skin vertices, not a biomechanical pressure centroid.','Floor contact and loop velocity may have small bounded residuals; do not claim absolute zero skating.']
a.report.parent.mkdir(parents=True,exist_ok=True);a.report.write_text(json.dumps(out,indent=2)+'\n');print('INDEPENDENT_AUDIT',a.report)
