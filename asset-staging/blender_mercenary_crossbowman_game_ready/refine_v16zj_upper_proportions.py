"""Refine the v16 upper proportions without touching production outputs."""

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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zg_narrow_interface_seal.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zj_refined_upper_proportions.blend"
REPORT = STAGING / "v16zj_refined_upper_proportions_report.json"


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
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            found = adjacency[stack.pop()] & unseen
            unseen.difference_update(found)
            stack.extend(found)
    return sum(count != 2 for count in edge_faces.values()), components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_IntegratedDrapedCowl_v16ze_LOD0"]
seal = bpy.data.objects.get("Mercenary_NarrowInterfaceSeal_v16zg_LOD0")
if seal is None:
    raise RuntimeError("Missing narrow interface seal")

# The previous cowl was vertically over-scaled and read as a rigid lampshade.
# Compress only its upper volume, retain lower coverage, shorten the rear
# projection and lightly relax the relief so it reads as soft bundled wool.
for vertex in cowl.data.vertices:
    co = vertex.co
    if co.z >= 1.43:
        co.z = 1.43 + (co.z - 1.43) * 0.70
    else:
        co.z = 1.43 + (co.z - 1.43) * 0.88
    if co.y > 0.02:
        co.y = 0.02 + (co.y - 0.02) * 0.86
    co.x *= 0.97
cowl.data.update()

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
relax = cowl.modifiers.new("V16ZJ_SoftClothRelax", "SMOOTH")
relax.factor = 0.12
relax.iterations = 1
bpy.ops.object.modifier_apply(modifier=relax.name)
cowl["source"] = "V16ZJ softened and vertically compacted one-piece wool cowl"
cowl["v16zj_upper_scale"] = 0.70

# Tuck the narrow bridge into the cowl and make its lower edge read as a
# continuation of the dark vest rather than a separate tall neck tube.
outer_wool = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if outer_wool is not None:
    seal.data.materials.clear()
    seal.data.materials.append(outer_wool)
for vertex in seal.data.vertices:
    co = vertex.co
    # Keep the hidden upper overlap, but lower and subtly widen the visible
    # garment root so it meets the chest without a rectangular black gap.
    t = max(0.0, min(1.0, (1.445 - co.z) / 0.075))
    co.x *= 1.0 + 0.10 * t
    if co.y < 0.015:
        co.y = 0.015 + (co.y - 0.015) * (1.0 + 0.05 * t)
    co.z -= 0.012 * t
seal.data.update()
seal["source"] = "V16ZJ compact under-cowl outer-vest transition"

# Remove the isolated rear scan flap that was visible underneath the cowl.
bm = bmesh.new()
bm.from_mesh(donor.data)
rear_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    if abs(center.x) < 0.19 and center.y > 0.135 and center.z > 1.275:
        rear_faces.append(face)
removed_rear_faces = len(rear_faces)
if rear_faces:
    bmesh.ops.delete(bm, geom=rear_faces, context="FACES")
    loose = [vert for vert in bm.verts if not vert.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zj_removed_rear_collar_flap_faces"] = removed_rear_faces

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.018, 0.020, 0.024, 1.0)
        background.inputs[1].default_value = 0.22

camera = scene.camera


def render(key, location, target, lens=82, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zj_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top_close": render("refined_upper_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("refined_upper_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "upper_three_quarter": render("refined_upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
    "front": render("refined_upper_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("refined_upper_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

checks = {}
for obj in (cowl, seal):
    nonmanifold, components = topology(obj)
    weight_sums = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    checks[obj.name] = {
        "triangles": triangles(obj),
        "nonmanifold_edges": nonmanifold,
        "components": components,
        "weight_sum_range": [min(weight_sums), max(weight_sums)],
    }
    if nonmanifold or components != 1 or min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
        raise RuntimeError(f"Upper validation failed: {obj.name}: {checks[obj.name]}")

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "upper_checks": checks,
    "removed_rear_collar_flap_faces": removed_rear_faces,
    "mesh_count": len(character_meshes),
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZJ_REPORT=" + json.dumps(report, sort_keys=True))
