"""Build an isolated V16FINALA natural medieval scarf/cowl candidate.

The current v16zz upper garment is topologically sound but its tall, nearly
vertical annular wall reads as a rigid cylinder.  This candidate preserves
every existing donor-outfit face, tucks only its inherited open neckline under
the scarf, replaces the generated cowl accessory, and gently re-contours the
already separate gambeson sleeve covers without deleting any of their faces.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zz_tucked_upper_no_deletion.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16finala_natural_draped_scarf_candidate.blend"
REPORT = STAGING / "v16finala_natural_draped_scarf_report.json"

OLD_COWL = "Mercenary_SoftIrregularWoolCowl_v16zx_LOD0"
NEW_COWL = "Mercenary_NaturalDrapedScarf_v16finala_LOD0"
SLEEVES_NAME = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def gaussian(value: float, center: float, width: float) -> float:
    return math.exp(-((value - center) / width) ** 2)


def angle_delta(angle: float, center: float) -> float:
    return (angle - center + math.pi) % math.tau - math.pi


def localized(angle: float, center: float, width: float) -> float:
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def triangles(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def mesh_topology(obj: bpy.types.Object) -> dict:
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)

    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            neighbours = adjacency[queue.popleft()] & unseen
            unseen.difference_update(neighbours)
            queue.extend(neighbours)

    zero_area = sum(poly.area <= 1.0e-12 for poly in obj.data.polygons)
    loose = sum(not adjacency[index] for index in range(len(obj.data.vertices)))
    return {
        "components": components,
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "zero_area_faces": zero_area,
        "loose_vertices": loose,
    }
def bounds(obj: bpy.types.Object) -> dict:
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "x": [min(point.x for point in points), max(point.x for point in points)],
        "y": [min(point.y for point in points), max(point.y for point in points)],
        "z": [min(point.z for point in points), max(point.z for point in points)],
    }


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
sleeves = bpy.data.objects[SLEEVES_NAME]
asset_collection = donor.users_collection[0]

donor_before = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangles(donor),
}

# The inherited donor has one large open upper boundary from an earlier scan
# reconstruction.  Preserve every face, but tuck that boundary and three soft
# neighbour rings inside the new scarf so it cannot appear as black teeth or
# hanging fins.  Counts and topology remain unchanged.
donor_edge_count = defaultdict(int)
donor_adjacency = defaultdict(set)
for poly in donor.data.polygons:
    ids = list(poly.vertices)
    for a, b in zip(ids, ids[1:] + ids[:1]):
        donor_edge_count[tuple(sorted((a, b)))] += 1
        donor_adjacency[a].add(b)
        donor_adjacency[b].add(a)
boundary_adjacency = defaultdict(set)
for (a, b), count in donor_edge_count.items():
    if count == 1:
        boundary_adjacency[a].add(b)
        boundary_adjacency[b].add(a)

remaining = set(boundary_adjacency)
boundary_components = []
while remaining:
    seed = remaining.pop()
    component = {seed}
    queue = deque([seed])
    while queue:
        current = queue.popleft()
        for neighbour in boundary_adjacency[current]:
            if neighbour in remaining:
                remaining.remove(neighbour)
                component.add(neighbour)
                queue.append(neighbour)
    boundary_components.append(component)

main_upper_boundary = max(
    (
        component
        for component in boundary_components
        if max(donor.data.vertices[index].co.z for index in component) > 1.35
        and max(abs(donor.data.vertices[index].co.x) for index in component) < 0.30
    ),
    key=len,
)
distance = {index: 0 for index in main_upper_boundary}
queue = deque(main_upper_boundary)
while queue:
    current = queue.popleft()
    if distance[current] >= 3:
        continue
    for neighbour in donor_adjacency[current]:
        if neighbour not in distance:
            distance[neighbour] = distance[current] + 1
            queue.append(neighbour)

tucked_donor_vertices = 0
for index, ring in distance.items():
    co = donor.data.vertices[index].co
    if abs(co.x) > 0.30 or co.z < 1.18:
        continue
    influence = ((4.0 - ring) / 4.0) ** 2
    target_x = clamp(co.x, -0.172, 0.172)
    target_y = clamp(co.y, -0.052, 0.145)
    target_z = 1.371 + 0.009 * smoothstep(abs(target_x) / 0.172)
    co.x = co.x * (1.0 - influence) + target_x * influence
    co.y = co.y * (1.0 - influence) + target_y * influence
    co.z = co.z * (1.0 - influence) + target_z * influence
    tucked_donor_vertices += 1
donor.data.update()
donor["v16finala_tucked_boundary_without_face_deletion"] = tucked_donor_vertices

# Replace only the generated v16zz scarf accessory.  No textured donor-body
# face (coat, gambeson, arms, or shoulders) is deleted.
old_cowl = bpy.data.objects.get(OLD_COWL)
if old_cowl is None:
    raise RuntimeError(f"Missing source cowl: {OLD_COWL}")
old_cowl_triangles = triangles(old_cowl)
old_cowl_data = old_cowl.data
bpy.data.objects.remove(old_cowl, do_unlink=True)
if old_cowl_data.users == 0:
    bpy.data.meshes.remove(old_cowl_data)

# Re-contour the separate clean sleeve shells.  Their topology and weights are
# retained exactly, but the circular log-like section is reduced and tapered.
AXIAL = 33
RING = 32
VERTS_PER_SIDE = AXIAL * RING + 2
if len(sleeves.data.vertices) != 2 * VERTS_PER_SIDE:
    raise RuntimeError(f"Unexpected sleeve layout: {len(sleeves.data.vertices)} vertices")

for side_index, sign in enumerate((-1.0, 1.0)):
    start = side_index * VERTS_PER_SIDE
    for axial in range(AXIAL):
        t = axial / (AXIAL - 1)
        x_abs = 0.105 + 0.450 * t
        bulge = math.sin(math.pi * t) ** 0.82
        center_y = 0.024 + 0.009 * t
        center_z = 1.427 - 0.025 * t + 0.0025 * math.sin(math.pi * t)
        radius_y = 0.059 + 0.009 * bulge - 0.006 * t
        radius_z = 0.055 + 0.009 * bulge - 0.007 * t
        for ring in range(RING):
            phi = math.tau * ring / RING
            cp = math.cos(phi)
            sp = math.sin(phi)
            # Subtle quilting, deliberately far below the old cushion scale.
            quilt = (
                1.0
                + 0.012 * math.sin(6.0 * math.pi * t + 2.0 * phi) * bulge
                + 0.006 * math.sin(3.0 * phi - 2.5 * t) * bulge
            )
            index = start + axial * RING + ring
            sleeves.data.vertices[index].co = (
                sign * x_abs,
                center_y + radius_y * quilt * cp,
                center_z + radius_z * quilt * sp + 0.003 * max(0.0, sp) ** 2,
            )
    sleeves.data.vertices[start + AXIAL * RING].co = (sign * 0.105, 0.024, 1.423)
    sleeves.data.vertices[start + AXIAL * RING + 1].co = (sign * 0.555, 0.033, 1.402)
sleeves.data.update()
sleeves["v16finala_recontoured_without_face_deletion"] = True

# One continuous closed cloth shell.  It is intentionally low at the chin,
# higher at the nape, and slopes outward/down toward the clavicles.  Two local
# wandering relief folds are embedded in the same surface; no torus, rolled
# collar object, shoulder plate, or separate floating patch is created.
ANGULAR = 176
ROWS = 30
vertices = []
faces = []


def scarf_point(theta: float, u: float, inner: bool) -> tuple[float, float, float]:
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # Snug neckline to compact drape.  The 0.38 m maximum width is deliberately
    # far inside the shoulders, avoiding both a capelet plate and a broad donut.
    top_rx = 0.115 + 0.0035 * math.sin(theta + 0.55) + 0.0018 * math.sin(3.0 * theta)
    top_ry = 0.086 + 0.0032 * math.sin(theta - 0.30) + 0.0017 * math.sin(2.0 * theta)
    hem_rx = 0.177 + 0.008 * back + 0.003 * left - 0.002 * front
    hem_ry = 0.132 + 0.012 * front + 0.022 * back + 0.003 * right
    rx = top_rx * (1.0 - eased) + hem_rx * eased
    ry = top_ry * (1.0 - eased) + hem_ry * eased

    # Soft overall cloth fullness, strongest below the collarbone transition.
    fullness = gaussian(u, 0.58, 0.30) * (
        0.0070 + 0.0022 * math.sin(theta + 0.5) + 0.0012 * math.sin(3.0 * theta - 0.2)
    )

    # Two partial diagonal folds.  Both vanish outside their cloth arcs, so
    # neither can read as a concentric ring when seen from above.
    path_a = 0.32 + 0.115 * math.sin(theta + 0.48) + 0.020 * math.sin(2.0 * theta)
    path_b = 0.69 + 0.100 * math.sin(theta - 1.05) - 0.018 * math.sin(3.0 * theta)
    envelope_a = min(
        1.0,
        0.88 * localized(theta, -1.15, 0.92) + 0.28 * localized(theta, 2.30, 0.60),
    )
    envelope_b = min(
        1.0,
        0.82 * localized(theta, -2.20, 0.88) + 0.38 * localized(theta, 0.55, 0.62),
    )
    fold_a = gaussian(u, path_a, 0.080) - 0.30 * gaussian(u, path_a + 0.075, 0.052)
    fold_b = gaussian(u, path_b, 0.090) - 0.28 * gaussian(u, path_b + 0.082, 0.058)
    relief = 0.0105 * envelope_a * fold_a + 0.0090 * envelope_b * fold_b
    relief += middle ** 1.5 * (
        0.0018 * math.sin(4.0 * theta + 3.8 * u)
        + 0.0010 * math.sin(8.0 * theta - 2.5 * u)
    )

    # Tuck the hem slightly inward so the lower edge disappears into the coat.
    hem_tuck = smoothstep((u - 0.84) / 0.16)
    rx += fullness + relief - 0.005 * hem_tuck
    ry += 0.84 * (fullness + relief) - 0.004 * hem_tuck

    top_z = (
        1.527
        + 0.032 * back
        - 0.017 * front
        + 0.003 * side
        + 0.004 * math.sin(theta + 0.35)
        + 0.002 * math.sin(3.0 * theta - 0.20)
    )
    hem_z = (
        1.413
        - 0.017 * front ** 2
        + 0.004 * side
        + 0.003 * back
        - 0.005 * localized(theta, -2.25, 0.75)
        + 0.003 * math.sin(2.0 * theta + 0.30)
    )
    z = top_z * (1.0 - eased) + hem_z * eased
    z += middle ** 1.4 * (
        0.0040 * math.sin(theta + 0.4)
        + 0.0020 * math.sin(3.0 * theta - 2.8 * u)
    )
    z += 0.0028 * envelope_a * fold_a - 0.0020 * envelope_b * fold_b

    # Mild tangential shear stops the front and back hems becoming symmetric.
    tangent = middle ** 1.5 * (
        0.0035 * math.sin(theta + 1.8 * u) + 0.0015 * math.sin(3.0 * theta - u)
    )
    center_x = -0.003 - 0.004 * eased
    center_y = 0.014 + 0.008 * eased

    thickness = 0.0068 + 0.0005 * math.sin(2.0 * theta + 1.1 * u)
    if inner:
        # The lining stays near the neck instead of following the outer hem.
        # This hides the inherited scan opening without adding a separate disk.
        inner_hem_rx = 0.116 + 0.005 * side + 0.003 * back
        inner_hem_ry = 0.091 + 0.006 * front + 0.008 * back
        rx = (top_rx - thickness) * (1.0 - eased) + inner_hem_rx * eased
        ry = (top_ry - 0.90 * thickness) * (1.0 - eased) + inner_hem_ry * eased
        rx += 0.22 * fullness + 0.26 * relief
        ry += 0.18 * fullness + 0.22 * relief
        tangent *= 0.35
        z -= 0.0007 * middle

    x = center_x + rx * c - tangent * s
    y = center_y + ry * s + tangent * c
    return (x, y, z)


surface_size = ANGULAR * ROWS
for inner in (False, True):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for angular in range(ANGULAR):
            theta = math.tau * angular / ANGULAR
            vertices.append(scarf_point(theta, u, inner))

for row in range(ROWS - 1):
    for angular in range(ANGULAR):
        nxt = (angular + 1) % ANGULAR
        a = row * ANGULAR + angular
        b = (row + 1) * ANGULAR + angular
        c = (row + 1) * ANGULAR + nxt
        d = row * ANGULAR + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

bottom = (ROWS - 1) * ANGULAR
for angular in range(ANGULAR):
    nxt = (angular + 1) % ANGULAR
    # Narrow top and bottom edge strips close the volume without any cap disk.
    faces.append((angular, nxt, surface_size + nxt, surface_size + angular))
    faces.append((
        bottom + angular,
        surface_size + bottom + angular,
        surface_size + bottom + nxt,
        bottom + nxt,
    ))

mesh = bpy.data.meshes.new("Mercenary_NaturalDrapedScarf_v16finala_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new(NEW_COWL, mesh)
asset_collection.objects.link(cowl)
for poly in mesh.polygons:
    poly.use_smooth = True

source_material = bpy.data.materials.get("MAT_v16zx_SoftCharcoalWool_4K")
if source_material is None:
    source_material = bpy.data.materials.get("MAT_CowlWool_Side_PBR_4K")
if source_material is None:
    raise RuntimeError("No suitable 4K cowl wool material found")
material = source_material.copy()
material.name = "MAT_v16finala_NaturalCharcoalWool_PBR_4K"
mesh.materials.append(material)

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.08, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

# Normalized Rigify deformation: mostly chest/neck, with restrained shoulder
# and upper-arm influence only at the compact side hem.
group_names = (
    "DEF-spine.004",
    "DEF-spine.005",
    "DEF-shoulder.L",
    "DEF-shoulder.R",
    "DEF-upper_arm.L",
    "DEF-upper_arm.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    side = smoothstep((abs(x) - 0.170) / 0.070)
    upper = smoothstep((z - 1.420) / 0.135)
    shoulder = 0.20 * side * (1.0 - 0.35 * upper)
    arm = 0.055 * side * (1.0 - 0.70 * upper)
    neck = 0.58 + 0.24 * upper
    chest = max(0.0, 1.0 - neck - shoulder - arm)
    weights = {
        "DEF-spine.004": chest,
        "DEF-spine.005": neck,
        "DEF-shoulder.L": shoulder if x >= 0.0 else 0.0,
        "DEF-shoulder.R": shoulder if x < 0.0 else 0.0,
        "DEF-upper_arm.L": arm if x >= 0.0 else 0.0,
        "DEF-upper_arm.R": arm if x < 0.0 else 0.0,
    }
    total = sum(weights.values())
    for name, weight in weights.items():
        if weight > 0.0:
            groups[name].add([vertex.index], weight / total, "REPLACE")

modifier = cowl.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_vertex_groups = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16FINALA single closed low draped medieval scarf"
cowl["separate_rings"] = 0
cowl["floating_panels"] = 0

# Diagnostics and hard validation.
cowl_topology = mesh_topology(cowl)
sleeve_topology = mesh_topology(sleeves)
cowl_weights = [sum(item.weight for item in vertex.groups) for vertex in cowl.data.vertices]
sleeve_weights = [sum(item.weight for item in vertex.groups) for vertex in sleeves.data.vertices]

for obj, stats, expected_components, sums in (
    (cowl, cowl_topology, 1, cowl_weights),
    (sleeves, sleeve_topology, 2, sleeve_weights),
):
    if stats["components"] != expected_components:
        raise RuntimeError(f"Unexpected components on {obj.name}: {stats}")
    if stats["nonmanifold_edges"] or stats["zero_area_faces"] or stats["loose_vertices"]:
        raise RuntimeError(f"Topology failure on {obj.name}: {stats}")
    if min(sums) < 0.999 or max(sums) > 1.001:
        raise RuntimeError(f"Weight normalization failure on {obj.name}: {min(sums)}..{max(sums)}")
    if not any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers):
        raise RuntimeError(f"Missing Rigify armature modifier on {obj.name}")

donor_after = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangles(donor),
}
if donor_after != donor_before:
    raise RuntimeError(f"Donor outfit topology changed: {donor_before} -> {donor_after}")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.045, 0.050, 0.060, 1.0)
        background.inputs[1].default_value = 0.22

lights = []
for name, location, energy, size, color in (
    ("V16FINALA_QA_Key", (-2.1, -2.7, 3.2), 82.0, 2.5, (1.0, 0.83, 0.70)),
    ("V16FINALA_QA_Fill", (2.4, -1.6, 2.5), 45.0, 2.2, (0.64, 0.77, 1.0)),
    ("V16FINALA_QA_Rim", (0.2, 2.5, 2.8), 58.0, 2.0, (0.73, 0.84, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("V16FINALA_DiagnosticCamera")
    camera = bpy.data.objects.new("V16FINALA_DiagnosticCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
camera.data.type = "PERSP"
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key: str, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16finala_natural_scarf_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "three_quarter": render("three_quarter", (0.78, -1.60, 1.80), (0.0, 0.01, 1.40), 88),
    "high": render("high", (0.70, -0.90, 2.10), (0.0, 0.02, 1.46), 88),
    "top": render("top", (0.0, 0.00, 2.62), (0.0, 0.02, 1.49), 88),
}

for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Rigify deform bone count changed: {deform_bones}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "donor_outfit_topology_unchanged": donor_before == donor_after,
    "donor_faces_deleted": 0,
    "donor_boundary_vertices_tucked": tucked_donor_vertices,
    "donor_before": donor_before,
    "donor_after": donor_after,
    "replaced_generated_cowl": OLD_COWL,
    "replaced_cowl_triangles": old_cowl_triangles,
    "new_cowl": cowl.name,
    "construction": "single compact closed draped cloth shell; two integrated local folds; no rings or floating panels",
    "cowl_bounds": bounds(cowl),
    "cowl_triangles": triangles(cowl),
    "cowl_topology": cowl_topology,
    "cowl_weight_sum_range": [min(cowl_weights), max(cowl_weights)],
    "cowl_has_rigify_modifier": any(
        mod.type == "ARMATURE" and mod.object == rig for mod in cowl.modifiers
    ),
    "sleeves_recontoured_without_face_deletion": True,
    "sleeve_triangles": triangles(sleeves),
    "sleeve_topology": sleeve_topology,
    "sleeve_weight_sum_range": [min(sleeve_weights), max(sleeve_weights)],
    "sleeves_have_rigify_modifier": any(
        mod.type == "ARMATURE" and mod.object == rig for mod in sleeves.modifiers
    ),
    "deform_bones": deform_bones,
    "character_meshes": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16finala_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16FINALA_REPORT=" + json.dumps(report, sort_keys=True))
