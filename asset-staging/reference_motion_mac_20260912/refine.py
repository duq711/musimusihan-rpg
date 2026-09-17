from pathlib import Path
p=Path(__file__).with_name('author_motion.py');s=p.read_text();s=s.replace("OUT=ROOT/'iteration_01'","OUT=ROOT/'iteration_02'")
start=s.index('def sample(keys,t):');end=s.index('\nidle=',start)
s=s[:start]+'''def sample(keys,t):
 i=next((i for i in range(len(keys)-1) if t<=keys[i+1][0]),len(keys)-2)
 times=[k[0] for k in keys];ps=[k[1][0] for k in keys];anchor=keys[0][1][1];rv=[]
 for _,(_,q) in keys:
  r=anchor.inverted()@q
  if r.w<0:r.negate()
  v=V((r.x,r.y,r.z));ang=2*math.atan2(v.length,r.w);axis=v.normalized() if v.length>1e-8 else V((0,1,0))
  cand=[axis*(ang+math.tau*j) for j in (-1,0,1)]
  rv.append(min(cand,key=lambda x:(x-(rv[-1] if rv else V((0,0,0)))).length))
 def curve(values):
  def tangent(k):
   if k in (0,len(keys)-1):return V((0,0,0))
   a=(values[k]-values[k-1])/(times[k]-times[k-1]);b=(values[k+1]-values[k])/(times[k+1]-times[k])
   # Monotone Hermite preserves anticipation holds and avoids overshoot.
   return V(tuple(2*a[j]*b[j]/(a[j]+b[j]) if a[j]*b[j]>0 else 0 for j in range(3)))
  dt=times[i+1]-times[i];u=max(0,min(1,(t-times[i])/dt));u2=u*u;u3=u2*u
  return values[i]*(2*u3-3*u2+1)+tangent(i)*dt*(u3-2*u2+u)+values[i+1]*(-2*u3+3*u2)+tangent(i+1)*dt*(u3-u2)
 r=curve(rv);q=anchor@(Quaternion(r.normalized(),r.length) if r.length>1e-8 else Quaternion())
 return curve(ps),q
''' + s[end:]
s=s.replace("lowshield=pose((-.53,-.94,-.43),(12,24,-10))","lowshield=pose((-.53,-.70,-.28),(65,40,-10))")
p.write_text(s)
