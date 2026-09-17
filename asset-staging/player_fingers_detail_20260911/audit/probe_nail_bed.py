import bpy,json,sys,inspect,traceback
from pathlib import Path
p=Path(__file__).resolve();root=p.parents[3];stage=p.parents[1];sys.path.insert(0,str(stage/'tools'));import verify_finger_detail as a
support=root/'asset-staging/player_hands_realism_20260911/tools';a.legacy=a.module(support/'verify_hands_realistic.py','b_legacy');a.core=a.legacy.core
src=inspect.getsource(a.nail_measurements).replace('groups[g.group].startswith(digit)','groups[g.group] == digit+"2"');exec(src,a.__dict__)
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'));scene,rigs=a.activate();old={s:a.nail_measurements(scene,r) for s,r in rigs.items()}
bpy.ops.wm.open_mainfile(filepath=str(stage/'mac_output/geometry_02/bilateral_hands_finger_detail.blend'));scene,rigs=a.activate();r={'checks':{},'errors':{}}
for side,rig in rigs.items():
 current=a.nail_measurements(scene,rig)
 for pose,digits in current.items():
  for d in digits:
   try:r['checks'][side+'/'+pose+'/'+d]=a.compare_nails({pose:{d:current[pose][d]}},{pose:{d:old[side][pose][d]}})
   except Exception as e:r['errors'][side+'/'+pose+'/'+d]=str(e)
(stage/'audit/nail_bed_probe.json').write_text(json.dumps(r,indent=2));print('NAIL_BED_PROBE',len(r['checks']),json.dumps(r['errors']))
