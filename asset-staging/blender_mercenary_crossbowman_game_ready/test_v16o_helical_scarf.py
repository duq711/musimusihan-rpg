"""Create one continuous, naturally wrapped scarf instead of stacked rings."""

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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16u_two_wrap_draped_scarf_candidate.blend"
REPORT = STAGING / "v16u_two_wrap_draped_scarf_report.json"

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
material.name = "MAT_Cowl_TwoWrapDrapedWool_PBR_4K_v16u"
material.use_backface_culling = False
nodes = material.node_tree.nodes
links = material.node_tree.links
base_texture = nodes.get("BaseColor_4K")
principled = nodes.get("Principled BSDF")
if base_texture is not None and principled is not None:
    for link in list(principled.inputs["Base Color"].links):
        links.remove(link)
    tone = nodes.new("ShaderNodeHueSaturation")
    tone.name = "DeepCharcoalTone_v16u"
    tone.inputs["Saturation"].default_value = 0.82
    tone.inputs["Value"].default_value = 0.52
    links.new(base_texture.outputs["Color"], tone.inputs["Color"])
    links.new(tone.outputs["Color"], principled.inputs["Base Color"])


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


TURNS = 2.0
LONG_SEGMENTS = 320
WIDTH_SEGMENTS = 12
HALF_WIDTH = 0.067
THICKNESS = 0.007
START_THETA = math.pi / 2.0  # both ends meet at the back after three turns


def centerline(progress):
    theta = START_THETA + progress * TURNS * 2.0 * math.pi
    # The wraps stay on almost the same neck radius and advance mainly down
    # the body.  Their broad width overlaps the small radial growth, so a top
    # view reads as one gathered cloth mass instead of a spiral target.
    rx = 0.158 + 0.038 * smoothstep(progress)
    ry = 0.105 + 0.030 * smoothstep(progress)
    irregular = (
        0.0110 * math.sin(3.0 * theta + 0.6)
        + 0.0050 * math.sin(7.0 * theta - 0.2)
        + 0.0025 * math.cos(11.0 * theta + 0.9)
    )
    rx += irregular
    ry += irregular * 0.55
    front = max(0.0, -math.sin(theta))
    back = max(0.0, math.sin(theta))
    z = (
        1.566
        - 0.132 * progress
        - 0.012 * front
        + 0.004 * back
        + 0.0100 * math.sin(2.0 * theta + 0.4)
        + 0.0040 * math.sin(5.0 * theta - 0.7)
    )
    x = -0.004 + rx * math.cos(theta)
    y = 0.010 + ry * math.sin(theta)
    return Vector((x, y, z)), theta, rx, ry


vertices = []
parameters = []
for surface in (-1.0, 1.0):
    for long_index in range(LONG_SEGMENTS + 1):
        progress = long_index / LONG_SEGMENTS
        center, theta, rx, ry = centerline(progress)
        epsilon = 1.0 / (LONG_SEGMENTS * 3.0)
        previous = centerline(max(0.0, progress - epsilon))[0]
        following = centerline(min(1.0, progress + epsilon))[0]
        tangent = (following - previous).normalized()
        radial = Vector((math.cos(theta) / max(rx, 1.0e-6),
                         math.sin(theta) / max(ry, 1.0e-6), 0.0)).normalized()
        # Width is mostly vertical, with an outward lean that turns the top
        # edge into a soft fold visible from above.
        outward_lean = 0.58 + 0.14 * math.sin(theta + 1.2)
        width_direction = (Vector((0.0, 0.0, 1.0)) + radial * outward_lean).normalized()
        normal = tangent.cross(width_direction).normalized()
        if normal.dot(radial) < 0.0:
            normal.negate()
        local_half_width = HALF_WIDTH * (
            1.0 + 0.12 * math.sin(4.0 * theta + 1.1)
            + 0.05 * math.sin(9.0 * theta)
        )
        for width_index in range(WIDTH_SEGMENTS + 1):
            width_parameter = width_index / WIDTH_SEGMENTS
            across = width_parameter * 2.0 - 1.0
            # Slight cupping and fine compression ripples replace the rigid
            # planar look of the earlier comparison candidate.
            cup = radial * (-0.0080 * (1.0 - across * across))
            ripple = normal * (0.0030 * math.sin(6.0 * theta + across * 2.8)
                               + 0.0015 * math.sin(13.0 * theta - across))
            position = (
                center
                + width_direction * (across * local_half_width)
                + cup
                + ripple
                + normal * (surface * THICKNESS * 0.5)
            )
            vertices.append(tuple(position))
            parameters.append((surface, progress, width_parameter, theta))

surface_size = (LONG_SEGMENTS + 1) * (WIDTH_SEGMENTS + 1)
faces = []
for long_index in range(LONG_SEGMENTS):
    for width_index in range(WIDTH_SEGMENTS):
        a = long_index * (WIDTH_SEGMENTS + 1) + width_index
        b = (long_index + 1) * (WIDTH_SEGMENTS + 1) + width_index
        c = (long_index + 1) * (WIDTH_SEGMENTS + 1) + width_index + 1
        d = long_index * (WIDTH_SEGMENTS + 1) + width_index + 1
        # Surface -1 and +1 use opposite winding.
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c,
                      surface_size + b, surface_size + a))

# Close the two long edges and both scarf ends, yielding a watertight cloth.
for long_index in range(LONG_SEGMENTS):
    next_long = long_index + 1
    low = long_index * (WIDTH_SEGMENTS + 1)
    low_next = next_long * (WIDTH_SEGMENTS + 1)
    high = low + WIDTH_SEGMENTS
    high_next = low_next + WIDTH_SEGMENTS
    faces.append((low_next, low, surface_size + low, surface_size + low_next))
    faces.append((high, high_next, surface_size + high_next, surface_size + high))
start_low = 0
start_high = WIDTH_SEGMENTS
end_low = LONG_SEGMENTS * (WIDTH_SEGMENTS + 1)
end_high = end_low + WIDTH_SEGMENTS
for width_index in range(WIDTH_SEGMENTS):
    nxt = width_index + 1
    faces.append((start_low + width_index, start_low + nxt,
                  surface_size + start_low + nxt, surface_size + start_low + width_index))
    faces.append((end_low + nxt, end_low + width_index,
                  surface_size + end_low + width_index, surface_size + end_low + nxt))

mesh = bpy.data.meshes.new("Mercenary_ContinuousWrappedCowl_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()
scarf = bpy.data.objects.new("Mercenary_ContinuousWrappedCowl_LOD0", mesh)
collection.objects.link(scarf)
mesh.materials.append(material)
scarf["game_asset"] = True
scarf["part_category"] = "ClothedBody"
scarf["intentional_layer"] = True
scarf["source"] = "V16 one continuous three-turn helical wool scarf with a flattened cloth section"
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        _surface, progress, width_parameter, _theta = parameters[vertex_index]
        uv.data[loop_index].uv = (progress * 5.5, width_parameter * 1.3)

# Bind the scarf to the same upper torso/head chain used by the donor cowl.
spine_4 = scarf.vertex_groups.new(name="DEF-spine.004")
spine_5 = scarf.vertex_groups.new(name="DEF-spine.005")
spine_6 = scarf.vertex_groups.new(name="DEF-spine.006")
arm_l = scarf.vertex_groups.new(name="DEF-upper_arm.L")
arm_r = scarf.vertex_groups.new(name="DEF-upper_arm.R")
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    head = smoothstep((z - 1.50) / 0.075)
    arm = 0.24 * smoothstep((abs(x) - 0.235) / 0.10) * (1.0 - head)
    torso = 1.0 - head - arm
    chest = torso * 0.37
    upper = torso - chest
    if chest:
        spine_4.add([vertex.index], chest, "REPLACE")
    if upper:
        spine_5.add([vertex.index], upper, "REPLACE")
    if head:
        spine_6.add([vertex.index], head, "REPLACE")
    if arm:
        (arm_l if x >= 0.0 else arm_r).add([vertex.index], arm, "REPLACE")
modifier = scarf.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
scarf.parent = rig
scarf.matrix_parent_inverse = rig.matrix_world.inverted()


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
    path = PREVIEWS / f"diagnostic_v16u_two_wrap_scarf_{key}.png"
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
stats = manifold_stats(scarf)
if not 100_000 <= triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {triangles}")
if stats["nonmanifold_edges"]:
    raise RuntimeError(f"Scarf is open: {stats}")
if min(weights) < 0.999 or max(weights) > 1.001:
    raise RuntimeError(f"Scarf weights invalid: {(min(weights), max(weights))}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "character_meshes": len(character_meshes),
    "character_triangles": triangles,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "scarf_triangles": triangle_count(scarf),
    "scarf_manifold": stats,
    "scarf_weight_sum_range": [min(weights), max(weights)],
    "turns": TURNS,
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2), encoding="utf-8")
rig.hide_viewport = True
rig.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print(json.dumps(report, indent=2))
