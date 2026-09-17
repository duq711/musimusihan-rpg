import bpy,json
from pathlib import Path
from mathutils import Vector
base=Path(__file__).resolve().parents[1]; report={}
for a in ['wooden_barrels_01','treasure_chest','wooden_crate_01','wooden_crate_02']:
 bpy.ops.wm.open_mainfile(filepath=str(base/'sources'/a/(a+'_4k.blend')),load_ui=False,use_scripts=False)
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH' and (a!='wooden_barrels_01' or o.name=='wooden_barrels_01_barrel01')]
 rec=[]
 for o in objs:
  verts=[o.matrix_world@v.co for v in o.data.vertices]; adj=[set() for v in verts]
  for e in o.data.edges: adj[e.vertices[0]].add(e.vertices[1]);adj[e.vertices[1]].add(e.vertices[0])
  remaining=set(range(len(verts)));comps=[]
  while remaining:
   c={remaining.pop()};q=list(c)
   while q:
    i=q.pop(); ns=adj[i]&remaining;c|=ns;remaining-=ns;q+=list(ns)
   vs=[verts[i] for i in c]
   comps.append({'count':len(c),'min':[min(v[k] for v in vs) for k in range(3)],'max':[max(v[k] for v in vs) for k in range(3)]})
  rec.append({'name':o.name,'min':[min(v[k] for v in verts) for k in range(3)],'max':[max(v[k] for v in verts) for k in range(3)],'components':comps})
 report[a]=rec
(base/'geometry_inspection.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2))
