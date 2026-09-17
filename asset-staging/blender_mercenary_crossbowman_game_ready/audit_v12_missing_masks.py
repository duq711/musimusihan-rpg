"""Print the exact v11 no-hit pixel masks inside the four audited boxes."""

from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
bpy.ops.wm.open_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v11.blend"))
scene = bpy.context.scene
camera = scene.camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 0.95
camera.location = (0.0, 0.0, 5.0)
camera.rotation_euler = (Vector((0.0, 0.02, 1.49)) - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
bpy.context.view_layer.update()

vertices = []
polygons = []
for obj in scene.objects:
    if obj.type != "MESH" or obj.get("part_category") is None:
        continue
    offset = len(vertices)
    vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
    polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons)
bvh = BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1.0e-7)


def ray(pixel_x, pixel_y):
    half_height = camera.data.ortho_scale * 0.5
    half_width = half_height * (1200 / 900)
    local_x = (((pixel_x + 0.5) / 1200) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / 900) * 2.0 - 1.0) * half_height
    rotation = camera.matrix_world.to_quaternion()
    origin = camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))
    direction = (rotation @ Vector((0.0, 0.0, -1.0))).normalized()
    return origin, direction


rectangles = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)
for rectangle_index, (xmin, xmax, ymin, ymax) in enumerate(rectangles):
    print("RECT", rectangle_index)
    for pixel_y in range(ymin, ymax + 1):
        row = []
        for pixel_x in range(xmin, xmax + 1):
            origin, direction = ray(pixel_x, pixel_y)
            location, _normal, _index, _distance = bvh.ray_cast(origin, direction, 10.0)
            row.append("#" if location is None else ".")
        print(pixel_y, "".join(row))
