"""Create v10 with a continuous, non-black cowl/shoulder cloth surface.

V9 closed the real shoulder openings, but the replacement cowl still used
front/back projection faces plus nearly black cowl textures.  At high angles
those faces read as square holes.  V10 keeps all v9 geometry and Rigify data,
then gives the complete cowl and its hidden yoke a single safe 4K cloth PBR
material and coherent UVs.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE_BLEND = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
SOURCE_SUMMARY = STAGING / "build_summary_v9.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v10.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v10.json"
OUTPUT_GLB = (
    WORKSPACE
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v10.glb"
)

PREVIEWS.mkdir(parents=True, exist_ok=True)
OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

scene = bpy.context.scene
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
metarig = bpy.data.objects["metarig_mercenary_v4"]


def triangle_count(obj):
    return sum(max(1, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


def nonmanifold_edge_count(obj):
    edge_faces = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for first, second in zip(vertices, vertices[1:] + vertices[:1]):
            edge_faces[tuple(sorted((first, second)))] += 1
    return sum(count != 2 for count in edge_faces.values())


base_gambeson = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]
safe_cowl = base_gambeson.copy()
safe_cowl.name = "MAT_CowlSafe_ContinuousCloth_PBR_4K"
safe_cowl.diffuse_color = (0.31, 0.25, 0.20, 1.0)
safe_cowl["source_4k_material"] = base_gambeson.name
safe_cowl["purpose"] = "continuous medium-value cowl cloth; no black projection patches"

# Multiply the beige cloth map by a medium warm-gray factor.  Blender's glTF
# exporter recognizes this exact RGBA Mix/Multiply pattern and exports the
# constant as baseColorFactor while retaining the 4K texture.
nodes = safe_cowl.node_tree.nodes
links = safe_cowl.node_tree.links
base_color_texture = nodes["BaseColor_4K"]
principled = nodes["Principled BSDF"]
for link in list(links):
    if link.to_node == principled and link.to_socket.name == "Base Color":
        links.remove(link)
multiply = nodes.new("ShaderNodeMix")
multiply.name = "Cowl_MediumValue_Multiply"
multiply.data_type = "RGBA"
multiply.blend_type = "MULTIPLY"
multiply.inputs[0].default_value = 1.0
multiply.inputs[7].default_value = (0.66, 0.58, 0.50, 1.0)
links.new(base_color_texture.outputs["Color"], multiply.inputs[6])
links.new(multiply.outputs[2], principled.inputs["Base Color"])
principled.inputs["Roughness"].default_value = 0.78


def replace_with_safe_material(obj):
    obj.data.materials.clear()
    obj.data.materials.append(safe_cowl)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True


replace_with_safe_material(cowl)
replace_with_safe_material(yoke)


def rewrite_cylindrical_uv(obj, center_y=0.085):
    uv_layer = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
    for polygon in obj.data.polygons:
        per_loop = []
        for loop_index in polygon.loop_indices:
            coordinate = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            angle_u = math.atan2(coordinate.y - center_y, coordinate.x) / (2.0 * math.pi) + 0.5
            vertical_v = (coordinate.z - 1.400) * 7.5
            per_loop.append([loop_index, angle_u, vertical_v])
        u_values = [item[1] for item in per_loop]
        if max(u_values) - min(u_values) > 0.5:
            for item in per_loop:
                if item[1] < 0.5:
                    item[1] += 1.0
        for loop_index, u, v in per_loop:
            uv_layer.data[loop_index].uv = (u * 3.0, v)


def rewrite_planar_uv(obj):
    uv_layer = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
    for polygon in obj.data.polygons:
        for loop_index in polygon.loop_indices:
            coordinate = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (coordinate.x * 6.0, coordinate.y * 6.0)


rewrite_cylindrical_uv(cowl)
rewrite_planar_uv(yoke)

cowl_nonmanifold_edges = nonmanifold_edge_count(cowl)
yoke_nonmanifold_edges = nonmanifold_edge_count(yoke)
if cowl_nonmanifold_edges or yoke_nonmanifold_edges:
    raise RuntimeError(
        "Continuous cloth geometry is unexpectedly open: "
        f"cowl={cowl_nonmanifold_edges}, yoke={yoke_nonmanifold_edges}"
    )


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
preview_paths = {}


def render_ortho(key, location, target, scale, resolution=(1200, 1200), diagnostic=False):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    prefix = "diagnostic_" if diagnostic else "mercenary_game_ready_"
    output = PREVIEWS / f"{prefix}v10_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    if not diagnostic:
        preview_paths[key] = str(output)


def render_perspective(key, location, target, lens, resolution=(1100, 1100), diagnostic=False):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    prefix = "diagnostic_" if diagnostic else "mercenary_game_ready_"
    output = PREVIEWS / f"{prefix}v10_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    if not diagnostic:
        preview_paths[key] = str(output)


rig.hide_viewport = True
rig.hide_set(True)
rig.hide_render = True
metarig.hide_viewport = True
metarig.hide_set(True)
metarig.hide_render = True

render_ortho("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), 1.95, (1500, 900))

azimuth = math.radians(45.0)
elevation = math.radians(80.0)
failure_radius = 4.7
failure_location = (
    failure_radius * math.cos(elevation) * math.sin(azimuth),
    -failure_radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + failure_radius * math.sin(elevation),
)
render_perspective(
    "failure_view",
    failure_location,
    (0.0, 0.06, 1.02),
    78,
    (1400, 1000),
)

# Eight high-angle QA directions.  These are diagnostics rather than delivery
# views, but they ensure the material/UV repair is not camera-specific.
high_angle_qa = []
for direction_index in range(8):
    qa_azimuth = math.radians(direction_index * 45.0)
    qa_location = (
        failure_radius * math.cos(elevation) * math.sin(qa_azimuth),
        -failure_radius * math.cos(elevation) * math.cos(qa_azimuth),
        0.95 + failure_radius * math.sin(elevation),
    )
    key = f"high_{direction_index * 45:03d}"
    render_perspective(
        key,
        qa_location,
        (0.0, 0.06, 1.02),
        78,
        (900, 700),
        diagnostic=True,
    )
    high_angle_qa.append(str(PREVIEWS / f"diagnostic_v10_{key}.png"))

render_ortho("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_ortho("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_perspective("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.00), 72)

# Save the v10 candidate framed at the reported failing view.
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = failure_location
look_at(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
bpy.ops.object.select_all(action="DESELECT")
rig.hide_viewport = False
rig.hide_set(False)
rig.select_set(True)
for obj in character_meshes:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig

export_properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_arguments = {
    "filepath": str(OUTPUT_GLB),
    "export_format": "GLB",
    "export_yup": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_animations": False,
    "export_skins": True,
    "export_def_bones": True,
    "export_armature_object_remove": False,
    "export_rest_position_armature": True,
    "export_all_influences": False,
    "export_influence_nb": 4,
    "export_leaf_bone": False,
    "export_texcoords": True,
    "export_normals": True,
    "export_apply": False,
    "export_morph": False,
    "export_tangents": True,
}
if "use_selection" in export_properties:
    gltf_arguments["use_selection"] = True
elif "export_selected" in export_properties:
    gltf_arguments["export_selected"] = True
bpy.ops.export_scene.gltf(**gltf_arguments)

summary = json.loads(SOURCE_SUMMARY.read_text(encoding="utf-8"))
summary["asset"] = "mercenary_crossbowman_game_ready_v10"
summary["triangles"] = sum(triangle_count(obj) for obj in character_meshes)
summary["triangle_breakdown"] = {obj.name: triangle_count(obj) for obj in character_meshes}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["high_angle_qa"] = high_angle_qa
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["cowl_surface_repair"] = {
    "diagnosis": (
        "v9 square black patches were clean-cowl projection materials plus "
        "near-black cowl basecolor, not background exposure"
    ),
    "safe_material": safe_cowl.name,
    "source_4k_texture_set": "gambeson 4K basecolor/normal/ORM",
    "base_color_factor": [0.66, 0.58, 0.50, 1.0],
    "cowl_faces_remapped": len(cowl.data.polygons),
    "yoke_faces_remapped": len(yoke.data.polygons),
    "cowl_uv": "three-repeat cylindrical with per-face seam correction",
    "yoke_uv": "planar top cloth UV",
    "cowl_nonmanifold_edges": cowl_nonmanifold_edges,
    "yoke_nonmanifold_edges": yoke_nonmanifold_edges,
    "geometry_or_weights_changed": False,
    "front_back_three_quarter_silhouette_changed": False,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V10_SUMMARY", json.dumps(summary))
