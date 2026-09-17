"""Recheck the four reported top-close holes on the exported v12 GLB."""

from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
GLB = ROOT / "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_v12.glb"
RECTS = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(GLB))
bpy.context.view_layer.update()

depsgraph = bpy.context.evaluated_depsgraph_get()
vertices = []
polygons = []
mesh_count = 0
for source_obj in bpy.context.scene.objects:
    # Ignore the importer-created unskinned Icosphere bone widget.  Only the
    # twelve exported skinned character meshes may satisfy a hole ray.
    if source_obj.type != "MESH" or not any(
        modifier.type == "ARMATURE" for modifier in source_obj.modifiers
    ):
        continue
    evaluated_obj = source_obj.evaluated_get(depsgraph)
    evaluated_mesh = evaluated_obj.to_mesh()
    offset = len(vertices)
    vertices.extend(evaluated_obj.matrix_world @ vertex.co for vertex in evaluated_mesh.vertices)
    polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in evaluated_mesh.polygons)
    evaluated_obj.to_mesh_clear()
    mesh_count += 1

bvh = BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1.0e-7)
camera_location = Vector((0.0, 0.0, 5.0))
camera_target = Vector((0.0, 0.02, 1.49))
camera_rotation = (camera_target - camera_location).to_track_quat("-Z", "Y")
ray_direction = (camera_rotation @ Vector((0.0, 0.0, -1.0))).normalized()
width = 1200.0
height = 900.0
half_height = 0.95 * 0.5
half_width = half_height * (width / height)


def pixel_origin(pixel_x, pixel_y):
    local_x = (((pixel_x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / height) * 2.0 - 1.0) * half_height
    return camera_location + camera_rotation @ Vector((local_x, local_y, 0.0))


misses_by_rect = []
for xmin, xmax, ymin, ymax in RECTS:
    misses = []
    for pixel_y in range(ymin, ymax + 1):
        for pixel_x in range(xmin, xmax + 1):
            hit = bvh.ray_cast(pixel_origin(pixel_x, pixel_y), ray_direction, 10.0)[0]
            if hit is None:
                misses.append((pixel_x, pixel_y))
    misses_by_rect.append(misses)

print("V12_EXPORTED_MESH_COUNT", mesh_count)
print("V12_EXPORTED_TOP_CLOSE_MISSES", [len(misses) for misses in misses_by_rect])
if any(misses_by_rect):
    raise RuntimeError(
        "Exported GLB still exposes background in reported rectangles: "
        + repr([misses[:12] for misses in misses_by_rect])
    )
