"""Project original front/back 4K detail onto only the exposed top cloth.

This keeps v13b geometry and every original cowl side/front/back face.  Faces
using the synthetic safe top material are reclassified by their Y position to
the existing front/back reference materials and receive the same reversed-X
world-X/world-Z UV formula as the donor, avoiding a flat radial lining panel.
"""

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v13b.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v13d.blend"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
safe_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"]
front_material = bpy.data.materials["MAT_ReferenceProjection_Front_4K"]
back_material = bpy.data.materials["MAT_ReferenceProjection_Back_4K"]
objects = [
    bpy.data.objects[name]
    for name in (
        "Mercenary_Cowl_LayeredClean_LOD0",
        "Mercenary_UnderCowl_Yoke_LOD0",
        "Mercenary_InnerCowl_Liner_LOD0",
        "Mercenary_ShoulderCowl_Gussets_LOD0",
        "Mercenary_RearShoulder_NotchPatches_LOD0",
    )
]

donor_x = [vertex.co.x for vertex in donor.data.vertices]
xmin, xmax = min(donor_x), max(donor_x)
xspan = xmax - xmin
zmin, zmax = 0.0, 1.78
zspan = zmax - zmin
image_size = 4096.0
bboxes = {
    "front": (417.0, 3677.0, 241.0, 3860.0),
    "back": (358.0, 3740.0, 239.0, 3854.0),
}

counts = {}
for obj in objects:
    source_index = obj.data.materials.find(safe_material.name)
    if source_index < 0:
        raise RuntimeError(f"{obj.name} does not contain the safe top material")
    front_index = obj.data.materials.find(front_material.name)
    if front_index < 0:
        obj.data.materials.append(front_material)
        front_index = len(obj.data.materials) - 1
    back_index = obj.data.materials.find(back_material.name)
    if back_index < 0:
        obj.data.materials.append(back_material)
        back_index = len(obj.data.materials) - 1
    uv = obj.data.uv_layers.get("UVMap") or obj.data.uv_layers.new(name="UVMap")
    front_count = 0
    back_count = 0
    for polygon in obj.data.polygons:
        if polygon.material_index != source_index:
            continue
        side = "front" if polygon.center.y < 0.0 else "back"
        polygon.material_index = front_index if side == "front" else back_index
        if side == "front":
            front_count += 1
        else:
            back_count += 1
        x0, x1, y0, y1 = bboxes[side]
        u0, u1 = x0 / image_size, x1 / image_size
        v0, v1 = 1.0 - y1 / image_size, 1.0 - y0 / image_size
        for loop_index in polygon.loop_indices:
            coordinate = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
            norm_x = (coordinate.x - xmin) / xspan
            norm_z = (coordinate.z - zmin) / zspan
            uv.data[loop_index].uv = (
                u0 + (1.0 - norm_x) * (u1 - u0),
                v0 + norm_z * (v1 - v0),
            )
    obj.data.update()
    counts[obj.name] = {"front": front_count, "back": back_count}

if sum(value[side] for value in counts.values() for side in ("front", "back")) != 2667:
    raise RuntimeError(f"Unexpected projected top-face count: {counts}")


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
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v13d_{name}.png")
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

print("V13D_PROJECTED_TOP_COUNTS", counts)
print("V13D_PROJECTION_X_BOUNDS", xmin, xmax)
print("V13D_ORIGINAL_COWL_FRONT_BACK_FACES_PRESERVED", True)
print("WROTE", OUTPUT)
