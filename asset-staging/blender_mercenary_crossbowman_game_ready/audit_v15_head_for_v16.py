from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
STAGING = ROOT / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
bpy.ops.wm.open_mainfile(filepath=str(STAGING / 'mercenary_crossbowman_game_ready_v15.blend'))

head = bpy.data.objects['Mercenary_Male_HeadNeck_LOD0']
print('HEAD_VERTS', len(head.data.vertices), 'FACES', len(head.data.polygons))
print('HEAD_MATS', [(i, m.name if m else None) for i, m in enumerate(head.data.materials)])
world = head.matrix_world
coords = [world @ v.co for v in head.data.vertices]
print('HEAD_BOUNDS', tuple(round(min(v[i] for v in coords), 6) for i in range(3)), tuple(round(max(v[i] for v in coords), 6) for i in range(3)))

for mi, mat in enumerate(head.data.materials):
    faces = [p for p in head.data.polygons if p.material_index == mi]
    if not faces:
        continue
    centers = [world @ p.center for p in faces]
    print('MAT', mi, mat.name if mat else None, 'FACES', len(faces), 'BOUNDS',
          tuple(round(min(v[i] for v in centers), 6) for i in range(3)),
          tuple(round(max(v[i] for v in centers), 6) for i in range(3)))
    high = [v for v in centers if v.z >= 1.66]
    if high:
        print('MAT_HIGH', mi, 'FACES', len(high), 'BOUNDS',
              tuple(round(min(v[i] for v in high), 6) for i in range(3)),
              tuple(round(max(v[i] for v in high), 6) for i in range(3)))

rig = bpy.data.objects['Mercenary_Rigify_Rig_v4']
print('HEAD_GROUPS', [g.name for g in head.vertex_groups])
print('RIG_PARENT', head.parent.name if head.parent else None)
