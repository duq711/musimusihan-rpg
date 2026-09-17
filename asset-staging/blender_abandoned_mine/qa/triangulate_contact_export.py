"""Finalize new prop cap topology without regenerating or moving the scene."""
import bpy, sys, os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
import scene_polish
scene_polish.prepare_meshes_for_export()
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
temp=ROOT/'abandoned_mine_export.glb'
bpy.ops.export_scene.gltf(filepath=str(temp),export_format='GLB',export_apply=True,export_yup=True,export_normals=True,export_tangents=True,export_materials='EXPORT',export_animations=False,export_cameras=False,export_lights=False,export_extras=True,export_image_format='AUTO')
os.replace(temp,ROOT.parents[1]/'godot-game/assets/3d/abandoned_mine/abandoned_mine.glb')
print('CONTACT_TRIANGULATED_EXPORT_COMPLETE',flush=True)
