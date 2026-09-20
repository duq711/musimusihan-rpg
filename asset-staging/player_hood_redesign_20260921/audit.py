"""Read-only topology, self-intersection and crown coverage audit of rebuilt hood."""
import bpy,bmesh,json,math,hashlib
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent
bpy.ops.wm.open_mainfile(filepath=str(W/'Gravebound_Rebuilt_Hood.blend'))
o=bpy.data.objects['Gravebound_PointHood'];m=o.data
m.calc_loop_triangles();vs=[v.co.copy() for v in m.vertices];ts=[tuple(t.vertices) for t in m.loop_triangles]
bv=BVHTree.FromPolygons(vs,ts,all_triangles=True)
pairs=[(i,j) for i,j in bv.overlap(bv) if i<j and not set(ts[i]).intersection(ts[j])]
# Moller-Trumbore finite segment, excluding contacts at segment endpoints.
def crossing(a,b,p,q,r):
 d=b-a;e1=q-p;e2=r-p;h=d.cross(e2);det=e1.dot(h)
 if abs(det)<1e-13:return None
 inv=1/det;s=a-p;u=inv*s.dot(h)
 if u< -1e-7 or u>1+1e-7:return None
 v=inv*d.dot(s.cross(e1))
 if v< -1e-7 or u+v>1+1e-7:return None
 t=inv*e2.dot(s.cross(e1))
 if 1e-6<t<1-1e-6:return a+t*d
 return None
hits=[]
for i,j in pairs:
 a=[vs[v] for v in ts[i]];b=[vs[v] for v in ts[j]];p=None
 for src,dst in ((a,b),(b,a)):
  for k in range(3):
   p=crossing(src[k],src[(k+1)%3],*dst)
   if p is not None:break
  if p is not None:break
 if p is not None:hits.append({'triangles':[i,j],'point':list(p)})
b=bmesh.new();b.from_mesh(m);b.verts.ensure_lookup_table();b.faces.ensure_lookup_table()
report={'source_blend_sha256':hashlib.sha256((W/'Gravebound_Rebuilt_Hood.blend').read_bytes()).hexdigest(),'output_glb_sha256':hashlib.sha256((W/'gravebound_player_rebuilt_hood.glb').read_bytes()).hexdigest(),'audit_script_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'hood_vertices':len(vs),'hood_triangles':len(ts),'boundary_edges':sum(e.is_boundary for e in b.edges),'nonmanifold_edges':sum(not e.is_manifold for e in b.edges),'zero_area_faces':sum(f.calc_area()<1e-12 for f in b.faces),'signed_volume_m3':b.calc_volume(signed=True),'nonadjacent_overlap_candidates':len(pairs),'confirmed_surface_crossings':len(hits),'surface_crossing_details':hits[:40]}
# Broader elliptical crown coverage includes high-curvature shoulder of dome.
failed=[];normals=[]
for ir in range(1,10):
 rho=ir/10
 for ia in range(96):
  a=math.tau*ia/96;x=.0806*rho*math.cos(a);y=.005+.092*rho*math.sin(a)
  p,n,idx,dist=bv.ray_cast(Vector((x,y,1.95)),Vector((0,0,-1)),.5)
  if p is None or p.z<1.700 or n.z<=0:failed.append({'x':x,'y':y,'point':list(p) if p else None,'normal':list(n) if n else None})
  else:normals.append(n.z)
report.update({'crown_rays':9*96,'crown_failed_rays':failed,'crown_min_upward_normal':min(normals)})
# Connected component count, independent of Blender polygon ordering.
unseen=set(b.verts);components=[]
while unseen:
 r=unseen.pop();todo=[r];count=0
 while todo:
  v=todo.pop();count+=1
  for e in v.link_edges:
   z=e.other_vert(v)
   if z in unseen:unseen.remove(z);todo.append(z)
 components.append(count)
report['components']=components
report['pass']=not(hits or failed or report['boundary_edges'] or report['nonmanifold_edges'] or report['zero_area_faces']) and len(components)==1 and report['signed_volume_m3']>0
(W/'audit_report.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report,indent=2));assert report['pass']
