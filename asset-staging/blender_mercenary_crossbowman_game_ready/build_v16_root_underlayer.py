"""V16 diagnostic: minimal three-fold scarf plus one hidden gambeson shoulder underlayer."""

from __future__ import annotations

from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16_underlayer.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
collection = donor.users_collection[0]


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def nonmanifold_edges(obj):
    counts = {}
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            key = tuple(sorted((a, b)))
            counts[key] = counts.get(key, 0) + 1
    return sum(value != 2 for value in counts.values())


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


# Remove v15's three perfect toruses and disconnected shoulder repair pieces.
for name in (
    "Mercenary_InnerCowl_RolledCollar_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
):
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)

# Retain the useful sculpted scarf folds, but make them one consistent wool.
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
cowl_material = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
cowl.data.materials.clear()
cowl.data.materials.append(cowl_material)
for poly in cowl.data.polygons:
    poly.material_index = 0
    poly.use_smooth = True

# A low, sloped, one-piece quilted yoke sits below the scarf.  It is not a
# visible collar: its only purpose is to replace the donor's jagged neck and
# shoulder cutout with continuous cloth matching the gambeson sleeves.
SEGMENTS = 160
RINGS = 6
THICKNESS = 0.010
vertices = []
faces = []


def surface_point(angle, radial, bottom=False):
    c = math.cos(angle)
    s = math.sin(angle)
    # The donor opening is deeper at the back (+Y), so the yoke is biased rearward.
    inner_rx = 0.120
    inner_ry = 0.083
    inner_cy = 0.018
    outer_rx = 0.372
    outer_ry = 0.190
    outer_cy = 0.045
    ease = radial * radial * (3.0 - 2.0 * radial)
    rx = inner_rx + (outer_rx - inner_rx) * ease
    ry = inner_ry + (outer_ry - inner_ry) * ease
    cy = inner_cy + (outer_cy - inner_cy) * ease
    x = c * rx
    y = cy + s * ry
    # Soft asymmetric cloth irregularity, kept small so it reads as fabric.
    x += (0.0035 * math.sin(3.0 * angle + 0.4) + 0.0018 * math.sin(7.0 * angle)) * radial
    y += 0.0028 * math.sin(5.0 * angle - 0.3) * radial
    side = c * c
    back = max(0.0, s)
    front = max(0.0, -s)
    outer_z = 1.402 - 0.024 * side + 0.011 * back + 0.004 * front
    inner_z = 1.447 + 0.004 * math.sin(3.0 * angle + 0.6)
    z = inner_z + (outer_z - inner_z) * ease
    z += 0.0030 * math.sin(4.0 * angle + radial * 1.8) * radial * (1.0 - radial)
    if bottom:
        z -= THICKNESS
    return (x, y, z)


for bottom in (False, True):
    for ring in range(RINGS):
        radial = ring / (RINGS - 1)
        for segment in range(SEGMENTS):
            angle = 2.0 * math.pi * segment / SEGMENTS
            vertices.append(surface_point(angle, radial, bottom))


def vid(bottom, ring, segment):
    per_surface = RINGS * SEGMENTS
    return (per_surface if bottom else 0) + ring * SEGMENTS + (segment % SEGMENTS)


for ring in range(RINGS - 1):
    for segment in range(SEGMENTS):
        nxt = (segment + 1) % SEGMENTS
        faces.append((vid(False, ring, segment), vid(False, ring, nxt), vid(False, ring + 1, nxt), vid(False, ring + 1, segment)))
        faces.append((vid(True, ring, segment), vid(True, ring + 1, segment), vid(True, ring + 1, nxt), vid(True, ring, nxt)))

for segment in range(SEGMENTS):
    nxt = (segment + 1) % SEGMENTS
    faces.append((vid(False, 0, segment), vid(True, 0, segment), vid(True, 0, nxt), vid(False, 0, nxt)))
    faces.append((vid(False, RINGS - 1, segment), vid(False, RINGS - 1, nxt), vid(True, RINGS - 1, nxt), vid(True, RINGS - 1, segment)))

mesh = bpy.data.meshes.new("Mercenary_Gambeson_ShoulderUnderlayer_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
yoke = bpy.data.objects.new("Mercenary_Gambeson_ShoulderUnderlayer_LOD0", mesh)
collection.objects.link(yoke)
yoke["game_asset"] = True
yoke["part_category"] = "ClothedBody"
yoke["intentional_layer"] = True
yoke["source"] = "V16 single hidden sloped gambeson yoke; replaces disconnected pads"

gambeson = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]
mesh.materials.append(gambeson)
uv = mesh.uv_layers.new(name="UVMap")
for poly in mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True
    for loop_index in poly.loop_indices:
        co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = ((co.x + 0.42) / 0.84 * 2.2, (co.y + 0.18) / 0.44 * 1.35)

# Stable Rigify deformation: torso-dominant with a deliberately limited arm share.
groups = {name: yoke.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005",
    "DEF-upper_arm.L", "DEF-upper_arm.L.001",
    "DEF-upper_arm.R", "DEF-upper_arm.R.001",
)}
for vertex in mesh.vertices:
    x = vertex.co.x
    side_t = min(1.0, max(0.0, (abs(x) - 0.205) / 0.167))
    arm_total = 0.28 * side_t * side_t
    second = min(1.0, max(0.0, (abs(x) - 0.285) / 0.087))
    arm_1 = arm_total * (1.0 - 0.55 * second)
    arm_2 = arm_total - arm_1
    torso = 1.0 - arm_total
    groups["DEF-spine.004"].add([vertex.index], torso * 0.62, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], torso * 0.38, "REPLACE")
    suffix = "L" if x >= 0.0 else "R"
    if arm_1:
        groups[f"DEF-upper_arm.{suffix}"].add([vertex.index], arm_1, "REPLACE")
    if arm_2:
        groups[f"DEF-upper_arm.{suffix}.001"].add([vertex.index], arm_2, "REPLACE")

modifier = yoke.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_deform_preserve_volume = True
yoke.parent = rig
yoke.matrix_parent_inverse = rig.matrix_world.inverted()

if nonmanifold_edges(yoke):
    raise RuntimeError("Shoulder underlayer is not closed manifold")

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"


def render(name, location, target, ortho_scale=None, lens=72, resolution=(1200, 1200)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v16_underlayer_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("top_oblique", (1.55, -1.85, 3.25), (0.0, 0.02, 1.45), lens=76)
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
character_meshes = [obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None]
print("V16_UNDERLAYER_TRIANGLES", sum(triangle_count(obj) for obj in character_meshes))
print("V16_UNDERLAYER_MESHES", len(character_meshes))
print("V16_UNDERLAYER_YOKE", len(vertices), len(faces), triangle_count(yoke), nonmanifold_edges(yoke))
print("V16_UNDERLAYER_OUTPUT", OUTPUT)
