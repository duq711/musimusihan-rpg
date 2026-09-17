import json,numpy as np
p='exports/Potion_Grip_2026-09-15/fit.json';d=json.load(open(p));v=np.array(d['vertices']);g=np.array(d['glass']);rot=np.diag([1,-1,-1]);v=v@rot.T
y=np.linspace(g[:,1].min(),g[:,1].max(),180);r=np.array([np.max(np.linalg.norm(g[abs(g[:,1]-h)<.08][:,[0,2]],axis=1),initial=0) for h in y]);r=np.interp(y,y[r>0],r[r>0]);np.savez('exports/Potion_Grip_2026-09-15/profile.npz',y=y,r=r)
bones={a[0]:rot@np.array(a[1:]) for a in d['bones']};groups=[v[np.linalg.norm(v-bones[k],axis=1)<.7][::3] for k in ['index2','middle2','ring2','little2','thumb2']]
def sdf(p):
 radial=np.linalg.norm(p[:,[0,2]],axis=1)-np.interp(p[:,1],y,r)
 return np.maximum(radial,np.maximum(y[0]-p[:,1],p[:,1]-y[-1]))
def fun(t):
 dist=sdf(v[::8]+t)
 contact=np.array([np.min(abs(sdf(a+t))) for a in groups])
 return 2000*np.mean(np.minimum(dist-.04,0)**2)+np.sum(contact**2)*.8+.002*np.dot(t,t)
rng=np.random.default_rng(2);best=(1e9,None)
for start in range(140):
 t=rng.uniform([-2,-1,-2],[2,1,2]);f=fun(t)
 for step in [.8,.4,.2,.1,.05,.025]:
  for repeat in range(6):
   improved=False
   for axis in range(3):
    for sign in [-1,1]:
     q=t.copy();q[axis]+=step*sign;score=fun(q)
     if score<f:t,f=q,score;improved=True
   if not improved:break
 if f<best[0]:best=f,t.copy()
f,t=best
print('shift',t,'meters',t*.022,'score',f,'inside before',np.mean(sdf(v)<-.05),'after',np.mean(sdf(v+t)<-.05),'min',sdf(v+t).min())
json.dump({'shift':t.tolist()},open('exports/Potion_Grip_2026-09-15/solution.json','w'))
