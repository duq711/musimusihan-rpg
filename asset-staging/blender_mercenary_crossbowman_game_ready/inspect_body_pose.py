import bpy


BASE_BLEND = "/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg/asset-staging/blender_mercenary_crossbowman_photoreal/resources/human-base-meshes-bundle-v1.4.1/human_base_meshes_bundle.blend"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
with bpy.data.libraries.load(BASE_BLEND, link=False) as (data_from, data_to):
    data_to.collections = ["Body Male - Realistic"]
collection = data_to.collections[0]
bpy.context.scene.collection.children.link(collection)
body = next(obj for obj in collection.objects if obj.name.startswith("GEO-body_male_realistic") and ".eye." not in obj.name)
for lo, hi in ((0.15, 0.20), (0.20, 0.25), (0.25, 0.32), (0.32, 0.40), (0.40, 0.50), (0.50, 0.60), (0.60, 0.75)):
    coords = [vertex.co for vertex in body.data.vertices if lo <= abs(vertex.co.x) < hi and vertex.co.z > 0.8]
    if coords:
        print("BIN", lo, hi, "n", len(coords), "z_avg", sum(co.z for co in coords) / len(coords), "z_min", min(co.z for co in coords), "z_max", max(co.z for co in coords), "x_avg", sum(abs(co.x) for co in coords) / len(coords))
print("BOUNDS", [(min(v.co[i] for v in body.data.vertices), max(v.co[i] for v in body.data.vertices)) for i in range(3)])
