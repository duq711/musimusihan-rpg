from collections import defaultdict, deque
from pathlib import Path
import bpy
from mathutils import Vector

root = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
bpy.ops.wm.open_mainfile(filepath=str(root / "asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v13b.blend"))

for name in (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_Clothed_Donor_LOD0",
):
    obj = bpy.data.objects.get(name)
    if not obj:
        print("MISSING", name)
        continue
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for polygon in obj.data.polygons:
        vs = list(polygon.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            edge = tuple(sorted((a, b)))
            counts[edge] += 1
    boundary = [edge for edge, count in counts.items() if count == 1]
    for a, b in boundary:
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(adjacency)
    components = []
    while unseen:
        start = unseen.pop()
        queue = deque([start])
        vertices = {start}
        while queue:
            current = queue.popleft()
            for other in adjacency[current]:
                if other not in vertices:
                    vertices.add(other)
                    unseen.discard(other)
                    queue.append(other)
        components.append(vertices)
    print("OBJECT", name, "verts", len(obj.data.vertices), "polys", len(obj.data.polygons),
          "boundary_edges", len(boundary), "boundary_components", len(components),
          "overconnected", sum(count > 2 for count in counts.values()))
    for index, component in enumerate(sorted(components, key=len, reverse=True)[:16]):
        coords = [obj.matrix_world @ obj.data.vertices[i].co for i in component]
        bounds = tuple(round(v, 4) for axis in range(3) for v in (min(c[axis] for c in coords), max(c[axis] for c in coords)))
        print(" COMPONENT", index, "n", len(component), "bounds x/y/z", bounds)
