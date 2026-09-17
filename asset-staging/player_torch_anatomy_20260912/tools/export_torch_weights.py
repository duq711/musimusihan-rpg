import bpy,numpy as np,json
from pathlib import Path
from mathutils import Matrix,kdtree
s=Path(__file__).resolve().parents[1];root=s.parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'godot-game/assets/3d/player/hands_detailed/left_hand_detailed.glb'))
x=np.load(s/'audit/fit_input_reweighted.npz');names=list(x['names']);W=x['weights'];v=x['vertices']
body=next(o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Supplied_AnatomicalHand'))
# Importer restores native glTF Y-up to Blender Z-up. Match source bind points.
lookup={tuple(np.round(p,5)):i for i,p in enumerate(v)};hits=0
tree=kdtree.KDTree(len(v))
for i,p in enumerate(v):tree.insert(p,i)
tree.balance()
for pt in body.data.vertices:
 _,i,error=tree.find(pt.co);assert error<.000002,(pt.index,error)
 for g in list(pt.groups):body.vertex_groups[g.group].remove([pt.index])
 for j,w in enumerate(W[i]):
  if w>1e-6:
   group=body.vertex_groups.get(names[j]) or body.vertex_groups.new(name=names[j]);group.add([pt.index],float(w),'REPLACE')
 hits+=1
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(s/'mac_output/left_hand_torch_weights.blend'))
bpy.ops.export_scene.gltf(filepath=str(s/'mac_output/left_hand_torch.glb'),export_format='GLB',export_yup=True,export_animations=False,export_skins=True,export_morph=True,export_materials='EXPORT',export_tangents=True)
(s/'audit/weight_export.json').write_text(json.dumps({'matched_imported_vertices':hits,'geometry_modified':False,'source':'left_hand_detailed.glb','output':'left_hand_torch.glb'},indent=2))
