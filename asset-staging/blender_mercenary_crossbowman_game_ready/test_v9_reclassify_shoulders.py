"""Prototype a topology-preserving shoulder fix from v4 and render QA views."""

from __future__ import annotations

from collections import deque
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
PREVIEWS.mkdir(parents=True, exist_ok=True)

donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
metarig = bpy.data.objects["metarig_mercenary_v4"]

bm = bmesh.new()
bm.from_mesh(donor.data)
bm.faces.ensure_lookup_table()

selected = {
    face
    for face in bm.faces
    if 0.235 < abs(face.calc_center_median().x) < 0.505
    and 1.455 < face.calc_center_median().z < 1.565
    and face.material_index == 4
    and face.normal.z > 0.08
}
if sum(max(1, len(face.verts) - 2) for face in selected) != 333:
    raise RuntimeError("The v4 shoulder selection no longer matches 333 triangles")

unseen = set(selected)
components = []
while unseen:
    seed = unseen.pop()
    component = {seed}
    queue = deque([seed])
    while queue:
        face = queue.popleft()
        for edge in face.edges:
            for neighbor in edge.link_faces:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
    components.append(component)

components.sort(key=lambda faces: sum(max(1, len(face.verts) - 2) for face in faces), reverse=True)
pbr_face_indices = set()
for component in components:
    triangle_count = sum(max(1, len(face.verts) - 2) for face in component)
    centers = [face.calc_center_median() for face in component]
    mean_abs_x = sum(abs(center.x) for center in centers) / len(centers)
    target_material = 3 if triangle_count >= 100 or mean_abs_x >= 0.29 else 5
    for face in component:
        face.material_index = target_material
        if target_material == 3:
            pbr_face_indices.add(face.index)

    # Preserve the original patch border, UVs and Rigify vertex groups. Only
    # relax internal vertices of the two large sleeve-top patches.
    if triangle_count >= 100:
        component_vertices = {vertex for face in component for vertex in face.verts}
        boundary_vertices = {
            vertex
            for vertex in component_vertices
            if any(linked_face not in component for linked_face in vertex.link_faces)
        }
        internal_vertices = list(component_vertices - boundary_vertices)
        for _iteration in range(3):
            if internal_vertices:
                bmesh.ops.smooth_vert(
                    bm,
                    verts=internal_vertices,
                    factor=0.35,
                    use_axis_x=False,
                    use_axis_y=True,
                    use_axis_z=True,
                )

bmesh.ops.recalc_face_normals(bm, faces=list(selected))

# The original image-to-3D donor also assigned several shoulder-top facets to
# planar front/back and dark outer-wool materials. From an overhead view these
# facets read as black voids even though geometry exists. Keep their topology
# and UVs, but make the padded sleeve surface continuous across the top.
for face in bm.faces:
    center = face.calc_center_median()
    if not (0.275 <= abs(center.x) < 0.430 and 1.395 < center.z < 1.585):
        continue
    if center.y <= 0.0 or abs(face.normal.z) < 0.25:
        continue
    if face.material_index not in {0, 1, 4, 5}:
        continue
    face.material_index = 3
    pbr_face_indices.add(face.index)

bm.to_mesh(donor.data)
bm.free()
donor.data.update()

# Reclassified faces need the same dominant-axis tiled UVs as the existing
# game-ready gambeson, rather than the front/back projection UVs that made the
# shoulder surface look like a flat beige smear.
donor_uv = donor.data.uv_layers.get("UVMap")
if donor_uv is None:
    donor_uv = donor.data.uv_layers.new(name="UVMap")
for polygon_index in sorted(pbr_face_indices):
    polygon = donor.data.polygons[polygon_index]
    normal = polygon.normal
    absolute = (abs(normal.x), abs(normal.y), abs(normal.z))
    for loop_index in polygon.loop_indices:
        coordinate = donor.data.vertices[donor.data.loops[loop_index].vertex_index].co
        if absolute[0] >= absolute[1] and absolute[0] >= absolute[2]:
            box_u, box_v = coordinate.y, coordinate.z
        elif absolute[1] >= absolute[2]:
            box_u, box_v = coordinate.x, coordinate.z
        else:
            box_u, box_v = coordinate.x, coordinate.y
        donor_uv.data[loop_index].uv = (box_u * 6.0, box_v * 6.0)
donor.data.update()


def make_closed_under_cowl_yoke():
    """Add a recessed, closed wool yoke below the cowl to block collar voids."""
    angular_segments = 64
    radial_segments = 5
    inner_rx, inner_ry = 0.095, 0.078
    outer_rx, outer_ry = 0.335, 0.190
    thickness = 0.008
    vertices = []
    faces = []

    def index(layer, radial, angular):
        return layer * (radial_segments + 1) * angular_segments + radial * angular_segments + angular

    for layer in range(2):
        for radial in range(radial_segments + 1):
            t = radial / radial_segments
            rx = inner_rx * (1.0 - t) + outer_rx * t
            ry = inner_ry * (1.0 - t) + outer_ry * t
            top_z = 1.462 - 0.036 * t - 0.006 * t * t
            z = top_z if layer == 0 else top_z - thickness
            for angular in range(angular_segments):
                theta = 2.0 * math.pi * angular / angular_segments
                vertices.append((rx * math.cos(theta), ry * math.sin(theta), z))

    for radial in range(radial_segments):
        for angular in range(angular_segments):
            following = (angular + 1) % angular_segments
            top = (
                index(0, radial, angular),
                index(0, radial + 1, angular),
                index(0, radial + 1, following),
                index(0, radial, following),
            )
            faces.append(top)
            # Explicit bottom order keeps normals facing away from the volume.
            faces.append(
                (
                    index(1, radial, following),
                    index(1, radial + 1, following),
                    index(1, radial + 1, angular),
                    index(1, radial, angular),
                )
            )

    for angular in range(angular_segments):
        following = (angular + 1) % angular_segments
        faces.append(
            (
                index(0, 0, following),
                index(0, 0, angular),
                index(1, 0, angular),
                index(1, 0, following),
            )
        )
        faces.append(
            (
                index(0, radial_segments, angular),
                index(0, radial_segments, following),
                index(1, radial_segments, following),
                index(1, radial_segments, angular),
            )
        )

    mesh = bpy.data.meshes.new("Mercenary_UnderCowlYoke_LOD0_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    yoke = bpy.data.objects.new("Mercenary_UnderCowlYoke_LOD0", mesh)
    donor.users_collection[0].objects.link(yoke)
    yoke["game_asset"] = True
    yoke["part_category"] = "ClothedBody"
    yoke["source"] = "Topology-safe recessed collar underlayer"
    mesh.materials.append(donor.data.materials[4])

    uv_layer = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            coordinate = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv_layer.data[loop_index].uv = (0.5 + coordinate.x * 3.0, 0.5 + coordinate.y * 3.0)
        polygon.use_smooth = True

    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    group_cache = {}

    def add_weight(vertex_index, name, weight):
        if name not in deform_names or weight <= 0.0:
            return
        group = group_cache.get(name)
        if group is None:
            group = yoke.vertex_groups.new(name=name)
            group_cache[name] = group
        group.add([vertex_index], weight, "REPLACE")

    for vertex in mesh.vertices:
        ax = abs(vertex.co.x)
        side = "L" if vertex.co.x >= 0.0 else "R"
        blend = max(0.0, min(1.0, (ax - 0.15) / 0.17))
        blend = blend * blend * (3.0 - 2.0 * blend)
        add_weight(vertex.index, "DEF-spine.004", 1.0 - 0.75 * blend)
        add_weight(vertex.index, "DEF-upper_arm." + side, 0.75 * blend)

    modifier = yoke.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    yoke.parent = rig
    yoke.matrix_parent_inverse = rig.matrix_world.inverted()
    return yoke


def make_closed_under_cowl_pads():
    """Place two recessed rounded wool pads only beneath the collar gaps."""
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    pads = []
    for side_sign, side_name in ((1.0, "L"), (-1.0, "R")):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=32,
            ring_count=16,
            location=(side_sign * 0.245, 0.075, 1.428),
            scale=(0.135, 0.105, 0.040),
        )
        pad = bpy.context.object
        pad.name = f"Mercenary_UnderCowlPad_{side_name}_LOD0"
        pad.data.name = pad.name + "_Mesh"
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        pad["game_asset"] = True
        pad["part_category"] = "ClothedBody"
        pad["source"] = "Closed recessed wool pad below collar gap"
        pad.data.materials.append(donor.data.materials[4])
        for polygon in pad.data.polygons:
            polygon.use_smooth = True

        for bone_name, weight in (
            ("DEF-spine.004", 0.38),
            ("DEF-upper_arm." + side_name, 0.62),
        ):
            if bone_name in deform_names:
                group = pad.vertex_groups.new(name=bone_name)
                group.add(range(len(pad.data.vertices)), weight, "REPLACE")

        modifier = pad.modifiers.new("RigifyDeform", "ARMATURE")
        modifier.object = rig
        modifier.use_deform_preserve_volume = True
        pad.parent = rig
        pad.matrix_parent_inverse = rig.matrix_world.inverted()
        pads.append(pad)
    return pads


# The topology-preserving v9 candidate intentionally adds no overlay geometry.

rig.hide_set(True)
rig.hide_viewport = True
rig.hide_render = True
metarig.hide_set(True)
metarig.hide_viewport = True
metarig.hide_render = True

scene = bpy.context.scene
camera = scene.camera
scene.render.resolution_percentage = 100


def look_at(location, target):
    camera.location = location
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat("-Z", "Y").to_euler()


def render_perspective(name, location, target, lens=65, resolution=(1200, 1200)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    look_at(location, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.filepath = str(PREVIEWS / f"diagnostic_v9g_{name}.png")
    bpy.ops.render.render(write_still=True)


def render_top():
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 2.10
    camera.location = (0.0, 0.03, 4.2)
    camera.rotation_euler = (0.0, 0.0, 0.0)
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 720
    scene.render.filepath = str(PREVIEWS / "diagnostic_v9g_top.png")
    bpy.ops.render.render(write_still=True)


render_top()
render_perspective("top_oblique", (1.65, -2.05, 3.35), (0.0, 0.03, 1.24), 70, (1400, 1000))
render_perspective("front", (0.0, -4.8, 0.98), (0.0, 0.0, 0.98), 78)
render_perspective("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.00), 72)

bpy.ops.wm.save_as_mainfile(filepath=str(STAGING / "mercenary_crossbowman_game_ready_v9g.blend"))
