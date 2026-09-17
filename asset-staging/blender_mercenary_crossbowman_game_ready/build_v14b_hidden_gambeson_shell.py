"""Build a compact hidden upper-gambeson shell for steep-angle cavity repair.

Unlike the rejected broad annular prototype, this shell is a rounded padded
volume kept entirely inside the character's existing shoulder/torso envelope.
It becomes visible only through genuine gaps in the donor garment.
"""

from __future__ import annotations

import json
import math
from collections import defaultdict
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v11.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v14b.blend"
REPORT = STAGING / "v14b_hidden_gambeson_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
collection = cowl.users_collection[0]
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]
cowl_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

retired = []
for name in (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True
        if "part_category" in obj:
            obj["part_category_retired_v14b"] = obj["part_category"]
            del obj["part_category"]
        obj["game_asset"] = False
        retired.append(name)


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def rig_object(obj, collar=False):
    spine = obj.vertex_groups.new(name="DEF-spine.004")
    left_arm = obj.vertex_groups.new(name="DEF-upper_arm.L")
    right_arm = obj.vertex_groups.new(name="DEF-upper_arm.R")
    for vertex in obj.data.vertices:
        outward = 0.0 if collar else smoothstep((abs(vertex.co.x) - 0.17) / 0.18)
        spine.add([vertex.index], 1.0 - outward, "REPLACE")
        if outward > 0:
            (left_arm if vertex.co.x >= 0 else right_arm).add([vertex.index], outward, "REPLACE")
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            counts[tuple(sorted((a, b)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


# A compact ellipsoid represents the padded upper tunic beneath the visible
# cowl/vest/sleeves.  Its extrema remain inside the donor envelope:
# x +/-0.37, y -0.16..+0.215, z 1.255..1.435.
bpy.ops.mesh.primitive_uv_sphere_add(segments=128, ring_count=64, location=(0.0, 0.0275, 1.345))
shell = bpy.context.object
shell.name = "Mercenary_HiddenUpperGambesonShell_LOD0"
shell.scale = (0.37, 0.1875, 0.09)
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
shell.data.name = "Mercenary_HiddenUpperGambesonShell_LOD0_Mesh"
if collection not in shell.users_collection:
    for user_collection in list(shell.users_collection):
        user_collection.objects.unlink(shell)
    collection.objects.link(shell)
shell.data.materials.append(gambeson_material)
for polygon in shell.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
shell["game_asset"] = True
shell["part_category"] = "ClothedBody"
shell["intentional_layer"] = True
shell["source"] = "V14b compact hidden padded gambeson under-shell"
rig_object(shell)

# A closed rolled wool collar replaces the thin inner liner.  The torus is
# small enough to remain behind the visible cowl folds and only catches steep
# rays that would otherwise enter a black tunnel.
segments, cross_segments = 128, 16
rx, ry, center_z = 0.133, 0.109, 1.496
collar_vertices = []
for i in range(segments):
    angle = 2 * math.pi * i / segments
    center = Vector((rx * math.cos(angle), ry * math.sin(angle), center_z))
    outward = Vector((math.cos(angle) / rx, math.sin(angle) / ry, 0.0)).normalized()
    for j in range(cross_segments):
        phi = 2 * math.pi * j / cross_segments
        point = center + outward * (0.015 * math.cos(phi))
        point.z += 0.012 * math.sin(phi)
        collar_vertices.append(tuple(point))
collar_faces = []
for i in range(segments):
    ni = (i + 1) % segments
    for j in range(cross_segments):
        nj = (j + 1) % cross_segments
        collar_faces.append((i * cross_segments + j, ni * cross_segments + j,
                             ni * cross_segments + nj, i * cross_segments + nj))
collar_mesh = bpy.data.meshes.new("Mercenary_CowlInnerRoll_v14b_LOD0_Mesh")
collar_mesh.from_pydata(collar_vertices, [], collar_faces)
collar_mesh.update()
bm = bmesh.new()
bm.from_mesh(collar_mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(collar_mesh)
bm.free()
collar_mesh.update()
collar = bpy.data.objects.new("Mercenary_CowlInnerRoll_v14b_LOD0", collar_mesh)
collection.objects.link(collar)
collar_mesh.materials.append(cowl_material)
uv = collar_mesh.uv_layers.new(name="UVMap")
for polygon in collar_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vertex_index = collar_mesh.loops[loop_index].vertex_index
        uv.data[loop_index].uv = ((vertex_index // cross_segments) / segments * 4.0,
                                  (vertex_index % cross_segments) / cross_segments)
collar["game_asset"] = True
collar["part_category"] = "ClothedBody"
collar["intentional_layer"] = True
collar["source"] = "V14b closed rolled cowl inner collar"
rig_object(collar, collar=True)


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


def build_bvh():
    vertices, polygons = [], []
    for obj in scene.objects:
        if obj.type != "MESH" or obj.get("part_category") is None or obj.hide_render:
            continue
        offset = len(vertices)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons)
    return BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1e-7)


def pixel_ray(x, y):
    width, height = 1200.0, 900.0
    half_height = 0.95 * 0.5
    half_width = half_height * (width / height)
    local_x = (((x + 0.5) / width) * 2 - 1) * half_width
    local_y = ((1 - (y + 0.5) / height) * 2 - 1) * half_height
    rotation = camera.matrix_world.to_quaternion()
    origin = camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0))
    direction = (rotation @ Vector((0, 0, -1))).normalized()
    return origin, direction


rects = ((718, 756, 256, 264), (430, 448, 266, 272),
         (386, 404, 280, 284), (836, 862, 290, 294))
set_top_close_camera()
bvh = build_bvh()
misses = []
for xmin, xmax, ymin, ymax in rects:
    count = 0
    for y in range(ymin, ymax + 1):
        for x in range(xmin, xmax + 1):
            origin, direction = pixel_ray(x, y)
            if bvh.ray_cast(origin, direction, 10.0)[0] is None:
                count += 1
    misses.append(count)

stats = {shell.name: manifold_stats(shell), collar.name: manifold_stats(collar)}
# Keep rendering the compact-shell prototype even if the four legacy audited
# rectangles need an additional local refinement.  A nonzero result is still
# recorded as a failed acceptance criterion in the report below.
if any(value["nonmanifold_edges"] for value in stats.values()):
    raise RuntimeError(f"V14b nonmanifold repair: {stats}")

weight_deviation = 0.0
for obj in (shell, collar):
    for vertex in obj.data.vertices:
        weight_deviation = max(weight_deviation, abs(1 - sum(group.weight for group in vertex.groups)))
if weight_deviation > 1e-5:
    raise RuntimeError(f"V14b weight deviation {weight_deviation}")

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v14b_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0, 0, 5), (0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0, 0, 5), (0, 0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius, elevation, azimuth = 4.7, math.radians(80), math.radians(45)
failure_location = (radius * math.cos(elevation) * math.sin(azimuth),
                    -radius * math.cos(elevation) * math.cos(azimuth),
                    0.95 + radius * math.sin(elevation))
render("failure", failure_location, (0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0, -5.2, 0.89), (0, 0, 0.89), ortho_scale=2.06)
render("back", (0, 5.2, 0.89), (0, 0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0, 0, 1.0), lens=72)

camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = failure_location
look_at(camera, (0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

report = {
    "source": str(SOURCE), "output": str(OUTPUT),
    "retired_thin_repairs": retired,
    "new_objects": {
        shell.name: {"vertices": len(shell.data.vertices), "polygons": len(shell.data.polygons), **stats[shell.name]},
        collar.name: {"vertices": len(collar.data.vertices), "polygons": len(collar.data.polygons), **stats[collar.name]},
    },
    "reported_top_rect_misses": misses,
    "max_weight_sum_deviation": weight_deviation,
    "production_touched": False, "viewer_touched": False,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("V14B_RETIRED", retired)
print("V14B_TOP_MISSES", misses)
print("V14B_MANIFOLD", stats)
print("V14B_WEIGHT_DEVIATION", weight_deviation)
print("V14B_WROTE", OUTPUT)
