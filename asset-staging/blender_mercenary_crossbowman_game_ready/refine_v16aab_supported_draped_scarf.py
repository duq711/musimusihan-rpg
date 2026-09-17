"""Build a supported asymmetric scarf while preserving the intact torso."""

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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zz_tucked_upper_no_deletion.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16aab_supported_draped_scarf.blend"
REPORT = STAGING / "v16aab_supported_draped_scarf_report.json"
OLD_COWL = "Mercenary_SoftIrregularWoolCowl_v16zx_LOD0"
NEW_COWL = "Mercenary_SupportedDrapedWoolScarf_v16aab_LOD0"
SLEEVES_NAME = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
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
    return (angle - center + math.pi) % math.tau - math.pi


def localized(angle, center, width):
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def scarf_point(theta, u, inner):
    """Closed double surface shaped like softly bunched cloth, not a cylinder."""
    c, s = math.cos(theta), math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # A close irregular neckline transitions into a slightly wider tucked hem.
    top_rx = 0.126 + 0.004 * math.sin(theta + 0.5) + 0.002 * math.sin(4.0 * theta)
    top_ry = 0.098 + 0.005 * back + 0.003 * math.sin(2.0 * theta - 0.3)
    hem_rx = 0.192 + 0.010 * side + 0.004 * left
    hem_ry = 0.145 + 0.050 * back - 0.003 * front
    rx = top_rx * (1.0 - eased) + hem_rx * eased
    ry = top_ry * (1.0 - eased) + hem_ry * eased

    # Barrel fullness is strongest halfway down, while the lower edge tucks in.
    fullness = middle ** 1.25 * (
        0.018
        + 0.0045 * math.sin(theta + 0.6)
        + 0.0025 * math.sin(3.0 * theta - 0.2)
    )
    hem_tuck = smoothstep((u - 0.78) / 0.22)
    rx += fullness - 0.014 * hem_tuck
    ry += 0.86 * fullness - 0.011 * hem_tuck

    # Two broad diagonal folds only on portions of the circumference.  Their
    # peaks and shallow shadow valleys make bunched fabric without full rings.
    path_a = 0.30 + 0.105 * math.sin(theta + 0.85)
    path_b = 0.63 + 0.090 * math.sin(theta - 0.55)
    env_a = min(1.0, 0.92 * localized(theta, -1.45, 1.28) + 0.28 * localized(theta, 2.55, 0.72))
    env_b = min(1.0, 0.82 * localized(theta, -0.35, 1.12) + 0.46 * localized(theta, -2.35, 0.88))
    fold_a = gaussian(u, path_a, 0.070) - 0.48 * gaussian(u, path_a + 0.067, 0.052)
    fold_b = gaussian(u, path_b, 0.078) - 0.42 * gaussian(u, path_b + 0.073, 0.057)
    relief = 0.024 * env_a * fold_a + 0.021 * env_b * fold_b
    relief += middle ** 1.5 * (
        0.0038 * math.sin(2.0 * theta + 3.7 * u)
        + 0.0020 * math.sin(5.0 * theta - 2.8 * u)
    )

    thickness = 0.0065 + 0.0006 * math.sin(2.0 * theta + 1.1 * u)
    surface_rx = rx + relief
    surface_ry = ry + relief * 0.84
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.90

    # Small shear keeps the folds from reading as concentric CAD rings.
    tangent = middle ** 1.35 * (
        0.0050 * math.sin(theta + 2.4 * u - 0.3)
        + 0.0022 * math.sin(3.0 * theta - 1.4 * u)
    )
    center_x = -0.003 - 0.004 * eased
    center_y = 0.008 + 0.010 * eased
    x = center_x + surface_rx * c - tangent * s
    y = center_y + surface_ry * s + tangent * c

    # The rear is raised and the front/left hem sags, as a real wrapped scarf
    # does under gravity.  This also removes the straight horizontal top lip.
    top_z = (
        1.574 + 0.026 * back - 0.030 * front + 0.004 * side
        + 0.006 * math.sin(theta + 0.35) + 0.003 * math.sin(3.0 * theta)
    )
    hem_z = (
        1.402 + 0.010 * back - 0.018 * front - 0.007 * left
        + 0.005 * math.sin(2.0 * theta + 0.2)
    )
    z = top_z * (1.0 - eased) + hem_z * eased
    z += middle ** 1.30 * (
        0.010 * math.sin(theta + 0.55)
        + 0.0045 * math.sin(2.0 * theta - 2.6 * u)
    )
    z += 0.0040 * env_a * fold_a - 0.0030 * env_b * fold_b
    if inner:
        z -= 0.0008 * middle
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
cowl = bpy.data.objects[OLD_COWL]
sleeves = bpy.data.objects[SLEEVES_NAME]
if len(cowl.data.vertices) != 2 * SURFACE_SIZE:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)}")

cowl.name = NEW_COWL
cowl.data.name = "Mercenary_SupportedDrapedWoolScarf_v16aab_Mesh"
for surface in (0, 1):
    for row in range(ROWS):
        u = row / VERTICAL_SEGMENTS
        for angular in range(ANGULAR_SEGMENTS):
            theta = math.tau * angular / ANGULAR_SEGMENTS
            index = surface * SURFACE_SIZE + row * ANGULAR_SEGMENTS + angular
            cowl.data.vertices[index].co = scarf_point(theta, u, bool(surface))
cowl.data.update()
bm = bmesh.new()
bm.from_mesh(cowl.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()
cowl["source"] = "V16AAB supported asymmetric one-piece draped wool scarf"
cowl["integrated_fold_count"] = 2
cowl["separate_cowl_rings"] = 0
if cowl.data.materials:
    cowl.data.materials[0].name = "MAT_v16aab_SupportedCharcoalWool_4K"

# Preserve the v16zz torso exactly.  Its front and rear garment panels are
# intact; the scarf's lower overlap hides their already-covered scan boundary.
depths = {}
donor["v16aab_additional_tucked_boundary_vertices"] = 0

checks = {}
for obj in (cowl, sleeves):
    stats = topology(obj)
    weights = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    expected_components = 2 if obj is sleeves else 1
    if stats["components"] != expected_components or stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Topology failed: {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weights failed: {obj.name}: {min(weights)}..{max(weights)}")
    checks[obj.name] = {
        "triangles": triangles(obj), "topology": stats,
        "weight_sum_range": [min(weights), max(weights)],
        "rigify": any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers),
    }

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
    ("V16AAB_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AAB_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AAB_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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
    path = PREVIEWS / f"diagnostic_v16aab_supported_draped_{key}.png"
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
    obj for obj in scene.objects if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE), "candidate": str(OUTPUT), "production_modified": False,
    "cowl": cowl.name, "sleeves": sleeves.name,
    "additional_tucked_boundary_vertices": 0, "checks": checks,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes), "total_triangles": total_triangles,
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AAB_REPORT=" + json.dumps(report, sort_keys=True))
