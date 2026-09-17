import bpy,json,sys,inspect
from pathlib import Path
p=Path(__file__).resolve();root=p.parents[3];stage=p.parents[1];sys.path.insert(0,str(stage/'tools'));import verify_finger_detail as a
support=root/'asset-staging/player_hands_realism_20260911/tools';a.legacy=a.module(support/'verify_hands_realistic.py','r_legacy');a.core=a.legacy.core
src=inspect.getsource(a.nail_measurements)
src=src.replace('ray_top.append((p-hit[0])', '''if label=='all_full_flex' and digit=='ring' and hit[0] is not None and (p-hit[0]).dot(dorsal)<-.001:
                            f=targets[digit][hit[2]]
                            details.append({'hit_clearance':(p-hit[0]).dot(dorsal),'face':list(f),'weight_rows':[{groups[g.group]:g.weight for g in hand.data.vertices[i].groups} for i in f],'world_point':list(p),'world_hit':list(hit[0])})
                        ray_top.append((p-hit[0])''')
a.details=[];exec(src,a.__dict__)
for folder,blend in [('player_hands_proportions_20260911/mac_output/iteration_01','bilateral_hands_proportions.blend'),('player_fingers_detail_20260911/mac_output/geometry_02','bilateral_hands_finger_detail.blend')]:
 bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging'/folder/blend));scene,rigs=a.activate();a.details=[]
 for side,rig in rigs.items():a.nail_measurements(scene,rig)
 out=stage/'audit'/('nail_ray_'+('source' if 'proportions' in folder else 'geometry02')+'.json');out.write_text(json.dumps(a.details,indent=2));print(out,len(a.details),a.details[:1])
