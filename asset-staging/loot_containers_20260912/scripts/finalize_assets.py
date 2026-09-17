import bpy,json,hashlib,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
BASE=Path(__file__).resolve().parents[1];OUT=BASE.parents[1]/'godot-game/assets/models/loot_containers';report=json.loads((BASE/'runtime_manifest.json').read_text())
def g(v):return [round(v.x,6),round(v.z,6),round(-v.y,6)]
for rec in report['assets']:
 name=rec['variant'];path=BASE/'normalized'/(name+'.blend');bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False,use_scripts=False)
 root=next(o for o in bpy.context.scene.objects if o.type=='EMPTY' and o.parent is None);root.name=name;lid=bpy.data.objects['LidPivot'];root['hinge_mode']=rec['opening_mode'];root['lid_open_degrees']=68.0;root['lift_distance_m']=.32 if rec['opening_mode']=='lift' else 0.0
 # Data maps use 8-bit PNG. Scalar maps at 1K, base color and tangent normal at 2K.
 for m in bpy.data.materials:
  if not m.use_nodes:continue
  for n in m.node_tree.nodes:
   if n.type!='TEX_IMAGE' or not n.image:continue
   old=n.image;target=Path(old.filepath);channel=target.stem
   if channel=='base_color':continue
   dim=2048 if channel=='normal' else 1024
   if tuple(old.size)!=(dim,dim):old.scale(dim,dim)
   fresh=bpy.data.images.new(name+'_'+channel+'_runtime',width=dim,height=dim,alpha=False,float_buffer=False);fresh.colorspace_settings.name='Non-Color'
   pixels=np.empty(dim*dim*4,dtype=np.float32);old.pixels.foreach_get(pixels);fresh.pixels.foreach_set(pixels)
   fresh.file_format='PNG';fresh.filepath_raw=str(target);fresh.save();n.image=fresh
   for t in rec['textures']:
    if t['channel']==channel:t.update(size=[dim,dim],bytes=target.stat().st_size,bit_depth=8)
 objs=[o for o in bpy.context.scene.objects if o.type=='MESH']
 for o in objs:
  bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
  tri=o.modifiers.new('ExportTriangles','TRIANGULATE');tri.keep_custom_normals=True;bpy.ops.object.modifier_apply(modifier=tri.name)
 # Recenter after topology optimization without changing opening hierarchy.
 bpy.context.view_layer.update();vs=[o.matrix_world@v.co for o in objs for v in o.data.vertices];lo=Vector([min(v[k] for v in vs) for k in range(3)]);hi=Vector([max(v[k] for v in vs) for k in range(3)]);shift=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
 for o in objs:
  if o.parent==lid:continue
  o.data.transform(Matrix.Translation(-shift))
 lid.location-=shift;bpy.context.view_layer.update()
 rec['bounds_min']=[round(lo.x-shift.x,6),0.0,round(-hi.y+shift.y,6)];rec['bounds_max']=[round(hi.x-shift.x,6),round(hi.z-shift.z,6),round(-lo.y+shift.y,6)];rec['lid_pivot']=g(lid.location);rec['hinge_open_angle_degrees']=68 if rec['opening_mode']=='hinge' else 0
 # Contacts on the actual top surface of Lid, using vertical ray intersection.
 lm=bpy.data.objects['Lid'];vertices=[lm.matrix_world@v.co for v in lm.data.vertices];polys=[list(p.vertices) for p in lm.data.polygons];tree=BVHTree.FromPolygons(vertices,polys,all_triangles=True)
 for contact in rec['contacts']:
  marker=bpy.data.objects[contact['name']];position=marker.matrix_world.translation;hit,normal,index,distance=tree.ray_cast(Vector((position.x,position.y,3)),Vector((0,0,-1)))
  assert hit is not None,(name,contact['name'],tuple(position))
  marker.location=lid.matrix_world.inverted()@hit;contact['closed_position']=g(hit);contact['local_position']=g(marker.location);contact['surface_distance_m']=0.0
 # Retain only actively used textures.
 used={n.image for m in bpy.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
 for im in list(bpy.data.images):
  if im not in used:bpy.data.images.remove(im)
 bpy.context.scene.render.image_settings.color_depth='8'
 bpy.ops.wm.save_as_mainfile(filepath=str(path))
 bpy.ops.object.select_all(action='SELECT');dest=OUT/(name+'.glb')
 bpy.ops.export_scene.gltf(filepath=str(dest),export_format='GLB',use_selection=True,export_animations=False,export_yup=True,export_apply=True,export_extras=True,export_image_format='AUTO',export_jpeg_quality=90,export_materials='EXPORT',export_texcoords=True,export_normals=True,export_tangents=True)
 rec['glb_bytes']=dest.stat().st_size;rec['sha256']=hashlib.sha256(dest.read_bytes()).hexdigest();rec['runtime_triangles']=sum(len(o.data.polygons) for o in objs)
 print('FINAL',name,rec['glb_bytes'],rec['runtime_triangles'],flush=True)
 (BASE/'runtime_manifest.json').write_text(json.dumps(report,indent=2));(OUT/'manifest.json').write_text(json.dumps(report,indent=2))
