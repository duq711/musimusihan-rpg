"""Replace only the artificial inner-cowl liner with three compact cloth rolls.

Base: v13b, which already has four closed knife-taper shoulder-notch repairs.
No broad yoke, torso shell, plate, or silhouette-changing volume is added.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13b.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v14c.blend"
REPORT = STAGING / "v14c_layered_inner_rolls_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
collection = cowl.users_collection[0]
material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

liner = bpy.data.objects["Mercenary_InnerCowl_Liner_LOD0"]
liner.hide_render = True
liner.hide_viewport = True
liner["part_category_retired_v14c"] = liner.get("part_category")
if "part_category" in liner:
    del liner["part_category"]
liner["game_asset"] = False


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        points = list(polygon.vertices)
        for first, second in zip(points, points[1:] + points[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        "nonmanifold_edges": sum(count != 2 for count in counts.values()),
        "boundary_edges": sum(count == 1 for count in counts.values()),
        "overconnected_edges": sum(count > 2 for count in counts.values()),
    }


def create_elliptical_roll(name, rx, ry, center_z, radial_width, vertical_height,
                           phase_offset, segments=128, cross_segments=14):
    vertices = []
    for angular_index in range(segments):
        angle = 2.0 * math.pi * angular_index / segments
        # Millimetric irregularity avoids a machine-perfect torus while
        # retaining a stable, closed silhouette inside the cowl.
        ripple = 1.0 + 0.018 * math.sin(3.0 * angle + phase_offset) + 0.010 * math.sin(7.0 * angle - 0.4)
        local_rx = rx * ripple
        local_ry = ry * ripple
        center = Vector((local_rx * math.cos(angle), local_ry * math.sin(angle),
                         center_z + 0.0014 * math.sin(4.0 * angle + phase_offset)))
        outward = Vector((math.cos(angle) / rx, math.sin(angle) / ry, 0.0)).normalized()
        for cross_index in range(cross_segments):
            phi = 2.0 * math.pi * cross_index / cross_segments
            point = center + outward * (radial_width * math.cos(phi))
            point.z += vertical_height * math.sin(phi)
            vertices.append(tuple(point))

    faces = []
    for angular_index in range(segments):
        angular_next = (angular_index + 1) % segments
        for cross_index in range(cross_segments):
            cross_next = (cross_index + 1) % cross_segments
            faces.append((
                angular_index * cross_segments + cross_index,
                angular_next * cross_segments + cross_index,
                angular_next * cross_segments + cross_next,
                angular_index * cross_segments + cross_next,
            ))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True
        for loop_index in polygon.loop_indices:
            vertex_index = mesh.loops[loop_index].vertex_index
            angular_index = vertex_index // cross_segments
            cross_index = vertex_index % cross_segments
            uv.data[loop_index].uv = (
                angular_index / segments * 4.0,
                cross_index / cross_segments,
            )

    obj["game_asset"] = True
    obj["part_category"] = "ClothedBody"
    obj["intentional_layer"] = True
    obj["source"] = "V14c compact layered closed inner-cowl roll"
    spine = obj.vertex_groups.new(name="DEF-spine.004")
    spine.add([vertex.index for vertex in mesh.vertices], 1.0, "REPLACE")
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    return obj


roll_specs = (
    # Bounds stay inside x +/-0.19 and y +/-0.13.
    ("Mercenary_CowlInnerRoll_01_LOD0", 0.106, 0.080, 1.517, 0.0115, 0.0095, 0.2),
    ("Mercenary_CowlInnerRoll_02_LOD0", 0.132, 0.098, 1.500, 0.0110, 0.0090, 1.4),
    ("Mercenary_CowlInnerRoll_03_LOD0", 0.158, 0.116, 1.484, 0.0090, 0.0080, 2.5),
)
rolls = [create_elliptical_roll(*spec) for spec in roll_specs]


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


def character_bvh():
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
    half_width = half_height * width / height
    local_x = (((x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (y + 0.5) / height) * 2.0 - 1.0) * half_height
    rotation = camera.matrix_world.to_quaternion()
    origin = camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))
    return origin, (rotation @ Vector((0.0, 0.0, -1.0))).normalized()


rects = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)
set_top_close_camera()
bvh = character_bvh()
misses = []
for xmin, xmax, ymin, ymax in rects:
    count = 0
    for y in range(ymin, ymax + 1):
        for x in range(xmin, xmax + 1):
            origin, direction = pixel_ray(x, y)
            if bvh.ray_cast(origin, direction, 10.0)[0] is None:
                count += 1
    misses.append(count)

stats = {obj.name: manifold_stats(obj) for obj in rolls}
bounds = {}
for obj in rolls:
    coords = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    bounds[obj.name] = {
        "min": [min(co[axis] for co in coords) for axis in range(3)],
        "max": [max(co[axis] for co in coords) for axis in range(3)],
    }
    if bounds[obj.name]["min"][0] < -0.19 or bounds[obj.name]["max"][0] > 0.19:
        raise RuntimeError(f"Roll exceeded x limit: {obj.name} {bounds[obj.name]}")
    if bounds[obj.name]["min"][1] < -0.13 or bounds[obj.name]["max"][1] > 0.13:
        raise RuntimeError(f"Roll exceeded y limit: {obj.name} {bounds[obj.name]}")
if any(misses):
    raise RuntimeError(f"V14c reopened shoulder rays: {misses}")
if any(value["nonmanifold_edges"] for value in stats.values()):
    raise RuntimeError(f"V14c nonmanifold rolls: {stats}")

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v14c_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0, 0, 5), (0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0, 0, 5), (0, 0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius, elevation, azimuth = 4.7, math.radians(80), math.radians(45)
failure_location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
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
    "source": str(SOURCE),
    "output": str(OUTPUT),
    "retired_object": liner.name,
    "new_rolls": {
        obj.name: {
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "triangles": sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons),
            "bounds": bounds[obj.name],
            **stats[obj.name],
        }
        for obj in rolls
    },
    "reported_shoulder_ray_misses": misses,
    "broad_yoke_or_shell_added": False,
    "production_touched": False,
    "viewer_touched": False,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("V14C_RAYS", misses)
print("V14C_MANIFOLD", stats)
print("V14C_BOUNDS", bounds)
print("V14C_WROTE", OUTPUT)
