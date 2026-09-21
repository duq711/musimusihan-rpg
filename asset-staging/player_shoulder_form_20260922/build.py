"""Resculpt the joined chest/shoulders/upper sleeves as one continuous garment."""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,shutil
from mathutils import Vector
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=W.parent/'player_trousers_only_20260922/Gravebound_Trousers_Only.blend'
NAMES=['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
def sig(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(p.vertices) for p in o.data.polygons],'uv':[[list(u.uv) for u in l.data] for l in o.data.uv_layers],'world':[list(r) for r in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
preserved={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in NAMES}
def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
def lerp_rows(z,rows,col):
 if z<=rows[0][0]:return rows[0][col]
 for a,b in zip(rows,rows[1:]):
  if z<=b[0]:
   t=(z-a[0])/(b[0]-a[0]);return a[col]*(1-t)+b[col]*t
 return rows[-1][col]
bm=bmesh.new();uv=bm.loops.layers.uv.new('UVMap');part=bm.faces.layers.int.new('source_part');materials=[]
for index,name in enumerate(NAMES):
 obj=bpy.data.objects[name];me=obj.data;vs=[bm.verts.new(obj.matrix_world@v.co) for v in me.vertices]
 for mat in me.materials:
  if mat not in materials:materials.append(mat)
 for poly in me.polygons:
  f=bm.faces.new([vs[i] for i in poly.vertices]);f[part]=index;f.material_index=materials.index(me.materials[poly.material_index])
  for loop,li in zip(f.loops,poly.loop_indices):loop[uv].uv=me.uv_layers.active.data[li].uv
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table();old_bvh=BVHTree.FromBMesh(bm)
original={v:v.co.copy() for v in bm.verts}
# Sample the old surface rather than confusing the visible arm volume with a seam.
def depth(x,z,front):
 start=Vector((x,-.6 if front else .6,z));direction=Vector((0,1 if front else -1,0))
 hit=old_bvh.ray_cast(start,direction,1.2)[0]
 return abs(hit.y) if hit is not None else None
rows=[]
for i in range(126):
 z=1.20+i*.002;points=[p for p in original.values() if abs(p.z-z)<.002]
 if not points:continue
 width=max(abs(p.x) for p in points)
 ds=[depth(s*.14,z,f) for s in [-1,1] for f in [True,False]]
 rows.append((z,width,*[v if v is not None else .045 for v in ds]))
for v,p in original.items():
 x=abs(p.x);z=p.z
 if z<=1.18 or z>=1.47 or x<=.10:continue
 zw=smooth((z-1.20)/.10)*smooth((lerp_rows(z,rows,1)-.145)/.035)
 # The lateral deltoid cap is smaller and flows down the upper sleeve.
 shrink=.024*zw*smooth((x-.175)/.09)
 newx=max(0,x-shrink)
 width=lerp_rows(z,rows,1)-.024*zw
 # Continue the outer chest monotonically toward the sleeve silhouette. This
 # fills the old 2–3cm front/back valley and removes the second bulging lobe.
 for front in [True,False]:
  if (p.y<0)!=front:continue
  old_d=depth(p.x,z,front)
  if old_d is None or old_d<.003:continue
  anchor=lerp_rows(z,rows,2+(0 if p.x<0 else 2)+(0 if front else 1))
  t=(newx-.14)/max(.055,width-.14)
  target=anchor*max(0,1-t)**.40
  lateral=smooth((x-.11)/.055)
  v.co.y=p.y*((1-zw*lateral)+zw*lateral*min(2.8,target/old_d))
 v.co.x=math.copysign(newx,p.x)
 # Round the high V-shaped underarm apex without moving elbows or wrists.
 pit=math.exp(-((x-.193)/.048)**2-((z-1.299)/.042)**2-(p.y/.068)**2)
 v.co.z-=.014*pit
# Fair the horizontal old stitch band over a broad area, including the front,
# back and underside. Shared vertices are sculpted once before object splitting.
for _ in range(90):
 updates={}
 for v in bm.verts:
  p=original[v];x=abs(p.x);z=p.z
  neck_radius=math.sqrt((p.x/.078)**2+((p.y-.007)/.080)**2)
  neck_mask=1-smooth((z-1.395)/.024)*(1-smooth((neck_radius-1.0)/.35))
  weight=smooth((z-1.18)/.075)*neck_mask
  if weight<=0:continue
  neighbours=[e.other_vert(v).co for e in v.link_edges]
  if not neighbours:continue
  average=sum(neighbours,Vector())/len(neighbours)
  q=v.co.lerp(average,.42*weight)
  updates[v]=q
 for v,q in updates.items():v.co=q
# Round the armpit corner across the actual joined topology, without pinning
# the artificial former object boundary to a vertical plane.
for _ in range(100):
 updates={}
 for v in bm.verts:
  p=original[v];x=abs(p.x);z=p.z
  weight=math.exp(-((x-.19)/.065)**2-((z-1.29)/.068)**2)*smooth((z-1.18)/.05)
  if weight<.015:continue
  neighbours=[e.other_vert(v).co for e in v.link_edges]
  average=sum(neighbours,Vector())/len(neighbours)
  updates[v]=v.co.lerp(average,.58*weight)
 for v,q in updates.items():v.co=q
# The Y-near-zero lateral silhouette cannot be solved by depth scaling:
# fit its X profile to neighbouring actual side surfaces, removing the narrow
# residual fin/ledge visible in the side view, without enlarging the cap.
side_bvh=BVHTree.FromBMesh(bm)
def side_x(y,z,side):
 hit=side_bvh.ray_cast(Vector((side*.6,y,z)),Vector((-side,0,0)),1.2)[0]
 return abs(hit.x) if hit is not None else None
side_profiles={}
for side in [-1,1]:
 raw=[]
 for step in range(171):
  z=1.31+step*.001
  near=[side_x(y,z,side) for y in [-.02,.02]]
  far=[side_x(y,z,side) for y in [-.04,.04]]
  if any(v is None for v in near+far):continue
  xn=sum(near)/2;xf=sum(far)/2
  curvature=max(0,(xn-xf)/(.04**2-.02**2))
  raw.append((z,xn+curvature*.02**2,curvature))
 # Uniform 1mm profile samples avoid mesh-density bias. Smooth in height
 # before projection so the former roof step cannot survive as an oval ledge.
 rows_side=[]
 for row in raw:
  samples=[(r,math.exp(-.5*((r[0]-row[0])/.008)**2)) for r in raw if abs(r[0]-row[0])<=.024]
  total=sum(w for r,w in samples)
  rows_side.append((row[0],*[sum(r[c]*w for r,w in samples)/total for c in [1,2]]))
 side_profiles[side]=rows_side
for v in bm.verts:
 p=v.co.copy();x=abs(p.x);y=abs(p.y);z=p.z
 if x<.12 or y>.05 or z<1.33 or z>1.47:continue
 side=1 if p.x>0 else -1;rows_side=side_profiles[side]
 target=lerp_rows(z,rows_side,1)-lerp_rows(z,rows_side,2)*p.y**2
 weight=smooth((z-1.33)/.040)*(1-smooth((z-1.445)/.025))*(1-smooth((y-.025)/.025))*smooth((x-.12)/.025)
 # Signed blending avoids a new crease where inward-only clipping stopped.
 v.co.x=math.copysign(x+(target-x)*weight,p.x)
cloth=bpy.data.materials['Gravebound_Matched_Sleeve_Cloth']
# One continuous cloth mapping removes the old circumferential shoulder stripe.
# Preserve original cuff skin and every original bitmap/material setting.
for face in bm.faces:
 if materials[face.material_index]!=cloth:continue
 for loop in face.loops:
  p=loop.vert.co;loop[uv].uv=(.32+p.x*.65,.12+(p.z-.98)*.5+p.y*.3)
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
for f in bm.faces:f.smooth=True
bm.normal_update()
for index,name in enumerate(NAMES):
 faces=[f for f in bm.faces if f[part]==index];verts=list({v for f in faces for v in f.verts});ids={v:i for i,v in enumerate(verts)}
 obj=bpy.data.objects[name];inv=obj.matrix_world.inverted();mesh=bpy.data.meshes.new(name+'_SculptedShoulderFlow')
 mesh.from_pydata([inv@v.co for v in verts],[],[[ids[v] for v in f.verts] for f in faces]);mesh.update()
 for m in materials:mesh.materials.append(m)
 layer=mesh.uv_layers.new(name='UVMap');normals=[]
 for poly,face in zip(mesh.polygons,faces):
  poly.use_smooth=True;poly.material_index=face.material_index
  for li,l in zip(poly.loop_indices,face.loops):
   layer.data[li].uv=l[uv].uv;normals.append((inv.to_3x3()@l.vert.normal).normalized())
 mesh.normals_split_custom_set(normals);obj.data=mesh
 obj['shoulder_revision']='Reduced lateral cap, continuous chest/back-to-arm surface and rounded underarm; coherent cloth mapping'
bm.free()
assert preserved=={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in NAMES}
bpy.data.orphans_purge(do_recursive=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Shoulder_Form.blend'),compress=True)
tmp=W/'shoulder_form.tmp.glb';out=W/'gravebound_player_shoulder_form.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes();assert data[:4]==b'glTF' and struct.unpack_from('<I',data,8)[0]==len(data);tmp.replace(out);shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report={'source':str(SOURCE.relative_to(ROOT)),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(data).hexdigest(),'modified_meshes':NAMES,'preserved_meshes':preserved,'preserved_mesh_count':len(preserved),'geometry_preserved_below_m':1.18,'cloth_mapping':'Continuous projection; existing bitmaps and material settings retained; cuff skin untouched','pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2)+'\n');print('SHOULDER FORM BUILD PASS',report['output_sha256'],flush=True)
