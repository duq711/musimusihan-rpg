"""Read-only Blender audit of final inward palms against the unchanged body.

Run with Blender -b -P audit_clearance.py. The only output is the JSON report;
the production blend and GLB are never saved or changed by this audit.
"""
import hashlib
import json
from pathlib import Path

import bpy
from mathutils.bvhtree import BVHTree

WORK = Path(__file__).resolve().parent
SOURCE = WORK / "Gravebound_Inward_Palms.blend"
GLB = WORK / "gravebound_player_inward_palms.glb"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def world_triangles(obj):
    obj.data.calc_loop_triangles()
    return (
        [obj.matrix_world @ vertex.co for vertex in obj.data.vertices],
        [tuple(triangle.vertices) for triangle in obj.data.loop_triangles],
    )


build = json.loads((WORK / "build_report.json").read_text())
assert all(build["sides"][side]["outward_offset_m"] == .015 for side in ("L", "R"))
source_hash = sha256(SOURCE)
assert sha256(GLB) == build["output_sha256"], "Final export differs from build report"
bpy.ops.wm.open_mainfile(filepath=str(SOURCE))

body_parts = [
    obj for obj in bpy.data.objects
    if obj.type == "MESH" and not obj.name.startswith("Gravebound_FP_")
]
assert len(body_parts) == 24, "Unexpected body part selection"
body_trees = {}
for obj in body_parts:
    vertices, triangles = world_triangles(obj)
    body_trees[obj.name] = BVHTree.FromPolygons(vertices, triangles, all_triangles=True)

report = {
    "source_blend_sha256": source_hash,
    "source_glb_sha256": sha256(GLB),
    "method": "Final Blender meshes, world-space triangles; hands against all 24 non-arm body parts",
    "distance_scope": "Minimum sampled hand-vertex to body-surface distance, not exact triangle clearance",
    "outward_offset_m": .015,
    "sides": {},
}
for side in ("L", "R"):
    obj = bpy.data.objects["Gravebound_FP_" + side + "_Hand"]
    vertices, triangles = world_triangles(obj)
    hand_tree = BVHTree.FromPolygons(vertices, triangles, all_triangles=True)
    overlaps = {}
    nearest_distance = float("inf")
    nearest_part = None
    for name, body_tree in body_trees.items():
        pairs = hand_tree.overlap(body_tree)
        if pairs:
            overlaps[name] = len(pairs)
        distance = min(body_tree.find_nearest(vertex)[3] for vertex in vertices)
        if distance < nearest_distance:
            nearest_distance = distance
            nearest_part = name
    report["sides"][side] = {
        "triangle_overlap_pairs": sum(overlaps.values()),
        "overlaps_by_body_part": overlaps,
        "minimum_sampled_vertex_surface_distance_m": nearest_distance,
        "closest_body_part": nearest_part,
        "hand_vertex_count": len(vertices),
        "hand_triangle_count": len(triangles),
    }
    assert not overlaps, (side, "Hand intersects body", overlaps)

assert sha256(SOURCE) == source_hash, "Source changed during read-only audit"
report["pass"] = True
(WORK / "clearance_report.json").write_text(json.dumps(report, indent=2) + "\n")
print("INWARD PALMS CLEARANCE PASS", json.dumps(report))
