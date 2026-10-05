import json,sys,math
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,'/Users/byeolee/Projects/musimusihan-rpg/tools/dcc')
from labrador_pet import set_action
from labrador_pet_bvh import read_bvh
base=Path('/Users/byeolee/Projects/musimusihan-rpg/asset-staging/labrador-gallop-20261006');bpy.ops.wm.open_mainfile(filepath=str(base/'production/LabradorPet_Gallop.blend'))
rig=bpy.data.objects['LabradorPet'];mesh=bpy.data.objects['LabradorPet_Mesh'];set_action(rig,bpy.data.actions['Run'])
index=mesh.vertex_groups['FFB.L_44'].index;ids=[v.index for v in mesh.data.vertices if any(g.group==index and g.weight>.6 for g in v.groups)]
names=['BackLeg.L_26','BackUpperLeg.L_25','BackLowerLeg.L_24','IKBackLeg.L_45','FFB.L_44','BackLeg.R_30','BackUpperLeg.R_29','BackLowerLeg.R_28','IKBackLeg.R_49']
rows=[]
for j in range(61):
 frame=1+j/2;bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update();ev=mesh.evaluated_get(bpy.context.evaluated_depsgraph_get());data=ev.to_mesh();points=[ev.matrix_world@data.vertices[i].co for i in ids];centroid=sum(points,Vector())/len(points)
 row={'frame':frame,'phase':j/60,'LH_paw_centroid_m':list(centroid),'joints_world':{n:list((rig.matrix_world@rig.pose.bones[n].matrix).translation) for n in names},'local_quaternions':{n:list(rig.pose.bones[n].rotation_quaternion) for n in names},'joint_world_quaternions':{n:list((rig.matrix_world@rig.pose.bones[n].matrix).to_quaternion()) for n in names}}
 ev.to_mesh_clear();rows.append(row)
pairs=[(math.dist(a['LH_paw_centroid_m'],b['LH_paw_centroid_m']),i,a,b) for i,(a,b) in enumerate(zip(rows,rows[1:]))];worst=max(pairs,key=lambda p:p[0])
prev,next=worst[2:]
result={'max_LH_paw_step_m':worst[0],'sample_pair':{'before':prev,'after':next},'adjacent_integer_key_samples':[r for r in rows if r['frame'].is_integer() and prev['frame']-1<=r['frame']<=next['frame']+1]}
# Model original standing hock sign, using preserved rig bind/rest positions.
for side,kn,hn,an in [('L','BackUpperLeg.L_25','BackLowerLeg.L_24','IKBackLeg.L_45'),('R','BackUpperLeg.R_29','BackLowerLeg.R_28','IKBackLeg.R_49')]:
 k=rig.data.bones[kn].head_local;h=rig.data.bones[hn].head_local;a=rig.data.bones[an].head_local
 result['rest_hock_'+side]={'tibia_cross_meta_x':(h-k).cross(a-h).x,'reversed_tibia_cross_meta_x':(k-h).cross(a-h).x,'points_rig_units':{kn:list(k),hn:list(h),an:list(a)}}
path=base/'gallop-pop-diagnostic.json';path.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
