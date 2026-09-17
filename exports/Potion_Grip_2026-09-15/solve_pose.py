exec(open('exports/Potion_Grip_2026-09-15/solve_initial.py').read().split('rng=np.random')[0].replace("print('vertices',len(v),'bones',d['bones'])",''))
g[:,[0,2]]*=0.60
r*=0.60
# Current dump has the opened roots / curled ends, rotated +90 degrees.
original=v.copy();allgroups=groups.copy();small=v[::5]
def rotation(q):
 x,y,z=q;c=np.cos(q);s=np.sin(q)
 return np.array([[c[2],-s[2],0],[s[2],c[2],0],[0,0,1]])@np.array([[c[1],0,s[1]],[0,1,0],[-s[1],0,c[1]]])@np.array([[1,0,0],[0,c[0],-s[0]],[0,s[0],c[0]]])
def fun(q):
 R=rotation(q[3:]);t=q[:3];dist=sdf(small@R.T+t)
 contacts=np.array([np.min(abs(sdf(a@R.T+t))) for a in allgroups])
 # All fingers stay close, strong penetration penalty, keep grip at body.
 return .2*max(0, 2-(bones["wrist"]@R.T+t)[0])**2 + .2*max(0, (bones["wrist"]@R.T+t)[1]-1)**2 + 2000*np.mean(np.minimum(dist-.03,0)**2)+3*np.sum(contacts**2)+.005*np.dot(t,t)+.06*t[1]**2
rng=np.random.default_rng(6);best=(1e9,None)
for start in range(150):
 q=np.r_[rng.uniform([-2,-1,-2],[2,2,2]),rng.uniform(-3.14,3.14,3)];f=fun(q)
 for step in [.65,.3,.15,.06,.025]:
  for repeat in range(5):
   improved=False
   for axis in range(6):
    for sign in [-1,1]:
     t=q.copy();t[axis]+=step*sign;score=fun(t)
     if score<f:q,f=t,score;improved=True
   if not improved:break
 if f<best[0]:best=f,q.copy()
f,q=best;R=rotation(q[3:]);dist=sdf(original@R.T+q[:3]);print('score',f,'translation',q[:3]*.022,'rotation',q[3:],'min',dist.min()*.022,'inside',np.mean(dist<-.05))
json.dump({'translation':(q[:3]*.022).tolist(),'rotation':q[3:].tolist(),'matrix':R.tolist()},open('exports/Potion_Grip_2026-09-15/pose_solution.json','w'))
small=original
oldfun=fun
def fun(q):
 R=rotation(q[3:]);p=small@R.T+q[:3];dist=sdf(p)
 return oldfun(q)+200000*np.mean(np.minimum(dist-.025,0)**2)
f=fun(q)
for step in [.1,.04,.02,.008,.003]:
 for repeat in range(30):
  changed=False
  for axis in range(6):
   for sign in [-1,1]:
    t=q.copy();t[axis]+=sign*step;score=fun(t)
    if score<f:q,f=t,score;changed=True
  if not changed:break
R=rotation(q[3:]);dist=sdf(original@R.T+q[:3]);print('REFINED',f,q[:3]*.022,q[3:],'min',dist.min()*.022,'inside',np.mean(dist<-.05))
json.dump({'translation':(q[:3]*.022).tolist(),'rotation':q[3:].tolist(),'matrix':R.tolist()},open('exports/Potion_Grip_2026-09-15/pose_solution.json','w'))
