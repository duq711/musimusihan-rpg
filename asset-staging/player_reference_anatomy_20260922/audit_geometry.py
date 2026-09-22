"""Independent read-only before/after mesh audit for the reference anatomy revision."""
from pathlib import Path
import bpy, json, hashlib, numpy as np, sys
from mathutils import Vector, Matrix
HERE=Path(__file__).resolve().parent
SOURCE=HERE.parent/'player_neck_arm_flow_20260922/Gravebound_Neck_Arm_Flow.blend'
CANDIDATE=HERE/'Gravebound_Reference_Anatomy.blend'
NAMES=['Gravebound_AnatomicalHead','Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
sys.path.insert(0,str(HERE))
from deformation import garment

def load(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));out={}
 for o in bpy.context.scene.objects:
  if o.type!='MESH':continue
  m=o.data
  v=np.empty(len(m.vertices)*3,np.float32);m.vertices.foreach_get('co',v);v=v.reshape(-1,3).astype(float)
  world=np.array(o.matrix_world);v=v@world[:3,:3].T+world[:3,3]
  m.calc_loop_triangles();tri=np.empty(len(m.loop_triangles)*3,np.int32);m.loop_triangles.foreach_get('vertices',tri);tri=tri.reshape(-1,3)
  norms=np.array([n.vector[:] for n in m.corner_normals]);nworld=np.linalg.inv(world[:3,:3]).T;norms=norms@nworld.T
  norms/=np.maximum(1e-20,np.linalg.norm(norms,axis=1))[:,None]
  tloops=np.array([t.loops[:] for t in m.loop_triangles])
  f=[list(f.vertices) for f in m.polygons]
  uv=[np.array([u.uv[:] for u in l.data]) for l in m.uv_layers]
  out[o.name]={'v':v,'tri':tri,'norms':norms,'tloops':tloops,'f':f,'uv':uv,'materials':[x.name for x in m.materials]}
 return out

def bounds(v):
 lo=v.min(axis=0);hi=v.max(axis=0)
 return {'min':lo.tolist(),'max':hi.tolist(),'size':(hi-lo).tolist(),'center':((hi+lo)/2).tolist()}

def section(part,z):
 v=part['v'][part['tri']];v=v[(v[:,:,2].min(axis=1)<=z)&(v[:,:,2].max(axis=1)>=z)]
 pts=[]
 for a,b in [(0,1),(1,2),(2,0)]:
  pa,pb=v[:,a],v[:,b];dz=pb[:,2]-pa[:,2];ok=(np.abs(dz)>1e-12)&((pa[:,2]-z)*(pb[:,2]-z)<=0)
  pa,pb,dz=pa[ok],pb[ok],dz[ok];pts.append(pa+((z-pa[:,2])/dz)[:,None]*(pb-pa))
 return np.concatenate(pts)

def normals(p):
 t=p['v'][p['tri']];n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);area=np.linalg.norm(n,axis=1)
 n=n/np.maximum(area,1e-20)[:,None];cn=p['norms'][p['tloops']].mean(axis=1)
 dots=(n*cn).sum(axis=1)
 return n,area,dots

before=load(SOURCE);after=load(CANDIDATE)
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(CANDIDATE.read_bytes()).hexdigest(),'output_glb_sha256':hashlib.sha256((HERE/'gravebound_player_reference_anatomy.glb').read_bytes()).hexdigest(),'parts':{},'preserved_meshes':[],'sections':{},'scope':'Read-only vertices, topology, UV, material names, normals, local deformation and section audit. Not exhaustive triangle self-intersection or anatomical correctness certification.'}
for name,a in before.items():
 b=after[name];d=np.linalg.norm(b['v']-a['v'],axis=1)
 face_equal=a['f']==b['f'];uv_equal=all(np.array_equal(x,y) for x,y in zip(a['uv'],b['uv'])) and len(a['uv'])==len(b['uv']);mat_equal=a['materials']==b['materials']
 an,aa,ad=normals(a);bn,ba,bd=normals(b)
 valid=aa>1e-12
 p={'max_vertex_displacement_m':float(d.max()),'topology_identical':face_equal,'uv_identical':uv_equal,'material_names_identical':mat_equal,'normal_change_max':float(np.max(np.linalg.norm(a['norms']-b['norms'],axis=1))),'min_triangle_double_area_ratio':float((ba[valid]/aa[valid]).min()),'new_degenerate_triangles':int(((aa>1e-12)&(ba<=1e-12)).sum()),'new_opposed_corner_normals':int(((ad>0)&(bd<=0)&valid).sum()),'source_opposed_corner_normals':int(((ad<=0)&valid).sum()),'candidate_opposed_corner_normals':int(((bd<=0)&valid).sum()),'triangles_rotated_over_90_degrees':int((((an*bn).sum(axis=1)<0)&valid).sum())}
 if name==NAMES[1]:
  ids=np.where((ad>0)&(bd<=0)&valid)[0]
  p['new_opposed_significant_triangles']=int(((ad>0)&(bd<=0)&(aa/2>=1e-10)).sum())
  p['opposed_triangle_source_area_tolerance_m2']=1e-10
  p['new_opposed_details']=[{'triangle_index':int(i),'vertices':a['tri'][i].tolist(),'source_vertices':a['v'][a['tri'][i]].tolist(),'candidate_vertices':b['v'][b['tri'][i]].tolist(),'source_area_m2':float(aa[i]/2),'candidate_area_m2':float(ba[i]/2),'candidate_normal_dot':float(bd[i])} for i in ids]
 if name not in NAMES:
  p['exactly_preserved']=bool(np.array_equal(a['v'],b['v']) and face_equal and uv_equal and mat_equal and np.array_equal(a['norms'],b['norms']))
  assert p['exactly_preserved'],name
  report['preserved_meshes'].append(name)
 if name==NAMES[0]:
  mask=a['v'][:,2]>=1.51;p['face_z_gte_1_51_max_displacement_m']=float(d[mask].max());assert p['face_z_gte_1_51_max_displacement_m']==0
 if name.endswith('_Arm'):
  mask=a['v'][:,2]<=.920;p['cuff_z_lte_0_920_max_displacement_m']=float(d[mask].max());assert p['cuff_z_lte_0_920_max_displacement_m']==0
  p['forearm_bands']={}
  for low,high in [(1.02,1.12),(.995,1.095),(.98,1.08),(1.00,1.10)]:
   am=(a['v'][:,2]>=low)&(a['v'][:,2]<=high);bm=(b['v'][:,2]>=low)&(b['v'][:,2]<=high)
   p['forearm_bands'][str((low,high))]={'before':bounds(a['v'][am]),'after':bounds(b['v'][bm]),'source_z_range_of_candidate_band':[float(a['v'][bm,2].min()),float(a['v'][bm,2].max())]}
  mask=np.abs(a['v'][:,2]-1.155)<.003;p['authored_elbow_band_mean_z_delta_m']=float((b['v'][mask,2]-a['v'][mask,2]).mean())
 assert face_equal and uv_equal and mat_equal
 assert p['new_degenerate_triangles']==0
 report['parts'][name]=p
 if name in NAMES:
  zs=[1.445,1.450,1.460,1.470,1.480,1.49,1.50,1.51,1.52] if name==NAMES[0] else [1.075,1.15,1.2,1.25,1.275,1.3,1.325,1.35,1.375,1.4,1.425,1.45] if name==NAMES[1] else [.9,.95,1.,1.075,1.1,1.129,1.15,1.175,1.2,1.225,1.25,1.275,1.3,1.325,1.35,1.375,1.4,1.425,1.44]
  report['sections'][name]=[]
  for z in zs:
   av=section(a,z);bv=section(b,z)
   report['sections'][name].append({'z':z,'before':bounds(av) if len(av) else None,'after':bounds(bv) if len(bv) else None})
# Shared source seam positions stay shared after applying the same continuous deformation.
seams=[]
for arm in NAMES[2:]:
 lookup={tuple(np.round(p,5)):i for i,p in enumerate(before[arm]['v'])}
 pairs=[(i,lookup[tuple(np.round(p,5))]) for i,p in enumerate(before[NAMES[1]]['v']) if tuple(np.round(p,5)) in lookup]
 oldg=[float(np.linalg.norm(before[NAMES[1]]['v'][i]-before[arm]['v'][j])) for i,j in pairs]
 newg=[float(np.linalg.norm(after[NAMES[1]]['v'][i]-after[arm]['v'][j])) for i,j in pairs]
 seams.append({'arm':arm,'source_shared_positions':len(pairs),'source_max_gap_m':max(oldg,default=None),'candidate_max_gap_m':max(newg,default=None)})
report['seams']=seams
# Independent interior sampling checks local orientation between authored vertices.
minimum=10.;at=None;negative=0;count=0;eps=.00002
for x in np.arange(0,.38,.02):
 for y in np.arange(-.16,.161,.025):
  for z in np.arange(.925,1.501,.02):
   p=Vector((x,y,z));cols=[]
   for k in range(3):
    d=Vector();d[k]=eps;cols.append((garment(p+d)-garment(p-d))/(2*eps))
   det=Matrix(cols).transposed().determinant();count+=1
   if det<minimum:minimum=det;at=list(p)
   if det<=0:negative+=1
report['volume_grid_jacobian']={'samples':count,'minimum_determinant':minimum,'minimum_at':at,'nonpositive_samples':negative}
assert negative==0
report['pass_scope_checks']=True
(HERE/'geometry_audit.json').write_text(json.dumps(report,indent=2)+'\n')
print('REFERENCE AUDIT COMPLETE',json.dumps({'hash':report['output_glb_sha256'],'preserved_meshes':len(report['preserved_meshes']),'seams':seams,'grid':report['volume_grid_jacobian'],'new_opposed_significant_triangles':report['parts'][NAMES[1]]['new_opposed_significant_triangles']}),flush=True)
