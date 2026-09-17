import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'blackwater_abandoned_mine.blend'))
for name in ['Mine_Limestone', 'Mine_Continuous_Mine_Limestone', 'Mine_GravelMud']:
 mat=bpy.data.materials[name]
 print('MATERIAL',name,dict(mat.items()),flush=True)
 for n in mat.node_tree.nodes:
  if n.type=='VECT_MATH': print('MAPPING',n.name,n.operation,n.inputs['Scale'].default_value,flush=True)
 for l in mat.node_tree.links:
  if l.to_node.type=='TEX_IMAGE': print('IMAGE_VECTOR',l.from_node.name,l.from_socket.name,l.to_node.name,flush=True)
