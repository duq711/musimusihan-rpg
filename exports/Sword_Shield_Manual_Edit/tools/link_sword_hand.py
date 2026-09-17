import bpy,json,shutil,datetime
from pathlib import Path
from mathutils import Vector
p=Path(bpy.data.filepath)
r=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE' and o.get('editor_side')=='right' and o.get('grip_editor'))

def points():
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 return {o.name:[o.matrix_world@v.co for v in o.evaluated_get(dg).data.vertices] for o in bpy.context.scene.objects if o.type=='MESH'}

def error(a,b):return max(((u-v).length for n,pts in a.items() for u,v in zip(pts,b[n])),default=0)
before=points()
if not r.get('sword_hand_linked'):
 poses={b.name:b.matrix.copy() for b in r.pose.bones}
 if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.select_all(action='DESELECT');r.select_set(True);bpy.context.view_layer.objects.active=r;bpy.ops.object.mode_set(mode='EDIT')
 r.data.edit_bones['equipment_adjust'].parent=None
 r.data.edit_bones['upper_arm'].parent=r.data.edit_bones['equipment_adjust']
 bpy.ops.object.mode_set(mode='POSE')
 def depth(b):return 0 if not b.parent else depth(b.parent)+1
 for b in sorted(r.pose.bones,key=depth):
  b.matrix=poses[b.name];bpy.context.view_layer.update()
 r['sword_hand_linked']=True
preserve_error=error(before,points());assert preserve_error<.00001,preserve_error
control=r.pose.bones['equipment_adjust'];base=control.matrix_basis.copy();old_world=r.matrix_world@control.matrix
control.location.x+=.025;control.rotation_euler.y+=.16;bpy.context.view_layer.update()
xf=(r.matrix_world@control.matrix)@old_world.inverted();moved=points()
errors={}
for name,pts in before.items():
 obj=bpy.data.objects[name]
 expected=[xf@v for v in pts] if obj.get('editor_side')=='right' else pts
 errors[name]=max(((u-v).length for u,v in zip(expected,moved[name])),default=0)
assert max(errors.values())<.00002,errors
control.matrix_basis=base;bpy.context.view_layer.update();assert error(before,points())<.00001
for b in r.pose.bones:b.select=False
control.select=True;r.data.bones.active=r.data.bones['equipment_adjust']
bpy.context.scene['editor_side']='right'
shutil.copy2(p,p.with_name('before_sword_hand_link_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S')+'.blend'))
bpy.ops.wm.save_as_mainfile(filepath=str(p))
(p.parent/'sword_hand_link_verification.json').write_text(json.dumps({'pose_preservation_error_m':preserve_error,'rigid_movement_error_m':max(errors.values()),'shield_and_left_hand_unchanged':True,'control':'equipment_adjust'},indent=2))
print('SWORD HAND LINK PASS',preserve_error,max(errors.values()))
