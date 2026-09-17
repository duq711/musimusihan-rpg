import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Quaternion
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'exports/Sword_Recovery_Fix_20260913/baseline/assets/animations/reference_sword_motion/motion_manifest.json'
OUT=Path(__file__).resolve().parent
j=json.loads(SOURCE.read_text());W=Vector((.0679751875,-.1080001335,.0524637313));SH=Vector((.29,-.34,.10))
def arm(p,q):
 wrist=p+q@W; off=wrist-SH;axis=off.normalized();reach=max(.081,min(.595,off.length));shoulder=wrist-axis*reach
 hint=Vector((.70,-.70,.23));bend=(hint-axis*hint.dot(axis)).normalized();along=(.34**2-.26**2+reach**2)/(2*reach)
 elbow=shoulder+axis*along+bend*math.sqrt(max(0,.34**2-along**2))
 return {k:list(v) for k,v in [('shoulder',shoulder),('elbow',elbow),('wrist',wrist)]}
def quat(s):
 q=s['rotation_xyzw'];return Quaternion((q[3],*q[:3]))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps=120
for name in ['right_diagonal','left_reverse']:
 clip=j['clips'][name];samples=clip['tracks']['sword'];end=clip['duration_seconds'];start=end-.12
 first=min(samples,key=lambda s:abs(s['time_seconds']-start));qa=quat(first);qb=quat(samples[-1]);qb.make_compatible(qa)
 obj=bpy.data.objects.new(name+'_corrected_recovery',None);bpy.context.collection.objects.link(obj);obj.rotation_mode='QUATERNION'
 for idx,s in enumerate(samples):
  t=s['time_seconds']
  if t>start+1e-8:
   u=min(1,max(0,(t-start)/.12));u=u*u*(3-2*u);q=qa.slerp(qb,u).normalized();s['rotation_xyzw']=[q.x,q.y,q.z,q.w]
   joints=arm(Vector(s['position']),q);joints['time_seconds']=t;clip['right_arm'][idx]=joints
  obj.location=s['position'];obj.rotation_quaternion=quat(s);obj.keyframe_insert('location',frame=t*120+1);obj.keyframe_insert('rotation_quaternion',frame=t*120+1)
j['recovery_correction']={'date':'2026-09-13','execution_os':'Darwin','blender_version':bpy.app.version_string,'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'clips':['right_diagonal','left_reverse'],'changed':'last 0.12s shortest-arc rotation plus dependent right-arm joints; positions, hit timing, equip and other tracks unchanged'}
bpy.context.scene.frame_end=172
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Recovery_Corrected.blend'))
(OUT/'motion_manifest.json').write_text(json.dumps(j,separators=(',',':')))
print('RECOVERY AUTHOR PASS')
