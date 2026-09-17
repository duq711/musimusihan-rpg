from pathlib import Path
import bpy

root = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
source = root / 'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
for obj in sorted((o for o in bpy.context.scene.objects if o.type == 'MESH'), key=lambda o: o.name):
    mins = [min(v.co[i] for v in obj.data.vertices) for i in range(3)] if obj.data.vertices else [0,0,0]
    maxs = [max(v.co[i] for v in obj.data.vertices) for i in range(3)] if obj.data.vertices else [0,0,0]
    mats = [slot.material.name if slot.material else None for slot in obj.material_slots]
    tris = sum(max(1, len(p.vertices)-2) for p in obj.data.polygons)
    print('OBJ', obj.name, 'tris', tris, 'cat', obj.get('part_category'), 'hide', obj.hide_render, 'bounds', mins, maxs, 'mats', mats)
