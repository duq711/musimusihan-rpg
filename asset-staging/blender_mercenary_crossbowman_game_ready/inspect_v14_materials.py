from pathlib import Path
import bpy

root = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
bpy.ops.wm.open_mainfile(filepath=str(root / "asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v11.blend"))

for name in (
    "MAT_CowlTop_SelectiveCharcoal_PBR_4K",
    "MAT_Gambeson_Side_PBR_4K",
    "MAT_OuterWool_Side_PBR_4K",
    "MAT_CowlWool_Side_PBR_4K",
    "MAT_ReferenceProjection_Front_4K",
    "MAT_ReferenceProjection_Back_4K",
):
    mat = bpy.data.materials.get(name)
    print("MATERIAL", name, "backface_culling", mat.use_backface_culling if mat else None)
    if not mat or not mat.use_nodes:
        continue
    for node in mat.node_tree.nodes:
        print(" NODE", node.bl_idname, node.name,
              "image", getattr(getattr(node, "image", None), "name", None))
        if node.bl_idname == "ShaderNodeBsdfPrincipled":
            for socket_name in ("Base Color", "Roughness", "Metallic", "Normal"):
                sock = node.inputs.get(socket_name)
                if sock:
                    print("  INPUT", socket_name, "default", sock.default_value if hasattr(sock, "default_value") else None,
                          "linked", bool(sock.links))
    print()
