"""Read-only source geometry and authored motion analysis. No game execution."""
import bisect,hashlib,json,math,struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1].parent
OUTPUT=Path(__file__).resolve().parent
MODEL=ROOT/'godot-game/assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb'
MANIFEST=ROOT/'godot-game/assets/animations/reference_sword_motion/motion_manifest.json'

def add(a,b):return [x+y for x,y in zip(a,b)]
def sub(a,b):return [x-y for x,y in zip(a,b)]
def mul(a,s):return [x*s for x in a]
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def norm(a):return math.sqrt(dot(a,a))
def unit(a):return mul(a,1/norm(a)) if norm(a)>1e-12 else [0]*len(a)
def lerp(a,b,t):return add(mul(a,1-t),mul(b,t))
def mm(a,b):return [[sum(a[i][k]*b[k][j] for k in range(len(b))) for j in range(len(b[0]))] for i in range(len(a))]
def mv(m,v):return [dot(row,v) for row in m]
def qm(a,b):return [a[3]*b[0]+a[0]*b[3]+a[1]*b[2]-a[2]*b[1],a[3]*b[1]-a[0]*b[2]+a[1]*b[3]+a[2]*b[0],a[3]*b[2]+a[0]*b[1]-a[1]*b[0]+a[2]*b[3],a[3]*b[3]-dot(a[:3],b[:3])]
def qi(a):return [-a[0],-a[1],-a[2],a[3]]
def qmatrix(q):
 x,y,z,w=unit(q)
 return [[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]]
def qs(a,b,t):
 a=unit(a);b=unit(b);d=dot(a,b)
 if d<0:b=mul(b,-1);d=-d
 if d>.999999:return unit(lerp(a,b,t))
 theta=math.acos(max(-1,min(1,d)));return add(mul(a,math.sin((1-t)*theta)/math.sin(theta)),mul(b,math.sin(t*theta)/math.sin(theta)))
def qlog(q):
 if q[3]<0:q=mul(q,-1)
 length=norm(q[:3]);return mul(q[:3],2*math.atan2(length,q[3])/length) if length>1e-8 else [0,0,0]
def qexp(v):
 a=norm(v);return add(mul(v,math.sin(a/2)/a),[0,0,0])+[math.cos(a/2)] if a>1e-8 else [0,0,0,1]
def qvelocity(a,b,c,before,after):
 if min(before,after)<=1e-7:return [0,0,0]
 return mul(add(mul(qlog(qm(qi(b),a)),-after/before),mul(qlog(qm(qi(b),c)),before/after)),1/(before+after))
def cubic(a,b,pre,post,t,bt,pret,postt):
 at=t*bt
 a1=lerp(pre,a,0 if pret==0 else (at-pret)/-pret)
 a2=lerp(a,b,at/bt)
 a3=lerp(b,post,1 if postt-bt==0 else (at-bt)/(postt-bt))
 b1=lerp(a1,a2,(at-pret)/(bt-pret))
 b2=lerp(a2,a3,at/postt)
 return lerp(b1,b2,at/bt)
def transform(node):
 if 'matrix' in node:return [node['matrix'][i::4] for i in range(4)]
 rotation=qmatrix(node.get('rotation',[0,0,0,1]));scale=node.get('scale',[1,1,1]);position=node.get('translation',[0,0,0])
 return [[rotation[i][j]*scale[j] for j in range(3)]+[position[i]] for i in range(3)]+[[0,0,0,1]]
def inverse3(m):
 columns=[list(c) for c in zip(*m)];det=dot(columns[0],cross(columns[1],columns[2]))
 return [mul(cross(columns[1],columns[2]),1/det),mul(cross(columns[2],columns[0]),1/det),mul(cross(columns[0],columns[1]),1/det)]

raw=MODEL.read_bytes();length=struct.unpack_from('<I',raw,12)[0];gltf=json.loads(raw[20:20+length]);binary=raw[28+length:]
def accessor(i):
 a=gltf['accessors'][i];v=gltf['bufferViews'][a['bufferView']];components={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];fmt={5126:'f',5125:'I',5123:'H',5121:'B'}[a['componentType']];size=struct.calcsize('<'+fmt*components);offset=v.get('byteOffset',0)+a.get('byteOffset',0);stride=v.get('byteStride',size)
 return [list(struct.unpack_from('<'+fmt*components,binary,offset+j*stride)) for j in range(a['count'])]
world={}
def walk(index,parent):
 world[index]=mm(parent,transform(gltf['nodes'][index]))
 for child in gltf['nodes'][index].get('children',[]):walk(child,world[index])
identity=[[1 if i==j else 0 for j in range(4)] for i in range(4)]
for node in gltf['scenes'][gltf.get('scene',0)]['nodes']:walk(node,identity)
ready=[[.6734562112,.1384824613,-.7261403196],[-.1673592395,.9853534854,.0327005009],[.7200327879,.0995039315,.6867691389]]
ready_p=[.3249563841,-.0035816696,-.5892537756];ready_inverse=inverse3(ready)
node_index=next(i for i,n in enumerate(gltf['nodes']) if n.get('name')=='Sword_PittedBlade')
primitives=gltf['meshes'][gltf['nodes'][node_index]['mesh']]['primitives']
vertices=[];indices=[]
for primitive in primitives:
 offset=len(vertices)
 vertices.extend(mv(ready_inverse,sub(mv(world[node_index],point+[1])[:3],ready_p)) for point in accessor(primitive['attributes']['POSITION']))
 indices.extend(offset+int(v[0]) for v in accessor(primitive['indices']))
minimum=[min(v[j] for v in vertices) for j in range(3)];maximum=[max(v[j] for v in vertices) for j in range(3)];center=mul(add(minimum,maximum),.5)
normal_area=[0,0,0];surface_area=0
for i in range(0,len(indices),3):
 a,b,c=[vertices[j] for j in indices[i:i+3]];twice_normal=cross(sub(b,a),sub(c,a));surface_area+=norm(twice_normal)*.5;normal_area=add(normal_area,mul([abs(v) for v in twice_normal],.5))
geometry={'primitive_count':len(primitives),'vertex_count':len(vertices),'triangle_count':len(indices)//3,'minimum':minimum,'maximum':maximum,'size':sub(maximum,minimum),'center':center,'area_weighted_absolute_face_normal_components':mul(normal_area,1/surface_area)}
manifest=json.loads(MANIFEST.read_text());clip=manifest['clips']['right_diagonal'];samples=clip['tracks']['sword'];times=[f['time_seconds'] for f in samples]
def sample(t):
 lower=max(0,min(len(samples)-2,bisect.bisect_right(times,t)-1));upper=lower+1;a=samples[lower];b=samples[upper];pre=samples[max(0,lower-1)];post=samples[min(len(samples)-1,upper+1)]
 interval=b['time_seconds']-a['time_seconds'];amount=(t-a['time_seconds'])/interval;pret=pre['time_seconds']-a['time_seconds'];postt=post['time_seconds']-a['time_seconds']
 if abs(t-a['time_seconds'])<1e-12:return a['position'],unit(a['rotation_xyzw'])
 position=cubic(a['position'],b['position'],pre['position'],post['position'],amount,interval,pret,postt)
 qa,qb=unit(a['rotation_xyzw']),unit(b['rotation_xyzw']);va=qvelocity(unit(pre['rotation_xyzw']),qa,qb,-pret,interval);vb=qvelocity(qa,qb,unit(post['rotation_xyzw']),interval,postt-interval)
 ca=qm(qa,qexp(mul(va,interval/3)));cb=qm(qb,qexp(mul(vb,-interval/3)));ab=qs(qa,ca,amount);bc=qs(ca,cb,amount);cd=qs(cb,qb,amount);rotation=qs(qs(ab,bc,amount),qs(bc,cd,amount),amount)
 return position,rotation
def point_at(t,point):
 p,q=sample(t);return add(p,mv(qmatrix(q),point))
results=[]
for t in [.62,.71,.80]:
 p,q=sample(t);matrix=qmatrix(q);axes=[list(c) for c in zip(*matrix)];x,y,z=axes;row={'authored_seconds':t,'position':p,'length_axis_y':y,'edge_width_axis_x':x,'face_normal_z':z,'blade_length_angle_to_camera_horizontal_degrees':math.degrees(math.asin(abs(y[1]))),'points':{}}
 for name,point in [('grip',[0,-.108,.002]),('blade_center',center),('blade_65cm',[0,.65,0]),('blade_tip',[0,maximum[1],0])]:
  h=.0001;velocity=mul(sub(point_at(t+h,point),point_at(t-h,point)),1/(2*h));along=dot(velocity,y);perp=sub(velocity,mul(y,along));a=dot(perp,x);b=dot(perp,z);angle=math.degrees(math.acos(max(-1,min(1,abs(dot(unit(perp),x)))))) if norm(perp)>1e-5 else None;roll=math.degrees(math.atan2(-b,a));roll=(roll+90)%180-90
  row['points'][name]={'position':point_at(t,point),'velocity_m_per_authored_s':velocity,'speed':norm(velocity),'axial_velocity':along,'transverse_speed':norm(perp),'velocity_local_xyz':mv([x,y,z],velocity),'edge_misalignment_degrees':angle,'minimum_longitudinal_roll_degrees':roll if norm(perp)>1e-5 else None,'flat_normal_velocity_fraction':abs(dot(unit(velocity),z)) if norm(velocity)>1e-5 else None}
 results.append(row)
report={'model_sha256':hashlib.sha256(raw).hexdigest(),'manifest_sha256':hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),'method':'Actual GLB accessor vertices through source node hierarchy and production SOURCE_READY inverse; authored camera-space interpolation matches reference_sword_motion.gd, central finite difference h=0.0001 authored seconds. No game/test/render execution.','geometry':geometry,'timing':clip['timing'],'samples':results}
(OUTPUT/'geometry_motion_analysis.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
