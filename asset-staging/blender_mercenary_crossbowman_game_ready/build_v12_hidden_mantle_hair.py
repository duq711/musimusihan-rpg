"""Build the v12 local rear-shoulder notch repairs.

This script starts from the validated v11 candidate.  It adds four closed,
rigged cloth wedges only beneath the measured top-view background notches.
Production assets and the viewer are not touched.
"""

from __future__ import annotations

import math
from pathlib import Path
from collections import defaultdict

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v11.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v12b.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
asset_collection = cowl.users_collection[0]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

# Correct the known inward-facing left component of the v11 seam gussets.
# The right component is already outward-facing and remains untouched.
gussets = bpy.data.objects["Mercenary_ShoulderCowl_Gussets_LOD0"]
gusset_bmesh = bmesh.new()
gusset_bmesh.from_mesh(gussets.data)
left_gusset_faces = [face for face in gusset_bmesh.faces if face.calc_center_median().x < 0.0]
bmesh.ops.reverse_faces(gusset_bmesh, faces=left_gusset_faces)
gusset_bmesh.to_mesh(gussets.data)
gusset_bmesh.free()
gussets.data.update()


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
    vertices = []
    polygons = []
    for obj in scene.objects:
        if obj.type != "MESH" or obj.get("part_category") is None:
            continue
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons)
    return BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1.0e-7)


def pixel_ray(pixel_x, pixel_y):
    width = scene.render.resolution_x * scene.render.resolution_percentage / 100.0
    height = scene.render.resolution_y * scene.render.resolution_percentage / 100.0
    aspect = (width * scene.render.pixel_aspect_x) / (height * scene.render.pixel_aspect_y)
    half_height = camera.data.ortho_scale * 0.5
    half_width = half_height * aspect
    local_x = (((pixel_x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / height) * 2.0 - 1.0) * half_height
    # Ignore object scale: camera projection uses rotation/translation and the
    # explicit ortho scale, while matrix_world may retain a presentation scale.
    rotation = camera.matrix_world.to_quaternion()
    origin = camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))
    direction = rotation @ Vector((0.0, 0.0, -1.0))
    return origin, direction.normalized()


REPORTED_HOLE_RECTS = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)


def reported_pixel_misses(bvh):
    misses = []
    for rectangle_index, (xmin, xmax, ymin, ymax) in enumerate(REPORTED_HOLE_RECTS):
        for pixel_y in range(ymin, ymax + 1):
            for pixel_x in range(xmin, xmax + 1):
                origin, direction = pixel_ray(pixel_x, pixel_y)
                location, _normal, _index, _distance = bvh.ray_cast(origin, direction, 10.0)
                if location is None:
                    misses.append((rectangle_index, pixel_x, pixel_y))
    return misses


set_top_close_camera()
print(
    "V12_CAMERA_DEBUG",
    camera.name,
    camera.parent.name if camera.parent else None,
    tuple(round(value, 6) for value in camera.location),
    tuple(round(value, 6) for value in camera.scale),
    tuple(round(value, 6) for value in camera.matrix_world.translation),
)
pre_mantle_misses = reported_pixel_misses(build_character_bvh())

# Four closed octagonal wedges match the audited missing footprints.  Each
# overlaps its adjacent donor lip by 8-10 mm, extends only a few millimetres
# toward +Y, and sits at the local surface height.  This avoids the visible
# oval/mast-like silhouette produced by a broad mantle.
PATCH_SPECS = (
    # label, CCW top footprint (front/narrow -> rear/wide), top z
    (
        "A_inner_right",
        ((0.120, 0.2076), (0.163, 0.2076), (0.174, 0.2281), (0.1166, 0.2281)),
        1.418,
    ),
    (
        "B_inner_left",
        ((-0.169, 0.1992), (-0.156, 0.1992), (-0.1514, 0.2176), (-0.1874, 0.2176)),
        1.460,
    ),
    (
        "C_outer_left",
        ((-0.218, 0.1865), (-0.207, 0.1865), (-0.1978, 0.2028), (-0.2339, 0.2028)),
        1.428,
    ),
    (
        "D_outer_right",
        ((0.247, 0.1760), (0.259, 0.1760), (0.2856, 0.1922), (0.2411, 0.1922)),
        1.424,
    ),
)
patch_vertices = []
patch_faces = []
patch_vertex_ranges = []

for label, outline, top_z in PATCH_SPECS:
    start = len(patch_vertices)
    ymin = min(point[1] for point in outline)
    ymax = max(point[1] for point in outline)
    top = []
    for x, y in outline:
        front_lift = 0.0015 * (1.0 - (y - ymin) / (ymax - ymin))
        top.append((x, y, top_z + front_lift))
    patch_vertices.extend(top)
    # Maximum under-lip depth is 9 mm at the hidden front overlap, tapering to
    # a sub-millimetre rear seam.  The front overlap keeps the repair closed
    # and rig-safe while the exposed rear rim becomes visually negligible.
    for x, y, z in top:
        rear_t = (y - ymin) / (ymax - ymin)
        local_depth = 0.009 * (1.0 - rear_t) + 0.00075 * rear_t
        patch_vertices.append((x, y, z - local_depth))
    point_count = len(outline)
    patch_faces.append(tuple(start + index for index in range(point_count)))
    patch_faces.append(
        tuple(start + index for index in reversed(range(point_count, point_count * 2)))
    )
    for index in range(point_count):
        following = (index + 1) % point_count
        patch_faces.append(
            (
                start + index,
                start + point_count + index,
                start + point_count + following,
                start + following,
            )
        )
    patch_vertex_ranges.append((label, range(start, start + point_count * 2)))

patch_mesh = bpy.data.meshes.new("Mercenary_RearShoulder_NotchPatches_LOD0_Mesh")
patch_mesh.from_pydata(patch_vertices, [], patch_faces)
patch_mesh.update()
notch_patches = bpy.data.objects.new("Mercenary_RearShoulder_NotchPatches_LOD0", patch_mesh)
asset_collection.objects.link(notch_patches)
notch_patches["game_asset"] = True
notch_patches["part_category"] = "ClothedBody"
notch_patches["intentional_layer"] = True
notch_patches["source"] = "V12 four closed audited rear-notch cloth wedges"
patch_mesh.materials.append(cloth_material)
patch_uv = patch_mesh.uv_layers.new(name="UVMap")
for polygon in patch_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = patch_mesh.vertices[patch_mesh.loops[loop_index].vertex_index].co
        patch_uv.data[loop_index].uv = (co.x * 4.0, co.y * 4.0)

spine_group = notch_patches.vertex_groups.new(name="DEF-spine.004")
left_arm_group = notch_patches.vertex_groups.new(name="DEF-upper_arm.L")
right_arm_group = notch_patches.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in patch_mesh.vertices:
    outward = max(0.0, min(1.0, (abs(vertex.co.x) - 0.16) / 0.20))
    outward = outward * outward * (3.0 - 2.0 * outward)
    spine_group.add([vertex.index], 1.0 - outward, "REPLACE")
    arm_group = left_arm_group if vertex.co.x >= 0.0 else right_arm_group
    arm_group.add([vertex.index], outward, "REPLACE")
patch_armature = notch_patches.modifiers.new("RigifyDeform", "ARMATURE")
patch_armature.object = rig
patch_armature.use_deform_preserve_volume = True
notch_patches.parent = rig
notch_patches.matrix_parent_inverse = rig.matrix_world.inverted()

# The staged scalp/strand meshes were visually rejected: their long strands
# radiated outward and the shell read as a bowl cut.  Preserve the stable v11
# opaque scalp treatment instead of adding either object.
hair_objects = []

post_mantle_misses = reported_pixel_misses(build_character_bvh())
print(
    "V12_PIXEL_MISSES_BY_RECT",
    [
        (
            rectangle_index,
            sum(1 for item in pre_mantle_misses if item[0] == rectangle_index),
            sum(1 for item in post_mantle_misses if item[0] == rectangle_index),
        )
        for rectangle_index in range(len(REPORTED_HOLE_RECTS))
    ],
)
for rectangle_index, (xmin, xmax, ymin, ymax) in enumerate(REPORTED_HOLE_RECTS):
    origin, _direction = pixel_ray((xmin + xmax) // 2, (ymin + ymax) // 2)
    print("V12_RECT_WORLD", rectangle_index, tuple(round(value, 6) for value in origin))
if post_mantle_misses:
    raise RuntimeError(
        f"V12 hidden mantle missed {len(post_mantle_misses)} reported pixels; "
        f"examples={post_mantle_misses[:12]}"
    )

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v12b_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
for direction_index in range(8):
    azimuth = math.radians(direction_index * 45.0)
    location = (
        radius * math.cos(elevation) * math.sin(azimuth),
        -radius * math.cos(elevation) * math.cos(azimuth),
        0.95 + radius * math.sin(elevation),
    )
    key = "failure" if direction_index == 1 else f"high_{direction_index * 45:03d}"
    render(key, location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000) if key == "failure" else (900, 700))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

# Save framed at the exact failure view.
failure_azimuth = math.radians(45.0)
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = (
    radius * math.cos(elevation) * math.sin(failure_azimuth),
    -radius * math.cos(elevation) * math.cos(failure_azimuth),
    0.95 + radius * math.sin(elevation),
)
look_at(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V12_REPORTED_PIXELS_PRE_MISSES", len(pre_mantle_misses))
print("V12_REPORTED_PIXELS_POST_MISSES", len(post_mantle_misses))
print("V12_HAIR_OBJECTS", [obj.name for obj in hair_objects])
print("WROTE", OUTPUT)
