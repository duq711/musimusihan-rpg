"""Sample which donor faces are visible from directly above in v9."""

from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
BLEND = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready" / "mercenary_crossbowman_game_ready_v9.blend"
bpy.ops.wm.open_mainfile(filepath=str(BLEND))
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
bm = bmesh.new()
bm.from_mesh(donor.data)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
bvh = BVHTree.FromBMesh(bm, epsilon=1.0e-7)
for side in (-1.0, 1.0):
    print("SIDE", side)
    for y in (-0.02, 0.01, 0.04, 0.07, 0.10, 0.13, 0.16, 0.19):
        row = []
        for ax in (0.24, 0.27, 0.30, 0.33, 0.36, 0.39, 0.42, 0.45, 0.48, 0.51):
            location, normal, index, distance = bvh.ray_cast(
                Vector((side * ax, y, 2.2)), Vector((0.0, 0.0, -1.0))
            )
            if index is None:
                row.append(f"{ax:.2f}:none")
                continue
            face = bm.faces[index]
            row.append(
                f"{ax:.2f}:m{face.material_index}/z{location.z:.3f}/n{normal.z:+.2f}/f{index}"
            )
        print(f" y={y:+.2f}", " ".join(row))
bm.free()
