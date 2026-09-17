"""Local A-D rear shoulder notch repair candidate built from v11.

This intentionally avoids a broad mantle: four tiny closed cloth wedges sit
inside the exact top-view silhouette notches found by the first-hit audit.
"""

from pathlib import Path
import math

import bmesh
import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v11.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v12c.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
asset_collection = yoke.users_collection[0]

# Audit-derived closed support bounds: xmin, xmax, ymin, ymax, top z.
supports = (
    ("A", 0.1166, 0.1737, 0.2076, 0.2281, 1.418),
    ("B", -0.1874, -0.1514, 0.1992, 0.2176, 1.460),
    ("C", -0.2339, -0.1978, 0.1865, 0.2028, 1.428),
    ("D", 0.2411, 0.2856, 0.1760, 0.1922, 1.424),
)

vertices = []
faces = []
support_ranges = []

for label, xmin, xmax, ymin, ymax, top_z in supports:
    start = len(vertices)
    width = xmax - xmin
    depth = ymax - ymin
    clip = min(width, depth) * 0.22
    ring_xy = (
        (xmin + clip, ymin),
        (xmax - clip, ymin),
        (xmax, ymin + clip),
        (xmax, ymax - clip),
        (xmax - clip, ymax),
        (xmin + clip, ymax),
        (xmin, ymax - clip),
        (xmin, ymin + clip),
    )
    # The top falls 1.5 mm toward the rear.  The closed underside is only
    # 2 mm lower so the rear wall cannot form a visible bar in back views.
    for x, y in ring_xy:
        rear_t = (y - ymin) / max(depth, 1.0e-6)
        vertices.append((x, y, top_z - 0.0015 * rear_t))
    for x, y in ring_xy:
        rear_t = (y - ymin) / max(depth, 1.0e-6)
        vertices.append((x, y, top_z - 0.0020 - 0.0015 * rear_t))

    faces.append(tuple(start + index for index in range(8)))
    faces.append(tuple(start + 8 + index for index in reversed(range(8))))
    for index in range(8):
        nxt = (index + 1) % 8
        faces.append((start + index, start + nxt, start + 8 + nxt, start + 8 + index))
    support_ranges.append((label, start, start + 16))

mesh = bpy.data.meshes.new("Mercenary_RearShoulder_NotchSupports_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
supports_obj = bpy.data.objects.new("Mercenary_RearShoulder_NotchSupports_LOD0", mesh)
asset_collection.objects.link(supports_obj)
supports_obj["game_asset"] = True
supports_obj["part_category"] = "ClothedBody"
supports_obj["intentional_layer"] = True
supports_obj["repair_scope"] = "four audited rear shoulder/cowl silhouette notches"

# Match the already visible under-cowl cloth instead of introducing a new
# flat grey or black material.
support_material = yoke.data.materials[0]
mesh.materials.append(support_material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    for loop_index in polygon.loop_indices:
        coordinate = mesh.vertices[mesh.loops[loop_index].vertex_index].co
        uv.data[loop_index].uv = (coordinate.x * 6.0, coordinate.y * 6.0)

# Use the same deform group as the existing hidden yoke.
yoke_groups = [group.name for group in yoke.vertex_groups]
deform_group_name = yoke_groups[0] if yoke_groups else "DEF-spine.004"
group = supports_obj.vertex_groups.new(name=deform_group_name)
group.add([vertex.index for vertex in mesh.vertices], 1.0, "REPLACE")
armature = supports_obj.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
supports_obj.parent = rig
supports_obj.matrix_parent_inverse = rig.matrix_world.inverted()

# Correct the left component of the legacy gusset mesh.  It was closed but
# all five faces pointed inward.
gussets = bpy.data.objects.get("Mercenary_ShoulderCowl_Gussets_LOD0")
if gussets is not None:
    bm = bmesh.new()
    bm.from_mesh(gussets.data)
    left_faces = [face for face in bm.faces if face.calc_center_median().x < 0.0]
    if left_faces:
        bmesh.ops.reverse_faces(bm, faces=left_faces, flip_multires=False)
    bm.to_mesh(gussets.data)
    bm.free()
    gussets.data.update()

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v12c_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), ortho_scale=1.95, resolution=(1500, 900))
radius = 4.7
elevation = math.radians(80.0)
azimuth = math.radians(45.0)
failure_location = (
    radius * math.cos(elevation) * math.sin(azimuth),
    -radius * math.cos(elevation) * math.cos(azimuth),
    0.95 + radius * math.sin(elevation),
)
render("failure", failure_location, (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V12C_SUPPORTS", support_ranges)
print("V12C_DEFORM_GROUP", deform_group_name)
print("WROTE", OUTPUT)
