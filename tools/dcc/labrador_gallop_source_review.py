"""Read-only real canine capture extension review, using Mac Blender FK."""
import argparse,json,math,sys
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh
parser=argparse.ArgumentParser();parser.add_argument('--source-base',type=Path,required=True);parser.add_argument('--report',type=Path,required=True)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);base=args.source_base.resolve()
segments=[('prior','dog_fast_run_02_006.bvh',2944,2992),('fast005','dog_fast_run_02_005.bvh',1824,1868),('fast005early','dog_fast_run_02_005.bvh',148,200),('fast007','dog_fast_run_02_007.bvh',236,288),('fast008','dog_fast_run_02_008.bvh',3424,3480)]
results=[]
for label,file,start,end in segments:
 cap=read_bvh(base/'source/raw_bvh_data'/file);poses=[cap.world_pose(i) for i in range(start,end+1)];n=end-start
 hips=[p['b_Hips'].translation for p in poses];chest=[p['b_Spine3'].translation for p in poses]
 direction=chest[n//2]-hips[n//2];direction.y=0;direction.normalize();right=Vector((direction.z,0,-direction.x))
 body=[(c-h).length for h,c in zip(hips,chest)];bodyplanar=[(c-h).dot(direction) for h,c in zip(hips,chest)]
 pitch=[math.degrees(math.atan2((c-h).y,(c-h).dot(direction))) for h,c in zip(hips,chest)]
 source_chains={'fore.L':['b_LeftArm','b_LeftForeArm','b_LeftHand','b__LeftFinger'],'fore.R':['b_RightArm','b_RightForeArm','b_RightHand','b_RightFinger'],'hind.L':['b_LeftLegUpper','b_LeftLeg','b_LeftLeg1','b_LeftAnkle','b_LeftToe'],'hind.R':['b_RightLegUpper','b_RightLeg','b_RightLeg1','b_RightAnkle','b_RightToe']}
 lengths={key:[(poses[0][z].translation-poses[0][a].translation).length for a,z in zip(chain,chain[1:])] for key,chain in source_chains.items()}
 row={'source_segment_lengths_cm':lengths,'label':label,'file':file,'start':start,'end':end,'duration_s':n*cap.frame_time,'root_speed_m_s':((hips[-1]-hips[0]).length/(n*cap.frame_time))/100,'bodylength_cm':[min(body),max(body)],'body_pitch_deg':[min(pitch),max(pitch)],'hip_height_cm':[min(h.y for h in hips),max(h.y for h in hips)],'limbs':{}}
 for foot,shoulder in [('b__LeftFinger','b_LeftArm'),('b_RightFinger','b_RightArm'),('b_LeftToe','b_LeftLegUpper'),('b_RightToe','b_RightLegUpper')]:
  positions=[p[foot].translation for p in poses];relative=[(p[foot].translation-p[shoulder].translation).dot(direction) for p in poses]
  minimum=min(relative);maximum=max(relative);j=relative.index(maximum if 'Finger' in foot else minimum)
  row['limbs'][foot]={'relative_forward_to_proximal_cm':[minimum,maximum],'extension_phase':j/n,'height_at_extension_cm':positions[j].y,'max_joint_height_cm':max(p.y for p in positions),'extension_body_ratio':(maximum if 'Finger' in foot else -minimum)/(sum(bodyplanar)/len(bodyplanar))}
 results.append(row)
output=args.report;output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps({'scope':'Read-only source segment extension review. Skeleton capture points, not target skinned quality or measured force.','coordinate':'Original centimetres/Y up, forward midpoint body heading','segments':results},indent=2)+'\n')
print('GALLOP_SOURCE_EXTENSION_REVIEW',output)
