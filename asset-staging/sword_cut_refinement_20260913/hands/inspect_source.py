import bpy
import json
from pathlib import Path
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

root = Path(__file__).resolve().parent
source = root.parents[1] / 'sword_hold_long_grip_integration/source/model/SwordHold_Static.blend'
bpy.ops.wm.open_mainfile(filepath=str(source))
report = {'blender_version': bpy.app.version_string, 'blender_binary': bpy.app.binary_path, 'source': str(source), 'objects': []}
for obj in bpy.data.objects:
    entry = {'name': obj.name, 'type': obj.type, 'matrix_world': [list(row) for row in obj.matrix_world]}
    if obj.type == 'MESH':
        entry.update(vertices=len(obj.data.vertices), polygons=len(obj.data.polygons), groups=[group.name for group in obj.vertex_groups], modifiers=[{'name': mod.name, 'type': mod.type} for mod in obj.modifiers])
    report['objects'].append(entry)
hand = bpy.data.objects['RightHand_Glove']
hilt = bpy.data.objects['Sword_GripLeather']
tree = BVHTree.FromPolygons([v.co for v in hilt.data.vertices], [p.vertices for p in hilt.data.polygons], all_triangles=False)
canonical = Matrix(((0.6734562112,0.1384824613,-0.7261403196,0.3249563841),(-0.1673592395,0.9853534854,0.0327005009,-0.0035816696),(0.7200327879,0.0995039315,0.6867691389,-0.5892537756),(0,0,0,1))).inverted() @ Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1))) @ hand.matrix_world
groups = {}
for group in hand.vertex_groups:
    selected = [v for v in hand.data.vertices if any(g.group == group.index and g.weight > .5 for g in v.groups)]
    if not selected: continue
    points = [canonical @ v.co for v in selected]
    gaps = []
    for v in selected:
        loc, normal, _, dist = tree.find_nearest(v.co)
        gaps.append(dist if (v.co-loc).dot(normal)>=0 else -dist)
    groups[group.name] = {'vertices': len(points), 'centroid': list(sum(points,Vector())/len(points)), 'min':[min(p[a] for p in points) for a in range(3)], 'max':[max(p[a] for p in points) for a in range(3)], 'min_hilt_gap_m':min(gaps), 'penetrating_count':sum(d < -.001 for d in gaps)}
report['groups'] = groups
(root / 'source_inspection.json').write_text(json.dumps(report, indent=2))
print('HAND SOURCE INSPECT:', json.dumps(report))
