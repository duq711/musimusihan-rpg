"""Inspect the v8 shoulder and upper-arm surfaces visible from above."""

from __future__ import annotations

from collections import Counter, deque
import json

import bmesh
import bpy
from mathutils import Vector


donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
donor.hide_set(False)
donor.hide_viewport = False

materials = [slot.material.name if slot.material else "<empty>" for slot in donor.material_slots]
print("MATERIALS", json.dumps(dict(enumerate(materials))))

region_counts = Counter()
top_counts = Counter()
for polygon in donor.data.polygons:
    center = polygon.center
    if 0.15 < abs(center.x) < 0.82 and 1.20 < center.z < 1.62:
        region_counts[polygon.material_index] += 1
        if polygon.normal.z > 0.15:
            top_counts[polygon.material_index] += 1
print("REGION_FACE_COUNTS", json.dumps(region_counts))
print("TOP_FACE_COUNTS", json.dumps(top_counts))

bm = bmesh.new()
bm.from_mesh(donor.data)
boundary_edges = [
    edge
    for edge in bm.edges
    if len(edge.link_faces) == 1
    and max(vertex.co.z for vertex in edge.verts) > 1.20
    and max(abs(vertex.co.x) for vertex in edge.verts) > 0.15
]

edge_by_vertex = {}
for edge in boundary_edges:
    for vertex in edge.verts:
        edge_by_vertex.setdefault(vertex, []).append(edge)

unseen = set(boundary_edges)
components = []
while unseen:
    seed = unseen.pop()
    queue = deque([seed])
    component = [seed]
    while queue:
        edge = queue.popleft()
        for vertex in edge.verts:
            for neighbor in edge_by_vertex.get(vertex, []):
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.append(neighbor)
                    queue.append(neighbor)
    vertices = {vertex for edge in component for vertex in edge.verts}
    coordinates = [vertex.co for vertex in vertices]
    components.append(
        {
            "edges": len(component),
            "verts": len(vertices),
            "min": [min(co[index] for co in coordinates) for index in range(3)],
            "max": [max(co[index] for co in coordinates) for index in range(3)],
            "materials": sorted(
                {
                    face.material_index
                    for edge in component
                    for face in edge.link_faces
                }
            ),
        }
    )
bm.free()
components.sort(key=lambda item: item["edges"], reverse=True)
print("BOUNDARY_COMPONENTS", json.dumps(components[:30]))

# Sample the first visible surface from above. This separates actual gaps from
# dark materials and records the face material hit by each ray.
depsgraph = bpy.context.evaluated_depsgraph_get()
scene = bpy.context.scene
for obj in scene.objects:
    if obj.type == "ARMATURE":
        obj.hide_set(True)

xs = [round(0.18 + index * 0.04, 2) for index in range(17)]
ys = [-0.20, -0.12, -0.04, 0.04, 0.12, 0.20]
ray_rows = []
for y in ys:
    row = []
    for x in xs:
        hit, location, normal, face_index, obj, _matrix = scene.ray_cast(
            depsgraph, Vector((x, y, 2.2)), Vector((0.0, 0.0, -1.0)), distance=1.3
        )
        if not hit:
            row.append({"x": x, "hit": None})
            continue
        source = obj.original if getattr(obj, "original", None) is not None else obj
        material_index = None
        material_name = None
        if source.type == "MESH" and 0 <= face_index < len(source.data.polygons):
            material_index = source.data.polygons[face_index].material_index
            if material_index < len(source.material_slots):
                material = source.material_slots[material_index].material
                material_name = material.name if material else None
        row.append(
            {
                "x": x,
                "hit": source.name,
                "z": round(location.z, 4),
                "normal_z": round(normal.z, 4),
                "material": material_index,
                "material_name": material_name,
            }
        )
    ray_rows.append({"y": y, "samples": row})
print("TOP_RAYS_RIGHT", json.dumps(ray_rows))
