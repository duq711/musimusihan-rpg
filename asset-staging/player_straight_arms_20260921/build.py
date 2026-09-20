"""Mac Blender: replace only full-body arms using current gameplay FP poses.
Run export_pose.gd first. Sources are preserved, and non-arm geometry is audited.
"""
import bpy,json,hashlib,shutil,bmesh,math
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[2]
WORK=Path(__file__).resolve().parent
BODY=ROOT/'godot-game/assets/3d/player/gravebound_player.glb'
SOURCE_WORK=ROOT/'asset-staging/player_fullbody_fp_arms_20260920'
BACKUP=SOURCE_WORK/'original_gravebound_player.glb'
assert BACKUP.exists(), "Restore the original full-body source from the previous production archive first."
POSE=json.loads((SOURCE_WORK/'pose.json').read_text())
G=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def signature(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(p.vertices) for p in o.data.polygons],'uv':[[list(x.uv) for x in l.data] for l in o.data.uv_layers],'transform':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(BACKUP))
parent=bpy.data.objects.get('GraveboundPlayer')
assert parent is not None
keep=[o for o in bpy.data.objects if o.parent==parent and o.type=='MESH' and not o.name.startswith(('Gravebound_SuppliedHand_','Gravebound_SuppliedNail_','Gravebound_Sleeve_','Gravebound_Bracer_'))]
assert len(keep)==24,len(keep)
removed=[o.name for o in parent.children if o not in keep]
for o in list(bpy.data.objects):
 if o not in keep and o!=parent:bpy.data.objects.remove(o,do_unlink=True)
before={o.name:signature(o) for o in keep}
scene=bpy.context.scene
# The original GLB includes multiple scenes; use one explicit final scene.
for o in [parent]+keep:
 if o.name not in scene.objects:scene.collection.objects.link(o)
added=[];sources={};rigs=[];pose_errors={};sleeve_fit={}
for side,file in [('L','left.glb'),('R','right.glb')]:
 source=ROOT/'godot-game/assets/3d/player/fp_arms'/file
 sources[file]=sha(source)
 old={o.name for o in bpy.data.objects}
 bpy.ops.import_scene.gltf(filepath=str(source))
 imported=[o for o in bpy.data.objects if o.name not in old]
 rig=next(o for o in imported if o.type=='ARMATURE')
 parts=[o for o in imported if o.type=='MESH' and o.name.startswith('FP_'+side+'_')]
 assert len(parts)==2,[(o.name,o.type) for o in imported]
 # Imported bone rest matrices are the same canonical deform bones used by
 # supplied_fp_arm.gd. Apply its actual relaxed fingers and limb fit matrices.
 for bone in rig.pose.bones:
  name=bone.name
  assert name in POSE[side]['bones'],name
  bone.matrix=G@Matrix(POSE[side]['bones'][name])@Matrix(POSE[side]['rest'][name]).inverted()@G.inverted()@bone.bone.matrix_local
  bpy.context.view_layer.update()
 root=G@Matrix(POSE[side]['root'])@G.inverted()
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 for obj in parts:
  mesh=bpy.data.meshes.new_from_object(obj.evaluated_get(dg),preserve_all_data_layers=True,depsgraph=dg)
  mesh.transform(root@obj.matrix_world)
  section='Arm' if '_Arm' in obj.name else 'Hand'
  expected=POSE[side]['surface_points'][section]
  kd=KDTree(len(expected))
  for i,p in enumerate(expected):kd.insert(Vector((p[0],-p[2],p[1])),i)
  kd.balance()
  error=max(kd.find(v.co)[2] for v in mesh.vertices)
  pose_errors[side+'_'+section]=error
  assert error<.003,('Baked mesh differs from real Godot deformation',side,section,error)
  if section=='Arm':
   # The first-person asset stops below the shoulder. Fit its existing sleeve
   # opening under the unchanged mantle; preserve the glove/wrist seam exactly.
   sign=-1 if side=='L' else 1
   changed=0;max_move=0.0
   for vertex in mesh.vertices:
    old=vertex.co.copy();height=old.z
    upper=max(0.0,min(1.0,(height-1.17)/(.148073)))
    smooth=upper*upper*(3-2*upper)
    width=max(0.0,min(1.0,(height-.995)/.115))
    center_x=sign*(.31-(height-.94)*.12)
    center_y=.075-(height-.94)*.26
    radial=1.0-.19*width-.16*smooth
    vertex.co.x=center_x+(old.x-center_x)*radial-sign*.105*smooth
    vertex.co.y=center_y+(old.y-center_y)*radial
    vertex.co.z=height+.125*smooth
    moved=(vertex.co-old).length
    if moved>1e-7:changed+=1
    max_move=max(max_move,moved)
   # Recompute the deformed sleeve normals, retaining the original UVs.
   mesh.update()
   if mesh.has_custom_normals:
    mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])
   sleeve_fit[side]={'changed_vertices':changed,'maximum_displacement_m':max_move,'upper_extension_m':.125,'wrist_below_y_preserved':.995}

  # Full-body-only proportions: keep the wrist anchor and taper the sleeve
  # continuously into the smaller glove. The gameplay FP sources stay intact.
  wrist=Vector(((-1 if side=='L' else 1)*.31,.075,.94))
  for vertex in mesh.vertices:
   t=max(0.0,min(1.0,(vertex.co.z-.975)/.14))
   weight=1.0 if section=='Hand' else 1.0-t*t*(3.0-2.0*t)
   vertex.co=wrist+(vertex.co-wrist)*(1.0-.18*weight)
  mesh.update()
  if mesh.has_custom_normals:
   mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])

  # Refit the entire sleeve, not just the glove: lower the elbow/wrist,
  # remove first-person forearm inflation, and bring the relaxed arm inward.
  def interp(h, knots):
   if h<=knots[0][0]:return knots[0][1]
   for (a,x),(b,y) in zip(knots,knots[1:]):
    if h<=b:return x+(y-x)*(h-a)/(b-a)
   return knots[-1][1]
  sign=-1 if side=='L' else 1
  for vertex in mesh.vertices:
   h=vertex.co.z
   if section=='Hand' or h<=.975:
    vertex.co.x-=sign*.02
    vertex.co.z-=.07
   else:
    old_x=interp(h,[(.94,.31),(1.05,.299),(1.15,.294),(1.20,.277),(1.30,.225),(1.443,.17)])
    old_y=interp(h,[(.94,.075),(1.05,.048),(1.15,.035),(1.20,.021),(1.30,.004),(1.443,0)])
    new_h=interp(h,[(.975,.905),(1.17,1.135),(1.4430726,1.4430726)])
    new_x=interp(h,[(.975,.2865),(1.17,.275),(1.4430726,.20)])
    radial=interp(h,[(.975,1.0),(1.02,.75),(1.07,.65),(1.17,.65),(1.30,.80),(1.4430726,.9)])
    vertex.co.x=sign*new_x+(vertex.co.x-sign*old_x)*radial
    vertex.co.y=old_y+(vertex.co.y-old_y)*radial
    vertex.co.z=new_h
  mesh.update()
  if mesh.has_custom_normals:
   mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])

  # Reconstruct the full sleeve silhouette around anatomical landmarks.
  # Slice the existing surface, then remap its cross-sections onto a continuous
  # shoulder / upper arm / elbow / proximal forearm / distal forearm profile.
  # Topology, UVs and production fabric materials are retained.
  if section=='Arm':
   mesh.update()
   coords=[v.co.copy() for v in mesh.vertices]
   edges=[tuple(e.vertices) for e in mesh.edges]
   samples=[]
   for i in range(121):
    z=.925+(1.443-.925)*i/120
    points=[]
    for a,b in edges:
     va,vb=coords[a],coords[b]
     if (va.z-z)*(vb.z-z)<=0 and abs(vb.z-va.z)>1e-8:
      points.append(va+(vb-va)*((z-va.z)/(vb.z-va.z)))
    if len(points)<4:continue
    xmin,xmax=min(p.x for p in points),max(p.x for p in points)
    ymin,ymax=min(p.y for p in points),max(p.y for p in points)
    samples.append((z,((xmin+xmax)/2,(ymin+ymax)/2,max(.005,(xmax-xmin)/2),max(.005,(ymax-ymin)/2))))
   # height, lateral center, depth center, lateral radius, depth radius
   profile=[
    (.925,.292,.068,.057,.050),
    (.935,.290,.064,.057,.050),
    (1.380,.215,.000,.060,.052),
    (1.405,.190,.000,.055,.044),
    (1.4431,.120,.010,.022,.022)]
   def target(z,k):
    for a,b in zip(profile,profile[1:]):
     if z<=b[0]:
      t=max(0.,min(1.,(z-a[0])/(b[0]-a[0])))
      return a[k]+(b[k]-a[k])*t
    return profile[-1][k]
   for vertex in mesh.vertices:
    p=vertex.co.copy();z=p.z
    if z<=.925:continue
    cx=interp(z,[(h,q[0]) for h,q in samples]);cy=interp(z,[(h,q[1]) for h,q in samples])
    rx=interp(z,[(h,q[2]) for h,q in samples]);ry=interp(z,[(h,q[3]) for h,q in samples])
    tx=sign*target(z,1);ty=target(z,2)
    fitted=Vector((tx+(p.x-cx)/rx*target(z,3),ty+(p.y-cy)/ry*target(z,4),z))
    t=max(0.,min(1.,(z-.925)/.055));t=t*t*(3-2*t)
    vertex.co=p.lerp(fitted,t)
   mesh.update()
   if mesh.has_custom_normals:
    mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])
   sleeve_fit[side]['straight_sections']=profile
   sleeve_fit[side]['source_section_count']=len(samples)
   # Remove the discontinuous upper/forearm surface and loft a single sleeve.
   # Keep the authored lower cuff, bridging from its actual cut boundary.
   mesh.calc_loop_triangles()
   source_coords=[v.co.copy() for v in mesh.vertices]
   tris=[tuple(t.vertices) for t in mesh.loop_triangles]
   tri_uvs=[[mesh.uv_layers.active.data[i].uv.copy() for i in t.loops] for t in mesh.loop_triangles]
   bvh=BVHTree.FromPolygons(source_coords,tris,all_triangles=True)
   bm=bmesh.new();bm.from_mesh(mesh)
   bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,.935),plane_no=(0,0,1),clear_outer=True,clear_inner=False)
   boundary=[v for v in bm.verts if abs(v.co.z-.935)<1e-5]
   bmesh.ops.remove_doubles(bm,verts=boundary,dist=1e-5)
   boundary=[v for v in bm.verts if abs(v.co.z-.935)<1e-5 and any(e.is_boundary for e in v.link_edges)]
   assert len(boundary)>=8,('Cuff cut ring missing',len(boundary))
   cx=sum(v.co.x for v in boundary)/len(boundary);cy=sum(v.co.y for v in boundary)/len(boundary)
   ring=sorted(boundary,key=lambda v:math.atan2(v.co.y-cy,v.co.x-cx))
   angles=[math.atan2(v.co.y-cy,v.co.x-cx) for v in ring]
   base=[v.co.copy() for v in ring]
   uv_layer=bm.loops.layers.uv.active
   def transferred_uv(point):
    hit,normal,idx,distance=bvh.find_nearest(point)
    a,b,c=[source_coords[i] for i in tris[idx]]
    uv=tri_uvs[idx]
    return barycentric_transform(hit,a,b,c,Vector((uv[0].x,uv[0].y,0)),Vector((uv[1].x,uv[1].y,0)),Vector((uv[2].x,uv[2].y,0))).xy
   for ri in range(1,81):
    z=.935+(1.443-.935)*ri/80
    next_ring=[]
    blend=max(0.,min(1.,(z-.935)/.02));blend=blend*blend*(3-2*blend)
    for i,angle in enumerate(angles):
     # Restrained folds; no separate elbow tube or bulbous lower-arm cuff.
     fold=0.0
     co=Vector((sign*target(z,1)+(target(z,3)+fold)*math.cos(angle),target(z,2)+(target(z,4)+fold)*math.sin(angle),z))
     anchored=Vector((base[i].x,base[i].y,z))
     next_ring.append(bm.verts.new(anchored.lerp(co,blend)))
    for i in range(len(ring)):
     j=(i+1)%len(ring)
     face=bm.faces.new((ring[i],ring[j],next_ring[j],next_ring[i]));face.smooth=True
     for loop in face.loops:loop[uv_layer].uv=transferred_uv(loop.vert.co)
    ring=next_ring
   cap=bm.faces.new(ring);cap.smooth=True
   for loop in cap.loops:loop[uv_layer].uv=transferred_uv(loop.vert.co)
   bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
   bmesh.ops.triangulate(bm,faces=list(bm.faces))
   bm.to_mesh(mesh);bm.free();mesh.update()
   if mesh.has_custom_normals:mesh.normals_split_custom_set_from_vertices([v.normal for v in mesh.vertices])
   sleeve_fit[side]['continuous_loft_rings']=81
   sleeve_fit[side]['preserved_cuff_cut_height']=.935


  new=bpy.data.objects.new('Gravebound_FP_'+side+('_Arm' if '_Arm' in obj.name else '_Hand'),mesh)
  scene.collection.objects.link(new)
  new['source_model']='fp_arms/'+file
  new['source_sha256']=sources[file]
  new['pose_source']='supplied_fp_arm.gd relaxed pose and fit_arm'
  added.append(new)
 for obj in imported:bpy.data.objects.remove(obj,do_unlink=True)
assert all(signature(o)==before[o.name] for o in keep)
# Parent new static meshes without changing their already posed world coordinates.
for obj in added:
 world=obj.matrix_world.copy();obj.parent=parent;obj.matrix_world=world
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in [parent]+keep+added:obj.select_set(True)
bpy.context.view_layer.objects.active=parent
for scene_other in list(bpy.data.scenes):
 if scene_other!=scene:bpy.data.scenes.remove(scene_other)
scene.name='Gravebound_FP_Arms'
bpy.data.orphans_purge(do_recursive=True)
for image in bpy.data.images:
 if image.source=='FILE' and image.has_data:image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'Gravebound_FP_Arms.blend'),compress=True)
out=WORK/'gravebound_player_fp_arms.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report={'original_sha256':sha(BACKUP),'production_script_sha256':sha(ROOT/'godot-game/scripts/supplied_fp_arm.gd'),'pose_json_sha256':sha(SOURCE_WORK/'pose.json'),'removed_objects':removed,'retained_non_arm_count':len(keep),'retained_signatures':before,'added_objects':[o.name for o in added],'fp_sources':sources,'max_posed_vertex_error_before_sleeve_fit_m':pose_errors,'sleeve_fit':sleeve_fit,'fullbody_hand_scale':.82,'anatomy_fit':{'wrist_height_m':.87,'elbow_height_m':1.135,'shoulder_height_m':1.443,'wrist_inset_m':.02,'mid_forearm_radial_scale':.65},'wrist_taper_y_m':[.975,1.115],'output_sha256':sha(out),'output_bytes':out.stat().st_size}
(WORK/'build_report.json').write_text(json.dumps(report,indent=2))
print('FULLBODY FP BUILD PASS',report['added_objects'])
