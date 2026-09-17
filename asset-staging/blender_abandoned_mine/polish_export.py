"""Apply the same production polish to an already authored .blend, then export."""
import bpy,json,sys,os
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT))
ASSETS=ROOT.parents[1]/'godot-game/assets/3d/abandoned_mine'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
layout=json.loads((ROOT/'layout.json').read_text())
report=json.loads((ASSETS/'build_manifest.json').read_text())
import scene_polish
report=scene_polish.finish_scene(layout,report)
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
temp=ROOT/'abandoned_mine_export.glb'
bpy.ops.export_scene.gltf(filepath=str(temp),export_format='GLB',export_apply=True,export_yup=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_extras=True,export_image_format='AUTO')
os.replace(temp,ASSETS/'abandoned_mine.glb')
(ASSETS/'build_manifest.json').write_text(json.dumps(report,indent=2))
(ROOT/'build_report.json').write_text(json.dumps(report,indent=2))
print('POLISH EXPORT COMPLETE',report['polish'],flush=True)
