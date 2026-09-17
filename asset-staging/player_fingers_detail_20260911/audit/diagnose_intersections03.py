import bpy,sys,json,importlib.util,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.geometry import intersect_ray_tri
root=Path(__file__).resolve().parents[3]
p=root/'asset-staging/player_fingers_detail_20260911/tools/verify_finger_detail.py'
spec=importlib.util.spec_from_file_location('audit',p);a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
source=root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'
current=root/'asset-staging/player_fingers_detail_20260911/mac_output/iteration_03/bilateral_hands_finger_detail.blend'
pairs=[(20280,20300),(20281,20300),(20283,20299),(20283,20300)]
indices=sorted(set(i for pair in pairs for i in pair));payload={}
for label,path in [('source',source),('current',current)]:
 bpy.ops.wm.open_mainfile(filepath=str(path));scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
 holder=scene.objects['LEFT_PreviewTranslationOnly'];hand=next(o for o in scene.objects if o.type=='MESH' and 'Anatomical' in o.name and o.parent and o.matrix_world.translation.x<0)
 hand.data.calc_loop_triangles();matrix=holder.matrix_world.inverted()@hand.matrix_world
 triangles=[t for t in hand.data.loop_triangles if max(t.vertices)<12036];points=[matrix@v.co for v in hand.data.vertices]
 rows={}
 for i in indices:
  t=triangles[i];polygon=hand.data.polygons[t.polygon_index]
  rows[i]={'vertex_ids':list(t.vertices),'polygon':t.polygon_index,'material':hand.data.materials[polygon.material_index].name,'points':[list(points[v]) for v in t.vertices]}
 vertices=sorted({v for i in indices for v in triangles[i].vertices})
 nset={v for t in triangles if set(t.vertices)&set(vertices) for v in t.vertices}
 w={i:{hand.vertex_groups[g.group].name:g.weight for g in hand.data.vertices[i].groups} for i in vertices}
 hits={}
 for i,j in pairs:
  fa,fb=[points[v] for v in triangles[i].vertices],[points[v] for v in triangles[j].vertices];out=[]
  for names,ends,target in [((i,j),fa,fb),((j,i),fb,fa)]:
   for edge,(p,q) in enumerate(zip(ends,ends[1:]+ends[:1])):
    hit=intersect_ray_tri(*target,q-p,p,True)
    if hit is not None:
     t=(hit-p).dot(q-p)/(q-p).length_squared
     if 0<t<1:out.append({'edge_of':names[0],'target_face':names[1],'edge':edge,'t':t,'hit':list(hit),'end_distance_m':min((hit-p).length,(hit-q).length)})
  hits[str((i,j))]={'actual_intersection':a.triangle_hit(fa,fb),'segment_hits':out}
 payload[label]={'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'triangles':rows,'vertices':{i:{'point':list(points[i]),'weights':w[i]} for i in vertices},'one_ring_vertices':sorted(nset),'hits':hits}
for i in payload['current']['vertices']:
 old=Vector(payload['source']['vertices'][i]['point']);new=Vector(payload['current']['vertices'][i]['point']);payload['current']['vertices'][i]['displacement_m']=list(new-old);payload['current']['vertices'][i]['distance_m']=(new-old).length
out=Path(__file__).with_name('intersection_diagnostic03.json');out.write_text(json.dumps(payload,indent=2));print('INTERSECTION_DIAGNOSTIC',out,flush=True)
