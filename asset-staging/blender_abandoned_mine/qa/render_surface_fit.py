import bpy, math, os
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parents[1]/'godot-game/artifacts/visual_qa/abandoned_mine/contact_fixes'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'qa/surface_contact_preview.blend'))
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=12
scene.cycles.use_denoising=True
scene.cycles.max_bounces=4
scene.render.threads_mode='FIXED'
scene.render.threads=2
scene.render.resolution_x=900
scene.render.resolution_y=600
scene.render.resolution_percentage=100
for obj in scene.objects:
    if obj.name.startswith('collision_') or obj.get('collision_only',False):obj.hide_render=True
data=bpy.data.cameras.new('SurfaceFitReview')
data.clip_start=.08
data.clip_end=160
data.angle=math.radians(75)
cam=bpy.data.objects.new('SurfaceFitReview',data)
scene.collection.objects.link(cam)
cam.location=(.0,-59.8,1.85)
cam.rotation_euler=(Vector((3.356,-57.539,1.55))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.camera=cam
light=bpy.data.lights.new('SurfaceReviewTorch','POINT')
light.energy=240
light.color=(1,.78,.55)
light.shadow_soft_size=.12
obj=bpy.data.objects.new(light.name,light)
scene.collection.objects.link(obj)
obj.parent=cam
obj.location=(-.35,-.2,-.55)
scene.render.filepath=str(OUT/'blender_scan_fit_draft.png')
bpy.ops.render.render(write_still=True)
print('SURFACE_FIT_RENDER_COMPLETE',flush=True)
