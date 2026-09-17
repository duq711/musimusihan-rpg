import numpy as np,json
from pathlib import Path
d=json.load(open('exports/Potion_Grip_2026-09-15/fit.json'));sol=json.load(open('exports/Potion_Grip_2026-09-15/pose_solution.json'));v=np.array(d['vertices']);g=np.array(d['glass']);g[:,[0,2]]*=.6;R=np.array(sol['matrix']);t=np.array(sol['translation'])/.022;v=v@R.T+t
ys=np.linspace(g[:,1].min(),g[:,1].max(),240);r=np.array([np.max(np.linalg.norm(g[abs(g[:,1]-h)<.06][:,[0,2]],axis=1),initial=0) for h in ys]);r=np.interp(ys,ys[r>0],r[r>0])
def sdf(p):return np.maximum(np.linalg.norm(p[:,[0,2]],axis=1)-np.interp(p[:,1],ys,r),np.maximum(ys[0]-p[:,1],p[:,1]-ys[-1]))
rng=np.random.default_rng(8);directions=rng.normal(size=(1000,3));directions/=np.linalg.norm(directions,axis=1)[:,None]
best=None
for distance in np.arange(.001,.041,.001):
 for direction in directions:
  delta=direction*distance/.022
  if sdf(v+delta).min()>.015:
   best=delta*.022;break
 if best is not None:break
print('additional shift',best,'min before',sdf(v).min()*.022)
if best is not None:
 final=np.array(sol['translation'])+best
 print('final',final,'min after',sdf(v+best/.022).min()*.022)
 sol['translation']=final.tolist();json.dump(sol,open('exports/Potion_Grip_2026-09-15/final_solution.json','w'))
