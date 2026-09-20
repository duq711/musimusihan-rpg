"""Rebuild only the hood as a sealed cloth shell with a smooth rounded crown."""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=ROOT/'asset-staging/player_inward_palms_20260921/Gravebound_Inward_Palms.blend'
S=1.78/1392;N=96
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
obj=bpy.data.objects['Gravebound_PointHood'];objects=list(bpy.data.objects)
def signature(o):return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(p.vertices) for p in o.data.polygons],'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers],'m':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
before={o.name:signature(o) for o in objects if o.type=='MESH' and o!=obj}
# Dome crown: no tiny open ring, no radius inversion, broad cloth curvature.
rows=[]
for j in range(1,13):
 t=math.pi*.5*j/12
 rows.append((1.702+.082*math.cos(t),.0806*math.sin(t),0,.092*math.sin(t),.005+.014*math.cos(t)))
original=[(123,63,0,.092,.005),(143,70,12,.105,-.007),(169,77,32,.111,-.01),(200,84,44,.119,-.013),(230,91,54,.127,-.015),(258,99,67,.132,-.012),(280,103,64,.131,-.005),(299,94,35,.126,.003),(315,69,2,.106,.009)]
# Preserve the authored face-opening profile and lower neck fit.
for a,b in zip(original,original[1:]):
 for j in range(1,7):
  t=j/6;py,rx,opening,dep,cy=[x+(y-x)*t for x,y in zip(a,b)]
  rows.append(((1454-py)*S,rx*S,opening*S,dep,cy))
verts=[(0,.019,1.784)];rings=[];faces=[]
for z,rx,opening,dep,cy in rows:
 angle=math.asin(min(.96,opening/rx));closed=opening<1e-8
 ring=[]
 for k in range(N if closed else N+1):
  a=angle+(math.tau-2*angle)*k/N
  # Restrained long folds fade completely before the crown.
  fade=max(0.,min(1.,(1.705-z)/.14))
  wrinkle=.0016*fade*(math.sin(5*a+.4)+.3*math.sin(9*a))
  # Keep the scalp under the 4 mm lining at the brow; the source head is
  # slightly proud of the old front profile and must not pierce the new cloth.
  brow_t=abs(z-1.70)/.06
  brow=.014*(.5+.5*math.cos(math.pi*brow_t)) if brow_t<1 else 0.
  front_clearance=brow*max(0.,math.cos(a))**2
  ring.append(len(verts));verts.append(((rx+wrinkle)*math.sin(a),cy-(dep+wrinkle)*math.cos(a)-front_clearance,z))
 rings.append(ring)
for k in range(N):faces.append((0,rings[0][(k+1)%N],rings[0][k]))
for upper,lower in zip(rings,rings[1:]):
 for k in range(N):faces.append((upper[k],upper[(k+1)%len(upper)],lower[(k+1)%len(lower)],lower[k]))
mesh=bpy.data.meshes.new('Gravebound_Rebuilt_Hood');mesh.from_pydata(verts,[],faces);mesh.update();obj.data=mesh
bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
for p in mesh.polygons:p.use_smooth=True
bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
outer=bpy.data.materials.new('HoodProjectionBake');outer.use_nodes=True
inner=bpy.data.materials.new('HoodLiningBake');inner.use_nodes=True
mesh.materials.clear();mesh.materials.append(outer);mesh.materials.append(inner)
solid=obj.modifiers.new('TailoredClothThickness','SOLIDIFY');solid.thickness=.004;solid.offset=-1;solid.use_even_offset=True;solid.material_offset=1;solid.material_offset_rim=0
bpy.ops.object.modifier_apply(modifier=solid.name)
mesh=obj.data
# Seamless cloth from a clean mantle area of the preserved outfit concept.
# Box projection keeps fiber scale continuous across the dome and avoids
# the former front/side projection collapsing into stripes at the crown.
import numpy as np
back=bpy.data.images.load(str(ROOT/'concept-art/player_gravebound/concept_back.png'),check_existing=True)
raw=np.array(back.pixels[:],dtype=np.float32).reshape(back.size[1],back.size[0],4)
x0,y0,x1,y1=438,320,590,390
patch=raw[back.size[1]-y1:back.size[1]-y0,x0:x1].copy()
row=np.concatenate([patch,patch[:,::-1]],axis=1);tile=np.concatenate([row,row[::-1]],axis=0)
cloth=bpy.data.images.new('Hood_Seamless_Cloth_Source',width=tile.shape[1],height=tile.shape[0],alpha=False)
cloth.pixels.foreach_set(tile.ravel());cloth.pack()
nt=outer.node_tree;nt.nodes.clear();out=nt.nodes.new('ShaderNodeOutputMaterial');em=nt.nodes.new('ShaderNodeEmission');nt.links.new(em.outputs[0],out.inputs['Surface'])
coord=nt.nodes.new('ShaderNodeTexCoord');scale=nt.nodes.new('ShaderNodeVectorMath');scale.operation='MULTIPLY';scale.inputs[1].default_value=(2.2,2.2,2.2);nt.links.new(coord.outputs['Generated'],scale.inputs[0])
tex=nt.nodes.new('ShaderNodeTexImage');tex.image=cloth;tex.projection='BOX';tex.projection_blend=.35;tex.extension='REPEAT';nt.links.new(scale.outputs[0],tex.inputs['Vector']);nt.links.new(tex.outputs['Color'],em.inputs['Color'])
nt=inner.node_tree;nt.nodes.clear();out=nt.nodes.new('ShaderNodeOutputMaterial');em=nt.nodes.new('ShaderNodeEmission');em.inputs[0].default_value=(.010,.011,.013,1);nt.links.new(em.outputs[0],out.inputs['Surface'])
atlas_uv=mesh.uv_layers.new(name='HoodAtlas');mesh.uv_layers.active=atlas_uv;atlas_uv.active_render=True
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(angle_limit=1.12,island_margin=.025,area_weight=.5);bpy.ops.object.mode_set(mode='OBJECT')
atlas=bpy.data.images.new('Gravebound_Rebuilt_Hood_Albedo',width=2048,height=2048,alpha=False)
for mat in (outer,inner):
 node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=atlas;mat.node_tree.nodes.active=node
# Bake normals/projections in authored local coordinates, then restore world pose.
parent=obj.parent;world=obj.matrix_world.copy();obj.parent=None;obj.matrix_world=Matrix.Identity(4)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.use_clear=True;scene.render.bake.margin=12;scene.render.bake.use_selected_to_active=False
bpy.ops.object.bake(type='EMIT');obj.parent=parent;obj.matrix_world=world
atlas.filepath_raw=str(W/'Gravebound_Rebuilt_Hood_Albedo.png');atlas.file_format='PNG';atlas.save();atlas.pack()
mat=bpy.data.materials.new('Gravebound_Rebuilt_Hood_Cloth');mat.use_nodes=True;p=mat.node_tree.nodes.get('Principled BSDF');p.inputs['Roughness'].default_value=.92;p.inputs['Specular IOR Level'].default_value=.25
node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=atlas;mat.node_tree.links.new(node.outputs['Color'],p.inputs['Base Color'])
mesh.materials.clear();mesh.materials.append(mat)
for f in mesh.polygons:f.material_index=0;f.use_smooth=True
for layer in list(mesh.uv_layers):
 if layer.name!='HoodAtlas':mesh.uv_layers.remove(layer)
mesh.uv_layers.active_index=0;mesh.uv_layers[0].active_render=True
# Audit the actual closed shell and crown rays, not just absence of open edges.
bm=bmesh.new();bm.from_mesh(mesh);boundary=sum(e.is_boundary for e in bm.edges);nonmanifold=sum(not e.is_manifold for e in bm.edges);bm.free();assert boundary==0 and nonmanifold==0,(boundary,nonmanifold)
mesh.calc_loop_triangles();bvh=BVHTree.FromPolygons([v.co for v in mesh.vertices],[tuple(t.vertices) for t in mesh.loop_triangles],all_triangles=True)
hits=[]
for i in range(21):
 for j in range(21):
  x=-.05+i*.005;y=.019-.05+j*.005
  hit,normal,index,d=bvh.ray_cast(Vector((x,y,1.95)),Vector((0,0,-1)),.5)
  assert hit is not None and hit.z>1.70 and normal.z>.25,('Crown ray failed',x,y,hit,normal)
  hits.append(normal.z)
assert before=={o.name:signature(o) for o in objects if o.type=='MESH' and o!=obj}
bpy.ops.object.select_all(action='DESELECT')
for o in objects:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer'];bpy.data.orphans_purge(do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Rebuilt_Hood.blend'),compress=True)
out=W/'gravebound_player_rebuilt_hood.glb';bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'other_27_meshes_unchanged':True,'hood_vertices':len(mesh.vertices),'hood_triangles':len(mesh.loop_triangles),'boundary_edges':boundary,'nonmanifold_edges':nonmanifold,'crown_ray_count':len(hits),'crown_minimum_upward_normal':min(hits),'shell_thickness_m':.004,'crown_design':'closed rounded crown; restrained lower folds; dark inner lining','cloth_source_crop':[438,320,590,390],'cloth_mapping':'mirrored seamless cloth patch; blended box projection'}
(W/'build_report.json').write_text(json.dumps(report,indent=2));print('REBUILT HOOD PASS',json.dumps(report))
