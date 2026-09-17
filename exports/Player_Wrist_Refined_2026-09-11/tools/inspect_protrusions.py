import json, sys
from pathlib import Path
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from wrist_geometry import native_points, radial_hit
from mathutils.bvhtree import BVHTree
stage=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(stage/'mac_output/iteration_01/bilateral_hands_wrist_refined.blend'))
scene=bpy.data.scenes['Bilateral_Wrist_Refined_Review'];bpy.context.window.scene=scene
holder=scene.objects['LEFT_PreviewTranslationOnly'];skin=scene.objects['ContinuousAnatomicalHand.001'];cuff=scene.objects['WristCuff_Surface.001']
points=native_points(cuff,holder);tree=BVHTree.FromPolygons(points,[list(p.vertices)for p in cuff.data.polygons],all_triangles=False)
names={g.index:g.name for g in skin.vertex_groups};rows=[]
import math
for v,p in zip(skin.data.vertices,native_points(skin,holder)):
 if -.0208<p.y<-.0108:
  angle=math.atan2(p.z-.001,p.x);hit=radial_hit(tree,p.y,angle)
  if hit:
   unused,normal,direction,radius=hit;gap=Vector((p.x,0,p.z-.001)).length-radius
   if gap>.00025:
    rows.append({'index':v.index,'native':list(p),'gap_mm':gap*1000,'owner':names[max(v.groups,key=lambda g:g.weight).group],'decorative':v.index>=12036})
(stage/'wrist_protrusions_iteration01.json').write_text(json.dumps(rows,indent=2))
print('PROTRUSIONS',len(rows),'body',sum(not r['decorative']for r in rows),'trim',sum(r['decorative']for r in rows))
print(sorted(rows,key=lambda r:-r['gap_mm'])[:30])
