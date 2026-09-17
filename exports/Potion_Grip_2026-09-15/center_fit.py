import numpy as np,json
D=json.load(open('exports/Potion_Grip_2026-09-15/fit.json'));V=np.array(D['vertices']);G=np.array(D['glass']);G[:,[0,2]]*=.6
Y=np.linspace(G[:,1].min(),G[:,1].max(),240);R=np.array([np.max(np.linalg.norm(G[abs(G[:,1]-y)<.06][:,[0,2]],axis=1),initial=0) for y in Y]);R=np.interp(Y,Y[R>0],R[R>0])
def sdf(p):return np.maximum(np.linalg.norm(p[:,[0,2]],axis=1)-np.interp(p[:,1],Y,R),np.maximum(Y[0]-p[:,1],p[:,1]-Y[-1]))
flip=np.diag([1,-1,-1]);V=V@flip.T
best=(1e9,None)
for x in np.arange(-1.5,1.51,.1):
 for z in np.arange(-2,2.01,.1):
  t=np.array([x,0,z]);dist=sdf(V+t);cost=np.mean(np.minimum(dist-.03,0)**2)*10000 + np.dot(t,t)
  if cost<best[0]:best=cost,t.copy()
c,t=best;print(c,t*.022,'min',sdf(V+t).min()*.022,'inside',np.mean(sdf(V+t)<-.05))
