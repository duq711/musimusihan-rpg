"""Hide the v12 repair's sub-millimetre rear seam in the back projection.

Geometry and audited top-facing footprints remain byte-for-byte unchanged.
Only the four +Y rear wall faces receive the existing 4K back projection and
its exact reversed-X world-X/world-Z UV mapping.
"""

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v12.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13a.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
patches = bpy.data.objects["Mercenary_RearShoulder_NotchPatches_LOD0"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
back_material = bpy.data.materials["MAT_ReferenceProjection_Back_4K"]

slot_index = patches.data.materials.find(back_material.name)
if slot_index < 0:
    patches.data.materials.append(back_material)
    slot_index = len(patches.data.materials) - 1

# Match the projection bounds and inclusive subject rectangle used to texture
# the original donor.  The source projection is reversed in X.
donor_x = [vertex.co.x for vertex in donor.data.vertices]
xmin, xmax = min(donor_x), max(donor_x)
xspan = xmax - xmin
zmin, zmax = 0.0, 1.78
zspan = zmax - zmin
x0, x1, y0, y1 = (358.0, 3740.0, 239.0, 3854.0)
image_size = 4096.0
u0, u1 = x0 / image_size, x1 / image_size
v0, v1 = 1.0 - y1 / image_size, 1.0 - y0 / image_size

uv = patches.data.uv_layers.get("UVMap") or patches.data.uv_layers.new(name="UVMap")
rear_faces = []
for polygon in patches.data.polygons:
    if polygon.normal.y <= 0.95 or abs(polygon.normal.z) >= 0.05:
        continue
    polygon.material_index = slot_index
    rear_faces.append(polygon.index)
    for loop_index in polygon.loop_indices:
        coordinate = patches.data.vertices[patches.data.loops[loop_index].vertex_index].co
        norm_x = (coordinate.x - xmin) / xspan
        norm_z = (coordinate.z - zmin) / zspan
        uv.data[loop_index].uv = (
            u0 + (1.0 - norm_x) * (u1 - u0),
            v0 + norm_z * (v1 - v0),
        )
patches.data.update()

if rear_faces != [4, 10, 16, 22]:
    raise RuntimeError(f"Unexpected rear wall selection: {rear_faces}")


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13a_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top_close", (0.0, 0.0, 5.0), (0.0, 0.02, 1.49), ortho_scale=0.95, resolution=(1200, 900))
render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06)
render("back_close", (0.0, 5.2, 1.42), (0.0, 0.0, 1.42), ortho_scale=0.78, resolution=(1400, 700))
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

# Keep direct inspection framed on the back shoulder seam.
camera.data.type = "ORTHO"
camera.data.ortho_scale = 0.78
camera.location = (0.0, 5.2, 1.42)
look_at(camera, (0.0, 0.0, 1.42))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

print("V13_REAR_FACES", rear_faces)
print("V13_BACK_MATERIAL", back_material.name, slot_index)
print("V13_PROJECTION_X_BOUNDS", xmin, xmax)
print("V13_GEOMETRY_UNCHANGED", len(patches.data.vertices), len(patches.data.polygons))
print("WROTE", OUTPUT)
