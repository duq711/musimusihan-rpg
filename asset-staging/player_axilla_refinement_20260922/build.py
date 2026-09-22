"""Fair the local chest/sleeve saddle while preserving approved proportions.

Only cloth depth changes: X/Z and every other object remain unchanged. One continuous
depth field keeps both sides of the split coincident with matching shading.
UVs, triangle indices, materials and all bitmap data are preserved.
"""
from pathlib import Path
import bpy,sys,json,hashlib,numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
SOURCE=HERE.parent/'player_multiview_proportions_20260922/Gravebound_Multiview_Proportions.blend'
NAMES=['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
def smooth(x):
 x=np.clip(x,0.,1.);return x*x*(3.-2.*x)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
# Cache shared coordinates without replacing production topology.
lookup={};vertices=[];indices={};old_normals={};triangles=[]
for name in NAMES:
 o=bpy.data.objects[name];me=o.data;ids=[]
 old_normals[name]=[n.vector.copy() for n in me.corner_normals]
 for v in me.vertices:
  p=o.matrix_world@v.co;k=tuple(round(c,6) for c in p)
  if k not in lookup:lookup[k]=len(vertices);vertices.append(tuple(p))
  ids.append(lookup[k])
 indices[name]=np.array(ids)
 me.calc_loop_triangles();triangles.extend([[ids[i] for i in t.vertices] for t in me.loop_triangles])
p=np.array(vertices);t=np.array(triangles);q=p.copy()
x=abs(p[:,0]);z=p[:,2];y=abs(p[:,1])
# Short, soft saddle below the shoulder cap. The underarm opening and outer
# silhouette are pinned; this fills the unnaturally long vertical furrow.
w=smooth((x-.132)/.025)*smooth((.234-x)/.025)*smooth((z-1.264)/.044)*smooth((1.463-z)/.030)*smooth((y-.016)/.034)
# Moving quadratic surface fits use spatial distance, rather than irregular
# remesh edge density. This avoids ripple-shaped shading from tiny triangles.
# Evaluate one smooth displacement field for every part, including shared seams.
fields=[]
for side in (-1.,1.):
 for front in (-1.,1.):
  selected=np.flatnonzero((p[:,0]*side>.075)&(p[:,0]*side<.29)&(p[:,1]*front>.016)&(z>1.22)&(z<1.49))
  tree=KDTree(len(selected))
  for k,i in enumerate(selected):tree.insert((p[i,0],p[i,2],0),k)
  tree.balance();fields.append((side,front,selected,tree))
def fitted_height(px,pz,sel,tree,radius,values):
 near=tree.find_range((px,pz,0),radius)
 if len(near)<12:
  near=tree.find_n((px,pz,0),12)
 ids=sel[[item[1] for item in near]];d=p[ids][:,[0,2]]-np.array([px,pz]);d/=radius
 weights=np.maximum(0,1.-(d*d).sum(axis=1))**3
 A=np.column_stack([np.ones(len(d)),d[:,0],d[:,1],d[:,0]**2,d[:,0]*d[:,1],d[:,1]**2])
 return float(np.linalg.lstsq(A*weights[:,None],values[ids]*weights,rcond=None)[0][0])
# Leave twenty percent of the source depth so the deformation stays invertible,
# while smoothly replacing the excessive groove with the fitted cloth surface.
def displacement(point):
 px,py,pz=point;xx=abs(px);yy=abs(py)
 weight=float(smooth((xx-.132)/.025)*smooth((.234-xx)/.025)*smooth((pz-1.264)/.044)*smooth((1.463-pz)/.030)*smooth((yy-.016)/.034))
 if weight<1e-10:return 0.
 side=1. if px>=0 else -1.;front=1. if py>=0 else -1.
 _,_,sel,tree=next(f for f in fields if f[0]==side and f[1]==front)
 target=fitted_height(px,pz,sel,tree,.042,p[:,1])
 return (target-py)*weight*.8
for i in np.flatnonzero(w>0):q[i,1]+=displacement(p[i])
# Rotate the original custom normal with the local geometric surface change.
# This retains its pre-existing smoothing and keeps the untouched region exact.
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'parts':{},'method':'Compact quadratic surface fit, 42mm radius','axes_changed':['Y'],'region_guard':{'abs_x':[.132,.234],'z':[1.264,1.463]}}
for name in NAMES:
 o=bpy.data.objects[name];me=o.data;ids=indices[name];inv=o.matrix_world.inverted();nw=o.matrix_world.to_3x3().inverted().transposed();nl=o.matrix_world.to_3x3().transposed()
 # Transform source shading by the continuous deformation Jacobian. The
 # zero-weight border retains the exact source normal.
 ns=[];normal_transforms={}
 for i in set(ids):
  if w[i]<=0:continue
  gradient=[]
  for axis in range(3):
   h=np.zeros(3);h[axis]=.00002
   gradient.append((displacement(p[i]+h)-displacement(p[i]-h))/.00004)
  J=np.eye(3);J[1]+=gradient
  if np.linalg.det(J)<=.05:raise RuntimeError(('Noninvertible fairing',p[i],J))
  normal_transforms[i]=np.linalg.inv(J).T
 for loop,n in zip(me.loops,old_normals[name]):
  i=ids[loop.vertex_index]
  if i in normal_transforms:
   normal=np.array(nw@n);v=Vector(normal_transforms[i]@normal).normalized();ns.append((nl@v).normalized())
  else:ns.append(n)
 for v,i in zip(me.vertices,ids):
  if w[i]>0:
   original=o.matrix_world@v.co;original.y+=float(q[i,1]-p[i,1]);v.co=inv@original
 me.update();me.normals_split_custom_set(ns)
 delta=q[ids]-p[ids];changed=np.linalg.norm(delta,axis=1)>1e-7
 report['parts'][name]={'changed':int(changed.sum()),'max_displacement_m':float(np.linalg.norm(delta,axis=1).max())}
 o['axilla_revision']='Local welded-surface fairing; approved silhouette and limb lengths preserved'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'Gravebound_Axilla_Refinement.blend'),compress=True)
out=HERE/'gravebound_player_axilla_refinement.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report['glb_sha256']=hashlib.sha256(out.read_bytes()).hexdigest();(HERE/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('AXILLA BUILD PASS',json.dumps(report),flush=True)
