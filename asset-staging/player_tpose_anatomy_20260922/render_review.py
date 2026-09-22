import bpy, math
from mathutils import Vector
from pathlib import Path
ROOT=Path(__file__).resolve().parent
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.import_scene.gltf(filepath=str(ROOT/'gravebound_player_tpose.glb'))
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.render.resolution_x=1400
scene.render.resolution_y=1400
scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('Studio')
scene.world.use_nodes=True
scene.world.node_tree.nodes.get('Background').inputs[0].default_value=(.15,.17,.18,1)
scene.world.node_tree.nodes.get('Background').inputs[1].default_value=.55
scene.view_settings.view_transform='AgX'
for name,xyz,energy,size in [('Key',(-2,3,4),450,4),('Fill',(3,2,2),160,3),('Rim',(0,-3,3),220,3)]:
 data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
 ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=xyz;ob.rotation_euler=(Vector((0,0,1.2))-ob.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Review camera');camera=bpy.data.objects.new('Review camera',data);scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO'
out=ROOT/'renders';out.mkdir(exist_ok=True)
def render(name,xyz,target,scale):
 camera.location=xyz;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler();data.ortho_scale=scale;scene.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
render('tpose_front',(0,4,.87),(0,0,.87),1.97)
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Gravebound_Tpose_Review.blend'),compress=True)
clay=bpy.data.materials.new('Neutral clay');clay.diffuse_color=(.46,.51,.54,1);clay.use_nodes=True;bsdf=clay.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Base Color'].default_value=(.46,.51,.54,1);bsdf.inputs['Roughness'].default_value=.85
for ob in scene.objects:
 if ob.type=='MESH':
  for i in range(len(ob.data.materials)):ob.data.materials[i]=clay
scene.render.resolution_y=1000
render('upper_front_clay',(0,4,1.37),(0,0,1.37),1.42)
render('upper_oblique_clay',(-1.5,4,1.7),(0,0,1.37),1.42)
render('upper_rear_clay',(0,-4,1.4),(0,0,1.37),1.42)
