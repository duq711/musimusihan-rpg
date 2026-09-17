import sys,json,math
from pathlib import Path
s=Path(__file__).resolve().parents[1];sys.path.insert(0,str(s/'tools/python_deps'))
import numpy as np
from scipy.optimize import least_squares
x=np.load(s/'audit/fit_input.npz');v=x['vertices'];B=x['bones'];Bi=np.linalg.inv(B);names=list(x['names']);parents=x['parents'];W=x['weights'];normals=x['normals']
rel=np.array([np.linalg.inv(B[p])@b if p>=0 else b for p,b in zip(parents,B)])
digits=['thumb','index','middle','ring','little'];deltas=x['key_deltas'];keynames=list(x['keynames'])
limits=np.radians([25,35,45]+[60,45,45]*4)
indices=[names.index(d+str(j)) for d in digits for j in range(3)]
keyindices=[keynames.index('Joint_'+d+'_'+str(j)) for d in digits for j in range(3)]
def rot(axis,a):
 c=np.cos(a);t=np.sin(a);R=np.eye(4)
 if axis==0:R[1:3,1:3]=[[c,-t],[t,c]]
 else:R[[0,0,2,2],[0,2,0,2]]=[c,t,-t,c]
 return R
def transforms(q):
 P=np.empty_like(B)
 for i,n in enumerate(names):
  R=rot(0,q[indices.index(i)]) if i in indices else np.eye(4)
  if n=='thumb0':R=rot(1,q[15])@R
  P[i]=(P[parents[i]] if parents[i]>=0 else np.eye(4))@rel[i]@R
 return P@Bi
base=np.radians([-25,-29.04,-21.03]+[-55.35,-42.80,-30.99]*4+[32.68])
T=transforms(base)
print('FK_RUNTIME_DELTA_MAX',np.max(np.abs(T-x['runtime_deltas'])),flush=True)
# Finger pad samples in each distal bone's actual local frame. Skin normals
# point toward the palmar half; nail-bearing dorsal vertices are excluded.
contact=[];labels=[]
for d in digits:
 i=names.index(d+'2');loc=v@Bi[i,:3,:3].T+Bi[i,:3,3]
 ns=normals@B[i,:3,:3]
 owner=W[:,i]>.65
 mask=owner&(loc[:,1]>.005)&(ns[:,2]<-.25)
 ids=np.where(mask)[0]
 if len(ids)<12:ids=np.where(owner&(ns[:,2]<.1))[0]
 contact.append(ids);labels.append(d)
mask=(np.abs(v[:,0])<.024)&(v[:,1]>.03)&(v[:,1]<.073)&(normals[:,2]<-.4)
contact.append(np.where(mask)[0]);labels.append('palm')
# Keep all pad samples and a uniform collision sample of the whole actual skin.
rng=np.random.default_rng(711);sample=np.unique(np.concatenate([np.arange(0,len(v),5)]+contact));vs=v[sample];ws=W[sample];ds=deltas[keyindices][:,sample];homo=np.column_stack([vs,np.ones(len(vs))]); maps=[np.where(np.isin(sample,c))[0] for c in contact]
print('CONTACT_COUNTS',dict(zip(labels,map(len,maps))),flush=True)
def skin(q,full=False):
 T=transforms(q)
 verts=v if full else vs;weights=W if full else ws
 kd=deltas[keyindices] if full else ds
 p=verts+np.einsum('i,ivc->vc',np.clip(-q[:15]/limits,0,1),kd)
 result=np.zeros_like(p)
 for i in range(16):result+=(p@T[i,:3,:3].T+T[i,:3,3])*weights[:,i:i+1]
 return result
# Torch's actual shaft has ~38 mm radius; the wrap near the grip adds a small
# extra rim. Optimize skin outside its measured cross-section, not a point.
handle=json.loads((s/'audit/handle_mesh.json').read_text());hv=np.array(handle['vertices']);radii=np.linalg.norm(hv[:,:2],axis=1)
ring=[]
for z in np.unique(np.round(hv[:,2],5)):
 rr=radii[np.abs(hv[:,2]-z)<.00002]
 if len(rr)>5:ring.append([float(z),float(np.max(rr))])
print('HANDLE_RINGS',ring,flush=True)
# Shaft is carried along native hand X, with optional cant through the knuckle row.
def distance(p,q):
 axis=np.array([np.cos(q[18]),np.sin(q[18]),0]);center=np.array([0,q[16],q[17]])
 offsets=p-center;along=offsets@axis
 radi=np.linalg.norm(offsets-along[:,None]*axis,axis=1)
 # Local x corresponds to torch height relative to the unchanged 0.12m grip.
 radius=np.interp(.12+along,np.array(ring)[:,0],np.array(ring)[:,1])
 return radi-radius
q0=np.r_[base,.0825,-.019,0.]
print('BASELINE',[(l,float(np.min(distance(skin(q0),q0)[m]))) for l,m in zip(labels,maps)],flush=True)
# Anatomical pose limits are additional bends from the already-curled source.
lo=np.r_[np.radians([-35,-45,-50]+[-78,-55,-50]*4),-.8,.04,-.085,-.4];hi=np.r_[np.radians([20,15,25]+[12,20,30]*4),.8,.12,-.012,.5]
for i in [3,6,9,12]:hi[i]=-.1745329252
qstart=np.r_[np.radians([-12,-15,-10]+[-20,-25,-15]*4+[20]),.085,-.045,.12]
def residual(q):
 p=skin(q);dist=distance(p,q)
 # Penalize all interpenetration; contacts use the closest pad patch, avoiding
 # an artificial demand to flatten an entire fingertip onto the round shaft.
 collision=np.minimum(0,dist-.0004)*120
 contacts=[]
 for m in maps:
  a=np.sort(dist[m]);n=max(3,int(len(a)*.06));contacts.append(np.mean(a[:n])-.0008)
 reg=(q[:15]-qstart[:15])*.025
 roots=q[[3,6,9,12]]-np.radians([18,4,-1,17])
 reg=np.r_[reg,np.diff(roots)*.07]
 return np.r_[collision,np.array(contacts)*100,reg,q[18]*.001]
runs=[]
for seed in range(4):
 start=qstart.copy();start[:15]+=np.random.default_rng(seed+17).normal(0,.17,15);start[15]=[.3,-.3,.6,-.6][seed];start[16]=[.08,.09,.065,.06][seed]
 start=np.clip(start,lo+1e-5,hi-1e-5)
 rr=least_squares(residual,start,bounds=(lo,hi),diff_step=1e-4,max_nfev=120,ftol=1e-6,xtol=1e-6,gtol=1e-6)
 print('SEED',seed,'COST',rr.cost,'EVAL',rr.nfev,flush=True);runs.append(rr)
res=min(runs,key=lambda r:r.cost)
q=res.x;p=skin(q,True);dist=distance(p,q)
result={'parameters':q.tolist(),'degrees':dict((d,np.degrees(q[di*3:di*3+3]).tolist()) for di,d in enumerate(digits)),'thumb_opposition_degrees':float(np.degrees(q[15])),'shaft_in_hand':{'center':[0,float(q[16]),float(q[17])],'axis':[float(np.cos(q[18])),float(np.sin(q[18])),0]},'full_skin_min_clearance_m':float(dist.min()),'penetrating_vertices':int(np.count_nonzero(dist<-.0005)),'contacts':dict((l,{'minimum_m':float(dist[c].min()),'closest_patch_mean_m':float(np.sort(dist[c])[:max(3,int(len(c)*.06))].mean())}) for l,c in zip(labels,contact)),'cost':res.cost,'evaluations':res.nfev,'runtime_delta_reproduction_error':float(np.max(np.abs(T-x['runtime_deltas']))),'handle_rings':ring}
(s/'audit/fitted_pose_03.json').write_text(json.dumps(result,indent=2));np.save(s/'audit/fitted_vertices_03.npy',p)
print(json.dumps(result,indent=2),flush=True)
