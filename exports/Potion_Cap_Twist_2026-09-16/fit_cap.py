import numpy as np,json
from pathlib import Path
out=Path('exports/Potion_Cap_Twist_2026-09-16')
d=json.load(open(out/'rig.json'));names=d['names'];rest=np.array(d['rest']);build=np.array(d['hand_build']);parents=d['parents'];parts=d['parts'][0]
v=np.c_[np.array(parts['vertices']),np.ones(len(parts['vertices']))];bind=np.array(parts['bind']);bids=np.array(parts['bone_ids']);bi=np.array(parts['bones']).reshape(-1,4);w=np.array(parts['weights']).reshape(-1,4)
# Pretransform each influence by its skin bind, then only apply bone poses.
bv=np.einsum('nkij,nj->nki',bind[bi],v);bone=bids[bi]
axes={names.index(k):np.array(a) for k,a in d['axes'].items()};digits=['index','middle','ring','little','thumb']
idigits=[[names.index(f'{digit}{j}') for j in range(3)] for digit in digits]
ids=sum(idigits,[])
regions=[]
for ii in idigits:
 regions.append(np.flatnonzero(np.sum(w*np.isin(bone,ii[2:]),axis=1)>.5))
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
# Grip at the exposed top of the existing cork. Original bottle and stopper geometry stay unchanged.
init=np.array([[.68,.78,.75],[.65,.80,.72],[.6,.76,.68],[.55,.68,.62],[.78,.80,.75]]).ravel()
vv,gg=pose(init);gc=np.mean(gg[[names.index('index2'),names.index('thumb2')],:3,3],axis=0)
print('initial fingertips',gg[names.index('index2'),:3,3],gg[names.index('thumb2'),:3,3],flush=True)
a=np.array([0,1.,0]);u=np.array([1.,0,0]);vaxis=np.array([0,0,1.])
g=np.array(json.load(open('exports/Potion_Grip_2026-09-15/fit.json'))['glass'])*np.array([.9,1.2,.9])*.022
g[:,1]-=4.795*.022*1.2+.016
ys=np.linspace(g[:,1].min(),g[:,1].max(),240);rs=np.array([np.max(np.linalg.norm(g[np.abs(g[:,1]-y)<.002][:,[0,2]],axis=1),initial=0) for y in ys]);rs=np.interp(ys,ys[rs>0],rs[rs>0])
def field(verts,q):
 axis=a+q[3]*u+q[4]*vaxis;axis/=np.linalg.norm(axis)
 p=verts-q[:3];y=p@axis;rad=np.sqrt(np.maximum(0,np.sum(p*p,axis=1)-y*y))
 # Signed distance to a closed cylinder; negative inside.
 radial=rad-.014;yy=np.abs(y+.016)-.022
 dc=np.linalg.norm(np.maximum(np.c_[radial,yy],0),axis=1)+np.minimum(np.maximum(radial,yy),0)
 db=np.maximum(rad-np.interp(y,ys,rs),np.maximum(ys[0]-y,y-ys[-1]))
 return dc,db

def fun(q):
 if np.any(q[5:]<0) or np.any(q[5:]>1) or np.max(np.abs(q[3:5]))>.65:return 1e9
 verts,gg=pose(q[5:]);dc,db=field(verts,q);dc*=1000;db*=1000;di=np.minimum(dc,db)
 pen=np.minimum(di-.5,0)
 contacts=np.array([np.mean(np.partition(np.abs(dc[regions[i]]-.7),2)[:3]) for i in [0,4]])
 # Keep both sides of the pinch close, with the remaining digits relaxed and curled.
 axis=a+q[3]*u+q[4]*vaxis;axis/=np.linalg.norm(axis)
 tips=gg[[names.index('index2'),names.index('thumb2')],:3,3]-q[:3]
 across=np.sum(tips*axis,axis=1)
 cost=350*np.mean(pen**2)+25*min(di.min(),0)**2+np.sum(contacts**2)*4
 cost+=1*np.sum(np.maximum(np.abs(across)-.018,0)**2)*1e6
 cost+=2*np.sum((q[5:]-init)**2)+.25*np.sum((q[3:5]*10)**2)+.08*np.sum(((q[:3]-gc)/.01)**2)
 return cost
rng=np.random.default_rng(619);best=(1e10,None)
for trial in range(10):
 q=np.r_[gc,[0,0],init]
 if trial:q[:3]+=rng.uniform(-.015,.015,3);q[5:]=np.clip(init+rng.uniform(-.18,.18,15),0,1)
 f=fun(q)
 for step in [.12,.06,.03,.012,.005]:
  for repeat in range(7):
   improved=False
   for k in range(20):
    for sign in [-1,1]:
     z=q.copy();z[k]+=sign*step*(.1 if k<3 else 1)
     z[5:]=np.clip(z[5:],0,1);ff=fun(z)
     if ff<f:q,f=z,ff;improved=True
   if not improved:break
 if f<best[0]:best=f,q.copy()
 print(trial,round(f,3),flush=True)
f,q=best;verts,gg=pose(q[5:]);axis=a+q[3]*u+q[4]*vaxis;axis/=np.linalg.norm(axis)
x=np.array([1.,0,0])-axis*axis[0];x/=np.linalg.norm(x);z=np.cross(x,axis);B=np.column_stack([x,axis,z]);HB=B.T
result={'center_in_hand':q[:3].tolist(),'bottle_basis_in_hand':B.tolist(),'hand_basis_in_cap':HB.tolist(),'hand_origin_in_cap':(-HB@q[:3]).tolist(),'amounts':q[5:].reshape(5,3).tolist(),'clearance_mm':float(np.minimum(*field(verts,q)).min()*1000),'contacts_mm':[float(np.min(np.abs(field(verts,q)[0][regions[i]])*1000)) for i in [0,4]],'score':f}
print(result,flush=True);json.dump(result,open(out/'cap_solution.json','w'),indent=2)
