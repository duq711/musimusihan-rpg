"""Remove coat tails and finish the previously concealed upper trousers."""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,shutil
from mathutils import Vector
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=W.parent/'player_natural_shoulders_20260922/Gravebound_Natural_Shoulders.blend'
REMOVED=['Gravebound_CoatBackAndSides','Gravebound_CoatSkirt_L','Gravebound_CoatSkirt_R']
PANTS=['Gravebound_Trousers_L','Gravebound_Trousers_R']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
def sig(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(f.vertices) for f in o.data.polygons],'uv':[[list(u.uv) for u in l.data] for l in o.data.uv_layers],'world':[list(r) for r in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
preserved={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in REMOVED+PANTS}
for name in REMOVED:bpy.data.objects.remove(bpy.data.objects[name],do_unlink=True)
def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
def interp(z,rows,k):
 if z<=rows[0][0]:return rows[0][k]
 for a,b in zip(rows,rows[1:]):
  if z<=b[0]:
   t=(z-a[0])/(b[0]-a[0]);return a[k]*(1-t)+b[k]*t
 return rows[-1][k]
# Preserve original knees and boot interfaces below the join at 0.62m.
low_meshes={};upper=bmesh.new()
for name in PANTS:
 obj=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.transform(bm,matrix=obj.matrix_world,verts=list(bm.verts))
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
 # Tuck the newly visible pant hems inside their individual boot cuffs.
 cuff=bpy.data.objects[name.replace('Trousers','BootCuff')]
 cp=[cuff.matrix_world@v.co for v in cuff.data.vertices]
 tx=(min(v.x for v in cp)+max(v.x for v in cp))/2;ty=(min(v.y for v in cp)+max(v.y for v in cp))/2
 hem=[v.co for v in bm.verts if v.co.z<.48]
 hx=(min(v.x for v in hem)+max(v.x for v in hem))/2;hy=(min(v.y for v in hem)+max(v.y for v in hem))/2
 for v in bm.verts:
  if v.co.z>=.50:continue
  w=1-smooth((v.co.z-.445)/.055);p=v.co.copy()
  v.co.x=p.x*(1-w)+(tx+(p.x-hx)*.86)*w
  v.co.y=p.y*(1-w)+(ty+(p.y-hy)*.86)*w
 low=bm.copy();bmesh.ops.bisect_plane(low,geom=list(low.verts)+list(low.edges)+list(low.faces),dist=1e-6,plane_co=(0,0,.62),plane_no=(0,0,1),clear_outer=True);low_meshes[name]=low
 rows=[]
 for i in range(90):
  z=.60+i*.355/89;pts=[]
  for e in bm.edges:
   a,b=[v.co for v in e.verts]
   if (a.z-z)*(b.z-z)<=0 and abs(b.z-a.z)>1e-7:pts.append(a.lerp(b,(z-a.z)/(b.z-a.z)))
  if pts:
   bx=(min(p.x for p in pts),max(p.x for p in pts));by=(min(p.y for p in pts),max(p.y for p in pts))
   rows.append((z,sum(bx)/2,sum(by)/2,(bx[1]-bx[0])/2,(by[1]-by[0])/2))
 side=1 if sum(v.co.x for v in bm.verts)>0 else -1
 profile=[(.60,.139,-.024,.069,.077),(.66,.139,-.020,.073,.079),(.72,.135,-.015,.079,.083),(.80,.126,-.008,.086,.094),(.87,.113,0,.090,.105),(.94,.101,0,.087,.113),(.956,.099,0,.085,.114)]
 for v in bm.verts:
  p=v.co.copy();z=p.z
  if z<.62:continue
  cx=interp(z,rows,1);cy=interp(z,rows,2);rx=interp(z,rows,3);ry=interp(z,rows,4);w=smooth((z-.62)/.12)
  target=Vector((side*interp(z,profile,1)+(p.x-cx)/rx*interp(z,profile,3),interp(z,profile,2)+(p.y-cy)/ry*interp(z,profile,4),z))
  v.co=p.lerp(target,w)
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,.605),plane_no=(0,0,1),clear_inner=True)
 bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)
 vm={v:upper.verts.new(v.co) for v in bm.verts}
 for f in bm.faces:upper.faces.new([vm[v] for v in f.verts])
 bm.free()
# A rounded, closed pelvis bridges both legs and overlaps the retained shirt/waist belt.
pelvis=[(.815,.022,.027),(.835,.079,.062),(.86,.130,.088),(.89,.162,.107),(.935,.177,.127),(.98,.176,.137),(1.035,.162,.135),(1.093,.155,.130)]
rings=[]
for z,rx,ry in pelvis:
 rings.append([upper.verts.new((rx*math.cos(2*math.pi*i/64),ry*math.sin(2*math.pi*i/64),z)) for i in range(64)])
for a,b in zip(rings,rings[1:]):
 for i in range(64):j=(i+1)%64;upper.faces.new((a[i],a[j],b[j],b[i]))
upper.faces.new(list(reversed(rings[0])));upper.faces.new(rings[-1]);bmesh.ops.recalc_face_normals(upper,faces=list(upper.faces))
me=bpy.data.meshes.new('TrousersUpperUnion');upper.to_mesh(me);upper.free();obj=bpy.data.objects.new('TrousersUpperUnion',me);bpy.context.scene.collection.objects.link(obj)
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
mod=obj.modifiers.new('JoinedHipsAndThighs','REMESH');mod.mode='VOXEL';mod.voxel_size=.003;mod.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=mod.name)
bm=bmesh.new();bm.from_mesh(obj.data)
for _ in range(22):bmesh.ops.smooth_vert(bm,verts=[v for v in bm.verts if v.co.z>.65],factor=.45,use_axis_x=True,use_axis_y=True,use_axis_z=True)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,.64),plane_no=(0,0,1),clear_inner=True)
def boundary_rings(mesh,z):
 edges={e for e in mesh.edges if e.is_boundary and all(abs(v.co.z-z)<1e-5 for v in e.verts)};out=[]
 while edges:
  e=edges.pop();r=[e.verts[0],e.verts[1]]
  while True:
   e=next((x for x in r[-1].link_edges if x in edges),None)
   if e is None:break
   edges.remove(e);v=e.other_vert(r[-1])
   if v==r[0]:break
   r.append(v)
  out.append(r)
 return out
highrings=boundary_rings(bm,.64);assert len(highrings)==2
for name,low in low_meshes.items():
 rings=boundary_rings(low,.62);assert len(rings)==1,(name,len(rings))
 vm={v:bm.verts.new(v.co) for v in low.verts}
 for f in low.faces:bm.faces.new([vm[v] for v in f.verts])
 a=[vm[v] for v in rings[0]];cx=sum(v.co.x for v in a)/len(a);cy=sum(v.co.y for v in a)/len(a)
 b=min(highrings,key=lambda r:abs(sum(v.co.x for v in r)/len(r)-cx))
 def angle(v):return math.atan2(v.co.y-cy,v.co.x-cx)
 a.sort(key=angle);b.sort(key=angle);i=j=0
 while i<len(a) or j<len(b):
  an=angle(a[(i+1)%len(a)])+(2*math.pi if i+1>=len(a) else 0) if i<len(a) else 1e9
  bn=angle(b[(j+1)%len(b)])+(2*math.pi if j+1>=len(b) else 0) if j<len(b) else 1e9
  if an<bn:vs=[a[i%len(a)],a[(i+1)%len(a)],b[j%len(b)]];i+=1
  else:vs=[a[i%len(a)],b[(j+1)%len(b)],b[j%len(b)]];j+=1
  bm.faces.new(vs)
 low.free()
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
for _ in range(10):bmesh.ops.smooth_vert(bm,verts=[v for v in bm.verts if .621<v.co.z<.69],factor=.4,use_axis_x=True,use_axis_y=True,use_axis_z=True)
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,0),plane_no=(1,0,0))
bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.normal_update()
cloth=bpy.data.materials['Gravebound_Matched_Sleeve_Cloth']
for name in PANTS:
 original=bpy.data.objects[name];side=1 if name.endswith('_L') else -1
 faces=[f for f in bm.faces if f.calc_center_median().x*side>0];verts=list({v for f in faces for v in f.verts});index={v:i for i,v in enumerate(verts)};inv=original.matrix_world.inverted()
 mesh=bpy.data.meshes.new(name+'_CompleteTrousers');mesh.from_pydata([inv@v.co for v in verts],[],[[index[v] for v in f.verts] for f in faces]);mesh.materials.append(cloth);mesh.update();uv=mesh.uv_layers.new(name='UVMap');normals=[]
 for p,f in zip(mesh.polygons,faces):
  p.use_smooth=True
  for li,l in zip(p.loop_indices,f.loops):
   co=l.vert.co;uv.data[li].uv=(.32+co.x*.65,.10+(co.z-.40)*.42+co.y*.22);normals.append((inv.to_3x3()@l.vert.normal).normalized())
 mesh.normals_split_custom_set(normals);original.data=mesh
 original['trousers_finish']='Full waist, pelvis and thighs, retained knees with hems tucked into original boot cuffs; no coat tails'
bm.free();bpy.data.objects.remove(obj,do_unlink=True)
assert preserved=={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in PANTS}
assert len([o for o in bpy.context.scene.objects if o.type=='MESH'])==20
bpy.data.orphans_purge(do_recursive=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Trousers_Only.blend'),compress=True)
tmp=W/'trousers.tmp.glb';out=W/'gravebound_player_trousers_only.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes();assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data);tmp.replace(out);shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(data).hexdigest(),'removed_meshes':REMOVED,'rebuilt_meshes':PANTS,'preserved_meshes':preserved,'preserved_mesh_count':len(preserved),'knee_geometry_preserved_height_range_m':[.50,.62],'lower_hems_tucked_into_retained_boot_cuffs':True,'pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2)+'\n');print('TROUSERS ONLY BUILD PASS',report['output_sha256'],flush=True)
