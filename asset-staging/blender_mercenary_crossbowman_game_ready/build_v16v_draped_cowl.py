"""Build a single draped annular cowl with sculpted, nonconcentric folds.

Unlike the rejected tube-union candidate, this is one continuous cloth band:
the visible folds are height variation in one surface rather than stacked torus
objects.  It writes only a versioned staging candidate.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16v_draped_cowl.blend"
REPORT = STAGING / "build_summary_v16v_draped_cowl.json"

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
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


angular_segments = 224
radial_segments = 24
vertices = []
parameters = []


def surface_coordinate(angle_index, radial_index, lower):
    theta = math.tau * angle_index / angular_segments
    radial_t = radial_index / radial_segments  # 0 outer, 1 inner
    sine = math.sin(theta)
    cosine = math.cos(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)

    # Both rims are irregular and use different phases; intermediate curves
    # therefore cannot form a perfect concentric annulus.
    outer_rx = 0.273 * (
        1.0 + 0.044 * math.sin(3.0 * theta + 0.55) + 0.021 * math.sin(7.0 * theta - 0.30)
    )
    outer_ry = 0.213 * (
        1.0 + 0.052 * math.sin(4.0 * theta - 0.70) + 0.018 * math.sin(9.0 * theta + 0.20)
    )
    inner_rx = 0.108 * (1.0 + 0.050 * math.sin(3.0 * theta + 1.40))
    inner_ry = 0.090 * (1.0 + 0.060 * math.sin(5.0 * theta - 0.30))
    eased = radial_t * radial_t * (3.0 - 2.0 * radial_t)
    rx = outer_rx * (1.0 - eased) + inner_rx * eased
    ry = outer_ry * (1.0 - eased) + inner_ry * eased
    center_x = 0.008 * math.sin(theta + 0.8) * radial_t + 0.004 * math.sin(4.0 * theta)
    center_y = 0.027 - 0.010 * radial_t + 0.006 * math.sin(2.0 * theta + 0.4)
    x = center_x + rx * cosine
    y = center_y + ry * sine

    outer_z = (
        1.425
        + 0.044 * back ** 1.45
        - 0.018 * front ** 1.3
        + 0.007 * math.sin(2.0 * theta + 0.1)
    )
    inner_z = (
        1.528
        + 0.074 * back ** 1.35
        - 0.012 * front
        + 0.009 * math.sin(theta + 1.0)
        + 0.005 * math.sin(4.0 * theta - 0.2)
    )
    base_z = outer_z * (1.0 - eased) + inner_z * eased

    # Radial folds travel diagonally and vary by angle.  They are deformations
    # of this one surface, not stacked circular tubes.
    edge_fade = math.sin(math.pi * radial_t) ** 0.65
    phase_warp = 1.20 * math.sin(theta + 0.25) + 0.48 * math.sin(3.0 * theta - 0.8)
    broad_fold = (
        0.0145
        * edge_fade
        * (0.75 + 0.45 * front + 0.20 * back)
        * math.sin(math.tau * (2.15 * radial_t) + phase_warp)
    )
    fine_fold = (
        0.0055
        * edge_fade
        * math.sin(math.tau * (5.3 * radial_t) - 1.7 * theta + 0.7 * math.sin(2.0 * theta))
    )
    diagonal_slouch = 0.006 * edge_fade * math.sin(2.0 * theta + 5.0 * radial_t + 1.1)
    top_z = base_z + broad_fold + fine_fold + diagonal_slouch

    thickness = 0.017 + 0.007 * (1.0 - radial_t) + 0.003 * back
    if lower:
        top_z -= thickness
    return Vector((x, y, top_z))


def vertex_index(layer, radial_index, angle_index):
    return (layer * (radial_segments + 1) + radial_index) * angular_segments + angle_index % angular_segments


for layer in (0, 1):
    for radial_index in range(radial_segments + 1):
        for angle_index in range(angular_segments):
            vertices.append(tuple(surface_coordinate(angle_index, radial_index, lower=bool(layer))))
            parameters.append((layer, radial_index, angle_index))

faces = []
face_kinds = []
for angle_index in range(angular_segments):
    following = angle_index + 1
    for radial_index in range(radial_segments):
        faces.append(
            (
                vertex_index(0, radial_index, angle_index),
                vertex_index(0, radial_index, following),
                vertex_index(0, radial_index + 1, following),
                vertex_index(0, radial_index + 1, angle_index),
            )
        )
        face_kinds.append("top")
        faces.append(
            (
                vertex_index(1, radial_index, angle_index),
                vertex_index(1, radial_index + 1, angle_index),
                vertex_index(1, radial_index + 1, following),
                vertex_index(1, radial_index, following),
            )
        )
        face_kinds.append("bottom")
    faces.append(
        (
            vertex_index(0, 0, angle_index),
            vertex_index(1, 0, angle_index),
            vertex_index(1, 0, following),
            vertex_index(0, 0, following),
        )
    )
    face_kinds.append("outer")
    faces.append(
        (
            vertex_index(0, radial_segments, following),
            vertex_index(1, radial_segments, following),
            vertex_index(1, radial_segments, angle_index),
            vertex_index(0, radial_segments, angle_index),
        )
    )
    face_kinds.append("inner")

mesh = bpy.data.meshes.new("Mercenary_DrapedWoolCowl_v16v_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new("Mercenary_DrapedWoolCowl_v16v_LOD0", mesh)
asset_collection.objects.link(cowl)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16V one connected asymmetrical draped scarf surface"
mesh.materials.append(cloth_material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Continuous cloth coordinates with one hidden rear-side seam.
uv = mesh.uv_layers.new(name="UVMap")
for polygon, kind in zip(mesh.polygons, face_kinds):
    angle_values = [parameters[index][2] for index in polygon.vertices]
    seam = min(angle_values) == 0 and max(angle_values) == angular_segments - 1
    for loop_index in polygon.loop_indices:
        vertex = mesh.loops[loop_index].vertex_index
        layer, radial_index, angle_index = parameters[vertex]
        u = angle_index / angular_segments * 5.0
        if seam and angle_index == 0:
            u = 5.0
        radial_t = radial_index / radial_segments
        if kind == "top":
            v = radial_t * 2.6
        elif kind == "bottom":
            v = 3.0 + radial_t * 2.6
        elif kind == "outer":
            v = 6.0 + layer * 0.35
        else:
            v = 6.6 + layer * 0.35
        uv.data[loop_index].uv = (u, v)

# Rigify profile derived from measured donor/cowl boundary weights.
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
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    upper = smoothstep(1.505, 1.555, z)
    outer = smoothstep(0.225, 0.300, abs(x))
    arm_weight = 0.25 * outer * (1.0 - 0.75 * upper)
    remaining = max(0.0, 1.0 - upper - arm_weight)
    mid = smoothstep(1.455, 1.505, z)
    spine004_fraction = (0.40 * (1.0 - mid) + 0.14 * mid) * (1.0 - outer) + 0.88 * outer
    weights = {
        "DEF-spine.004": remaining * spine004_fraction,
        "DEF-spine.005": remaining * (1.0 - spine004_fraction),
        "DEF-spine.006": upper,
        "DEF-upper_arm.L" if x >= 0.0 else "DEF-upper_arm.R": arm_weight,
    }
    total = sum(weights.values())
    for name, weight in weights.items():
        if weight > 1.0e-8:
            groups[name].add([vertex.index], weight / total, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()

# Reclassify the crown consistently and replace projection UVs there.  A later
# dedicated hair shell can replace this provisional scalp treatment cleanly.
hair_material = bpy.data.materials["MAT_ScalpHair_DarkBrown_PBR_2K_v11"]
hair_index = list(head.data.materials).index(hair_material)
head_uv = head.data.uv_layers.get("UVMap")
hair_polygons = []
for polygon in head.data.polygons:
    center = polygon.center
    threshold = (
        1.684
        - 0.032 * smoothstep(-0.015, 0.105, center.y)
        + 0.010 * smoothstep(0.060, 0.100, abs(center.x))
        + 0.006 * math.sin(center.x * 83.0 + center.y * 39.0)
    )
    if center.z < threshold:
        continue
    polygon.material_index = hair_index
    hair_polygons.append(polygon)
    if head_uv:
        for loop_index in polygon.loop_indices:
            co = head.data.vertices[head.data.loops[loop_index].vertex_index].co
            head_uv.data[loop_index].uv = (
                (math.atan2(co.y - 0.005, co.x) / math.tau + 0.5) * 2.0,
                (co.z - 1.625) * 8.0,
            )
head.data.update()


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    edge_faces = defaultdict(list)
    for poly in obj.data.polygons:
        vs = list(poly.vertices)
        for first, second in zip(vs, vs[1:] + vs[:1]):
            edge_faces[tuple(sorted((first, second)))].append(poly.index)
    adjacency = defaultdict(set)
    for linked in edge_faces.values():
        for first in linked:
            for second in linked:
                if first != second:
                    adjacency[first].add(second)
    remaining = set(range(len(obj.data.polygons)))
    components = []
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
        components.append(size)
    return sum(len(linked) != 2 for linked in edge_faces.values()), sorted(components, reverse=True)


nonmanifold_edges, component_sizes = topology(cowl)
if nonmanifold_edges or component_sizes != [len(mesh.polygons)]:
    raise RuntimeError(f"Invalid cowl topology: nonmanifold={nonmanifold_edges}, components={component_sizes}")
weight_sums = [sum(item.weight for item in vertex.groups) for vertex in mesh.vertices]
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Unnormalized weights: {min(weight_sums)}..{max(weight_sums)}")

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle target failed: {total_triangles}")

points = [cowl.matrix_world @ vertex.co for vertex in mesh.vertices]
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
    path = PREVIEWS / f"diagnostic_v16v_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top_close": render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900)),
    "user_high_three_quarter": render("user_high_three_quarter", (0.577, -0.577, 5.578), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000)),
    "front": render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06, resolution=(1200, 1200)),
    "back": render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06, resolution=(1200, 1200)),
    "three_quarter": render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72, resolution=(1200, 1200)),
    "cowl_close": render("cowl_close", (0.72, -1.20, 2.05), (0.0, 0.0, 1.50), lens=84, resolution=(1200, 1000)),
}

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
summary = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "removed_objects": list(REMOVE_NAMES),
    "new_cowl": cowl.name,
    "new_cowl_vertices": len(mesh.vertices),
    "new_cowl_triangles": triangle_count(cowl),
    "new_cowl_components": component_sizes,
    "new_cowl_nonmanifold_edges": nonmanifold_edges,
    "new_cowl_bounds": cowl_bounds,
    "new_cowl_materials": [material.name for material in mesh.materials],
    "new_cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "head_polygons_reclassified_as_hair": len(hair_polygons),
    "total_triangles": total_triangles,
    "triangle_breakdown": {obj.name: triangle_count(obj) for obj in character_meshes},
    "previews": previews,
    "production_modified": False,
}
REPORT.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V16V_SUMMARY", json.dumps(summary))
print("WROTE", OUTPUT)
