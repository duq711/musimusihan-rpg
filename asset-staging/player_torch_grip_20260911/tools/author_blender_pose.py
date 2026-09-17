import bpy,numpy as np,json,math,sys,hashlib
from pathlib import Path
from mathutils import Matrix,Vector,Quaternion
s=Path(__file__).resolve().parents[1];root=s.parents[1]
bpy.ops.wm.open_mainfile(filepath=str(s/'mac_output/torch_grip_working.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
info=json.loads((s/'mac_output/torch_grip_pose.json').read_text());q=info['parameters'];C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
a=info['arm_transform_godot'];G=Matrix.Identity(4)
for i in range(3):G.col[i]=Vector((*a[i],0))
G.translation=Vector(a[3]);O=Matrix.Translation((0,.019,-.0035))
holder=bpy.data.objects['LEFT_PreviewTranslationOnly'];holder.matrix_world=C.inverted()@G@O@C
rig=bpy.data.objects['Supplied_HandRig_left'];body=bpy.data.objects['Supplied_AnatomicalHand_left']
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
for di,d in enumerate(('thumb','index','middle','ring','little')):
 for j in range(3):
  angle=q[di*3+j];r=Quaternion((1,0,0),angle)
  if d=='thumb' and j==0:r=Quaternion((0,1,0),q[15])@r
  if j==0 and d!='thumb':r=Quaternion((0,0,1),info['root_adduction_radians'][d])@r
  rig.pose.bones[d+str(j)].rotation_mode='QUATERNION';rig.pose.bones[d+str(j)].rotation_quaternion=r
  limit=math.radians(([25,35,45] if d=='thumb' else [60,45,45])[j])
  body.data.shape_keys.key_blocks[f'Joint_{d}_{j}'].value=max(0,min(1,-angle/limit))
bpy.context.view_layer.update()
ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=ev.to_mesh();actual=np.array([v.co for v in mesh.vertices]);ev.to_mesh_clear()
expected=np.load(s/'audit/fitted_vertices_04.npy');err=np.linalg.norm(actual-expected,axis=1)
assert err.max()<1e-6,err.max()
# Save pad landmarks from actual source vertices for independent runtime skinning QA.
x=np.load(s/'audit/fit_input.npz');v=x['vertices'];N=x['normals'];W=x['weights'];B=x['bones'];names=list(x['names']);center=np.array(info['shaft_in_hand']['center']);axis=np.array(info['shaft_in_hand']['axis'])
rel=actual-center;along=rel@axis;radii=np.linalg.norm(rel-along[:,None]*axis,axis=1);rings=np.array(info['handle_rings']);dist=radii-np.interp(.12+along,rings[:,0],rings[:,1]);regions={}
for d in ('thumb','index','middle','ring','little','palm'):
 if d=='palm':mask=(np.abs(v[:,0])<.024)&(v[:,1]>.03)&(v[:,1]<.073)&(N[:,2]<-.4)
 else:
  i=names.index(d+'2');inv=np.linalg.inv(B[i]);loc=v@inv[:3,:3].T+inv[:3,3];ns=N@B[i,:3,:3];mask=(W[:,i]>.65)&(loc[:,1]>.005)&(ns[:,2]<-.25)
 ids=np.where(mask)[0];ids=ids[np.argsort(dist[ids])[:12]]
 regions[d]={'bind_points_godot':[[float(p[0]),float(p[2]),float(-p[1])] for p in v[ids]],'vertex_ids_native':ids.tolist(),'native_distances_m':dist[ids].tolist()}
# Independently audit the middle phalanges, not just fingertip pads.
for d in ('index','middle','ring','little'):
 i=names.index(d+'1');ns=N@B[i,:3,:3];ids=np.where((W[:,i]>.55)&(ns[:,2]<-.3))[0];ids=ids[np.argsort(dist[ids])[:12]]
 regions[d+'_middle']={'bind_points_godot':[[float(p[0]),float(p[2]),float(-p[1])] for p in v[ids]],'vertex_ids_native':ids.tolist(),'native_distances_m':dist[ids].tolist()}
(root/'godot-game/tests/torch_grip_contact_samples.json').write_text(json.dumps(regions,indent=2))
for im in bpy.data.images:
 if im.source=='FILE' and im.users and not im.packed_file:im.pack()
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(s/'mac_output/torch_grip_authored.blend'))
(s/'audit/blender_pose_match.json').write_text(json.dumps({'maximum_skin_point_error_m':float(err.max()),'vertices':len(v),'source_geometry_changed':False,'pose':info,'bind_pad_samples':regions},indent=2))
print('BLENDER_POSE_MATCH_PASS',err.max(),flush=True)
