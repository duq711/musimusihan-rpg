"""Replace v12 rear seam walls with closed knife-tapered cloth wedges.

The four audited top footprints remain unchanged.  Each wedge retains a 9 mm
hidden front overlap, but its top and underside share the same rear edge, so
the back orthographic view has no rear-facing repair wall to draw as a bar.
"""

from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v12.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13b.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
patches = bpy.data.objects["Mercenary_RearShoulder_NotchPatches_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

PATCH_SPECS = (
    ("A_inner_right", ((0.120, 0.2076), (0.163, 0.2076), (0.174, 0.2281), (0.1166, 0.2281)), 1.418),
    ("B_inner_left", ((-0.169, 0.1992), (-0.156, 0.1992), (-0.1514, 0.2176), (-0.1874, 0.2176)), 1.460),
    ("C_outer_left", ((-0.218, 0.1865), (-0.207, 0.1865), (-0.1978, 0.2028), (-0.2339, 0.2028)), 1.428),
    ("D_outer_right", ((0.247, 0.1760), (0.259, 0.1760), (0.2856, 0.1922), (0.2411, 0.1922)), 1.424),
)

vertices = []
faces = []
component_ranges = []
for label, outline, top_z in PATCH_SPECS:
    start = len(vertices)
    ymin = min(point[1] for point in outline)
    ymax = max(point[1] for point in outline)
    top = []
    for x, y in outline:
        front_lift = 0.0015 * (1.0 - (y - ymin) / (ymax - ymin))
        top.append((x, y, top_z + front_lift))

    # t0, t1, rear-right, rear-left, bottom-front-left, bottom-front-right.
    # The rear top vertices are reused by the underside rather than duplicated.
    vertices.extend(top)
    vertices.append((top[0][0], top[0][1], top[0][2] - 0.009))
    vertices.append((top[1][0], top[1][1], top[1][2] - 0.009))
    faces.extend(
        (
            (start + 0, start + 1, start + 2, start + 3),
            (start + 4, start + 3, start + 2, start + 5),
            (start + 0, start + 4, start + 5, start + 1),
            (start + 1, start + 5, start + 2),
            (start + 0, start + 3, start + 4),
        )
    )
    component_ranges.append((label, range(start, start + 6)))

new_mesh = bpy.data.meshes.new("Mercenary_RearShoulder_NotchPatches_KnifeTaper_LOD0_Mesh")
new_mesh.from_pydata(vertices, [], faces)
new_mesh.update()
old_mesh = patches.data
patches.data = new_mesh
bpy.data.meshes.remove(old_mesh)
new_mesh.materials.append(cloth_material)
uv = new_mesh.uv_layers.new(name="UVMap")
for polygon in new_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        coordinate = new_mesh.vertices[new_mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = (coordinate.x * 4.0, coordinate.y * 4.0)

patches.vertex_groups.clear()
spine_group = patches.vertex_groups.new(name="DEF-spine.004")
left_arm_group = patches.vertex_groups.new(name="DEF-upper_arm.L")
right_arm_group = patches.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in new_mesh.vertices:
    outward = max(0.0, min(1.0, (abs(vertex.co.x) - 0.16) / 0.20))
    outward = outward * outward * (3.0 - 2.0 * outward)
    spine_group.add([vertex.index], 1.0 - outward, "REPLACE")
    (left_arm_group if vertex.co.x >= 0.0 else right_arm_group).add(
        [vertex.index], outward, "REPLACE"
    )
patches["repair_geometry"] = "four closed knife-taper wedges; shared rear edge"


def nonmanifold_edge_count(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        points = list(polygon.vertices)
        for first, second in zip(points, points[1:] + points[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return sum(count != 2 for count in counts.values())


if nonmanifold_edge_count(patches) != 0:
    raise RuntimeError("Knife-taper repair is not closed manifold")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def set_top_close_camera():
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.95
    camera.location = (0.0, 0.0, 5.0)
    look_at(camera, (0.0, 0.02, 1.49))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    bpy.context.view_layer.update()


def build_character_bvh():
    all_vertices = []
    all_polygons = []
    for obj in scene.objects:
        if obj.type != "MESH" or obj.get("part_category") is None:
            continue
        offset = len(all_vertices)
        all_vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        all_polygons.extend(
            tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons
        )
    return BVHTree.FromPolygons(all_vertices, all_polygons, all_triangles=False, epsilon=1.0e-7)


def pixel_origin(pixel_x, pixel_y):
    width, height = 1200.0, 900.0
    half_height = 0.95 * 0.5
    half_width = half_height * (width / height)
    local_x = (((pixel_x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / height) * 2.0 - 1.0) * half_height
    rotation = camera.matrix_world.to_quaternion()
    return camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))


RECTS = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)
set_top_close_camera()
bvh = build_character_bvh()
ray_direction = camera.matrix_world.to_quaternion() @ Vector((0.0, 0.0, -1.0))
misses_by_rect = []
for xmin, xmax, ymin, ymax in RECTS:
    misses = 0
    for pixel_y in range(ymin, ymax + 1):
        for pixel_x in range(xmin, xmax + 1):
            if bvh.ray_cast(pixel_origin(pixel_x, pixel_y), ray_direction, 10.0)[0] is None:
                misses += 1
    misses_by_rect.append(misses)
if any(misses_by_rect):
    raise RuntimeError(f"Knife taper reopened top-close holes: {misses_by_rect}")

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"


def render(name, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13b_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back_close", (0.0, 5.2, 1.42), (0.0, 0.0, 1.42), ortho_scale=0.78, resolution=(1400, 700))
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

camera.data.type = "ORTHO"
camera.data.ortho_scale = 0.78
camera.location = (0.0, 5.2, 1.42)
look_at(camera, (0.0, 0.0, 1.42))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V13B_TOP_CLOSE_MISSES", misses_by_rect)
print("V13B_NONMANIFOLD", nonmanifold_edge_count(patches))
print("V13B_PATCH_VERTICES_POLYGONS_TRIANGLES", len(new_mesh.vertices), len(new_mesh.polygons), 32)
print("V13B_SHARED_REAR_EDGE", True)
print("WROTE", OUTPUT)
