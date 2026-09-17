from collections import defaultdict, deque
import json
from pathlib import Path

import bpy


root = Path('/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg')
staging = root / 'asset-staging' / 'blender_mercenary_crossbowman_game_ready'
bpy.ops.wm.open_mainfile(filepath=str(staging / 'mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend'))

names = (
    'Mercenary_Cowl_LayeredClean_LOD0',
    'Mercenary_UnderCowl_Yoke_LOD0',
    'Mercenary_ShoulderCowl_Gussets_LOD0',
    'Mercenary_RearShoulder_NotchPatches_LOD0',
    'Mercenary_InnerCowl_RolledCollar_LOD0',
)
report = {}
for name in names:
    obj = bpy.data.objects.get(name)
    if not obj:
        continue
    mesh = obj.data
    adjacency = defaultdict(set)
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(mesh.vertices)))
    comps = []
    while unseen:
        seed = unseen.pop()
        comp = {seed}
        q = [seed]
        while q:
            current = q.pop()
            found = adjacency[current] & unseen
            unseen.difference_update(found)
            comp.update(found)
            q.extend(found)
        coords = [mesh.vertices[i].co for i in comp]
        faces = [p for p in mesh.polygons if p.vertices[0] in comp]
        comps.append({
            'vertices': len(comp),
            'triangles': sum(max(1, len(p.vertices)-2) for p in faces),
            'bbox_min': [min(c[j] for c in coords) for j in range(3)],
            'bbox_max': [max(c[j] for c in coords) for j in range(3)],
            'centroid': [sum(c[j] for c in coords)/len(coords) for j in range(3)],
        })
    report[name] = {
        'triangles': sum(max(1, len(p.vertices)-2) for p in mesh.polygons),
        'components': sorted(comps, key=lambda c: c['centroid'][2]),
        'materials': [m.name if m else None for m in mesh.materials],
    }

path = staging / 'v16j_upper_components.json'
path.write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
