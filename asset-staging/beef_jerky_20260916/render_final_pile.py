import bpy
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[2]
out=root/'exports/Beef_Jerky_2026-09-16'
bpy.ops.wm.open_mainfile(filepath=str(out/'beef_jerky.blend'))
scene=bpy.context.scene
for obj in bpy.data.objects:
    if obj.name.startswith('Pile_'):
        obj.hide_set(False)
        obj.hide_render=False
    elif obj.name.startswith('Jerky_'):
        obj.hide_render=True
cam=scene.camera
cam.location=(.30,-.40,.43)
cam.data.ortho_scale=.40
cam.rotation_euler=(Vector((0,0,.025))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=1600
scene.render.resolution_y=1100
scene.render.filepath=str(out/'jerky_pile.png')
bpy.ops.render.render(write_still=True)
