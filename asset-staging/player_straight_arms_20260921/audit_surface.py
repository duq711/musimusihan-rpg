import bpy
from collections import Counter
from pathlib import Path
w=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(w/'Gravebound_FP_Arms.blend'))
for o in bpy.data.objects:
 if o.type!='MESH' or not o.name.startswith('Gravebound_FP_') or not o.name.endswith('_Arm'):continue
 counts=Counter(tuple(sorted(e)) for f in o.data.polygons for e in f.edge_keys)
 upper=[e for e in o.data.edges if min(o.data.vertices[i].co.z for i in e.vertices)>.936]
 assert all(counts[tuple(sorted(e.vertices))]==2 for e in upper),o.name
 print('Smallest upper faces',sorted((f.area,tuple(f.center)) for f in o.data.polygons if f.center.z>.936)[:8])
 assert all(f.area>1e-12 for f in o.data.polygons if f.center.z>.936),o.name
 print(o.name,'continuous upper sleeve: no open edges or degenerate faces',len(upper))
print('CONTINUOUS SLEEVE SURFACE PASS')
