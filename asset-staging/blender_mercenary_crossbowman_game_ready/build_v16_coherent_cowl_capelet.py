"""Build a single coherent cloth cowl/capelet candidate from v15.

This is an isolated candidate build.  It retires the old layered cowl and all
four seam-repair helpers, then replaces them with one connected, closed,
manifold garment.  The new cloth rises gently at the neck, slopes over the
trapezius, and drapes over the upper chest/back/shoulders.  It intentionally
avoids separate torus rolls, flat plates, floating wedges, and ragged patch
objects.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16d_cowl_candidate.blend"
REPORT = STAGING / "v16d_coherent_cowl_report.json"

RETIRED_NAMES = (
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
asset_collection = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"].users_collection[0]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]


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


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


# Keep provenance in the editable candidate while making the obsolete pieces
# impossible to render or export as character parts.
retired = []
for name in RETIRED_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.hide_render = True
    obj.hide_viewport = True
    obj.hide_set(True)
    obj["retired_by_v16_coherent_cowl"] = True
    obj["part_category_before_retirement"] = obj.get("part_category")
    if "part_category" in obj:
        del obj["part_category"]
    obj["game_asset"] = False
    retired.append(name)


# A single closed annular cloth shell.  The first few radial samples form one
# subtle integrated neckline roll; the rest continuously drape to a rounded
# capelet hem.  The hem falls more at front/back and stays higher over the
# shoulder caps, which reads as fabric on the body rather than a broad plate.
ANGULAR_SEGMENTS = 144
RADIAL_SEGMENTS = 30
THICKNESS = 0.010


def interpolate_profile(v, values):
    """Smoothly interpolate [(parameter, value), ...]."""
    if v <= values[0][0]:
        return values[0][1]
    for (a_t, a_v), (b_t, b_v) in zip(values, values[1:]):
        if v <= b_t:
            local = smoothstep((v - a_t) / (b_t - a_t))
            return a_v * (1.0 - local) + b_v * local
    return values[-1][1]


RX_PROFILE = (
    (0.00, 0.112),
    (0.07, 0.118),
    (0.17, 0.138),
    (0.35, 0.174),
    (0.60, 0.216),
    (0.82, 0.252),
    (1.00, 0.275),
)
RY_PROFILE = (
    (0.00, 0.085),
    (0.07, 0.090),
    (0.17, 0.108),
    (0.35, 0.137),
    (0.60, 0.168),
    (0.82, 0.195),
    (1.00, 0.215),
)


def surface_point(theta, v):
    cosine = math.cos(theta)
    sine = math.sin(theta)
    front = max(0.0, -sine)
    back = max(0.0, sine)
    side = abs(cosine)

    rx = interpolate_profile(v, RX_PROFILE)
    ry = interpolate_profile(v, RY_PROFILE)

    # Small irregularities are broad and coherent, never sharp torn teeth.
    envelope = math.sin(math.pi * v) ** 1.25
    # The phase of the bunching changes around the neck, so the relief reads
    # as crumpled cloth instead of mathematically concentric rings.
    bunch_phase = 0.85 * math.sin(2.0 * theta + 0.2) + 0.35 * math.sin(5.0 * theta - 0.7)
    bunch_wave = math.sin(3.4 * math.pi * v + bunch_phase)
    radial_warp = 1.0 + envelope * (
        0.014 * math.sin(5.0 * theta + 0.45)
        + 0.008 * math.sin(9.0 * theta - 0.80)
        + 0.012 * bunch_wave
    )
    hem_warp = smoothstep((v - 0.82) / 0.18) * 0.008 * math.sin(7.0 * theta + 0.25)
    radial_warp += hem_warp

    # A tiny rearward shift lets the front drape sit on the chest while the
    # rear covers the old shoulder seam without forming shoulder pads.
    y_center = 0.015 + 0.020 * smoothstep(v)
    x = rx * radial_warp * cosine
    y = y_center + ry * radial_warp * sine

    inner_z = (
        1.525
        + 0.052 * back ** 1.35
        - 0.010 * front ** 1.15
        + 0.004 * math.cos(2.0 * theta)
    )
    # A shawl/cowl rests on the lateral shoulder caps but hangs markedly down
    # the chest and back.  This strong angular falloff is what prevents the
    # garment from reading as a horizontal disc or armour plate.
    outer_z = (
        1.416
        + 0.030 * side ** 2.20
        + 0.015 * back
        - 0.002 * front
    )
    descent = smoothstep(v)
    z = inner_z * (1.0 - descent) + outer_z * descent

    # One integrated neckline roll, not a separate torus or stack of rings.
    z += 0.014 * math.exp(-((v - 0.070) / 0.050) ** 2)
    z -= 0.004 * math.exp(-((v - 0.205) / 0.085) ** 2)

    # Radial cloth folds radiate from the neck.  Their amplitude disappears at
    # both rims so the opening and hem stay clean and continuous.
    fold_envelope = math.sin(math.pi * v) ** 1.15
    z += fold_envelope * (
        0.0090 * math.sin(7.0 * theta + 0.35)
        + 0.0045 * math.sin(13.0 * theta - 0.65)
        + 0.0025 * math.sin(3.0 * theta + 1.10)
        + 0.0120 * bunch_wave
    )
    z += smoothstep((v - 0.78) / 0.22) * 0.004 * math.sin(6.0 * theta - 0.4)
    return x, y, z


vertices = []
parameters = []
for surface in (0, 1):
    for radial_index in range(RADIAL_SEGMENTS + 1):
        v = radial_index / RADIAL_SEGMENTS
        for angular_index in range(ANGULAR_SEGMENTS):
            theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
            x, y, z = surface_point(theta, v)
            if surface == 1:
                z -= THICKNESS
            vertices.append((x, y, z))
            parameters.append((surface, radial_index, angular_index, v, theta))

RING = ANGULAR_SEGMENTS
SURFACE_SIZE = (RADIAL_SEGMENTS + 1) * RING
faces = []

for radial_index in range(RADIAL_SEGMENTS):
    for angular_index in range(ANGULAR_SEGMENTS):
        nxt = (angular_index + 1) % ANGULAR_SEGMENTS
        a = radial_index * RING + angular_index
        b = (radial_index + 1) * RING + angular_index
        c = (radial_index + 1) * RING + nxt
        d = radial_index * RING + nxt
        faces.append((a, b, c, d))
        faces.append((SURFACE_SIZE + d, SURFACE_SIZE + c, SURFACE_SIZE + b, SURFACE_SIZE + a))

outer_start = RADIAL_SEGMENTS * RING
for angular_index in range(ANGULAR_SEGMENTS):
    nxt = (angular_index + 1) % ANGULAR_SEGMENTS
    # Outer rim, outward-facing.
    faces.append(
        (
            outer_start + angular_index,
            SURFACE_SIZE + outer_start + angular_index,
            SURFACE_SIZE + outer_start + nxt,
            outer_start + nxt,
        )
    )
    # Inner neckline rim, inward-facing.
    faces.append(
        (
            angular_index,
            nxt,
            SURFACE_SIZE + nxt,
            SURFACE_SIZE + angular_index,
        )
    )

mesh = bpy.data.meshes.new("Mercenary_CoherentClothCowlCapelet_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
recalc_outside(mesh)
capelet = bpy.data.objects.new("Mercenary_CoherentClothCowlCapelet_LOD0", mesh)
asset_collection.objects.link(capelet)
mesh.materials.append(cloth_material)
capelet["game_asset"] = True
capelet["part_category"] = "ClothedBody"
capelet["intentional_layer"] = True
capelet["source"] = "V16 single connected closed cloth cowl/capelet"
capelet["replaces"] = ", ".join(RETIRED_NAMES)

# Top-projected wool UVs avoid radial pinching.  The 4K source texture is
# seamless and is shared with the accepted neutral-charcoal cowl material.
uv_layer = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv_layer.data[loop_index].uv = (0.5 + co.x * 2.65, 0.5 + (co.y - 0.02) * 2.65)

# Rigify binding.  The neckline follows the upper spine; the outer shoulder
# areas blend into their corresponding upper arms for useful animation.
spine_neck = capelet.vertex_groups.new(name="DEF-spine.006")
spine_upper = capelet.vertex_groups.new(name="DEF-spine.005")
spine_chest = capelet.vertex_groups.new(name="DEF-spine.004")
left_arm = capelet.vertex_groups.new(name="DEF-upper_arm.L")
right_arm = capelet.vertex_groups.new(name="DEF-upper_arm.R")

weight_sums = []
for vertex, (_surface, _r, _a, v, _theta) in zip(mesh.vertices, parameters):
    arm_weight = 0.25 * smoothstep((abs(vertex.co.x) - 0.230) / 0.045) * smoothstep((v - 0.72) / 0.28)
    torso_weight = 1.0 - arm_weight
    neck_factor = 0.10 + 0.78 * (1.0 - smoothstep(v / 0.55))
    chest_factor = 0.62 * smoothstep((v - 0.38) / 0.62)
    upper_factor = max(0.0, 1.0 - neck_factor - chest_factor)
    normalizer = neck_factor + upper_factor + chest_factor
    neck_share = torso_weight * neck_factor / normalizer
    upper_share = torso_weight * upper_factor / normalizer
    chest_share = torso_weight * chest_factor / normalizer
    spine_neck.add([vertex.index], neck_share, "REPLACE")
    spine_upper.add([vertex.index], upper_share, "REPLACE")
    spine_chest.add([vertex.index], chest_share, "REPLACE")
    if arm_weight > 0.0:
        (left_arm if vertex.co.x >= 0.0 else right_arm).add([vertex.index], arm_weight, "REPLACE")
    weight_sums.append(neck_share + upper_share + chest_share + arm_weight)

armature = capelet.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
capelet.parent = rig
capelet.matrix_parent_inverse = rig.matrix_world.inverted()


stats = manifold_stats(capelet)
if stats["nonmanifold_edges"] != 0:
    raise RuntimeError(f"Cowl/capelet is not closed manifold: {stats}")
if min(weight_sums) < 0.999999 or max(weight_sums) > 1.000001:
    raise RuntimeError(f"Invalid skin weight sums: {min(weight_sums)}, {max(weight_sums)}")


character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f"diagnostic_v16d_cowl_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    return str(output)


previews = {}
previews["top_close"] = render(
    "top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49),
    ortho_scale=0.95, resolution=(1200, 900),
)
previews["failure_view"] = render(
    "failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02),
    lens=78, resolution=(1400, 1000),
)
previews["front"] = render(
    "front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89),
    ortho_scale=2.06,
)
previews["back"] = render(
    "back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89),
    ortho_scale=2.06,
)
previews["three_quarter"] = render(
    "three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72,
)
previews["upper_three_quarter"] = render(
    "upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49),
    lens=76, resolution=(1200, 1000),
)

bounds = {
    "min": [min(vertex.co[i] for vertex in mesh.vertices) for i in range(3)],
    "max": [max(vertex.co[i] for vertex in mesh.vertices) for i in range(3)],
}
report = {
    "source": str(SOURCE),
    "candidate_blend": str(OUTPUT),
    "new_object": capelet.name,
    "retired_objects": retired,
    "new_vertices": len(mesh.vertices),
    "new_polygons": len(mesh.polygons),
    "new_triangles": triangle_count(capelet),
    "character_meshes": len(character_meshes),
    "character_triangles": total_triangles,
    "manifold": stats,
    "skin_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "rig_modifier": armature.name,
    "bounds": bounds,
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")

# Leave a useful close three-quarter camera and a clean viewport in the file.
rig.hide_viewport = True
rig.hide_set(True)
camera.data.type = "PERSP"
camera.data.lens = 76
camera.location = (1.15, -1.55, 2.05)
look_at(camera, (0.0, 0.0, 1.49))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V16_COWL_OBJECT", capelet.name)
print("V16_COWL_RETIRED", retired)
print("V16_COWL_TRIANGLES", triangle_count(capelet))
print("V16_CHARACTER_TRIANGLES", total_triangles)
print("V16_COWL_MANIFOLD", stats)
print("V16_COWL_WEIGHT_RANGE", min(weight_sums), max(weight_sums))
print("V16_COWL_BOUNDS", bounds)
print("WROTE", OUTPUT)
print("WROTE", REPORT)
