import json
from pathlib import Path
import bpy
S=Path(__file__).resolve().parents[1]
source=S.parent/'player_wrist_refinement_20260910/mac_output/iteration_02/bilateral_hands_wrist_refined.blend'
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Wrist_Refined_Review'];bpy.context.window.scene=scene
report=[]
for obj in scene.objects:
 if obj.type!='MESH':continue
 top=obj
 while top.parent:top=top.parent
 if top.name not in ['LEFT_PreviewTranslationOnly','RIGHT_PreviewTranslationOnly']:continue
 uv=[]
 for layer in obj.data.uv_layers:
  coords=[x.uv.copy() for x in layer.data]
  areas=[]
  for p in obj.data.polygons:
   c=[coords[i] for i in p.loop_indices];ar=sum(c[i].x*c[(i+1)%len(c)].y-c[(i+1)%len(c)].x*c[i].y for i in range(len(c)))*.5;areas.append(abs(ar))
  uv.append({'name':layer.name,'bounds':[[min(p[i] for p in coords),max(p[i] for p in coords)]for i in range(2)],'degenerate_polygons':sum(x<1e-12 for x in areas),'uv_total_area':sum(areas)})
 row={'name':obj.name,'side':top.name,'vertices':len(obj.data.vertices),'polygons':len(obj.data.polygons),'materials':[{ 'name':m.name,'polygons':sum(p.material_index==i for p in obj.data.polygons)}for i,m in enumerate(obj.data.materials)],'uv':uv,'shape_keys':obj.data.shape_keys.key_blocks.keys() if obj.data.shape_keys else [],'normals':{'auto_smooth':getattr(obj.data,'use_auto_smooth',None)}}
 report.append(row)
(S/'source_uv_inspection.json').write_text(json.dumps(report,indent=2))
for r in report:print(json.dumps(r))
