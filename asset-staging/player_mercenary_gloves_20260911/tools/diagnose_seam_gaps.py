"""Read-only compare originally coincident split skin vertices after padding."""
import bpy,json,sys
from pathlib import Path
from mathutils.kdtree import KDTree
root=Path.cwd();stage=root/'asset-staging/player_mercenary_gloves_20260911'
source=root/'asset-staging/player_fingers_detail_20260911/mac_output/iteration_10/bilateral_hands_finger_detail.blend'
candidate=stage/'mac_output/iteration_01/bilateral_mercenary_gloves.blend'
def objects():
 scene=bpy.data.scenes['Bilateral_Realistic_Review'];result={}
 for side in ['LEFT','RIGHT']:
  holder=scene.objects[side+'_PreviewTranslationOnly'];todo=list(holder.children)
  while todo:
   obj=todo.pop();todo.extend(obj.children)
   if obj.type=='MESH' and 'Anatomical' in obj.name:result[side]=obj
 return result
bpy.ops.wm.open_mainfile(filepath=str(source));before={}
for side,obj in objects().items():
 points=[v.co.copy() for v in obj.data.vertices[:12036]];tree=KDTree(len(points))
 for i,p in enumerate(points):tree.insert(p,i)
 tree.balance();pairs={(min(i,j),max(i,j)) for i,p in enumerate(points) for _,j,_ in tree.find_range(p,.000001) if j!=i}
 names={g.index:g.name for g in obj.vertex_groups};owners=[]
 for v in obj.data.vertices[:12036]:
  w={d:sum(g.weight for g in v.groups if names[g.group].startswith(d)) for d in ['thumb','index','middle','ring','little']};owners.append(max(w,key=w.get))
 before[side]={'points':points,'pairs':pairs,'owners':owners}
bpy.ops.wm.open_mainfile(filepath=str(candidate));report={}
for side,obj in objects().items():
 old=before[side];changed=[]
 for i,j in old['pairs']:
  gap=(obj.data.vertices[i].co-obj.data.vertices[j].co).length
  if gap>.00002:changed.append({'vertices':[i,j],'owner':old['owners'][i],'gap_m':gap,'source_gap_m':(old['points'][i]-old['points'][j]).length,'candidate_midpoint':list((obj.data.vertices[i].co+obj.data.vertices[j].co)*.5)})
 changed.sort(key=lambda r:r['gap_m'],reverse=True)
 report[side]={'source_coincident_pairs':len(old['pairs']),'opened_pairs':len(changed),'maximum_gap_m':changed[0]['gap_m'] if changed else 0,'by_digit':{d:sum(r['owner']==d for r in changed) for d in ['thumb','index','middle','ring','little']},'largest':changed[:20]}
(stage/'mac_output/iteration_01/seam_gap_diagnostic.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
