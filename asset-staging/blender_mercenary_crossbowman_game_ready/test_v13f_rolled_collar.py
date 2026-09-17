"""Visual-only v13f: replace the flat inner-cowl annulus with cloth rolls."""

from pathlib import Path
import math

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13e.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13f.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
asset_collection = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"].users_collection[0]
material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]

old_liner = bpy.data.objects.get("Mercenary_InnerCowl_Liner_LOD0")
if old_liner:
    old_mesh = old_liner.data
    bpy.data.objects.remove(old_liner, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)

major_segments = 128
minor_segments = 14
ring_specs = (
    # rx, ry, center_y, z, tube radius, phase
    (0.113, 0.073, 0.026, 1.495, 0.0155, 0.20),
    (0.142, 0.097, 0.018, 1.474, 0.0180, 1.35),
    (0.170, 0.121, 0.008, 1.451, 0.0190, 2.20),
)
vertices = []
faces = []

for ring_index, (rx, ry, center_y, base_z, tube, phase) in enumerate(ring_specs):
    base = len(vertices)
    for major in range(major_segments):
        theta = 2.0 * math.pi * major / major_segments
        c, s = math.cos(theta), math.sin(theta)
        fold = 0.0032 * math.sin(3.0 * theta + phase) + 0.0016 * math.sin(7.0 * theta - phase)
        center = Vector((rx * c, center_y + ry * s, base_z + fold))
        outward = Vector((c / rx, s / ry, 0.0)).normalized()
        local_tube = tube * (1.0 + 0.08 * math.sin(5.0 * theta + phase))
        for minor in range(minor_segments):
            phi = 2.0 * math.pi * minor / minor_segments
            vertex = center + outward * (local_tube * math.cos(phi))
            vertex.z += local_tube * 0.72 * math.sin(phi)
            vertices.append(tuple(vertex))

    for major in range(major_segments):
        nxt_major = (major + 1) % major_segments
        for minor in range(minor_segments):
            nxt_minor = (minor + 1) % minor_segments
            a = base + major * minor_segments + minor
            b = base + nxt_major * minor_segments + minor
            c_index = base + nxt_major * minor_segments + nxt_minor
            d = base + major * minor_segments + nxt_minor
            faces.append((a, b, c_index, d))

mesh = bpy.data.meshes.new("Mercenary_InnerCowl_RolledCollar_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
collar = bpy.data.objects.new("Mercenary_InnerCowl_RolledCollar_LOD0", mesh)
asset_collection.objects.link(collar)
collar["game_asset"] = True
collar["part_category"] = "ClothedBody"
collar["intentional_layer"] = True
collar["source"] = "V13F compact closed rolled collar replacing flat radial liner"
mesh.materials.append(material)
uv = mesh.uv_layers.new(name="UVMap")
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True
    for loop_index in polygon.loop_indices:
        vertex_index = mesh.loops[loop_index].vertex_index
        within_ring = vertex_index % (major_segments * minor_segments)
        major = within_ring // minor_segments
        minor = within_ring % minor_segments
        uv.data[loop_index].uv = (major / major_segments * 3.0, minor / minor_segments)

upper_spine = collar.vertex_groups.new(name="DEF-spine.006")
lower_spine = collar.vertex_groups.new(name="DEF-spine.005")
for vertex in mesh.vertices:
    # Match the neighbouring cowl's neck/chest blend: the upper lip follows
    # the neck, while the lower rolls retain enough chest influence to avoid
    # opening a gap during head and torso animation.
    t = max(0.0, min(1.0, (vertex.co.z - 1.435) / 0.095))
    smooth_t = t * t * (3.0 - 2.0 * t)
    upper_weight = 0.45 + 0.55 * smooth_t
    upper_spine.add([vertex.index], upper_weight, "REPLACE")
    lower_spine.add([vertex.index], 1.0 - upper_weight, "REPLACE")
armature = collar.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
collar.parent = rig
collar.matrix_parent_inverse = rig.matrix_world.inverted()

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


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


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), 0.95, resolution=(1200, 900))
render("failure", (0.577, -0.577, 5.578), (0.0, 0.06, 1.02), lens=78, resolution=(1400, 1000))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("V13F_COLLAR", len(mesh.vertices), len(mesh.polygons), len(faces) * 2)
print("WROTE", OUTPUT)
