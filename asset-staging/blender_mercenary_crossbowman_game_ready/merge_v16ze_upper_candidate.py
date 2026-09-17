"""Merge the best draped cowl with the cleaned upper-body candidate."""

from __future__ import annotations

from collections import defaultdict
import json
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zd_coherent_upper_candidate.blend"
COWL_SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16_compact_crumpled_cowl_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16ze_integrated_upper_candidate.blend"
REPORT = STAGING / "v16ze_integrated_upper_report.json"


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj):
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        verts = list(poly.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    nonmanifold = sum(1 for count in edge_faces.values() if count != 2)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        seed = unseen.pop()
        stack = [seed]
        while stack:
            current = stack.pop()
            for neighbour in adjacency[current]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    stack.append(neighbour)
    return nonmanifold, components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
asset_collection = donor.users_collection[0]

old_cowl = bpy.data.objects.get("Mercenary_CoherentDrapedCowl_v16z_LOD0")
if old_cowl is not None:
    old_mesh = old_cowl.data
    bpy.data.objects.remove(old_cowl, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)

# The chosen cowl already has UVs, 4K wool, manifold topology and Rigify
# weights.  Append it, then explicitly bind it to this file's rig.
with bpy.data.libraries.load(str(COWL_SOURCE), link=False) as (available, requested):
    requested.objects = ["Mercenary_CompactCrumpledCowl_LOD0"]
cowl = requested.objects[0]
if cowl is None:
    raise RuntimeError("Could not append Mercenary_CompactCrumpledCowl_LOD0")
if not cowl.users_collection:
    asset_collection.objects.link(cowl)
elif asset_collection not in cowl.users_collection:
    asset_collection.objects.link(cowl)
cowl.name = "Mercenary_IntegratedDrapedCowl_v16ze_LOD0"
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
for modifier in cowl.modifiers:
    if modifier.type == "ARMATURE":
        modifier.object = rig
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16ZE selected compact draped cowl on cleaned upper body"

# Remove only donor collar faces fully hidden by the new cowl.  This eliminates
# the last paper-thin spikes seen through the top opening without touching the
# visible chest, sleeves, or forearms.
bm = bmesh.new()
bm.from_mesh(donor.data)
hidden_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    if abs(center.x) < 0.255 and center.z > 1.385:
        hidden_faces.append(face)
removed_hidden_collar_faces = len(hidden_faces)
if hidden_faces:
    bmesh.ops.delete(bm, geom=hidden_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16ze_removed_hidden_collar_faces"] = removed_hidden_collar_faces

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.018, 0.020, 0.024, 1.0)
        background.inputs[1].default_value = 0.22

camera = scene.camera
camera.data.type = "PERSP"


def render(key, location, target, lens=82, resolution=(1200, 1000)):
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    path = PREVIEWS / f"diagnostic_v16ze_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top_close": render("integrated_upper_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("integrated_upper_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.46), 86),
    "upper_three_quarter": render("integrated_upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.43), 88),
    "front": render("integrated_upper_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("integrated_upper_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

nonmanifold, components = topology(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
report = {
    "source": str(SOURCE),
    "cowl_source": str(COWL_SOURCE),
    "candidate": str(OUTPUT),
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": nonmanifold,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "removed_hidden_collar_faces": removed_hidden_collar_faces,
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
cowl["v16ze_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZE_REPORT=" + json.dumps(report, sort_keys=True))
