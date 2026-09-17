"""Hybrid final candidate: v16aac shoulder integrity with a compact draped scarf.

No donor or sleeve faces are deleted or added.  The existing single closed
v16aac scarf mesh is resculpted in place: close neckline, lower front lip,
vertical side drape, and a longer rear hood-like fall that hides scan damage.
"""

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aac_integrated_shoulder_caps.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16finalb_hybrid_compact_supported_scarf_candidate.blend"
REPORT = STAGING / "v16finalb_hybrid_compact_supported_scarf_report.json"
COWL_NAME = "Mercenary_SupportedDrapedWoolScarf_v16aab_LOD0"
SLEEVES_NAME = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
ANGULAR = 192
ROWS = 49
SURFACE_SIZE = ANGULAR * ROWS


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def gaussian(value, center, width):
    return math.exp(-((value - center) / width) ** 2)


def angle_delta(angle, center):
    return (angle - center + math.pi) % math.tau - math.pi


def localized(angle, center, width):
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
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
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "loose_vertices": sum(not adjacency[index] for index in range(len(obj.data.vertices))),
        "zero_area_faces": sum(poly.area <= 1.0e-12 for poly in obj.data.polygons),
    }


def bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "x": [min(point.x for point in points), max(point.x for point in points)],
        "y": [min(point.y for point in points), max(point.y for point in points)],
        "z": [min(point.z for point in points), max(point.z for point in points)],
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def scarf_point(theta, u, inner):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # The opening sits close to the neck; the outer surface widens mainly at
    # the sides and rear, where gravity makes the scarf/hood fall downward.
    outer_top_rx = 0.119 + 0.0035 * math.sin(theta + 0.45) + 0.0018 * math.sin(3.0 * theta)
    outer_top_ry = 0.089 + 0.0030 * math.sin(theta - 0.25) + 0.0015 * math.sin(2.0 * theta)
    outer_hem_rx = 0.187 + 0.013 * side + 0.004 * back + 0.003 * left
    outer_hem_ry = 0.142 + 0.010 * front + 0.067 * back + 0.003 * right

    path_a = 0.31 + 0.105 * math.sin(theta + 0.70)
    path_b = 0.67 + 0.090 * math.sin(theta - 0.80)
    env_a = min(1.0, 0.88 * localized(theta, -1.30, 0.95) + 0.26 * localized(theta, 2.50, 0.62))
    env_b = min(1.0, 0.82 * localized(theta, -0.20, 0.90) + 0.40 * localized(theta, -2.30, 0.75))
    fold_a = gaussian(u, path_a, 0.078) - 0.32 * gaussian(u, path_a + 0.072, 0.052)
    fold_b = gaussian(u, path_b, 0.086) - 0.30 * gaussian(u, path_b + 0.078, 0.056)
    relief = 0.0115 * env_a * fold_a + 0.0100 * env_b * fold_b
    relief += middle ** 1.5 * (
        0.0018 * math.sin(4.0 * theta + 3.7 * u)
        + 0.0010 * math.sin(8.0 * theta - 2.4 * u)
    )
    fullness = gaussian(u, 0.56, 0.31) * (
        0.0085 + 0.0022 * math.sin(theta + 0.5) + 0.0012 * math.sin(3.0 * theta)
    )

    if inner:
        top_rx = outer_top_rx - 0.0070
        top_ry = outer_top_ry - 0.0062
        hem_rx = 0.116 + 0.006 * side + 0.003 * back
        hem_ry = 0.091 + 0.007 * front + 0.010 * back
        rx = top_rx * (1.0 - eased) + hem_rx * eased + 0.20 * fullness + 0.22 * relief
        ry = top_ry * (1.0 - eased) + hem_ry * eased + 0.17 * fullness + 0.18 * relief
    else:
        hem_tuck = smoothstep((u - 0.85) / 0.15)
        rx = outer_top_rx * (1.0 - eased) + outer_hem_rx * eased
        ry = outer_top_ry * (1.0 - eased) + outer_hem_ry * eased
        rx += fullness + relief - 0.0045 * hem_tuck
        ry += 0.84 * (fullness + relief) - 0.0040 * hem_tuck

    # Low front, downward side fall, and a longer rear hood drape.  This makes
    # the surface steep rather than a horizontal plate when viewed from above.
    top_z = (
        1.528 + 0.034 * back - 0.017 * front + 0.003 * side
        + 0.0035 * math.sin(theta + 0.35) + 0.0018 * math.sin(3.0 * theta)
    )
    hem_z = (
        1.393 - 0.012 * front - 0.012 * side - 0.031 * back
        - 0.004 * left + 0.003 * math.sin(2.0 * theta + 0.25)
    )
    z = top_z * (1.0 - eased) + hem_z * eased
    z += middle ** 1.4 * (
        0.0045 * math.sin(theta + 0.45)
        + 0.0022 * math.sin(3.0 * theta - 2.7 * u)
    )
    z += 0.0027 * env_a * fold_a - 0.0020 * env_b * fold_b
    if inner:
        z -= 0.0008 * middle

    tangent = middle ** 1.5 * (
        0.0035 * math.sin(theta + 1.9 * u) + 0.0014 * math.sin(3.0 * theta - u)
    )
    if inner:
        tangent *= 0.35
    center_x = -0.003 - 0.004 * eased
    center_y = 0.012 + 0.007 * eased
    x = center_x + rx * c - tangent * s
    y = center_y + ry * s + tangent * c
    return (x, y, z)


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects[COWL_NAME]
sleeves = bpy.data.objects[SLEEVES_NAME]
if len(cowl.data.vertices) != 2 * SURFACE_SIZE:
    raise RuntimeError(f"Unexpected cowl layout: {len(cowl.data.vertices)} vertices")

donor_before = (len(donor.data.vertices), len(donor.data.polygons), triangles(donor))
sleeves_before = (len(sleeves.data.vertices), len(sleeves.data.polygons), triangles(sleeves))

for surface in (0, 1):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANGULAR):
            theta = math.tau * angular / ANGULAR
            index = surface * SURFACE_SIZE + row * ANGULAR + angular
            cowl.data.vertices[index].co = scarf_point(theta, u, bool(surface))
cowl.data.update()
bm = bmesh.new()
bm.from_mesh(cowl.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()
cowl.name = "Mercenary_HybridCompactSupportedScarf_v16finalb_LOD0"
cowl.data.name = "Mercenary_HybridCompactSupportedScarf_v16finalb_Mesh"
cowl["source"] = "V16FINALB compact low scarf on V16AAC integrated shoulders"
cowl["separate_rings"] = 0
cowl["floating_panels"] = 0

cowl_stats = topology(cowl)
sleeve_stats = topology(sleeves)
cowl_weights = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
sleeve_weights = [sum(item.weight for item in vertex.groups) for vertex in sleeves.data.vertices]
for obj, stats, components, weights in (
    (cowl, cowl_stats, 1, cowl_weights),
    (sleeves, sleeve_stats, 2, sleeve_weights),
):
    if stats["components"] != components or stats["nonmanifold_edges"]:
        raise RuntimeError(f"Topology failed on {obj.name}: {stats}")
    if stats["zero_area_faces"] or stats["loose_vertices"]:
        raise RuntimeError(f"Degenerate geometry on {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weights failed on {obj.name}: {min(weights)}..{max(weights)}")
    if not any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers):
        raise RuntimeError(f"Missing Rigify modifier on {obj.name}")

if donor_before != (len(donor.data.vertices), len(donor.data.polygons), triangles(donor)):
    raise RuntimeError("Donor topology changed")
if sleeves_before != (len(sleeves.data.vertices), len(sleeves.data.polygons), triangles(sleeves)):
    raise RuntimeError("Sleeve topology changed")

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
        background.inputs[1].default_value = 0.14

lights = []
for name, location, energy, size, color in (
    ("V16FINALB_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16FINALB_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16FINALB_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16finalb_hybrid_scarf_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
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
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Rigify deform bones changed: {deform_bones}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "donor_faces_deleted": 0,
    "donor_topology_unchanged": True,
    "sleeve_faces_deleted": 0,
    "sleeve_topology_unchanged": True,
    "construction": "single closed compact scarf, two partial folds, rear vertical drape, v16aac integrated shoulders",
    "cowl": cowl.name,
    "cowl_bounds": bounds(cowl),
    "cowl_triangles": triangles(cowl),
    "cowl_topology": cowl_stats,
    "cowl_weight_sum_range": [min(cowl_weights), max(cowl_weights)],
    "cowl_rigify": True,
    "sleeves": sleeves.name,
    "sleeve_bounds": bounds(sleeves),
    "sleeve_triangles": triangles(sleeves),
    "sleeve_topology": sleeve_stats,
    "sleeve_weight_sum_range": [min(sleeve_weights), max(sleeve_weights)],
    "sleeve_rigify": True,
    "deform_bones": deform_bones,
    "character_meshes": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16finalb_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16FINALB_REPORT=" + json.dumps(report, sort_keys=True))
