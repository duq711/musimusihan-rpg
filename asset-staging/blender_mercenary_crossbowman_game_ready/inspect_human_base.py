import bpy
import os
import addon_utils


WORKSPACE = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg"
BASE_BLEND = os.path.join(
    WORKSPACE,
    "asset-staging/blender_mercenary_crossbowman_photoreal/resources",
    "human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend",
)

print("BASE_BLEND", BASE_BLEND)
rigify_modules = [module.__name__ for module in addon_utils.modules() if "rigify" in module.__name__.lower()]
print("RIGIFY_MODULES", rigify_modules)
print("RIGIFY_ENABLED", [name for name in rigify_modules if addon_utils.check(name)[1]])
with bpy.data.libraries.load(BASE_BLEND, link=False) as (data_from, data_to):
    print("COLLECTION_NAMES", sorted(data_from.collections))
    data_to.collections = ["Body Male - Realistic"]

collection = data_to.collections[0]
bpy.context.scene.collection.children.link(collection)

for obj in sorted(collection.objects, key=lambda item: item.name):
    entry = {
        "name": obj.name,
        "type": obj.type,
        "parent": obj.parent.name if obj.parent else None,
        "modifiers": [(mod.name, mod.type) for mod in obj.modifiers],
    }
    if obj.type == "MESH":
        entry.update(
            vertices=len(obj.data.vertices),
            edges=len(obj.data.edges),
            polygons=len(obj.data.polygons),
            uv_layers=[layer.name for layer in obj.data.uv_layers],
            shape_keys=list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [],
            vertex_groups=[group.name for group in obj.vertex_groups],
        )
    elif obj.type == "ARMATURE":
        entry.update(bones=[bone.name for bone in obj.data.bones])
    print("OBJECT", entry)

for obj in collection.all_objects:
    if obj.type != "MESH":
        continue
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    triangles = sum(len(poly.vertices) - 2 for poly in mesh.polygons)
    print("EVALUATED", obj.name, "verts", len(mesh.vertices), "polys", len(mesh.polygons), "tris", triangles)
    evaluated.to_mesh_clear()
