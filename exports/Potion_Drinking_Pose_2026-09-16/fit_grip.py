import numpy as np,json
from pathlib import Path
out=Path('exports/Potion_Drinking_Pose_2026-09-16')
d=json.load(open(out/'rig.json'));names=d['names'];rest=np.array(d['rest']);build=np.array(d['hand_build']);parents=d['parents'];parts=d['parts'][0]
v=np.c_[np.array(parts['vertices']),np.ones(len(parts['vertices']))];bind=np.array(parts['bind']);bids=np.array(parts['bone_ids']);bi=np.array(parts['bones']).reshape(-1,4);w=np.array(parts['weights']).reshape(-1,4)
# Pretransform each influence by its skin bind, then only apply bone poses.
bv=np.einsum('nkij,nj->nki',bind[bi],v);bone=bids[bi]
axes={names.index(k):np.array(a) for k,a in d['axes'].items()};digits=['index','middle','ring','little','thumb']
idigits=[[names.index(f'{digit}{j}') for j in range(3)] for digit in digits]
ids=sum(idigits,[])
g=np.array(json.load(open('exports/Potion_Grip_2026-09-15/fit.json'))['glass'])*np.array([.9,1.2,.9])*.022
ys=np.linspace(g[:,1].min(),g[:,1].max(),220);rs=np.array([np.max(np.linalg.norm(g[np.abs(g[:,1]-y)<.002][:,[0,2]],axis=1),initial=0) for y in ys]);rs=np.interp(ys,ys[rs>0],rs[rs>0])
regions=[]
for ii in idigits:
 regions.append(np.flatnonzero(np.sum(w*np.isin(bone,ii[1:]),axis=1)>.5))
regions.append(np.flatnonzero(np.sum(w*np.isin(bone,[names.index('palm'),names.index('wrist')]),axis=1)>.5))
def rot(axis,angle):
 x,y,z=axis;K=np.array([[0,-z,y],[z,0,-x],[-y,x,0]]);return np.eye(3)+np.sin(angle)*K+(1-np.cos(angle))*(K@K)
def pose(amount):
 local=rest.copy();aa=np.array(amount).reshape(5,3)
 for digit,ii in enumerate(idigits):
  lo=np.array([-.12,-.25,-.22]) if digit==4 else np.array([-.48,-.82,-.48]);hi=np.array([.3,.35,.48]) if digit==4 else np.array([.48,.42,.32])
  angles=lo+(hi-lo)*aa[digit]
  for j,i in enumerate(ii):local[i,:3,:3]=rest[i,:3,:3]@rot(axes[i],angles[j])
 local[3]=build@rest[3]
 glob=local.copy()
 for i,p in enumerate(parents):
  if p>=0:glob[i]=glob[p]@local[i]
 verts=np.einsum('nkij,nkj,nk->ni',glob[bone],bv,w)[:,:3]
 return verts,glob
init=np.tile([.20,.5,.5],5);init[-3:]=[.6,.65,.55];vv,gg=pose(init)
a=gg[names.index('index0'),:3,3]-gg[names.index('little0'),:3,3];a/=np.linalg.norm(a)
gc=np.mean(gg[[names.index(k) for k in ['middle1','ring1','thumb2']],:3,3],axis=0)
print('axis',a,'grip',gc,flush=True)
u=np.cross(a,[0,1,0]);u/=np.linalg.norm(u);vaxis=np.cross(a,u)
def field(verts,q):
 axis=a+q[3]*u+q[4]*vaxis;axis/=np.linalg.norm(axis)
 p=verts-q[:3];y=p@axis;rad=np.sqrt(np.maximum(0,np.sum(p*p,axis=1)-y*y));return np.maximum(rad-np.interp(y,ys,rs),np.maximum(ys[0]-y,y-ys[-1]))
def fun(q,verts=None):
 if np.any(q[5:]<0) or np.any(q[5:]>1) or np.max(np.abs(q[3:5]))>.45:return 1e6
 if verts is None:verts,_=pose(q[5:])
 dist=field(verts,q)*1000
 pen=np.minimum(dist-.6,0)
 # Surface contact at all four curled fingers, thumb, and broad palm pad.
 contacts=np.array([np.mean(np.partition(np.abs(dist[r]-.8),2)[:3]) for r in regions])
 return 350*np.mean(pen**2)+20*min(dist.min()-.3,0)**2+np.sum(contacts**2)+1.0*np.sum((q[3:5]*10)**2)+.5*np.sum(((q[:3]-gc)/.01)**2)
best=(1e10,None);rng=np.random.default_rng(812)
for trial in range(8):
 q=np.r_[gc-a*.018,[0,0],init]
 if trial:q[:3]+=rng.uniform(-.018,.018,3);q[5:]=np.clip(init+rng.uniform(-.2,.2,15),0,1)
 f=fun(q)
 for step in [.10,.05,.025,.01]:
  for repeat in range(10):
   improved=False
   for k in range(20):
    for sign in [-1,1]:
     z=q.copy();z[k]+=sign*step*(.10 if k<3 else 1)
     z[5:]=np.clip(z[5:],0,1)
     ff=fun(z)
     if ff<f:q,f=z,ff;improved=True
   if not improved:break
 if f<best[0]:best=f,q.copy()
 print(trial,round(f,3),flush=True)
f,q=best;verts,gg=pose(q[5:]);axis=a+q[3]*u+q[4]*vaxis;axis/=np.linalg.norm(axis)
# Bottle-to-hand frame: choose its radial orientation with the forearm on +X.
x=np.array([0,0,1.])-axis*axis[2];x/=np.linalg.norm(x);z=np.cross(x,axis);B=np.column_stack([x,axis,z]);HB=B.T
hand_pos=-HB@q[:3];grip=np.mean(gg[[names.index(k) for k in ['middle1','ring1','thumb2']],:3,3],axis=0)
result={'center_in_hand':q[:3].tolist(),'bottle_basis_in_hand':B.tolist(),'hand_basis_in_bottle':HB.tolist(),'hand_origin_in_bottle':hand_pos.tolist(),'grip_in_bottle':(HB@(grip-q[:3])).tolist(),'amounts':q[5:].reshape(5,3).tolist(),'min_clearance_mm':float(field(verts,q).min()*1000),'contacts_mm':[float(np.min(np.abs(field(verts,q)[r])*1000)) for r in regions],'score':f}
print(result,flush=True);json.dump(result,open(out/'grip_solution.json','w'),indent=2)
