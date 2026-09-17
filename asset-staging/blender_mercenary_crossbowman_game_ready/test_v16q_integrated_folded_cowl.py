"""Build one compact, vertically bundled cowl shell over the donor opening."""

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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16s_sculpted_bundled_cowl_candidate.blend"
REPORT = STAGING / "v16s_sculpted_bundled_cowl_report.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
collection = donor.users_collection[0]

for name in (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is not None:
        bpy.data.objects.remove(obj, do_unlink=True)

source_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
material = source_material.copy()
material.name = "MAT_Cowl_SculptedBundledWool_PBR_4K_v16s"
material.use_backface_culling = False
nodes = material.node_tree.nodes
links = material.node_tree.links
texture = nodes.get("BaseColor_4K")
principled = nodes.get("Principled BSDF")
if texture is not None and principled is not None:
    for link in list(principled.inputs["Base Color"].links):
        links.remove(link)
    tone = nodes.new("ShaderNodeHueSaturation")
    tone.name = "SculptedCharcoalTone_v16s"
    tone.inputs["Saturation"].default_value = 0.85
    tone.inputs["Value"].default_value = 0.60
    links.new(texture.outputs["Color"], tone.inputs["Color"])
    links.new(tone.outputs["Color"], principled.inputs["Base Color"])


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


ANGULAR_SEGMENTS = 192
CROSS_SEGMENTS = 48
vertices = []
parameters = []

for cross_index in range(CROSS_SEGMENTS):
    phi = 2.0 * math.pi * cross_index / CROSS_SEGMENTS
    outer_bias = 0.5 + 0.5 * math.cos(phi)
    top_bias = max(0.0, math.sin(phi))
    bottom_bias = max(0.0, -math.sin(phi))
    for angular_index in range(ANGULAR_SEGMENTS):
        theta = 2.0 * math.pi * angular_index / ANGULAR_SEGMENTS
        cosine = math.cos(theta)
        sine = math.sin(theta)
        front = max(0.0, -sine)
        back = max(0.0, sine)
        side = abs(cosine)

        # One closed tubular cloth volume.  Its cross-section is taller than it
        # is wide, so it bunches around the neck instead of becoming a poncho.
        phase = 0.36 * math.sin(theta + 0.7) + 0.17 * math.sin(3.0 * theta - 0.3)
        cross_fold = math.sin(3.0 * phi + phase)
        diagonal_fold = math.sin(2.0 * phi - 1.7 * theta + 0.9)
        irregular = math.sin(5.0 * theta + 0.6) + 0.45 * math.sin(9.0 * theta - 0.2)

        center_rx = 0.169 + 0.010 * math.sin(2.0 * theta + 0.3)
        center_ry = 0.119 + 0.008 * math.cos(3.0 * theta - 0.5)
        half_rx = 0.062 + 0.008 * front + 0.004 * side
        half_ry = 0.047 + 0.010 * front + 0.003 * back
        # A three-lobed cross-section produces broad, integrated fabric folds
        # instead of smooth inflatable tubing or separate stacked rings.
        fold_radial = outer_bias * (0.018 * math.cos(3.0 * phi + phase)
                                    + 0.006 * diagonal_fold)
        fold_radial += 0.008 * outer_bias * irregular

        rx = center_rx + half_rx * math.cos(phi) + fold_radial
        ry = center_ry + half_ry * math.cos(phi) + 0.72 * fold_radial
        center_x = -0.004 + 0.004 * math.sin(2.0 * theta + 0.8)
        center_y = 0.012 + 0.006 * math.cos(2.0 * theta - 0.4)
        x = center_x + rx * cosine
        y = center_y + ry * sine

        z_center = 1.500 - 0.011 * front + 0.003 * back
        z = z_center + 0.080 * math.sin(phi)
        z += 0.018 * math.sin(3.0 * phi + phase) * (0.30 + 0.70 * outer_bias)
        z += 0.006 * diagonal_fold * outer_bias
        z -= 0.014 * bottom_bias * front
        z += 0.009 * top_bias * math.sin(4.0 * theta + 0.4)
        vertices.append((x, y, z))
        parameters.append((phi, theta))

faces = []
for cross_index in range(CROSS_SEGMENTS):
    cross_next = (cross_index + 1) % CROSS_SEGMENTS
    for angular_index in range(ANGULAR_SEGMENTS):
        angular_next = (angular_index + 1) % ANGULAR_SEGMENTS
        a = cross_index * ANGULAR_SEGMENTS + angular_index
        b = cross_next * ANGULAR_SEGMENTS + angular_index
        c = cross_next * ANGULAR_SEGMENTS + angular_next
        d = cross_index * ANGULAR_SEGMENTS + angular_next
        faces.append((a, b, c, d))

mesh = bpy.data.meshes.new("Mercenary_CompactBundledCowl_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()
cowl = bpy.data.objects.new("Mercenary_CompactBundledCowl_LOD0", mesh)
collection.objects.link(cowl)
mesh.materials.append(material)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16 one compact connected vertically bundled wool cowl"
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        phi, theta = parameters[vertex_index]
        uv.data[loop_index].uv = (theta / (2.0 * math.pi) * 3.0, phi / (2.0 * math.pi) * 1.8)

spine_4 = cowl.vertex_groups.new(name="DEF-spine.004")
spine_5 = cowl.vertex_groups.new(name="DEF-spine.005")
spine_6 = cowl.vertex_groups.new(name="DEF-spine.006")
arm_l = cowl.vertex_groups.new(name="DEF-upper_arm.L")
arm_r = cowl.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    head = smoothstep((z - 1.49) / 0.085)
    arm = 0.27 * smoothstep((abs(x) - 0.235) / 0.10) * (1.0 - head)
    torso = 1.0 - head - arm
    chest = torso * 0.39
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


def triangle_count(obj):
    return sum(max(1, len(face.vertices) - 2) for face in obj.data.polygons)


def manifold_stats(obj):
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
    path = PREVIEWS / f"diagnostic_v16s_sculpted_cowl_{key}.png"
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
weights = [sum(group.weight for group in vertex.groups) for vertex in mesh.vertices]
stats = manifold_stats(cowl)
if not 100_000 <= triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {triangles}")
if stats["nonmanifold_edges"] or component_count(cowl) != 1:
    raise RuntimeError(f"Integrated cowl topology failed: {stats}, components={component_count(cowl)}")
if min(weights) < 0.999 or max(weights) > 1.001:
    raise RuntimeError(f"Cowl weights invalid: {(min(weights), max(weights))}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "cowl_triangles": triangle_count(cowl),
    "cowl_components": component_count(cowl),
    "cowl_manifold": stats,
    "cowl_weight_sum_range": [min(weights), max(weights)],
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
