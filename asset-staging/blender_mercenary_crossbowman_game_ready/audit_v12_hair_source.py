"""Read-only audit of reusable hair objects in the original staging blend."""

from pathlib import Path
from collections import Counter

import bpy


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_3d.blend"))

for name in ("Hair_ScalpCap", "Hair_Unkempt_Strands"):
    obj = bpy.data.objects[name]
    triangles = sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)
    print("OBJECT", name, "TRIANGLES", triangles)
    print("  TRANSFORM", tuple(obj.location), tuple(obj.rotation_euler), tuple(obj.scale))
    print("  PARENT", obj.parent.name if obj.parent else None)
    print("  MODIFIERS", [(m.name, m.type, getattr(m, "object", None).name if getattr(m, "object", None) else None) for m in obj.modifiers])
    print("  GROUPS", [g.name for g in obj.vertex_groups])
    sums = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    print("  WEIGHTS", (min(sums), max(sums)) if sums else None)
    print("  BOUNDS", [tuple(corner) for corner in obj.bound_box])
    for index, material in enumerate(obj.data.materials):
        print("  MATERIAL", index, material.name if material else None)
        if material and material.use_nodes and material.node_tree:
            print("   SETTINGS", material.surface_render_method, material.diffuse_color, material.roughness)
            for node in material.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    print("   IMAGE", node.name, node.image.name, list(node.image.size), node.image.filepath)
    print("  MATERIAL_COUNTS", Counter(p.material_index for p in obj.data.polygons))
