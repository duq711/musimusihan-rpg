"""Resculpt v16zt as a soft irregular cowl with only two local diagonal folds."""

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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zt_compact_layered_scarf.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zx_soft_irregular_cowl.blend"
REPORT = STAGING / "v16zx_soft_irregular_cowl_report.json"
SOURCE_COWL = "Mercenary_CompactLayeredScarf_v16zt_LOD0"
NEW_COWL = "Mercenary_SoftIrregularWoolCowl_v16zx_LOD0"
ANGULAR_SEGMENTS = 192
VERTICAL_SEGMENTS = 48
ROWS = VERTICAL_SEGMENTS + 1
SURFACE_SIZE = ANGULAR_SEGMENTS * ROWS


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def gaussian(value, center, width):
    return math.exp(-((value - center) / width) ** 2)


def angle_delta(angle, center):
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle, center, width):
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def soft_cowl_point(theta, u, inner):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # A close, visibly irregular neckline opens into a compact clavicle cowl.
    top_rx = 0.135 + 0.007 * math.sin(theta + 0.50) + 0.003 * math.sin(3.0 * theta - 0.25)
    top_ry = 0.104 + 0.006 * math.sin(theta - 0.18) + 0.003 * math.sin(2.0 * theta + 0.40)
    hem_rx = 0.198 + 0.010 * back + 0.006 * left - 0.004 * front
    hem_ry = 0.145 + 0.018 * back - 0.005 * front + 0.004 * right
    rx = top_rx * (1.0 - eased) + hem_rx * eased
    ry = top_ry * (1.0 - eased) + hem_ry * eased

    # Broad cloth fullness without any circumference-wide ridge.
    fullness = gaussian(u, 0.59, 0.31) * (
        0.014
        + 0.006 * math.sin(theta + 0.70)
        + 0.003 * math.sin(3.0 * theta - 0.35)
    )
    hem_tuck = smoothstep((u - 0.82) / 0.18)
    rx += fullness - hem_tuck * (0.009 + 0.003 * front)
    ry += 0.82 * fullness - hem_tuck * (0.007 + 0.003 * side)

    # Only two partial diagonal folds.  Each fades completely outside its arc,
    # so the garment cannot form stacked rings or a rubber-tube silhouette.
    path_a = 0.34 + 0.145 * math.sin(theta + 0.52) + 0.025 * math.sin(2.0 * theta - 0.30)
    path_b = 0.69 + 0.125 * math.sin(theta - 1.18) - 0.022 * math.sin(3.0 * theta + 0.25)
    envelope_a = min(1.0, 0.92 * localized(theta, -1.20, 1.02) + 0.25 * localized(theta, 2.65, 0.55))
    envelope_b = min(1.0, 0.86 * localized(theta, -2.05, 0.95) + 0.42 * localized(theta, 0.72, 0.72))
    fold_a = gaussian(u, path_a, 0.070) - 0.34 * gaussian(u, path_a + 0.066, 0.048)
    fold_b = gaussian(u, path_b, 0.078) - 0.32 * gaussian(u, path_b + 0.074, 0.054)
    relief = 0.022 * envelope_a * fold_a + 0.020 * envelope_b * fold_b

    # Two-dimensional low-frequency crumple breaks the remaining CAD symmetry.
    relief += middle ** 1.45 * (
        0.0040 * math.sin(2.0 * theta + 4.2 * u + 0.3)
        + 0.0023 * math.sin(5.0 * theta - 3.4 * u)
        + 0.0014 * math.sin(9.0 * theta + 2.1 * u)
    )

    thickness = 0.0070 + 0.0007 * math.sin(2.0 * theta + 1.25 * u) + 0.0004 * middle
    surface_rx = rx + relief
    surface_ry = ry + 0.86 * relief
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.91

    tangential = middle ** 1.4 * (
        0.0060 * math.sin(theta + 2.15 * u - 0.25)
        + 0.0025 * math.sin(3.0 * theta - 1.35 * u)
    )
    center_x = -0.004 - 0.007 * eased + 0.003 * middle * math.sin(theta + 0.6)
    center_y = 0.010 + 0.011 * eased
    x = center_x + surface_rx * c - tangential * s
    y = center_y + surface_ry * s + tangential * c

    # The front edge sags below the jaw while the rear rises softly.  Neither
    # lip is a perfect oval, and the lower edge has a broad off-centre drape.
    top_z = (
        1.580
        + 0.034 * back
        - 0.020 * front
        + 0.005 * side
        + 0.007 * math.sin(theta + 0.42)
        + 0.003 * math.sin(3.0 * theta - 0.15)
    )
    hem_z = (
        1.398
        - 0.018 * front
        - 0.010 * back
        - 0.022 * localized(theta, -2.10, 0.88)
        - 0.008 * localized(theta, -0.72, 0.70)
        + 0.006 * localized(theta, 1.35, 0.80)
        + 0.005 * math.sin(2.0 * theta + 0.28)
    )
    z = top_z * (1.0 - eased) + hem_z * eased
    z += middle ** 1.35 * (
        0.011 * math.sin(theta + 0.40)
        + 0.005 * math.sin(2.0 * theta - 3.2 * u)
    )
    z += 0.0035 * envelope_a * fold_a - 0.0028 * envelope_b * fold_b
    if inner:
        z -= 0.0007 * middle
    return x, y, z


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
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
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects[SOURCE_COWL]
if len(cowl.data.vertices) != 2 * SURFACE_SIZE:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)}")

cowl.name = NEW_COWL
cowl.data.name = "Mercenary_SoftIrregularWoolCowl_v16zx_Mesh"
for surface in (0, 1):
    for row in range(ROWS):
        u = row / VERTICAL_SEGMENTS
        for angular in range(ANGULAR_SEGMENTS):
            theta = math.tau * angular / ANGULAR_SEGMENTS
            index = surface * SURFACE_SIZE + row * ANGULAR_SEGMENTS + angular
            cowl.data.vertices[index].co = soft_cowl_point(theta, u, bool(surface))
cowl.data.update()

bm = bmesh.new()
bm.from_mesh(cowl.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()
cowl["source"] = "V16ZX one-piece soft cowl with two local diagonal folds"
cowl["integrated_fold_count"] = 2
cowl["separate_cowl_rings"] = 0
if cowl.data.materials:
    cowl.data.materials[0].name = "MAT_v16zx_SoftCharcoalWool_4K"

# Remove only fragments that rise behind the new cowl or protrude through the
# clean shoulder sleeves.  The central front/back garment below the cowl stays.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    rear_high = center.y > 0.055 and center.z > 1.345 and ax < 0.52
    sleeve_hidden = 0.215 < ax < 0.485 and center.z > 1.305
    if rear_high or sleeve_hidden:
        remove_faces.append(face)
removed_donor_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zx_removed_upper_fragments"] = removed_donor_faces

cowl_topology = topology(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
if cowl_topology["components"] != 1 or cowl_topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZX topology failed: {cowl_topology}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"V16ZX weights failed: {min(weight_sums)}..{max(weight_sums)}")

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
    ("V16ZX_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZX_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZX_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zx_soft_irregular_{key}.png"
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
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"V16ZX triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "construction": "single soft irregular shell with two partial diagonal folds",
    "removed_donor_faces": removed_donor_faces,
    "cowl_triangles": triangles(cowl),
    "topology": cowl_topology,
    "weight_sum_range": [min(weight_sums), max(weight_sums)],
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16zx_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZX_REPORT=" + json.dumps(report, sort_keys=True))
