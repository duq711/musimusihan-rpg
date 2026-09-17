import bpy,json,math,shutil
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
p=Path(bpy.data.filepath);out=p.parent/'finger_fit'
r=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE' and o.get('editor_side')=='left')
o=bpy.data.objects[r['hand_mesh']]
original={b.name:b.matrix_basis.copy() for b in r.pose.bones}

def points(d,tip=False):
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();ev=o.evaluated_get(dg)
 ids={o.vertex_groups[d+str(i)].index for i in ((2,) if tip else (1,2))}
 return [o.matrix_world@v.co for v in ev.data.vertices if sum(g.weight for g in v.groups if g.group in ids)>.7]

def nearest(a,b,tip=False):
 pa=points(a,tip);pb=points(b,tip);t=KDTree(len(pb))
 for i,v in enumerate(pb):t.insert(v,i)
 t.balance();return min(((t.find(v)[2],v,t.find(v)[0]) for v in pa),key=lambda q:q[0])

report={};adjusted={}
# Keep index as the reference; close each adjacent gap along its local separation.
for a,b in [('index','middle'),('middle','ring'),('ring','little')]:
 first=nearest(a,b)[0];total=Vector()
 for step in range(20):
  dist,va,vb=nearest(a,b)
  if dist<=.00055:break
  delta=(va-vb).normalized()*min(dist-.0005,.00035)
  bone=r.pose.bones[b+'0'];matrix=bone.matrix.copy();matrix.translation+=r.matrix_world.inverted().to_3x3()@delta
  bone.matrix=matrix;total+=delta
 report[a+'_'+b]={'initial_gap_m':first,'final_gap_m':nearest(a,b)[0],'shift_m':list(total)}
# Close the remaining distal opening along the hand's transverse axis.
axis=(sum(points('index',True),Vector())/len(points('index',True))-sum(points('little',True),Vector())/len(points('little',True))).normalized()
for name,amount in [('ring0',.0025),('little0',.005)]:
 bone=r.pose.bones[name];m=bone.matrix.copy();m.translation+=r.matrix_world.inverted().to_3x3()@(axis*amount);bone.matrix=m
for b in r.pose.bones:
 if b.name not in ('middle0','ring0','little0'):
  assert max(abs(b.matrix_basis[i][j]-original[b.name][i][j]) for i in range(4) for j in range(4))<1e-6
adjusted={name:r.pose.bones[name].matrix_basis.copy() for name in ('middle0','ring0','little0')}
(out/'fit_report.json').write_text(json.dumps(report,indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(out/'fingers_contact_candidate.blend'),copy=True)
# Render real meshes from the user's saved close-up direction, then a second side view.
scene=bpy.context.scene
view=next(a.spaces.active.region_3d for s in bpy.data.screens for a in s.areas if a.type=='VIEW_3D' and a.spaces.active.region_3d.view_distance<.4)
rotation=view.view_rotation.copy();center=view.view_location.copy()
camdata=bpy.data.cameras.new('finger_fit_qa');cam=bpy.data.objects.new('finger_fit_qa',camdata);scene.collection.objects.link(cam)
cam.rotation_euler=rotation.to_euler();cam.location=center+rotation@Vector((0,0,.25));camdata.lens=45;camdata.clip_start=.005;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=850;scene.render.resolution_y=850;scene.render.resolution_percentage=100
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.10,.10,.10,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.4
for pos,energy,size in [((-.15,-.05,.20),5,.25),((.15,.02,.12),3,.20)]:
 ld=bpy.data.lights.new('soft_light','AREA');ld.energy=energy;ld.shape='DISK';ld.size=size
 light=bpy.data.objects.new('soft_light',ld);scene.collection.objects.link(light);light.location=center+rotation@Vector(pos);light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
for phase in ['before','after']:
 for name,matrix in adjusted.items():r.pose.bones[name].matrix_basis=original[name] if phase=='before' else matrix
 bpy.context.view_layer.update();scene.render.filepath=str(out/(phase+'.png'));bpy.ops.render.render(write_still=True)
# View from slightly around the same hand; geometry and pose remain identical.
from mathutils import Quaternion
q=rotation@Quaternion((0,1,0),math.radians(28));cam.rotation_euler=q.to_euler();cam.location=center+q@Vector((0,0,.25));scene.render.filepath=str(out/'after_side.png');bpy.ops.render.render(write_still=True)
print('FINGER FIT PASS',report)
