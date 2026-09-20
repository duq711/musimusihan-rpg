"""Mac Blender: replace only full-body arms using current gameplay FP poses.
Run export_pose.gd first. Sources are preserved, and non-arm geometry is audited.
"""
import bpy,json,hashlib,shutil
from pathlib import Path
from mathutils import Matrix,Vector
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[2]
WORK=Path(__file__).resolve().parent
BODY=ROOT/'godot-game/assets/3d/player/gravebound_player.glb'
BACKUP=WORK/'original_gravebound_player.glb'
if not BACKUP.exists():shutil.copy2(BODY,BACKUP)
POSE=json.loads((WORK/'pose.json').read_text())
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
report={'original_sha256':sha(BACKUP),'production_script_sha256':sha(ROOT/'godot-game/scripts/supplied_fp_arm.gd'),'pose_json_sha256':sha(WORK/'pose.json'),'removed_objects':removed,'retained_non_arm_count':len(keep),'retained_signatures':before,'added_objects':[o.name for o in added],'fp_sources':sources,'max_posed_vertex_error_before_sleeve_fit_m':pose_errors,'sleeve_fit':sleeve_fit,'output_sha256':sha(out),'output_bytes':out.stat().st_size}
(WORK/'build_report.json').write_text(json.dumps(report,indent=2))
print('FULLBODY FP BUILD PASS',report['added_objects'])
