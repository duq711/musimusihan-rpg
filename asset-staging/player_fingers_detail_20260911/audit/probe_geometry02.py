import bpy,json,sys,importlib.util
from pathlib import Path
p=Path(__file__).resolve();root=p.parents[3];stage=p.parents[1];sys.path.insert(0,str(stage/'tools'));import verify_finger_detail as a
support=root/'asset-staging/player_hands_realism_20260911/tools';a.legacy=a.module(support/'verify_hands_realistic.py','p_legacy');a.core=a.legacy.core;a.generic=a.module(root/'asset-staging/player_hands_proportions_20260911/tools/verify_proportions.py','p_generic');a.generic.legacy=a.legacy;a.generic.core=a.core
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'));scene,rigs=a.activate();old={s:a.capture(scene,r) for s,r in rigs.items()}
bpy.ops.wm.open_mainfile(filepath=str(stage/'mac_output/geometry_02/bilateral_hands_finger_detail.blend'));scene,rigs=a.activate();new={s:a.capture(scene,r) for s,r in rigs.items()};r={s:a.inspect_changes(old[s],new[s]) for s in rigs};(stage/'audit/geometry02_preservation.json').write_text(json.dumps(r,indent=2));print('GEOMETRY02_PRESERVATION_PASS')
