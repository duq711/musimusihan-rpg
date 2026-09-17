"""Diagnostic v9 variant with a lifted charcoal cowl base colour."""

from pathlib import Path
import math

import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v9i.blend"
TEXTURE = STAGING / "textures" / "cowl_wool_basecolor_4k_lifted.jpg"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene

# Keep the original 4K weave variation, but raise it from near-black to a
# readable charcoal so the covered shoulder cavity cannot resemble a hole.
source_image = bpy.data.images["cowl_wool_basecolor_4k.jpg"]
pixels = np.empty(len(source_image.pixels), dtype=np.float32)
source_image.pixels.foreach_get(pixels)
rgba = pixels.reshape((-1, 4))
rgba[:, :3] = np.clip(rgba[:, :3] * 4.2 + 0.040, 0.0, 1.0)

lifted = bpy.data.images.get("cowl_wool_basecolor_4k_lifted.jpg")
if lifted is None:
    lifted = bpy.data.images.new(
        "cowl_wool_basecolor_4k_lifted.jpg",
        width=source_image.size[0],
        height=source_image.size[1],
        alpha=False,
    )
lifted.colorspace_settings.name = source_image.colorspace_settings.name
lifted.pixels.foreach_set(rgba.reshape(-1))
lifted.filepath_raw = str(TEXTURE)
lifted.file_format = "JPEG"
lifted.save()

cowl = bpy.data.materials["MAT_CowlWool_Side_PBR_4K"]
cowl.node_tree.nodes["BaseColor_4K"].image = lifted

# Unify only the cowl surfaces that are the first visible layer from above.
# Projection-material islands in this annulus read as disconnected black slabs
# even though they are closed.  Keeping one charcoal cloth material and one
# planar UV direction makes the collar read as continuous fabric.
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
bm = bmesh.new()
bm.from_mesh(donor.data)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
uv_layer = bm.loops.layers.uv.get("UVMap") or bm.loops.layers.uv.new("UVMap")
bvh = BVHTree.FromBMesh(bm, epsilon=1.0e-7)
unified_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    radial = math.hypot(center.x, center.y - 0.055)
    if not (
        0.105 < radial < 0.405
        and 1.345 < center.z < 1.590
        and face.material_index in {0, 1, 4, 5}
        and face.normal.z > 0.08
    ):
        continue
    _location, _normal, index, _distance = bvh.ray_cast(
        Vector((center.x, center.y, 2.2)), Vector((0.0, 0.0, -1.0))
    )
    if index != face.index:
        continue
    unified_faces.append(face)

for face in unified_faces:
    face.material_index = 5
    face.smooth = True
    for loop in face.loops:
        coordinate = loop.vert.co
        loop[uv_layer].uv = (coordinate.x * 4.8, coordinate.y * 4.8)
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
print("UNIFIED_TOP_COWL_FACES", len(unified_faces))

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


def render(name, location, target, scale=None, lens=60, resolution=(1200, 1200)):
    if scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v9i_{name}.png")
    bpy.ops.render.render(write_still=True)


render("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), scale=1.95, resolution=(1500, 900))

# Approximate the user's steep 45-degree overhead viewer angle.
radius = 3.0
from_vertical = math.radians(24.0)
azimuth = math.radians(45.0)
target = Vector((0.0, 0.0, 1.05))
failure_location = target + Vector(
    (
        radius * math.sin(from_vertical) * math.cos(azimuth),
        -radius * math.sin(from_vertical) * math.sin(azimuth),
        radius * math.cos(from_vertical),
    )
)
render("failure", failure_location, target, lens=62, resolution=(1400, 1100))
render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), scale=2.06)
render("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.0), lens=72)

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))
print("WROTE", OUTPUT)
