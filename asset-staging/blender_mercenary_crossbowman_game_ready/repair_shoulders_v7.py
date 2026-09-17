"""Finish the restored v4 shoulders with fitted, rigged cloth caps.

This script opens the already validated v4 blend, removes only protruding dark
top-surface shards, adds two thin closed quilted-cloth shoulder panels, weights
them to the existing Rigify deform rig, renders QA views and exports v7.
"""

from __future__ import annotations

import json
import math
import os
import struct
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE_SUMMARY = STAGING / "build_summary_v4.json"
OUTPUT_SUMMARY = STAGING / "build_summary_v7.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v7.blend"
OUTPUT_GLB = (
    WORKSPACE
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v7.glb"
)

scene = bpy.context.scene
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
metarig = bpy.data.objects["metarig_mercenary_v4"]
asset_collection = donor.users_collection[0]


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def apply_modifier(obj, modifier):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)


# Remove only the torn dark upper-surface shards that protrude through the new
# shoulder caps.  Front/back projected chest and quilted sleeve faces remain.
donor_bm = bmesh.new()
donor_bm.from_mesh(donor.data)
ragged_faces = []
for face in donor_bm.faces:
    center = face.calc_center_median()
    if not (0.235 < abs(center.x) < 0.505 and 1.455 < center.z < 1.565):
        continue
    if face.material_index != 4:
        continue
    if face.normal.z <= 0.08:
        continue
    ragged_faces.append(face)
ragged_shoulder_triangles_removed = sum(
    max(1, len(face.verts) - 2) for face in ragged_faces
)
if ragged_faces:
    bmesh.ops.delete(donor_bm, geom=ragged_faces, context="FACES_ONLY")
donor_bm.to_mesh(donor.data)
donor_bm.free()
donor.data.update()


def shoulder_top_z(abs_x, transverse):
    outward = (abs_x - 0.215) / 0.270
    return (
        1.535
        - 0.043 * outward
        - 0.040 * transverse * transverse
        + 0.002 * math.cos(transverse * math.pi)
    )


def make_shoulder_panel(side):
    nx = 18
    ny = 11
    vertices = []
    faces = []

    for layer in range(2):
        for ix in range(nx):
            u = ix / (nx - 1)
            abs_x = 0.215 + 0.270 * u
            half_depth = 0.175 - 0.040 * u
            for iy in range(ny):
                v = iy / (ny - 1)
                transverse = 2.0 * v - 1.0
                x = side * abs_x
                y = transverse * half_depth
                top_z = shoulder_top_z(abs_x, transverse)
                z = top_z if layer == 0 else top_z - 0.006
                vertices.append((x, y, z))

    layer_size = nx * ny

    def index(layer, ix, iy):
        return layer * layer_size + ix * ny + iy

    for ix in range(nx - 1):
        for iy in range(ny - 1):
            a = index(0, ix, iy)
            b = index(0, ix + 1, iy)
            c = index(0, ix + 1, iy + 1)
            d = index(0, ix, iy + 1)
            faces.append((a, b, c, d) if side > 0 else (d, c, b, a))
            a = index(1, ix, iy)
            b = index(1, ix, iy + 1)
            c = index(1, ix + 1, iy + 1)
            d = index(1, ix + 1, iy)
            faces.append((a, b, c, d) if side > 0 else (d, c, b, a))

    perimeter = []
    perimeter.extend((ix, 0) for ix in range(nx))
    perimeter.extend((nx - 1, iy) for iy in range(1, ny))
    perimeter.extend((ix, ny - 1) for ix in range(nx - 2, -1, -1))
    perimeter.extend((0, iy) for iy in range(ny - 2, 0, -1))
    for current, following in zip(perimeter, perimeter[1:] + perimeter[:1]):
        a = index(0, *current)
        b = index(0, *following)
        c = index(1, *following)
        d = index(1, *current)
        faces.append((a, b, c, d) if side > 0 else (d, c, b, a))

    mesh = bpy.data.meshes.new(
        "Mercenary_ShoulderCap_%s_LOD0_Mesh" % ("L" if side > 0 else "R")
    )
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    panel = bpy.data.objects.new(
        "Mercenary_ShoulderCap_%s_LOD0" % ("L" if side > 0 else "R"), mesh
    )
    asset_collection.objects.link(panel)
    panel["game_asset"] = True
    panel["part_category"] = "ClothedBody"
    panel["source"] = "V7 fitted quilted-cloth shoulder cap"

    for material in donor.data.materials:
        mesh.materials.append(material)
    for poly in mesh.polygons:
        poly.material_index = 3

    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        normal = poly.normal
        absolute = (abs(normal.x), abs(normal.y), abs(normal.z))
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if absolute[2] >= absolute[0] and absolute[2] >= absolute[1]:
                uv = (co.x * 6.0, co.y * 6.0)
            elif absolute[1] >= absolute[0]:
                uv = (co.x * 6.0, co.z * 6.0)
            else:
                uv = (co.y * 6.0, co.z * 6.0)
            uv_layer.data[loop_index].uv = uv

    bevel = panel.modifiers.new("SoftClothEdge", "BEVEL")
    bevel.width = 0.0025
    bevel.segments = 2
    bevel.limit_method = "ANGLE"
    apply_modifier(panel, bevel)
    for poly in panel.data.polygons:
        poly.use_smooth = True
    return panel


shoulder_panels = [make_shoulder_panel(1.0), make_shoulder_panel(-1.0)]

deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}


def smoothstep(value, low, high):
    t = max(0.0, min(1.0, (value - low) / max(1.0e-8, high - low)))
    return t * t * (3.0 - 2.0 * t)


def panel_weights(co):
    side = "L" if co.x >= 0.0 else "R"
    ax = abs(co.x)
    groups = {}

    def add(name, weight):
        if name in deform_names and weight > 1.0e-6:
            groups[name] = groups.get(name, 0.0) + weight

    if ax < 0.345:
        t = smoothstep(ax, 0.205, 0.345)
        add("DEF-spine.004", 1.0 - t)
        add("DEF-upper_arm." + side, t)
    elif ax < 0.485:
        t = smoothstep(ax, 0.345, 0.485)
        add("DEF-upper_arm." + side, 1.0 - 0.65 * t)
        add("DEF-upper_arm." + side + ".001", 0.65 * t)
    else:
        add("DEF-upper_arm." + side + ".001", 1.0)
    total = sum(groups.values())
    return {name: weight / total for name, weight in groups.items()}


for panel in shoulder_panels:
    cache = {}
    for vertex in panel.data.vertices:
        for bone_name, weight in panel_weights(vertex.co).items():
            group = cache.get(bone_name)
            if group is None:
                group = panel.vertex_groups.new(name=bone_name)
                cache[bone_name] = group
            group.add([vertex.index], weight, "REPLACE")
    modifier = panel.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    panel.parent = rig
    panel.matrix_parent_inverse = rig.matrix_world.inverted()


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
    path = PREVIEWS / f"mercenary_game_ready_v7_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(path)


def render_perspective(key, location, target, lens, resolution=(1100, 1100)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"mercenary_game_ready_v7_{key}.png"
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

# Save a clean presentation with armatures hidden.
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

# Export the complete rigged character, excluding the preview studio.
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

properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
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
if "use_selection" in properties:
    gltf_args["use_selection"] = True
elif "export_selected" in properties:
    gltf_args["export_selected"] = True
bpy.ops.export_scene.gltf(**gltf_args)

summary = json.loads(SOURCE_SUMMARY.read_text(encoding="utf-8"))
summary["asset"] = "mercenary_crossbowman_game_ready_v7"
summary["triangles"] = sum(triangle_count(obj) for obj in character_meshes)
summary["triangle_breakdown"] = {
    obj.name: triangle_count(obj) for obj in character_meshes
}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["shoulder_repair"] = {
    "mode": "two fitted thin quilted-cloth caps weighted to Rigify",
    "ragged_shoulder_triangles_removed": ragged_shoulder_triangles_removed,
    "panel_triangles": {
        panel.name: triangle_count(panel) for panel in shoulder_panels
    },
    "intentional_layer": True,
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V7_SUMMARY", json.dumps(summary))
