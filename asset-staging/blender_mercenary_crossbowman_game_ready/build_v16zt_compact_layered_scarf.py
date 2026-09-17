"""Build V16ZT: a compact, fold-rich, single-piece wool scarf cowl.

This candidate keeps the proven V16ZS closed topology and 4K material, but
resculpts every vertex into a narrower clavicle-hugging shape.  Four wandering
fold ridges live in the same continuous thin shell; no separate rings, plates,
bridges, or open gaps are introduced.
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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zt_compact_layered_scarf.blend"
REPORT = STAGING / "v16zt_compact_layered_scarf_report.json"

SOURCE_COWL = "Mercenary_TuckedHemWoolCowl_v16zs_LOD0"
NEW_COWL = "Mercenary_CompactLayeredScarf_v16zt_LOD0"
ANGULAR_SEGMENTS = 192
VERTICAL_SEGMENTS = 48
ROWS = VERTICAL_SEGMENTS + 1
SURFACE_SIZE = ANGULAR_SEGMENTS * ROWS


def clamp(value: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return max(lo, min(hi, value))


def smoothstep(value: float) -> float:
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def angular_delta(angle: float, center: float) -> float:
    return (angle - center + math.pi) % (2.0 * math.pi) - math.pi


def localized(angle: float, center: float, width: float) -> float:
    return math.exp(-0.5 * (angular_delta(angle, center) / width) ** 2)


def gaussian(value: float, center: float, width: float) -> float:
    return math.exp(-((value - center) / width) ** 2)


def fold_profile(u: float, center: float, width: float) -> float:
    """Rounded fold crest followed by a compressed valley/overlap shadow."""
    crest = gaussian(u, center, width)
    valley = gaussian(u, center + 0.064, width * 0.74)
    return crest - 0.52 * valley


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
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
        "nonmanifold_edges": sum(value != 2 for value in edge_faces.values()),
        "boundary_edges": sum(value == 1 for value in edge_faces.values()),
        "overconnected_edges": sum(value > 2 for value in edge_faces.values()),
    }


def layered_scarf_point(theta: float, u: float, inner: bool) -> tuple[float, float, float]:
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)
    left = max(0.0, -cosine)
    right = max(0.0, cosine)
    eased = smoothstep(u)
    middle = math.sin(math.pi * u)

    # Compact neckline and hem: the widest cloth remains clearly inside the
    # sleeve/shoulder line, while the rear receives a little extra drape.
    top_rx = (
        0.121
        + 0.0060 * math.sin(theta + 0.40)
        + 0.0035 * math.sin(3.0 * theta - 0.25)
    )
    top_ry = (
        0.091
        + 0.0055 * math.sin(theta - 0.20)
        + 0.0030 * math.sin(2.0 * theta + 0.55)
    )
    hem_rx = (
        0.181
        + 0.015 * back
        + 0.008 * left
        + 0.007 * localized(theta, -0.72, 0.58)
        - 0.005 * localized(theta, -2.30, 0.62)
    )
    # Rear coverage is concentrated into asymmetric drapes instead of a
    # uniformly wide shoulder cape.  This keeps the exact-top view clean while
    # retaining the donor's intact chest/back geometry below the hem.
    hem_ry = (
        0.128
        + 0.055 * back
        - 0.004 * front
        + 0.006 * right
        + 0.086 * localized(theta, 2.30, 0.50)
        + 0.032 * localized(theta, 1.02, 0.68)
    )
    rx = top_rx * (1.0 - eased) + hem_rx * eased
    ry = top_ry * (1.0 - eased) + hem_ry * eased

    # The bundle is fuller just above the hem, then turns inward against the
    # clavicle/chest instead of projecting as a horizontal cape.
    gathered_fullness = gaussian(u, 0.69, 0.25) * (
        0.014
        + 0.005 * math.sin(theta + 0.65)
        + 0.004 * math.sin(3.0 * theta - 0.45)
        + 0.004 * back
    )
    rx += gathered_fullness
    ry += 0.86 * gathered_fullness

    # Four folds wind at different heights and favour different angular arcs.
    # The low common component keeps them legible around the garment, while
    # the strong local envelopes stop them reading as concentric rings.
    path_1 = 0.105 + 0.050 * math.sin(theta + 0.75) + 0.018 * math.sin(3.0 * theta)
    path_2 = 0.300 + 0.105 * math.sin(theta - 0.15) + 0.034 * math.sin(2.0 * theta + 0.45)
    path_3 = 0.535 + 0.118 * math.sin(theta + 1.45) - 0.038 * math.sin(3.0 * theta - 0.30)
    path_4 = 0.755 + 0.085 * math.sin(theta - 1.15) + 0.030 * math.sin(2.0 * theta + 0.20)

    envelope_1 = 0.30 + 0.70 * localized(theta, -0.48, 1.15)
    envelope_2 = 0.24 + 0.76 * localized(theta, -2.05, 1.05)
    envelope_3 = 0.20 + 0.80 * localized(theta, 0.75, 1.18)
    envelope_4 = min(
        1.0,
        0.20
        + 0.59 * localized(theta, -1.22, 1.02)
        + 0.39 * localized(theta, 2.20, 0.82),
    )

    fold_1 = envelope_1 * fold_profile(u, path_1, 0.055)
    fold_2 = envelope_2 * fold_profile(u, path_2, 0.068)
    fold_3 = envelope_3 * fold_profile(u, path_3, 0.074)
    fold_4 = envelope_4 * fold_profile(u, path_4, 0.078)
    relief = (
        0.017 * fold_1
        + 0.035 * fold_2
        + 0.039 * fold_3
        + 0.033 * fold_4
    )

    # A tucked crossing on the front-right suggests the end of a wrapped scarf
    # without adding a separate flap or an intersecting surface.
    crossing = (
        localized(theta, -0.58, 0.34)
        * gaussian(u, 0.48 + 0.055 * math.sin(theta + 0.3), 0.17)
    )
    relief += 0.019 * crossing
    relief -= 0.005 * localized(theta, -2.45, 0.42) * gaussian(u, 0.57, 0.22)
    relief += middle ** 1.4 * (
        0.0028 * math.sin(5.0 * theta + 2.2 * u)
        + 0.0017 * math.sin(9.0 * theta - 3.0 * u)
    )

    thickness = 0.0068 + 0.0007 * math.sin(2.0 * theta + 1.3 * u) + 0.0004 * middle
    surface_rx = rx + relief
    surface_ry = ry + 0.86 * relief
    if inner:
        surface_rx -= thickness
        surface_ry -= thickness * 0.92

    # Tangential drift gives the folds a wrapped, helical flow while remaining
    # a single connected manifold sheet.
    tangential = middle ** 1.35 * (
        0.0075 * math.sin(theta + 2.0 * u - 0.25)
        + 0.0032 * math.sin(3.0 * theta - 1.4 * u)
        + 0.0045 * crossing
    )
    center_x = -0.0045 * eased + 0.0030 * middle
    center_y = 0.009 + 0.013 * eased
    x = center_x + surface_rx * cosine - tangential * sine
    y = center_y + surface_ry * sine + tangential * cosine

    # The hem cups down over front clavicle and upper back with broad, smooth
    # asymmetry.  No central V point or rear diamond is possible here.
    top_z = (
        1.600
        + 0.009 * math.sin(theta + 0.30)
        + 0.004 * math.sin(3.0 * theta - 0.35)
        + 0.005 * back
        - 0.003 * front
    )
    hem_z = (
        1.394
        - 0.030 * front ** 0.82
        - 0.040 * back ** 0.90
        + 0.006 * side
        + 0.009 * math.sin(theta + 0.48)
        + 0.005 * math.sin(2.0 * theta - 0.25)
        - 0.008 * localized(theta, -0.82, 0.72)
        + 0.006 * localized(theta, -2.35, 0.70)
    )
    z = top_z * (1.0 - eased) + hem_z * eased
    z += middle ** 1.35 * (
        0.0050 * math.sin(theta - 0.45)
        + 0.0028 * math.sin(3.0 * theta + 1.7 * u)
    )
    # Small alternating vertical shifts make the radial ridges read as cloth
    # laid over itself, not embossed stripes on a smooth cylinder.
    z += 0.0060 * fold_1 - 0.0050 * fold_2 + 0.0070 * fold_3 - 0.0045 * fold_4
    if inner:
        z -= 0.0007 * middle
    return x, y, z


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cowl = bpy.data.objects[SOURCE_COWL]
if len(cowl.data.vertices) != 2 * SURFACE_SIZE:
    raise RuntimeError(f"Unexpected V16ZS cowl vertex count: {len(cowl.data.vertices)}")

cowl.name = NEW_COWL
cowl.data.name = "Mercenary_CompactLayeredScarf_v16zt_Mesh"
cowl["source"] = "V16ZT compact one-piece heavy wool scarf with four integrated folds"
cowl["topology"] = "single closed thin manifold shell; one neck opening; no separate rings"
cowl["integrated_fold_count"] = 4
cowl["separate_cowl_rings"] = 0

# Resculpt both sides of the existing proven closed shell in-place.
parameters = []
for surface in (0, 1):
    for row in range(ROWS):
        u = row / VERTICAL_SEGMENTS
        for angular in range(ANGULAR_SEGMENTS):
            theta = math.tau * angular / ANGULAR_SEGMENTS
            vertex_index = surface * SURFACE_SIZE + row * ANGULAR_SEGMENTS + angular
            cowl.data.vertices[vertex_index].co = layered_scarf_point(theta, u, bool(surface))
            parameters.append((surface, row, angular, u, theta))
cowl.data.update()

bm = bmesh.new()
bm.from_mesh(cowl.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()

# Keep the established 4K wool texture, isolated under a V16ZT material name.
source_material = cowl.data.materials[0]
material = source_material.copy()
material.name = "MAT_v16zt_HeavyCharcoalWool_4K"
cowl.data.materials.clear()
cowl.data.materials.append(material)
for polygon in cowl.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

# Rebuild normalized Rigify weights for the narrower silhouette.
for modifier in list(cowl.modifiers):
    if modifier.type == "ARMATURE":
        cowl.modifiers.remove(modifier)
cowl.vertex_groups.clear()
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
for vertex, (_surface, _row, _angular, u, _theta) in zip(cowl.data.vertices, parameters):
    side_gate = smoothstep((abs(vertex.co.x) - 0.165) / 0.060)
    lower_gate = smoothstep((u - 0.68) / 0.32)
    arm_weight = 0.085 * side_gate * lower_gate
    max_arm_weight = max(max_arm_weight, arm_weight)
    torso = 1.0 - arm_weight
    upper_factor = 1.0 - smoothstep((u - 0.12) / 0.55)
    lower_factor = smoothstep((u - 0.54) / 0.46)
    w006 = torso * (0.20 + 0.55 * upper_factor)
    remaining = torso - w006
    w004 = remaining * (0.30 + 0.48 * lower_factor)
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

topology = topology_stats(cowl)
if topology["components"] != 1 or topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"V16ZT topology failed: {topology}")
if min(weight_sums) < 0.999999 or max(weight_sums) > 1.000001:
    raise RuntimeError(f"V16ZT weights failed: {min(weight_sums)}..{max(weight_sums)}")
if not any(mod.type == "ARMATURE" and mod.object == rig for mod in cowl.modifiers):
    raise RuntimeError("V16ZT Rigify armature modifier missing")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zt_layered_scarf_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high": render("high", (0.66, -0.82, 2.16), (0.0, 0.01, 1.45), 86),
    "three_quarter": render("three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"V16ZT triangle budget failed: {total_triangles}")

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
    "construction": "one compact closed wool shell with four integrated asymmetric folds and a tucked clavicle hem",
    "integrated_folds": 4,
    "separate_rings": 0,
    "cowl_vertices": len(cowl.data.vertices),
    "cowl_triangles": triangle_count(cowl),
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
cowl["v16zt_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZT_REPORT=" + json.dumps(report, sort_keys=True))
