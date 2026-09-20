"""Remove the actual hood object, preserving the exposed head and outfit."""
import bpy,json,hashlib,importlib.util
from pathlib import Path
W=Path(__file__).resolve().parent
SOURCE=W.parent/'player_hood_shoulder_closure_20260921/Gravebound_Closed_Shoulder_Hood.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
hood=bpy.data.objects['Gravebound_PointHood']
def signature(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(f.vertices) for f in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'matrix':[list(row) for row in o.matrix_world]},sort_keys=True).encode()).hexdigest()
before={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o!=hood and o.name!='Gravebound_AnatomicalHead'}
head=bpy.data.objects['Gravebound_AnatomicalHead']
head_geometry=[tuple(v.co) for v in head.data.vertices],[tuple(f.vertices) for f in head.data.polygons]
bpy.data.objects.remove(hood,do_unlink=True)
spec=importlib.util.spec_from_file_location('restore_scalp',W/'restore_scalp.py')
helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
scalp=helper.restore_scalp(full_head=True)
assert head_geometry==([tuple(v.co) for v in head.data.vertices],[tuple(f.vertices) for f in head.data.polygons])
assert before=={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name!='Gravebound_AnatomicalHead'}
assert len(before)==26
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.data.orphans_purge(do_recursive=True)
blend=W/'Gravebound_No_Hood.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(blend),compress=True)
glb=W/'gravebound_player_no_hood.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(glb.read_bytes()).hexdigest(),'removed_object':'Gravebound_PointHood','remaining_meshes':27,'other_26_meshes_unchanged':True,'head_geometry_unchanged':True,'head_material_restoration':scalp}
(W/'build_report.json').write_text(json.dumps(report,indent=2));print('NO HOOD BUILD PASS',json.dumps(report))
