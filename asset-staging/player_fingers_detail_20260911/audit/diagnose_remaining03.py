import bpy,json,importlib.util,traceback,hashlib
from pathlib import Path
root=Path(__file__).resolve().parents[3];stage=root/'asset-staging/player_fingers_detail_20260911';support=root/'asset-staging/player_hands_realism_20260911/tools';source=root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01';output=stage/'mac_output/iteration_03'
p=stage/'tools/verify_finger_detail.py';spec=importlib.util.spec_from_file_location('audit',p);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
a.legacy=a.module(support/'verify_hands_realistic.py','remaining_legacy');a.core=a.legacy.core;a.generic=a.module(root/'asset-staging/player_hands_proportions_20260911/tools/verify_proportions.py','remaining_generic');a.generic.legacy=a.legacy;a.generic.core=a.core
report={'status':'diagnostic_only_not_acceptance','checks':{},'failures':{}}
def run(name,fn):
 try:report['checks'][name]=fn();print('DIAG_PASS',name,flush=True)
 except Exception as e:report['failures'][name]={'error':str(e),'traceback':traceback.format_exc()};print('DIAG_FAIL',name,str(e),flush=True)
files=[source/'bilateral_hands_proportions.blend',output/'bilateral_hands_finger_detail.blend',*[output/(s+'_hand_finger_detail.glb') for s in ('left','right')]];hashes={str(p):a.sha(p) for p in files}
bpy.ops.wm.open_mainfile(filepath=str(files[0]));scene,rigs=a.activate();old={s:a.capture(scene,r) for s,r in rigs.items()};old_nails={s:a.nail_measurements(scene,r) for s,r in rigs.items()}
for side in ('left','right'):
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(source/(side+'_hand_proportions.glb')),bone_heuristic='TEMPERANCE');rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE');a.legacy.attach_prior_export_weights(old[side],a.legacy.snapshot(bpy.context.scene,rig))
bpy.ops.wm.open_mainfile(filepath=str(files[1]));scene,rigs=a.activate();current={s:a.capture(scene,r) for s,r in rigs.items()};atlases,evidence=a.packed_atlases(scene,output);report['checks']['actual_packed_png']=evidence
for side,rig in rigs.items():
 run(side+'_preservation',lambda:a.inspect_changes(old[side],current[side]))
 run(side+'_locality',lambda:a.inspect_key_locality(current[side]))
 run(side+'_articulation',lambda:a.generic.inspect_pose(scene,rig))
 nails=a.nail_measurements(scene,rig)
 for pose in nails:
  for digit in a.DIGITS:
   run(side+'/'+pose+'/'+digit,lambda:a.compare_nails({pose:{digit:nails[pose][digit]}},{pose:{digit:old_nails[side][pose][digit]}}))
 for label,part in current[side]['parts'].items():part['prior_export_weights']=old[side]['parts'][label]['prior_export_weights']
for side in ('left','right'):
 path=output/(side+'_hand_finger_detail.glb')
 run(side+'_glb_container',lambda:a.legacy.inspect_glb_container(path))
 run(side+'_glb_new_actual_png',lambda:a.embedded_pixels(path,source/(side+'_hand_proportions.glb'),atlases))
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(path),bone_heuristic='TEMPERANCE');scene=bpy.context.scene;rig=next(o for o in scene.objects if o.type=='ARMATURE');actual=a.capture(scene,rig)
 run(side+'_glb_roundtrip',lambda:a.generic.roundtrip(actual,current[side]))
 run(side+'_glb_pose',lambda:a.generic.inspect_pose(scene,rig))
 run(side+'_glb_locality',lambda:a.inspect_key_locality(actual))
assert all(a.sha(p)==v for p,v in hashes.items());report['source_hashes_unchanged']=hashes
p=Path(__file__).with_name('remaining_checks03.json');p.write_text(json.dumps(report,indent=2));print('REMAINING_DIAGNOSTIC_DONE',len(report['checks']),len(report['failures']),flush=True)
