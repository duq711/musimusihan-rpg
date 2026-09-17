import bpy
from bpy.props import StringProperty

CONTROL='equipment_adjust'
def rigs():
 return [o for o in bpy.context.scene.objects if o.type=='ARMATURE' and o.get('grip_editor')]

def choose(r):
 if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.select_all(action='DESELECT');r.select_set(True);bpy.context.view_layer.objects.active=r

def prepare():
 previous=bpy.context.object;mode=previous.mode if previous else 'OBJECT'
 selected=list(bpy.context.selected_objects)
 for r in rigs():
  if CONTROL in r.data.bones:continue
  choose(r);bpy.ops.object.mode_set(mode='EDIT')
  wrist=r.data.edit_bones['wrist'];bone=r.data.edit_bones.new(CONTROL)
  bone.head=wrist.head;bone.tail=wrist.tail;bone.roll=wrist.roll;bone.parent=wrist
  bpy.ops.object.mode_set(mode='OBJECT')
  r.pose.bones[CONTROL].rotation_mode='XYZ';r.pose.bones[CONTROL].lock_scale=(True,True,True)
  r.data.bones[CONTROL].color.palette='THEME09'
  for obj in bpy.context.scene.objects:
   if obj.get('editor_equipment') and obj.get('editor_side')==r['editor_side']:
    group=obj.vertex_groups.get('wrist')
    if group:group.name=CONTROL
 if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
 bpy.ops.object.select_all(action='DESELECT')
 for o in selected:o.select_set(True)
 if previous:
  bpy.context.view_layer.objects.active=previous
  if mode!='OBJECT':bpy.ops.object.mode_set(mode=mode)

class GRIP_OT_select_equipment(bpy.types.Operator):
 bl_idname='grip_edit.select_equipment';bl_label='장비 선택'
 side:StringProperty()
 def execute(self,context):
  r=next(o for o in rigs() if o['editor_side']==self.side)
  choose(r);bpy.ops.object.mode_set(mode='POSE')
  for b in r.pose.bones:b.select=False
  r.pose.bones[CONTROL].select=True;r.data.bones.active=r.data.bones[CONTROL]
  context.scene['editor_side']=self.side
  for window in context.window_manager.windows:
   for area in window.screen.areas:
    if area.type=='VIEW_3D':
     area.spaces.active.show_gizmo=True
     with context.temp_override(window=window,area=area):bpy.ops.wm.tool_set_by_id(name='builtin.transform')
  return {'FINISHED'}

class GRIP_PT_equipment(bpy.types.Panel):
 bl_label='검 · 방패 위치와 각도';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='양손 편집';bl_order=-20
 @classmethod
 def poll(cls,context):return bool(rigs())
 def draw(self,context):
  l=self.layout;row=l.row(align=True)
  right=next(o for o in rigs() if o['editor_side']=='right')
  linked=right.get('sword_hand_linked',False)
  row.operator('grip_edit.select_equipment',text='검 + 오른손 선택' if linked else '검만 선택').side='right'
  row.operator('grip_edit.select_equipment',text='방패만 선택').side='left'
  l.label(text='검과 오른손·팔 함께 이동' if linked else 'G 이동 / R 회전 · 손 자세는 유지')
  l.label(text='장비 표면 더블클릭으로도 선택 가능')
  side=context.scene.get('editor_side','right')
  r=next(o for o in rigs() if o['editor_side']==side)
  bone=r.pose.bones.get(CONTROL)
  if bone:
   l.prop(bone,'location',text='장비 위치');l.prop(bone,'rotation_euler',text='장비 각도')

prepare()
for cls in (GRIP_OT_select_equipment,GRIP_PT_equipment):
 old=getattr(bpy.types,cls.__name__,None)
 if old:bpy.utils.unregister_class(old)
 bpy.utils.register_class(cls)
