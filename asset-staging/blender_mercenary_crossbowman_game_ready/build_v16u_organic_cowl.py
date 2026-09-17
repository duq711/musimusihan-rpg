"""Build an isolated v16 organic cowl candidate from the v15 scene.

This candidate deliberately removes the six concentric shells and every small
repair object.  Five intersecting, irregular cloth folds are voxel-unioned into
one connected closed manifold.  The canonical GLB and web preview are not
touched by this script.
"""

from __future__ import annotations

from collections import Counter, defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16u_organic_cowl.blend"
REPORT = STAGING / "build_summary_v16u_organic_cowl.json"

REMOVE_NAMES = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
asset_collection = donor.users_collection[0]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

for name in REMOVE_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return float(value >= edge1)
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


vertices = []
faces = []


def add_tube(path, radii, vertical_radii, cyclic):
    """Add a closed elliptical tube around an already organic center path."""

    start = len(vertices)
    segments = len(path)
    cross_segments = 14
    for index, point in enumerate(path):
        previous = path[(index - 1) % segments] if cyclic or index else path[index]
        following = path[(index + 1) % segments] if cyclic or index < segments - 1 else path[index]
        tangent = (following - previous).normalized()
        # Keep the cloth tube upright.  Its horizontal normal follows the path
        # but is allowed to skew, removing the machined-torus appearance.
        horizontal = Vector((-tangent.y, tangent.x, 0.0))
        if horizontal.length < 1.0e-6:
            horizontal = Vector((1.0, 0.0, 0.0))
        horizontal.normalize()
        if horizontal.dot(Vector((point.x, point.y - 0.02, 0.0))) < 0.0:
            horizontal.negate()
        for cross in range(cross_segments):
            phi = math.tau * cross / cross_segments
            local_r = radii[index] * (1.0 + 0.055 * math.sin(3.0 * phi + index * 0.071))
            co = point + horizontal * (local_r * math.cos(phi))
            co.z += vertical_radii[index] * math.sin(phi)
            vertices.append(tuple(co))

    span = segments if cyclic else segments - 1
    for index in range(span):
        following = (index + 1) % segments
        for cross in range(cross_segments):
            following_cross = (cross + 1) % cross_segments
            faces.append(
                (
                    start + index * cross_segments + cross,
                    start + following * cross_segments + cross,
                    start + following * cross_segments + following_cross,
                    start + index * cross_segments + following_cross,
                )
            )
    if not cyclic:
        for end_index, reverse in ((0, True), (segments - 1, False)):
            center_index = len(vertices)
            vertices.append(tuple(path[end_index]))
            ring_start = start + end_index * cross_segments
            for cross in range(cross_segments):
                triangle = (
                    center_index,
                    ring_start + cross,
                    ring_start + (cross + 1) % cross_segments,
                )
                faces.append(tuple(reversed(triangle)) if reverse else triangle)


def irregular_ring(rx, ry, center_y, base_z, radial, vertical, phase, back_lift, front_drop):
    count = 176
    path = []
    radii = []
    vertical_radii = []
    for index in range(count):
        theta = math.tau * index / count
        sine = math.sin(theta)
        cosine = math.cos(theta)
        radial_noise = 1.0 + 0.040 * math.sin(3.0 * theta + phase) + 0.024 * math.sin(7.0 * theta - 0.7 * phase)
        x = rx * radial_noise * cosine + 0.007 * math.sin(2.0 * theta + phase)
        y = center_y + ry * (1.0 + 0.045 * math.sin(5.0 * theta - phase)) * sine
        rear = max(0.0, sine)
        front = max(0.0, -sine)
        z = (
            base_z
            + back_lift * rear * rear
            - front_drop * front * front
            + 0.0075 * math.sin(3.0 * theta + phase)
            + 0.0035 * math.sin(8.0 * theta - phase)
        )
        path.append(Vector((x, y, z)))
        radii.append(radial * (1.0 + 0.13 * math.sin(5.0 * theta + phase) + 0.05 * math.sin(11.0 * theta)))
        vertical_radii.append(vertical * (1.0 + 0.11 * math.sin(4.0 * theta - phase)))
    add_tube(path, radii, vertical_radii, cyclic=True)


# The three principal folds overlap, but their paths and profiles are not
# concentric.  The lower fold seals the donor's branching collar boundary; the
# upper fold rises only at the back like a soft hood.
irregular_ring(0.258, 0.188, 0.030, 1.447, 0.038, 0.030, 0.35, 0.024, 0.025)
irregular_ring(0.214, 0.154, 0.021, 1.480, 0.040, 0.032, 1.55, 0.040, 0.018)
irregular_ring(0.158, 0.112, 0.020, 1.524, 0.041, 0.035, 2.45, 0.058, 0.010)


# A raised, incomplete rear wrap creates the hood mass without making another
# full torus.  The front arc makes a broad, low clavicle drape.
rear_path = []
rear_radii = []
rear_vertical = []
for index in range(112):
    theta = math.pi * index / 111.0
    sine = math.sin(theta)
    cosine = math.cos(theta)
    rear_path.append(
        Vector(
            (
                0.205 * cosine + 0.006 * math.sin(4.0 * theta),
                0.034 + 0.190 * sine,
                1.493 + 0.072 * sine + 0.006 * math.sin(5.0 * theta + 0.4),
            )
        )
    )
    rear_radii.append(0.041 * (1.0 + 0.10 * math.sin(3.0 * theta + 0.2)))
    rear_vertical.append(0.035 * (1.0 + 0.08 * math.sin(4.0 * theta - 0.5)))
add_tube(rear_path, rear_radii, rear_vertical, cyclic=False)

front_path = []
front_radii = []
front_vertical = []
for index in range(104):
    theta = math.pi + math.pi * index / 103.0
    sine = math.sin(theta)
    cosine = math.cos(theta)
    front = max(0.0, -sine)
    front_path.append(
        Vector(
            (
                0.215 * cosine + 0.005 * math.sin(3.0 * theta + 0.9),
                0.018 + 0.162 * sine,
                1.469 - 0.034 * front + 0.006 * math.sin(4.0 * theta + 0.7),
            )
        )
    )
    front_radii.append(0.038 * (1.0 + 0.12 * math.sin(5.0 * theta + 0.3)))
    front_vertical.append(0.030 * (1.0 + 0.10 * math.sin(3.0 * theta - 0.8)))
add_tube(front_path, front_radii, front_vertical, cyclic=False)


mesh = bpy.data.meshes.new("Mercenary_OrganicWoolCowl_v16u_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new("Mercenary_OrganicWoolCowl_v16u_LOD0", mesh)
asset_collection.objects.link(cowl)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16U five irregular folds voxel-unioned into one manifold scarf"

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
mesh.remesh_voxel_size = 0.0032
mesh.remesh_voxel_adaptivity = 0.0
bpy.ops.object.voxel_remesh()

# Remove voxel stair-stepping while preserving the larger asymmetric folds.
smooth = cowl.modifiers.new("V16U_ClothRelax", "SMOOTH")
smooth.factor = 0.22
smooth.iterations = 3
bpy.context.view_layer.objects.active = cowl
bpy.ops.object.modifier_apply(modifier=smooth.name)

current_triangles = sum(max(1, len(poly.vertices) - 2) for poly in cowl.data.polygons)
target_triangles = 17_500
if current_triangles > target_triangles:
    decimate = cowl.modifiers.new("V16U_GameReadyDecimate", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = target_triangles / current_triangles
    decimate.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = cowl
    bpy.ops.object.modifier_apply(modifier=decimate.name)

for polygon in cowl.data.polygons:
    polygon.use_smooth = True
cowl.data.materials.append(cloth_material)
for polygon in cowl.data.polygons:
    polygon.material_index = 0

# One coherent UV atlas drives the one coherent wool material.
bpy.context.view_layer.objects.active = cowl
cowl.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.151917, island_margin=0.015, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

# Spatial Rigify profile measured from the neighbouring v15 cowl/donor.
groups = {
    name: cowl.vertex_groups.new(name=name)
    for name in (
        "DEF-spine.004",
        "DEF-spine.005",
        "DEF-spine.006",
        "DEF-upper_arm.L",
        "DEF-upper_arm.R",
    )
}
for vertex in cowl.data.vertices:
    x, _y, z = vertex.co
    upper = smoothstep(1.495, 1.540, z)
    outer = smoothstep(0.225, 0.305, abs(x))
    arm_weight = 0.25 * outer * (1.0 - 0.70 * upper)
    remaining = 1.0 - upper - arm_weight
    if remaining < 0.0:
        remaining = 0.0
    mid = smoothstep(1.455, 1.505, z)
    spine004_fraction = (0.40 * (1.0 - mid) + 0.14 * mid) * (1.0 - outer) + 0.90 * outer
    spine004 = remaining * spine004_fraction
    spine005 = remaining - spine004
    values = {
        "DEF-spine.004": spine004,
        "DEF-spine.005": spine005,
        "DEF-spine.006": upper,
        "DEF-upper_arm.L" if x >= 0.0 else "DEF-upper_arm.R": arm_weight,
    }
    total = sum(values.values())
    for name, value in values.items():
        if value > 1.0e-7:
            groups[name].add([vertex.index], value / total, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()


# Remove the square crown projection seam without changing head topology.  The
# selection is a softly sloped, asymmetric hairline; its UVs wrap around the
# scalp instead of retaining front/back projection coordinates.
hair_material = bpy.data.materials["MAT_ScalpHair_DarkBrown_PBR_2K_v11"]
hair_index = list(head.data.materials).index(hair_material)
uv_layer = head.data.uv_layers.get("UVMap")
hair_polygons = []
for polygon in head.data.polygons:
    center = polygon.center
    rear_relief = 0.030 * smoothstep(-0.015, 0.105, center.y)
    side_raise = 0.012 * smoothstep(0.060, 0.100, abs(center.x))
    irregular = 0.006 * math.sin(center.x * 83.0 + center.y * 39.0)
    threshold = 1.682 - rear_relief + side_raise + irregular
    if center.z >= threshold:
        polygon.material_index = hair_index
        hair_polygons.append(polygon)
        if uv_layer is not None:
            for loop_index in polygon.loop_indices:
                co = head.data.vertices[head.data.loops[loop_index].vertex_index].co
                u = (math.atan2(co.y - 0.005, co.x) / math.tau + 0.5) * 2.0
                v = (co.z - 1.625) * 8.0
                uv_layer.data[loop_index].uv = (u, v)
head.data.update()


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        vs = list(poly.vertices)
        for first, second in zip(vs, vs[1:] + vs[:1]):
            counts[tuple(sorted((first, second)))] += 1
    # A voxel union should have one face component.  Count it independently of
    # the edge-manifold assertion.
    edge_faces = defaultdict(list)
    for poly in obj.data.polygons:
        vs = list(poly.vertices)
        for first, second in zip(vs, vs[1:] + vs[:1]):
            edge_faces[tuple(sorted((first, second)))].append(poly.index)
    for linked in edge_faces.values():
        for first in linked:
            for second in linked:
                if first != second:
                    adjacency[first].add(second)
    remaining = set(range(len(obj.data.polygons)))
    component_sizes = []
    while remaining:
        seed = remaining.pop()
        queue = deque([seed])
        size = 1
        while queue:
            current = queue.popleft()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    queue.append(neighbor)
                    size += 1
        component_sizes.append(size)
    return sum(value != 2 for value in counts.values()), sorted(component_sizes, reverse=True)


nonmanifold_edges, component_sizes = topology(cowl)
if nonmanifold_edges:
    raise RuntimeError(f"Organic cowl is not manifold: {nonmanifold_edges} edges")
if len(component_sizes) != 1:
    raise RuntimeError(f"Organic cowl did not union to one component: {component_sizes}")

weight_sums = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights not normalized: {min(weight_sums)}..{max(weight_sums)}")

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Candidate outside triangle target: {total_triangles}")

points = [cowl.matrix_world @ vertex.co for vertex in cowl.data.vertices]
cowl_bounds = {
    "min": [min(point[axis] for point in points) for axis in range(3)],
    "max": [max(point[axis] for point in points) for axis in range(3)],
}


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True
        obj.hide_set(True)

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=76, resolution=(1200, 1000)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16u_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


preview_paths = {}
preview_paths["top_close"] = render(
    "top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900)
)
preview_paths["user_high_three_quarter"] = render(
    "user_high_three_quarter", (0.577, -0.577, 5.578), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000)
)
preview_paths["front"] = render(
    "front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06, resolution=(1200, 1200)
)
preview_paths["back"] = render(
    "back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06, resolution=(1200, 1200)
)
preview_paths["three_quarter"] = render(
    "three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72, resolution=(1200, 1200)
)
preview_paths["cowl_close"] = render(
    "cowl_close", (0.72, -1.20, 2.05), (0.0, 0.0, 1.50), lens=84, resolution=(1200, 1000)
)

# Save only the isolated candidate.  The canonical v15 and production assets
# remain untouched.
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

summary = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "removed_objects": list(REMOVE_NAMES),
    "new_cowl": cowl.name,
    "new_cowl_vertices": len(cowl.data.vertices),
    "new_cowl_triangles": triangle_count(cowl),
    "new_cowl_components": component_sizes,
    "new_cowl_nonmanifold_edges": nonmanifold_edges,
    "new_cowl_bounds": cowl_bounds,
    "new_cowl_materials": [material.name for material in cowl.data.materials],
    "new_cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "head_polygons_reclassified_as_hair": len(hair_polygons),
    "character_meshes": len(character_meshes),
    "total_triangles": total_triangles,
    "triangle_breakdown": {obj.name: triangle_count(obj) for obj in character_meshes},
    "previews": preview_paths,
    "production_modified": False,
}
REPORT.write_text(json.dumps(summary, indent=2), encoding="utf-8")

print("V16U_SUMMARY", json.dumps(summary))
print("WROTE", OUTPUT)
