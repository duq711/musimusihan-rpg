import bpy,json
from pathlib import Path
p=Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
bpy.ops.wm.open_mainfile(filepath=str(p/'asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend'))
from mathutils import Vector
for o in bpy.data.objects:
 if o.type=='MESH':
  coords=[o.matrix_world@Vector(v) for v in o.bound_box]
  print(o.name, list(o.dimensions), list(o.location), len(o.data.vertices), [m.name for m in o.data.materials], 'bounds',[[min(v[i] for v in coords) for i in range(3)],[max(v[i] for v in coords) for i in range(3)]])
