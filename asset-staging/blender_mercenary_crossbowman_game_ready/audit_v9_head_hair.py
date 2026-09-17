"""Read-only audit of the v9 head's misclassified scalp faces and hair assets."""

from pathlib import Path
from collections import Counter

import bpy


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v9.blend"))

head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
print("HEAD_MATERIALS")
for index, material in enumerate(head.data.materials):
    print(index, material.name if material else None)

print("HAIR_MATERIAL_CANDIDATES")
for material in bpy.data.materials:
    if "hair" in material.name.lower() or "scalp" in material.name.lower():
        images = []
        if material.use_nodes and material.node_tree:
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    images.append((node.name, node.image.name, node.image.filepath))
        print(material.name, images)

print("HAIR_IMAGES")
for image in bpy.data.images:
    if "hair" in image.name.lower() or "scalp" in image.name.lower():
        print(image.name, list(image.size), image.filepath)

mat5 = [polygon for polygon in head.data.polygons if polygon.material_index == 5]
print("MAT5_COUNT", len(mat5))
print("MAT5_Z", min(p.center.z for p in mat5), max(p.center.z for p in mat5))
for threshold in (1.55, 1.58, 1.60, 1.62, 1.64, 1.65, 1.66, 1.67, 1.68, 1.70, 1.72):
    selected = [p for p in mat5 if p.center.z >= threshold]
    print("THRESHOLD", threshold, "COUNT", len(selected), "NZ", Counter(round(p.normal.z, 1) for p in selected))

print("MAT5_BOUNDS_BY_Z")
for lower, upper in ((0, 1.55), (1.55, 1.60), (1.60, 1.64), (1.64, 1.66), (1.66, 1.68), (1.68, 1.80)):
    selected = [p for p in mat5 if lower <= p.center.z < upper]
    if not selected:
        continue
    centers = [p.center for p in selected]
    print(
        (lower, upper), len(selected),
        "x", (min(c.x for c in centers), max(c.x for c in centers)),
        "y", (min(c.y for c in centers), max(c.y for c in centers)),
        "nz", (min(p.normal.z for p in selected), max(p.normal.z for p in selected)),
    )
