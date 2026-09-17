"""Settle the clean padded sleeves under the scarf to form continuous shoulders."""

from collections import defaultdict, deque
import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aab_supported_draped_scarf.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16aac_integrated_shoulder_caps.blend"
REPORT = STAGING / "v16aac_integrated_shoulder_caps_report.json"
COWL_NAME = "Mercenary_SupportedDrapedWoolScarf_v16aab_LOD0"
SLEEVES_NAME = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"


def clamp(value):
    return max(0.0, min(1.0, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


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
cowl = bpy.data.objects[COWL_NAME]
sleeves = bpy.data.objects[SLEEVES_NAME]

# Build a padded shoulder slope at each inner sleeve root.  The upper quarter
# rises toward the neck, while the underside settles over the original coat
# boundary.  This removes the floating-cylinder/black-notch transition.
moved_vertices = 0
for vertex in sleeves.data.vertices:
    co = vertex.co
    ax = abs(co.x)
    inner = 1.0 - smoothstep((ax - 0.095) / 0.245)
    if inner <= 0.001:
        continue
    top = smoothstep((co.z - 1.425) / 0.090)
    bottom = 1.0 - smoothstep((co.z - 1.338) / 0.092)
    co.z += inner * (0.014 * top - 0.040 * bottom)
    center_y = 0.031
    co.y = center_y + (co.y - center_y) * (1.0 + 0.23 * inner)
    # Bring only the deepest inner root slightly toward the torso.
    co.x *= 1.0 - 0.025 * inner
    moved_vertices += 1
sleeves.data.update()
sleeves["v16aac_integrated_shoulder_vertices"] = moved_vertices
sleeves["source"] = "V16AAC closed quilted sleeves with integrated padded shoulder caps"

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
    ("V16AAC_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AAC_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AAC_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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
    path = PREVIEWS / f"diagnostic_v16aac_integrated_shoulders_{key}.png"
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
    "moved_shoulder_vertices": moved_vertices, "checks": checks,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes), "total_triangles": total_triangles,
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AAC_REPORT=" + json.dumps(report, sort_keys=True))
