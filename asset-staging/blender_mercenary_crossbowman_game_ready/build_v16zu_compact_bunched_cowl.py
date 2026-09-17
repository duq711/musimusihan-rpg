"""Build a compact, vertically bunched one-piece wool cowl candidate.

This replaces the broad capelet-like v16zs shell with one closed vertical
cloth volume.  Three asymmetric folds are sculpted into the same continuous
surface; there are no stacked rings or floating patches.  Torn donor shoulder
fragments hidden by the clean gambeson sleeves are removed as part of the
isolated candidate build.  Production exports are deliberately untouched.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zs_tucked_hem_cowl.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zu_compact_bunched_cowl.blend"
REPORT = STAGING / "v16zu_compact_bunched_cowl_report.json"

OLD_COWL = "Mercenary_TuckedHemWoolCowl_v16zs_LOD0"
NEW_COWL = "Mercenary_CompactBunchedWoolCowl_v16zu_LOD0"
ANGLE_SEGMENTS = 160
VERTICAL_SEGMENTS = 56
ROWS = VERTICAL_SEGMENTS + 1


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def gaussian(value: float, center: float, width: float) -> float:
    return math.exp(-((value - center) / width) ** 2)


def angle_delta(angle: float, center: float) -> float:
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle: float, center: float, width: float) -> float:
    return math.exp(-0.5 * (angle_delta(angle, center) / width) ** 2)


def triangles(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj: bpy.types.Object) -> dict[str, int]:
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
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def fold_profile(u: float, path: float, width: float) -> float:
    """Rounded roll with a shallow compression crease immediately below."""
    return gaussian(u, path, width) - 0.48 * gaussian(u, path + width * 1.12, width * 0.62)


def cowl_point(theta: float, u: float, inner: bool = False) -> tuple[float, float, float]:
    """Sample a compact vertical neck cowl with integrated asymmetric folds."""
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)
    left = max(0.0, -cosine)
    right = max(0.0, cosine)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # The garment stays close to the neck.  Its lower third opens only enough
    # to settle into the clavicle instead of spreading across the shoulders.
    top_rx = 0.137 + 0.004 * math.sin(theta + 0.4) + 0.002 * math.sin(3.0 * theta)
    top_ry = 0.108 + 0.004 * math.sin(theta - 0.2) + 0.002 * math.sin(2.0 * theta)
    bottom_rx = 0.205 + 0.012 * back + 0.005 * left - 0.004 * front
    bottom_ry = 0.145 + 0.018 * back - 0.005 * front + 0.003 * right
    rx = top_rx * (1.0 - eased) + bottom_rx * eased
    ry = top_ry * (1.0 - eased) + bottom_ry * eased

    # Local fullness gives the scarf a gathered fabric profile instead of a
    # cone.  The hem curls back inward so it cannot read as a flat bib shelf.
    fullness = gaussian(u, 0.64, 0.28) * (
        0.012 + 0.0035 * math.sin(theta + 0.8) + 0.0025 * math.sin(3.0 * theta - 0.2)
    )
    hem_tuck = smoothstep((u - 0.80) / 0.20)
    rx += fullness - hem_tuck * (0.012 + 0.004 * front)
    ry += 0.82 * fullness - hem_tuck * (0.009 + 0.003 * side)

    # Three meandering folds belong to this one surface.  Their paths cross
    # different heights around the neck and their strengths vary by quadrant,
    # preventing the concentric rubber-ring look of the old model.
    path_upper = 0.245 + 0.055 * math.sin(theta + 0.35) + 0.018 * math.sin(2.0 * theta - 0.5)
    path_middle = 0.505 + 0.078 * math.sin(theta - 1.05) - 0.022 * math.sin(3.0 * theta + 0.2)
    path_lower = 0.745 + 0.060 * math.sin(theta + 1.45) + 0.020 * math.sin(2.0 * theta + 0.4)

    env_upper = 0.44 + 0.56 * localized(theta, -0.35, 1.35)
    env_middle = 0.38 + 0.62 * localized(theta, -1.55, 1.20)
    env_lower = min(1.0, 0.34 + 0.50 * localized(theta, 1.05, 1.18) + 0.34 * localized(theta, -2.2, 0.85))
    fold_upper = fold_profile(u, path_upper, 0.060) * env_upper
    fold_middle = fold_profile(u, path_middle, 0.067) * env_middle
    fold_lower = fold_profile(u, path_lower, 0.070) * env_lower
    relief = 0.019 * fold_upper + 0.024 * fold_middle + 0.021 * fold_lower

    # A front-left bunch and a quieter opposite quadrant break symmetry while
    # remaining smooth enough for deformation.
    relief += 0.010 * localized(theta, -2.20, 0.42) * gaussian(u, 0.58, 0.17)
    relief -= 0.004 * localized(theta, -0.45, 0.50) * gaussian(u, 0.68, 0.20)
    relief += middle ** 1.35 * (
        0.0023 * math.sin(5.0 * theta + 3.0 * u)
        + 0.0013 * math.sin(9.0 * theta - 2.0 * u)
    )

    thickness = 0.0070 + 0.0007 * math.sin(2.0 * theta + 1.3 * u) + 0.0005 * middle
    surface_rx = rx + relief
    surface_ry = ry + 0.86 * relief
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.90

    tangential = middle ** 1.45 * (
        0.0045 * math.sin(theta + 2.4 * u - 0.4)
        + 0.0020 * math.sin(3.0 * theta - 1.2 * u)
    )
    center_x = -0.003 - 0.004 * eased + 0.002 * middle * math.sin(2.0 * theta)
    center_y = 0.010 + 0.010 * eased
    x = center_x + surface_rx * cosine - tangential * sine
    y = center_y + surface_ry * sine + tangential * cosine

    top_z = 1.610 + 0.007 * back - 0.003 * front + 0.005 * math.sin(theta + 0.25)
    bottom_z = (
        1.365
        - 0.012 * front
        - 0.010 * back
        + 0.006 * math.sin(theta - 0.45)
        + 0.004 * math.sin(2.0 * theta + 0.2)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += middle ** 1.3 * (0.0045 * math.sin(theta - 0.45) + 0.0022 * math.sin(3.0 * theta + 2.5 * u))
    # Small crest shifts help the bands appear as compressed cloth, not tubes.
    z += 0.0030 * fold_upper - 0.0020 * fold_middle + 0.0020 * fold_lower
    if inner:
        z -= 0.0007 * middle
    return x, y, z


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
old_cowl = bpy.data.objects[OLD_COWL]
asset_collection = old_cowl.users_collection[0]
base_material = old_cowl.data.materials[0]
old_mesh = old_cowl.data
bpy.data.objects.remove(old_cowl, do_unlink=True)
if old_mesh.users == 0:
    bpy.data.meshes.remove(old_mesh)


def index(surface: int, vertical_index: int, angular_index: int) -> int:
    return surface * ROWS * ANGLE_SEGMENTS + vertical_index * ANGLE_SEGMENTS + angular_index


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
    faces.append((
        index(0, 0, angular_index), index(0, 0, nxt),
        index(1, 0, nxt), index(1, 0, angular_index),
    ))
    faces.append((
        index(0, VERTICAL_SEGMENTS, nxt), index(0, VERTICAL_SEGMENTS, angular_index),
        index(1, VERTICAL_SEGMENTS, angular_index), index(1, VERTICAL_SEGMENTS, nxt),
    ))

mesh = bpy.data.meshes.new("Mercenary_CompactBunchedWoolCowl_v16zu_Mesh")
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
cowl["source"] = "V16ZU compact one-piece vertically bunched medieval wool cowl"
cowl["separate_cowl_rings"] = 0
cowl["topology"] = "one closed thin manifold shell with one neck opening"

material = base_material.copy()
material.name = "MAT_v16zu_CompactCharcoalWool_4K"
material.use_backface_culling = False
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv_layer = mesh.uv_layers.new(name="UVMap")
surface_size = ROWS * ANGLE_SEGMENTS
for polygon in mesh.polygons:
    angular_indices = []
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        angular_indices.append((vertex_index % surface_size) % ANGLE_SEGMENTS)
    crosses_seam = 0 in angular_indices and ANGLE_SEGMENTS - 1 in angular_indices
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within = vertex_index % surface_size
        vertical_index = within // ANGLE_SEGMENTS
        angular_index = within % ANGLE_SEGMENTS
        texture_u = angular_index / ANGLE_SEGMENTS * 3.4
        if crosses_seam and angular_index == 0:
            texture_u = 3.4
        texture_v = vertical_index / VERTICAL_SEGMENTS * 2.2
        uv_layer.data[loop_index].uv = (texture_u, texture_v)

# Normalized Rigify weights.  The compact garment is torso-led; only its very
# lowest side vertices inherit a subtle upper-arm response.
group_names = (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
    "DEF-upper_arm.L", "DEF-upper_arm.R",
)
groups = {name: cowl.vertex_groups.new(name=name) for name in group_names}
weight_sums = []
for vertex, (_surface, _vertical_index, _angular_index, u, _theta) in zip(mesh.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.185) / 0.050)
    lower_gate = smoothstep((u - 0.72) / 0.28)
    arm_weight = 0.08 * side_gate * lower_gate
    torso = 1.0 - arm_weight
    upper_factor = 1.0 - smoothstep((u - 0.18) / 0.52)
    lower_factor = smoothstep((u - 0.54) / 0.46)
    w006 = torso * (0.20 + 0.58 * upper_factor)
    remaining = torso - w006
    w004 = remaining * (0.36 + 0.42 * lower_factor)
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

# Remove only the torn original shoulder-root fragments that sit beneath the
# dedicated clean upper-sleeve meshes.  The central textured chest/back and
# all lower clothing remain intact.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    if 0.205 < ax < 0.535 and center.z > 1.285:
        remove_faces.append(face)
removed_shoulder_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zu_removed_torn_shoulder_faces"] = removed_shoulder_faces

cowl_topology = topology(cowl)
if cowl_topology["components"] != 1 or cowl_topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZU topology failed: {cowl_topology}")
if min(weight_sums) < 0.999999 or max(weight_sums) > 1.000001:
    raise RuntimeError(f"V16ZU weights failed: {min(weight_sums)}..{max(weight_sums)}")

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

qa_lights = []
for name, location, energy, size, color in (
    ("V16ZU_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16ZU_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16ZU_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
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
    path = PREVIEWS / f"diagnostic_v16zu_compact_bunched_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

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
total_triangles = sum(triangles(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"V16ZU triangle budget failed: {total_triangles}")

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
    "construction": "compact vertical single closed shell with three integrated asymmetric folds",
    "removed_torn_shoulder_faces": removed_shoulder_faces,
    "cowl_triangles": triangles(cowl),
    "cowl_vertices": len(cowl.data.vertices),
    "topology": cowl_topology,
    "weight_sum_range": [min(weight_sums), max(weight_sums)],
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
cowl["v16zu_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZU_REPORT=" + json.dumps(report, sort_keys=True))
