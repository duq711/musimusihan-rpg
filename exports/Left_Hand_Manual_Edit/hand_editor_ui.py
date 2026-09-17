import bpy,json
from mathutils import Vector
RIG='Supplied_HandRig_left'
DIGITS=[('thumb','엄지'),('index','검지'),('middle','중지'),('ring','약지'),('little','새끼')]
def rig():return bpy.data.objects.get(RIG)
def arm():return bpy.data.objects.get('LEFT_PreviewTranslationOnly')
class HAND_OT_arm_select(bpy.types.Operator):
 bl_idname='hand_manual.arm_select';bl_label='팔 전체 선택'
 def execute(self,context):
  if context.object and context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
  for o in context.selected_objects:o.select_set(False)
  h=arm();h.hide_set(False);h.hide_select=False;h.select_set(True);context.view_layer.objects.active=h
  return {'FINISHED'}
class HAND_OT_arm_reset(bpy.types.Operator):
 bl_idname='hand_manual.arm_reset';bl_label='팔 위치만 복원';bl_options={'REGISTER','UNDO'}
 def execute(self,context):
  h=arm();a=json.loads(h['editor_arm_start']);h.location=a['location'];h.rotation_euler=a['rotation']
  return {'FINISHED'}
class HAND_OT_arm_show(bpy.types.Operator):
 bl_idname='hand_manual.arm_show';bl_label='팔뚝 표시 / 숨김';bl_options={'REGISTER','UNDO'}
 def execute(self,context):
  objs=[o for o in context.scene.objects if o.name.startswith(('Forearm','UpperArm'))]
  show=any(o.hide_get() for o in objs)
  for o in objs:o.hide_set(not show)
  return {'FINISHED'}
class HAND_OT_select(bpy.types.Operator):
 bl_idname='hand_manual.select';bl_label='이 마디 선택'
 bone:bpy.props.StringProperty()
 def execute(self,context):
  r=rig()
  if context.object and context.object.mode!='OBJECT':bpy.ops.object.mode_set(mode='OBJECT')
  for o in context.selected_objects:o.select_set(False)
  r.hide_set(False);r.select_set(True);context.view_layer.objects.active=r;bpy.ops.object.mode_set(mode='POSE')
  for p in r.pose.bones:p.select=False
  r.pose.bones[self.bone].select=True;r.data.bones.active=r.data.bones[self.bone]
  return {'FINISHED'}
class HAND_OT_reset(bpy.types.Operator):
 bl_idname='hand_manual.reset';bl_label='시작 자세로 복원';bl_options={'REGISTER','UNDO'}
 neutral:bpy.props.BoolProperty(default=False)
 def execute(self,context):
  r=rig();stored=json.loads(r['editor_start_angles'])
  for n,a in stored.items():r.pose.bones[n].rotation_euler=(0,0,0) if self.neutral else a
  context.view_layer.update();return {'FINISHED'}
class HAND_OT_shaft(bpy.types.Operator):
 bl_idname='hand_manual.shaft';bl_label='자루 표시 / 숨김';bl_options={'REGISTER','UNDO'}
 def execute(self,context):
  r=rig();show=not r.get('editor_show_shaft',True);r['editor_show_shaft']=show
  for o in context.scene.objects:
   if o.name.startswith(('CharredHandle','LeatherWrap')):o.hide_set(not show)
  return {'FINISHED'}
class HAND_OT_view(bpy.types.Operator):
 bl_idname='hand_manual.view';bl_label='손 보기'
 direction:bpy.props.StringProperty(default='palm')
 def execute(self,context):
  h=bpy.data.objects['LEFT_PreviewTranslationOnly'];center=h.matrix_world@Vector((0,.062,.013))
  vectors={'palm':(0,0,-1),'back':(0,0,1),'thumb':(1,0,0),'little':(-1,0,0),'three':(.8,-.2,-1)}
  d=(h.matrix_world.to_3x3()@Vector(vectors[self.direction])).normalized();q=(-d).to_track_quat('-Z','Y')
  for area in context.screen.areas:
   if area.type=='VIEW_3D':
    v=area.spaces.active.region_3d;v.view_location=center;v.view_distance=.42;v.view_rotation=q;v.view_perspective='ORTHO'
  return {'FINISHED'}
class HAND_OT_save(bpy.types.Operator):
 bl_idname='hand_manual.save';bl_label='작업 저장'
 def execute(self,context):bpy.ops.wm.save_mainfile();self.report({'INFO'},'손 작업을 저장했습니다. Godot에는 아직 자동 반영되지 않습니다.');return {'FINISHED'}
class HAND_PT_editor(bpy.types.Panel):
 bl_label='왼손 · 손가락 조절';bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='손 편집'
 @classmethod
 def poll(cls,context):return rig() is not None and rig().get('torch_hand_editor',False)
 def draw(self,context):
  r=rig();l=self.layout;l.label(text='숫자를 좌우로 드래그하여 조절하세요.')
  row=l.row(align=True);row.operator('hand_manual.save',text='작업 저장',icon='FILE_TICK');row.operator('hand_manual.shaft',text='자루 표시/숨김',icon='HIDE_OFF')
  row=l.row(align=True)
  for d,label in [('palm','손바닥'),('back','손등'),('thumb','엄지쪽'),('little','새끼쪽')]:row.operator('hand_manual.view',text=label).direction=d
  h=arm()
  if h:
   b=l.box();b.label(text='팔·손 전체 이동 / 회전')
   b.label(text='자루는 고정됩니다.')
   b.prop(h,'location',text='위치')
   b.prop(h,'rotation_euler',text='회전')
   b.operator('hand_manual.arm_select',text='팔 선택 (G 이동 / R 회전)',icon='ORIENTATION_GLOBAL')
   row=b.row(align=True);row.operator('hand_manual.arm_reset',text='팔 위치 복원');row.operator('hand_manual.arm_show',text='팔뚝 표시')
  for d,label in DIGITS:
   b=l.box();b.label(text=label)
   for j,title in enumerate(['뿌리 굽힘','중간 마디','끝마디']):
    row=b.row(align=True);row.operator('hand_manual.select',text='',icon='BONE_DATA').bone=d+str(j);row.prop(r.pose.bones[d+str(j)],'rotation_euler',index=0,text=title)
   row=b.row(align=True);row.prop(r.pose.bones[d+'0'],'rotation_euler',index=2,text='뿌리 방향')
   if d=='thumb':b.prop(r.pose.bones['thumb0'],'rotation_euler',index=1,text='엄지 비틀기')
  row=l.row(align=True);row.operator('hand_manual.reset',text='시작 자세');row.operator('hand_manual.reset',text='원본 자세').neutral=True
  l.label(text='Ctrl+Z: 실행 취소 / N: 패널 열기')
classes=[HAND_OT_arm_select,HAND_OT_arm_reset,HAND_OT_arm_show,HAND_OT_select,HAND_OT_reset,HAND_OT_shaft,HAND_OT_view,HAND_OT_save,HAND_PT_editor]
for cls in classes:
 old=getattr(bpy.types,cls.__name__,None)
 if old:
  try:bpy.utils.unregister_class(old)
  except:pass
 bpy.utils.register_class(cls)
def activate():
 for window in bpy.context.window_manager.windows:
  for area in window.screen.areas:
   if area.type=='VIEW_3D':
    area.spaces.active.show_region_ui=True
    for region in area.regions:
     if region.type=='UI' and hasattr(region,'active_panel_category'):
      region.active_panel_category='손 편집'
 return None
bpy.app.timers.register(activate,first_interval=1.0)

h=arm()
if h and 'editor_arm_start' not in h:
 h['editor_arm_start']=json.dumps({'location':list(h.location),'rotation':list(h.rotation_euler)})
if h:
 h.lock_location=(False,False,False);h.lock_rotation=(False,False,False)
