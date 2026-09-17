import json,math
from pathlib import Path
from mathutils import Vector as V, Quaternion, Euler, Matrix
root=Path(__file__).resolve().parent
m=json.loads((root/'iteration_03/motion_manifest.json').read_text())
def elbow(p,q):
 g=p+q@V((.18,.015,.1287358));top=p+q@V((.1841,.07361,.10167));bottom=p+q@V((.1759,-.04361,.10073));st=p+q@V((-.13,-.005,.1114568)) - q@V((0,0,.04))
 x=(top-bottom).normalized();back=st-g;back=(back-x*back.dot(x)).normalized();b=Matrix((x,back.cross(x),back)).transposed();w=g-b@V((0,-.019,-.0825));return w+(st-w).normalized()*.34
candidates=[]
for x in [-.25,-.3,-.35,-.4,-.45]:
 for y in [-.50,-.55,-.6,-.65]:
  for z in [-.2,-.25,-.3]:
   for pitch in [-85,-65,55,65,80,90]:
    for yaw in [0,30,55,75,85]:
     p=V((x,y,z));q=Euler(tuple(math.radians(a) for a in (pitch,yaw,-10)),'YXZ').to_quaternion();length=(elbow(p,q)-V((-.29,-.34,.1))).length
     ys=[]
     for a in range(0,360,10):
      pt=p+q@V((.427*math.cos(math.radians(a)),.427*math.sin(math.radians(a)),0));ys.append(.5-pt.y/(2*max(.01,-pt.z)*math.tan(math.radians(76/2))))
     if length<.46 and min(ys)>1.04:candidates.append((length,min(ys),list(p),(pitch,yaw,-10)))
print('CANDIDATES',sorted(candidates,key=lambda a:abs(a[0]-.4))[:8])
for k,c in m['clips'].items():
 vals=[]
 for e in c['tracks']['shield']:
  q=e['rotation_xyzw']; vals.append(((elbow(V(e['position']),Quaternion((q[3],q[0],q[1],q[2])))-V((-.29,-.34,.1))).length,e['time_seconds']))
 print(k,max(vals))
