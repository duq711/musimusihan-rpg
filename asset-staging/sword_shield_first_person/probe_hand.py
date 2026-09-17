import bpy, json
from pathlib import Path
from mathutils import Vector, Matrix
p=Path(__file__).parent
bpy.ops.wm.open_mainfile(filepath=str(p/'anatomy_source.blend'))
body=bpy.data.objects['GEO-body_male_realistic']
body.parent=None
body.matrix_world=Matrix.Identity(4)
bpy.context.view_layer.update()
for obj in list(bpy.data.objects):
    if obj != body: bpy.data.objects.remove(obj,do_unlink=True)
body.hide_render=False
scene=bpy.context.scene
scene.render.engine='BLENDER_WORKBENCH'
scene.display.shading.light='STUDIO'
scene.display.shading.studiolight_rotate_z=0.3
scene.display.shading.color_type='SINGLE'
scene.display.shading.single_color=(.62,.53,.45)
scene.display.shading.show_shadows=True
scene.display.shading.show_cavity=True
scene.display.shading.cavity_type='BOTH'
scene.display.shading.background_type='WORLD'
scene.world=bpy.data.worlds.new('ProbeWorld')
scene.world.color=(.045,.045,.045)
scene.render.resolution_x=768
scene.render.resolution_y=768
scene.render.resolution_percentage=100
for label,offset in [('front',(0,-2,0)),('back',(0,2,0)),('side',(2,0,0))]:
    camdata=bpy.data.cameras.new(label)
    cam=bpy.data.objects.new(label,camdata)
    scene.collection.objects.link(cam)
    target=Vector((.36,0,.90))
    cam.location=target+Vector(offset)
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
    camdata.type='ORTHO';camdata.ortho_scale=.40
    scene.camera=cam
    scene.render.filepath=str(p/('source_hand_'+label+'.png'))
    bpy.ops.render.render(write_still=True)
