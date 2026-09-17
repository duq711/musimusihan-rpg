import bpy,json
from pathlib import Path
from mathutils import Matrix
OUT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/exports/Sword_Shield_Manual_Edit')
bpy.ops.wm.open_mainfile(filepath=str(OUT/'검_방패_양손_직접편집.blend'))
exec(compile((OUT/'editor_ui.py').read_text(),str(OUT/'editor_ui.py'),'exec'))
def coords(o):
 bpy.context.view_layer.update();ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());m=ev.to_mesh();v=[ev.matrix_world@p.co for p in m.vertices];ev.to_mesh_clear();return v
checks=[]
for side in ['right','left']:
 bpy.ops.grip_edit.choose(side=side);r=rig();o=bpy.data.objects[r['hand_mesh']];before=coords(o)
 for name in [d+str(i) for d in ['thumb','index','middle','ring','little'] for i in range(3)]+['wrist','forearm','upper_arm']:
  bone=r.pose.bones[name];bone.rotation_euler.x=.20;after=coords(o);delta=max((a-b).length for a,b in zip(before,after));assert delta>1e-5,(side,name,delta);bone.matrix_basis=Matrix.Identity(4)
  checks.append({'side':side,'control':name,'maximum_vertex_movement_m':delta})
 bpy.context.view_layer.update();after=coords(o);assert max((a-b).length for a,b in zip(before,after))<1e-5
 bpy.ops.grip_edit.select(bone='index1');assert bpy.context.object.mode=='POSE'
 bpy.ops.grip_edit.shape(target='glove_mesh');assert bpy.context.object.mode=='EDIT'
 object_mode();bpy.ops.grip_edit.arm();assert bpy.context.object.type=='EMPTY'
 bpy.ops.grip_edit.reset();bpy.ops.grip_edit.view();bpy.ops.grip_edit.equipment();bpy.ops.grip_edit.equipment()
assert all(im.packed_file or im.source!='FILE' or not im.users for im in bpy.data.images)
(OUT/'verification.json').write_text(json.dumps({'passed':True,'controls':checks,'panel_operators':'both hands, bone select, hand surface edit, whole arm select, reset, view, equipment lock','textures_packed':True},indent=2))
print('EDITOR VERIFICATION PASS: 36 deform controls and panel operations')
