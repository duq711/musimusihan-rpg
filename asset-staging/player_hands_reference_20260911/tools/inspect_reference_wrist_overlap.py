import bpy,json,sys,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
stage=Path(__file__).resolve().parents[1];sys.path.insert(0,str(stage/'tools'))
from build_reference_hands import collect
source=stage/'mac_output/geometry_03/bilateral_hands_reference_geometry.blend';original=hashlib.sha256(source.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(source));scene=bpy.data.scenes['Bilateral_Reference_Review'];bpy.context.window.scene=scene
rows={}
for side,(holder,objects,rig,skin,nails) in collect(scene).items():
 cuff=next(o for o in objects if o.type=='MESH' and 'WristCuff' in o.name)
 matrix=holder.matrix_world.inverted()@cuff.matrix_world;cp=[matrix@v.co for v in cuff.data.vertices];tree=BVHTree.FromPolygons(cp,[tuple(p.vertices) for p in cuff.data.polygons if max(p.vertices)<2112])
 matrix=holder.matrix_world.inverted()@skin.matrix_world;sp=[matrix@v.co for v in skin.data.vertices];deltas={}
 for i,p in enumerate(sp):
  if not -.025<p.y<-.011:continue
  center=Vector((0,p.y,0));direction=Vector((p.x,0,p.z)).normalized();hit=tree.ray_cast(center+direction*.1,-direction,.15)
  if hit[0] is not None:deltas[i]=(p-hit[0]).dot(direction)
 crossing=[p.index for p in skin.data.polygons if all(i in deltas for i in p.vertices) and min(deltas[i] for i in p.vertices)<0<max(deltas[i] for i in p.vertices)]
 rows[side]={'hand_y_min':min(p.y for p in sp),'band_samples':len(deltas),'hand_above_cuff_m_max':max(deltas.values()),'hand_above_cuff_m_min':min(deltas.values()),'crossing_skin_triangle_count':len(crossing),'crossing_triangles':crossing,
 'near_cut_points':[{'vertex':i,'point':list(sp[i]),'radial_skin_minus_cuff_m':d} for i,d in deltas.items() if sp[i].y<-.019]}
assert hashlib.sha256(source.read_bytes()).hexdigest()==original
(stage/'diagnostics/wrist_overlap_geometry03.json').write_text(json.dumps(rows,indent=2));print(json.dumps({s:{k:v for k,v in r.items() if k!='near_cut_points'} for s,r in rows.items()}))
