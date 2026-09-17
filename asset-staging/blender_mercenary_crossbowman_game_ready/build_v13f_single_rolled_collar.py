"""Test a single compact rolled under-cowl collar on the v13b repair base.

The original cowl stays untouched.  The existing flat liner is replaced by one
closed elliptical roll tucked under the visible cowl.  All small shoulder-hole
helper pieces use the same gambeson material as the sleeves so that they do not
read as gray-green or black repair patches from high angles.
"""

import math
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13b.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13f.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
liner = bpy.data.objects["Mercenary_InnerCowl_Liner_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]

# A single cloth roll that hugs the neck/head and remains well inside the
# requested x +/-0.19, y +/-0.13 envelope.  The slight rear offset follows the
# existing cowl opening while staying hidden in standard eye-level views.
RX = 0.125
RY = 0.105
CENTER_Y = 0.010
CENTER_Z = 1.501
TUBE_R = 0.014
TUBE_Z = 0.013
SEGMENTS = 128
CROSS_SEGMENTS = 12

vertices = []
faces = []
parameters = []
for angular_index in range(SEGMENTS):
    theta = 2.0 * math.pi * angular_index / SEGMENTS
    cosine = math.cos(theta)
    sine = math.sin(theta)
    normal = Vector((cosine / RX, sine / RY))
    normal.normalize()
    # Low-amplitude asymmetric folds keep the roll from reading as a rigid
    # geometric torus while preserving a closed, predictable silhouette.
    fold = 0.0018 * math.cos(3.0 * theta + 0.55) + 0.0008 * math.cos(7.0 * theta - 0.4)
    base_x = RX * cosine
    base_y = CENTER_Y + RY * sine
    for cross_index in range(CROSS_SEGMENTS):
        phi = 2.0 * math.pi * cross_index / CROSS_SEGMENTS
        radial = TUBE_R * math.cos(phi)
        vertices.append(
            (
                base_x + normal.x * radial,
                base_y + normal.y * radial,
                CENTER_Z + fold + TUBE_Z * math.sin(phi),
            )
        )
        parameters.append((angular_index, cross_index))

for angular_index in range(SEGMENTS):
    following = (angular_index + 1) % SEGMENTS
    for cross_index in range(CROSS_SEGMENTS):
        following_cross = (cross_index + 1) % CROSS_SEGMENTS
        faces.append(
            (
                angular_index * CROSS_SEGMENTS + cross_index,
                following * CROSS_SEGMENTS + cross_index,
                following * CROSS_SEGMENTS + following_cross,
                angular_index * CROSS_SEGMENTS + following_cross,
            )
        )

new_mesh = bpy.data.meshes.new("Mercenary_InnerCowl_SingleRolledCollar_LOD0_Mesh")
new_mesh.from_pydata(vertices, [], faces)
new_mesh.update()
old_mesh = liner.data
liner.data = new_mesh
bpy.data.meshes.remove(old_mesh)
new_mesh.materials.append(cloth_material)

uv = new_mesh.uv_layers.new(name="UVMap")
for polygon in new_mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    angular_values = [parameters[index][0] for index in polygon.vertices]
    cross_values = [parameters[index][1] for index in polygon.vertices]
    wraps_angular = min(angular_values) == 0 and max(angular_values) == SEGMENTS - 1
    wraps_cross = min(cross_values) == 0 and max(cross_values) == CROSS_SEGMENTS - 1
    for loop_index in polygon.loop_indices:
        vertex_index = new_mesh.loops[loop_index].vertex_index
        angular_index, cross_index = parameters[vertex_index]
        u = angular_index / SEGMENTS * 5.0
        v = cross_index / CROSS_SEGMENTS
        if wraps_angular and angular_index == 0:
            u = 5.0
        if wraps_cross and cross_index == 0:
            v = 1.0
        uv.data[loop_index].uv = (u, v)

liner.vertex_groups.clear()
# Match the original flat liner's stable upper-spine attachment.  This avoids
# a collar/head separation in animation and keeps total deform weight at 1.0.
group = liner.vertex_groups.new(name="DEF-spine.006")
group.add([vertex.index for vertex in new_mesh.vertices], 1.0, "REPLACE")
if not any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in liner.modifiers):
    modifier = liner.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
liner["source"] = "V13f compact single-roll elliptical under-cowl collar"

# These are only hidden support surfaces.  Keep them visually continuous with
# the quilted shoulders rather than assigning a dark or greenish patch material.
helper_names = (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearCowl_NotchPatches_LOD0",
)
for name in helper_names:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    obj.data.materials.clear()
    obj.data.materials.append(gambeson_material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True


def nonmanifold_edge_count(obj):
    counts = defaultdict(int)
    for polygon in obj.data.polygons:
        points = list(polygon.vertices)
        for first, second in zip(points, points[1:] + points[:1]):
            counts[tuple(sorted((first, second)))] += 1
    return sum(count != 2 for count in counts.values())


if nonmanifold_edge_count(liner) != 0:
    raise RuntimeError("Single rolled collar is not closed manifold")
mins = [min(vertex.co[axis] for vertex in new_mesh.vertices) for axis in (0, 1, 2)]
maxs = [max(vertex.co[axis] for vertex in new_mesh.vertices) for axis in (0, 1, 2)]
if mins[0] < -0.19 or maxs[0] > 0.19 or mins[1] < -0.13 or maxs[1] > 0.13:
    raise RuntimeError(f"Single rolled collar exceeds envelope: min={mins}, max={maxs}")


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13f_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
for degrees in (0, 45, 90, 180, 270):
    azimuth = math.radians(degrees)
    location = (
        radius * math.cos(elevation) * math.sin(azimuth),
        -radius * math.cos(elevation) * math.cos(azimuth),
        0.95 + radius * math.sin(elevation),
    )
    render(
        "failure" if degrees == 45 else f"high_{degrees:03d}",
        location,
        (0.0, 0.06, 1.02),
        lens=78,
        resolution=(1400, 1000) if degrees == 45 else (900, 700),
    )
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

camera.data.type = "PERSP"
camera.data.lens = 78
azimuth = math.radians(45.0)
camera.location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
look_at(camera, (0.0, 0.06, 1.02))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V13F_ROLL_BOUNDS", mins, maxs)
print("V13F_ROLL_VERTICES_POLYGONS_TRIANGLES", len(new_mesh.vertices), len(new_mesh.polygons), len(new_mesh.polygons) * 2)
print("V13F_ROLL_NONMANIFOLD", nonmanifold_edge_count(liner))
print("V13F_HELPER_MATERIALS", {name: bpy.data.objects[name].data.materials[0].name for name in helper_names if name in bpy.data.objects})
print("V13F_ORIGINAL_COWL_UNCHANGED", True)
print("WROTE", OUTPUT)
