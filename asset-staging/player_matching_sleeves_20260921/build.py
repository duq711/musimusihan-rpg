"""Grade sleeve cloth to match the outfit; preserve UVs and all geometry."""
import bpy,json,hashlib
from pathlib import Path
from mathutils import Vector
W=Path(__file__).resolve().parent;ROOT=W.parents[1]
SOURCE=ROOT/'asset-staging/player_relaxed_elbows_20260921/Gravebound_FP_Arms.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original_objects=list(bpy.data.objects)
def signature(o):return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices],'f':[list(f.vertices) for f in o.data.polygons],'m':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
before={o.name:signature(o) for o in original_objects if o.type=='MESH'}
# Preserve existing UV layout and weave; grade a separate cloth-only albedo.
report={}
matched=None
for obj in original_objects:
 if not obj.name.startswith('Gravebound_FP_') or not obj.name.endswith('_Arm'):continue
 mesh=obj.data
 image=next(n.image for n in mesh.materials[0].node_tree.nodes if n.type=='TEX_IMAGE' and 'albedo' in n.image.name.lower());pix=list(image.pixels);iw,ih=image.size
 parent=list(range(len(mesh.vertices)))
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for e in mesh.edges:
  a,b=map(find,e.vertices);parent[a]=b
 groups={}
 for f in mesh.polygons:groups.setdefault(find(f.vertices[0]),[]).append(f)
 skin=set()
 for faces in groups.values():
  maxz=max(mesh.vertices[i].co.z for f in faces for i in f.vertices)
  if maxz>.93:continue
  values=[]
  for f in faces:
   uv=sum((mesh.uv_layers.active.data[i].uv for i in f.loop_indices),Vector((0,0)))/len(f.loop_indices)
   x=max(0,min(iw-1,int(uv.x*iw)));y=max(0,min(ih-1,int(uv.y*ih)));values.append(pix[(y*iw+x)*4])
  if sorted(values)[len(values)//2]>.55:skin.update(f.index for f in faces)
 assert skin,('Skin classification missing',obj.name)
 saved_skin={f.index:[list(mesh.uv_layers.active.data[i].uv) for i in f.loop_indices] for f in mesh.polygons if f.index in skin}
 if matched is None:
  matched=mesh.materials[0].copy();matched.name='Gravebound_Matched_Sleeve_Cloth'
  node=next(n for n in matched.node_tree.nodes if n.type=='TEX_IMAGE' and 'albedo' in n.image.name.lower())
  graded=bpy.data.images.new('Gravebound_Matched_Sleeve_Albedo',width=iw,height=ih,alpha=True)
  import numpy as np
  pixels=np.array(pix,dtype=np.float32).reshape(-1,4)
  luminance=pixels[:,:3]@np.array([.2126,.7152,.0722])
  pixels[:,:3]=.72*(pixels[:,:3]*.2+luminance[:,None]*.8)
  graded.pixels.foreach_set(pixels.ravel());graded.pack();node.image=graded
  principled=next(n for n in matched.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
  # Match the matte cloth response of the torso while retaining original normal detail.
  for socket in ('Roughness','Metallic'):
   for link in list(principled.inputs[socket].links):matched.node_tree.links.remove(link)
  principled.inputs['Roughness'].default_value=.9
  principled.inputs['Metallic'].default_value=0
  principled.inputs['Specular IOR Level'].default_value=.32
 slot=len(mesh.materials);mesh.materials.append(matched)
 for f in mesh.polygons:
  if f.index not in skin:f.material_index=slot
 for f in mesh.polygons:
  if f.index in skin:assert saved_skin[f.index]==[list(mesh.uv_layers.active.data[i].uv) for i in f.loop_indices]
 report[obj.name]={'cloth_faces':len(mesh.polygons)-len(skin),'preserved_skin_faces':len(skin),'material':matched.name,'uvs_unchanged':True,'albedo_brightness':.72,'albedo_desaturation':.8}
assert before=={o.name:signature(o) for o in original_objects if o.type=='MESH'}
bpy.ops.object.select_all(action='DESELECT')
for o in original_objects:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.data.orphans_purge(do_recursive=True)
for im in bpy.data.images:
 if im.source=='FILE' and im.has_data:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Matching_Sleeves.blend'),compress=True)
out=W/'gravebound_player_matching_sleeves.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
(W/'build_report.json').write_text(json.dumps({'parts':report,'geometry_signatures':before,'all_geometry_unchanged':True,'source_blend_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'output_sha256':hashlib.sha256(out.read_bytes()).hexdigest()},indent=2))
print('MATCHED SLEEVE MATERIALS PASS',report)
