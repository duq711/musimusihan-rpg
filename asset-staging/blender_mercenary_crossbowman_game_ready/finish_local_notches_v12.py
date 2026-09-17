"""Finish and export the v12 four-notch shoulder/cowl repair candidate.

The deterministic prototype starts from v11 and adds only four tiny closed
cloth wedges under the audited rear shoulder/cowl holes.  This finishing
stage validates topology, weights, normals, exact top-close rays and budget;
renders delivery/high-ring QA; and exports a new v12 GLB.  Production and the
interactive viewer are intentionally untouched.
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
PROTOTYPE = STAGING / "build_v12_hidden_mantle_hair.py"
SOURCE_SUMMARY = STAGING / "build_summary_v11.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v12.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v12.json"
OUTPUT_GLB = (
    ROOT
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v12.glb"
)

# Leaves the rebuilt v12 scene and its audit variables live in this namespace.
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


def weight_sum_range(obj):
    values = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    if not values:
        raise RuntimeError(f"{obj.name} has no skin weights")
    return min(values), max(values)


if len(pre_mantle_misses) != 421 or post_mantle_misses:
    raise RuntimeError(
        f"Exact top-close ray audit failed: pre={len(pre_mantle_misses)}, "
        f"post={len(post_mantle_misses)}"
    )

if triangle_count(notch_patches) != 48:
    raise RuntimeError(f"Unexpected notch repair size: {triangle_count(notch_patches)} triangles")

closed_objects = {
    "cowl": cowl,
    "yoke": bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"],
    "liner": bpy.data.objects["Mercenary_InnerCowl_Liner_LOD0"],
    "gussets": gussets,
    "notch_patches": notch_patches,
}
nonmanifold_counts = {
    label: nonmanifold_edge_count(obj) for label, obj in closed_objects.items()
}
if any(nonmanifold_counts.values()):
    raise RuntimeError(f"Open repair geometry found: {nonmanifold_counts}")

patch_weight_range = weight_sum_range(notch_patches)
if patch_weight_range[0] < 0.999 or patch_weight_range[1] > 1.001:
    raise RuntimeError(f"Invalid patch weight sums: {patch_weight_range}")
if not any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in notch_patches.modifiers):
    raise RuntimeError("Notch repair is not bound to the Rigify armature")

# The corrected left gusset component must mirror the already-correct right
# component.  This catches a second inversion before Godot backface culling.
if len(gussets.data.polygons) != 10:
    raise RuntimeError(f"Unexpected gusset polygon count: {len(gussets.data.polygons)}")
gusset_mirror_dots = []
for left, right in zip(gussets.data.polygons[:5], gussets.data.polygons[5:]):
    mirrored_right = Vector((-right.normal.x, right.normal.y, right.normal.z))
    gusset_mirror_dots.append(left.normal.dot(mirrored_right))
if min(gusset_mirror_dots) < 0.95:
    raise RuntimeError(f"Left gusset normals are not outward/mirrored: {gusset_mirror_dots}")

safe_material_index = cowl.data.materials.find(cloth_material.name)
cowl_material_counts = Counter(polygon.material_index for polygon in cowl.data.polygons)
if cowl_material_counts[0] != 6205 or cowl_material_counts[1] != 6141:
    raise RuntimeError("Original cowl front/back projection faces changed")
if cowl_material_counts[safe_material_index] != 1005:
    raise RuntimeError("Selective cowl top-face material assignment changed")
if notch_patches.data.materials[0] != cloth_material:
    raise RuntimeError("Notch repair does not use the safe charcoal cowl material")
if hair_objects:
    raise RuntimeError(f"Rejected additional hair geometry returned: {hair_objects}")
for rejected_name in ("Mercenary_HiddenShoulder_Mantle_LOD0", "Hair_Unkempt_Strands"):
    if bpy.data.objects.get(rejected_name) is not None:
        raise RuntimeError(f"Rejected broad/exploding object exists: {rejected_name}")


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
    name = f"diagnostic_v12_{key}.png" if diagnostic else f"mercenary_game_ready_v12_{key}.png"
    output = PREVIEWS / name
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    if diagnostic:
        high_angle_paths.append(str(output))
    else:
        preview_paths[key] = str(output)


render_final(
    "top_close",
    (0.0, 0.0, 5.0),
    (0.0, 0.02, 1.49),
    ortho_scale=0.95,
    resolution=(1200, 900),
)
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

# Store the blend at the exact previously failing view for direct inspection.
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = failure_location
look_at_final(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

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
summary["asset"] = "mercenary_crossbowman_game_ready_v12"
summary["triangles"] = total_triangles
summary["triangle_breakdown"] = {obj.name: triangle_count(obj) for obj in character_meshes}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["high_angle_qa"] = high_angle_paths
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["rear_notch_repair"] = {
    "source": "v11 validated geometry",
    "object": notch_patches.name,
    "component_count": 4,
    "triangles": triangle_count(notch_patches),
    "closed_manifold": nonmanifold_counts["notch_patches"] == 0,
    "audited_pixel_misses_before": len(pre_mantle_misses),
    "audited_pixel_misses_after": len(post_mantle_misses),
    "footprints": [label for label, _outline, _top_z in PATCH_SPECS],
    "front_overlap_depth_m": 0.009,
    "rear_seam_depth_m": 0.00075,
    "material": cloth_material.name,
    "weight_sum_range": list(patch_weight_range),
    "rig": rig.name,
    "left_gusset_normals_corrected": True,
    "gusset_mirror_dot_min": min(gusset_mirror_dots),
    "existing_v11_hair_preserved": True,
    "broad_mantle_or_floating_panel_added": False,
    "duplicate_limb_added": False,
    "front_back_three_quarter_silhouette_changed": False,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("V12_FINAL_TRIANGLES", total_triangles)
print("V12_FINAL_MESHES", len(character_meshes))
print("V12_FINAL_NONMANIFOLD", nonmanifold_counts)
print("V12_FINAL_PATCH_WEIGHT_RANGE", patch_weight_range)
print("V12_FINAL_GUSSET_MIRROR_DOT_MIN", min(gusset_mirror_dots))
print("V12_FINAL_EXACT_RAY_MISSES", len(post_mantle_misses))
print("V12_FINAL_BLEND", OUTPUT_BLEND)
print("V12_FINAL_GLB", OUTPUT_GLB)
print("V12_FINAL_SUMMARY", OUTPUT_SUMMARY)
