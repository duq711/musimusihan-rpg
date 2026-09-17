"""Clean the rear shoulder halo on the selected sculpted cowl candidate."""

from collections import defaultdict
import json
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zl_sculpted_lower_drape.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
REPORT = STAGING / "v16zm_clean_rear_shoulders_report.json"


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


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
    return sum(count != 2 for count in counts.values()), components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"]

# Extend only the lower rear drape across the shoulder roots.  This replaces
# the jagged scan halo with the same continuous cloth shell; the neck opening
# and front silhouette are untouched.
rear_drape_vertices = 0
for vertex in cowl.data.vertices:
    co = vertex.co
    back = smoothstep((co.y - 0.055) / 0.125)
    lower = smoothstep((1.505 - co.z) / 0.185)
    influence = back * lower
    if influence <= 0.001:
        continue
    co.x *= 1.0 + 0.28 * influence
    co.y += 0.010 * influence
    co.z -= 0.010 * influence
    rear_drape_vertices += 1
cowl.data.update()
cowl["v16zm_rear_shoulder_drape_vertices"] = rear_drape_vertices
cowl["source"] = "V16ZM single cowl with sculpted lower front and clean rear shoulder drape"

# Delete the torn rear scan faces now hidden under that expanded cowl.  This
# targets only the back-facing collar halo, preserving the front chest and all
# of the original garment below it.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    if abs(center.x) < 0.44 and center.y > 0.125 and center.z > 1.285:
        remove_faces.append(face)
removed_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vert for vert in bm.verts if not vert.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zm_removed_rear_scan_faces"] = removed_faces

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
    path = PREVIEWS / f"diagnostic_v16zm_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top_close": render("clean_rear_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("clean_rear_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "upper_three_quarter": render("clean_rear_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
    "front": render("clean_rear_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("clean_rear_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

bad_edges, components = topology(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
if bad_edges or components != 1 or min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError("V16ZM cowl topology or weights failed")
character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "rear_drape_vertices": rear_drape_vertices,
    "removed_rear_scan_faces": removed_faces,
    "mesh_count": len(character_meshes),
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZM_REPORT=" + json.dumps(report, sort_keys=True))
