import bpy,numpy as np,json,sys
from pathlib import Path
from mathutils import Matrix,Vector
s=Path(__file__).resolve().parents[1];root=s.parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_supplied_hands_20260911/mac_output/iteration_05/bilateral_supplied_hands.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
body=bpy.data.objects['Supplied_AnatomicalHand_left'];rig=bpy.data.objects['Supplied_HandRig_left']
C=np.array([[1,0,0,0],[0,0,1,0],[0,-1,0,0],[0,0,0,1.]])
def mt(a):
 m=np.eye(4);m[:3,:]=np.array(a).T;return m
runtime=json.loads((root/'godot-game/artifacts/visual_qa/torch_grip/baseline_01/geometry.json').read_text())
names=[b.name for b in rig.data.bones];B=np.array([b.matrix_local for b in rig.data.bones]);parents=np.array([names.index(b.parent.name) if b.parent else -1 for b in rig.data.bones])
verts=np.array([v.co for v in body.data.vertices]);normals=np.array([v.normal for v in body.data.vertices]);faces=np.array([p.vertices[:] for p in body.data.polygons])
weights=np.zeros((len(verts),len(names)))
for v in body.data.vertices:
 for g in v.groups:
  n=body.vertex_groups[g.group].name
  if n in names:weights[v.index,names.index(n)]=g.weight
D=np.array([np.linalg.inv(C)@mt(runtime['bones'][n]['pose'])@np.linalg.inv(mt(runtime['bones'][n]['rest']))@C for n in names])
posed=sum((verts@d[:3,:3].T+d[:3,3])*weights[:,i:i+1] for i,d in enumerate(D))
keys=np.array([[p.co[:] for p in k.data] for k in body.data.shape_keys.key_blocks]);keynames=[k.name for k in body.data.shape_keys.key_blocks]
np.savez(s/'audit/fit_input.npz',vertices=verts,normals=normals,faces=faces,weights=weights,bones=B,parents=parents,names=names,key_deltas=keys-keys[0],keynames=keynames,runtime_pose=posed,runtime_deltas=D)
# Actual torch, including its collar and shaft, authored alongside the hand.
for o in scene.objects:o.hide_render=True
holder=bpy.data.objects['LEFT_PreviewTranslationOnly'];holder.matrix_world=Matrix((np.linalg.inv(C)@mt(runtime['arm_in_torch'])@mt(runtime['adapter_in_arm'])@C).tolist())
for o in [holder]+list(holder.children_recursive):o.hide_render=False
for i,n in enumerate(names):rig.pose.bones[n].matrix=Matrix((D[i]@B[i]).tolist())
before=set(scene.objects);bpy.ops.import_scene.gltf(filepath=str(root/'godot-game/assets/3d/dark_fantasy/iron_cage_torch.glb'))
objects=set(scene.objects)-before
for o in objects:
 if o.parent not in objects:o.scale*=.74
 o.hide_render=False
handle=next(o for o in objects if o.name.startswith('CharredHandle'))
bpy.context.view_layer.update()
hv=np.array([handle.matrix_world@v.co for v in handle.data.vertices]);hf=[p.vertices[:] for p in handle.data.polygons]
(s/'audit/handle_mesh.json').write_text(json.dumps({'vertices':hv.tolist(),'faces':hf}))
print('HANDLE_Z_RANGE',hv[:,2].min(),hv[:,2].max(),'RADII',np.linalg.norm(hv[:,:2],axis=1).min(),np.linalg.norm(hv[:,:2],axis=1).max())
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(s/'mac_output/torch_grip_working.blend'))
print('FIT_INPUT_READY',names)
