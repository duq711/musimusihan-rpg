"""Read-only visual experiment for the v3 overlap cleanup.

Run against the saved v2 blend.  The script edits only the in-memory scene and
writes diagnostic renders to /tmp; it never saves the blend or production GLB.
"""

import math

import bmesh
import bpy
from mathutils import Vector


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
mesh = donor.data
bm = bmesh.new()
bm.from_mesh(mesh)
bm.faces.ensure_lookup_table()

remove = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    # Delete only donor faces that occupy the replacement head/neck's actual
    # bounding volume.  A wider X-only crop removes the surrounding cowl and
    # opens shoulder holes, so keep the mask tightly covered by the MPFB mesh.
    inside_replacement = (
        center.z > 1.49
        and ax < 0.154
        and -0.110 < center.y < 0.160
    )
    if inside_replacement:
        remove.append(face)

bmesh.ops.delete(bm, geom=remove, context="FACES")
bm.to_mesh(mesh)
bm.free()
mesh.update()

# The v2 replacement object accidentally retained a narrow torso rectangle
# because its first cut used only Z and X.  Reduce it to the actual head plus a
# short anatomical neck so it cannot overlap the donor chest/cowl.
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
head_mesh = head.data
head_bm = bmesh.new()
head_bm.from_mesh(head_mesh)
head_bm.faces.ensure_lookup_table()
remove_head_extra = []
for face in head_bm.faces:
    center = face.calc_center_median()
    keep_cranium = center.z > 1.49
    if not keep_cranium:
        remove_head_extra.append(face)
head_bm.faces.ensure_lookup_table()
bmesh.ops.delete(head_bm, geom=remove_head_extra, context="FACES")
head_bm.to_mesh(head_mesh)
head_bm.free()
head_mesh.update()

# Correct the classification order used by the v2 generator: high shoulder and
# sleeve faces must remain gambeson/leather instead of being labelled cowl.
for poly in mesh.polygons:
    center = poly.center
    ax = abs(center.x)
    if poly.material_index not in (0, 1) and center.z > 1.18 and ax > 0.24:
        if ax > 0.76:
            poly.material_index = 2  # exposed hands
        elif ax > 0.50 and center.z < 1.44:
            poly.material_index = 6  # bracers
        else:
            poly.material_index = 3  # padded sleeves/shoulders
mesh.update()

scene = bpy.context.scene
camera = scene.camera
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"


def render_ortho(path):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.06
    camera.location = (0.0, -5.2, 0.89)
    look_at(camera, (0.0, 0.0, 0.89))
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_back(path):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.06
    camera.location = (0.0, 5.2, 0.89)
    look_at(camera, (0.0, 0.0, 0.89))
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_portrait(path):
    camera.data.type = "PERSP"
    camera.data.lens = 92
    camera.location = (0.42, -1.42, 1.69)
    look_at(camera, (0.0, -0.03, 1.61))
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def render_three_quarter(path):
    camera.data.type = "PERSP"
    camera.data.lens = 72
    camera.location = (2.35, -3.15, 1.55)
    look_at(camera, (0.0, 0.0, 1.0))
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


render_ortho("/tmp/mercenary_cleanup_v3_front.png")
render_back("/tmp/mercenary_cleanup_v3_back.png")
render_three_quarter("/tmp/mercenary_cleanup_v3_three_quarter.png")
render_portrait("/tmp/mercenary_cleanup_v3_portrait.png")
print("REMOVED_DONOR_FACES", len(remove))
print("REMOVED_REPLACEMENT_EXTRA_FACES", len(remove_head_extra))
