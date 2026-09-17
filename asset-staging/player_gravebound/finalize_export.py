"""Normalize runtime UV compatibility and canonical Godot -Z front direction."""
from pathlib import Path
import bpy,json,math
ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg');WORK=ROOT/'asset-staging/player_gravebound';OUT=ROOT/'godot-game/assets/3d/player/gravebound_player.glb'
bpy.ops.wm.open_mainfile(filepath=str(WORK/'gravebound_player.blend'))
parent=bpy.data.objects['GraveboundPlayer'];parts=[o for o in bpy.data.objects if o.type=='MESH' and o.parent==parent]
for o in parts:
 for uv in list(o.data.uv_layers):
  if uv.name!='Atlas':o.data.uv_layers.remove(uv)
 o.data.uv_layers.active_index=0;o.data.uv_layers[0].active_render=True
bpy.ops.object.select_all(action='DESELECT');parent.select_set(True)
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parent
bpy.ops.wm.save_as_mainfile(filepath=str(WORK/'gravebound_player.blend'))
parent.rotation_euler.z=math.pi;bpy.context.view_layer.update()
props=set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
args=dict(filepath=str(OUT),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_animations=False,export_skins=False,export_extras=True,export_image_format='JPEG',export_jpeg_quality=95)
bpy.ops.export_scene.gltf(**{k:v for k,v in args.items() if k in props})
report=json.loads((WORK/'build_report.json').read_text());report.update({'uv_channels':['Atlas'],'atlas_size':[4096,4096],'glb_bytes':OUT.stat().st_size,'front_axis_godot':'-Z'});(WORK/'build_report.json').write_text(json.dumps(report,indent=2))
print('FINALIZED',OUT,OUT.stat().st_size,'bytes; Atlas UV0; Godot front -Z')
