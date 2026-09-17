from pathlib import Path
import json
import bpy

ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING = ROOT / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
SOURCE = STAGING / 'mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

def tris(obj):
    return sum(max(1, len(p.vertices)-2) for p in obj.data.polygons)

objects = []
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH':
        continue
    corners = [obj.matrix_world @ v.co for v in obj.data.vertices]
    bounds = None
    if corners:
        bounds = {
            'x': [min(v.x for v in corners), max(v.x for v in corners)],
            'y': [min(v.y for v in corners), max(v.y for v in corners)],
            'z': [min(v.z for v in corners), max(v.z for v in corners)],
        }
    objects.append({
        'name': obj.name,
        'triangles': tris(obj),
        'part_category': obj.get('part_category'),
        'hide_render': obj.hide_render,
        'bounds': bounds,
        'materials': [m.name if m else None for m in obj.data.materials],
        'groups': [g.name for g in obj.vertex_groups],
        'modifiers': [{'name': m.name, 'type': m.type, 'target': getattr(getattr(m, 'object', None), 'name', None)} for m in obj.modifiers],
    })

print(json.dumps({'objects': objects, 'materials': [m.name for m in bpy.data.materials]}, indent=2))
