"""Mac-only non-destructive forehand tail: horizontal continuation, hidden reset."""
import copy, importlib.util, json, math, platform, hashlib
from pathlib import Path
import bpy
from mathutils import Vector, Quaternion
ROOT=Path(__file__).resolve().parent
PROJECT=ROOT.parent.parent
spec=importlib.util.spec_from_file_location('rig_helpers',PROJECT/'asset-staging/sword_forehand_mirror_reverse_20260913/author_mirror.py')
rig=importlib.util.module_from_spec(spec);spec.loader.exec_module(rig)
assert platform.system()=='Darwin'
source=ROOT/'baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json'
original=json.loads(source.read_text()); data=copy.deepcopy(original)
cut=data['clips']['right_diagonal']; rows=cut['tracks']['sword']
anchor=next(r for r in rows if r['time_seconds']==.71)
p0,q0=rig.pose(anchor); g0=p0+q0@rig.GRIP
ready_p,ready_q=rig.pose(data['clips']['idle']['tracks']['sword'][0]); ready_g=ready_p+ready_q@rig.GRIP
prior=next(r for r in rows if r['time_seconds']==.7)
pp,pq=rig.pose(prior); velocity=(g0-(pp+pq@rig.GRIP))/.01
end_g=Vector((-1.30,g0.y-.025,g0.z))
end_q=(Quaternion(Vector((0,1,0)),math.radians(110))@q0).normalized()
low_g=Vector((end_g.x,-2.0,ready_g.z)); low_ready=Vector((ready_g.x,-2.0,ready_g.z))
# First control retains incoming leftward grip speed; zero end tangent.
c1=g0+velocity*(.09/3); c1.x=max(end_g.x,min(g0.x,c1.x))
c1.y=g0.y;c1.z=g0.z
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
controls={n:rig.make_control('Forehand_'+n) for n in ['sword','grip','shoulder','elbow','wrist']}
previous=Vector((0,0,0)); previous_q=None; changed=0; max_length=0
for i,row in enumerate(rows):
 t=row['time_seconds'];p,q=rig.pose(row)
 if t>.71:
  if t<=.8:
   u=(t-.71)/.09
   g=(1-u)**3*g0+3*(1-u)**2*u*c1+3*(1-u)*u*u*end_g+u**3*end_g
   q=(Quaternion(Vector((0,1,0)),math.radians(110)*rig.smooth(u))@q0).normalized()
  elif t<=.90:
   g=end_g.lerp(low_g,rig.smooth((t-.80)/.10));q=end_q.copy()
  elif t<=1.20:
   u=rig.smooth((t-.90)/.30);g=low_g.lerp(low_ready,u);q=end_q.slerp(ready_q,rig.smooth((t-.90)/.275))
  else:
   g=low_ready.lerp(ready_g,rig.smooth((t-1.20)/.22));q=ready_q.copy()
  p=g-q@rig.GRIP
  if t==1.42:p,q=ready_p.copy(),ready_q.copy()
  if previous_q is not None and previous_q.dot(q)<0:q.negate()
  row['position']=list(p);row['rotation_xyzw']=[q.x,q.y,q.z,q.w]
  a=cut['right_arm'][i];wrist=p+q@rig.WRIST
  # Original shoulder and original elbow hint, followed by the same fixed-length fit.
  solved=rig.solve_arm(Vector((.29,-.34,.10)),Vector(a['elbow']),wrist,previous)
  previous=solved['bend'].copy()
  cut['right_arm'][i]={'time_seconds':t,**{n:list(solved[n]) for n in ['shoulder','elbow','wrist']}}
  max_length=max(max_length,abs((solved['shoulder']-solved['elbow']).length-rig.UPPER),abs((solved['elbow']-solved['wrist']).length-rig.FOREARM));changed+=1
 previous_q=q.copy()
 a=cut['right_arm'][i]
 for name in ['sword','grip','shoulder','elbow','wrist']:
  obj=controls[name];obj.location=p if name=='sword' else p+q@rig.GRIP if name=='grip' else Vector(a[name]);obj.keyframe_insert('location',frame=t*120+1)
  if name=='sword':obj.rotation_quaternion=q;obj.keyframe_insert('rotation_quaternion',frame=t*120+1)
assert max_length<2e-6
assert all(data['clips'][k]==v for k,v in original['clips'].items() if k!='right_diagonal')
assert cut['tracks']['shield']==original['clips']['right_diagonal']['tracks']['shield']
assert all(r==s for r,s in zip(rows,original['clips']['right_diagonal']['tracks']['sword']) if r['time_seconds']<=.71)
scene=bpy.context.scene;scene.render.fps=120;scene.frame_end=172
scene['description']='Preserved forehand through contact .71s; same horizontal swing continues left through .80s; lower and reorient outside view, then lift without wrist turn.'
out=ROOT/'candidate_02';out.mkdir(exist_ok=True)
(out/'motion_manifest.json').write_text(json.dumps(data,separators=(',',':')))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'Forehand_Followthrough.blend'))
qa={'changed_keys':changed,'unchanged_sword_keys_through_source_seconds':.71,'other_clips_unchanged':True,'shield_unchanged':True,'arm_max_length_error_m':max_length,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256((out/'motion_manifest.json').read_bytes()).hexdigest(),'end_to_ready_angle_degrees':math.degrees(rig.rotation_distance(end_q,ready_q)),'note':'Source control validation only; actual Godot viewport and interpolation require separate inspection.'}
(out/'qa.json').write_text(json.dumps(qa,indent=2)+'\n');print('FOLLOWTHROUGH AUTHOR PASS',json.dumps(qa))
