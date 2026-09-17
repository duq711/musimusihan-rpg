import json, numpy as np
from pathlib import Path
from scipy.spatial.transform import Rotation
from scipy.optimize import least_squares
D=Path(__file__).parent
X=json.loads((D/'hand_export.json').read_text())
B=X['bones']; names=[b['name'] for b in B]; axes=X['axes']
def mat(t):
 a=np.eye(4);a[:3,:3]=np.array(t[:3]).T;a[:3,3]=t[3];return a
rest=np.array([mat(b['rest']) for b in B]); pose0=np.array([mat(b['pose']) for b in B]); rig=mat(X['rig_transform'])
p=X['parts'][0];v=np.c_[p['vertices'],np.ones(len(p['vertices']))];n=np.array(p['normals']);weights=np.array(p['weights']).reshape(-1,4);ids=np.array(p['bones']).reshape(-1,4);bind=np.array([mat(b['transform']) for b in p['binds']]);boneids=np.array([b['bone'] for b in p['binds']]); food=np.array(X['food']['vertices'])
digits=['index','middle','ring','little','thumb']
initial=np.array([[.533948664,.884146886,.624727228],[.652432312,.796511932,.721119819],[.600076350,.759318354,.678573156],[.549979131,.680524039,.622076560],[.796078899,.624578494,.667113122]])
def skin(q,vs=v,nn=n):
 poses=pose0.copy();g=np.empty_like(poses)
 for d,vals in zip(digits,q):
  lo=np.array([-.12,-.25,-.22] if d=='thumb' else [-.48,-.82,-.48]);hi=np.array([.30,.35,.48] if d=='thumb' else [.48,.42,.32]);ang=lo+(hi-lo)*vals
  for j in range(3):
   k=names.index(d+str(j));poses[k,:3,:3]=rest[k,:3,:3]@Rotation.from_rotvec(np.array(axes[d+str(j)])*ang[j]).as_matrix()
 for k,b in enumerate(B):g[k]=g[b['parent']]@poses[k] if b['parent']>=0 else poses[k]
 skinmat=g[boneids]@bind
 vv=np.einsum('vjab,vb->vja',skinmat[ids],vs)
 out=np.einsum('vja,vj->va',vv,weights)[:,:3]
 norm=np.einsum('vjab,vb->vja',skinmat[ids][...,:3,:3],nn)
 norm=np.einsum('vja,vj->va',norm,weights);norm/=np.linalg.norm(norm,axis=1)[:,None]
 return out,norm,g
if __name__=='__main__':
 vv,nn,g=skin(initial)
 for d in digits:
  ii=names.index(d+'2');weight=np.sum(weights*(boneids[ids]==ii),axis=1);sel=np.where(weight>.7)[0]
  center=vv[sel].mean(axis=0)
  print(d,'n',len(sel),'center',center,'range',vv[sel].min(axis=0),vv[sel].max(axis=0))
  print('candidates:', [(int(i),vv[i].round(4).tolist(),nn[i].round(2).tolist()) for i in sel[np.argsort(vv[sel,1])[:6]]])
 np.savez(D/'skin_initial.npz',v=vv,n=nn)

if __name__=='__main__':
 def gapcost(q):
  qq=initial.copy();qq[0]=q[:3];qq[4]=q[3:];vv,nn,g=skin(qq)
  a,b=vv[156],vv[17];delta=b-a;dist=np.linalg.norm(delta);axis=delta/dist
  return np.r_[(dist-.0045)*300, (nn[156]-axis)*.8,(nn[17]+axis)*.8,(q-np.r_[initial[0],initial[4]])*.04]
 best=least_squares(gapcost,np.r_[initial[0],initial[4]],bounds=(0,1),max_nfev=200)
 qq=initial.copy();qq[0]=best.x[:3];qq[4]=best.x[3:];vv,nn,g=skin(qq)
 a,b=vv[156],vv[17];delta=b-a;normal=delta/np.linalg.norm(delta)
 axis=np.array([0.,-1.,0.]);axis-=normal*np.dot(axis,normal);axis/=np.linalg.norm(axis)
 width=np.cross(axis,normal)
 basis=np.column_stack([axis,normal,width])
 contact=(a+b)/2
 foodcontact=np.array([-.055,.0025,-.003])
 origin=contact-basis@foodcontact
 print('solution',best.cost,qq.tolist(),'contact',contact,'gap',np.linalg.norm(delta))
 print('basis columns',basis.T.tolist(),'origin',origin.tolist(),'pads',a,b,'normals',nn[156],nn[17])
 (D/'grip_fit.json').write_text(json.dumps({'pose':dict(zip(digits,qq.tolist())),'basis':basis.T.tolist(),'origin':origin.tolist(),'pads':[156,17],'skin_points':[a.tolist(),b.tolist()],'gap':np.linalg.norm(delta)}))
 np.savez(D/'skin_fit.npz',v=vv,n=nn,food=food@basis.T+origin)
