import bpy,numpy as np,json,os
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
s=Path(__file__).resolve().parents[1];variant=os.environ.get('TORCH_VARIANT','full');x=np.load(s/'audit/fit_input_reweighted.npz');v=np.load(s/('audit/fitted_vertices_'+variant+'.npy'));faces=x['faces'];d=json.loads((s/('audit/fitted_pose_'+variant+'.json')).read_text())
p=np.concatenate([v,v[faces].mean(1),((v[faces]+np.roll(v[faces],1,axis=1))/2).reshape(-1,3)])
a=np.array(d['shaft_in_hand']['axis']);r=p-np.array(d['shaft_in_hand']['center']);along=r@a;h=np.array(d['handle_rings']);dist=np.linalg.norm(r-along[:,None]*a,axis=1)-np.interp(.12+along,h[:,0],h[:,1])*d['radius_ratio']
names=list(x['names']);W=x['weights'];digits=['thumb','index','middle','ring','little'];masks={}
for digit in digits:
 weight=sum(W[:,names.index(digit+str(i))] for i in range(3));masks[digit]=weight>.75
checks={};constraints=[]
# Open basal boundaries excluded by requiring nearest point inside a triangle.
for i,first in enumerate(digits):
 for second in digits[i+1:]:
  triangles=faces[masks[second][faces].all(1)];tree=BVHTree.FromPolygons([Vector(p) for p in v],triangles.tolist(),all_triangles=True)
  suspect=[]
  for idx in np.where(masks[first])[0]:
   co,n,fi,distance=tree.find_nearest(Vector(v[idx]))
   if co is None or distance>.008:continue
   signed=(Vector(v[idx])-co).dot(n)
   if signed<-.001:
    tri=v[triangles[fi]];u=tri[1]-tri[0];w=tri[2]-tri[0];p0=np.array(co)-tri[0];uv=np.linalg.lstsq(np.column_stack([u,w]),p0,rcond=None)[0]
    if uv.min()>.025 and uv.sum()<.975:
     suspect.append([int(idx),float(signed)]);constraints.append([int(idx),*map(int,triangles[fi]),float(1-uv.sum()),float(uv[0]),float(uv[1])])
  checks[first+'_'+second]={'suspect_interior_samples':len(suspect),'maximum_depth_m':max([-t[1] for t in suspect],default=0)}
# Track actual material thickness of palm away from bend creases, not screen width.
base=x['vertices'];mask=(base[:,1]>.015)&(base[:,1]<.05)&(abs(base[:,0])<.025)
report={'variant':variant,'shaft_samples':len(p),'minimum_shaft_clearance_m':float(dist.min()),'shaft_penetration_samples':int((dist<0).sum()),'finger_surface_screening':checks,'palm_normal_extent_rest_m':float(np.ptp(base[mask,2])),'palm_normal_extent_posed_m':float(np.ptp(v[mask,2])),'limits':'Nearest-surface screening on interior triangles with >1mm depth; inspect rendered views as well. Not an exhaustive mesh boolean.'}
cp=s/('audit/collision_constraints_'+variant+'.json');prior=json.loads(cp.read_text()) if cp.exists() else [];cp.write_text(json.dumps(prior+constraints))
(s/('audit/surface_'+variant+'.json')).write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
