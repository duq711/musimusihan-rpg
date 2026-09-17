"""Prepare the actual supplied OBJ with direct decimation and a new shared UV atlas.

No previous game hand is read. Preserve separate full-density source surfaces in a
hidden collection for later normal baking. This file authors no rig or weights.
"""
import bpy,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
root=Path.cwd();stage=root/'asset-staging/player_supplied_hands_20260911';src=stage/'input/hand1.OBJ';landmarks=json.loads((stage/'geometry/canonical_landmarks.json').read_text());transform=json.loads((stage/'input/canonical_transform.json').read_text());out=stage/'geometry/supplied_left_prepared.blend';assert not out.exists();assert bpy.app.background
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest();before=sha(src);mapping=transform['component_digit_mapping'];raw_centers={d:Vector(v['center_source']) for d,v in transform['nails'].items()}
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.wm.obj_import(filepath=str(src),forward_axis='Y',up_axis='Z',global_scale=1.0,use_split_objects=False,use_split_groups=False)
original=next(o for o in bpy.context.scene.objects if o.type=='MESH');bpy.context.view_layer.objects.active=original;original.select_set(True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.mesh.separate(type='LOOSE');bpy.ops.object.mode_set(mode='OBJECT')
parts=[o for o in bpy.context.scene.objects if o.type=='MESH'];assert len(parts)==6
scene=bpy.context.scene;scene.name='Supplied_Hand_Prepared';scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
hi=bpy.data.collections.new('Source_High_Resolution');low=bpy.data.collections.new('Prepared_Gameplay_Hand');scene.collection.children.link(hi);scene.collection.children.link(low)
matrices=Matrix(landmarks['source_to_canonical_matrix']);high_objects={};used=set()
for ob in parts:
 if len(ob.data.vertices)>100000:partname='Supplied_AnatomicalHand';component=0
 else:
  center=sum((v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices);digit=min(raw_centers,key=lambda d:(center-raw_centers[d]).length);assert digit not in used;used.add(digit);partname='Nail_'+digit;component=mapping[digit]
 ob.name='HighRes_'+partname;ob.data.name=ob.name+'_Mesh';ob.data.transform(matrices);ob.data.update()
 for polygon in ob.data.polygons:polygon.use_smooth=True
 for collection in list(ob.users_collection):collection.objects.unlink(ob)
 hi.objects.link(ob);ob['source_obj_sha256']=before;ob['source_component_id']=component;ob['source_geometry_full_density']=True;ob.data.materials.clear();high_objects[partname]=ob
assert len(used)==5
skin=bpy.data.materials.new('Supplied_Skin');skin.use_nodes=True
nail=bpy.data.materials.new('Supplied_Nail');nail.use_nodes=True
for material,color,rough in [(skin,(.24,.24,.24,1),.68),(nail,(.28,.28,.28,1),.5)]:
 p=material.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=rough
report={'status':'preparing','source_obj_sha256':before,'source_to_canonical_matrix':landmarks['source_to_canonical_matrix'],'uniform_scale':landmarks['uniform_scale'],'source_geometry':'Direct imported supplied OBJ; no old game hand, shrinkwrap, projection deformation or retopology substitute.','parts':{}}
low_objects=[]
for name,high in high_objects.items():
 mesh=high.data.copy();mesh.name=name+'_Mesh';ob=bpy.data.objects.new(name,mesh);low.objects.link(ob);ob['source_component_id']=high['source_component_id'];ob['source_obj_sha256']=before;ob['direct_source_decimation']=True
 for o in bpy.context.selected_objects:o.select_set(False)
 ob.select_set(True);bpy.context.view_layer.objects.active=ob
 mesh.calc_loop_triangles();source_tri=len(mesh.loop_triangles);target=45000 if name=='Supplied_AnatomicalHand' else 600
 dec=ob.modifiers.new('Source_Surface_Decimation','DECIMATE');dec.decimate_type='COLLAPSE';dec.ratio=min(1.0,target/source_tri);dec.use_collapse_triangulate=True
 print('DIRECT_DECIMATE_START',name,source_tri,target,flush=True);bpy.ops.object.modifier_apply(modifier=dec.name)
 material=skin if name=='Supplied_AnatomicalHand' else nail;ob.data.materials.append(material);high.data.materials.append(material)
 for poly in ob.data.polygons:poly.use_smooth=True;poly.material_index=0
 ob.data.calc_loop_triangles();report['parts'][name]={'source_component_id':high['source_component_id'],'source_vertices':len(high.data.vertices),'source_triangles':source_tri,'prepared_vertices':len(ob.data.vertices),'prepared_polygons':len(ob.data.polygons),'prepared_triangles':len(ob.data.loop_triangles),'target_triangles':target,'method':'Blender Decimate COLLAPSE on actual source mesh; no object-space reshaping','highres_object':high.name,'material':material.name};low_objects.append(ob)
 print('DIRECT_DECIMATE_COMPLETE',name,report['parts'][name]['prepared_triangles'],flush=True)
for ob in high_objects.values():ob.hide_render=True;ob.hide_set(True)
hi.hide_render=True;hi.hide_viewport=True
for ob in bpy.context.selected_objects:ob.select_set(False)
for ob in low_objects:ob.select_set(True)
bpy.context.view_layer.objects.active=next(ob for ob in low_objects if ob.name=='Supplied_AnatomicalHand')
print('SHARED_UV_UNWRAP_START',flush=True)
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.008,area_weight=.5,correct_aspect=True,scale_to_bounds=True);bpy.ops.uv.select_all(action='SELECT');bpy.ops.uv.pack_islands(rotate=True,margin=.006,scale=True);bpy.ops.object.mode_set(mode='OBJECT')
for ob in low_objects:
 mesh=ob.data;mesh.uv_layers.active.name='SuppliedUV';values=[v.uv for v in mesh.uv_layers.active.data];assert len(values)==len(mesh.loops) and all(math.isfinite(x) for v in values for x in v)
 report['parts'][ob.name]['uv_layer']='SuppliedUV';report['parts'][ob.name]['uv_loop_count']=len(values);report['parts'][ob.name]['uv_bounds']=[[min(v[i] for v in values) for i in range(2)],[max(v[i] for v in values) for i in range(2)]]
scene['source_obj_sha256']=before;scene['source_geometry_preserved_in_collection']=hi.name;scene['prepared_geometry_collection']=low.name;scene['appearance_pending']='Matte grey preview; user surface appearance decision belongs to integration';scene['canonical_landmarks_json']=str(stage/'geometry/canonical_landmarks.json')
scene['no_rig_authored_in_preparation']=True;scene.render.engine='CYCLES';scene.render.threads_mode='FIXED';scene.render.threads=2
bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out),check_existing=False,compress=True)
assert sha(src)==before
originals=json.loads((stage/'input/source_manifest.json').read_text())
for item in originals.values():assert sha(item['source'])==item['sha256'] and sha(item['preserved_copy'])==item['sha256']
report.update(status='complete',blend=str(out),blend_sha256=sha(out),original_obj_and_ztl_unchanged=True,high_resolution_collection_hidden=True,rig_created=False,shared_uv_atlas=True,prepared_triangle_total=sum(v['prepared_triangles'] for v in report['parts'].values()))
(stage/'geometry/preparation_report.json').write_text(json.dumps(report,indent=2));print('SUPPLIED_HAND_PREPARATION_COMPLETE',json.dumps(report),flush=True)
