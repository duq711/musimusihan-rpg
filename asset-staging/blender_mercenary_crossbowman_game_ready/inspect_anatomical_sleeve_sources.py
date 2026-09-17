"""Print mesh/bone bounds needed for the anatomical upper-sleeve rebuild."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import bpy


def world_bounds(obj):
    points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "min": [min(point[i] for point in points) for i in range(3)],
        "max": [max(point[i] for point in points) for i in range(3)],
        "vertices": len(obj.data.vertices),
        "polygons": len(obj.data.polygons),
    }


path = Path(sys.argv[-1]).resolve()
bpy.ops.wm.open_mainfile(filepath=str(path))
report = {"file": str(path), "meshes": {}, "armatures": {}}
for obj in bpy.data.objects:
    if obj.type == "MESH":
        report["meshes"][obj.name] = world_bounds(obj)
    elif obj.type == "ARMATURE":
        report["armatures"][obj.name] = {
            "bones": len(obj.data.bones),
            "deform": sum(bone.use_deform for bone in obj.data.bones),
            "location": list(obj.location),
            "scale": list(obj.scale),
            "upper_arm_bones": {
                bone.name: {
                    "head": list(obj.matrix_world @ bone.head_local),
                    "tail": list(obj.matrix_world @ bone.tail_local),
                }
                for bone in obj.data.bones
                if bone.name.startswith("DEF-upper_arm")
            },
        }
print("ANATOMY_INSPECT=" + json.dumps(report, sort_keys=True))

for candidate_name in (
    "Mercenary_AnatomicalGambesonUpperSleeves_v16as_LOD0",
    "Mercenary_GambesonUpperSleeves_v16zb_LOD0",
):
    candidate = bpy.data.objects.get(candidate_name)
    if candidate is None:
        continue
    edges = []
    for edge in candidate.data.edges:
        a = candidate.data.vertices[edge.vertices[0]].co
        b = candidate.data.vertices[edge.vertices[1]].co
        edges.append(((a - b).length, edge.index, list(a), list(b)))
    edges.sort(reverse=True)
    print("ANATOMY_SLEEVE_EDGES=" + json.dumps({
        "name": candidate_name,
        "longest": edges[:12],
    }, sort_keys=True))

body = bpy.data.objects.get("GEO-body_male_realistic")
if body is not None:
    points = [body.matrix_world @ vertex.co for vertex in body.data.vertices]
    center_x = 0.5 * (min(point.x for point in points) + max(point.x for point in points))
    rows = {}
    for z0 in (0.8, 1.0, 1.2, 1.35, 1.45, 1.55):
        slab = [point for point in points if abs(point.z - z0) < 0.02]
        if slab:
            rows[str(z0)] = {
                "count": len(slab),
                "x_rel": [min(point.x - center_x for point in slab), max(point.x - center_x for point in slab)],
                "y": [min(point.y for point in slab), max(point.y for point in slab)],
            }
    print("ANATOMY_BODY_ROWS=" + json.dumps({
        "matrix_world": [list(row) for row in body.matrix_world],
        "center_x": center_x,
        "rows": rows,
    }, sort_keys=True))
