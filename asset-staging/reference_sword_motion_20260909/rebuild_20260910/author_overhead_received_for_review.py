"""Independent joint-controlled overhead review. Never writes input models."""
import bpy, json, math, hashlib, sys
from pathlib import Path
import numpy as np
from mathutils import Matrix, Vector, Quaternion

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'output'/sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else ROOT/'output/iteration_01'
OUT.mkdir(parents=True,exist_ok=True)
if (OUT/'Overhead_Review.blend').exists(): raise RuntimeError('Existing iteration is immutable')
BASE=ROOT.parent
SRC=BASE/'sword_hold_long_grip/model/SwordHold_Static.glb'
SRC_BLEND=BASE/'sword_hold_long_grip/model/SwordHold_Static.blend'
POSE=json.loads((ROOT/'pose_fit_proposal.json').read_text())
S=Matrix(POSE['canonical_source_ready_rows']); SI=S.inverted()
W0,E0,H0=[Vector(POSE[k]) for k in ['W0','E0','H0']]
G=Vector((0,-.108,.002))
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1))); CI=C.inverted()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
before={str(p):sha(p) for p in [SRC,SRC_BLEND]}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SRC))
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH']
assert len(meshes)==11
canonical={o.name:SI@CI@o.matrix_world for o in meshes}
original_points={o.name:[CI@o.matrix_world@v.co for v in o.data.vertices] for o in meshes}
for o in meshes:
    o.data=o.data.copy(); o.data.transform(canonical[o.name]); o.parent=None
    o.matrix_world=Matrix.Identity(4)
for o in list(scene.objects):
    if o not in meshes:bpy.data.objects.remove(o,do_unlink=True)
roundtrip=max((S@v.co-original_points[o.name][i]).length for o in meshes for i,v in enumerate(o.data.vertices))
assert roundtrip<3e-5,roundtrip

def empty(name,parent=None):
    o=bpy.data.objects.new(name,None); scene.collection.objects.link(o)
    o.parent=parent; o.matrix_parent_inverse=Matrix.Identity(4)
    o.empty_display_type='SPHERE';o.empty_display_size=.015
    o.rotation_mode='QUATERNION';return o
root=empty('CameraSpace');root.matrix_world=C
names=['SwordGrip','ShieldGrip','Shoulder_R','Elbow_R','Wrist_R','Forearm_R','UpperArm_R','WristCuff_R']
ctrl={n:empty(n,root) for n in names}
roles={'RightArm_Forearm_Surface':'Forearm_R','RightArm_UpperArm_Surface':'UpperArm_R','RightArm_WristCuff_Surface':'WristCuff_R'}
for o in meshes:
    o.parent=ctrl[roles.get(o.name,'SwordGrip')];o.matrix_parent_inverse=Matrix.Identity(4);o.matrix_basis=Matrix.Identity(4)
    o['source_mesh_name']=o.name;o['geometry_space']='canonical_source_ready_inverse'
markers={}
for role in ['sword','glove']:
    m=empty('GripAudit_'+role,ctrl['SwordGrip']);m.location=G;markers[role]=m
# Markers are independent children with the canonical shared contact coordinate;
# the actual mesh/control matrices are sampled in addition below.

def fit(a0,b0,a1,b1):
    u=(b0-a0).normalized();v=(b1-a1).normalized();k=(b1-a1).length/(b0-a0).length
    q=u.rotation_difference(v);K=Matrix.Identity(3)
    for r in range(3):
        for c in range(3):K[r][c]+=(k-1)*u[r]*u[c]
    B=q.to_matrix()@K;M=B.to_4x4();M.translation=a1-B@a0;return M

def gram(M):
    x=Vector(M.col[0][:3]).normalized(); y=Vector(M.col[1][:3]);y=(y-x*x.dot(y)).normalized()
    z=Vector(M.col[2][:3]);z=(z-x*x.dot(z)-y*y.dot(z)).normalized()
    return Matrix((x,y,z)).transposed()

def matrix_pose(p,q):
    return Matrix.Translation(Vector(p))@Quaternion((q[3],q[0],q[1],q[2])).to_matrix().to_4x4()
def transform_json(M):
    q=M.to_quaternion().normalized()
    return {'position':list(M.translation),'rotation_xyzw':[q.x,q.y,q.z,q.w]}
def part_json(M):
    return {'basis_columns':[list(M.col[i][:3]) for i in range(3)],'position':list(M.translation)}

# A review-only shield disk represents the observed rim. It does not claim the
# received production shield's geometry or normalization; see metadata.
# Production normalization is resolved in a separate evidence file.
shield=ctrl['ShieldGrip']
shield_mat=bpy.data.materials.new('Shield review proxy');shield_mat.diffuse_color=(.09,.115,.15,1)
verts=[(0,0,0)]+[(.32*math.cos(i*2*math.pi/64),.32*math.sin(i*2*math.pi/64),0) for i in range(64)]
faces=[(0,i+1,(i+1)%64+1) for i in range(64)]
me=bpy.data.meshes.new('ReviewShieldDisk');me.from_pydata(verts,[],faces);me.materials.append(shield_mat)
disk=bpy.data.objects.new('Shield_Review_Proxy',me);scene.collection.objects.link(disk);disk.parent=shield
disk['review_proxy']=True

SHIELD_KEYS=[(0,.121,.785),(2,.133,.812),(4,.167,.861),(7,.219,.929),(12,.23,1.12),(34,.23,1.15),(46,.15,1.12),(70,.103,.824),(78,.131,.767),(85,.145,.801),(93,.141,.785)]
def shield_pose(t):
    fr=t*60
    # Linear interpolation of source rim observations, 0.32 m proxy radius.
    a,b=SHIELD_KEYS[0],SHIELD_KEYS[-1]
    for j in range(len(SHIELD_KEYS)-1):
        if SHIELD_KEYS[j][0]<=fr<=SHIELD_KEYS[j+1][0]:a,b=SHIELD_KEYS[j:j+2];break
    u=(fr-a[0])/max(1,b[0]-a[0]);sx=a[1]*(1-u)+b[1]*u;sy=a[2]*(1-u)+b[2]*u
    d=.55;tan=math.tan(math.radians(38))
    p=Vector(((sx-.5)*2*d*tan*16/9,(.5-sy)*2*d*tan-.32,-d))
    return Matrix.Translation(p)

samples=[];previous={}
for row in POSE['frames']:
    T=matrix_pose(row['position'],row['rotation_xyzw']);H=Vector(row['shoulder']);E=Vector(row['elbow']);W=T@W0
    h=T.inverted()@H;e=T.inverted()@E
    FF=fit(W0,E0,W0,e);FU=fit(E0,H0,e,h);Q=gram(FF.to_3x3())
    FC=Q.to_4x4();FC.translation=W0-Q@W0
    mats={'SwordGrip':T,'ShieldGrip':shield_pose(row['time_seconds']),
          'Shoulder_R':Matrix.Translation(H),'Elbow_R':Matrix.Translation(E),'Wrist_R':Matrix.Translation(W),
          'Forearm_R':T@FF,'UpperArm_R':T@FU,'WristCuff_R':T@FC}
    vals={}
    for name,M in mats.items():
        loc,q,scale=M.decompose()
        if name in previous and q.dot(previous[name])<0:q.negate()
        previous[name]=q.copy(); vals[name]={'location':list(loc),'rotation_quaternion':list(q),'scale':list(scale)}
    samples.append({'time_seconds':row['time_seconds'],'values':vals})

scene.render.fps=120;scene.frame_start=1;scene.frame_end=187
action=bpy.data.actions.new('overhead');action.use_fake_user=True
layer=action.layers.new('Independent right arm surface controls');strip=layer.strips.new(type='KEYFRAME')
slotmap={}
for name,o in ctrl.items():
    slot=action.slots.new('OBJECT',name);bag=strip.channelbags.new(slot);slotmap[name]=slot
    for prop,count in [('location',3),('rotation_quaternion',4),('scale',3)]:
        for axis in range(count):
            fc=bag.fcurves.new(data_path=prop,index=axis);fc.keyframe_points.add(len(samples))
            fc.keyframe_points.foreach_set('co',[v for r in samples for v in (1+r['time_seconds']*120,r['values'][name][prop][axis])])
            for k in fc.keyframe_points:k.interpolation='LINEAR'
    o.animation_data_create();o.animation_data.action=action;o.animation_data.action_slot=slot
action.use_frame_range=True;action.frame_start=1;action.frame_end=187

camdata=bpy.data.cameras.new('GameCamera76');cam=bpy.data.objects.new('GameCamera76',camdata);scene.collection.objects.link(cam)
cam.matrix_world=C;camdata.sensor_fit='VERTICAL';camdata.sensor_height=32;camdata.lens=16/math.tan(math.radians(38));camdata.clip_start=.025;camdata.clip_end=50;scene.camera=cam
scene.render.resolution_x=960;scene.render.resolution_y=540;scene.render.resolution_percentage=100
world=bpy.data.worlds.new('Neutral reference review');world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.12,.16,.22,1);world.node_tree.nodes['Background'].inputs[1].default_value=.6;scene.world=world
for name,p,power,size in [('Key',(-1.5,2,-1),110,2),('Fill',(2,.7,-1.5),85,2),('Rim',(0,2,.5),130,2)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size
    o=bpy.data.objects.new(name,data);scene.collection.objects.link(o);o.location=C@Vector(p)
    o.rotation_euler=((C@Vector((.1,0,-.3)))-o.location).to_track_quat('-Z','Y').to_euler()
scene.view_settings.view_transform='AgX'
scene['review_only']=True;scene['coordinate_space']='godot_camera_local_x_right_y_up_minus_z_forward'
scene['rig_type']='independently_keyed_joint_and_surface_controls_no_skin'
scene['source_ready_roundtrip_max_m']=roundtrip
scene['source_fov_unknown']=True
frames=[];deps=bpy.context.evaluated_depsgraph_get()
for idx in range(187):
    scene.frame_set(idx+1);bpy.context.view_layer.update()
    M={n:CI@o.evaluated_get(deps).matrix_world for n,o in ctrl.items()}
    endpoint={
      'wrist':(M['Forearm_R']@W0-M['SwordGrip']@W0).length,
      'elbow_forearm':(M['Forearm_R']@E0-M['Elbow_R'].translation).length,
      'elbow_upper':(M['UpperArm_R']@E0-M['Elbow_R'].translation).length,
      'shoulder':(M['UpperArm_R']@H0-M['Shoulder_R'].translation).length,
      'cuff_wrist':(M['WristCuff_R']@W0-M['SwordGrip']@W0).length}
    grip={role:list(CI@markers[role].evaluated_get(deps).matrix_world.translation) for role in markers}
    # Also evaluate each actual retained sword/glove object and compare its shared
    # canonical contact point. Its vertices remain attached to the same matrix.
    meshgrip={name:list(CI@bpy.data.objects[name].evaluated_get(deps).matrix_world@G) for name in ['RightHand_Glove','Sword_GripLeather']}
    frames.append({'time_seconds':idx/120,'source_time_seconds':1040/60+idx/120,
      'sword':transform_json(M['SwordGrip']),'shield':transform_json(M['ShieldGrip']),
      'right_arm':{'shoulder':list(M['Shoulder_R'].translation),'elbow':list(M['Elbow_R'].translation),
        'wrist':list(M['Wrist_R'].translation),'parts_camera':{'forearm':part_json(M['Forearm_R']),'upper_arm':part_json(M['UpperArm_R']),'cuff':part_json(M['WristCuff_R'])}},
      'endpoint_error_m':endpoint,'evaluated_grip_camera':{'sword':meshgrip['Sword_GripLeather'],'glove':meshgrip['RightHand_Glove']}})
max_endpoint=max(v for f in frames for v in f['endpoint_error_m'].values())
assert max_endpoint<3e-5,max_endpoint
sidecar={'schema_version':1,'status':'authored_windows_output','review_only':True,'clip_id':'overhead',
 'coordinate_space':'godot_camera_local_x_right_y_up_minus_z_forward','geometry_space':'canonical_source_ready_inverse',
 'seconds_basis':'original_authored_clip_seconds','sample_hz':120,'duration_seconds':1.55,
 'frames':frames,'camera':{'vertical_fov_degrees':76,'aspect_ratio':[16,9],'near_m':.025,'source_fov_known':False},
 'rig':{'type':'independent_joint_and_surface_controls','skin_count':0,'controls':names,'parent':'CameraSpace','extra_twist':False},
 'shield_normalization_status':'review_proxy_camera_absolute_pending_production_basis',
 'source_hashes':before,'source_ready_roundtrip_max_m':roundtrip,'max_endpoint_error_m':max_endpoint,
 'contact_checkpoint':{'time_seconds':42/60,'source_time_seconds':18+2/60,'meaning':'authored review checkpoint, not measured impact event'}}
(OUT/'arm_pose_samples.json').write_text(json.dumps(sidecar,separators=(',',':')),encoding='utf-8')
(OUT/'raw_evaluated_control_samples.json').write_text(json.dumps(samples,separators=(',',':')),encoding='utf-8')
scene.frame_set(1);bpy.context.view_layer.update()
for image in bpy.data.images:
    if image.source not in ['VIEWER','GENERATED'] and not image.packed_file:image.pack()
# Export exactly one layered Action via the supported ACTIONS path.
for name,o in ctrl.items():
    track=o.animation_data.nla_tracks.new();track.name='overhead';track.mute=True
    nla=track.strips.new('overhead',1,action);nla.action_slot=slotmap[name]
    nla.action_frame_start=1;nla.action_frame_end=187;nla.extrapolation='NOTHING'
    o.animation_data.action=None
bpy.ops.object.select_all(action='DESELECT')
for o in [root,*ctrl.values(),*meshes,disk]:o.select_set(True)
bpy.context.view_layer.objects.active=ctrl['SwordGrip']
bpy.ops.export_scene.gltf(filepath=str(OUT/'Overhead_Review.glb'),export_format='GLB',use_selection=True,
 export_animations=True,export_animation_mode='ACTIONS',export_merge_animation='ACTION',
 export_frame_range=False,export_force_sampling=False,export_optimize_animation_size=False,
 export_anim_slide_to_zero=True,export_skins=False,export_cameras=False,export_lights=False,export_extras=True,export_yup=True)
for name,o in ctrl.items():o.animation_data.action=action;o.animation_data.action_slot=slotmap[name]
scene.frame_set(1);bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Overhead_Review.blend'),compress=True)
assert before=={str(p):sha(p) for p in [SRC,SRC_BLEND]}
report={'status':'authored_windows_review_output','blender_version':bpy.app.version_string,'frame_samples':187,
 'duration_seconds':1.55,'rig_type':scene['rig_type'],'source_preserved':True,'source_hashes':before,
 'normalization_roundtrip_error_m':roundtrip,'max_endpoint_error_m':max_endpoint,
 'visual_review':'pending rendered silhouette check','shield':'review proxy; production normalization pending',
 'artifacts':{p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in [OUT/'Overhead_Review.blend',OUT/'Overhead_Review.glb',OUT/'arm_pose_samples.json']}}
(OUT/'authoring_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('AUTHOR_DONE '+json.dumps(report))

