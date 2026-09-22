"""Independent read-only audit of the localized axilla/shoulder edit.

Compare to the approved full-body source, not to older discarded proportions.
The broad geometric guard is abs(X) .11-.29 m, Z 1.19-1.47 m.
No source file, model or production setting is written by this script.
"""
from pathlib import Path
import bpy, json, hashlib, numpy as np
from mathutils.kdtree import KDTree
H=Path(__file__).resolve().parent
SOURCE=H.parent/'player_multiview_proportions_20260922/Gravebound_Multiview_Proportions.blend'
CANDIDATE=H/'Gravebound_Axilla_Refinement.blend'
GLB=H/'gravebound_player_axilla_refinement.glb'
TARGETS={'Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm'}
POSITION_TOLERANCE=5e-7
JOIN_TOLERANCE=1e-6
AREA_TOLERANCE=1e-10

def simple(v):
 if isinstance(v,(int,float,str,bool)) or v is None:return v
 if hasattr(v,'to_list'):return v.to_list()
 if hasattr(v,'to_dict'):return v.to_dict()
 if hasattr(v,'name'):return v.name
 try:return [simple(x) for x in v]
 except:return str(v)
def load(path):
 bpy.ops.wm.open_mainfile(filepath=str(path));meshes={};objects={}
 for o in bpy.context.scene.objects:
  objects[o.name]={'type':o.type,'matrix':np.array(o.matrix_world).tolist(),'parent':o.parent.name if o.parent else None,'metadata':{k:simple(o[k]) for k in o.keys()}}
  if o.type!='MESH':continue
  m=o.data;v=np.empty(len(m.vertices)*3,np.float32);m.vertices.foreach_get('co',v);v=v.reshape(-1,3).astype(float);w=np.array(o.matrix_world);v=v@w[:3,:3].T+w[:3,3]
  m.calc_loop_triangles();t=np.empty(len(m.loop_triangles)*3,np.int32);m.loop_triangles.foreach_get('vertices',t);t=t.reshape(-1,3)
  n=np.array([n.vector[:] for n in m.corner_normals]);n=n@np.linalg.inv(w[:3,:3]);n/=np.maximum(1e-20,np.linalg.norm(n,axis=1))[:,None]
  loopverts=np.array([l.vertex_index for l in m.loops]);vn=np.zeros_like(v);np.add.at(vn,loopverts,n);vn/=np.maximum(1e-20,np.linalg.norm(vn,axis=1))[:,None]
  meshes[o.name]={'v':v,'t':t,'triangle_loops':np.array([t.loops[:] for t in m.loop_triangles]),'normals':n,'loop_vertex_indices':loopverts,'vertex_normals':vn,'faces':[list(f.vertices) for f in m.polygons],'uv':[np.array([d.uv[:] for d in l.data]) for l in m.uv_layers],'materials':[m.name for m in m.materials],'metadata':{k:simple(m[k]) for k in m.keys()}}
 images={i.name:hashlib.sha256(bytes(i.packed_file.data)).hexdigest() for i in bpy.data.images if i.packed_file}
 materials={}
 for m in bpy.data.materials:
  record={'diffuse_color':list(m.diffuse_color),'roughness':m.roughness,'metallic':m.metallic,'use_nodes':m.use_nodes,'nodes':{},'links':[]}
  if m.node_tree:
   for n in m.node_tree.nodes:
    record['nodes'][n.name]={'type':n.bl_idname,'inputs':{p.name:simple(p.default_value) for p in n.inputs if hasattr(p,'default_value')},'image':getattr(getattr(n,'image',None),'name',None),'operation':getattr(n,'operation',None),'blend_type':getattr(n,'blend_type',None)}
   record['links']=[(l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in m.node_tree.links]
  materials[m.name]=record
 return meshes,objects,images,materials

def box(v):
 if not len(v):return None
 lo=v.min(axis=0);hi=v.max(axis=0);return {'min':lo.tolist(),'max':hi.tolist(),'center':((lo+hi)/2).tolist(),'size':(hi-lo).tolist()}
def triangle_normals(p):
 t=p['v'][p['t']];n=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);area=np.linalg.norm(n,axis=1)/2;n/=np.maximum(1e-20,2*area)[:,None];cn=p['normals'][p['triangle_loops']].mean(axis=1);return n,area,(n*cn).sum(axis=1)
def shared_pairs(a,b):
 tree=KDTree(len(b))
 for i,p in enumerate(b):tree.insert(p,i)
 tree.balance();out=[]
 for i,p in enumerate(a):
  q,j,d=tree.find(p)
  if d<=JOIN_TOLERANCE:out.append((i,j))
 return out

def run():
 if not CANDIDATE.exists():raise SystemExit('Candidate Blender file does not exist yet; no audit was run.')
 A,AO,AI,AM=load(SOURCE);B,BO,BI,BM=load(CANDIDATE)
 report={'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'candidate':str(CANDIDATE),'candidate_sha256':hashlib.sha256(CANDIDATE.read_bytes()).hexdigest(),'glb_sha256':hashlib.sha256(GLB.read_bytes()).hexdigest() if GLB.exists() else None,'same_object_names':set(AO)==set(BO),'same_mesh_names':set(A)==set(B),'packed_images_byte_identical':AI==BI,'packed_image_count':len(AI),'material_graphs_identical':AM==BM,'position_noise_tolerance_m':POSITION_TOLERANCE,'broad_allowed_region':{'abs_x':[.11,.29],'z':[1.19,1.47]},'detailed_allowed_region':{'abs_x':[.132,.234],'z':[1.264,1.463],'allowed_displacement_axes':['Y']},'meaningful_triangle_area_m2':AREA_TOLERANCE,'parts':{},'unchanged_objects':{},'shared_boundaries':{},'issues':[],'normal_rotation_note':'Normal rotation over 90 degrees is diagnostic, not automatically inverted winding. A deep saddle can change slope while retaining its exterior-facing direction. Check geometric normals against transported custom normals and preserved XZ-projection winding instead.','limits':'Bounded preservation/continuity/local triangle audit. Does not certify global self-intersection absence or visual/anatomical acceptance.'}
 for n,a in A.items():
  if n not in B:report['issues'].append('Missing mesh '+n);continue
  b=B[n];topology=a['faces']==b['faces'];uv=len(a['uv'])==len(b['uv']) and all(np.array_equal(x,y) for x,y in zip(a['uv'],b['uv']));d=np.linalg.norm(b['v']-a['v'],axis=1);changed=d>POSITION_TOLERANCE
  an,aa,ad=triangle_normals(a);bn,ba,bd=triangle_normals(b);significant=aa>=AREA_TOLERANCE
  guard=(np.abs(a['v'][:,0])>=.11)&(np.abs(a['v'][:,0])<=.29)&(a['v'][:,2]>=1.19)&(a['v'][:,2]<=1.47)
  detailed=(np.abs(a['v'][:,0])>=.132)&(np.abs(a['v'][:,0])<=.234)&(a['v'][:,2]>=1.264)&(a['v'][:,2]<=1.463)
  p={'topology_identical':topology,'uv_identical':uv,'material_slots_identical':a['materials']==b['materials'],'mesh_metadata_identical':a['metadata']==b['metadata'],'original_object_metadata_preserved':all(k in BO[n]['metadata'] and BO[n]['metadata'][k]==v for k,v in AO[n]['metadata'].items()),'changed_vertex_count':int(changed.sum()),'maximum_vertex_displacement_m':float(d.max()),'changed_source_bounds':box(a['v'][changed]),'changed_candidate_bounds':box(b['v'][changed]),'changed_outside_broad_guard':int((changed&~guard).sum()),'changed_outside_detailed_guard':int((changed&~detailed).sum()),'max_world_x_displacement_m':float(np.abs(b['v'][:,0]-a['v'][:,0]).max()),'max_world_z_displacement_m':float(np.abs(b['v'][:,2]-a['v'][:,2]).max()),'maximum_outside_guard_displacement_m':float(d[~guard].max()) if (~guard).any() else 0.,'new_nontrivial_degenerate_triangles':int(((aa>=AREA_TOLERANCE)&(ba<1e-12)).sum()),'new_nontrivial_opposed_corner_normals':int(((ad>0)&(bd<=0)&significant).sum()),'significant_triangles_rotated_over_90_degrees':int((((an*bn).sum(axis=1)<0)&significant).sum()),'projected_xz_winding_reversed':int(((an[:,1]*bn[:,1]<0)&(np.abs(an[:,1]*aa)>1e-12)&significant).sum()),'source_opposed_normals_any_area':int((ad<=0).sum()),'candidate_opposed_normals_any_area':int((bd<=0).sum()),'minimum_significant_triangle_area_ratio':float((ba[significant]/aa[significant]).min())}
  bad_ids=np.where(significant&(((ad>0)&(bd<=0))|((an*bn).sum(axis=1)<0)))[0]
  p['problem_triangle_details']=[{'triangle_index':int(i),'source_area_m2':float(aa[i]),'candidate_area_m2':float(ba[i]),'source_center':a['v'][a['t'][i]].mean(axis=0).tolist(),'candidate_normal_dot':float(bd[i])} for i in bad_ids]
  if n not in TARGETS:
   p['exactly_preserved']=np.array_equal(a['v'],b['v']) and np.array_equal(a['normals'],b['normals']) and topology and uv and a['materials']==b['materials'] and a['metadata']==b['metadata'] and AO[n]==BO[n]
   if not p['exactly_preserved']:report['issues'].append('Non-target mesh changed: '+n)
  else:
   if p['changed_outside_broad_guard'] or p['changed_outside_detailed_guard']:report['issues'].append('Change outside shoulder/axilla guard: '+n)
   if p['max_world_x_displacement_m']>POSITION_TOLERANCE or p['max_world_z_displacement_m']>POSITION_TOLERANCE:report['issues'].append('World X/Z changed in depth-only refit: '+n)
  for k in ['topology_identical','uv_identical','material_slots_identical','mesh_metadata_identical','original_object_metadata_preserved']:
   if not p[k]:report['issues'].append(n+': '+k+' failed')
  for k in ['new_nontrivial_degenerate_triangles','new_nontrivial_opposed_corner_normals','projected_xz_winding_reversed']:
   if p[k]:report['issues'].append(n+': '+k+'='+str(p[k]))
  report['parts'][n]=p
 for n,a in AO.items():
  if n in TARGETS:continue
  report['unchanged_objects'][n]=n in BO and a==BO[n]
  if not report['unchanged_objects'][n]:report['issues'].append('Non-target object metadata/transform changed: '+n)
 for side in ['L','R']:
  for label,na,nb in [('shoulder','Gravebound_QuiltedTorso','Gravebound_FP_'+side+'_Arm'),('wrist','Gravebound_FP_'+side+'_Arm','Gravebound_FP_'+side+'_Hand')]:
   pp=shared_pairs(A[na]['v'],A[nb]['v']);oldgap=[];gap=[];oldangles=[];angles=[];outliers=[]
   for i,j in pp:
    oldgap.append(float(np.linalg.norm(A[na]['v'][i]-A[nb]['v'][j])));gap.append(float(np.linalg.norm(B[na]['v'][i]-B[nb]['v'][j])))
    oldangles.append(float(np.degrees(np.arccos(np.clip(np.dot(A[na]['vertex_normals'][i],A[nb]['vertex_normals'][j]),-1,1)))))
    angles.append(float(np.degrees(np.arccos(np.clip(np.dot(B[na]['vertex_normals'][i],B[nb]['vertex_normals'][j]),-1,1)))))
    if gap[-1]>JOIN_TOLERANCE or angles[-1]-oldangles[-1]>.5:outliers.append({'first_vertex':i,'second_vertex':j,'source_position':A[na]['v'][i].tolist(),'candidate_gap_m':gap[-1],'normal_angle_increase_deg':angles[-1]-oldangles[-1]})
   row={'source_shared_vertex_count':len(pp),'source_max_gap_m':max(oldgap,default=0),'candidate_max_gap_m':max(gap,default=0),'source_max_normal_angle_deg':max(oldangles,default=0),'candidate_max_normal_angle_deg':max(angles,default=0),'source_normal_angle_p95_deg':float(np.percentile(oldangles,95)) if oldangles else 0,'candidate_normal_angle_p95_deg':float(np.percentile(angles,95)) if angles else 0,'candidate_normal_angle_increase_max_deg':float(max((b-a for a,b in zip(oldangles,angles)),default=0)),'candidate_shared_bounds':box(np.array([B[na]['v'][i] for i,j in pp])),'outliers':outliers}
   report['shared_boundaries'][side+'_'+label]=row
   if not pp or row['candidate_max_gap_m']>JOIN_TOLERANCE:report['issues'].append('Shared boundary separated: '+side+'_'+label)
   # Source normals have their own tiny numerical mismatch. Allow .5 degrees
   # of additional rounding/averaging uncertainty, never a visible normal seam.
   if row['candidate_normal_angle_increase_max_deg']>.5:report['issues'].append('Normal continuity worsened: '+side+'_'+label)
 for k in ['same_object_names','same_mesh_names','packed_images_byte_identical','material_graphs_identical']:
  if not report[k]:report['issues'].append(k+' failed')
 report['pass']=not report['issues']
 (H/'audit_local.json').write_text(json.dumps(report,indent=2)+'\n')
 lines=['# Local axilla refinement audit','',f"Candidate GLB SHA-256: `{report['glb_sha256']}`.",'',f"Result: {'PASS' if report['pass'] else 'ISSUES FOUND'}.",'','Comparison is read-only against the approved full-body source. Only torso and two sleeve meshes may change. The broad guard is abs(X) .11-.29 m and Z 1.19-1.47 m; the detailed candidate mask is abs(X) .132-.234 m and Z 1.264-1.463 m. Only world Y depth may change; world X/Z silhouette coordinates must remain fixed. Guards are measured on original vertices. Position tolerance is .0005 mm for floating-point roundoff.','',f"Packed images unchanged: {report['packed_images_byte_identical']} ({len(AI)} images). Material graphs unchanged: {report['material_graphs_identical']}.",'','| Changed part | Vertices | Max displacement, mm | Outside guard |','|---|---:|---:|---:|']
 for n in sorted(TARGETS):
  p=report['parts'][n];lines.append(f"| {n} | {p['changed_vertex_count']} | {p['maximum_vertex_displacement_m']*1000:.4f} | {p['changed_outside_broad_guard']} |")
 lines+=['','## Shared boundaries','','| Boundary | Points | Max gap, mm | Source normal angle max | Candidate normal angle max |','|---|---:|---:|---:|---:|']
 for n,p in report['shared_boundaries'].items():lines.append(f"| {n} | {p['source_shared_vertex_count']} | {p['candidate_max_gap_m']*1000:.6f} | {p['source_max_normal_angle_deg']:.6f} | {p['candidate_max_normal_angle_deg']:.6f} |")
 lines+=['','## Surface orientation','',report['normal_rotation_note'],'','| Part | Newly opposed normals | Degenerate triangles | XZ winding reversals | Normals rotated over 90 degrees |','|---|---:|---:|---:|---:|']
 for n in sorted(TARGETS):
  p=report['parts'][n];lines.append(f"| {n} | {p['new_nontrivial_opposed_corner_normals']} | {p['new_nontrivial_degenerate_triangles']} | {p['projected_xz_winding_reversed']} | {p['significant_triangles_rotated_over_90_degrees']} |")
 lines+=['','## Scope and limits','',report['limits']]
 if report['issues']:lines+=['','## Issues','']+['- '+x for x in report['issues']]
 (H/'audit_local.md').write_text('\n'.join(lines)+'\n')
 print('LOCAL AXILLA AUDIT',json.dumps({'pass':report['pass'],'hash':report['glb_sha256'],'issues':report['issues'],'boundaries':report['shared_boundaries']}),flush=True)
 return report
if __name__=='__main__':run()
