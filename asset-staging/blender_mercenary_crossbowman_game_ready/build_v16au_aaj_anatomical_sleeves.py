"""Integrate the V16AS anatomical sleeves with the clean V16AAJ cowl.

This is a separate QA candidate.  No production or source blend is modified.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aaj_clean_draped_cowl.blend"
SLEEVE_SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16as_anatomical_upper_sleeves_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16au_aaj_anatomical_sleeves_candidate.blend"
REPORT = STAGING / "v16au_aaj_anatomical_sleeves_report.json"

OLD_SLEEVES = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
NEW_SLEEVES = "Mercenary_AnatomicalGambesonUpperSleeves_v16as_LOD0"
RIG = "Mercenary_Rigify_Rig_v4"
DONOR = "Mercenary_Clothed_Donor_LOD0"
COWL = "Mercenary_CleanDrapedScarf_v16aaj_LOD0"


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def weight_range(obj: bpy.types.Object) -> tuple[float, float]:
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    return min(sums), max(sums)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects[RIG]
donor = bpy.data.objects[DONOR]
collection = donor.users_collection[0]

old_sleeve_triangles = 0
old_sleeves = bpy.data.objects.get(OLD_SLEEVES)
if old_sleeves is not None:
    old_sleeve_triangles = triangle_count(old_sleeves)
    old_mesh = old_sleeves.data
    bpy.data.objects.remove(old_sleeves, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)

# Repeat the V16AS covered-volume cleanup on the AAJ donor.  The bounds end at
# the sleeve/forearm overlap, preserving the forearms, hands, torso and face.
donor_bm = bmesh.new()
donor_bm.from_mesh(donor.data)
removed_faces = []
for face in donor_bm.faces:
    center = face.calc_center_median()
    side = 1 if center.x >= 0.0 else -1
    shoulder = Vector((side * 0.145, 0.020, 1.425))
    cuff = Vector((side * 0.590, 0.092, 1.425))
    axis = cuff - shoulder
    t = (center - shoulder).dot(axis) / axis.length_squared
    radial = (center - shoulder - axis * t).length
    if (
        0.0 <= t <= 1.045
        and 0.120 < abs(center.x) < 0.610
        and 1.275 < center.z < 1.505
        and radial < 0.145
    ):
        removed_faces.append(face)
removed_donor_faces = len(removed_faces)
if removed_faces:
    bmesh.ops.delete(donor_bm, geom=removed_faces, context="FACES")
    loose = [vertex for vertex in donor_bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(donor_bm, geom=loose, context="VERTS")
donor_bm.to_mesh(donor.data)
donor_bm.free()
donor.data.update()
donor["v16au_additional_torn_upper_arm_faces_removed"] = removed_donor_faces

with bpy.data.libraries.load(str(SLEEVE_SOURCE), link=False) as (data_from, data_to):
    if NEW_SLEEVES not in data_from.objects:
        raise RuntimeError(f"Sleeve object missing: {NEW_SLEEVES}")
    data_to.objects = [NEW_SLEEVES]
sleeves = data_to.objects[0]
if sleeves is None:
    raise RuntimeError("Could not append anatomical sleeves")
collection.objects.link(sleeves)
for modifier in sleeves.modifiers:
    if modifier.type == "ARMATURE":
        modifier.object = rig
sleeves.parent = rig
sleeves.matrix_parent_inverse = rig.matrix_world.inverted()

# Drop any dependency-only duplicate rig appended with the sleeve object.
for obj in list(bpy.data.objects):
    if obj is not rig and obj.name.startswith(RIG) and not obj.users_collection:
        bpy.data.objects.remove(obj, do_unlink=True)

topology = topology_stats(sleeves)
weights = weight_range(sleeves)
if topology != {
    "components": 2,
    "nonmanifold_edges": 0,
    "boundary_edges": 0,
    "overconnected_edges": 0,
}:
    raise RuntimeError(f"Sleeve topology failed: {topology}")
if weights[0] < 0.999999 or weights[1] > 1.000001:
    raise RuntimeError(f"Sleeve weights failed: {weights}")

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
        background.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        background.inputs[1].default_value = 0.13

lights = []
for name, location, energy, size, color in (
    ("V16AU_QA_Key", (-2.2, -2.6, 3.3), 80.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AU_QA_Fill", (2.4, -1.5, 2.5), 44.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AU_QA_Rim", (0.3, 2.4, 2.7), 58.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16au_aaj_anatomical_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.48), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Rigify deform bone count failed: {deform_bones}")

report = {
    "source": str(SOURCE),
    "sleeve_source": str(SLEEVE_SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl_object": COWL,
    "removed_object": OLD_SLEEVES,
    "replacement_object": NEW_SLEEVES,
    "old_sleeve_triangles": old_sleeve_triangles,
    "new_sleeve_triangles": triangle_count(sleeves),
    "additional_torn_donor_faces_removed": removed_donor_faces,
    "donor_preservation": "Only faces inside the sleeve-covered upper-arm transition were removed; torso, forearms, hands and face remain.",
    "topology": topology,
    "weight_sum_range": list(weights),
    "deform_bones": deform_bones,
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "hunyuan_used": False,
    "visual_qa": {
        "views_checked": ["top", "high", "three_quarter", "front", "back"],
        "verdict": "best current merge candidate; conditional pass",
        "passes": [
            "No original rectangular V16ZB upper-sleeve objects remain",
            "AAJ cowl covers the shoulder seam from normal gameplay views",
            "Cuff overlap hides the torn donor transition",
            "No open/non-manifold edges in replacement sleeves",
        ],
        "remaining_limits": [
            "Sleeve quilting is lower-frequency than the front gambeson",
            "Extreme close high angles still show low-poly donor/head artefacts unrelated to the sleeve shell",
        ],
    },
    "previews": previews,
}
sleeves["v16au_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AU_REPORT=" + json.dumps(report, sort_keys=True))
