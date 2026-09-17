"""Test the donor's native cowl with only a hidden seam closure."""

from collections import defaultdict
import json
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16l_soft_loop_cowl_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16m_donor_cowl_candidate.blend"
REPORT = STAGING / "v16m_donor_cowl_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects.get("Mercenary_SoftLoopCowl_LOD0")
if cowl is None:
    raise RuntimeError("Soft-loop comparison object is missing")
bpy.data.objects.remove(cowl, do_unlink=True)

# Use the dark cowl textile on the compact closure so any millimetric exposed
# area blends into the donor's already modelled scarf instead of beige sleeves.
closure = bpy.data.objects["Mercenary_HiddenGambesonSeamClosure_LOD0"]
closure.data.materials.clear()
closure.data.materials.append(bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"])
closure["source"] = "V16 donor-native cowl with one low hidden textile seam closure"
for polygon in closure.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
previews = {}


def render(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16m_donor_cowl_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    previews[key] = str(path)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49), lens=76, resolution=(1200, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
triangles = sum(triangle_count(obj) for obj in character_meshes)
weights = [sum(group.weight for group in vertex.groups) for vertex in closure.data.vertices]
stats = manifold_stats(closure)
if not 100_000 <= triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {triangles}")
if stats["nonmanifold_edges"]:
    raise RuntimeError(f"Closure is open: {stats}")
if min(weights) < 0.999 or max(weights) > 1.001:
    raise RuntimeError(f"Closure weights invalid: {(min(weights), max(weights))}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "closure_triangles": triangle_count(closure),
    "closure_manifold": stats,
    "closure_weight_sum_range": [min(weights), max(weights)],
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
