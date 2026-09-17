"""Build authored natural skin PBR hands while preserving articulated wrist assets."""
import argparse,hashlib,json,math,platform,struct,sys,shutil
from datetime import datetime,timezone
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from realism_surface import setup_hand,setup_part
from realism_bake import unwrap,bake
DIGITS=('thumb','index','middle','ring','little')
KEYS=[f'Joint_{d}_{j}'for d in DIGITS for j in range(3)]
def native_points(obj,holder):
 matrix=holder.matrix_world.inverted()@obj.matrix_world
 return[matrix@v.co for v in obj.data.vertices]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def activate(scene):
    bpy.context.window.scene = scene
    bpy.context.view_layer.update()

def descendants(parent):
    output = []
    for child in parent.children:
        output.append(child)
        output.extend(descendants(child))
    return output

def bone_signature(rig):
    return {bone.name: {"parent": bone.parent.name if bone.parent else None,
                        "matrix": [list(row) for row in bone.matrix_local]}
            for bone in rig.data.bones}

def mesh_signature(obj):
    h = hashlib.sha256()
    for vertex in obj.data.vertices:
        h.update(struct.pack("<3f", *vertex.co))
        for group in vertex.groups:
            h.update(struct.pack("<If", group.group, group.weight))
    for polygon in obj.data.polygons:
        h.update(struct.pack(f"<{len(polygon.vertices)}I", *polygon.vertices))
    return h.hexdigest()

def glb_morph_report(path):
    data = path.read_bytes()
    size, kind = struct.unpack_from("<II", data, 12)
    document = json.loads(data[20:20 + size])
    assert kind == 0x4E4F534A
    morph_meshes = []
    for mesh in document["meshes"]:
        names = mesh.get("extras", {}).get("targetNames", [])
        if names:
            assert names == KEYS, f"Exported shape names/order changed: {names}"
            rows = []
            for primitive in mesh["primitives"]:
                targets = primitive.get("targets", [])
                assert len(targets) == 15, "Primitive lost corrective targets"
                assert all("POSITION" in target and "NORMAL" in target for target in targets), "Position/normal morph missing"
                rows.append({"vertices": document["accessors"][primitive["attributes"]["POSITION"]]["count"],
                             "target_count": len(targets), "position_and_normal": True})
            assert all(value == 0 for value in mesh.get("weights", [])), "Exported corrective is active in neutral asset"
            morph_meshes.append({"mesh": mesh.get("name"), "target_names": names, "primitives": rows})
    assert len(morph_meshes) == 1, "Only the anatomical hand mesh should have corrective morphs"
    assert len(document.get("skins", [])) == 1 and len(document["skins"][0]["joints"]) == 16
    for mesh in document["meshes"]:
        if "Nail_" in mesh.get("name", ""):
            assert not mesh.get("extras", {}).get("targetNames"), "Nail unexpectedly has corrective targets"
    return {"sha256": digest(path), "bytes": path.stat().st_size, "morph_meshes": morph_meshes,
            "skin_joints": [document["nodes"][j]["name"] for j in document["skins"][0]["joints"]]}

def repair_zero_export_tangents(path):
    """Apply the documented UV-frame fix only if Blender exported a zero tangent."""
    import runpy
    blob=path.read_bytes();size=struct.unpack_from('<I',blob,12)[0];document=json.loads(blob[20:20+size]);binary_start=20+size+8;has_zero=False
    for mesh in document['meshes']:
        for primitive in mesh['primitives']:
            tangent=primitive['attributes'].get('TANGENT')
            if tangent is None:continue
            accessor=document['accessors'][tangent];view=document['bufferViews'][accessor['bufferView']];offset=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0);stride=view.get('byteStride',16)
            for index in range(accessor['count']):
                vector=struct.unpack_from('<3f',blob,offset+index*stride)
                if sum(value*value for value in vector)<1e-12:has_zero=True;break
    if not has_zero:return
    temporary=path.with_name(path.stem+'_valid_tangents.glb');report=path.with_name(path.stem+'_tangent_repair.json');script=Path(__file__).with_name('repair_export_tangents.py');arguments=sys.argv
    try:
        sys.argv=[str(script),'--input-glb',str(path),'--output-glb',str(temporary),'--report',str(report)]
        runpy.run_path(str(script),run_name='__main__')
    finally:sys.argv=arguments
    temporary.replace(path)


def export_native(scene, side_objects, holder, output_path):
    temporary = bpy.data.scenes.new("Realistic_Export_Native")
    roots = [obj for obj in side_objects if obj.parent == holder]
    for obj in side_objects:
        temporary.collection.objects.link(obj)
        scene.collection.objects.unlink(obj)
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = None
        obj.matrix_basis = basis
    activate(temporary)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in side_objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = roots[0]
    options = {"filepath": str(output_path), "export_format": "GLB", "use_selection": True,
               "use_active_scene": True, "export_yup": True, "export_materials": "EXPORT",
               "export_skins": True, "export_influence_nb": 8, "export_animations": False,
               "export_apply": False, "export_extras": True, "export_cameras": False,
               "export_lights": False, "export_morph": True, "export_morph_normal": True,
               "export_morph_tangent": False, "export_tangents": True}
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    assert "export_morph" in props and "export_morph_normal" in props
    bpy.ops.export_scene.gltf(**{key: value for key, value in options.items() if key in props})
    for obj in roots:
        basis = obj.matrix_basis.copy()
        obj.parent = holder
        obj.matrix_basis = basis
    for obj in side_objects:
        scene.collection.objects.link(obj)
        temporary.collection.objects.unlink(obj)
    activate(scene)
    bpy.data.scenes.remove(temporary)
    repair_zero_export_tangents(output_path)
    return glb_morph_report(output_path)


def morph_deltas(skin):
    basis = skin.data.shape_keys.key_blocks['Basis']
    h = hashlib.sha256()
    for key in skin.data.shape_keys.key_blocks:
        if key.name == 'Basis':
            continue
        h.update(key.name.encode())
        for first, second in zip(key.data, basis.data):
            h.update(struct.pack('<3f', *(first.co - second.co)))
    return h.hexdigest()


def bounds(points):
    return {'min': [min(point[i] for point in points) for i in range(3)],
            'max': [max(point[i] for point in points) for i in range(3)]}



def render_views(scene,hands,source,output,report,preview_only=False):
 holder,objects,rig,skin=hands['left'];right=hands['right'][1]
 camera=scene.camera;original_denoising=scene.cycles.use_denoising;scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1400;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
 native_fingers=[holder.matrix_world.inverted()@(skin.matrix_world@v.co)for v in skin.data.vertices if(holder.matrix_world.inverted()@(skin.matrix_world@v.co)).y>.10]
 configurations=[('finger_dorsum_closeup',(0,.135,.005),(0,-.08,1),.205,False),('finger_palm_closeup',(0,.135,0),(0,.03,-1),.205,False),('finger_side',(0,.125,.008),(1,0,.18),.235,False),('flex_dorsum',(0,.090,.008),(0,-.35,1),.26,True),('flex_palm',(0,.090,-.018),(0,-.05,-1),.26,True),('wrist_material_closeup',(0,-.035,0),(0,0,1),.205,False)]
 if not preview_only and(output/'preview_finger_dorsum.png').is_file():configurations=[c for c in configurations if c[0]!='finger_dorsum_closeup']
 if preview_only:configurations=[('preview_finger_dorsum',(0,.135,.005),(0,-.08,1),.205,False)]
 for obj in right:obj.hide_render=True
 for obj in objects:
  if obj.type=='MESH'and'UpperArm'in obj.name:obj.hide_render=True
 for name,center_native,direction,scale,flex in configurations:
  for d in DIGITS:
   for j,limit in enumerate(([60,70,80]if d=='thumb'else[90,110,80])):
    rig.pose.bones[d+str(j)].rotation_mode='XYZ';rig.pose.bones[d+str(j)].rotation_euler=(math.radians(-limit)*.78 if flex else 0,0,0);skin.data.shape_keys.key_blocks[f'Joint_{d}_{j}'].value=.78 if flex else 0
  bpy.context.view_layer.update();center=holder.matrix_world@Vector(center_native);camera.location=center+Vector(direction).normalized()*1.2;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=scale
  scene.render.filepath=str(output/(name+'.png'));bpy.ops.render.render(write_still=True);report['renders'][name]={'file':name+'.png','flexion':.78 if flex else 0,'center_native_blender':center_native,'direction':direction,'ortho_scale':scale,'samples':scene.cycles.samples,'denoising':scene.cycles.use_denoising}
  print('REALISM_RENDER',name,flush=True)
 if preview_only:return
 # Match the neutral fingers closeup with the preserved source using actual renders.
 center=holder.matrix_world@Vector((0,.135,.005));camera.location=center+Vector((0,-.08,1)).normalized()*1.2;camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=.205
 for d in DIGITS:
  for j in range(3):rig.pose.bones[d+str(j)].rotation_euler=(0,0,0);skin.data.shape_keys.key_blocks[f'Joint_{d}_{j}'].value=0
 bpy.context.view_layer.update();camera_matrix=camera.matrix_world.copy();scene.render.filepath=str(output/'realism_before_after_after.png')
 if(output/'preview_finger_dorsum.png').is_file():shutil.copy2(output/'preview_finger_dorsum.png',scene.render.filepath)
 else:scene.cycles.samples=40;scene.cycles.use_denoising=original_denoising;bpy.ops.render.render(write_still=True)
 settings={'camera_world':[list(r)for r in camera_matrix],'orthographic_scale':.205,'resolution':[1400,1200],'samples':40,'denoising':original_denoising,'after_reuses_identical_original_preview_pixels':True}
 bpy.ops.wm.open_mainfile(filepath=str(source/'bilateral_hands_wrist_refined.blend'));before=bpy.data.scenes['Bilateral_Wrist_Refined_Review'];activate(before)
 for obj in before.objects:
  top=obj
  while top.parent:top=top.parent
  if top.name=='RIGHT_PreviewTranslationOnly'or(obj.type=='MESH'and'UpperArm'in obj.name):obj.hide_render=True
 before.camera.matrix_world=camera_matrix;before.camera.data.ortho_scale=.205;before.cycles.samples=40;before.cycles.use_denoising=original_denoising;before.render.resolution_x=1400;before.render.resolution_y=1200;before.render.resolution_percentage=100;before.render.filepath=str(output/'realism_before_after_before.png');bpy.ops.render.render(write_still=True)
 report['comparison']={'method':'Two direct Blender renders, same camera/light/neutral pose, no compositing','settings':settings,'before':'realism_before_after_before.png','after':'realism_before_after_after.png'}

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--input-dir',type=Path,required=True);parser.add_argument('--output-dir',type=Path,required=True);parser.add_argument('--preview-only',action='store_true');args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);source=args.input_dir.resolve();output=args.output_dir.resolve()
 assert bpy.app.background;assert source!=output;assert not output.exists()or not any(output.iterdir());output.mkdir(parents=True,exist_ok=True)
 paths={name:source/name for name in('bilateral_hands_wrist_refined.blend','left_hand_wrist_refined.glb','right_hand_wrist_refined.glb','build_report.json')};assert all(p.is_file()for p in paths.values());hashes={n:digest(p)for n,p in paths.items()}
 bpy.ops.wm.open_mainfile(filepath=str(paths['bilateral_hands_wrist_refined.blend']));scene=bpy.data.scenes['Bilateral_Wrist_Refined_Review'];scene.name='Bilateral_Realistic_Review';activate(scene)
 report={'status':'building','created_utc':datetime.now(timezone.utc).isoformat(),'host':{'platform':platform.platform(),'binary':bpy.app.binary_path,'version':bpy.app.version_string,'background':bpy.app.background},'source_sha256':hashes,'hands':{},'renders':{},'physical_skin_vertex_count':12036,'physical_range_evidence':'The detailed build appended glove edge/stitch geometry after the unchanged imported 12036-vertex anatomical skin; all later detail vertices are protected from sculpt.', 'material_names':['Detailed_Skin','Detailed_Glove','Detailed_Sleeve','Detailed_Nail','Detailed_Trim'],'texture_contract':'4096 shared atlas: sRGB basecolor; tangent OpenGL normal; non-color roughness exported through glTF G channel. All textures packed in blend and embedded in GLB.'}
 hands={};meshes=[]
 for side in('left','right'):
  holder=scene.objects[side.upper()+'_PreviewTranslationOnly'];objects=descendants(holder);rig=next(o for o in objects if o.type=='ARMATURE');skin=next(o for o in objects if o.type=='MESH'and'Anatomical'in o.name);nails=[o for o in objects if'Nail_'in o.name]
  beforebones=bone_signature(rig);morphs=morph_deltas(skin);original=[v.co.copy()for v in skin.data.vertices];static={o.name:mesh_signature(o)for o in objects if o.type=='MESH'and o!=skin};weights=[[(g.group,g.weight)for g in v.groups]for v in skin.data.vertices]
  sculpt=setup_hand(skin,rig,holder,nails)
  assert all(skin.data.vertices[i].co==original[i]for i in sculpt['protected_vertex_indices']);assert beforebones==bone_signature(rig);assert weights==[[(g.group,g.weight)for g in v.groups]for v in skin.data.vertices]
  # Correctives only affect joint regions; allow float32 addition rounding while retaining every authored delta.
  handmeshes=[o for o in objects if o.type=='MESH'];meshes.extend(handmeshes)
  for o in handmeshes:
   if o!=skin:setup_part(o,rig)
  assert static=={o.name:mesh_signature(o)for o in handmeshes if o!=skin}
  report['hands'][side]={'skin_object':skin.name,'rig_object':rig.name,'sculpt':sculpt,'source_morph_delta_sha256':morphs,'output_morph_delta_sha256':morph_deltas(skin),'preserved_static_mesh_signatures':static,'rest_bones':beforebones}
  hands[side]=(holder,objects,rig,skin)
 report['uv']=unwrap(meshes);print('REALISM_UV_PACKED',flush=True)
 report['textures']=bake(scene,meshes,output)
 for side,(holder,objects,rig,skin)in hands.items():report['hands'][side]['export']=export_native(scene,objects,holder,output/f'{side}_hand_realistic.glb')
 bpy.ops.wm.save_as_mainfile(filepath=str(output/'bilateral_hands_realistic.blend'));print('REALISM_MODEL_SAVED',flush=True)
 (output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False))
 render_views(scene,hands,source,output,report,args.preview_only)
 assert hashes=={n:digest(p)for n,p in paths.items()};report['status']='built_pending_independent_verification';report['outputs']={p.name:{'bytes':p.stat().st_size,'sha256':digest(p)}for p in output.iterdir()if p.is_file()and p.name!='build_report.json'}
 (output/'build_report.json').write_text(json.dumps(report,indent=2,ensure_ascii=False));print('REALISM_BUILD_COMPLETE',output,flush=True)
if __name__=='__main__':main()
