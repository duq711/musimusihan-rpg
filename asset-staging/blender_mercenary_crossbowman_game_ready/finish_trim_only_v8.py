"""Create the approved trim-only v8 candidate from the validated v4 blend."""

from __future__ import annotations

import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE_BLEND = STAGING / "mercenary_crossbowman_game_ready_v4.blend"
SOURCE_SUMMARY = STAGING / "build_summary_v4.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v8.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v8.json"
OUTPUT_GLB = (
    WORKSPACE
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v8.glb"
)

PREVIEWS.mkdir(parents=True, exist_ok=True)
OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

scene = bpy.context.scene
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
metarig = bpy.data.objects["metarig_mercenary_v4"]


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


# Approved predicate: trim only the dark, upward-facing donor shards protruding
# from the restored shoulder surface.  No replacement panels are created.
bm = bmesh.new()
bm.from_mesh(donor.data)
trim_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    if not (0.235 < abs(center.x) < 0.505 and 1.455 < center.z < 1.565):
        continue
    if face.material_index != 4 or face.normal.z <= 0.08:
        continue
    trim_faces.append(face)

removed_triangles = sum(max(1, len(face.verts) - 2) for face in trim_faces)
if removed_triangles != 333:
    bm.free()
    raise RuntimeError(f"Expected exactly 333 trim triangles, found {removed_triangles}")
bmesh.ops.delete(bm, geom=trim_faces, context="FACES_ONLY")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.resolution_percentage = 100
preview_paths = {}


def render_ortho(key, location, target, scale, resolution=(1200, 1200)):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"mercenary_game_ready_v8_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(path)


def render_perspective(key, location, target, lens, resolution=(1100, 1100)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"mercenary_game_ready_v8_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(path)


rig.hide_viewport = True
rig.hide_set(True)
rig.hide_render = True
metarig.hide_viewport = True
metarig.hide_set(True)
metarig.hide_render = True
render_ortho("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_ortho("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_perspective("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.00), 72)
render_perspective("portrait", (0.42, -1.42, 1.69), (0.0, -0.03, 1.61), 92)

# Save a clean Blender presentation while retaining the complete hidden rig.
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
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
gltf_args = {
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
    gltf_args["use_selection"] = True
elif "export_selected" in export_properties:
    gltf_args["export_selected"] = True
bpy.ops.export_scene.gltf(**gltf_args)

summary = json.loads(SOURCE_SUMMARY.read_text(encoding="utf-8"))
summary["asset"] = "mercenary_crossbowman_game_ready_v8"
summary["triangles"] = sum(triangle_count(obj) for obj in character_meshes)
summary["triangle_breakdown"] = {
    obj.name: triangle_count(obj) for obj in character_meshes
}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["shoulder_finish"] = {
    "mode": "trim-only; no replacement shoulder panels",
    "source": "validated v4 blend",
    "protruding_donor_triangles_removed": removed_triangles,
    "predicate": (
        "0.235 < abs(center.x) < 0.505; 1.455 < center.z < 1.565; "
        "material_index == 4; normal.z > 0.08"
    ),
    "added_geometry": False,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V8_SUMMARY", json.dumps(summary))
