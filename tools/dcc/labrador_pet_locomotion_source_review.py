"""Read-only real canine BVH footfall review; run inside Mac Blender."""
import argparse,sys,json,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from labrador_pet_bvh import read_bvh
from mathutils import Vector
parser=argparse.ArgumentParser();parser.add_argument('--base',type=Path,required=True);parser.add_argument('--report',type=Path)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);base=args.base.resolve()
clips=[('Walk','dog_quad_walk_002.bvh',14132,14224),('Run','dog_fast_run_02_006.bvh',2944,2992),('Trot','dog_quad_run_001.bvh',4096,4164)]
out={'scope':'Read-only capture timing and anatomy analysis; no authored model/clip changes','units':'Source centimetres, Y up. Foot-joint height and inferred contact are not measured surface contact.','clips':[]}
feet=['b__LeftFinger','b_RightFinger','b_LeftToe','b_RightToe']
ankles=['b_LeftHand','b_RightHand','b_LeftAnkle','b_RightAnkle']
for name,file,start,end in clips:
 cap=read_bvh(base/'source/raw_bvh_data'/file)
 poses=[cap.world_pose(i) for i in range(start,end+1)]
 n=end-start
 root=[p['b_Hips'].translation for p in poses]
 heading=(root[-1]-root[0]);heading.y=0;heading.normalize()
 left=Vector((heading.z,0,-heading.x))
 row={'name':name,'file':file,'start':start,'end':end,'duration_s':n*cap.frame_time,'root_displacement_cm':list(root[-1]-root[0]),'planar_direction':list(heading),'hip_height_cm':[min(p.y for p in root),max(p.y for p in root)],'feet':{}}
 for foot,ankle in zip(feet,ankles):
  p=[v[foot].translation for v in poses];a=[v[ankle].translation for v in poses]
  heights=[v.y for v in p];low=min(heights)
  rel=[v-r for v,r in zip(p,root)]
  progress=[v.dot(heading) for v in rel];cross=[v.dot(left) for v in rel]
  speed=[(p[min(i+1,n)]-p[max(i-1,0)]).length/(cap.frame_time*(min(i+1,n)-max(i-1,0))) for i in range(n+1)]
  # Height threshold 3 cm above cycle low, with low planar foot speed corroboration reported separately.
  stance=[y<=low+3 for y in heights]
  starts=[i for i in range(n) if stance[i] and not stance[(i-1)%n]]
  ends=[i for i in range(n) if not stance[i] and stance[(i-1)%n]]
  row['feet'][foot]={'ankle':ankle,'joint_height_cm':[low,max(heights)],'max_clearance_above_cycle_min_cm':max(heights)-low,'relative_forward_cm':[min(progress),max(progress)],'relative_lateral_cm':[min(cross),max(cross)],'ankle_height_cm':[min(v.y for v in a),max(v.y for v in a)],'height_based_contact_fraction':sum(stance[:n])/n,'height_threshold_cm':low+3,'touchdown_phase': [round(i/n,4) for i in starts],'liftoff_phase':[round(i/n,4) for i in ends],'stance_speed_cm_s':[round(min((s for s,c in zip(speed[:n],stance[:n]) if c),default=0),3),round(max((s for s,c in zip(speed[:n],stance[:n]) if c),default=0),3)],'velocity_contact': {'threshold_cm_s':round(((root[-1]-root[0]).length/(n*cap.frame_time))*.35,3),'phases':[round(i/n,4) for i in range(n) if speed[i] < ((root[-1]-root[0]).length/(n*cap.frame_time))*.35]},'sample_8phase':[{'phase':round(i/n,4),'y':round(heights[i],3),'forward_relative_hip':round(progress[i],3),'lateral':round(cross[i],3),'speed_cm_s':round(speed[i],3)} for i in [round(j*n/8) for j in range(9)]]}
 out['clips'].append(row)
path=args.report or base/'locomotion-source-review.json';path.write_text(json.dumps(out,indent=2)+'\n')
print('LOCOMOTION_SOURCE_REVIEW',path)
