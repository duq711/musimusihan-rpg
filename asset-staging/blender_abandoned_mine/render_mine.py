"""Render the actual packed Blender source quietly. No Godot window is opened."""
import bpy, json, math, os, time
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parent
OUT=ROOT.parents[1]/'godot-game/artifacts/visual_qa/abandoned_mine'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'blackwater_abandoned_mine.blend'))
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=int(os.environ.get('MINE_RENDER_SAMPLES','24'))
scene.cycles.use_denoising=True
scene.cycles.max_bounces=5
scene.cycles.diffuse_bounces=3
scene.cycles.glossy_bounces=3
scene.render.threads_mode='FIXED'
scene.render.threads=2
scene.render.resolution_x=int(os.environ.get('MINE_RENDER_WIDTH','1100'))
scene.render.resolution_y=round(scene.render.resolution_x*9/16)
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
for obj in scene.objects:
    if obj.name.startswith('collision_') or obj.get('collision_only',False):
        obj.hide_render=True
shots=[
('grand_quarry',(-10,2,2),(1.2536,3,-9.7544),72),
('bone_cavern',(-40,2,29),(-51.9,1.1,25.6),72),
('pillar_shrine',(49.2033,2,-41.6778),(49.4123,3,-55.4226),70),
('longlake',(26.1164,2,36.0247),(38.9657,1.1,28.3764),72),
('workshops',(-1.6715,2,43.0080),(1.4625,1.8,36.2464),72),
]
cam_data=bpy.data.cameras.new('QA_FirstPerson_70deg')
cam_data.sensor_fit='VERTICAL'
cam_data.clip_start=.08
cam_data.clip_end=180
cam=bpy.data.objects.new('QA_FirstPerson',cam_data)
scene.collection.objects.link(cam)
scene.camera=cam
spot_data=bpy.data.lights.new('QA_CarriedTorch_Spot','SPOT')
spot_data.energy=260
spot_data.color=(1,.78,.55)
spot_data.spot_size=math.radians(110)
spot_data.spot_blend=.65
spot_data.shadow_soft_size=.13
spot=bpy.data.objects.new(spot_data.name,spot_data)
scene.collection.objects.link(spot)
spot.parent=cam
spot.location=(-.35,-.2,-.55)
fill_data=bpy.data.lights.new('QA_CarriedTorch_Fill','POINT')
fill_data.energy=90
fill_data.color=(1,.68,.40)
fill_data.shadow_soft_size=.16
fill=bpy.data.objects.new(fill_data.name,fill_data)
scene.collection.objects.link(fill)
fill.parent=cam
fill.location=(-.35,-.2,-.55)
selected=os.environ.get('MINE_RENDER_SHOTS','').split(',')
for name,pos,target,fov in shots:
    if selected!=[''] and name not in selected: continue
    cam.location=Vector((pos[0],-pos[2],pos[1]))
    look=Vector((target[0],-target[2],target[1]))
    cam.rotation_euler=(look-cam.location).to_track_quat('-Z','Y').to_euler()
    cam_data.angle=math.radians(fov)
    scene.render.filepath=str(OUT/(name+'.png'))
    started=time.time()
    bpy.ops.render.render(write_still=True)
    print('MINE_RENDER',name,round(time.time()-started,1),flush=True)
(OUT/'render_notes.json').write_text(json.dumps({'source':'blackwater_abandoned_mine.blend','renderer':bpy.app.version_string+' Cycles CPU','actual_game_capture':False,'description':'Actual exported model/material source. Camera light approximates the in-game carried torch; game UI and enemies are not in this Blender scene.','shots':shots},indent=2))
