"""Build the isolated V16ZO realistic one-piece medieval wool cowl candidate.

The cowl is one closed, thin manifold cloth volume with one neck opening.  Its
folds are shallow, angle-localised deformations in the same surface, avoiding
stacked rings, floating plates, sharp bib points, and visible seams.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zm_clean_rear_shoulders.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zo_realistic_singlepiece_cowl.blend"
REPORT = STAGING / "v16zo_realistic_singlepiece_cowl_report.json"

OLD_COWL = "Mercenary_SculptedLowerDrapeCowl_v16zl_LOD0"
NEW_COWL = "Mercenary_RealisticSinglePieceCowl_v16zo_LOD0"
ANGLE_SEGMENTS = 192
VERTICAL_SEGMENTS = 48
ROWS = VERTICAL_SEGMENTS + 1


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angle_delta(angle: float, center: float) -> float:
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle: float, center: float, width: float) -> float:
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def gaussian(value: float, center: float, width: float) -> float:
    return math.exp(-((value - center) / width) ** 2)


def fold_profile(u: float, center: float, width: float) -> float:
    """A broad cloth roll with a shallow compressed valley below it."""
    return gaussian(u, center, width) - 0.44 * gaussian(u, center + 0.072, width * 0.78)


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
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
            current = queue.popleft()
            found = adjacency[current] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def cowl_point(theta: float, u: float, inner: bool = False) -> tuple[float, float, float]:
    """Sample one surface of a softly draped, non-concentric scarf cowl."""
    cosine = math.cos(theta)
    sine = math.sin(theta)
    side = abs(cosine)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    left = max(0.0, -cosine)
    right = max(0.0, cosine)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # A close, irregular neckline opens gradually into the clavicle and upper
    # back.  The rear has more cloth and hangs farther out than the front.
    top_rx = (
        0.123
        + 0.0065 * math.sin(theta + 0.55)
        + 0.0040 * math.sin(2.0 * theta - 0.35)
        + 0.0020 * math.sin(5.0 * theta + 0.2)
    )
    top_ry = (
        0.093
        + 0.0060 * math.sin(theta - 0.15)
        + 0.0040 * math.sin(3.0 * theta + 0.5)
    )
    bottom_rx = (
        0.240
        + 0.026 * back
        + 0.012 * left
        - 0.007 * front
        + 0.012 * localized(theta, -0.90, 0.62)
        - 0.007 * localized(theta, -2.45, 0.68)
    )
    bottom_ry = 0.150 + 0.070 * back - 0.009 * front + 0.006 * right
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # Fullness gathers just above the hem, then tucks back toward the garment.
    # This removes the straight lampshade profile of a simple cone.
    skirt_billow = gaussian(u, 0.72, 0.23) * (
        0.017
        + 0.007 * math.sin(theta + 0.85)
        + 0.004 * math.sin(3.0 * theta - 0.3)
        + 0.006 * localized(theta, 1.25, 1.25)
    )
    rx += skirt_billow
    ry += 0.82 * skirt_billow

    # Three shallow, wandering fold ridges.  Each dominates a different arc,
    # so none forms a complete concentric ring or rubber-tube band.
    path_upper = (
        0.205
        + 0.108 * math.sin(theta + 0.55)
        + 0.038 * math.sin(2.0 * theta - 0.4)
    )
    path_middle = (
        0.465
        + 0.148 * math.sin(theta - 1.00)
        - 0.048 * math.sin(3.0 * theta + 0.25)
    )
    path_lower = (
        0.725
        + 0.118 * math.sin(theta + 1.65)
        + 0.042 * math.sin(2.0 * theta - 0.8)
        - 0.205 * localized(theta, 1.40, 0.72)
    )
    upper_envelope = 0.12 + 0.88 * localized(theta, -0.35, 1.08)
    middle_envelope = 0.10 + 0.90 * localized(theta, -1.75, 1.10)
    lower_envelope = min(
        1.0,
        0.08
        + 0.68 * localized(theta, 1.18, 1.08)
        + 0.54 * localized(theta, -2.18, 0.78),
    )
    fold_upper = fold_profile(u, path_upper, 0.075) * upper_envelope
    fold_middle = fold_profile(u, path_middle, 0.088) * middle_envelope
    fold_lower = fold_profile(u, path_lower, 0.092) * lower_envelope
    relief = 0.0220 * fold_upper + 0.0300 * fold_middle + 0.0270 * fold_lower

    # The front-right wrap is slightly bunched and crosses diagonally; the
    # opposite side relaxes inward.  Fine harmonics break CAD-like symmetry.
    relief += (
        0.0240
        * localized(theta, -0.62, 0.38)
        * gaussian(u, 0.52 + 0.06 * math.sin(theta + 0.4), 0.19)
    )
    relief -= 0.0055 * localized(theta, -2.45, 0.46) * gaussian(u, 0.58, 0.24)
    relief += middle ** 1.35 * (
        0.0035 * math.sin(3.0 * theta + 2.8 * u)
        + 0.0020 * math.sin(7.0 * theta - 3.1 * u)
    )

    # Keep the cloth genuinely thin: inner and outer surfaces share every
    # fold, separated only by a 6.5-8.5 mm wool thickness.
    thickness = 0.0072 + 0.0008 * math.sin(2.0 * theta + 1.4 * u) + 0.0005 * middle
    surface_rx = rx + relief
    surface_ry = ry + 0.82 * relief
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.92

    # A subtle tangential drift makes the folds look wrapped rather than
    # extruded directly out from the neck.
    tangential = middle ** 1.45 * (
        0.0070 * math.sin(theta + 2.2 * u - 0.3)
        + 0.0030 * math.sin(3.0 * theta - 1.5 * u)
    )
    center_x = -0.006 * eased + 0.003 * middle * math.sin(2.0 * theta)
    center_y = 0.008 + 0.016 * eased
    x = center_x + surface_rx * cosine - tangential * sine
    y = center_y + surface_ry * sine + tangential * cosine

    # Low-frequency edge variation creates a relaxed hem.  The front stays a
    # shallow curve (never a shield point); the rear falls onto the upper back.
    top_z = (
        1.596
        + 0.010 * math.sin(theta + 0.35)
        + 0.005 * math.sin(3.0 * theta - 0.2)
        + 0.007 * back
        - 0.004 * front
    )
    bottom_z = (
        1.414
        - 0.068 * back ** 1.45
        - 0.008 * front
        - 0.003 * side
        + 0.015 * math.sin(theta - 0.25)
        + 0.008 * math.sin(2.0 * theta + 0.55)
        + 0.004 * left
        - 0.021 * localized(theta, -0.92, 0.62)
        + 0.013 * localized(theta, -2.42, 0.58)
        - 0.011 * localized(theta, 2.20, 0.68)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += middle ** 1.30 * (
        0.0065 * math.sin(theta - 0.50)
        + 0.0035 * math.sin(3.0 * theta + 2.0 * u)
    )
    z -= 0.009 * back * middle ** 1.7
    # Fold crests meander slightly in height, but remain soft cloth creases.
    z += 0.0035 * fold_upper - 0.0020 * fold_middle + 0.0025 * fold_lower
    if inner:
        z -= 0.0008 * middle
    return x, y, z


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
old_cowl = bpy.data.objects[OLD_COWL]
asset_collection = old_cowl.users_collection[0]
base_material = old_cowl.data.materials[0]
old_triangles = triangle_count(old_cowl)
old_mesh = old_cowl.data
bpy.data.objects.remove(old_cowl, do_unlink=True)
if old_mesh.users == 0:
    bpy.data.meshes.remove(old_mesh)


def index(surface: int, vertical_index: int, angular_index: int) -> int:
    return (
        surface * ROWS * ANGLE_SEGMENTS
        + vertical_index * ANGLE_SEGMENTS
        + angular_index
    )


vertices = []
parameters = []
for surface in (0, 1):
    for vertical_index in range(ROWS):
        u = vertical_index / VERTICAL_SEGMENTS
        for angular_index in range(ANGLE_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGLE_SEGMENTS
            vertices.append(cowl_point(theta, u, inner=bool(surface)))
            parameters.append((surface, vertical_index, angular_index, u, theta))

faces = []
for vertical_index in range(VERTICAL_SEGMENTS):
    for angular_index in range(ANGLE_SEGMENTS):
        nxt = (angular_index + 1) % ANGLE_SEGMENTS
        faces.append((
            index(0, vertical_index, angular_index),
            index(0, vertical_index + 1, angular_index),
            index(0, vertical_index + 1, nxt),
            index(0, vertical_index, nxt),
        ))
        faces.append((
            index(1, vertical_index, nxt),
            index(1, vertical_index + 1, nxt),
            index(1, vertical_index + 1, angular_index),
            index(1, vertical_index, angular_index),
        ))

for angular_index in range(ANGLE_SEGMENTS):
    nxt = (angular_index + 1) % ANGLE_SEGMENTS
    # Thin closed lip around the sole neck opening.
    faces.append((
        index(0, 0, angular_index),
        index(0, 0, nxt),
        index(1, 0, nxt),
        index(1, 0, angular_index),
    ))
    # Smooth closed lower hem; no open underside or dark slit.
    faces.append((
        index(0, VERTICAL_SEGMENTS, nxt),
        index(0, VERTICAL_SEGMENTS, angular_index),
        index(1, VERTICAL_SEGMENTS, angular_index),
        index(1, VERTICAL_SEGMENTS, nxt),
    ))

mesh = bpy.data.meshes.new("Mercenary_RealisticSinglePieceCowl_v16zo_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()

cowl = bpy.data.objects.new(NEW_COWL, mesh)
asset_collection.objects.link(cowl)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16ZO one-piece asymmetric medieval wool scarf cowl"
cowl["topology"] = "single closed thin manifold shell with one neck opening"

material = base_material.copy()
material.name = "MAT_v16zo_RealisticCharcoalWool_4K"
material.use_backface_culling = False
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Seam-aware tiled UVs preserve the scale of the established 4K wool maps.
uv_layer = mesh.uv_layers.new(name="UVMap")
surface_size = ROWS * ANGLE_SEGMENTS
for polygon in mesh.polygons:
    angular_indices = []
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % surface_size
        angular_indices.append(within % ANGLE_SEGMENTS)
    crosses_seam = 0 in angular_indices and (ANGLE_SEGMENTS - 1) in angular_indices
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % surface_size
        vertical_index = within // ANGLE_SEGMENTS
        angular_index = within % ANGLE_SEGMENTS
        texture_u = angular_index / ANGLE_SEGMENTS * 4.0
        if crosses_seam and angular_index == 0:
            texture_u = 4.0
        texture_v = vertical_index / VERTICAL_SEGMENTS * 2.25
        uv_layer.data[loop_index].uv = (texture_u, texture_v)

# Normalized Rigify deformation: torso-led with a gentle outer-hem shoulder
# blend.  This avoids rigid shoulder clipping without dragging the whole cowl.
group_names = (
    "DEF-spine.004",
    "DEF-spine.005",
    "DEF-spine.006",
    "DEF-upper_arm.L",
    "DEF-upper_arm.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
weight_sums = []
max_arm_weight = 0.0
for vertex, (_surface, _vertical_index, _angular_index, u, _theta) in zip(mesh.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.205) / 0.075)
    lower_gate = smoothstep((u - 0.62) / 0.38)
    arm_weight = 0.15 * side_gate * lower_gate
    max_arm_weight = max(max_arm_weight, arm_weight)
    torso = 1.0 - arm_weight
    upper_factor = 1.0 - smoothstep((u - 0.16) / 0.52)
    lower_factor = smoothstep((u - 0.56) / 0.44)
    w006 = torso * (0.18 + 0.58 * upper_factor)
    remaining = torso - w006
    w004 = remaining * (0.34 + 0.46 * lower_factor)
    w005 = remaining - w004
    groups["DEF-spine.004"].add([vertex.index], w004, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], w005, "REPLACE")
    groups["DEF-spine.006"].add([vertex.index], w006, "REPLACE")
    if arm_weight > 0.0:
        arm_group = "DEF-upper_arm.L" if vertex.co.x >= 0.0 else "DEF-upper_arm.R"
        groups[arm_group].add([vertex.index], arm_weight, "REPLACE")
    weight_sums.append(w004 + w005 + w006 + arm_weight)

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()

# QA before rendering.
topology = topology_stats(cowl)
if topology["components"] != 1 or topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZO topology failed: {topology}")
if min(weight_sums) < 0.999999 or max(weight_sums) > 1.000001:
    raise RuntimeError(f"V16ZO weight normalization failed: {min(weight_sums)}..{max(weight_sums)}")
if not any(mod.type == "ARMATURE" and mod.object == rig for mod in cowl.modifiers):
    raise RuntimeError("V16ZO Rigify armature modifier missing")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        background.inputs[1].default_value = 0.14

# Temporary soft studio fills make the fold relief readable in the QA renders.
qa_lights = []
for name, location, energy, size, color in (
    ("V16ZO_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZO_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZO_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    light_data = bpy.data.lights.new(name + "_Data", "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    qa_lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zo_realistic_cowl_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.48), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

# QA lights are not part of the game asset.
for light in qa_lights:
    light_data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if light_data.users == 0:
        bpy.data.lights.remove(light_data)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"V16ZO triangle budget failed: {total_triangles}")

texture_images = {}
if material.use_nodes:
    for node in material.node_tree.nodes:
        if node.type == "TEX_IMAGE" and node.image:
            texture_images[node.image.name] = list(node.image.size)

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "construction": "single thin closed manifold scarf shell with one neck opening and three localized soft folds",
    "replaced_cowl_triangles": old_triangles,
    "cowl_triangles": triangle_count(cowl),
    "cowl_vertices": len(cowl.data.vertices),
    "topology": topology,
    "weight_sum_range": [min(weight_sums), max(weight_sums)],
    "max_upper_arm_weight": max_arm_weight,
    "rigify_modifier": True,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "material": material.name,
    "texture_images": texture_images,
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "cowl_bounds": {
        "min": [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    "previews": previews,
}
cowl["v16zo_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZO_REPORT=" + json.dumps(report, sort_keys=True))
