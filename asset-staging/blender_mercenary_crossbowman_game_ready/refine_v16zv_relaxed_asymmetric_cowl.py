"""Relax v16zu into a lower, asymmetric one-piece wrapped cowl."""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zu_compact_bunched_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zv_relaxed_asymmetric_cowl.blend"
REPORT = STAGING / "v16zv_relaxed_asymmetric_cowl_report.json"
SOURCE_COWL = "Mercenary_CompactBunchedWoolCowl_v16zu_LOD0"
NEW_COWL = "Mercenary_RelaxedAsymmetricWoolCowl_v16zv_LOD0"
ANGLE_SEGMENTS = 160
VERTICAL_SEGMENTS = 56
ROWS = VERTICAL_SEGMENTS + 1


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def gaussian(value: float, center: float, width: float) -> float:
    return math.exp(-((value - center) / width) ** 2)


def angle_delta(angle: float, center: float) -> float:
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle: float, center: float, width: float) -> float:
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def fold_profile(u: float, center: float, width: float) -> float:
    return gaussian(u, center, width) - 0.42 * gaussian(u, center + width * 1.15, width * 0.66)


def point(theta: float, u: float, inner: bool) -> tuple[float, float, float]:
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # Close neckline and modest clavicle opening.  The rear carries slightly
    # more wool; the front remains compact and below the jaw.
    top_rx = 0.142 + 0.006 * math.sin(theta + 0.55) + 0.002 * math.sin(3.0 * theta)
    top_ry = 0.110 + 0.005 * math.sin(theta - 0.15) + 0.002 * math.sin(2.0 * theta)
    bottom_rx = 0.205 + 0.012 * back + 0.006 * left - 0.005 * front
    bottom_ry = 0.148 + 0.019 * back - 0.006 * front + 0.003 * right
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    fullness = gaussian(u, 0.62, 0.30) * (
        0.013 + 0.004 * math.sin(theta + 0.75) + 0.002 * math.sin(3.0 * theta - 0.5)
    )
    hem_tuck = smoothstep((u - 0.82) / 0.18)
    rx += fullness - hem_tuck * (0.010 + 0.004 * front)
    ry += 0.84 * fullness - hem_tuck * (0.008 + 0.003 * side)

    # Each fold is strong on a different arc and nearly disappears elsewhere.
    # This produces cloth bunches instead of complete horizontal bands.
    path_upper = 0.27 + 0.075 * math.sin(theta + 0.25) + 0.018 * math.sin(2.0 * theta - 0.4)
    path_middle = 0.53 + 0.095 * math.sin(theta - 1.10) - 0.022 * math.sin(3.0 * theta)
    path_lower = 0.77 + 0.065 * math.sin(theta + 1.55) + 0.018 * math.sin(2.0 * theta + 0.35)
    env_upper = min(1.0, 0.07 + 0.86 * localized(theta, -0.55, 1.05) + 0.18 * localized(theta, 2.45, 0.60))
    env_middle = min(1.0, 0.06 + 0.88 * localized(theta, -2.05, 1.00) + 0.16 * localized(theta, 0.95, 0.65))
    env_lower = min(1.0, 0.06 + 0.74 * localized(theta, 1.45, 1.05) + 0.35 * localized(theta, -0.65, 0.72))
    upper = fold_profile(u, path_upper, 0.063) * env_upper
    middle_fold = fold_profile(u, path_middle, 0.071) * env_middle
    lower = fold_profile(u, path_lower, 0.073) * env_lower
    relief = 0.021 * upper + 0.025 * middle_fold + 0.020 * lower
    relief += 0.008 * localized(theta, -2.30, 0.40) * gaussian(u, 0.62, 0.19)
    relief += middle ** 1.4 * (
        0.0022 * math.sin(4.0 * theta + 2.7 * u)
        + 0.0012 * math.sin(8.0 * theta - 2.0 * u)
    )

    thickness = 0.0070 + 0.0007 * math.sin(2.0 * theta + 1.2 * u) + 0.0004 * middle
    surface_rx = rx + relief
    surface_ry = ry + 0.86 * relief
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.90

    tangential = middle ** 1.5 * (
        0.0040 * math.sin(theta + 2.2 * u - 0.35)
        + 0.0018 * math.sin(3.0 * theta - 1.4 * u)
    )
    center_x = -0.004 - 0.003 * eased + 0.002 * middle * math.sin(2.0 * theta)
    center_y = 0.010 + 0.009 * eased
    x = center_x + surface_rx * c - tangential * s
    y = center_y + surface_ry * s + tangential * c

    # Open, sloped upper edge: low beneath the chin and high behind the neck.
    top_z = (
        1.585
        + 0.032 * back
        - 0.022 * front
        + 0.006 * side
        + 0.005 * math.sin(theta + 0.35)
    )
    # A shallow diagonal fall at the front-left replaces the rigid straight hem.
    bottom_z = (
        1.393
        - 0.016 * front
        - 0.008 * back
        - 0.010 * localized(theta, -2.18, 0.70)
        + 0.006 * localized(theta, -0.55, 0.65)
        + 0.004 * math.sin(2.0 * theta + 0.2)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += middle ** 1.35 * (0.004 * math.sin(theta - 0.55) + 0.002 * math.sin(3.0 * theta + 2.0 * u))
    z += 0.0025 * upper - 0.0016 * middle_fold + 0.0018 * lower
    if inner:
        z -= 0.0007 * middle
    return x, y, z


def triangles(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj: bpy.types.Object) -> dict[str, int]:
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


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects[SOURCE_COWL]
cowl.name = NEW_COWL
cowl.data.name = "Mercenary_RelaxedAsymmetricWoolCowl_v16zv_Mesh"

surface_size = ROWS * ANGLE_SEGMENTS
if len(cowl.data.vertices) != 2 * surface_size:
    raise RuntimeError(f"Unexpected v16zu cowl vertex count: {len(cowl.data.vertices)}")
for surface in (0, 1):
    for vertical_index in range(ROWS):
        u = vertical_index / VERTICAL_SEGMENTS
        for angular_index in range(ANGLE_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGLE_SEGMENTS
            vertex_index = surface * surface_size + vertical_index * ANGLE_SEGMENTS + angular_index
            cowl.data.vertices[vertex_index].co = point(theta, u, bool(surface))
cowl.data.update()
cowl["source"] = "V16ZV relaxed one-piece asymmetric medieval wool cowl"
cowl["separate_cowl_rings"] = 0

if cowl.data.materials:
    cowl.data.materials[0].name = "MAT_v16zv_RelaxedCharcoalWool_4K"

cowl_topology = topology(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
if cowl_topology["components"] != 1 or cowl_topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZV topology failed: {cowl_topology}")
if min(weight_sums) < 0.999999 or max(weight_sums) > 1.000001:
    raise RuntimeError(f"V16ZV weights failed: {min(weight_sums)}..{max(weight_sums)}")

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

qa_lights = []
for name, location, energy, size, color in (
    ("V16ZV_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZV_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZV_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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
    qa_lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zv_relaxed_asymmetric_{key}.png"
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

for light in qa_lights:
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
    raise RuntimeError(f"V16ZV triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "construction": "lower asymmetric one-piece cowl with three localized continuous folds",
    "cowl_triangles": triangles(cowl),
    "topology": cowl_topology,
    "weight_sum_range": [min(weight_sums), max(weight_sums)],
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "cowl_bounds": {
        "min": [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    "previews": previews,
}
cowl["v16zv_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZV_REPORT=" + json.dumps(report, sort_keys=True))
