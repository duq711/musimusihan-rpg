from pathlib import Path
import bpy
ROOT=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v15.blend'))
for n in ['MAT_CowlTop_SelectiveCharcoal_PBR_4K','MAT_CowlWool_Side_PBR_4K','MAT_OuterWool_Side_PBR_4K','MAT_Gambeson_Side_PBR_4K']:
 m=bpy.data.materials[n]
 print('MAT',n,'diffuse',tuple(round(x,3) for x in m.diffuse_color))
 for node in m.node_tree.nodes:
  if node.type=='TEX_IMAGE': print(' IMAGE',node.name,node.image.filepath if node.image else None)
  elif node.type=='BSDF_PRINCIPLED':
   print(' BSDF',node.inputs['Base Color'].default_value[:], 'rough',node.inputs['Roughness'].default_value,'metal',node.inputs['Metallic'].default_value)
