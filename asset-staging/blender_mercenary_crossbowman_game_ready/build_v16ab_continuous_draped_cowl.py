"""Build a single continuous draped cowl with integrated, non-ring cloth folds."""

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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16ag_dark_bunched_cowl_candidate.blend"
REPORT = STAGING / "v16ag_dark_bunched_cowl_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]

removed = []
for name in (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_Liner_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        removed.append(name)
        bpy.data.objects.remove(obj, do_unlink=True)


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


segments = 192
radial_steps = 36
texture_repeats_u = 3.5
texture_repeats_v = 2.2
vertices = []
params = []


def surface_point(angle_index, radial_index, bottom=False):
    theta = 2.0 * math.pi * angle_index / segments
    u = radial_index / radial_steps
    sin_t = math.sin(theta)
    cos_t = math.cos(theta)
    front = max(0.0, -sin_t)
    back = max(0.0, sin_t)
    side = abs(cos_t)

    # An asymmetric opening and shoulder outline prevent a mechanical donut.
    inner_rx = 0.112 * (1.0 + 0.050 * math.sin(3.0 * theta + 0.55))
    inner_ry = 0.086 * (1.0 + 0.060 * math.sin(2.0 * theta - 0.35))
    outer_rx = (0.290 + 0.032 * side ** 6) * (
        1.0 + 0.045 * math.sin(3.0 * theta + 1.10)
    )
    outer_ry = (0.205 + 0.018 * back - 0.008 * front) * (
        1.0 + 0.038 * math.sin(5.0 * theta - 0.70)
    )
    rx = inner_rx + (outer_rx - inner_rx) * u
    ry = inner_ry + (outer_ry - inner_ry) * u
    x = rx * cos_t
    y = ry * sin_t

    # The neck edge stands higher; the outside drapes onto chest and shoulders.
    inner_z = 1.548 + 0.044 * back + 0.018 * side - 0.008 * front
    outer_z = 1.408 + 0.036 * back + 0.028 * side - 0.010 * front
    z = inner_z * (1.0 - u) + outer_z * u

    # Two broad ridges are sculpted into one surface instead of stacked shells.
    ridge_a_path = 0.29 + 0.055 * math.sin(2.0 * theta + 0.35)
    ridge_b_path = 0.67 + 0.060 * math.sin(3.0 * theta - 0.80)
    ridge_a = math.exp(-((u - ridge_a_path) / 0.075) ** 2)
    ridge_b = math.exp(-((u - ridge_b_path) / 0.088) ** 2)
    valley = math.exp(-((u - 0.49) / 0.070) ** 2)
    z += 0.046 * ridge_a * (0.78 + 0.22 * math.sin(theta + 0.9))
    z += 0.036 * ridge_b * (0.80 + 0.20 * math.sin(2.0 * theta - 0.4))
    z -= 0.010 * valley * (0.85 + 0.15 * math.sin(3.0 * theta))
    z += 0.0080 * math.sin(3.0 * theta + 0.7) * (1.0 - 0.35 * u)
    z += 0.0045 * math.sin(7.0 * theta - 0.2) * (0.3 + 0.7 * u)

    # Pull the center-front outer cloth down into a shallow natural drape.
    front_center = math.exp(-((theta + math.pi / 2.0) / 0.52) ** 2)
    z -= 0.030 * front_center * smoothstep((u - 0.32) / 0.68)
    x += 0.006 * math.sin(2.0 * theta + 0.4) * u
    y += 0.006 * math.sin(3.0 * theta - 0.2) * (0.25 + 0.75 * u)

    if bottom:
        z -= 0.016 + 0.004 * u
    return (x, y, z)


for bottom in (False, True):
    for angle_index in range(segments):
        for radial_index in range(radial_steps + 1):
            vertices.append(surface_point(angle_index, radial_index, bottom))
            params.append((angle_index, radial_index, bottom))

ring_stride = radial_steps + 1
surface_stride = segments * ring_stride


def vid(angle_index, radial_index, bottom=False):
    return (surface_stride if bottom else 0) + (angle_index % segments) * ring_stride + radial_index


faces = []
face_uvs = []
for angle_index in range(segments):
    next_angle = (angle_index + 1) % segments
    u0 = texture_repeats_u * angle_index / segments
    u1 = texture_repeats_u * (angle_index + 1) / segments
    for radial_index in range(radial_steps):
        v0 = texture_repeats_v * radial_index / radial_steps
        v1 = texture_repeats_v * (radial_index + 1) / radial_steps
        faces.append((
            vid(angle_index, radial_index),
            vid(angle_index, radial_index + 1),
            vid(next_angle, radial_index + 1),
            vid(next_angle, radial_index),
        ))
        face_uvs.append(((u0, v0), (u0, v1), (u1, v1), (u1, v0)))
        faces.append((
            vid(angle_index, radial_index, True),
            vid(next_angle, radial_index, True),
            vid(next_angle, radial_index + 1, True),
            vid(angle_index, radial_index + 1, True),
        ))
        face_uvs.append(((u0, v0), (u1, v0), (u1, v1), (u0, v1)))

    # Inner and outer walls close the sheet into one watertight volume.
    faces.append((
        vid(angle_index, 0),
        vid(next_angle, 0),
        vid(next_angle, 0, True),
        vid(angle_index, 0, True),
    ))
    face_uvs.append(((u0, 0.0), (u1, 0.0), (u1, 0.20), (u0, 0.20)))
    faces.append((
        vid(angle_index, radial_steps),
        vid(angle_index, radial_steps, True),
        vid(next_angle, radial_steps, True),
        vid(next_angle, radial_steps),
    ))
    face_uvs.append(((u0, 0.0), (u0, 0.20), (u1, 0.20), (u1, 0.0)))

mesh = bpy.data.meshes.new("Mercenary_ContinuousDrapedCowl_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.validate(clean_customdata=False)
mesh.update()
uv_layer = mesh.uv_layers.new(name="UVMap")
for polygon, polygon_uvs in zip(mesh.polygons, face_uvs):
    for loop_index, uv in zip(polygon.loop_indices, polygon_uvs):
        uv_layer.data[loop_index].uv = uv

cowl = bpy.data.objects.new("Mercenary_ContinuousDrapedCowl_LOD0", mesh)
scene.collection.objects.link(cowl)
for polygon in mesh.polygons:
    polygon.use_smooth = True

material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"].copy()
material.name = "MAT_Cowl_DarkBunchedWeatheredWool_PBR_4K_v16ag"
material.use_backface_culling = False
principled = material.node_tree.nodes.get("Principled BSDF")
if principled is not None:
    principled.inputs["Roughness"].default_value = 0.76
    texture = material.node_tree.nodes.get("BaseColor_4K")
    if texture is not None:
        for link in list(principled.inputs["Base Color"].links):
            material.node_tree.links.remove(link)
        tone = material.node_tree.nodes.new("ShaderNodeHueSaturation")
        tone.name = "BunchedCowlCharcoalTone_v16ag"
        tone.inputs["Saturation"].default_value = 0.82
        tone.inputs["Value"].default_value = 0.68
        material.node_tree.links.new(texture.outputs["Color"], tone.inputs["Color"])
        material.node_tree.links.new(tone.outputs["Color"], principled.inputs["Base Color"])
mesh.materials.append(material)

spine_4 = cowl.vertex_groups.new(name="DEF-spine.004")
spine_5 = cowl.vertex_groups.new(name="DEF-spine.005")
spine_6 = cowl.vertex_groups.new(name="DEF-spine.006")
arm_l = cowl.vertex_groups.new(name="DEF-upper_arm.L")
arm_r = cowl.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    head = smoothstep((z - 1.505) / 0.080)
    arm = 0.27 * smoothstep((abs(x) - 0.245) / 0.095) * (1.0 - head)
    torso = max(0.0, 1.0 - head - arm)
    chest = torso * (0.42 - 0.10 * smoothstep((z - 1.43) / 0.12))
    upper = torso - chest
    if chest:
        spine_4.add([vertex.index], chest, "REPLACE")
    if upper:
        spine_5.add([vertex.index], upper, "REPLACE")
    if head:
        spine_6.add([vertex.index], head, "REPLACE")
    if arm:
        (arm_l if x >= 0.0 else arm_r).add([vertex.index], arm, "REPLACE")

modifier = cowl.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16 continuous draped cloth cowl with integrated folds"


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def topology_stats(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return {
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def component_count(obj):
    adjacency = defaultdict(set)
    for edge in obj.data.edges:
        a, b = edge.vertices
        adjacency[a].add(b)
        adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    count = 0
    while unseen:
        count += 1
        stack = [unseen.pop()]
        while stack:
            current = stack.pop()
            linked = adjacency[current] & unseen
            unseen.difference_update(linked)
            stack.extend(linked)
    return count


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        obj.hide_render = True
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
previews = {}


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
    path = PREVIEWS / f"diagnostic_v16ag_dark_bunched_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    previews[key] = str(path)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure_view", (0.57, -0.57, 5.58), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("upper_three_quarter", (1.15, -1.55, 2.05), (0.0, 0.0, 1.49), lens=76, resolution=(1200, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
triangles = sum(triangle_count(obj) for obj in character_meshes)
topology = topology_stats(cowl)
components = component_count(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in mesh.vertices]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "removed": removed,
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "cowl_triangles": triangle_count(cowl),
    "cowl_components": components,
    "cowl_topology": topology,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "previews": previews,
}
if not 100_000 <= triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {triangles}")
if components != 1 or topology["nonmanifold_edges"]:
    raise RuntimeError(f"Cowl topology failed: {topology}, components={components}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights failed: {(min(weight_sums), max(weight_sums))}")

REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
