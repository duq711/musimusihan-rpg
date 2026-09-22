"""Independent full-body geometry/asset preservation audit, read-only."""
from pathlib import Path
import bpy,json,numpy as np,hashlib
from mathutils.kdtree import KDTree
H=Path(__file__).resolve().parent;SOURCE=H.parent/'player_reference_anatomy_20260922/Gravebound_Reference_Anatomy.blend';CAND=H/'Gravebound_Multiview_Proportions.blend'
def simple(v):
 if isinstance(v,(int,float,str,bool)) or v is None:return v
 if hasattr(v,'to_list'):return v.to_list()
 if hasattr(v,'to_dict'):return v.to_dict()
 try:return list(v)
 except:return str(v)
def load(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));meshes={};metadata={}
 for o in bpy.context.scene.objects:
  metadata[o.name]={k:simple(o[k]) for k in o.keys()}
  if o.type!='MESH':continue
  m=o.data;v=np.empty(len(m.vertices)*3,np.float32);m.vertices.foreach_get('co',v);v=v.reshape(-1,3).astype(float);w=np.array(o.matrix_world);v=v@w[:3,:3].T+w[:3,3]
  m.calc_loop_triangles();t=np.empty(len(m.loop_triangles)*3,np.int32);m.loop_triangles.foreach_get('vertices',t);t=t.reshape(-1,3)
  n=np.array([n.vector[:] for n in m.corner_normals]);n=n@np.linalg.inv(w[:3,:3]);n/=np.maximum(1e-20,np.linalg.norm(n,axis=1))[:,None]
  meshes[o.name]={'v':v,'t':t,'loops':np.array([t.loops[:] for t in m.loop_triangles]),'normals':n,'faces':[list(f.vertices) for f in m.polygons],'uv':[np.array([d.uv[:] for d in l.data]) for l in m.uv_layers],'materials':[m.name for m in m.materials],'matrix':w,'mesh_metadata':{k:simple(m[k]) for k in m.keys()}}
 images={i.name:hashlib.sha256(bytes(i.packed_file.data)).hexdigest() for i in bpy.data.images if i.packed_file}
 return meshes,metadata,images
def box(v):
 if not len(v):return None
 lo=v.min(axis=0);hi=v.max(axis=0);return {'min':lo.tolist(),'max':hi.tolist(),'center':((lo+hi)/2).tolist(),'size':(hi-lo).tolist()}
def section(p,z):
 v=p['v'][p['t']];v=v[(v[:,:,2].min(axis=1)<=z)&(v[:,:,2].max(axis=1)>=z)];out=[]
 for a,b in [(0,1),(1,2),(2,0)]:
  va,vb=v[:,a],v[:,b];dz=vb[:,2]-va[:,2];ok=(np.abs(dz)>1e-12)&((va[:,2]-z)*(vb[:,2]-z)<=0);va,vb,dz=va[ok],vb[ok],dz[ok];out.append(va+(z-va[:,2])[:,None]/dz[:,None]*(vb-va))
 return np.concatenate(out)
def norms(p):
 t=p['v'][p['t']];n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);area=np.linalg.norm(n,axis=1)/2;n/=np.maximum(1e-20,2*area)[:,None];cn=p['normals'][p['loops']].mean(axis=1);return n,area,(n*cn).sum(axis=1)
def pairs(a,b,tol=1e-6):
 tree=KDTree(len(b))
 for i,p in enumerate(b):tree.insert(p,i)
 tree.balance();out=[]
 for i,p in enumerate(a):
  q,j,d=tree.find(p)
  if d<=tol:out.append((i,j))
 return out
A,AM,AI=load(SOURCE);B,BM,BI=load(CAND)
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'candidate_sha256':hashlib.sha256(CAND.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256((H/'gravebound_player_multiview_proportions.glb').read_bytes()).hexdigest(),'same_mesh_names':list(A)==list(B),'packed_images_byte_identical':AI==BI,'packed_image_count':len(AI),'parts':{},'connections':{},'landmarks':{},'sections':{},'notes':['All body dimensions may change. Preservation targets are identity/topology/UV/material data, not old proportions.','Triangle-area tolerance for meaningful winding/degeneracy is 1e-10 square metres. Local area/normal checks do not certify no global self-intersection.']}
for n,a in A.items():
 b=B[n];an,aa,ad=norms(a);bn,ba,bd=norms(b);nontrivial=aa>=1e-10
 p={'topology_identical':a['faces']==b['faces'],'uv_identical':len(a['uv'])==len(b['uv']) and all(np.array_equal(x,y) for x,y in zip(a['uv'],b['uv'])),'material_names_identical':a['materials']==b['materials'],'world_transform_identical':bool(np.array_equal(a['matrix'],b['matrix'])),'mesh_metadata_identical':a['mesh_metadata']==b['mesh_metadata'],'original_object_metadata_preserved':all(k in BM[n] and BM[n][k]==v for k,v in AM[n].items()),'added_object_metadata_keys':[k for k in BM[n] if k not in AM[n]],'new_nontrivial_degenerate_triangles':int(((aa>=1e-10)&(ba<1e-12)).sum()),'new_nontrivial_opposed_normals':int(((ad>0)&(bd<=0)&nontrivial).sum()),'source_opposed_normals_any_size':int((ad<=0).sum()),'candidate_opposed_normals_any_size':int((bd<=0).sum()),'candidate_nontrivial_opposed_normals':int(((bd<=0)&(ba>=1e-10)).sum()),'significant_triangle_min_area_ratio':float((ba[nontrivial]/aa[nontrivial]).min()),'source_bounds':box(a['v']),'candidate_bounds':box(b['v'])}
 report['parts'][n]=p
for side in ['L','R']:
 arm='Gravebound_FP_'+side+'_Arm';hand='Gravebound_FP_'+side+'_Hand';torso='Gravebound_QuiltedTorso';pants='Gravebound_Trousers_'+side;boot='Gravebound_Boot_'+side
 for key,na,nb in [('shoulder',torso,arm),('wrist',arm,hand)]:
  pp=pairs(A[na]['v'],A[nb]['v']);dist=[np.linalg.norm(B[na]['v'][i]-B[nb]['v'][j]) for i,j in pp];report['connections'][side+'_'+key]={'source_coincident_vertices':len(pp),'candidate_max_gap_m':float(max(dist,default=0)),'candidate_join_bounds':box(np.array([B[na]['v'][i] for i,j in pp]))}
  if key=='wrist':report['landmarks'][side+'_wrist_join']=report['connections'][side+'_'+key]['candidate_join_bounds']['center']
 report['landmarks'][side+'_fingertip']=B[hand]['v'][B[hand]['v'][:,2].argmin()].tolist()
 report['landmarks'][side+'_elbow_section_center']=box(section(B[arm],1.15793))['center']
 report['landmarks'][side+'_boot_top']=B[boot]['v'][B[boot]['v'][:,2].argmax()].tolist()
 # Track closest old pants/boot vertex pairs in the original overlap band.
 tree=KDTree(len(A[boot]['v']))
 for i,p in enumerate(A[boot]['v']):tree.insert(p,i)
 tree.balance();rows=[]
 for i,p in enumerate(A[pants]['v']):
  if .44<=p[2]<=.49:
   q,j,d=tree.find(p)
   if d<.012:rows.append((d,float(np.linalg.norm(B[pants]['v'][i]-B[boot]['v'][j]))))
 report['connections'][side+'_pants_boot_overlap']={'coincident_source_vertices':len(pairs(A[pants]['v'],A[boot]['v'])),'tracked_near_pairs':len(rows),'source_distance_range_m':[min(a for a,b in rows),max(a for a,b in rows)],'candidate_same_pair_distance_range_m':[min(b for a,b in rows),max(b for a,b in rows)],'candidate_pants_bottom_z':float(B[pants]['v'][:,2].min()),'candidate_boot_top_z':float(B[boot]['v'][:,2].max()),'note':'Pants are tucked inside boot; pair distances measure old nearby vertices, not a visible surface gap.'}
for n in ['Gravebound_QuiltedTorso','Gravebound_AnatomicalHead','Gravebound_FP_L_Arm','Gravebound_FP_L_Hand','Gravebound_Trousers_L','Gravebound_Trousers_R','Gravebound_Boot_L','Gravebound_Boot_R']:
 zs=[.025,.05,.075,.1,.125,.15,.175,.2,.25,.3,.35,.4,.425,.4354,.45,.5,.53576,.55,.6,.65,.7,.75,.78162,.8,.85,.9,.93089,.95,.98483,1.,1.05,1.1,1.15793,1.2,1.25,1.3,1.35,1.37368,1.4,1.45,1.5,1.55,1.6,1.65,1.7]
 report['sections'][n]=[]
 for z in zs:
  av=section(A[n],z);bv=section(B[n],z)
  if len(av) or len(bv):report['sections'][n].append({'z':z,'source':box(av),'candidate':box(bv)})
head=B['Gravebound_AnatomicalHead']['v'];report['landmarks']['crown']=head[head[:,2].argmax()].tolist();report['landmarks']['belt_center']=box(B['Gravebound_LeatherBelt']['v'])['center'];pv=np.concatenate([B['Gravebound_Trousers_L']['v'],B['Gravebound_Trousers_R']['v']]);mid=pv[np.abs(pv[:,0])<.005];report['landmarks']['crotch_bridge_lowest']=mid[mid[:,2].argmin()].tolist();report['world_bounds']=box(np.concatenate([p['v'] for p in B.values()]))
report['scope_pass']=report['same_mesh_names'] and AI==BI and all(all(p[k] for k in ['topology_identical','uv_identical','material_names_identical','world_transform_identical','mesh_metadata_identical','original_object_metadata_preserved']) and p['new_nontrivial_degenerate_triangles']==0 and p['new_nontrivial_opposed_normals']==0 for p in report['parts'].values())
(H/'audit_current.json').write_text(json.dumps(report,indent=2)+'\n');print('AUDIT',json.dumps({'hash':report['glb_sha256'],'scope_pass':report['scope_pass'],'landmarks':report['landmarks'],'connections':report['connections'],'bad_parts':{n:p for n,p in report['parts'].items() if p['new_nontrivial_opposed_normals'] or p['new_nontrivial_degenerate_triangles']}}),flush=True)
