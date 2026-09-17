import bpy, bmesh, json, math, hashlib
from pathlib import Path
from mathutils import Vector, Matrix
BASE=Path(__file__).resolve().parents[1]
OUT=BASE.parents[1]/'godot-game/assets/models/loot_containers'
OUT.mkdir(parents=True,exist_ok=True)
CONFIGS=[('wooden_barrels_01','wooden_barrel_01',1.0,'lift'),('treasure_chest','treasure_chest',1.2,'hinge'),('wooden_crate_01','wooden_crate_01',1.10,'hinge'),('wooden_crate_02','wooden_crate_02',1.28,'lift')]
def bounds(objs):
 vs=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 return Vector([min(v[k] for v in vs) for k in range(3)]),Vector([max(v[k] for v in vs) for k in range(3)])
def g(v): return [round(v.x,6),round(v.z,6),round(-v.y,6)]
def empty(name,location=(0,0,0),parent=None):
 o=bpy.data.objects.new(name,None);bpy.context.collection.objects.link(o);o.location=location;o.parent=parent;return o
def bake_mesh(o):
 deps=bpy.context.evaluated_depsgraph_get(); mesh=bpy.data.meshes.new_from_object(o.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
 old=o.data;o.modifiers.clear();o.data=mesh;mesh.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 if old.users==0: bpy.data.meshes.remove(old)
def select_only(o):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
report=[]
for source,name,target,mode in CONFIGS:
 bpy.ops.wm.open_mainfile(filepath=str(BASE/'sources'/source/(source+'_4k.blend')),load_ui=False,use_scripts=False)
 for o in list(bpy.data.objects):
  if o.type!='MESH' or (source=='wooden_barrels_01' and o.name!='wooden_barrels_01_barrel01'): bpy.data.objects.remove(o,do_unlink=True)
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH']; source_tris=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objs)
 for o in objs:bake_mesh(o)
 if source=='wooden_barrels_01':
  o=objs[0];adj=[set() for _ in o.data.vertices]
  for e in o.data.edges:adj[e.vertices[0]].add(e.vertices[1]);adj[e.vertices[1]].add(e.vertices[0])
  remaining=set(range(len(adj)));lid_indices=set()
  while remaining:
   component={remaining.pop()};queue=list(component)
   while queue:
    ns=adj[queue.pop()]&remaining;remaining-=ns;component|=ns;queue+=list(ns)
   if min(o.data.vertices[i].co.z for i in component)>.835:lid_indices|=component
  assert 100<len(lid_indices)<len(adj)*.2,(len(lid_indices),len(adj))
  select_only(o)
  for v in o.data.vertices:v.select=v.index in lid_indices
  for e in o.data.edges:e.select=all(i in lid_indices for i in e.vertices)
  for p in o.data.polygons:p.select=all(i in lid_indices for i in p.vertices)
  bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.separate(type='SELECTED');bpy.ops.object.mode_set(mode='OBJECT')
  for obj in bpy.context.selected_objects:
   if obj!=o:obj.name='wooden_barrel_01_lid'
  objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
 # Place all vertices in common world coordinates; face latches toward Blender +Y / Godot -Z.
 rot=Matrix.Rotation(math.pi,4,'Z')
 for o in objs:o.data.transform(rot)
 lo,hi=bounds(objs);mid=(lo+hi)/2;mid.z=lo.z
 scale=target/(hi.z-lo.z if source=='wooden_barrels_01' else hi.x-lo.x)
 norm=Matrix.Diagonal((scale,scale,scale,1))@Matrix.Translation(-mid)
 for o in objs:o.data.transform(norm)
 # Build a straightforward glTF PBR material, retaining source UV coordinates.
 used_mats={s.material for o in objs for s in o.material_slots if s.material}
 texdir=BASE/'runtime_textures'/name;texdir.mkdir(parents=True,exist_ok=True)
 textures=[]
 for mat in used_mats:
  nodes=mat.node_tree.nodes;old_images=[n.image for n in nodes if n.type=='TEX_IMAGE' and n.image]
  mapping={}
  for old in old_images:
   channel='base_color' if '_diff' in old.name else 'normal' if '_nor_' in old.name else 'roughness' if '_rough' in old.name else 'metallic'
   if not old.has_data:old.reload()
   assert old.size[0]>0,(name,old.name)
   image=old.copy();image.name=name+'_'+channel+'_2k';image.scale(2048,2048)
   image.filepath_raw=str(texdir/(channel+('.jpg' if channel=='base_color' else '.png')))
   image.file_format='JPEG' if channel=='base_color' else 'PNG';image.save()
   colorspace='sRGB' if channel=='base_color' else 'Non-Color'
   # Reload saved files to verify runtime source and avoid exporter retaining 4K source payloads.
   saved=bpy.data.images.load(image.filepath_raw,check_existing=False);saved.colorspace_settings.name=colorspace
   mapping[channel]=saved;textures.append({'channel':channel,'size':list(saved.size),'path':str(Path(saved.filepath).relative_to(BASE)),'bytes':Path(saved.filepath).stat().st_size})
  nodes.clear();out=nodes.new('ShaderNodeOutputMaterial');bsdf=nodes.new('ShaderNodeBsdfPrincipled');mat.node_tree.links.new(bsdf.outputs['BSDF'],out.inputs['Surface'])
  for channel,img in mapping.items():
   node=nodes.new('ShaderNodeTexImage');node.image=img
   if channel=='normal':
    normal=nodes.new('ShaderNodeNormalMap');mat.node_tree.links.new(node.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs['Normal'],bsdf.inputs['Normal'])
   else:mat.node_tree.links.new(node.outputs['Color'],bsdf.inputs[{'base_color':'Base Color','roughness':'Roughness','metallic':'Metallic'}[channel]])
  mat.diffuse_color=(.34,.22,.11,1);mat.surface_render_method='DITHERED'
 # Treasure source is over 100k triangles; lower density retains sculpt detail through normals.
 if name=='treasure_chest':
  current=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objs)
  ratio=min(1,32000/current)
  for o in objs:
   if len(o.data.polygons)>1500:
    select_only(o);dec=o.modifiers.new('RuntimeDecimate','DECIMATE');dec.ratio=ratio;dec.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=dec.name)
 lo,hi=bounds(objs)
 lid_objs=[o for o in objs if 'lid' in o.name or (name=='treasure_chest' and 'lock' in o.name) or (name=='wooden_crate_01' and 'latch' in o.name)]
 assert lid_objs
 lid_lo,lid_hi=bounds([o for o in lid_objs if 'lid' in o.name])
 if mode=='hinge':pivot=Vector((0,lid_lo.y,lid_lo.z))
 else:pivot=Vector((0,0,lid_lo.z))
 root=empty(name);root['asset_variant']=name;root['opening_mode']=mode;body=empty('Body',parent=root);lid=empty('LidPivot',pivot,root)
 for o in objs:
  if o in lid_objs:o.data.transform(Matrix.Translation(-pivot));o.parent=lid
  else:o.parent=body
  o.name='Lid' if 'lid' in o.name.lower() else ('LidLatch' if o in lid_objs else 'ContainerBody' if ('crate' in o.name or 'barrel' in o.name or 'bottom' in o.name) else o.name)
 contacts=[]
 for side,x in [('Left',-min((lid_hi.x-lid_lo.x)*.27,.30)),('Right',min((lid_hi.x-lid_lo.x)*.27,.30))]:
  pos=Vector((x,lid_hi.y-.025*scale,lid_lo.z+(lid_hi.z-lid_lo.z)*.15))
  if mode=='lift' and name=='wooden_barrel_01':pos=Vector((x,.20*scale,lid_hi.z-.045*scale))
  marker=empty('Lid'+side+'Contact',pos-pivot,lid);contacts.append({'name':marker.name,'closed_position':g(pos),'local_position':g(pos-pivot)})
 # Save the derivative separately; remove unused source images to keep authoring derivative small.
 used_images={n.image for m in used_mats for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
 for img in list(bpy.data.images):
  if img not in used_images and img.name not in ['Render Result','Viewer Node']:bpy.data.images.remove(img)
 bpy.context.scene.world=None
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1.0
 blend=BASE/'normalized'/f'{name}.blend';blend.parent.mkdir(parents=True,exist_ok=True)
 bpy.ops.wm.save_as_mainfile(filepath=str(blend))
 bpy.ops.object.select_all(action='SELECT')
 dest=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_animations=False,export_yup=True,export_apply=True,export_extras=True,export_image_format='AUTO',export_jpeg_quality=90,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_tangents=True)
 record={'variant':name,'source':source,'glb':'res://assets/models/loot_containers/'+dest.name,'glb_bytes':dest.stat().st_size,'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'dimensions_m':g(hi-lo),'bounds_min':g(lo),'bounds_max':g(hi),'source_triangles':source_tris,'runtime_triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in objs),'opening_mode':mode,'hinge_axis':'+X','hinge_open_angle_degrees':95 if mode=='hinge' else 0,'lift_distance_m':.32 if mode=='lift' else 0,'lid_pivot':g(pivot),'lid_node':'LidPivot','front_axis':'-Z','contacts':contacts,'textures':textures,'mesh_objects':len(objs),'animation_clips':[],'opening_notes':'Runtime drives separate LidPivot; no whole-container rotation.'}
 # Dimensions are lengths, so Z must be positive (g() encodes positions).
 record['dimensions_m'][2]=abs(record['dimensions_m'][2]);record['bounds_min']=[round(lo.x,6),round(lo.z,6),round(-hi.y,6)];record['bounds_max']=[round(hi.x,6),round(hi.z,6),round(-lo.y,6)]
 report.append(record);(BASE/'runtime_manifest.json').write_text(json.dumps({'assets':report},indent=2));(OUT/'manifest.json').write_text(json.dumps({'assets':report},indent=2))
 print('ASSET_DONE',json.dumps(record),flush=True)
