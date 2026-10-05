import sys
from pathlib import Path
sys.path.insert(0,'/Users/byeolee/Projects/musimusihan-rpg/tools/dcc')
from labrador_pet_bvh import read_bvh
cap=read_bvh('/Users/byeolee/Projects/musimusihan-rpg/asset-staging/labrador-pet-20261005/source/raw_bvh_data/dog_fast_run_02_006.bvh')
for i in [2944,2968,2992]:
 p=cap.world_pose(i);print('frame',i)
 for ch in [('b_LeftClav','b_LeftArm','b_LeftForeArm','b_LeftHand','b__LeftFinger'),('b_RightClav','b_RightArm','b_RightForeArm','b_RightHand','b_RightFinger'),('b_LeftLegUpper','b_LeftLeg','b_LeftLeg1','b_LeftAnkle','b_LeftToe'),('b_RightLegUpper','b_RightLeg','b_RightLeg1','b_RightAnkle','b_RightToe')]:
  print([(a,z,round((p[z].translation-p[a].translation).length,5)) for a,z in zip(ch,ch[1:])])
print('hierarchy')
for j in cap.joints:
 if j.name in ['b_LeftLegUpper','b_LeftLeg','b_LeftLeg1','b_LeftAnkle','b_LeftToe','b_LeftClav','b_LeftArm','b_LeftForeArm','b_LeftHand','b__LeftFinger']:print(j.name,'parent',cap.joints[j.parent].name,'OFFSET',j.offset)
