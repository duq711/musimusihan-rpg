"""Finish the approved i4 motion, preserving all existing evaluated transforms."""
import bpy,bmesh,json,math,hashlib,sys,shutil
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parent
SRC=ROOT/'output/iteration_04'
OUT=ROOT/'output'/(sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'iteration_05')
OUT.mkdir(parents=True,exist_ok=True)
SKIN='--skin' in sys.argv
if (OUT/'Overhead_Review.blend').exists():raise RuntimeError('Iteration already exists')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
protected={str(p):sha(p) for p in [SRC/'Overhead_Review.blend',SRC/'Overhead_Review.glb',SRC/'arm_pose_samples.json']}
bpy.ops.wm.open_mainfile(filepath=str(SRC/'Overhead_Review.blend'),load_ui=False,use_scripts=False)
s=bpy.context.scene;s.frame_set(0);bpy.context.view_layer.update()
root=bpy.data.objects['CameraSpace'];C=root.matrix_world.copy();CI=C.inverted()
data=json.loads((SRC/'arm_pose_samples.json').read_text())
proposal=json.loads((ROOT/'pose_fit_proposal.json').read_text())
W,E,H=[Vector(proposal[k]) for k in ['W0','E0','H0']]
report={'status':'surface_finish_candidate','motion_source':'iteration_04','motion_unchanged':True,'modifications':[]}
new_objects=[]

def boundary_groups(bm):
    left=set(v for e in bm.edges if e.is_boundary for v in e.verts);groups=[]
    while left:
        group=set();todo=[left.pop()]
        while todo:
            v=todo.pop();group.add(v)
            for e in v.link_edges:
                if not e.is_boundary:continue
                v2=e.other_vert(v)
                if v2 in left:left.remove(v2);todo.append(v2)
        groups.append(group)
    return groups

# Finish the open sleeve ends on copied mesh data, keeping original exterior faces.
# UV seam duplication is welded only on the three arm meshes, never sword/glove.
end_loops={}
for name in ['RightArm_Forearm_Surface','RightArm_UpperArm_Surface','RightArm_WristCuff_Surface']:
    o=bpy.data.objects[name];o.data=o.data.copy();bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
    groups=boundary_groups(bm)
    end_loops[name]=[[v.co.copy() for v in group] for group in groups if len(group)>20]
    edge_count=sum(e.is_boundary for e in bm.edges)
    filled=bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)['faces']
    for face in filled:face.material_index=0;face.smooth=False
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    remaining=sum(e.is_boundary for e in bm.edges)
    bm.to_mesh(o.data);bm.free();o.data.update()
    assert remaining==0,(name,remaining)
    report['modifications'].append({'mesh':name,'boundary_edges_before':edge_count,'boundary_edges_after':remaining,'finish':'sealed sleeve and strap ends; original exterior retained'})

# A leather articulation insert encloses both real elbow end loops. Its radius is
# calculated from the actual aperture vertices, not from the centerline alone.
def center(points):return sum(points,Vector())/len(points)
fore_end=min(end_loops['RightArm_Forearm_Surface'],key=lambda p:(center(p)-E).length)
upper_end=min(end_loops['RightArm_UpperArm_Surface'],key=lambda p:(center(p)-E).length)
elbow_radius=max((v-E).length for loop in [fore_end,upper_end] for v in loop)+.0015
cuff_end=min(end_loops['RightArm_WristCuff_Surface'],key=lambda p:(center(p)-W).length)
wrist_radius=max((v-W).length for v in cuff_end)+.001
leather=bpy.data.objects['RightArm_UpperArm_Surface'].data.materials[0]
def insert(name,parent,radius,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64,ring_count=32,radius=radius)
    o=bpy.context.object;o.name=name;o.parent=bpy.data.objects[parent]
    o.matrix_parent_inverse=Matrix.Identity(4);o.matrix_basis=Matrix.Identity(4)
    o.data.materials.append(mat)
    for p in o.data.polygons:p.use_smooth=True
    o['purpose']='closed leather joint insert; independent rigid translation with exact joint center'
    o['radius_m']=radius;new_objects.append(o);return o
elbow=insert('RightArm_Elbow_LeatherGusset','Elbow_R',elbow_radius,leather)
wrist=insert('RightArm_Wrist_UnderCuff','Wrist_R',wrist_radius,bpy.data.objects['RightArm_WristCuff_Surface'].data.materials[0])
report['modifications'] += [{'mesh':elbow.name,'radius_m':elbow_radius,'finish':'closed leather insert enclosing both sleeve end apertures'}, {'mesh':wrist.name,'radius_m':wrist_radius,'finish':'closed leather under-cuff enclosing wrist sleeve aperture'}]

# Restore exact supplied shield grip markers. Q is applied once to model geometry
# and marker coordinates, while ShieldGrip retains the reviewed absolute T.
shield_source=Path(data['shield_source']['path']);before=set(s.objects)
bpy.ops.import_scene.gltf(filepath=str(shield_source));bpy.context.view_layer.update()
imported=[o for o in s.objects if o not in before]
marker_names=['RearGrip','RearGripTop','RearGripBottom','RearArmStrap']
Q=Matrix.Rotation(math.pi,4,'Y');marker_report=[]
marker_transforms={name:Q@CI@next(o for o in imported if o.name==name).matrix_world for name in marker_names}
for o in imported:bpy.data.objects.remove(o,do_unlink=True)
for name,M in marker_transforms.items():
    o=bpy.data.objects.new(name,None);s.collection.objects.link(o);o.parent=bpy.data.objects['ShieldGrip']
    o.matrix_parent_inverse=Matrix.Identity(4);o.matrix_basis=M;o.empty_display_type='SPHERE';o.empty_display_size=.008
    o['source_asset']=str(shield_source);o['model_y_pi_applied_once']=True
    new_objects.append(o);marker_report.append({'name':name,'shield_pivot_local_matrix':[list(r) for r in M]})
report['shield_markers']=marker_report

# Prove the accepted animation and the actual aperture coverage across all samples.
deps=bpy.context.evaluated_depsgraph_get();maximum_delta=0.;minimum_clearance=1.;worst=None
from mathutils import Quaternion
def trs(v):
    x,y,z,w=v['rotation_xyzw'];return Matrix.Translation(Vector(v['position']))@Quaternion((w,x,y,z)).to_matrix().to_4x4()
def part(v):
    M=Matrix.Identity(4)
    for i,col in enumerate(v['basis_columns']):M.col[i]=(*col,0)
    M.translation=Vector(v['position']);return M
for index,row in enumerate(data['frames']):
    s.frame_set(index);bpy.context.view_layer.update()
    values={'SwordGrip':trs(row['sword']),'ShieldGrip':trs(row['shield'])}
    for n,k in [('Shoulder_R','shoulder'),('Elbow_R','elbow'),('Wrist_R','wrist')]:values[n]=Matrix.Translation(Vector(row['right_arm'][k]))
    for n,k in [('Forearm_R','forearm'),('UpperArm_R','upper_arm'),('WristCuff_R','cuff')]:values[n]=part(row['right_arm']['parts_camera'][k])
    actual={n:CI@bpy.data.objects[n].evaluated_get(deps).matrix_world for n in values}
    maximum_delta=max(maximum_delta,max(abs(actual[n][r][c]-values[n][r][c]) for n in values for r in range(4) for c in range(4)))
    for name,loop,joint,radius in [('Forearm_R',fore_end,'elbow',elbow_radius),('UpperArm_R',upper_end,'elbow',elbow_radius),('WristCuff_R',cuff_end,'wrist',wrist_radius)]:
        joint_pos=Vector(row['right_arm'][joint])
        clearance=radius-max((actual[name]@v-joint_pos).length for v in loop)
        if clearance<minimum_clearance:minimum_clearance=clearance;worst={'sample':index,'part':name}
assert maximum_delta<3e-5,maximum_delta
assert minimum_clearance>.0005,(minimum_clearance,worst)
report['motion_validation']={'sample_count':187,'sample_hz':120,'max_matrix_delta_from_i4':maximum_delta}
report['surface_coverage']={'sample_count':187,'minimum_aperture_inside_insert_clearance_m':minimum_clearance,'worst':worst,'note':'Analytical enclosing volume check; visual review separately required'}

armature=None
if SKIN:
    sys.path.insert(0,str(ROOT))
    from continuous_sleeve import build
    armature,sleeve,skin_report=build(s,root,W,E,H,{n:bpy.data.objects[n] for n in data['rig']['controls']},data['frames'])
    new_objects=[bpy.data.objects[n] for n in marker_names]
    new_objects.extend([armature,sleeve])
    report['skin_finish']=skin_report
    report['surface_coverage']={'status':'continuous_closed_skin_replaces_the_trial_spheres','note':'Sphere aperture clearance does not apply to this skin; topology and rendered skin checked separately'}

s.frame_set(0);bpy.context.view_layer.update()
data['review_only']=False;data['status']='authored_windows_surface_finished_output'
data['surface_finish']={'source_iteration':'iteration_04','method':'continuous_sleeve_skin' if SKIN else 'closed_rigid_inserts','shield_markers':marker_names}
if SKIN:data['surface_finish'].update(skin_report);data['rig']['skin_count']=1
data['shield_normalization_status']='verified_mac_idle_matrix_match_in_iteration_04_independent_report'
(OUT/'arm_pose_samples.json').write_text(json.dumps(data,separators=(',',':')),encoding='utf-8')
shutil.copyfile(SRC/'raw_evaluated_control_samples.json',OUT/'raw_evaluated_control_samples.json')
ctrl=[bpy.data.objects[n] for n in data['rig']['controls']]
if armature:ctrl.append(armature)
actions={o.name:(o.animation_data.action,o.animation_data.action_slot) for o in ctrl}
for o in ctrl:o.animation_data.action=None
bpy.ops.object.select_all(action='DESELECT')
exports=[root,*ctrl,*[o for o in s.objects if o.type=='MESH'],*[o for o in new_objects if o.type=='EMPTY']]
for o in exports:o.select_set(True)
bpy.context.view_layer.objects.active=ctrl[0]
bpy.ops.export_scene.gltf(filepath=str(OUT/'Overhead_Review.glb'),export_format='GLB',use_selection=True,
 export_animations=True,export_animation_mode='ACTIONS',export_merge_animation='ACTION',export_frame_range=False,
 export_force_sampling=False,export_optimize_animation_size=False,export_anim_slide_to_zero=True,
 export_skins=SKIN,export_cameras=False,export_lights=False,export_extras=True,export_yup=True)
for o in ctrl:o.animation_data.action,o.animation_data.action_slot=actions[o.name]
s.frame_set(0);bpy.context.view_layer.update();s['review_only']=False;s['surface_finish']='closed leather joint inserts and sealed sleeve ends; no body mesh'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Overhead_Review.blend'),compress=True)
assert all(sha(Path(p))==h for p,h in protected.items()),'Source changed'
report['source_preserved']=True;report['protected_source_sha256']=protected
report['artifacts']={p.name:{'bytes':p.stat().st_size,'sha256':sha(p)} for p in [OUT/'Overhead_Review.blend',OUT/'Overhead_Review.glb',OUT/'arm_pose_samples.json']}
(OUT/'surface_finish_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SURFACE_FINISH_DONE '+json.dumps(report))
