import json,math,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,'/Users/byeolee/Projects/musimusihan-rpg/tools/dcc')
from labrador_pet_bvh import read_bvh
from labrador_pet_locomotion import basis,normalized
p=Path('/Users/byeolee/Projects/musimusihan-rpg/asset-staging/labrador-pet-20261005/source/raw_bvh_data/dog_fast_run_02_006.bvh');c=read_bvh(p);coord=basis(c,2968)
result=[]
for f in [2955.2,2956,2956.8,2957.6,2958.4,2959.2,2960]:
 a=normalized(c,f,coord);x={'source_frame':f,'q':{},'p':{}}
 for n in ['b_LeftLeg1','b_LeftAnkle','b_LeftToe']:
  x['q'][n]=list(a[n].to_quaternion());x['p'][n]=list(a[n].translation)
 result.append(x)
for prev,nxt in zip(result,result[1:]):
 q1=normalized(c,prev['source_frame'],coord)['b_LeftAnkle'].to_quaternion();q2=normalized(c,nxt['source_frame'],coord)['b_LeftAnkle'].to_quaternion();dot=q1.dot(q2);angle=2*math.acos(min(1,abs(dot)));print(prev['source_frame'],nxt['source_frame'],'dot',dot,'rotation_delta_deg',math.degrees(angle),'ankletravelcm',math.dist(prev['p']['b_LeftAnkle'],nxt['p']['b_LeftAnkle']),'toetravelcm',math.dist(prev['p']['b_LeftToe'],nxt['p']['b_LeftToe']))
print(json.dumps(result,indent=2))
Path('/Users/byeolee/Projects/musimusihan-rpg/asset-staging/labrador-gallop-20261006/gallop-source-ankle-diagnostic.json').write_text(json.dumps(result,indent=2)+'\n')
