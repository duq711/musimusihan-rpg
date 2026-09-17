"""Test a clean, closed coherent cowl after removing hidden scan fragments."""

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zd_coherent_upper_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zk_clean_coherent_upper.blend"
REPORT = STAGING / "v16zk_clean_coherent_upper_report.json"


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        verts = list(poly.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            counts[tuple(sorted((a, b)))] += 1
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
    return sum(value != 2 for value in counts.values()), components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_CoherentDrapedCowl_v16z_LOD0"]

# Delete only the scan fragments inside the combined coverage envelope of the
# one-piece cowl and the clean upper sleeves.  The visible chest starts below
# this mask and the original forearms remain untouched.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    central = ax < 0.285 and center.z > 1.325
    shoulder = 0.285 <= ax < 0.505 and center.z > 1.355
    rear = ax < 0.43 and center.y > 0.135 and center.z > 1.285
    if central or shoulder or rear:
        remove_faces.append(face)
removed = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vert for vert in bm.verts if not vert.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zk_removed_hidden_upper_scan_faces"] = removed

# Replace the deleted scan fragments with a compact sleeveless upper-vest
# section.  This is a torso garment shell (not a neck ring): it follows the
# chest/back volume and overlaps both the existing coat below and cowl above.
material = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if material is None:
    material = cowl.data.materials[0]
COUNT = 192
vest_vertices = []
vest_faces = []
for index in range(COUNT):
    theta = math.tau * index / COUNT
    ct, st = math.cos(theta), math.sin(theta)
    front = max(0.0, -st)
    back = max(0.0, st)
    side = abs(ct)
    wobble = 0.0025 * math.sin(3.0 * theta + 0.4)
    outer_top_rx = 0.218 + 0.010 * side + wobble
    outer_bottom_rx = 0.198 + 0.006 * side + wobble
    outer_top_ry = 0.126 + 0.082 * back + 0.008 * front + wobble
    outer_bottom_ry = 0.138 + 0.074 * back + 0.006 * front + wobble
    inner_rx = 0.126 + 0.003 * math.sin(2.0 * theta)
    inner_ry = 0.091 + 0.006 * back
    top_z = 1.445 + 0.008 * back - 0.006 * front + 0.003 * math.sin(2.0 * theta)
    bottom_z = 1.215 + 0.026 * side + 0.006 * back
    vest_vertices.extend((
        (outer_top_rx * ct, 0.018 + outer_top_ry * st, top_z),
        (outer_bottom_rx * ct, 0.018 + outer_bottom_ry * st, bottom_z),
        (inner_rx * ct, 0.018 + inner_ry * st, top_z - 0.004),
        (inner_rx * ct, 0.018 + inner_ry * st, bottom_z + 0.004),
    ))
for index in range(COUNT):
    nxt = (index + 1) % COUNT
    ot, ob, it, ib = index * 4, index * 4 + 1, index * 4 + 2, index * 4 + 3
    not_, nob, nit, nib = nxt * 4, nxt * 4 + 1, nxt * 4 + 2, nxt * 4 + 3
    vest_faces.extend((
        (ot, ob, nob, not_),
        (it, nit, nib, ib),
        (ot, not_, nit, it),
        (ob, ib, nib, nob),
    ))
vest_mesh = bpy.data.meshes.new("Mercenary_UpperVestBridge_v16zk_Mesh")
vest_mesh.from_pydata(vest_vertices, [], vest_faces)
vest_mesh.update()
vest = bpy.data.objects.new("Mercenary_UpperVestBridge_v16zk_LOD0", vest_mesh)
donor.users_collection[0].objects.link(vest)
vest_mesh.materials.append(material)
for polygon in vest_mesh.polygons:
    polygon.use_smooth = True
bpy.ops.object.select_all(action="DESELECT")
vest.select_set(True)
bpy.context.view_layer.objects.active = vest
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")
groups = {name: vest.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-shoulder.L", "DEF-shoulder.R",
)}
for vertex in vest_mesh.vertices:
    x, _y, z = vertex.co
    side_weight = max(0.0, min(0.38, (abs(x) - 0.13) / 0.22))
    upper = max(0.0, min(1.0, (z - 1.22) / 0.23))
    shoulder_weight = side_weight * (0.50 + 0.35 * upper)
    spine5 = (1.0 - shoulder_weight) * (0.35 + 0.45 * upper)
    spine4 = 1.0 - shoulder_weight - spine5
    groups["DEF-spine.004"].add([vertex.index], spine4, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], spine5, "REPLACE")
    shoulder_name = "DEF-shoulder.L" if x >= 0.0 else "DEF-shoulder.R"
    groups[shoulder_name].add([vertex.index], shoulder_weight, "REPLACE")
modifier = vest.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
vest.parent = rig
vest.matrix_parent_inverse = rig.matrix_world.inverted()
vest["game_asset"] = True
vest["part_category"] = "ClothedBody"
vest["source"] = "V16ZK clean upper-vest torso bridge"

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


def render(key, location, target, lens=84, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zk_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top_close": render("clean_coherent_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("clean_coherent_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "upper_three_quarter": render("clean_coherent_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
    "front": render("clean_coherent_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("clean_coherent_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

upper_checks = {}
for upper_obj in (cowl, vest):
    bad_edges, components = topology(upper_obj)
    weight_sums = [sum(group.weight for group in vertex.groups) for vertex in upper_obj.data.vertices]
    upper_checks[upper_obj.name] = {
        "triangles": triangles(upper_obj),
        "nonmanifold_edges": bad_edges,
        "components": components,
        "weight_sum_range": [min(weight_sums), max(weight_sums)],
    }
    if bad_edges or components != 1 or min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
        raise RuntimeError(f"Upper validation failed: {upper_obj.name}: {upper_checks[upper_obj.name]}")
character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "upper_checks": upper_checks,
    "removed_hidden_scan_faces": removed,
    "mesh_count": len(character_meshes),
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZK_REPORT=" + json.dumps(report, sort_keys=True))
