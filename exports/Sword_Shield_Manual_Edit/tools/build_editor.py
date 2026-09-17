import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.kdtree import KDTree
ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg');OUT=ROOT/'exports/Sword_Shield_Manual_Edit'
r=json.loads((OUT/'current_game_grips.json').read_text())
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
def cv(v):return (C@Vector((*v,1))).to_3d()
def mat(a):return Matrix((*[(*a[i],0) for i in range(3)],(*a[3],1))).transposed()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(OUT/'current_game_grips.glb'))
parts=[o for o in bpy.context.scene.objects if o.type=='MESH']
# Read the retained original vertex groups; do not modify or link the source object.
with bpy.data.libraries.load(str(ROOT/'asset-staging/sword_hold_long_grip_integration/source/model/SwordHold_Static.blend'),link=False) as (a,b):b.objects=['RightHand_Glove']
source=b.objects[0]
def source_world(o):return source_world(o.parent)@o.matrix_parent_inverse@o.matrix_basis if o.parent else o.matrix_basis
xf=C@mat(r['right_source_to_editor'])@C.inverted()@source_world(source)
print('SOURCE_MATRIX', source.matrix_world, source.parent)
right_samples=[]
valid={'wrist'}|{d+str(i) for d in ['thumb','index','middle','ring','little'] for i in range(3)}
for v in source.data.vertices:
 weights={source.vertex_groups[g.group].name:g.weight for g in v.groups if source.vertex_groups[g.group].name in valid and g.weight>1e-6}
 right_samples.append((xf@v.co,weights))
def tree(samples):
 t=KDTree(len(samples))
 for i,(p,w) in enumerate(samples):t.insert(p,i)
 t.balance();return t
rt=tree(right_samples);all_weights={};maxerr=0
for o in parts:
 name=o.name
 if name.startswith('right__') and 'RightHand_Glove' in name:
  samples=right_samples;t=rt
 elif name in r['weights']:
  samples=[(cv(x['p']),x['w']) for x in r['weights'][name]];t=tree(samples)
 else:continue
 rows=[]
 for v in o.data.vertices:
  co=o.matrix_world@v.co;_,index,error=t.find(co);maxerr=max(maxerr,error)
  w={k:v for k,v in samples[index][1].items() if k in valid};total=sum(w.values())
  rows.append({k:v/total for k,v in w.items()} if total>1e-7 else {'wrist':1.0})
 all_weights[name]=rows
 print("COUNTS",name,len(samples),len(o.data.vertices))
 print("MATCH",name,"source",list(samples[0][0]),"dest",list(o.matrix_world@o.data.vertices[0].co),"max",maxerr)
print('WEIGHT_TRANSFER_MAX_ERROR',maxerr)
assert maxerr<0.0001, 'Source correspondence differs from current game mesh'
bpy.data.objects.remove(source,do_unlink=True)
for side in ['right','left']:
 collection=bpy.data.collections.new('오른손_검' if side=='right' else '왼손_방패');bpy.context.scene.collection.children.link(collection)
 assembly=bpy.data.objects.new('검_팔전체_이동' if side=='right' else '방패_팔전체_이동',None);collection.objects.link(assembly);assembly.empty_display_type='CIRCLE';assembly.empty_display_size=.10;assembly['editor_side']=side
 side_parts=[o for o in parts if o.name.startswith(side+'__')]
 samples=[]
 for o in side_parts:
  if o.name in all_weights:samples += [(o.matrix_world@v.co,all_weights[o.name][v.index]) for v in o.data.vertices]
 def center(g,fallback):
  n=sum(w.get(g,0) for p,w in samples)
  return sum((p*w.get(g,0) for p,w in samples),Vector())/n if n>1e-6 else fallback
 def boundary(a,b,fallback):
  n=sum(min(w.get(a,0),w.get(b,0)) for p,w in samples)
  return sum((p*min(w.get(a,0),w.get(b,0)) for p,w in samples),Vector())/n if n>1e-5 else fallback
 wrist=cv(r['sides'][side]['wrist']);elbow=cv(r['sides'][side]['elbow']);shoulder=cv(r['sides'][side]['shoulder'])
 chains={}
 for d in ['thumb','index','middle','ring','little']:
  c0=center(d+'0',wrist);c1=center(d+'1',c0+Vector((0,-.02,0)));c2=center(d+'2',c1+Vector((0,-.02,0)))
  if side=='left':heads=[cv(r['bones'][side+'__'+d+str(i)][3]) for i in range(3)]
  else:heads=[boundary('wrist',d+'0',c0+(c0-c1)*.45),boundary(d+'0',d+'1',(c0+c1)*.5),boundary(d+'1',d+'2',(c1+c2)*.5)]
  tail=c2+(c2-heads[2])*.7
  if (tail-heads[2]).length<.008:tail=heads[2]+(heads[2]-heads[1]).normalized()*.016
  chains[d]=heads+[tail]
 palm=sum((pts[0] for d,pts in chains.items() if d!='thumb'),Vector())/4
 width=(chains['index'][0]-chains['little'][0]).normalized()
 data=bpy.data.armatures.new(side+'_EditBones');rig=bpy.data.objects.new('검_오른손_관절' if side=='right' else '방패_왼손_관절',data);collection.objects.link(rig);rig.parent=assembly
 rig.show_in_front=True;data.display_type='STICK';rig['grip_editor']=True;rig['editor_side']=side
 bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='EDIT')
 def bone(name,head,tail,parent=None):
  b=data.edit_bones.new(name);b.head=head;b.tail=tail
  if (tail-head).length<.005:b.tail=head+Vector((0,0,.015))
  if parent:b.parent=data.edit_bones[parent]
  z=width.cross(b.tail-b.head)
  if z.length>.0001:b.align_roll(z.normalized())
  return b
 bone('upper_arm',shoulder,elbow);bone('forearm',elbow,wrist,'upper_arm');bone('wrist',wrist,palm,'forearm')
 for d,pts in chains.items():
  for i in range(3):bone(d+str(i),pts[i],pts[i+1],'wrist' if i==0 else d+str(i-1))
 bpy.ops.object.mode_set(mode='OBJECT')
 for pb in rig.pose.bones:
  pb.rotation_mode='XYZ';pb.lock_scale=(True,True,True)
  pb.bone.color.palette='THEME04' if side=='right' else 'THEME03'
 for o in side_parts:
  world=o.matrix_world.copy()
  for co in list(o.users_collection):co.objects.unlink(o)
  collection.objects.link(o);o.parent=assembly;o.matrix_world=world;o['editor_side']=side
  modifier=o.modifiers.new('편집 관절','ARMATURE');modifier.object=rig;modifier.use_deform_preserve_volume=True
  groups={name:o.vertex_groups.new(name=name) for name in ['upper_arm','forearm','wrist']+[d+str(i) for d in chains for i in range(3)]}
  if o.name in all_weights:
   o['editor_hand']=True
   for i,weights in enumerate(all_weights[o.name]):
    for name,w in weights.items():groups[name].add([i],w,'REPLACE')
  elif any(t in o.name.lower() for t in ['forearm','upperarm','cuff','sleeve']):
   for v in o.data.vertices:
    co=o.matrix_world@v.co
    # Soft elbow region between the baked upper and lower sleeve segments.
    axis=(shoulder-wrist).normalized();along=(co-elbow).dot(axis);w=max(0,min(1,(along+.035)/.07))
    if 'cuff' in o.name.lower():groups['wrist'].add([v.index],1,'REPLACE')
    else:
     if w>0:groups['upper_arm'].add([v.index],w,'REPLACE')
     if w<1:groups['forearm'].add([v.index],1-w,'REPLACE')
  else:
   o['editor_equipment']=True;o.hide_select=True;groups['wrist'].add(list(range(len(o.data.vertices))),1,'REPLACE')
  for poly in o.data.polygons:poly.use_smooth=True
 # Property ties hand controls to matching assembly and mesh without renamed source bones.
 rig['assembly_name']=assembly.name
 hand=next(o for o in side_parts if 'RightHand_Glove' in o.name or 'ContinuousAnatomicalHand' in o.name)
 rig['hand_mesh']=hand.name
 rig['glove_mesh']=next((o.name for o in side_parts if 'FingerlessLeatherGlove' in o.name),hand.name)
scene=bpy.context.scene;scene.name='검_방패_양손_직접편집';scene.unit_settings.system='METRIC';scene.unit_settings.length_unit='CENTIMETERS'
scene['editor_side']='right';scene['source_note']='현재 Godot 기본 자세에서 추출. 별도 편집 사본. 게임에는 자동 반영되지 않음.'
scene.world=bpy.data.worlds.new('편집 배경');scene.world.color=(.07,.07,.07)
for im in bpy.data.images:
 if im.source=='FILE' and im.users and not im.packed_file:im.pack()
# Camera is a saved game-view guide, not a constraint on editing.
data=bpy.data.cameras.new('게임_시점');cam=bpy.data.objects.new('게임_시점',data);scene.collection.objects.link(cam);cam.rotation_euler=(math.pi/2,0,0);data.lens=28;scene.camera=cam;cam.hide_set(True)
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   sp=area.spaces.active;sp.shading.type='MATERIAL';sp.overlay.show_floor=False;sp.region_3d.view_location=Vector((0,.60,-.16));sp.region_3d.view_distance=1.4;sp.region_3d.view_rotation=Vector((0,-1,.22)).to_track_quat('Z','Y');sp.region_3d.view_perspective='PERSP';sp.show_region_ui=True
readme='''검·방패 양손 편집 파일입니다. N 패널 → 양손 편집에서 오른손/왼손을 선택하세요.
손가락: 각 마디 회전을 드래그. 손등/손목: 손목 회전. 팔: 위팔과 팔뚝 회전 또는 팔 전체 선택 후 G/R.
손등 표면: 손등 형태 편집 버튼 → 정점 선택 → O 비례 편집 → G 이동, 휠로 범위 조절. Tab으로 마침.
장비는 기본적으로 손을 따라 움직입니다. 장비 고정 버튼으로 검/방패를 고정한 뒤 손만 맞출 수 있습니다.
Ctrl+Z 실행 취소, 시작 자세 복원, Ctrl+S 저장. 현재 게임 원본은 바뀌지 않습니다.
검 쪽은 기존 굳어진 파지에 편집용 관절을 새로 붙였으므로 과한 굽힘은 피하고 자루 관통을 확인하세요.
'''
text=bpy.data.texts.new('먼저_읽어주세요');text.write(readme);(OUT/'사용방법.md').write_text(readme)
ui=bpy.data.texts.new('양손_편집_패널.py');ui.write((OUT/'editor_ui.py').read_text())
bpy.ops.object.select_all(action='DESELECT');rig=bpy.data.objects['검_오른손_관절'];rig.select_set(True);bpy.context.view_layer.objects.active=rig;bpy.ops.object.mode_set(mode='POSE');rig.data.bones.active=rig.data.bones['index1'];rig.pose.bones['index1'].select=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'검_방패_양손_직접편집.blend'))
(OUT/'build_report.json').write_text(json.dumps({'weight_transfer_max_error_m':maxerr,'meshes':len(parts),'rigs':2,'bones_per_rig':18,'source_game_pose':'idle'},indent=2))
print('EDITOR BUILD PASS')
