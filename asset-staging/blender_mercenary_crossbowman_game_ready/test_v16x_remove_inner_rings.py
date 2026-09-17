"""Open the three textured scarf folds at the back so they read as wraps."""

from collections import defaultdict
import json
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16ae_open_back_textured_wraps_candidate.blend"
REPORT = STAGING / "v16ae_open_back_textured_wraps_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]

removed = []
for name in (
    "Mercenary_InnerCowl_RolledCollar_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        removed.append(name)
        bpy.data.objects.remove(obj, do_unlink=True)

# The remaining textured cowl contains three useful cloth folds.  Cut each one
# open at a slightly different position behind the neck, then cap the ends.
# From above these become nested U-shaped wraps rather than complete rings.
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
bm = bmesh.new()
bm.from_mesh(cowl.data)
unseen = set(bm.verts)
components = []
while unseen:
    seed = unseen.pop()
    component = {seed}
    stack = [seed]
    while stack:
        vertex = stack.pop()
        linked = {edge.other_vert(vertex) for edge in vertex.link_edges} & unseen
        unseen.difference_update(linked)
        component.update(linked)
        stack.extend(linked)
    components.append(component)
components.sort(key=lambda group: max(abs(vertex.co.x) for vertex in group))
cap_faces = []
for index, component in enumerate(components):
    cutoff = (0.070, 0.092, 0.116)[index]
    doomed = [vertex for vertex in component if vertex.co.y > cutoff]
    bmesh.ops.delete(bm, geom=doomed, context="VERTS")
    boundary = [edge for edge in bm.edges if edge.is_boundary]
    if boundary:
        result = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
        cap_faces.extend(result.get("faces", []))
for face in cap_faces:
    face.material_index = 5
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()
for material in cowl.data.materials:
    if material is not None:
        material.use_backface_culling = False
removed.append("closed back arcs from all three textured cowl folds")


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


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True

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
    path = PREVIEWS / f"diagnostic_v16ae_open_back_textured_wraps_{key}.png"
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
topology = manifold_stats(cowl)
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "removed": removed,
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "textured_cowl_triangles": triangle_count(cowl),
    "textured_cowl_manifold": topology,
    "previews": previews,
}
if not 100_000 <= triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {triangles}")
if topology["nonmanifold_edges"]:
    raise RuntimeError(f"Textured cowl topology failed: {topology}")

REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
