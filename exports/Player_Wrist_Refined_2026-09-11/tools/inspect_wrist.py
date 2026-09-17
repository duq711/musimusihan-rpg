"""Read-only source wrist component and section inspection in Blender background."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

STAGE = Path(__file__).resolve().parents[1]
SOURCE = STAGE.parent / 'player_finger_joints_20260910/mac_output/iteration_02/bilateral_hands_articulated.blend'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.data.scenes['Bilateral_Articulated_Review']
bpy.context.window.scene = scene
holder = bpy.data.objects['LEFT_PreviewTranslationOnly']
rig = bpy.data.objects['HandRig.001']
wrist = rig.matrix_world @ rig.data.bones['wrist'].head_local
rows = []
for obj in scene.objects:
    if obj.type != 'MESH' or not any(t in obj.name.lower() for t in ('anatomicalhand', 'forearm', 'wristcuff')):
        continue
    parent = obj
    while parent.parent:
        parent = parent.parent
    if parent != holder:
        continue
    points = [obj.matrix_world @ v.co - wrist for v in obj.data.vertices]
    row = {'name': obj.name, 'vertices': len(points), 'polygons': len(obj.data.polygons),
           'materials': [m.name if m else None for m in obj.data.materials],
           'min_relative_wrist': [min(p[i] for p in points) for i in range(3)],
           'max_relative_wrist': [max(p[i] for p in points) for i in range(3)]}
    adjacency = [set() for unused in points]
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b); adjacency[b].add(a)
    remaining, components = set(range(len(points))), []
    while remaining:
        pending, ids = [remaining.pop()], []
        while pending:
            index = pending.pop(); ids.append(index)
            for neighbor in adjacency[index]:
                if neighbor in remaining:
                    remaining.remove(neighbor); pending.append(neighbor)
        if min(points[i].y for i in ids) < .06:
            components.append({'count': len(ids), 'ids_first': ids[:8],
                'min': [min(points[j][i] for j in ids) for i in range(3)],
                'max': [max(points[j][i] for j in ids) for i in range(3)]})
    row['wrist_components'] = sorted(components, key=lambda c: -c['count'])[:30]
    row['sections'] = []
    for y in [-.03, -.02, -.01, 0, .01, .02, .03, .04, .05, .06, .075]:
        samples = [p for p in points if abs(p.y - y) < .0015]
        if samples:
            row['sections'].append({'y': y, 'samples': len(samples),
                'x': [min(p.x for p in samples), max(p.x for p in samples)],
                'z': [min(p.z for p in samples), max(p.z for p in samples)]})
    rows.append(row)
report = {'wrist_world': list(wrist), 'coordinates': 'meters, relative to wrist bone; +Y toward fingers, +Z dorsal', 'objects': rows}
(STAGE/'wrist_source_inspection.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
for row in rows:
    print(row['name'], 'bounds',row['min_relative_wrist'],row['max_relative_wrist'],'components',len(row['wrist_components']))
    print('sections',row['sections'])
