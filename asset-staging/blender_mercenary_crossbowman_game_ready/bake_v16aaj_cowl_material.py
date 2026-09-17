"""Bake the V16AAJ mixed reference projection into a glTF-safe 4K PBR material."""

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aaj_clean_draped_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16aaj_baked_cowl_candidate.blend"
TEXTURE = STAGING / "textures" / "cowl_reference_blended_basecolor_4k_v16.png"
COWL_NAME = "Mercenary_CleanDrapedScarf_v16aaj_LOD0"


def only_active(obj):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
cowl = bpy.data.objects[COWL_NAME]
only_active(cowl)

# Build a dedicated non-overlapping atlas while retaining the tiled wool and
# front/back projection UV sets used by the source material.
atlas = cowl.data.uv_layers.get("ScarfAtlasUV")
if atlas is None:
    atlas = cowl.data.uv_layers.new(name="ScarfAtlasUV")
cowl.data.uv_layers.active = atlas
atlas.active_render = True
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.05, island_margin=0.008, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

TEXTURE.parent.mkdir(parents=True, exist_ok=True)
image = bpy.data.images.get("CowlReferenceBlendedBaseColor4K_v16")
if image is None:
    image = bpy.data.images.new(
        "CowlReferenceBlendedBaseColor4K_v16",
        width=4096,
        height=4096,
        alpha=False,
        float_buffer=False,
    )
image.generated_color = (0.035, 0.028, 0.022, 1.0)

source_material = cowl.data.materials[0]
tree = source_material.node_tree
nodes = tree.nodes
links = tree.links
output = next(node for node in nodes if node.type == "OUTPUT_MATERIAL")
blend = nodes.get("Mix") or next(
    (node for node in nodes if node.type == "MIX_RGB"), None
)
if blend is None:
    raise RuntimeError("V16AAJ colour blend node is missing")

bake_target = nodes.new("ShaderNodeTexImage")
bake_target.name = "V16_CowlBakeTarget"
bake_target.image = image
nodes.active = bake_target

# Emission baking captures the mixed photographic colour exactly, without
# studio-light shading becoming part of the game texture.
emission = nodes.new("ShaderNodeEmission")
links.new(blend.outputs["Color"], emission.inputs["Color"])
old_surface_links = list(output.inputs["Surface"].links)
for link in old_surface_links:
    links.remove(link)
links.new(emission.outputs["Emission"], output.inputs["Surface"])

scene.render.engine = "CYCLES"
scene.cycles.samples = 1
scene.render.bake.use_clear = True
scene.render.bake.margin = 24
scene.render.bake.target = "IMAGE_TEXTURES"
bpy.ops.object.bake(type="EMIT")
image.filepath_raw = str(TEXTURE)
image.file_format = "PNG"
image.save()
image.pack()

# Replace the Blender-only mixed graph with a simple glTF-exportable PBR
# graph.  The established tiled wool normal map is retained separately.
normal_image = next(
    (
        node.image
        for node in nodes
        if node.type == "TEX_IMAGE"
        and node.image is not None
        and "normal" in node.image.name.lower()
    ),
    None,
)
material = bpy.data.materials.new("MAT_Cowl_ReferenceBaked_PBR_4K_v16")
material.use_nodes = True
material.use_backface_culling = False
material.diffuse_color = (0.12, 0.095, 0.075, 1.0)
new_nodes = material.node_tree.nodes
new_links = material.node_tree.links
new_nodes.clear()
new_output = new_nodes.new("ShaderNodeOutputMaterial")
bsdf = new_nodes.new("ShaderNodeBsdfPrincipled")
bsdf.inputs["Roughness"].default_value = 0.78
bsdf.inputs["Metallic"].default_value = 0.0
atlas_uv = new_nodes.new("ShaderNodeUVMap")
atlas_uv.uv_map = "ScarfAtlasUV"
base_tex = new_nodes.new("ShaderNodeTexImage")
base_tex.image = image
base_tex.interpolation = "Linear"
new_links.new(atlas_uv.outputs["UV"], base_tex.inputs["Vector"])
new_links.new(base_tex.outputs["Color"], bsdf.inputs["Base Color"])
if normal_image is not None:
    normal_image.colorspace_settings.name = "Non-Color"
    tiled_uv = new_nodes.new("ShaderNodeUVMap")
    tiled_uv.uv_map = "UVMap"
    normal_tex = new_nodes.new("ShaderNodeTexImage")
    normal_tex.image = normal_image
    normal = new_nodes.new("ShaderNodeNormalMap")
    normal.inputs["Strength"].default_value = 0.58
    new_links.new(tiled_uv.outputs["UV"], normal_tex.inputs["Vector"])
    new_links.new(normal_tex.outputs["Color"], normal.inputs["Color"])
    new_links.new(normal.outputs["Normal"], bsdf.inputs["Normal"])
new_links.new(bsdf.outputs["BSDF"], new_output.inputs["Surface"])
cowl.data.materials.clear()
cowl.data.materials.append(material)
cowl["gltf_safe_baked_4k"] = True
cowl["baked_basecolor"] = str(TEXTURE)

for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
print(f"V16_AAJ_BAKED={OUTPUT}")
print(f"V16_AAJ_TEXTURE={TEXTURE}")
