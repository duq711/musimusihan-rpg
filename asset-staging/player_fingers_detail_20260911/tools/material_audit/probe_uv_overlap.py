import bpy,json
from pathlib import Path
from mathutils import Vector
root=Path.cwd();out=root/'asset-staging/player_fingers_detail_20260911/tools/material_audit/image_copy_probe'
bpy.ops.wm.open_mainfile(filepath=str(root/'asset-staging/player_hands_proportions_20260911/mac_output/iteration_01/bilateral_hands_proportions.blend'))
scene=bpy.data.scenes['Bilateral_Realistic_Review'];bpy.context.window.scene=scene
holder=scene.objects['LEFT_PreviewTranslationOnly']
def desc(root):
 result=[]
 for c in root.children:result.append(c);result.extend(desc(c))
 return result
pixels=[9373197,11670565];r={str(i):[] for i in pixels}
for obj in desc(holder):
 if obj.type!='MESH' or not obj.data.uv_layers.active:continue
 mesh=obj.data;mesh.calc_loop_triangles();uv=mesh.uv_layers.active.data
 for tri in mesh.loop_triangles:
  m=mesh.materials[mesh.polygons[tri.polygon_index].material_index]
  coords=[Vector(uv[i].uv)*4096 for i in tri.loops]
  lo=Vector((min(p.x for p in coords),min(p.y for p in coords)));hi=Vector((max(p.x for p in coords),max(p.y for p in coords)))
  for index in pixels:
   p=Vector((index%4096+.5,index//4096+.5))
   if not all(lo[k]-4<=p[k]<=hi[k]+4 for k in range(2)):continue
   sign=[];d=[]
   for a,b in zip(coords,coords[1:]+coords[:1]):
    e=b-a;cross=e.x*(p.y-a.y)-e.y*(p.x-a.x);sign.append(cross)
    t=max(0,min(1,(p-a).dot(e)/max(1e-20,e.length_squared)));d.append((p-a-e*t).length)
   inside=all(v>=0 for v in sign) or all(v<=0 for v in sign)
   if inside or min(d)<4:r[str(index)].append({'object':obj.name,'material':m.name,'tri':tri.index,'polygon':tri.polygon_index,'inside':inside,'edge_distance':min(d),'uv':list(map(list,coords))})
(out/'uv_overlap.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
