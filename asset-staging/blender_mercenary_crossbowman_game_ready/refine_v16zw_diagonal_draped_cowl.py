"""Give v16zv a softer diagonal wrap and a compact asymmetric lower drape."""

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zv_relaxed_asymmetric_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zw_diagonal_draped_cowl.blend"
REPORT = STAGING / "v16zw_diagonal_draped_cowl_report.json"
SOURCE_COWL = "Mercenary_RelaxedAsymmetricWoolCowl_v16zv_LOD0"
NEW_COWL = "Mercenary_DiagonalDrapedWoolCowl_v16zw_LOD0"
ANGLE_SEGMENTS = 160
VERTICAL_SEGMENTS = 56
ROWS = VERTICAL_SEGMENTS + 1


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angle_delta(angle, center):
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle, center, width):
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


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
cowl = bpy.data.objects[SOURCE_COWL]
cowl.name = NEW_COWL
cowl.data.name = "Mercenary_DiagonalDrapedWoolCowl_v16zw_Mesh"

surface_size = ROWS * ANGLE_SEGMENTS
if len(cowl.data.vertices) != 2 * surface_size:
    raise RuntimeError(f"Unexpected cowl vertex count: {len(cowl.data.vertices)}")

for surface in (0, 1):
    for vertical_index in range(ROWS):
        u = vertical_index / VERTICAL_SEGMENTS
        middle = math.sin(math.pi * u)
        lower = smoothstep((u - 0.48) / 0.52)
        for angular_index in range(ANGLE_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGLE_SEGMENTS
            index = surface * surface_size + vertical_index * ANGLE_SEGMENTS + angular_index
            co = cowl.data.vertices[index].co

            # Column-wise height drift tilts all built-in relief into a wrapped
            # diagonal rather than three horizontal accordion rings.
            wrap_warp = middle ** 1.25 * (
                0.016 * math.sin(theta + 0.48)
                + 0.007 * math.sin(2.0 * theta - 0.55)
            )
            co.z += wrap_warp

            # A broad front-left fall and a smaller opposite fall make a soft
            # scarf end without producing a pointed shield or wide capelet.
            front_left = localized(theta, -2.12, 0.82)
            front_right = localized(theta, -0.78, 0.66)
            rear_lift = localized(theta, 1.52, 0.86)
            co.z -= lower * (0.020 * front_left + 0.008 * front_right - 0.004 * rear_lift)

            # Let the same draping arcs settle a few millimetres forward.  Both
            # inner and outer skins move together, preserving cloth thickness.
            co.y -= lower * (0.006 * front_left + 0.003 * front_right)
            co.x -= lower * (0.003 * front_left - 0.0015 * front_right)

cowl.data.update()

# Very light relaxation removes synthetic sharpness while preserving folds.
bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
modifier = cowl.modifiers.new("V16ZW_ClothRelax", "SMOOTH")
modifier.factor = 0.055
modifier.iterations = 1
bpy.ops.object.modifier_apply(modifier=modifier.name)
cowl["source"] = "V16ZW compact single-shell cowl with diagonal continuous folds"
cowl["separate_cowl_rings"] = 0
if cowl.data.materials:
    cowl.data.materials[0].name = "MAT_v16zw_DiagonalCharcoalWool_4K"

cowl_topology = topology(cowl)
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
if cowl_topology["components"] != 1 or cowl_topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZW topology failed: {cowl_topology}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"V16ZW weights failed: {min(weight_sums)}..{max(weight_sums)}")

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
    ("V16ZW_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZW_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZW_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zw_diagonal_draped_{key}.png"
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
    raise RuntimeError(f"V16ZW triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "construction": "compact single closed shell with diagonal folds and broad asymmetric drape",
    "cowl_triangles": triangles(cowl),
    "topology": cowl_topology,
    "weight_sum_range": [min(weight_sums), max(weight_sums)],
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16zw_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZW_REPORT=" + json.dumps(report, sort_keys=True))
