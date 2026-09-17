"""Keep the actual supplied attachment fixed while fingers flex above it."""
import bpy,json,sys,shutil,math,hashlib,numpy as np
from pathlib import Path
from mathutils import Matrix,Vector
stage=Path(__file__).resolve().parents[1];project=stage.parents[1]
sys.path.insert(0,str(stage/'tools'));sys.path.insert(0,str(project/'asset-staging/player_mercenary_gloves_20260911/tools'))
from rig_supplied import matrix_weights,assign_weights,evaluated_coordinates,inspect_binding
from reference_export import export_native,descendants
old=stage/'mac_output/iteration_02';out=stage/'mac_output/iteration_03';out.mkdir(parents=True,exist_ok=False)
bpy.ops.wm.open_mainfile(filepath=str(old/'bilateral_supplied_hands.blend'))
scene=bpy.data.scenes['Bilateral_SuppliedHands_Review'];bpy.context.window.scene=scene
report={'source_blend_sha256':hashlib.sha256((old/'bilateral_supplied_hands.blend').read_bytes()).hexdigest(),
        'fixed_through_native_y_m':-.008,'original_weights_from_native_y_m':.018,'hands':{}}
for side in ('left','right'):
    holder=bpy.data.objects[side.upper()+'_PreviewTranslationOnly'];body=bpy.data.objects['Supplied_AnatomicalHand_'+side];rig=bpy.data.objects['Supplied_HandRig_'+side]
    nails={d:bpy.data.objects['Nail_'+d+'_'+side] for d in ('thumb','index','middle','ring','little')}
    points=np.asarray([v.co[:] for v in body.data.vertices]);y=points[:,1]
    t=np.clip((y+.008)/.026,0,1);blend=t*t*(3-2*t)
    weights=matrix_weights(body);weights*=blend[:,None];weights[:,0]+=1-blend
    assign_weights(body,weights)
    keys=body.data.shape_keys.key_blocks;basis=keys[0]
    for key in list(keys)[1:]:
        for i in np.flatnonzero(blend<1):key.data[int(i)].co=basis.data[int(i)].co+(key.data[int(i)].co-basis.data[int(i)].co)*float(blend[i])
    bpy.context.view_layer.update();before=evaluated_coordinates(body)
    for d in nails:
        for j,angle in enumerate((25,35,45) if d=='thumb' else (60,45,45)):
            rig.pose.bones[d+str(j)].matrix_basis=Matrix.Rotation(-math.radians(angle),4,'X');keys[f'Joint_{d}_{j}'].value=1
    bpy.context.view_layer.update();after=evaluated_coordinates(body)
    fixed=blend==0;error=float(np.linalg.norm(after[fixed]-before[fixed],axis=1).max());assert error<1e-6
    for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
    for k in keys:k.value=0
    bpy.context.view_layer.update()
    assert np.array_equal(points,np.asarray([v.co[:] for v in body.data.vertices]))
    assert float(np.linalg.norm(evaluated_coordinates(body)-before,axis=1).max())<1e-7
    report['hands'][side]={'fixed_wrist_vertices':int(fixed.sum()),'transition_vertices':int(((blend>0)&(blend<1)).sum()),'maximum_fixed_skin_movement_at_all_joint_max_m':error,
        'neutral_mesh_unchanged':True,'binding':inspect_binding(body,nails,rig),
        'export':export_native(scene,descendants(holder),holder,out/(side+'_hand_supplied.glb'))}
for p in old.glob('*.png'):shutil.copy2(p,out/p.name)
shutil.copy2(old/'gravebound_player_supplied_hands.glb',out/'gravebound_player_supplied_hands.glb')
shutil.copy2(old/'attachment_report.json',out/'attachment_report.json')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'bilateral_supplied_hands.blend'),check_existing=False)
report['blend_sha256']=hashlib.sha256((out/'bilateral_supplied_hands.blend').read_bytes()).hexdigest()
(out/'wrist_binding_report.json').write_text(json.dumps(report,indent=2))
print('SUPPLIED_WRIST_BINDING_PASS',flush=True)
