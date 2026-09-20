"""Compare original/final body visibility from rear-upper and upper-side views."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent
paths=[W.parent/'player_hood_redesign_20260921/Gravebound_Rebuilt_Hood.blend',W/'Gravebound_Closed_Shoulder_Hood.blend']
body_names={'Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm'}
def load(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));vertices=[];triangles=[];owners=[];targets=[]
 for o in bpy.data.objects:
  if o.type!='MESH':continue
  m=o.data;m.calc_loop_triangles();vs=[o.matrix_world@v.co for v in m.vertices];offset=len(vertices);vertices+=vs
  for t in m.loop_triangles:triangles.append(tuple(offset+i for i in t.vertices));owners.append(o.name)
  if o.name in body_names:
   for p in vs:
    if .075<=abs(p.x)<=.25 and -.125<=p.y<=.14 and 1.36<=p.z<=1.48:targets.append(p)
 return BVHTree.FromPolygons(vertices,triangles,all_triangles=True),owners,targets
before,bo,targets=load(paths[0]);after,ao,_=load(paths[1])
targets=list({tuple(round(c,5) for c in p):p for p in targets}.values())
views=[('rear_left_upper',(-.45,-.65,1.85)),('rear_upper',(0,-.70,1.85)),('rear_right_upper',(.45,-.65,1.85)),('left_side_upper',(-.60,-.05,1.78)),('right_side_upper',(.60,-.05,1.78))]
rows=[];still=[];fixed=[]
for name,position in views:
 cam=Vector(position);counts={'view':name,'camera':position,'sampled_rays':len(targets),'before_body_visible':0,'after_body_visible':0,'formerly_exposed_now_covered':0,'newly_exposed':0}
 for target in targets:
  d=target-cam;length=d.length
  p,n,i,dist=before.ray_cast(cam,d.normalized(),length+.001)
  q,no,j,d2=after.ray_cast(cam,d.normalized(),length+.001)
  before_body=i is not None and bo[i] in body_names
  after_body=j is not None and ao[j] in body_names
  counts['before_body_visible']+=before_body;counts['after_body_visible']+=after_body
  if before_body and not after_body:counts['formerly_exposed_now_covered']+=1;fixed.append({'view':name,'old_visible':list(p),'new_hit':ao[j] if j is not None else None})
  if after_body:
   r={'view':name,'target':list(target),'visible_point':list(q),'object':ao[j],'previously_visible':before_body}
   still.append(r)
   if not before_body:counts['newly_exposed']+=1
 rows.append(counts)
report={'source_blend_sha256':hashlib.sha256(paths[0].read_bytes()).hexdigest(),'final_blend_sha256':hashlib.sha256(paths[1].read_bytes()).hexdigest(),'audit_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'unique_upper_shoulder_targets':len(targets),'views':rows,'remaining_visible_samples':still,'fixed_count':len(fixed),'judgment_note':'Remaining body samples can lie below the natural mantle hem; assess visible_point heights/angles before classifying as gaps.'}
report['remaining_torso_visibility']=sum(r['object']=='Gravebound_QuiltedTorso' for r in still)
report['newly_exposed_total']=sum(r['newly_exposed'] for r in rows)
report['remaining_visible_region']={'abs_x_m':[min(abs(r['visible_point'][0]) for r in still),max(abs(r['visible_point'][0]) for r in still)],'height_m':[min(r['visible_point'][2] for r in still),max(r['visible_point'][2] for r in still)]} if still else None
report['pass']=report['remaining_torso_visibility']==0 and report['newly_exposed_total']==0 and all(r['visible_point'][2]<1.40 and abs(r['visible_point'][0])>.225 for r in still)
(W/'oblique_report.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'targets':len(targets),'views':rows,'fixed_count':len(fixed),'remaining_count':len(still),'remaining_torso_visibility':report['remaining_torso_visibility'],'newly_exposed_total':report['newly_exposed_total'],'remaining_visible_region':report['remaining_visible_region'],'pass':report['pass']},indent=2))

assert report["pass"]
