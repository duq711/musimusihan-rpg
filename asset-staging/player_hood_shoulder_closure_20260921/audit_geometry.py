"""Read-only source preservation, bridge shape and solidified shell smoke audit."""
from pathlib import Path
import bpy,bmesh,json,hashlib,sys
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent;sys.path.insert(0,str(W))
from geometry import create_bridges
source=W.parent/'player_hood_redesign_20260921/Gravebound_Rebuilt_Hood.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
def sig(o):return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(p.vertices) for p in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'world':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
before={o.name:sig(o) for o in bpy.data.objects if o.type=='MESH'}
new=create_bridges();report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'original_meshes_unchanged':before=={name:sig(bpy.data.objects[name]) for name in before},'sheets':[]}
for o in new:
 m=o.data;m.calc_loop_triangles();vs=[v.co.copy() for v in m.vertices];ts=[tuple(t.vertices) for t in m.loop_triangles]
 bv=BVHTree.FromPolygons(vs,ts,all_triangles=True);pairs=[(i,j) for i,j in bv.overlap(bv) if i<j and not set(ts[i]).intersection(ts[j])]
 bm=bmesh.new();bm.from_mesh(m);row={'name':o.name,'vertices':len(vs),'triangles':len(ts),'nonadjacent_triangle_overlaps':len(pairs),'zero_area_faces':sum(f.calc_area()<1e-12 for f in bm.faces),'minimum_normal_z':min(f.normal.z for f in bm.faces)};bm.free()
 bpy.context.view_layer.objects.active=o;o.select_set(True);mod=o.modifiers.new('AuditClothThickness','SOLIDIFY');mod.thickness=.004;mod.offset=-1;mod.use_even_offset=True;bpy.ops.object.modifier_apply(modifier=mod.name)
 bm=bmesh.new();bm.from_mesh(o.data);row['solidified_boundary_edges']=sum(e.is_boundary for e in bm.edges);row['solidified_nonmanifold_edges']=sum(not e.is_manifold for e in bm.edges);row['solidified_volume']=bm.calc_volume(signed=True);bm.free();report['sheets'].append(row)
report['pass']=report['original_meshes_unchanged'] and all(not s['nonadjacent_triangle_overlaps'] and not s['zero_area_faces'] and not s['solidified_boundary_edges'] and not s['solidified_nonmanifold_edges'] and s['minimum_normal_z']>0 for s in report['sheets'])
(W/'geometry_audit_report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
# Temporary smoke asset for the separate coverage audit; never publish this file.
bpy.ops.wm.save_as_mainfile(filepath='/tmp/shoulder_bridge_geometry_audit.blend',compress=True)
assert report['pass']
