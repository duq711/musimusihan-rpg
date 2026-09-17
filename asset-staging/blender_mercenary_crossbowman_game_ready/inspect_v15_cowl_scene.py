from pathlib import Path
import bpy

ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
SRC = ROOT/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v15.blend'
bpy.ops.wm.open_mainfile(filepath=str(SRC))
for o in bpy.context.scene.objects:
    if o.type == 'MESH' and (o.get('part_category') is not None or 'Cowl' in o.name or 'Head' in o.name):
        pts=[o.matrix_world @ v.co for v in o.data.vertices]
        mins=tuple(round(min(p[i] for p in pts),4) for i in range(3))
        maxs=tuple(round(max(p[i] for p in pts),4) for i in range(3))
        tris=sum(max(1,len(p.vertices)-2) for p in o.data.polygons)
        print('OBJ',o.name,'cat=',o.get('part_category'),'hide=',o.hide_render,'verts=',len(o.data.vertices),'tris=',tris,'bounds=',mins,maxs,'mats=',[m.name if m else None for m in o.data.materials])
