"""Build and export the final v11 selective cowl/neck-gap repair candidate.

The prototype script performs the topology/material work from a clean v9
source.  This finishing stage reruns that deterministic build, asserts its
geometry/skin invariants, renders delivery and high-ring QA views, then writes
the standalone v11 blend, GLB, and summary.  Production/viewer paths are never
touched.
"""

from __future__ import annotations

from collections import Counter, defaultdict
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
PROTOTYPE = STAGING / "test_v11b_selective_cowl.py"
SOURCE_SUMMARY = STAGING / "build_summary_v9.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v11.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v11.json"
OUTPUT_GLB = (
    ROOT
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v11.glb"
)

# Execute the deterministic prototype in this namespace.  It opens v9 and
# leaves the repaired scene, cowl, yoke, liner, rig and selected-face set live.
exec(compile(PROTOTYPE.read_text(encoding="utf-8"), str(PROTOTYPE), "exec"), globals())


def triangle_count(obj):
    return sum(max(1, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


def nonmanifold_edge_count(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for first, second in zip(vertices, vertices[1:] + vertices[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return sum(count != 2 for count in counts.values())


if len(selected) != 1005:
    raise RuntimeError(f"Expected 1005 first-hit dark cowl faces, got {len(selected)}")

cowl_nonmanifold = nonmanifold_edge_count(cowl)
yoke_nonmanifold = nonmanifold_edge_count(yoke)
liner_nonmanifold = nonmanifold_edge_count(liner)
gusset_nonmanifold = nonmanifold_edge_count(gussets)
if cowl_nonmanifold or yoke_nonmanifold or liner_nonmanifold or gusset_nonmanifold:
    raise RuntimeError(
        "Unexpected open repair geometry: "
        f"cowl={cowl_nonmanifold}, yoke={yoke_nonmanifold}, "
        f"liner={liner_nonmanifold}, gussets={gusset_nonmanifold}"
    )

liner_weight_sums = [sum(group.weight for group in vertex.groups) for vertex in liner.data.vertices]
yoke_weight_sums = [sum(group.weight for group in vertex.groups) for vertex in yoke.data.vertices]
gusset_weight_sums = [sum(group.weight for group in vertex.groups) for vertex in gussets.data.vertices]
for label, values in (
    ("liner", liner_weight_sums),
    ("yoke", yoke_weight_sums),
    ("gussets", gusset_weight_sums),
):
    if not values or min(values) < 0.999 or max(values) > 1.001:
        raise RuntimeError(f"Invalid {label} weight sums: {min(values):.6f}..{max(values):.6f}")

safe_material_index = cowl.data.materials.find(top_material.name)
cowl_material_counts = Counter(polygon.material_index for polygon in cowl.data.polygons)
if cowl_material_counts[safe_material_index] != 1005:
    raise RuntimeError("Selective cowl material assignment changed unexpectedly")
if cowl_material_counts[0] != 6205 or cowl_material_counts[1] != 6141:
    raise RuntimeError("Original front/back cowl projection faces were not preserved")
if head_scalp_faces != 1944 or head_skin_restored_faces != 3498:
    raise RuntimeError(
        "Unexpected head material split: "
        f"scalp={head_scalp_faces}, restored_skin={head_skin_restored_faces}"
    )


def look_at_final(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
preview_paths = {}
high_angle_paths = []


def render_final(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200), diagnostic=False):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at_final(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    name = f"diagnostic_v11_{key}.png" if diagnostic else f"mercenary_game_ready_v11_{key}.png"
    output = PREVIEWS / name
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    if diagnostic:
        high_angle_paths.append(str(output))
    else:
        preview_paths[key] = str(output)


render_final("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))

radius = 4.7
elevation = math.radians(80.0)
failure_azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(failure_azimuth),
    -radius * math.cos(elevation) * math.cos(failure_azimuth),
    0.95 + radius * math.sin(elevation),
)
render_final("failure_view", failure_location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))

for direction_index in range(8):
    azimuth = math.radians(direction_index * 45.0)
    location = (
        radius * math.cos(elevation) * math.sin(azimuth),
        -radius * math.cos(elevation) * math.cos(azimuth),
        0.95 + radius * math.sin(elevation),
    )
    render_final(
        f"high_{direction_index * 45:03d}",
        location,
        (0.0, 0.06, 1.02),
        lens=78,
        resolution=(900, 700),
        diagnostic=True,
    )

render_final("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render_final("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render_final("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

# Store v11 framed at the exact failure view for direct Blender inspection.
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = failure_location
look_at_final(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
bpy.ops.object.select_all(action="DESELECT")
rig.hide_viewport = False
rig.hide_set(False)
rig.hide_render = False
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
summary["asset"] = "mercenary_crossbowman_game_ready_v11"
summary["triangles"] = sum(triangle_count(obj) for obj in character_meshes)
if not 100000 <= summary["triangles"] <= 150000:
    raise RuntimeError(f"Triangle budget failed: {summary['triangles']}")
summary["triangle_breakdown"] = {obj.name: triangle_count(obj) for obj in character_meshes}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["high_angle_qa"] = high_angle_paths
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["selective_cowl_repair"] = {
    "source": "v9 closed topology",
    "original_front_projection_faces_preserved": cowl_material_counts[0],
    "original_back_projection_faces_preserved": cowl_material_counts[1],
    "first_hit_top_dark_faces_remapped": cowl_material_counts[safe_material_index],
    "selector": "original mat5, normal.z > 0.50, cowl-only vertical BVH first hit",
    "safe_material": top_material.name,
    "safe_texture": str(LIFTED_TEXTURE),
    "safe_texture_size": list(lifted_image.size),
    "safe_uv": "planar XY 4x tile on selected loops only",
    "head_repair": {
        "geometry_changed": False,
        "weights_changed": False,
        "misclassified_mat5_faces": head_scalp_faces + head_skin_restored_faces,
        "scalp_faces_to_opaque_hair_2k": head_scalp_faces,
        "ear_neck_side_faces_restored_to_skin_4k": head_skin_restored_faces,
        "split_height_m": 1.66,
        "hair_material": hair_material.name,
        "hair_source_texture": str(HAIR_SOURCE_TEXTURE),
        "hair_texture": str(HAIR_SCALP_TEXTURE),
        "hair_texture_size": list(hair_image.size),
        "alpha_transparency_used": False,
        "source_side_uv_preserved": True,
    },
    "liner": {
        "object": liner.name,
        "triangles": triangle_count(liner),
        "closed_manifold": liner_nonmanifold == 0,
        "inner_center_y": inner_center_y,
        "outer_center_y": outer_center_y,
        "inner_radii": [inner_rx, inner_ry],
        "outer_radii": [outer_rx, outer_ry],
        "height_range": [outer_z, inner_z],
        "rig_bone": "DEF-spine.006",
        "weight_sum_range": [min(liner_weight_sums), max(liner_weight_sums)],
    },
    "yoke": {
        "object": yoke.name,
        "triangles": triangle_count(yoke),
        "closed_manifold": yoke_nonmanifold == 0,
        "outer_tip_extension_m": 0.015,
        "rise_m": 0.002,
        "weight_sum_range": [min(yoke_weight_sums), max(yoke_weight_sums)],
    },
    "gussets": {
        "object": gussets.name,
        "triangles": triangle_count(gussets),
        "closed_manifold": gusset_nonmanifold == 0,
        "weight_sum_range": [min(gusset_weight_sums), max(gusset_weight_sums)],
        "purpose": "two seam-sized closed cloth gussets at measured shoulder-cowl notches",
    },
    "cowl_nonmanifold_edges": cowl_nonmanifold,
    "floating_panel_or_duplicate_limb_added": False,
    "front_back_three_quarter_silhouette_changed": False,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V11_SUMMARY", json.dumps(summary))
