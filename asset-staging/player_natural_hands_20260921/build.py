"""Mac Blender: natural full-body hand pose and separately graded skin texture."""
import bpy, json, hashlib, sys
import numpy as np
from pathlib import Path
W=Path(__file__).resolve().parent; ROOT=W.parents[1]
SOURCE=ROOT/'asset-staging/player_matching_sleeves_20260921/Gravebound_Matching_Sleeves.blend'
sys.path.insert(0,str(W))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def signature(o):
 return hashlib.sha256(json.dumps({'v':[list(v.co) for v in o.data.vertices], 'f':[list(f.vertices) for f in o.data.polygons], 'uv':[[list(p.uv) for p in l.data] for l in o.data.uv_layers], 'm':[list(r) for r in o.matrix_world]},sort_keys=True).encode()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
original=list(bpy.data.objects)
unchanged={o.name:signature(o) for o in original if o.type=='MESH' and not o.name.endswith('_Hand')}
# Grade only bright skin texels in a copy. The original leather, seams, cloth,
# source first-person assets and their roughness/normal maps are preserved.
source_mat=bpy.data.objects['Gravebound_FP_L_Hand'].data.materials[0]
image_node=next(n for n in source_mat.node_tree.nodes if n.type=='TEX_IMAGE' and 'albedo' in n.image.name.lower())
source=image_node.image; iw,ih=source.size
pixels=np.empty(iw*ih*4,dtype=np.float32);source.pixels.foreach_get(pixels);pixels=pixels.reshape(-1,4)
rgb=pixels[:,:3].copy()
mask=np.clip((rgb[:,0]-.52)/.12,0,1)*np.clip((rgb[:,1]-.36)/.13,0,1)
mask=mask*mask*(3-2*mask)
lum=rgb@np.array([.2126,.7152,.0722])
color=(rgb*.78+lum[:,None]*.22)*np.array([.78,.79,.80])
pixels[:,:3]=rgb+(color-rgb)*mask[:,None]
assert np.array_equal(pixels[mask==0,:3],rgb[mask==0])
graded=bpy.data.images.new('Gravebound_Natural_Hand_Albedo',width=iw,height=ih,alpha=True)
graded.pixels.foreach_set(pixels.ravel());graded.pack()
materials={}
for obj in original:
 if not obj.name.startswith('Gravebound_FP_'):continue
 for i,mat in enumerate(obj.data.materials):
  if not mat or mat.name=='Gravebound_Matched_Sleeve_Cloth':continue
  node=next((n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.image.name.lower().startswith('albedo')),None)
  if not node:continue
  original_pixels=np.empty(iw*ih*4,dtype=np.float32);node.image.pixels.foreach_get(original_pixels)
  assert np.array_equal(original_pixels.reshape(-1,4)[:,:3],rgb), 'Mirrored hand source texture differs'
  if mat.name not in materials:
   new=mat.copy();new.name='Gravebound_Natural_Hands_'+mat.name
   next(n for n in new.node_tree.nodes if n.type=='TEX_IMAGE' and n.image and n.image.name.lower().startswith('albedo')).image=graded
   materials[mat.name]=new
  obj.data.materials[i]=materials[mat.name]
from hand_pose import apply_hand_pose
pose_report=apply_hand_pose(ROOT)
assert unchanged=={o.name:signature(o) for o in original if o.type=='MESH' and not o.name.endswith('_Hand')},'Non-hand geometry/UV changed'
bpy.ops.object.select_all(action='DESELECT')
for o in original:o.select_set(True)
bpy.context.view_layer.objects.active=bpy.data.objects['GraveboundPlayer']
bpy.data.orphans_purge(do_recursive=True)
for im in bpy.data.images:
 if im.source=='FILE' and im.has_data:im.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(W/'Gravebound_Natural_Hands.blend'),compress=True)
out=W/'gravebound_player_natural_hands.glb'
bpy.ops.export_scene.gltf(filepath=str(out),export_format='GLB',use_selection=True,export_animations=False,export_skins=False,export_extras=True,export_tangents=True,export_yup=True)
report={'source_sha256':sha(SOURCE),'output_sha256':sha(out),'non_hand_geometry_uv_unchanged':True,'skin_grade':{'saturation':.78,'rgb_brightness':[.78,.79,.80],'skin_texels':int(np.count_nonzero(mask)),'non_skin_texels_unchanged':True},'pose':pose_report}
(W/'build_report.json').write_text(json.dumps(report,indent=2))
print('NATURAL HANDS BUILD PASS',json.dumps(report))
