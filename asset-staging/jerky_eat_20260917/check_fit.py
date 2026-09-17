from fit_grip import *
f=json.loads((D/'grip_fit.json').read_text());basis=np.array(f['basis']).T;origin=np.array(f['origin']);q=np.array([f['pose'][d] for d in digits]);vv,nn,g=skin(q);local=(vv-origin)@basis
tris=food[np.array(X['food']['indices']).reshape(-1,3)];a=tris[:,0][:,[0,2]];b=tris[:,1][:,[0,2]];c=tris[:,2][:,[0,2]]
u=b-a;w=c-a;den=u[:,0]*w[:,1]-u[:,1]*w[:,0];good=np.abs(den)>1e-12
inside=[];dist=[]
for i,p in enumerate(local):
 r=p[[0,2]]-a;t=(r[:,0]*w[:,1]-r[:,1]*w[:,0])/np.where(good,den,1);s=(u[:,0]*r[:,1]-u[:,1]*r[:,0])/np.where(good,den,1);valid=good&(s>=0)&(t>=0)&(s+t<=1)
 if not np.any(valid):continue
 ys=tris[:,0,1]+t*(tris[:,1,1]-tris[:,0,1])+s*(tris[:,2,1]-tris[:,0,1]);low=np.min(ys[valid]);hi=np.max(ys[valid]);dd=max(low-p[1],p[1]-hi)
 dist.append((dd,i,local[i],low,hi))
 if dd<0:inside.append((dd,i,local[i],low,hi))
print('INSIDE',len(inside),sorted(inside,key=lambda x:x[0])[:10]);print('CONTACT', sorted(dist,key=lambda x:abs(x[0]))[:15])
print('PADS',[t for t in dist if t[1] in [156,17]])
