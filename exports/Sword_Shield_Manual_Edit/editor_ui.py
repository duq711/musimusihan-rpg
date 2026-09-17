import bpy
from mathutils import Vector,Matrix
from bpy.props import StringProperty
DIGITS=[('thumb','엄지'),('index','검지'),('middle','중지'),('ring','약지'),('little','새끼')]
def rig():return next((o for o in bpy.context.scene.objects if o.type=='ARMATURE' and o.get('grip_editor') and o.get('editor_side')==bpy.context.scene.get('editor_side','right')),None)
def object_mode():
 if bpy.context.object and bpy.context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
def select(o,mode='OBJECT'):
 object_mode();bpy.ops.object.select_all(action='DESELECT');o.hide_set(False);o.hide_select=False;o.select_set(True);bpy.context.view_layer.objects.active=o
 if mode!='OBJECT':bpy.ops.object.mode_set(mode=mode)
def focus(r,both=False):
 center=Vector((0,.58,-.15)) if both else r.matrix_world@r.pose.bones['wrist'].head
 for window in bpy.context.window_manager.windows:
  for area in window.screen.areas:
   if area.type=='VIEW_3D':
    sp=area.spaces.active;sp.show_region_ui=True;sp.region_3d.view_location=center;sp.region_3d.view_distance=1.45 if both else .42;sp.region_3d.view_rotation=Vector((0,-1,.25)).to_track_quat('Z','Y');sp.region_3d.view_perspective='PERSP'
class GRIP_OT_choose(bpy.types.Operator):
 bl_idname='grip_edit.choose';bl_label='손 선택'
 side:StringProperty()
 def execute(self,context):
  context.scene['editor_side']=self.side;r=rig();select(r,'POSE');focus(r);return {'FINISHED'}
class GRIP_OT_select(bpy.types.Operator):
 bl_idname='grip_edit.select';bl_label='관절 선택'
 bone:StringProperty()
 def execute(self,context):
  r=rig();select(r,'POSE')
  for b in r.pose.bones:b.select=False
  r.pose.bones[self.bone].select=True;r.data.bones.active=r.data.bones[self.bone];return {'FINISHED'}
class GRIP_OT_shape(bpy.types.Operator):
 bl_idname='grip_edit.shape';bl_label='손등 형태 편집'
 target:StringProperty(default='glove_mesh')
 def execute(self,context):
  o=bpy.data.objects[rig()[self.target]];select(o,'EDIT');bpy.ops.mesh.select_all(action='DESELECT');context.scene.tool_settings.use_proportional_edit=True;context.scene.tool_settings.use_proportional_connected=True
  self.report({'INFO'},'정점을 선택하고 G로 이동하세요. 휠로 영향 범위를 조절합니다. Tab으로 마칩니다.');return {'FINISHED'}
class GRIP_OT_arm(bpy.types.Operator):
 bl_idname='grip_edit.arm';bl_label='팔 전체 이동·회전'
 def execute(self,context):select(bpy.data.objects[rig()['assembly_name']]);return {'FINISHED'}
class GRIP_OT_equipment(bpy.types.Operator):
 bl_idname='grip_edit.equipment';bl_label='장비 고정 / 함께 이동'
 def execute(self,context):
  side=rig()['editor_side']
  for o in context.scene.objects:
   if o.get('editor_equipment') and o.get('editor_side')==side:
    for m in o.modifiers:
     if m.type=='ARMATURE':m.show_viewport=not m.show_viewport;m.show_render=m.show_viewport
  return {'FINISHED'}
class GRIP_OT_reset(bpy.types.Operator):
 bl_idname='grip_edit.reset';bl_label='선택한 팔 시작 자세 복원';bl_options={'REGISTER','UNDO'}
 def execute(self,context):
  r=rig()
  for b in r.pose.bones:b.matrix_basis=Matrix.Identity(4)
  bpy.data.objects[r['assembly_name']].matrix_basis=Matrix.Identity(4);return {'FINISHED'}
class GRIP_OT_view(bpy.types.Operator):
 bl_idname='grip_edit.view';bl_label='양손 전체 보기'
 def execute(self,context):focus(rig(),True);return {'FINISHED'}
class GRIP_OT_save(bpy.types.Operator):
 bl_idname='grip_edit.save';bl_label='작업 저장'
 def execute(self,context):bpy.ops.wm.save_mainfile();self.report({'INFO'},'편집 파일 저장 완료. 게임에는 자동 반영되지 않습니다.');return {'FINISHED'}
class GRIP_PT_editor(bpy.types.Panel):
 bl_label='검·방패 양손 조정';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='양손 편집'
 @classmethod
 def poll(cls,context):return rig() is not None
 def draw(self,context):
  l=self.layout;r=rig();row=l.row(align=True);row.operator('grip_edit.choose',text='검 · 오른손').side='right';row.operator('grip_edit.choose',text='방패 · 왼손').side='left'
  row=l.row(align=True);row.operator('grip_edit.view');row.operator('grip_edit.save')
  l.label(text='숫자를 드래그하거나 관절 선택 후 R')
  b=l.box();b.label(text='팔 · 손목 · 손등 방향')
  b.operator('grip_edit.arm',text='팔 전체 선택 → G 이동 / R 회전')
  for name,label in [('upper_arm','위팔'),('forearm','팔뚝'),('wrist','손목·손등')]:
   row=b.row();row.operator('grip_edit.select',text=label).bone=name;row.prop(r.pose.bones[name],'rotation_euler',text='')
  b.operator('grip_edit.shape',text='장갑·손등 표면 편집').target='glove_mesh'
  b.operator('grip_edit.shape',text='피부·손가락 표면 편집').target='hand_mesh'
  b.operator('grip_edit.equipment')
  for d,label in DIGITS:
   b=l.box();b.label(text=label)
   for i,title in enumerate(['뿌리','가운데','끝마디']):
    row=b.row();row.operator('grip_edit.select',text=title).bone=d+str(i);row.prop(r.pose.bones[d+str(i)],'rotation_euler',text='')
  l.operator('grip_edit.reset');l.label(text='Ctrl+Z 취소 / Ctrl+S 저장')
  l.label(text='게임 자동 반영 없음 · 원본 보존')
classes=[GRIP_OT_choose,GRIP_OT_select,GRIP_OT_shape,GRIP_OT_arm,GRIP_OT_equipment,GRIP_OT_reset,GRIP_OT_view,GRIP_OT_save,GRIP_PT_editor]
for cls in classes:
 old=getattr(bpy.types,cls.__name__,None)
 if old:
  try:bpy.utils.unregister_class(old)
  except:pass
 bpy.utils.register_class(cls)
def activate():
 r=rig()
 if r:
  select(r,'POSE')
  if not bpy.context.scene.get('editor_preserve_view',False):focus(r,True)
 return None
bpy.app.timers.register(activate,first_interval=1.0)
from pathlib import Path
equipment_path=Path(bpy.data.filepath).parent/'equipment_controls.py'
if equipment_path.exists():
 exec(compile(equipment_path.read_text(),str(equipment_path),'exec'),{'__name__':'grip_equipment'})
picker_path=Path(bpy.data.filepath).parent/'direct_picker.py'
if picker_path.exists():
 exec(compile(picker_path.read_text(),str(picker_path),'exec'),{'__name__':'grip_direct_picker'})
