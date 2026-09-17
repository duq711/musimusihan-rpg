"""Read-only actual-mesh test of root's pivot-section candidate and bend compression."""
import json,math,struct,sys
from pathlib import Path
import numpy as np
S=Path(__file__).resolve().parents[1]
a,b=.014,.075;L=b-a;P=np.array([0.,0.,.05625]);E=np.array([0.,0.,1.]);ease_mm=float(sys.argv[1]) if len(sys.argv)>1 else 3.0
eps=ease_mm*.001/L

def unit(v):return v/np.linalg.norm(v)
def frame(x,y):
 d=unit(y-x);ref=np.array([0.,1.,0.]) if abs(d[1])<.95 else np.array([0.,0.,-1.]);u=unit(np.cross(ref,d));return np.column_stack([u,d,unit(np.cross(u,d))])
def fit(old):
 elbow=old[:,2]*.26;rest=np.array([0.,0.,.26]);s=np.linalg.norm(elbow-P)/np.linalg.norm(rest-P)
 B=frame(elbow,P)@np.diag([1,s,1])@frame(rest,P).T;return B,P-B@P

def load(side):
 blob=(S/f'mac_output/iteration_02/{side}_hand_wrist_refined.glb').read_bytes();n=struct.unpack_from('<I',blob,12)[0];d=json.loads(blob[20:20+n]);base=20+n+8
 def acc(i):
  x=d['accessors'][i];v=d['bufferViews'][x['bufferView']];k={'SCALAR':1,'VEC3':3}[x['type']];fmt={5126:'f',5123:'H',5125:'I'}[x['componentType']];width=struct.calcsize(fmt)*k;stride=v.get('byteStride',width);off=base+v.get('byteOffset',0)+x.get('byteOffset',0)
  return np.array([struct.unpack_from('<'+fmt*k,blob,off+j*stride) for j in range(x['count'])])
 mesh=next(m for m in d['meshes'] if 'Wrist' in m['name']);ps=[];fs=[];offset=0
 for p in mesh['primitives']:
  points=acc(p['attributes']['POSITION']);faces=acc(p['indices']).reshape(-1,3);ps.append(points);fs.append(faces+offset);offset+=len(points)
 return np.vstack(ps),np.vstack(fs).astype(int)

def study(points,faces,B,origin,compress):
 s=np.linalg.norm(B[:,2]);R=B@np.diag([1,1,1/s]);angle=math.acos(np.clip((np.trace(R)-1)/2,-1,1));axis=unit(np.array([R[2,1]-R[1,2],R[0,2]-R[2,0],R[1,0]-R[0,1]]))
 bend=unit(np.cross(E,axis));active=(points[:,2]>a)&(points[:,2]<b)
 bend_rmax=max(abs(points[active,:2]@bend[:2]));axial=1+(s-1)*(b-P[2])/L
 def mapper(p,details=False):
  t=np.clip((p[:,2]-a)/L,0,1);edge=np.minimum(t,1-t)
  early=(edge**3/eps**2-.5*edge**4/eps**3)/(1-eps);middle=(edge-.5*eps)/(1-eps)
  w=np.where(edge<eps,early,middle);w=np.where(t<=.5,w,1-w)
  wd=np.where(edge<eps,(3*edge**2/eps**2-2*edge**3/eps**3)/(1-eps),1/(1-eps))/L
  inside=(p[:,2]>a)&(p[:,2]<b);wd=np.where(inside,wd,0)
  anglew=angle*w;cos=np.cos(anglew)[:,None];sin=np.sin(anglew)[:,None]
  def rot(v):return v*cos+np.cross(axis,v)*sin+axis*np.sum(v*axis,axis=1)[:,None]*(1-cos)
  A=p[:,2]-P[2]+(s-1)*(b-P[2])*t;A=np.where(p[:,2]>=b,s*(p[:,2]-P[2]),A)
  Ad=np.where(inside,axial,np.where(p[:,2]>=b,s,1))
  # C1 compression: use a smooth lower envelope of1 andsafetycap; compute
  # from each section's max projected radius. This conservativeglobal bound
  # deliberately avoids relying on mesh z-ring indexing or inconsistent weights.
  K=angle*wd*np.linalg.norm(axis[:2])*bend_rmax
  if compress:
   cap=(Ad-.2)/np.maximum(K,1e-15)
   # alpha=min(1,cap), with a .1-wide Hermite easing entirely belowboth.
   u=np.clip((cap-.9)/.2,0,1)
   alpha=np.where(cap<=.9,cap,np.where(cap>=1.1,1,.9+.2*u-.1*u*u))
  else:alpha=np.ones(len(p))
  radial=p.copy();radial[:,2]=0
  radial+=((alpha-1)*(radial@bend))[:,None]*bend
  v=radial.copy();v[:,2]=A
  out=P+rot(v)
  det=alpha*(Ad+angle*wd*np.linalg.norm(axis[:2])*(radial@bend))
  return (out,det,alpha,rot(np.broadcast_to(E,p.shape))) if details else out
 out,det,alpha,unused=mapper(points,True)
 # Face normals compared to true finite-difference Jacobian at triangle center.
 center=points[faces].mean(axis=1);step=1e-6
 J=np.stack([(mapper(center+np.eye(3)[k]*step)-mapper(center-np.eye(3)[k]*step))/(2*step) for k in range(3)],axis=2)
 old_cross=np.cross(points[faces[:,1]]-points[faces[:,0]],points[faces[:,2]]-points[faces[:,0]])
 new_cross=np.cross(out[faces[:,1]]-out[faces[:,0]],out[faces[:,2]]-out[faces[:,0]])
 expected=np.linalg.solve(np.transpose(J,(0,2,1)),old_cross[:,:,None])[:,:,0]
 align=np.sum(expected*new_cross,axis=1)/(np.linalg.norm(expected,axis=1)*np.linalg.norm(new_cross,axis=1))
 fixed=points[:,2]<=a;follow=points[:,2]>=b
 return {'min_jacobian':float(det.min()),'nonpositive_vertices':int(np.sum(det<=1e-6)), 'min_width_scale':float(alpha.min()),
 'reversed_triangles':int(np.sum(align<0)), 'min_triangle_expected_alignment':float(align.min()),
 'min_triangle_area_ratio':float((np.linalg.norm(new_cross,axis=1)/np.linalg.norm(old_cross,axis=1)).min()),
 'fixed_endpoint_error_m':float(np.linalg.norm(out[fixed]-points[fixed],axis=1).max()),
 'follow_endpoint_error_m':float(np.linalg.norm(out[follow]-(points[follow]@B.T+origin),axis=1).max()),
 'maximum_section_bend_radius_m':float(bend_rmax),'rotation_degrees':math.degrees(angle),'axial_scale':float(s)}
rows=[]
for line in (S/'godot_wrist_fullfit_diagnostic02.log').read_text().splitlines():
 if 'WRIST FIT DIAGNOSTIC: ' not in line:continue
 r=json.loads(line.split('WRIST FIT DIAGNOSTIC: ',1)[1]);B,origin=fit(np.array(r['fit_basis']).T);points,faces=load('left' if r['side']<0 else 'right')
 row={'context':r['context'],'original_width':study(points,faces,B,origin,False),'compressed_bend_direction':study(points,faces,B,origin,True)}
 rows.append(row);print(json.dumps(row))
(S/('wrist_pivot_curve_active_probe_'+str(ease_mm)+'mm.json')).write_text(json.dumps({'poses':rows,'method':'Exact mesh vertices/triangles with pivot-root candidate; linear stretch g and 3mm eased rotation, conservativeglobal bend support; finite differenceJacobian faceorientation verification','limitation':'Local determinant/triangle checks do not prove no nonadjacent mesh self-intersections.'},indent=2))
