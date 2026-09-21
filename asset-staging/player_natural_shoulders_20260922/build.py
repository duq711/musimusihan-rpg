"""Rebuild the exposed neckline and shoulder junction as a continuous garment."""
from pathlib import Path
import bpy,bmesh,math,json,hashlib,struct,shutil
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=W.parent/'player_cowl_removed_20260922/Gravebound_No_Cowl.blend'
NAMES=['Gravebound_QuiltedTorso','Gravebound_FP_L_Arm','Gravebound_FP_R_Arm']
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
def sig(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(p.vertices) for p in o.data.polygons],'uv':[[list(u.uv) for u in l.data] for l in o.data.uv_layers],'world':[list(r) for r in o.matrix_world],'materials':[m.name for m in o.data.materials]},sort_keys=True).encode()).hexdigest()
preserved={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in NAMES}
def smooth(t):t=max(0,min(1,t));return t*t*(3-2*t)
def interp(z,rows,col):
 if z<=rows[0][0]:return rows[0][col]
 for a,b in zip(rows,rows[1:]):
  if z<=b[0]:
   t=(z-a[0])/(b[0]-a[0]);return a[col]*(1-t)+b[col]*t
 return rows[-1][col]
originals={};materials=[]
for name in NAMES:
 o=bpy.data.objects[name];me=o.data;me.calc_loop_triangles()
 coords=[o.matrix_world@v.co for v in me.vertices]
 tris=[tuple(t.vertices) for t in me.loop_triangles]
 uv=[[me.uv_layers.active.data[i].uv.copy() for i in t.loops] for t in me.loop_triangles]
 for m in me.materials:
  if m not in materials:materials.append(m)
 mids=[materials.index(me.materials[t.material_index]) for t in me.loop_triangles]
 edges=[tuple(e.vertices) for e in me.edges]
 rows=[]
 for j in range(180):
  z=1.24+j*(1.48-1.24)/179;pts=[]
  for a,b in edges:
   va,vb=coords[a],coords[b]
   if (va.z-z)*(vb.z-z)<=0 and abs(vb.z-va.z)>1e-8:pts.append(va.lerp(vb,(z-va.z)/(vb.z-va.z)))
  if len(pts)<4:continue
  bounds=[(min(p[k] for p in pts),max(p[k] for p in pts)) for k in (0,1)]
  rows.append((z,*(sum(b)*.5 for b in bounds),*((b[1]-b[0])*.5 for b in bounds)))
 originals[name]={'coords':coords,'tris':tris,'uv':uv,'mids':mids,'bvh':BVHTree.FromPolygons(coords,tris,all_triangles=True),'rows':rows}

def getuv(name,p):
 d=originals[name];hit,normal,idx,dist=d['bvh'].find_nearest(p)
 a,b,c=[d['coords'][i] for i in d['tris'][idx]];uv=d['uv'][idx]
 q=barycentric_transform(hit,a,b,c,Vector((*uv[0],0)),Vector((*uv[1],0)),Vector((*uv[2],0)))
 return q.xy,d['mids'][idx]

# Sculpt the upper trunk from the chest into a narrow, sloping neckline.
torso_profile=[(1.27,.171,.145),(1.30,.177,.139),(1.34,.192,.127),(1.38,.196,.111),(1.41,.184,.091),(1.435,.145,.076),(1.46,.073,.069),(1.477,.062,.063)]
arm_profile=[(1.26,.243,.002,.061,.056),(1.29,.239,.002,.060,.064),(1.33,.229,.002,.062,.075),(1.365,.216,.002,.057,.074),(1.395,.207,.002,.052,.069),(1.415,.202,.002,.046,.062),(1.435,.197,.002,.013,.021),(1.4431,.195,.002,.006,.010)]
upper=bmesh.new()
for name in NAMES:
 obj=bpy.data.objects[name];bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.transform(bm,matrix=obj.matrix_world,verts=list(bm.verts))
 for v in bm.verts:
  p=v.co.copy();z=p.z
  if z<1.26:continue
  rows=originals[name]['rows'];cx=interp(z,rows,1);cy=interp(z,rows,2);rx=max(.002,interp(z,rows,3));ry=max(.002,interp(z,rows,4))
  if name==NAMES[0]:
   v.co.x=(p.x-cx)/rx*interp(z,torso_profile,1)
   v.co.y=(p.y-cy)/ry*interp(z,torso_profile,2)
  else:
   side=-1 if '_L_' in name else 1
   v.co.x=side*interp(z,arm_profile,1)+(p.x-cx)/rx*interp(z,arm_profile,3)
   v.co.y=interp(z,arm_profile,2)+(p.y-cy)/ry*interp(z,arm_profile,4)
   v.co.z=z-.012*smooth((z-1.365)/.078)
 bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-5)
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,1.255),plane_no=(0,0,1),clear_inner=True)
 bmesh.ops.holes_fill(bm,edges=[e for e in bm.edges if e.is_boundary],sides=0)
 bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
 vm={v:upper.verts.new(v.co) for v in bm.verts}
 for f in bm.faces:upper.faces.new([vm[v] for v in f.verts])
 bm.free()
me=bpy.data.meshes.new('ShoulderUnion');upper.to_mesh(me);upper.free()
o=bpy.data.objects.new('ShoulderUnion',me);bpy.context.scene.collection.objects.link(o)
bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
rem=o.modifiers.new('ContinuousShoulderSurface','REMESH');rem.mode='VOXEL';rem.voxel_size=.0025;rem.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=rem.name)
bm=bmesh.new();bm.from_mesh(o.data)
for _ in range(9):
 bmesh.ops.smooth_vert(bm,verts=[v for v in bm.verts if v.co.z>1.285],factor=.48,use_axis_x=True,use_axis_y=True,use_axis_z=True)
# Fair the shoulder union over a broader area; preserve the lower cut and neck.
shoulder_verts=[v for v in bm.verts if abs(v.co.x)>.115 and v.co.z>1.305]
for _ in range(65):
 bmesh.ops.smooth_vert(bm,verts=shoulder_verts,factor=.55,use_axis_x=True,use_axis_y=True,use_axis_z=True)
# A monotonic shoulder roof prevents a second peak at each sleeve crown.
roof=[(.075,1.468),(.10,1.458),(.14,1.444),(.18,1.430),(.21,1.418),(.24,1.399),(.265,1.368),(.285,1.335)]
current=[]
for i in range(106):
 x=.075+i*.002;heights=[]
 for e in bm.edges:
  a,b=e.verts[0].co,e.verts[1].co
  if max(a.z,b.z)<1.30 or (a.x-x)*(b.x-x)>0 or abs(b.x-a.x)<1e-8:continue
  heights.append(a.z+(b.z-a.z)*(x-a.x)/(b.x-a.x))
 if heights:current.append((x,max(heights)))
for v in bm.verts:
 x=abs(v.co.x);z=v.co.z
 if x<.095 or z<1.34:continue
 oldtop=interp(x,current,1);newtop=interp(x,roof,1)
 weight=smooth((z-1.34)/max(.035,oldtop-1.34))*smooth((x-.095)/.025)
 v.co.z+=(newtop-oldtop)*weight
bm.to_mesh(o.data);bm.free()
# Cut a true neck opening. The hidden bottom is below the donor neck's end.
bpy.ops.mesh.primitive_cylinder_add(vertices=96,radius=1,depth=1,location=(0,.007,1.93))
cut=bpy.context.object;cut.name='NeckOpeningTool';cut.scale=(.0635,.064,1.0)
bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
bpy.context.view_layer.objects.active=o
boolean=o.modifiers.new('TrueNeckOpening','BOOLEAN');boolean.operation='DIFFERENCE';boolean.solver='EXACT';boolean.object=cut
bpy.ops.object.modifier_apply(modifier=boolean.name);bpy.data.objects.remove(cut,do_unlink=True)
# Trim above the unchanged cuffs/lower sleeves and torso, then stitch the three rings.
bm=bmesh.new();bm.from_mesh(o.data)
for v in bm.verts:
 p=v.co;rho=math.sqrt((p.x/.0635)**2+((p.y-.007)/.064)**2)
 if p.z>1.443 and .99<=rho<1.5:
  edge_height=1.465-.010*((p.y-.007)/.064)/rho
  weight=1-smooth((rho-1)/.5)
  p.z=p.z*(1-weight)+edge_height*weight
bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,1.285),plane_no=(0,0,1),clear_inner=True)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
for sx in [-.175,.175]:
 bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(sx,0,0),plane_no=(1,0,0))
uvlayer=bm.loops.layers.uv.verify();partlayer=bm.faces.layers.int.new('part')
# Use a continuous weave region from the existing sleeve atlas on the new yoke.
# This is a UV/material reassignment, with all original bitmap files unchanged.
cloth=bpy.data.materials['Gravebound_Matched_Sleeve_Cloth']
for n in cloth.node_tree.nodes:
 if n.type=='NORMAL_MAP':n.inputs['Strength'].default_value=.25
cloth_index=materials.index(cloth)
for f in bm.faces:
 c=f.calc_center_median();part=0 if abs(c.x)<.175 else (1 if c.x<0 else 2)
 f[partlayer]=part;f.material_index=cloth_index
 for loop in f.loops:
  p=loop.vert.co
  loop[uvlayer].uv=(.32+p.x*.65,.12+(p.z-.98)*.5+p.y*.3)

# Boundary ordering uses edges, not cap triangulation or vertex insertion order.
def loops_at(bm,z):
 edges={e for e in bm.edges if e.is_boundary and all(abs(v.co.z-z)<1e-4 for v in e.verts)};result=[]
 while edges:
  e=edges.pop();ring=[e.verts[0],e.verts[1]]
  while True:
   nxt=next((x for x in ring[-1].link_edges if x in edges),None)
   if nxt is None:break
   edges.remove(nxt);v=nxt.other_vert(ring[-1])
   if v==ring[0]:break
   ring.append(v)
  result.append(ring)
 return result
upperrings=loops_at(bm,1.285)
print('CUT RINGS',[(len(r),[sum(v.co[i] for v in r)/len(r) for i in range(3)]) for r in upperrings],flush=True)
assert len(upperrings)==3,len(upperrings)
upperrings.sort(key=lambda r:sum(v.co.x for v in r)/len(r))
ring_for={NAMES[1]:upperrings[0],NAMES[0]:upperrings[1],NAMES[2]:upperrings[2]}
for part,name in enumerate(NAMES):
 obj=bpy.data.objects[name];low=bmesh.new();low.from_mesh(obj.data);bmesh.ops.transform(low,matrix=obj.matrix_world,verts=list(low.verts))
 bmesh.ops.bisect_plane(low,geom=list(low.verts)+list(low.edges)+list(low.faces),dist=1e-6,plane_co=(0,0,1.27),plane_no=(0,0,1),clear_outer=True)
 bmesh.ops.remove_doubles(low,verts=[v for v in low.verts if abs(v.co.z-1.27)<1e-4],dist=1e-5)
 rings=loops_at(low,1.27);assert len(rings)==1,(name,len(rings))
 vm={v:bm.verts.new(v.co) for v in low.verts};luv=low.loops.layers.uv.active
 for face in low.faces:
  f=bm.faces.new([vm[v] for v in face.verts]);f[partlayer]=part;f.material_index=materials.index(obj.data.materials[face.material_index])
  for a,b in zip(f.loops,face.loops):a[uvlayer].uv=b[luv].uv
 a=[vm[v] for v in rings[0]];b=ring_for[name]
 cx=sum(v.co.x for v in a)/len(a);cy=sum(v.co.y for v in a)/len(a)
 def ordered(r):return sorted(r,key=lambda v:math.atan2(v.co.y-cy,v.co.x-cx))
 a=ordered(a);b=ordered(b)
 def angle(v):return math.atan2(v.co.y-cy,v.co.x-cx)
 i=j=0
 while i<len(a) or j<len(b):
  ai=a[i%len(a)];bj=b[j%len(b)]
  an=angle(a[(i+1)%len(a)])+(2*math.pi if i+1>=len(a) else 0) if i<len(a) else 1e9
  bn=angle(b[(j+1)%len(b)])+(2*math.pi if j+1>=len(b) else 0) if j<len(b) else 1e9
  if an<bn:points=[ai,a[(i+1)%len(a)],bj];i+=1
  else:points=[ai,b[(j+1)%len(b)],bj];j+=1
  f=bm.faces.new(points);f[partlayer]=part
  for loop in f.loops:
   uv,mi=getuv(name,loop.vert.co);loop[uvlayer].uv=uv;f.material_index=mi
 low.free()
# Continue the same woven panel through the torso to avoid a cape-like mid-chest edge.
for f in bm.faces:
 if f[partlayer]==0:
  f.material_index=cloth_index
  for loop in f.loops:
   p=loop.vert.co;loop[uvlayer].uv=(.32+p.x*.65,.12+(p.z-.98)*.5+p.y*.3)
bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
blend_band=[v for v in bm.verts if 1.245<v.co.z<1.315]
for _ in range(24):
 bmesh.ops.smooth_vert(bm,verts=blend_band,factor=.45,use_axis_x=True,use_axis_y=True,use_axis_z=True)
bmesh.ops.triangulate(bm,faces=list(bm.faces))
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
for f in bm.faces:f.smooth=True
bm.normal_update()
# Shared normals survive the object split, so shoulder seams do not shade as stumps.
for part,name in enumerate(NAMES):
 faces=[f for f in bm.faces if f[partlayer]==part];verts=list({v for f in faces for v in f.verts});index={v:i for i,v in enumerate(verts)}
 obj=bpy.data.objects[name];inv=obj.matrix_world.inverted();mesh=bpy.data.meshes.new(name+'_AnatomicalJoin')
 mesh.from_pydata([inv@v.co for v in verts],[],[[index[v] for v in f.verts] for f in faces]);mesh.update()
 for m in materials:mesh.materials.append(m)
 uv=mesh.uv_layers.new(name='UVMap');normals=[]
 for p,f in zip(mesh.polygons,faces):
  p.use_smooth=True;p.material_index=f.material_index
  for li,l in zip(p.loop_indices,f.loops):
   uv.data[li].uv=l[uvlayer].uv;normals.append((inv.to_3x3()@l.vert.normal).normalized())
 mesh.normals_split_custom_set(normals);obj.data=mesh
 obj['anatomical_join']='Continuous chest, sloped shoulders and true neck opening; preserved lower sleeve/cuff'
bm.free();bpy.data.objects.remove(o,do_unlink=True)
assert preserved=={o.name:sig(o) for o in bpy.context.scene.objects if o.type=='MESH' and o.name not in NAMES}
bpy.data.orphans_purge(do_recursive=True);bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Natural_Shoulders.blend'),compress=True)
tmp=W/'shoulders.tmp.glb';out=W/'gravebound_player_natural_shoulders.glb'
bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
data=tmp.read_bytes();assert struct.unpack_from('<I',data,8)[0]==len(data);tmp.replace(out)
shutil.copy2(out,ROOT/'godot-game/assets/3d/player/gravebound_player.glb')
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(data).hexdigest(),'preserved_meshes':preserved,'modified_meshes':NAMES,'neck_opening_radii_m':[.0635,.064],'shoulder_root_depth_m':.156,'lower_geometry_preserved_below_m':1.24,'pass':True}
(W/'build_report.json').write_text(json.dumps(report,indent=2)+'\n');print('NATURAL SHOULDERS BUILD PASS',report['output_sha256'])
