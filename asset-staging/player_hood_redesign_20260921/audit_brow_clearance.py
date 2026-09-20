"""Read-only front-ray clearance between rebuilt hood shell/lining and scalp."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent
source=W/'Gravebound_Rebuilt_Hood.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
def tree(name):
 o=bpy.data.objects[name];m=o.data;m.calc_loop_triangles()
 return BVHTree.FromPolygons([o.matrix_world@v.co for v in m.vertices],[tuple(t.vertices) for t in m.loop_triangles],all_triangles=True)
a=tree('Gravebound_PointHood');b=tree('Gravebound_AnatomicalHead')
rows=[];exclusions=0;warnings=[]
for iz in range(29):
 z=1.66+iz*.0025
 for ix in range(45):
  x=-.055+ix*.0025
  ray=Vector((x,.5,z));direction=Vector((0,-1,0))
  p,n,i,d=a.ray_cast(ray,direction,1)
  q=b.ray_cast(ray,direction,1)[0]
  if p is None or q is None or p.y<.02 or n.y<0:exclusions+=1;continue
  inner,inn,ii,dd=a.ray_cast(p+direction*.00001,direction,1)
  if inner is None or inner.y<.02 or inn.y>=0:
   exclusions+=1;continue
  row={'x':round(x,6),'z':round(z,6),'outer_y':round(p.y,7),'lining_y':round(inner.y,7),'head_y':round(q.y,7),'outer_clearance_m':p.y-q.y,'lining_clearance_m':inner.y-q.y}
  rows.append(row)
  if row['lining_clearance_m']<0:warnings.append(row)
original_region=[r for r in rows if 1.6875<=r['z']<=1.7075 and abs(r['x'])<=.0425]
report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'output_glb_sha256':hashlib.sha256((W/'gravebound_player_rebuilt_hood.glb').read_bytes()).hexdigest(),'audit_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'sampled_front_brow_region':{'x_m':[-.055,.055],'z_m':[1.66,1.73],'step_m':.0025},'valid_shell_and_scalp_rays':len(rows),'excluded_aperture_or_outside_head_rays':exclusions,'outer_minimum_clearance_m':min(r['outer_clearance_m'] for r in rows),'lining_minimum_clearance_m':min(r['lining_clearance_m'] for r in rows),'previously_protruding_region_valid_rays':len(original_region),'previously_protruding_region_outer_minimum_m':min(r['outer_clearance_m'] for r in original_region),'previously_protruding_region_lining_minimum_m':min(r['lining_clearance_m'] for r in original_region),'lining_intersections':warnings,'worst_clearance_samples':sorted(rows,key=lambda x:x['lining_clearance_m'])[:12],'pass':len(warnings)==0}
(W/'brow_clearance_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2));assert report['pass']
