"""Reproduce the final rear-only hand-pose surface checks without running Godot.
Uses the saved actual rig/binds export; does not alter a model or game files.
"""
import json, math, re, pathlib, hashlib, argparse
import numpy as np
ROOT=pathlib.Path(__file__).resolve().parents[4]
parser=argparse.ArgumentParser();parser.add_argument('--source',default=str(ROOT/'godot-game/scripts/sword_long_grip_visual.gd'));parser.add_argument('--rig-export',default=str(pathlib.Path(__file__).with_name('grip_rig_export.json')));parser.add_argument('--selected-pose',default=str(pathlib.Path(__file__).with_name('grip_candidate.json')));args=parser.parse_args()
SCRIPT=pathlib.Path(args.source)
J=json.load(open(args.rig_export));S=J['surfaces'][0];B=J['bones']
def mat(v):
 m=np.eye(4);m[:3,:]=np.array(v).T;return m
def rotation(axis,angle):
 a=np.array(axis,dtype=float);a/=np.linalg.norm(a);x,y,z=a;c=math.cos(angle);s=math.sin(angle);d=1-c
 return np.array([[c+x*x*d,x*y*d-z*s,x*z*d+y*s],[x*y*d+z*s,c+y*y*d,y*z*d-x*s],[x*z*d-y*s,y*z*d+x*s,c+z*z*d]])
def numbers(s):return [float(x.strip())for x in s.split(',')]
source=SCRIPT.read_text();tilt=float(re.search(r'THRUST_GRIP_DEGREES := ([\d.]+)',source)[1]);offset=np.array(numbers(re.search(r'THRUST_CONTACT_OFFSET := Vector3\((.*?)\)',source)[1]));block=re.search(r'THRUST_DIGIT_POSES := \{(.*?)\n\}',source,re.S)[1]
profiles={d:{'angles':numbers(a),'axis':numbers(ax),'lateral':float(r)}for d,a,ax,r in re.findall(r'"(\w+)": \[Vector3\((.*?)\), Vector3\((.*?)\), ([\d.-]+)\]',block)}
poses=np.array([mat(b['pose'])for b in B]);rests=np.array([mat(b['rest'])for b in B]);names={b['name']:i for i,b in enumerate(B)};p=poses.copy()
for d,profile in profiles.items():
 for j,angle in enumerate(profile['angles']):
  k=names[d+str(j)];r=rotation(J['axes'][d+str(j)],angle)
  if j==0:r=rotation(profile['axis'],profile['lateral'])@r
  p[k,:3,:3]=rests[k,:3,:3]@r
world=p.copy()
for k,b in enumerate(B):
 if b['parent']>=0:world[k]=world[b['parent']]@p[k]
base=mat(J['fp_frame']);center=np.array(J['grip']);neutral=base[:3,:3]@np.array([-.0061573014,.0032993148,.2419044524]);neutral/=np.linalg.norm(neutral);axis=np.cross(neutral,[0,-1,0]);r=rotation(axis,math.radians(tilt));f=base.copy();f[:3,:3]=r@base[:3,:3];f[:3,3]=center+r@(base[:3,3]-center)+offset
binds=np.array([mat(b['transform'])for b in S['binds']]);bi=np.array([b['bone']for b in S['binds']]);v=np.c_[S['vertices'],np.ones(len(S['vertices']))];indices=np.array(S['bones']).reshape(-1,4);weights=np.array(S['weights']).reshape(-1,4);skin=world[bi]@binds;points=(f@np.einsum('nijk,nk,ni->nj',skin[indices],v,weights).T).T[:,:3]
dom=bi[indices[np.arange(len(v)),weights.argmax(1)]];labels=np.array([B[k]['name'].rstrip('012')for k in dom]);tri=np.array(S['indices']).reshape(-1,3)
def crosses(a,b):
 A=points[tri[np.all(labels[tri]==a,1)]];BB=points[tri[np.all(labels[tri]==b,1)]];pairs=np.argwhere(np.all(A.min(1)[:,None,:]<=BB.max(1)[None,:,:],2)&np.all(A.max(1)[:,None,:]>=BB.min(1)[None,:,:],2))
 if not len(pairs):return 0
 aa=A[pairs[:,0]];bb=BB[pairs[:,1]];hit=np.zeros(len(pairs),bool)
 for t,u in [(aa,bb),(bb,aa)]:
  e1=u[:,1]-u[:,0];e2=u[:,2]-u[:,0]
  for k in range(3):
   o=t[:,k];di=t[:,(k+1)%3]-o;h=np.cross(di,e2);det=np.einsum('ij,ij->i',e1,h);valid=abs(det)>1e-12;inv=np.divide(1,det,out=np.zeros_like(det),where=valid);vv=o-u[:,0];xx=np.einsum('ij,ij->i',vv,h)*inv;q=np.cross(vv,e1);yy=np.einsum('ij,ij->i',di,q)*inv;tt=np.einsum('ij,ij->i',e2,q)*inv
   hit|=valid&(xx>1e-5)&(yy>1e-5)&(xx+yy<1-1e-5)&(tt>1e-5)&(tt<1-1e-5)
 return int(hit.sum())
result={'selected_tilt_degrees':tilt,'contact_offset':offset.tolist(),'source_script_sha256':hashlib.sha256(SCRIPT.read_bytes()).hexdigest(),'wrist_local':(f@np.r_[[0,.0057,.02475],1])[:3].tolist(),'neutral_axis_local':((f[:3,:3]@np.array([-.0061573014,.0032993148,.2419044524]))/np.linalg.norm(f[:3,:3]@np.array([-.0061573014,.0032993148,.2419044524]))).tolist(),'dominant_digit_triangle_crossings':{a+'__'+b:crosses(a,b)for a,b in[('index','middle'),('middle','ring'),('ring','little'),('thumb','index'),('thumb','middle')]},'handle_ellipse':{}}
for d in ['index','middle','ring','little','thumb','palm']:
 ps=points[labels==d];rho=np.hypot(ps[:,0]/.0225,ps[:,2]/.0154);result['handle_ellipse'][d]={'minimum_normalized_radius':float(rho.min()),'vertices_below_0_8':int((rho<.8).sum()),'sample_count':len(ps)}
saved=np.array(json.load(open(args.selected_pose))['vertices']);result['serialized_profile_vs_optimizer_max_vertex_difference_m']=float(np.max(np.linalg.norm(points-saved,axis=1)))
print(json.dumps(result,indent=2))
assert not any(result['dominant_digit_triangle_crossings'].values())
# Palm is a separate diagnostic: one vertex lies inside the approximate
# ellipse. Never report this as a complete hand/handle collision clearance.
assert not any(result['handle_ellipse'][d]['vertices_below_0_8']for d in profiles)
