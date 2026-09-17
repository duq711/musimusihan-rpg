from pathlib import Path
import bpy

root = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
source = root / 'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
for name in ('MAT_CowlWool_Side_PBR_4K', 'MAT_CowlTop_SelectiveCharcoal_PBR_4K'):
    material = bpy.data.materials[name]
    print('\nMATERIAL', name)
    print('diffuse', list(material.diffuse_color), 'roughness', material.roughness, 'metallic', material.metallic)
    if material.node_tree:
        for node in material.node_tree.nodes:
            if node.type == 'TEX_IMAGE':
                print(' image', node.name, getattr(node.image, 'filepath', None), 'interp', node.interpolation)
            elif node.type == 'BSDF_PRINCIPLED':
                print(' bsdf')
                for socket_name in ('Base Color', 'Roughness', 'Normal'):
                    socket = node.inputs.get(socket_name)
                    if socket:
                        print('  ', socket_name, list(socket.default_value) if hasattr(socket.default_value, '__len__') else socket.default_value, 'linked', socket.is_linked)
