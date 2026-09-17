import bpy,json,math
from pathlib import Path
from mathutils import Vector
s=Path(__file__).resolve().parents[1];root=s.parents[1];out=root/'exports/Left_Hand_Manual_Edit'
bpy.ops.wm.open_mainfile(filepath=str(s/'mac_output/torch_grip_authored.blend'))
source=bpy.data.scenes['Bilateral_SuppliedHands_Review'];scene=bpy.data.scenes.new('왼손_횃불_직접편집');bpy.context.window.scene=scene
holder=bpy.data.objects['LEFT_PreviewTranslationOnly'];rig=bpy.data.objects['Supplied_HandRig_left'];body=bpy.data.objects['Supplied_AnatomicalHand_left']
objects=[holder]+list(holder.children_recursive)
objects += [o for o in source.objects if o.name.startswith(('CharredHandle','LeatherWrap'))]
# Keep required ancestors of the shaft meshes and all original source objects.
for o in list(objects):
 p=o.parent
 while p:
  if p not in objects:objects.append(p)
  p=p.parent
for o in objects:
 if o.name not in scene.objects:scene.collection.objects.link(o)
 o.hide_set(False);o.hide_viewport=False
 if o.name.startswith(('UpperArm','Forearm')):o.hide_set(True);o.hide_render=True
 elif o.type=='MESH':o.hide_render=False
for o in objects:
 if o.type=='MESH' and not o.name.startswith(('Supplied_','Nail_')):o.hide_select=True
# Retain original bone names, neutral mesh and current authored pose for later Godot integration.
rest={}
for b in rig.pose.bones:
 b.rotation_euler=b.rotation_quaternion.to_euler('XYZ');b.rotation_mode='XYZ';rest[b.name]=list(b.rotation_euler)
 b.lock_location=(True,True,True);b.lock_scale=(True,True,True)
 b.select=False
 if b.name=='wrist':b.bone.hide=True
 else:b.bone.color.palette={'thumb':'THEME09','index':'THEME04','middle':'THEME03','ring':'THEME02','little':'THEME06'}[next(d for d in ['thumb','index','middle','ring','little'] if b.name.startswith(d))]
rig['torch_hand_editor']=True;rig['editor_start_angles']=json.dumps(rest);rig['editor_show_shaft']=True
rig.show_in_front=True;rig.data.display_type='OCTAHEDRAL';rig.data.show_names=False
for d in ('thumb','index','middle','ring','little'):
 for j in range(3):
  key=body.data.shape_keys.key_blocks[f'Joint_{d}_{j}'];key.driver_remove('value');drv=key.driver_add('value').driver;drv.type='SCRIPTED'
  var=drv.variables.new();var.name='a';var.type='SINGLE_PROP';var.targets[0].id=rig;var.targets[0].data_path=f'pose.bones["{d}{j}"].rotation_euler[0]'
  limit=math.radians(([25,35,45] if d=='thumb' else [60,45,45])[j]);drv.expression=f'min(1,max(0,-a/{limit}))'
for o in scene.objects:o.select_set(False)
rig.hide_set(False);rig.select_set(True);bpy.context.view_layer.objects.active=rig
rig.pose.bones['index1'].select=True
rig.data.bones.active=rig.data.bones['index1']
bpy.ops.object.mode_set(mode='POSE')
scene.tool_settings.transform_pivot_point='MEDIAN_POINT';scene.transform_orientation_slots[0].type='LOCAL';scene.unit_settings.system='METRIC';scene.unit_settings.length_unit='CENTIMETERS'
bpy.context.view_layer.update()
center=holder.matrix_world@Vector((0,.062,.013))
# A three-quarter view exposes thumb, pads, shaft and cuff without the torch cage.
direction=(holder.matrix_world.to_3x3()@Vector((.8,-.2,-1))).normalized();quat=(-direction).to_track_quat('-Z','Y')
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   sp=area.spaces.active;sp.show_region_ui=True;sp.shading.type='SOLID';sp.shading.light='STUDIO';sp.shading.color_type='MATERIAL';sp.shading.show_shadows=True;sp.clip_start=.001;sp.clip_end=20
   sp.overlay.show_floor=False;sp.overlay.show_axis_x=False;sp.overlay.show_axis_y=False;sp.region_3d.view_location=center;sp.region_3d.view_distance=.42;sp.region_3d.view_rotation=quat;sp.region_3d.view_perspective='ORTHO'
for im in bpy.data.images:
 if im.source=='FILE' and im.users and not im.packed_file:im.pack()
text=bpy.data.texts.new('먼저_읽어주세요');text.write('왼손 직접 편집 파일. 원본 이름/왼손 구조 유지. N 패널 > 손 편집에서 각 마디 굽힘/엄지 방향을 조절하세요. 자루 표시 버튼으로 가려진 면을 확인하세요. 숫자 0은 원본 기본 자세, 시작 자세 버튼은 이 파일을 준비할 때의 자세입니다. Ctrl+S로 저장. Godot에 자동 반영되지 않습니다. 완료 후 이 blend 파일을 전달하면 게임 적용을 이어갈 수 있습니다.\n')
bpy.context.preferences.filepaths.save_version=1
bpy.ops.wm.save_as_mainfile(filepath=str(out/'왼손_횃불_직접편집.blend'))
print('MANUAL_READY',out/'왼손_횃불_직접편집.blend')
