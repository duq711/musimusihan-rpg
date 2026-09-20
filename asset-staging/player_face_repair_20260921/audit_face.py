import bpy,json
from pathlib import Path
from collections import defaultdict
W=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(W.parent/'player_no_hood_20260921/Gravebound_No_Hood.blend'))
h=bpy.data.objects['Gravebound_AnatomicalHead'];m=h.data
r={}
for i,mat in enumerate(m.materials):
 fs=[p for p in m.polygons if p.material_index==i];cs=[p.center for p in fs]
 r[mat.name]={'index':i,'faces':len(fs),'bounds':[[min(c[a] for c in cs),max(c[a] for c in cs)] for a in range(3)],'nodes':[(n.type,n.name) for n in mat.node_tree.nodes]}
(W/'head_materials.json').write_text(json.dumps(r,indent=2))
import numpy as np
np.savez_compressed(str(W/'head_audit.npz'),vertices=np.array([list(v.co) for v in m.vertices]),normals=np.array([list(v.normal) for v in m.vertices]),faces=np.array([list(p.vertices) for p in m.polygons]),materials=np.array([p.material_index for p in m.polygons]),uv=np.array([list(d.uv) for d in m.uv_layers.active.data]),loops=np.array([l.vertex_index for l in m.loops]))
print(json.dumps(r,indent=2))
