from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
SOURCE = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v11.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

print("MESH_SUMMARY")
for obj in sorted((o for o in scene.objects if o.type == "MESH"), key=lambda o: o.name):
    coords = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    mins = tuple(min(c[i] for c in coords) for i in range(3))
    maxs = tuple(max(c[i] for c in coords) for i in range(3))
    mats = [mat.name if mat else None for mat in obj.data.materials]
    print(obj.name, "cat=", obj.get("part_category"), "verts=", len(obj.data.vertices),
          "bounds=", tuple(round(v, 4) for v in (*mins, *maxs)), "mats=", mats)

def make_bvh(obj):
    verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    polys = [tuple(p.vertices) for p in obj.data.polygons]
    return BVHTree.FromPolygons(verts, polys, all_triangles=False, epsilon=1e-7)

objects = [o for o in scene.objects if o.type == "MESH" and o.get("part_category") is not None]
bvhs = {o.name: make_bvh(o) for o in objects}

print("TOP_WORLD_GRID_HITS")
for y in (0.30, 0.25, 0.20, 0.15, 0.10, 0.05, 0.0, -0.05, -0.10, -0.15, -0.20, -0.25, -0.30):
    row = []
    for x in (-0.50, -0.40, -0.30, -0.25, -0.20, -0.15, -0.10, 0.0, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40, 0.50):
        best = None
        for name, bvh in bvhs.items():
            hit, normal, index, dist = bvh.ray_cast(Vector((x, y, 3.0)), Vector((0, 0, -1)), 3.0)
            if hit is not None and (best is None or hit.z > best[0]):
                best = (hit.z, name)
        if best is None:
            row.append("--")
        else:
            short = best[1].replace("Mercenary_", "")[:9]
            row.append(f"{best[0]:.3f}:{short}")
    print(f"y={y:+.2f}", " | ".join(row))
