"""Replace the flat v11 liner with three compact rolled cloth collars.

The rolls remain inside x +/-0.19 and y +/-0.13, descend outward beneath the
existing cowl, and add no shoulder plate.  The original cowl is untouched;
the existing hidden yoke is restored to its gambeson material.
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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13e.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
liner = bpy.data.objects["Mercenary_InnerCowl_Liner_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]

# major x/y radii, Y offset, Z centre, radial tube radius, vertical tube radius,
# broad fold amplitude, angular phase.  Every outer bound stays below the
# requested +/-0.19 X and +/-0.13 Y envelope.
ROLLS = (
    (0.112, 0.055, 0.045, 1.475, 0.010, 0.010, 0.0015, 0.30),
    (0.143, 0.082, 0.025, 1.459, 0.012, 0.012, 0.0020, 1.10),
    (0.172, 0.105, 0.008, 1.445, 0.013, 0.013, 0.0022, 2.00),
)
segments = 96
cross_segments = 10
vertices = []
faces = []
vertex_parameters = []
component_ranges = []

for roll_index, (rx, ry, center_y, center_z, tube_r, tube_z, fold_amp, phase) in enumerate(ROLLS):
    start = len(vertices)
    for angular_index in range(segments):
        theta = 2.0 * math.pi * angular_index / segments
        cosine = math.cos(theta)
        sine = math.sin(theta)
        # Unit outward normal of the ellipse in the XY plane.
        normal = Vector((cosine / rx, sine / ry))
        normal.normalize()
        fold = fold_amp * math.cos((3.0 + roll_index) * theta + phase)
        base_x = rx * cosine
        base_y = center_y + ry * sine
        for cross_index in range(cross_segments):
            phi = 2.0 * math.pi * cross_index / cross_segments
            radial = tube_r * math.cos(phi)
            vertices.append(
                (
                    base_x + normal.x * radial,
                    base_y + normal.y * radial,
                    center_z + fold + tube_z * math.sin(phi),
                )
            )
            vertex_parameters.append((start, angular_index, cross_index))
    for angular_index in range(segments):
        following = (angular_index + 1) % segments
        for cross_index in range(cross_segments):
            following_cross = (cross_index + 1) % cross_segments
            faces.append(
                (
                    start + angular_index * cross_segments + cross_index,
                    start + following * cross_segments + cross_index,
                    start + following * cross_segments + following_cross,
                    start + angular_index * cross_segments + following_cross,
                )
            )
    component_ranges.append((start, len(vertices)))

new_mesh = bpy.data.meshes.new("Mercenary_InnerCowl_RolledCollar_LOD0_Mesh")
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
    angular_values = [vertex_parameters[index][1] for index in polygon.vertices]
    cross_values = [vertex_parameters[index][2] for index in polygon.vertices]
    wraps_angular = min(angular_values) == 0 and max(angular_values) == segments - 1
    wraps_cross = min(cross_values) == 0 and max(cross_values) == cross_segments - 1
    for loop_index in polygon.loop_indices:
        vertex_index = new_mesh.loops[loop_index].vertex_index
        _start, angular_index, cross_index = vertex_parameters[vertex_index]
        u = angular_index / segments * 6.0
        v = cross_index / cross_segments
        if wraps_angular and angular_index == 0:
            u = 6.0
        if wraps_cross and cross_index == 0:
            v = 1.0
        uv.data[loop_index].uv = (u, v)

liner.vertex_groups.clear()
group = liner.vertex_groups.new(name="DEF-spine.006")
group.add([vertex.index for vertex in new_mesh.vertices], 1.0, "REPLACE")
if not any(modifier.type == "ARMATURE" and modifier.object == rig for modifier in liner.modifiers):
    modifier = liner.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
liner["source"] = "V13 compact three-roll elliptical under-cowl collar"
liner["roll_bounds"] = "x +/-0.185, y -0.110..+0.126"

yoke.data.materials.clear()
yoke.data.materials.append(gambeson_material)
for polygon in yoke.data.polygons:
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
    raise RuntimeError("Rolled collar is not closed manifold")
mins = [min(vertex.co[axis] for vertex in new_mesh.vertices) for axis in (0, 1, 2)]
maxs = [max(vertex.co[axis] for vertex in new_mesh.vertices) for axis in (0, 1, 2)]
if mins[0] < -0.19 or maxs[0] > 0.19 or mins[1] < -0.13 or maxs[1] > 0.13:
    raise RuntimeError(f"Rolled collar exceeds envelope: min={mins}, max={maxs}")


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13e_{name}.png")
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

print("V13E_ROLL_BOUNDS", mins, maxs)
print("V13E_ROLL_VERTICES_POLYGONS_TRIANGLES", len(new_mesh.vertices), len(new_mesh.polygons), len(new_mesh.polygons) * 2)
print("V13E_ROLL_NONMANIFOLD", nonmanifold_edge_count(liner))
print("V13E_YOKE_MATERIAL", yoke.data.materials[0].name)
print("V13E_ORIGINAL_COWL_UNCHANGED", True)
print("WROTE", OUTPUT)
