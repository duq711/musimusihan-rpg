"""Evaluate candidate and fresh GLB skin surfaces at all 187 original sample times."""
import bpy, json, struct, hashlib, math
from pathlib import Path
import numpy as np
from mathutils import Matrix, Vector, Quaternion
from mathutils.kdtree import KDTree

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/iteration_07';VERIFY=OUT/'verification';VERIFY.mkdir(exist_ok=True)
BLEND=OUT/'Overhead_Review.blend';GLB=OUT/'Overhead_Review.glb';SIDECAR=OUT/'arm_pose_samples.json'
SOURCE=ROOT.parents[1]/'work/game-project/RPG_Workspace/godot-game/assets/3d/player/sword_shield/round_shield.glb'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();before={str(p):sha(p) for p in [BLEND,GLB,SIDECAR,SOURCE]}
meshes=['RightArm_ContinuousSleeve_Surface','RightArm_Forearm_Surface','RightArm_WristCuff_Surface']
bones=['SleeveHand','SleeveWrist','SleeveForearm','SleeveElbow25','SleeveElbow50','SleeveElbow75','SleeveUpper']
markers=['RearGrip','RearGripTop','RearGripBottom','RearArmStrap']
C=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)));CI=C.inverted();Q=Matrix.Diagonal((-1,1,-1,1))
def doc(p):
    b=p.read_bytes();return json.loads(b[20:20+struct.unpack_from('<I',b,12)[0]])
def mat(n):
    if 'matrix' in n:return Matrix([n['matrix'][i::4] for i in range(4)])
    q=n.get('rotation',[0,0,0,1]);return Matrix.LocRotScale(Vector(n.get('translation',[0,0,0])),Quaternion((q[3],*q[:3])),Vector(n.get('scale',[1,1,1])))
def cumulative(d,i):
    parents={child:j for j,n in enumerate(d['nodes']) for child in n.get('children',[])};m=mat(d['nodes'][i])
    while i in parents:i=parents[i];m=mat(d['nodes'][i])@m
    return m
def err(a,b):return float(np.max(np.abs(np.array(a)-np.array(b))))
def verts(mesh,M):
    a=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',a);a=a.reshape(-1,3).astype(np.float64)
    m=np.array(M);return a@m[:3,:3].T+m[:3,3]
def evaluated_points(o,deps):
    e=o.evaluated_get(deps);mesh=e.to_mesh();v=verts(mesh,CI@e.matrix_world);e.to_mesh_clear();return v
def bone_deformations(arm,deps):
    a=arm.evaluated_get(deps);return {n:np.array(CI@a.matrix_world@a.pose.bones[n].matrix@a.data.bones[n].matrix_local.inverted()@a.matrix_world.inverted()@C) for n in bones}
def pose(row):
    q=row['rotation_xyzw'];return Matrix.Translation(Vector(row['position']))@Quaternion((q[3],*q[:3])).to_matrix().to_4x4()

d=doc(GLB);source=doc(SOURCE);original_markers={n:cumulative(source,next(i for i,v in enumerate(source['nodes']) if v.get('name')==n)) for n in markers}
skin_nodes={n['name']:n['skin'] for n in d['nodes'] if 'skin' in n};assert set(skin_nodes)==set(meshes),skin_nodes
assert len(d['skins'])==1 and len(d['skins'][0]['joints'])==7
joint_names=[d['nodes'][i]['name'] for i in d['skins'][0]['joints']];assert set(joint_names)==set(bones)
channels={n:[] for n in bones}
assert len(d['animations'])==1 and d['animations'][0]['name']=='overhead'
for ch in d['animations'][0]['channels']:
    n=d['nodes'][ch['target']['node']]['name']
    if n in channels:channels[n].append(ch['target']['path'])
assert all('translation' in p and 'rotation' in p for p in channels.values())
side=json.loads(SIDECAR.read_text());assert len(side['frames'])==187
bpy.ops.wm.open_mainfile(filepath=str(BLEND),load_ui=False,use_scripts=False);s=bpy.context.scene
objects={n:bpy.data.objects[n] for n in meshes};arm=bpy.data.objects['SleeveSurfaceRig']
assert len(arm.data.bones)==7 and all(b.parent is None for b in arm.data.bones)
source_bones={n:{'parent':arm.data.bones[n].parent.name if arm.data.bones[n].parent else None,'bind_matrix_rows':[list(r) for r in arm.data.bones[n].matrix_local]} for n in bones}
source_bind={n:verts(o.data,CI@o.matrix_world) for n,o in objects.items()}
source_counts={n:len(a) for n,a in source_bind.items()}
source_skin={n:sum(1 for m in o.modifiers if m.type=='ARMATURE' and m.object==arm) for n,o in objects.items()};assert all(v==1 for v in source_skin.values())
deps=bpy.context.evaluated_depsgraph_get();snap=[];source_bone_frames=[]
for i in range(187):
    s.frame_set(i);bpy.context.view_layer.update();snap.append({n:evaluated_points(o,deps) for n,o in objects.items()});source_bone_frames.append(bone_deformations(arm,deps))
print('SOURCE_SKIN_SNAPSHOT_COMPLETE',flush=True)
bpy.ops.wm.read_factory_settings(use_empty=True);s=bpy.context.scene;s.render.fps=120
bpy.ops.import_scene.gltf(filepath=str(GLB));bpy.context.view_layer.update()
objects={n:bpy.data.objects[n] for n in meshes};arms=[o for o in s.objects if o.type=='ARMATURE'];assert len(arms)==1;arm=arms[0]
assert len(arm.data.bones)==7 and all(b.parent is None for b in arm.data.bones)
assert all(n in bpy.data.objects for n in markers)
imported_skin={n:sum(1 for m in o.modifiers if m.type=='ARMATURE' and m.object==arm) for n,o in objects.items()};assert all(v==1 for v in imported_skin.values())
mapping={};mapping_report={};imported_bind={n:verts(o.data,CI@o.matrix_world) for n,o in objects.items()}
for n in meshes:
    a=source_bind[n];b=imported_bind[n];ta=KDTree(len(a));tb=KDTree(len(b))
    for i,v in enumerate(a):ta.insert(Vector(v),i)
    for i,v in enumerate(b):tb.insert(Vector(v),i)
    ta.balance();tb.balance();ab=[tb.find(Vector(v)) for v in a];ba=[ta.find(Vector(v)) for v in b]
    mapping[n]={'source_to_import':np.array([r[1] for r in ab]),'import_to_source':np.array([r[1] for r in ba])}
    distance=max(max(r[2] for r in ab),max(r[2] for r in ba))
    mapping_report[n]={'source_vertices':len(a),'imported_vertices':len(b),'bind_geometry_bidirectional_max_error_m':distance,
      'correspondence':'Bidirectional nearest source/import bind positions; UV seam duplicates allowed. Both directions are compared after actual skin evaluation at every frame.'}
    assert distance<3e-5,(n,distance)
deps=bpy.context.evaluated_depsgraph_get();frames=[];max_mesh={n:0. for n in meshes};max_bone={n:0. for n in bones};max_marker=0
for i,row in enumerate(side['frames']):
    s.frame_set(i);bpy.context.view_layer.update();evaluated={n:evaluated_points(o,deps) for n,o in objects.items()};bone_now=bone_deformations(arm,deps)
    mesh_errors={};bone_errors={}
    for n in meshes:
        a=snap[i][n];b=evaluated[n];m=mapping[n]
        error=max(float(np.linalg.norm(a-b[m['source_to_import']],axis=1).max()),float(np.linalg.norm(b-a[m['import_to_source']],axis=1).max()))
        mesh_errors[n]=error;max_mesh[n]=max(max_mesh[n],error)
    for n in bones:
        error=err(bone_now[n],source_bone_frames[i][n]);bone_errors[n]=error;max_bone[n]=max(max_bone[n],error)
    marker_errors={};T=pose(row['shield'])
    for n in markers:
        actual=CI@bpy.data.objects[n].evaluated_get(deps).matrix_world@C;expected=T@Q@original_markers[n]
        e=err(actual,expected);marker_errors[n]=e;max_marker=max(max_marker,e)
    frames.append({'index':i,'time_seconds':row['time_seconds'],'skinned_vertex_max_error_m':mesh_errors,'bone_deformation_matrix_max_error':bone_errors,'shield_marker_full_matrix_error':marker_errors})
checks={'single_skin_seven_animated_bones':True,'all_three_meshes_reimport_as_skinned':all(v==1 for v in imported_skin.values()),'bone_hierarchy_unparented':all(b.parent is None for b in arm.data.bones),
 'all_187_evaluated_surface_samples_match':max(max_mesh.values())<3e-5,'all_187_bone_deformations_match':max(max_bone.values())<3e-5,
 'all_shield_marker_matrices_match':max_marker<3e-5,'all_inputs_unchanged':before=={p:sha(Path(p)) for p in before}}
report={'status':'pass' if all(checks.values()) else 'failed','iteration':'iteration_07','blender_version':bpy.app.version_string,
 'method':'Separate actual dependency-graph skin evaluations of saved blend and freshly imported GLB at all 187 original 120Hz sample times. Compare every evaluated vertex in both directions using bind-position correspondence, and compare bind-corrected bone deformation matrices.',
 'sample_count':187,'skin_count':len(d['skins']),'joint_count':len(d['skins'][0]['joints']),'skin_mesh_nodes':skin_nodes,
 'bone_animation_channels':channels,'source_bone_bind_data':source_bones,'mesh_mapping':mapping_report,'max_surface_error_m':max_mesh,
 'max_bone_deformation_matrix_error':max_bone,'max_shield_marker_matrix_error':max_marker,'checks':checks,'input_sha256':before,
 'limits':['Numerical skin/export preservation only; does not approve visible skin folds, silhouette, wrist junction, or artistic anatomy.',
  'These surfaces require the delivered skin/bind/action. Applying only right_arm.parts_camera discards sleeve deformation.','No Godot runtime/shader execution.'],'frames':frames}
(VERIFY/'skinned_surface_reimport.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
summary={k:v for k,v in report.items() if k!='frames'};summary['full_report_sha256']=sha(VERIFY/'skinned_surface_reimport.json')
(VERIFY/'skinned_surface_summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print('SKIN_REIMPORT_RESULT '+json.dumps(summary));assert all(checks.values()),checks
