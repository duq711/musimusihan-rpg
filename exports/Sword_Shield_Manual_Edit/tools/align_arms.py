import bpy,json,math,shutil,datetime
from pathlib import Path
from mathutils import Vector,Matrix
p=Path(bpy.data.filepath);out=p.parent/'arm_alignment'
rigs={o['editor_side']:o for o in bpy.context.scene.objects if o.type=='ARMATURE' and o.get('grip_editor')}
def reflect(v):return Vector((-v.x,v.y,v.z))
def wrist(r):return r.matrix_world@r.pose.bones['wrist'].head
def direction(r):return (r.matrix_world.to_3x3()@(r.pose.bones['forearm'].tail-r.pose.bones['forearm'].head)).normalized()
def points():
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 return {o.name:[o.matrix_world@v.co for v in o.evaluated_get(dg).data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}
before=points();old={s:bpy.data.objects[r['assembly_name']].matrix_world.copy() for s,r in rigs.items()}
target=(wrist(rigs['right'])+reflect(wrist(rigs['left'])))*.5
d=(direction(rigs['right'])+reflect(direction(rigs['left']))).normalized()
transforms={}
for side,r in rigs.items():
 goal=target if side=='right' else reflect(target)
 aim=d if side=='right' else reflect(d)
 rotation=direction(r).rotation_difference(aim).to_matrix().to_4x4()
 xf=Matrix.Translation(goal)@rotation@Matrix.Translation(-wrist(r))
 transforms[side]=xf
 bpy.data.objects[r['assembly_name']].matrix_world=xf@old[side]
bpy.context.view_layer.update();after=points()
err=max(((transforms[bpy.data.objects[n]['editor_side']]@v-w).length for n,vs in before.items() if bpy.data.objects[n].get('editor_side') in rigs for v,w in zip(vs,after[n])),default=0)
assert err<1e-5,err
assert (wrist(rigs['right'])-reflect(wrist(rigs['left']))).length<1e-5
assert not rigs['right'].get('sword_hand_linked')
backup=p.with_name('before_arm_alignment_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'.blend');shutil.copy2(p,backup)
bpy.ops.wm.save_as_mainfile(filepath=str(p))
(out/'verification.json').write_text(json.dumps({'rigid_pose_preservation_error_m':err,'wrist_right':list(wrist(rigs['right'])),'wrist_left':list(wrist(rigs['left'])),'forearm_right':list(direction(rigs['right'])),'forearm_left':list(direction(rigs['left'])),'sword_independent':True,'backup':str(backup)},indent=2))
# QA only: identical perspective and soft lights for before/after.
scene=bpy.context.scene
cd=bpy.data.cameras.new('arm_alignment_qa');cam=bpy.data.objects.new('arm_alignment_qa',cd);scene.collection.objects.link(cam)
cam.location=(0,-.55,.12);center=Vector((0,.52,-.04));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cd.lens=25;cd.clip_start=.01;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=1000;scene.render.resolution_y=760;scene.render.resolution_percentage=100
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.12,.12,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
for pos,energy,size in [((0,-.4,1.5),90,2),((-1,.2,.3),40,1)]:
 ld=bpy.data.lights.new('qa_soft','AREA');ld.energy=energy;ld.size=size;lo=bpy.data.objects.new('qa_soft',ld);scene.collection.objects.link(lo);lo.location=pos;lo.rotation_euler=(center-lo.location).to_track_quat('-Z','Y').to_euler()
new={s:bpy.data.objects[r['assembly_name']].matrix_world.copy() for s,r in rigs.items()}
for phase,matrices in [('before',old),('after',new)]:
 for s,r in rigs.items():bpy.data.objects[r['assembly_name']].matrix_world=matrices[s]
 bpy.context.view_layer.update();scene.render.filepath=str(out/(phase+'.png'));bpy.ops.render.render(write_still=True)
print('ARM ALIGNMENT PASS',err)
