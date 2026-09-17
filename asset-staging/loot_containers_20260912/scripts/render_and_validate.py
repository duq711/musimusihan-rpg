import bpy,json,math,struct,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
BASE=Path(__file__).resolve().parents[1];OUT=BASE.parents[1]/'godot-game/assets/models/loot_containers';QA=BASE/'qa';QA.mkdir(exist_ok=True);manifest=json.loads((BASE/'runtime_manifest.json').read_text());checks=json.loads((BASE/'validation_report.json').read_text())['automated_checks'] if (BASE/'validation_report.json').exists() else []
def bounds(objs):
 vs=[o.matrix_world@v.co for o in objs for v in o.data.vertices]
 return Vector([min(v[k] for v in vs) for k in range(3)]),Vector([max(v[k] for v in vs) for k in range(3)])
def aim(o,at):o.rotation_euler=(Vector(at)-o.location).to_track_quat('-Z','Y').to_euler()
def studio():
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.cycles.use_denoising=True
 scene.render.resolution_x=700;scene.render.resolution_y=640;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGB';scene.render.image_settings.color_depth='8'
 scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=0;scene.view_settings.gamma=1
 world=bpy.data.worlds.new('QA Studio');world.use_nodes=True;world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.34,.38,.44,1);world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.4;scene.world=world
 floor=bpy.data.materials.new('QA Neutral Floor');floor.diffuse_color=(.075,.086,.098,1);floor.use_nodes=True;floor.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.075,.086,.098,1);floor.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.85
 bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.003));bpy.context.object.name='QA Ground';bpy.context.object.data.materials.append(floor)
 bpy.ops.object.camera_add(location=(1.7,2.5,1.85));camera=bpy.context.object;camera.data.type='ORTHO';camera.data.ortho_scale=1.9;aim(camera,(0,0,.49));scene.camera=camera
 for name,location,power,size,color in [('Key',(1.4,2.6,4.1),550,3,(1,.85,.70)),('Fill',(-2,1,2.6),260,2.5,(.76,.86,1)),('Rim',(1,-2.3,3),500,2,(1,.92,.78))]:
  bpy.ops.object.light_add(type='AREA',location=location);o=bpy.context.object;o.name=name;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.data.color=color;aim(o,(0,0,.4))
 return scene
def raw_gltf(path):
 blob=path.read_bytes();length,typ=struct.unpack_from('<II',blob,12);return json.loads(blob[20:20+length])
for rec in manifest['assets']:
 name=rec['variant'];
 if any(c['asset']==name and (QA/(name+'_source_closed.png')).exists() for c in checks):continue
 path=OUT/(name+'.glb');data=raw_gltf(path);assert all('uri' not in i for i in data['images']);assert all('normalTexture' in m for m in data['materials']);assert all('TANGENT' in p['attributes'] for m in data['meshes'] for p in m['primitives'])
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path));bpy.context.view_layer.update()
 root=bpy.data.objects.get(name);lid=bpy.data.objects.get('LidPivot');assert root and lid and root.get('hinge_mode')==rec['opening_mode'];assert root.get('lid_open_degrees')==68
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH'];lo,hi=bounds(objs);assert abs(lo.z)<.0001 and abs((lo.x+hi.x)/2)<.0001 and abs((lo.y+hi.y)/2)<.0001
 assert bpy.data.objects['Lid'].parent==lid;assert bpy.data.objects['LidLeftContact'].parent==lid;assert bpy.data.objects['LidRightContact'].parent==lid
 assert all(i.size[0]<=2048 and i.size[1]<=2048 for i in bpy.data.images if i.type=='IMAGE')
 body=[o for o in objs if o.parent!=lid];body_before=[tuple(o.matrix_world@v.co) for o in body for v in o.data.vertices];lid_before=[tuple(bpy.data.objects['Lid'].matrix_world@v.co) for v in bpy.data.objects['Lid'].data.vertices]
 scene=studio();scene.render.filepath=str(QA/(name+'_runtime_closed.png'));bpy.ops.render.render(write_still=True)
 if rec['opening_mode']=='hinge':lid.rotation_mode='XYZ';lid.rotation_euler.x=math.radians(68)
 else:lid.location.z+=.32
 bpy.context.view_layer.update();assert body_before==[tuple(o.matrix_world@v.co) for o in body for v in o.data.vertices];assert lid_before!=[tuple(bpy.data.objects['Lid'].matrix_world@v.co) for v in bpy.data.objects['Lid'].data.vertices]
 scene.render.filepath=str(QA/(name+'_runtime_open.png'));bpy.ops.render.render(write_still=True)
 checks.append({'asset':name,'glb_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'reimport':'passed','embedded_images':len(data['images']),'pbr_normal_and_tangents':'passed','hierarchy_and_extras':'passed','ground_and_center':'passed','body_stable_lid_moves':'passed','texture_maximum':2048,'runtime_closed':str(QA/(name+'_runtime_closed.png')),'runtime_open':str(QA/(name+'_runtime_open.png'))})
 (BASE/'validation_report.json').write_text(json.dumps({'automated_checks':checks,'visual_review':'pending'},indent=2))
 # Render preserved source with the same orientation, scale and studio for direct comparison.
 source=rec['source'];bpy.ops.wm.open_mainfile(filepath=str(BASE/'sources'/source/(source+'_4k.blend')),load_ui=False,use_scripts=False)
 for o in list(bpy.data.objects):
  if o.type!='MESH' or (source=='wooden_barrels_01' and o.name!='wooden_barrels_01_barrel01'):bpy.data.objects.remove(o,do_unlink=True)
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
 for o in objs:
  o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);o.data.transform(Matrix.Rotation(math.pi,4,'Z'))
 lo,hi=bounds(objs);mid=(lo+hi)/2;mid.z=lo.z;target=1 if source=='wooden_barrels_01' else 1.2 if name=='treasure_chest' else 1.1 if name=='wooden_crate_01' else 1.28;scale=target/(hi.z-lo.z if source=='wooden_barrels_01' else hi.x-lo.x)
 for o in objs:o.data.transform(Matrix.Diagonal((scale,scale,scale,1))@Matrix.Translation(-mid))
 scene=studio();scene.render.filepath=str(QA/(name+'_source_closed.png'));bpy.ops.render.render(write_still=True)
 print('QA_DONE',name,flush=True)
print('ALL_QA_COMPLETE',flush=True)
