"""Inspect the 333 v4 faces that v8 incorrectly removed."""

from __future__ import annotations

from collections import Counter, defaultdict, deque
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v4.blend"))
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]

bm = bmesh.new()
bm.from_mesh(donor.data)
bm.faces.ensure_lookup_table()
selected = {
    face
    for face in bm.faces
    if (
        0.235 < abs(face.calc_center_median().x) < 0.505
        and 1.455 < face.calc_center_median().z < 1.565
        and face.material_index == 4
        and face.normal.z > 0.08
    )
}
print("SELECTED", len(selected), "triangles", sum(max(1, len(face.verts) - 2) for face in selected))

remaining = set(selected)
components = []
while remaining:
    seed = remaining.pop()
    component = {seed}
    queue = deque([seed])
    while queue:
        face = queue.popleft()
        for edge in face.edges:
            for neighbor in edge.link_faces:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
    components.append(component)

for index, component in enumerate(sorted(components, key=len, reverse=True), 1):
    centers = [face.calc_center_median() for face in component]
    minimum = Vector((min(c.x for c in centers), min(c.y for c in centers), min(c.z for c in centers)))
    maximum = Vector((max(c.x for c in centers), max(c.y for c in centers), max(c.z for c in centers)))
    neighbors = Counter()
    for face in component:
        for edge in face.edges:
            for neighbor in edge.link_faces:
                if neighbor not in component:
                    neighbors[neighbor.material_index] += 1
    print(
        "COMPONENT", index,
        "faces", len(component),
        "triangles", sum(max(1, len(face.verts) - 2) for face in component),
        "bounds", tuple(round(value, 6) for value in minimum), tuple(round(value, 6) for value in maximum),
        "neighbor_material_edges", dict(sorted(neighbors.items())),
    )
    for face in sorted(component, key=lambda f: f.index)[:8]:
        center = face.calc_center_median()
        print(
            " FACE", face.index,
            "center", tuple(round(value, 6) for value in center),
            "normal", tuple(round(value, 6) for value in face.normal),
            "neighbor_mats", sorted({neighbor.material_index for edge in face.edges for neighbor in edge.link_faces if neighbor is not face}),
        )
bm.free()
