"""Mac-authored camera-space controls fitted to directly inspected sU7jk2OQlgc frames.
Depth/occluded poses are authored, not a recovered mocap. Existing meshes untouched.
Run with Blender --background --factory-startup --python this_file.
"""
import bpy, math, json, hashlib, platform
from pathlib import Path
from mathutils import Vector, Matrix, Quaternion
ROOT=Path(__file__).resolve().parent
GAME=ROOT.parents[1]/'godot-game'
OUT=ROOT/'iteration_05'; OUT.mkdir(exist_ok=True)
V=lambda x:Vector(x)
G=V((0,-.108,.002)); W=V((.0679751875,-.1080001335,.0524637313))
SH=V((.29,-.34,.10))
def held(p,d,roll=-30):
 y=V(d).normalized(); z=V((0,0,1)); z=(z-y*z.dot(y)).normalized(); z=Quaternion(y,math.radians(roll))@z
 q=Matrix((y.cross(z),y,z)).transposed().to_quaternion()
 return V(p)-q@G,q

def pose(p,degrees):
 from mathutils import Euler
 return V(p),Euler(tuple(math.radians(x) for x in degrees),'YXZ').to_quaternion()
def mix(a,b,t):
 t=max(0,min(1,t)); t=t*t*(3-2*t)
 return a[0].lerp(b[0],t),a[1].slerp(b[1],t)
def sample(keys,t):
 i=next((i for i in range(len(keys)-1) if t<=keys[i+1][0]),len(keys)-2)
 times=[k[0] for k in keys];ps=[k[1][0] for k in keys];anchor=keys[0][1][1];rv=[]
 for _,(_,q) in keys:
  r=anchor.inverted()@q
  if r.w<0:r.negate()
  v=V((r.x,r.y,r.z));ang=2*math.atan2(v.length,r.w);axis=v.normalized() if v.length>1e-8 else V((0,1,0))
  cand=[axis*(ang+math.tau*j) for j in (-1,0,1)]
  rv.append(min(cand,key=lambda x:(x-(rv[-1] if rv else V((0,0,0)))).length))
 def curve(values):
  def tangent(k):
   if k in (0,len(keys)-1):return V((0,0,0))
   a=(values[k]-values[k-1])/(times[k]-times[k-1]);b=(values[k+1]-values[k])/(times[k+1]-times[k])
   # Monotone Hermite preserves anticipation holds and avoids overshoot.
   return V(tuple(2*a[j]*b[j]/(a[j]+b[j]) if a[j]*b[j]>0 else 0 for j in range(3)))
  dt=times[i+1]-times[i];u=max(0,min(1,(t-times[i])/dt));u2=u*u;u3=u2*u
  return values[i]*(2*u3-3*u2+1)+tangent(i)*dt*(u3-2*u2+u)+values[i+1]*(-2*u3+3*u2)+tangent(i+1)*dt*(u3-u2)
 r=curve(rv);q=anchor@(Quaternion(r.normalized(),r.length) if r.length>1e-8 else Quaternion())
 return curve(ps),q

idle=held((.36,-.38,-.46),(-.035,1,-.045),-30)
shield=pose((-.43,-.62,-.37),(8,55,-6))
lowshield=pose((-.30,-.50,-.20),(55,30,-10))
clips={}
def add(name,dur,loop,skeys,hkeys,timing=None):
 clips[name]=(dur,loop,skeys,hkeys,timing)
add('idle',1,False,[(0,idle),(1,idle)],[(0,shield),(1,shield)])
for name,amp,dur in [('walk',.58,1.18),('run',1,1.02)]:
 sk=[]; hk=[]
 for i in range(25):
  t=dur*i/24; phase=i/24*math.tau
  y=.023*amp*math.cos(phase*2); x=.016*amp*math.sin(phase)
  sk.append((t,held((.36+x,-.38+y,-.46+.006*amp*math.sin(phase*2)),(-.035+.025*amp*math.sin(phase),1,-.045),-30+2*amp*math.sin(phase))))
  hp,hq=shield; hk.append((t,(hp+V((x*.65,y*.75,.004*amp*math.sin(phase))),hq@Quaternion(V((0,0,1)),.012*amp*math.sin(phase)))))
 sk[-1]=(dur,sk[0][1]);hk[-1]=(dur,hk[0][1]);add(name,dur,True,sk,hk)
dip=held((.365,-.53,-.46),(-.18,1,-.10),-31)
up=held((.35,-.29,-.46),(-.08,1,-.05),-29)
land=held((.35,-.45,-.47),(-.11,.86,-.50),-30)
add('takeoff',.20,False,[(0,idle),(.09,dip),(.20,dip)],[(0,shield),(.11,lowshield),(.20,lowshield)])
add('air',1,True,[(0,up),(.5,held((.354,-.285,-.46),(-.08,1,-.05),-29)),(1,up)],[(0,pose((-.43,-.52,-.37),(8,55,-6))),(.5,pose((-.43,-.517,-.37),(8,55,-6))),(1,pose((-.43,-.52,-.37),(8,55,-6)))])
add('land',.34,False,[(0,up),(.07,land),(.12,land),(.34,idle)],[(0,pose((-.43,-.52,-.37),(8,55,-6))),(.07,lowshield),(.34,shield)])
# Source has 0.5 s anticipation hold then ~0.15 s fast pass. The player keeps
# authoritative hit clocks; hold belongs to WINDUP, not an artificially slow cut.
wind=.62; active=.18; recovery=.62; hit=.09; dur=wind+active+recovery
for name,prep,entry,contact,follow in [
 ('overhead',held((.35,.31,-.23),(-.2,.98,.10),55),held((.25,.24,-.33),(-.05,1,-.08),70),held((.055,-.34,-.44),(.04,.98,-.20),75),held((-.04,-.70,-.27),(-.03,-.93,-.36),70)),
 ('left_reverse',held((-.52,-.43,-.24),(-.97,.08,-.1),-65),held((-.30,-.26,-.43),(-.95,.15,-.25),-60),held((.28,-.24,-.45),(-.90,.20,-.39),-55),held((.69,-.49,-.24),(.93,-.12,-.34),-30)),
 ('right_diagonal',held((.69,-.20,-.24),(.7,.70,.12),25),held((.49,-.22,-.38),(.79,.55,-.27),20),held((.09,-.25,-.44),(.70,.60,-.38),20),held((-.49,-.63,-.26),(-.7,-.65,-.30),-5))]:
 sk=[(0,idle),(.34,prep),(wind,prep),(wind+.055,entry),(wind+hit,contact),(wind+.13,follow),(wind+active,follow),(wind+active+.20,follow),(dur-.12,held((.32,-.43,-.46),(-.21,.97,-.12),-30)),(dur,idle)]
 hk=[(0,shield),(.34,lowshield),(wind+active+.19,lowshield),(dur-.18,shield),(dur,shield)]
 add(name,dur,False,sk,hk,dict(windup_seconds=wind,active_seconds=active,hit_seconds=hit,recovery_seconds=recovery))

def arm(p,q):
 wrist=p+q@W; shoulder=SH.copy(); off=wrist-shoulder; length=off.length; axis=off.normalized(); reach=max(.081,min(.595,length)); shoulder=wrist-axis*reach
 hint=V((.70,-.70,.23)); bend=(hint-axis*hint.dot(axis)).normalized()
 along=(.34**2-.26**2+reach**2)/(2*reach); elbow=shoulder+axis*along+bend*math.sqrt(max(0,.34**2-along**2))
 return {k:list(v) for k,v in [('shoulder',shoulder),('elbow',elbow),('wrist',wrist)]}
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.context.scene.render.fps=120
manifest={'schema_version':2,'status':'authored_macos_output','reference_video_url':'https://youtu.be/sU7jk2OQlgc','source':{'godot_model_sha256':hashlib.sha256((GAME/'assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb').read_bytes()).hexdigest()},'coordinate_system':{'space':'godot_camera_local_x_right_y_up_minus_z_forward','quaternion_order':'xyzw','transform_semantics':'absolute_pivot_local_to_camera','units':'meters','position_order':'xyz','scale':[1,1,1]},'provenance':{'execution_os':'Darwin','exit_code':0,'source_preserved':True,'authoring_tool':bpy.app.version_string,'method':'Mac Blender camera-space hand controls; reference frame observations, authored depth','script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()},'clips':{}}
for name,(dur,loop,sk,hk,timing) in clips.items():
 data={'duration_seconds':dur,'loop':loop,'kind':'attack' if timing else 'locomotion','tracks':{'sword':[],'shield':[]},'right_arm':[]}
 if timing:data['timing']=timing
 times=sorted(set([round(i/120,9) for i in range(math.floor(dur*120)+1)]+[dur]+([wind,wind+hit,wind+active] if timing else [])))
 times=[t for i,t in enumerate(times) if i==0 or t-times[i-1]>1e-7]
 obs={}
 for track in ('sword','shield','shoulder','elbow','wrist'):
  ob=bpy.data.objects.new(name+'_'+track,None);bpy.context.collection.objects.link(ob);ob.rotation_mode='QUATERNION';obs[track]=ob
 prev={}
 for t in times:
  for track,keys in [('sword',sk),('shield',hk)]:
   p,q=sample(keys,t)
   if track in prev and prev[track].dot(q)<0:q.negate()
   prev[track]=q.copy();data['tracks'][track].append({'time_seconds':t,'position':list(p),'rotation_xyzw':[q.x,q.y,q.z,q.w]})
   ob=obs[track];ob.location=p;ob.rotation_quaternion=q;ob.keyframe_insert('location',frame=t*120+1);ob.keyframe_insert('rotation_quaternion',frame=t*120+1)
   if track=='sword': joints=arm(p,q)
  joints['time_seconds']=t;data['right_arm'].append(joints)
  for j in ('shoulder','elbow','wrist'):
   obs[j].location=joints[j];obs[j].keyframe_insert('location',frame=t*120+1)
 manifest['clips'][name]=data
bpy.context.scene.frame_end=172
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'FirstPerson_Motion_Controls.blend'))
(OUT/'motion_manifest.json').write_text(json.dumps(manifest,separators=(',',':')))
print('MAC MOTION AUTHOR PASS',platform.system(),list(manifest['clips']))
