import bpy
from pathlib import Path
s=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(s/'mac_output/torch_grip_final.blend'))
scene=bpy.data.scenes['Torch_Grip_Authoring'];bpy.context.window.scene=scene
for n in ['Supplied_Skin','Supplied_Nail']:
 m=bpy.data.materials[n]
 for node in m.node_tree.nodes:
  if node.type=='BSDF_PRINCIPLED':
   for link in list(node.inputs['Normal'].links):m.node_tree.links.remove(link)
scene.render.filepath=str(s/'review/surface_without_normal.png');bpy.ops.render.render(write_still=True)
