"""Repair the exposed head and eyes; preserve all 25 outfit/hand meshes."""
import bpy,json,hashlib,importlib.util,struct
from pathlib import Path
W=Path(__file__).resolve().parent
SOURCE=W.parent/'player_no_hood_20260921/Gravebound_No_Hood.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
def signature(o):
 return hashlib.sha256(json.dumps({'vertices':[list(v.co) for v in o.data.vertices],'faces':[list(f.vertices) for f in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'matrix':[list(r) for r in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
before={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in ['Gravebound_AnatomicalHead','Gravebound_Eyes']}
assert len(before)==25
reports={}
for task in ['face','hair','temples','eyes']:
 path=W/f'repair_{task}.py';spec=importlib.util.spec_from_file_location(f'repair_{task}',path);mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
 reports[task]=getattr(mod,f'repair_{task}')()
for name in ['Gravebound_AnatomicalHead','Gravebound_Eyes']:
 mesh=bpy.data.objects[name].data;used=sorted(set(p.material_index for p in mesh.polygons));indices=[used.index(p.material_index) for p in mesh.polygons];mats=[mesh.materials[i] for i in used];mesh.materials.clear()
 for mat in mats:mesh.materials.append(mat)
 for poly,index in zip(mesh.polygons,indices):poly.material_index=index
assert before=={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in ['Gravebound_AnatomicalHead','Gravebound_Eyes']}
assert 'Gravebound_PointHood' not in bpy.data.objects
assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])==27
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer'];bpy.data.orphans_purge(do_recursive=True)
bpy.context.preferences.filepaths.save_version=0
blend=W/'Gravebound_Repaired_Face.blend';bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
glb=W/'gravebound_player_repaired_face.glb';tmp=W/'face_export.tmp.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes();assert struct.unpack_from('<I',data,8)[0]==len(data);tmp.replace(glb)
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(data).hexdigest(),'mesh_count':27,'other_25_meshes_unchanged':True,'repairs':reports,'pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2));print('FACE BUILD PASS',report['output_sha256'])
