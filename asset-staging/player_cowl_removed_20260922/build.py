"""Remove the draped hood and neck wrap from the supplied-head player."""
from pathlib import Path
import bpy, hashlib, json, struct, shutil
W=Path(__file__).resolve().parent
SOURCE=W.parent/'player_supplied_face_20260921/Gravebound_Supplied_Face.blend'
REMOVED=('Gravebound_InnerNeckCowl','Gravebound_Mantle_L','Gravebound_Mantle_R','Gravebound_MantleBack')
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
def signature(o):
    return hashlib.sha256(json.dumps({'vertices':[list(v.co) for v in o.data.vertices],
        'faces':[list(p.vertices) for p in o.data.polygons],
        'uv':[[list(v.uv) for v in l.data] for l in o.data.uv_layers],
        'world':[list(r) for r in o.matrix_world],
        'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
before={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in REMOVED}
for name in REMOVED:
    obj=bpy.data.objects.get(name)
    assert obj is not None, name
    bpy.data.objects.remove(obj,do_unlink=True)
after={o.name:signature(o) for o in bpy.context.scene.objects if o.type=='MESH'}
assert before==after and len(after)==23
assert not any(o.name in REMOVED or o.name=='Gravebound_PointHood' for o in bpy.context.scene.objects)
bpy.data.orphans_purge(do_recursive=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT')
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_No_Cowl.blend'),compress=True)
tmp=W/'no_cowl.tmp.glb'; out=W/'gravebound_player_no_cowl.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes()
assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data)
tmp.replace(out)
runtime=W.parents[1]/'godot-game/assets/3d/player/gravebound_player.glb'
shutil.copy2(out,runtime)
report={'source':str(SOURCE.relative_to(W.parents[1])),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    'removed_objects':list(REMOVED),'preserved_mesh_count':len(after),'preserved_mesh_signatures':after,
    'remaining_meshes_unchanged':before==after,'output_sha256':hashlib.sha256(data).hexdigest(),'pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('COWL REMOVAL BUILD PASS',report['output_sha256'])
