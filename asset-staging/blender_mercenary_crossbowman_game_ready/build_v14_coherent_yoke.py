"""Build an independent coherent upper-gambeson/yoke candidate from v11.

The v11 scene contains several thin fan/gusset repairs at the shoulder/cowl
seam.  From a steep camera angle they read as disconnected panels and leave
dark cavities.  This candidate replaces only those repair objects with one
curved, closed, rigged cloth yoke plus a small rolled inner collar.  The base
donor, cowl, head, silhouette, and production files are left untouched.
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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v14.blend"
REPORT = STAGING / "v14_coherent_yoke_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
asset_collection = cowl.users_collection[0]
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]
cowl_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

# Retire the disconnected v11 fan/gusset repairs.  They are kept in the file
# as non-rendering provenance, but cannot be exported or appear in previews.
retired = []
for object_name in (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
):
    obj = bpy.data.objects.get(object_name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True
        obj["part_category_retired_v14"] = obj.get("part_category")
        if "part_category" in obj:
            del obj["part_category"]
        obj["game_asset"] = False
        retired.append(object_name)


def smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def recalc_outside(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def edge_manifold_stats(obj):
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


def add_rigging(obj, collar=False):
    spine = obj.vertex_groups.new(name="DEF-spine.004")
    left_arm = obj.vertex_groups.new(name="DEF-upper_arm.L")
    right_arm = obj.vertex_groups.new(name="DEF-upper_arm.R")
    for vertex in obj.data.vertices:
        if collar:
            outward = 0.0
        else:
            outward = smoothstep((abs(vertex.co.x) - 0.16) / 0.23)
        spine.add([vertex.index], 1.0 - outward, "REPLACE")
        if outward > 0.0:
            (left_arm if vertex.co.x >= 0.0 else right_arm).add(
                [vertex.index], outward, "REPLACE"
            )
    armature = obj.modifiers.new("RigifyDeform", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


# ---------------------------------------------------------------------------
# One closed, padded shoulder yoke.  It is an elliptical annulus following the
# slope from neck to shoulder, not a flat plate.  The top is finely segmented,
# the underside is offset downward, and both rims are closed.
# ---------------------------------------------------------------------------
angular_segments = 128
radial_segments = 14
inner_rx, inner_ry = 0.125, 0.105
outer_rx, outer_ry = 0.445, 0.245
thickness = 0.014

yoke_vertices = []
for surface in ("top", "bottom"):
    for radial_index in range(radial_segments + 1):
        t = radial_index / radial_segments
        eased = smoothstep(t)
        rx = inner_rx + (outer_rx - inner_rx) * eased
        ry = inner_ry + (outer_ry - inner_ry) * eased
        for angular_index in range(angular_segments):
            angle = 2.0 * math.pi * angular_index / angular_segments
            x = rx * math.cos(angle)
            y = ry * math.sin(angle) + 0.015 * eased
            # Raised neck seam, soft shoulder falloff, and low-amplitude cloth
            # undulation.  The back lip is slightly higher to fill the audited
            # rear shoulder notches while staying beneath the donor garment.
            outer_height = 1.405 + 0.020 * abs(math.cos(angle)) ** 1.7
            rear_lift = 0.012 * max(0.0, math.sin(angle)) * eased
            z = 1.502 * (1.0 - eased) + outer_height * eased + rear_lift
            z += 0.0025 * math.sin(4.0 * angle + 0.7) * math.sin(math.pi * t) ** 2
            if surface == "bottom":
                z -= thickness
            yoke_vertices.append((x, y, z))

ring_size = angular_segments
surface_size = (radial_segments + 1) * ring_size
yoke_faces = []
for radial_index in range(radial_segments):
    for angular_index in range(angular_segments):
        nxt = (angular_index + 1) % angular_segments
        a = radial_index * ring_size + angular_index
        b = (radial_index + 1) * ring_size + angular_index
        c = (radial_index + 1) * ring_size + nxt
        d = radial_index * ring_size + nxt
        yoke_faces.append((a, b, c, d))
        yoke_faces.append(
            (surface_size + d, surface_size + c, surface_size + b, surface_size + a)
        )

for angular_index in range(angular_segments):
    nxt = (angular_index + 1) % angular_segments
    # Outer rim: normal points away from the garment.
    outer_top = radial_segments * ring_size
    yoke_faces.append(
        (
            outer_top + angular_index,
            surface_size + outer_top + angular_index,
            surface_size + outer_top + nxt,
            outer_top + nxt,
        )
    )
    # Inner rim: normal points into the neck opening.
    yoke_faces.append(
        (
            nxt,
            surface_size + nxt,
            surface_size + angular_index,
            angular_index,
        )
    )

yoke_mesh = bpy.data.meshes.new("Mercenary_CoherentPaddedYoke_LOD0_Mesh")
yoke_mesh.from_pydata(yoke_vertices, [], yoke_faces)
yoke_mesh.update()
recalc_outside(yoke_mesh)
yoke = bpy.data.objects.new("Mercenary_CoherentPaddedYoke_LOD0", yoke_mesh)
asset_collection.objects.link(yoke)
yoke_mesh.materials.append(gambeson_material)
yoke["game_asset"] = True
yoke["part_category"] = "ClothedBody"
yoke["intentional_layer"] = True
yoke["source"] = "V14 coherent padded gambeson shoulder yoke"

yoke_uv = yoke_mesh.uv_layers.new(name="UVMap")
for polygon in yoke_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = yoke_mesh.vertices[yoke_mesh.loops[loop_index].vertex_index].co
        # Stable top projection at a useful texel density; the 4K gambeson
        # texture is seamless, so the closed underside/rims may reuse it.
        yoke_uv.data[loop_index].uv = (0.5 + co.x * 2.25, 0.5 + (co.y - 0.015) * 2.25)
add_rigging(yoke)


# ---------------------------------------------------------------------------
# Closed rolled collar at the yoke's inner rim.  Its curved top replaces the
# dark, tunnel-like inner edge visible from steep angles without touching the
# head or changing the front silhouette.
# ---------------------------------------------------------------------------
collar_segments = 128
collar_cross_segments = 14
collar_vertices = []
for angular_index in range(collar_segments):
    angle = 2.0 * math.pi * angular_index / collar_segments
    center = Vector((inner_rx * math.cos(angle), inner_ry * math.sin(angle), 1.502))
    outward = Vector((math.cos(angle) / inner_rx, math.sin(angle) / inner_ry, 0.0)).normalized()
    for cross_index in range(collar_cross_segments):
        phi = 2.0 * math.pi * cross_index / collar_cross_segments
        # Slightly flattened cloth roll, 26-30 mm across.
        radial_width = 0.0145
        vertical_height = 0.012
        point = center + outward * (radial_width * math.cos(phi))
        point.z += vertical_height * math.sin(phi)
        collar_vertices.append(tuple(point))

collar_faces = []
for angular_index in range(collar_segments):
    angular_next = (angular_index + 1) % collar_segments
    for cross_index in range(collar_cross_segments):
        cross_next = (cross_index + 1) % collar_cross_segments
        a = angular_index * collar_cross_segments + cross_index
        b = angular_next * collar_cross_segments + cross_index
        c = angular_next * collar_cross_segments + cross_next
        d = angular_index * collar_cross_segments + cross_next
        collar_faces.append((a, b, c, d))

collar_mesh = bpy.data.meshes.new("Mercenary_CowlInnerRoll_LOD0_Mesh")
collar_mesh.from_pydata(collar_vertices, [], collar_faces)
collar_mesh.update()
recalc_outside(collar_mesh)
collar = bpy.data.objects.new("Mercenary_CowlInnerRoll_LOD0", collar_mesh)
asset_collection.objects.link(collar)
collar_mesh.materials.append(cowl_material)
collar["game_asset"] = True
collar["part_category"] = "ClothedBody"
collar["intentional_layer"] = True
collar["source"] = "V14 closed rolled charcoal inner collar"
collar_uv = collar_mesh.uv_layers.new(name="UVMap")
for polygon in collar_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vertex_index = collar_mesh.loops[loop_index].vertex_index
        angular_index = vertex_index // collar_cross_segments
        cross_index = vertex_index % collar_cross_segments
        collar_uv.data[loop_index].uv = (
            angular_index / collar_segments * 4.0,
            cross_index / collar_cross_segments,
        )
add_rigging(collar, collar=True)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def build_character_bvh():
    vertices = []
    polygons = []
    object_ranges = []
    for obj in scene.objects:
        if obj.type != "MESH" or obj.get("part_category") is None or obj.hide_render:
            continue
        offset = len(vertices)
        start_polygon = len(polygons)
        vertices.extend(obj.matrix_world @ vertex.co for vertex in obj.data.vertices)
        polygons.extend(tuple(offset + index for index in polygon.vertices) for polygon in obj.data.polygons)
        object_ranges.append((start_polygon, len(polygons), obj.name))
    return BVHTree.FromPolygons(vertices, polygons, all_triangles=False, epsilon=1.0e-7), object_ranges


def set_top_close_camera():
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 0.95
    camera.location = (0.0, 0.0, 5.0)
    look_at(camera, (0.0, 0.02, 1.49))
    scene.render.resolution_x = 1200
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    bpy.context.view_layer.update()


def pixel_ray(pixel_x, pixel_y):
    width, height = 1200.0, 900.0
    aspect = width / height
    half_height = camera.data.ortho_scale * 0.5
    half_width = half_height * aspect
    local_x = (((pixel_x + 0.5) / width) * 2.0 - 1.0) * half_width
    local_y = ((1.0 - (pixel_y + 0.5) / height) * 2.0 - 1.0) * half_height
    rotation = camera.matrix_world.to_quaternion()
    origin = camera.matrix_world.translation + rotation @ Vector((local_x, local_y, 0.0))
    return origin, (rotation @ Vector((0.0, 0.0, -1.0))).normalized()


REPORTED_HOLE_RECTS = (
    (718, 756, 256, 264),
    (430, 448, 266, 272),
    (386, 404, 280, 284),
    (836, 862, 290, 294),
)

set_top_close_camera()
bvh, _ranges = build_character_bvh()
misses_by_rect = []
for xmin, xmax, ymin, ymax in REPORTED_HOLE_RECTS:
    misses = 0
    for pixel_y in range(ymin, ymax + 1):
        for pixel_x in range(xmin, xmax + 1):
            origin, direction = pixel_ray(pixel_x, pixel_y)
            if bvh.ray_cast(origin, direction, 10.0)[0] is None:
                misses += 1
    misses_by_rect.append(misses)

manifold = {
    yoke.name: edge_manifold_stats(yoke),
    collar.name: edge_manifold_stats(collar),
}
if any(misses_by_rect):
    raise RuntimeError(f"V14 reopened audited top holes: {misses_by_rect}")
if any(stats["nonmanifold_edges"] for stats in manifold.values()):
    raise RuntimeError(f"V14 repair shell is not closed manifold: {manifold}")

weight_deviation = 0.0
for obj in (yoke, collar):
    for vertex in obj.data.vertices:
        total = sum(group.weight for group in vertex.groups)
        weight_deviation = max(weight_deviation, abs(1.0 - total))
if weight_deviation > 1.0e-5:
    raise RuntimeError(f"V14 weight normalization deviation {weight_deviation}")

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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v14_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
failure_azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(failure_azimuth),
    -radius * math.cos(elevation) * math.cos(failure_azimuth),
    0.95 + radius * math.sin(elevation),
)
render("failure", failure_location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

# Save at the user's reported steep inspection angle.
camera.data.type = "PERSP"
camera.data.lens = 78
camera.location = failure_location
look_at(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

report = {
    "source": str(SOURCE),
    "output": str(OUTPUT),
    "retired_disconnected_repairs": retired,
    "new_objects": {
        yoke.name: {
            "vertices": len(yoke_mesh.vertices),
            "polygons": len(yoke_mesh.polygons),
            "triangles": sum(max(1, len(poly.vertices) - 2) for poly in yoke_mesh.polygons),
            **manifold[yoke.name],
        },
        collar.name: {
            "vertices": len(collar_mesh.vertices),
            "polygons": len(collar_mesh.polygons),
            "triangles": sum(max(1, len(poly.vertices) - 2) for poly in collar_mesh.polygons),
            **manifold[collar.name],
        },
    },
    "reported_top_rect_misses": misses_by_rect,
    "max_weight_sum_deviation": weight_deviation,
    "production_touched": False,
    "viewer_touched": False,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

print("V14_RETIRED", retired)
print("V14_REPORTED_TOP_MISSES", misses_by_rect)
print("V14_MANIFOLD", manifold)
print("V14_MAX_WEIGHT_DEVIATION", weight_deviation)
print("V14_WROTE", OUTPUT)
print("V14_REPORT", REPORT)
