import bpy,math,json,hashlib
from pathlib import Path
from mathutils import Vector
s=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(s/'mac_output/torch_grip_authored.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene;scene.name='Torch_Grip_Authoring'
for o in scene.objects:
 if o.hide_render:o.hide_set(True)
# A saved, framed authoring view; source geometry and all bone poses are untouched.
camdata=bpy.data.cameras.new('TorchGrip_ReviewCamera');camera=bpy.data.objects.new(camdata.name,camdata);scene.collection.objects.link(camera)
center=Vector((0,0,.12));camera.location=(.25,-.55,.23);camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=.29;scene.camera=camera
for name,location,energy,size in [('Key',(-.3,-.45,.6),35,.5),('Fill',(.4,.1,.35),15,.5)]:
 data=bpy.data.lights.new('TorchGrip_'+name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
 o=bpy.data.objects.new(data.name,data);scene.collection.objects.link(o);o.location=location;o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler()
scene.world=bpy.data.worlds.new('TorchGrip_NeutralWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.08,.08,.08,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.3
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=2;scene.view_settings.exposure=-.7
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   area.spaces.active.region_3d.view_location=center;area.spaces.active.region_3d.view_distance=.55;area.spaces.active.region_3d.view_rotation=camera.rotation_euler.to_quaternion()
readme=bpy.data.texts.new('TORCH_GRIP_README');readme.write('Supplied left hand with authored torch-only pose. Geometry, weights and UV are unchanged. Signed bone rotations partly unbend the already curled source. Runtime pose lives in godot-game/scripts/torch_grip_pose.gd. Native forearm is shown in its authoring rest; Godot fits the sleeve to the live shoulder/elbow. All referenced source textures are packed.\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(s/'mac_output/torch_grip_final.blend'))
scene.render.filepath=str(s/'review/blender_torch_grip.png');bpy.ops.render.render(write_still=True)
print('TORCH_NATIVE_FINAL_READY',flush=True)
