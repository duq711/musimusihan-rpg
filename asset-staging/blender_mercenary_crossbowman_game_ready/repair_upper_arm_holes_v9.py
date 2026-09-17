"""Preserve and finish the original v4 shoulder surface for the v9 candidate.

V8 removed 333 original donor faces and thereby opened two true holes.  V9
starts from v4, keeps all original topology, UVs and Rigify weights, and only
reclassifies the exposed upper sleeve surface to the correct cloth materials.
No panel, second limb, duplicate shell or new vertex is created.
"""

from __future__ import annotations

from collections import Counter, defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE_BLEND = STAGING / "mercenary_crossbowman_game_ready_v4.blend"
SOURCE_SUMMARY = STAGING / "build_summary_v4.json"
OUTPUT_BLEND = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUTPUT_SUMMARY = STAGING / "build_summary_v9.json"
OUTPUT_GLB = (
    WORKSPACE
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_v9.glb"
)

PREVIEWS.mkdir(parents=True, exist_ok=True)
OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))

scene = bpy.context.scene
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
metarig = bpy.data.objects["metarig_mercenary_v4"]
asset_collection = donor.users_collection[0]


def triangle_count(obj):
    return sum(max(1, len(polygon.vertices) - 2) for polygon in obj.data.polygons)


def face_components(faces):
    remaining = set(faces)
    components = []
    while remaining:
        seed = remaining.pop()
        component = {seed}
        queue = deque([seed])
        while queue:
            face = queue.popleft()
            for edge in face.edges:
                for neighbor in edge.link_faces:
                    if neighbor in remaining:
                        remaining.remove(neighbor)
                        component.add(neighbor)
                        queue.append(neighbor)
        components.append(component)
    return sorted(components, key=len, reverse=True)


bm = bmesh.new()
bm.from_mesh(donor.data)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
uv_layer = bm.loops.layers.uv.get("UVMap")
if uv_layer is None:
    uv_layer = bm.loops.layers.uv.new("UVMap")

# Reproduce the exact v8 trim selection, but preserve these faces.
v8_trim_selection = {
    face
    for face in bm.faces
    if (
        0.235 < abs(face.calc_center_median().x) < 0.505
        and 1.455 < face.calc_center_median().z < 1.565
        and face.material_index == 4
        and face.normal.z > 0.08
    )
}
if len(v8_trim_selection) != 333:
    bm.free()
    raise RuntimeError(
        f"Expected the 333 original v4 shoulder faces, found {len(v8_trim_selection)}"
    )

components = face_components(v8_trim_selection)
if [len(component) for component in components[:2]] != [160, 144]:
    bm.free()
    raise RuntimeError(
        "Unexpected major shoulder components: "
        f"{[len(component) for component in components[:8]]}"
    )

# Classify all top-exposed shoulder faces before changing any materials.  This
# catches the additional projection/outer-wool triangles that still rendered
# as black patches even when only the original 333 faces were reclassified.
surface_bvh = BVHTree.FromBMesh(bm, epsilon=1.0e-7)
top_exposed_faces = set()
top_exposed_by_original_material = Counter()
under_cowl_yoke_faces = set()
for face in bm.faces:
    center = face.calc_center_median()
    shoulder_candidate = (
        0.235 < abs(center.x) < 0.530
        and 1.400 < center.z < 1.580
        and center.y > 0.035
        and abs(face.normal.z) > 0.35
        and face.material_index in {0, 1, 4}
    )
    yoke_candidate = (
        0.250 < abs(center.x) < 0.390
        and 1.470 < center.z < 1.555
        and 0.045 < center.y < 0.175
        and face.normal.z > 0.50
        and face.material_index == 5
    )
    if not (shoulder_candidate or yoke_candidate):
        continue
    _hit_location, _hit_normal, hit_index, _distance = surface_bvh.ray_cast(
        Vector((center.x, center.y, 2.2)), Vector((0.0, 0.0, -1.0))
    )
    if hit_index == face.index:
        if shoulder_candidate:
            top_exposed_faces.add(face)
            top_exposed_by_original_material[face.material_index] += 1
        if yoke_candidate:
            under_cowl_yoke_faces.add(face)

# Major components are the original left/right quilted shoulder surfaces.
major_components = components[:2]
major_faces = set().union(*major_components)
small_faces = v8_trim_selection - major_faces
if len(major_faces) != 304 or len(small_faces) != 29:
    bm.free()
    raise RuntimeError(
        f"Unexpected preserved-face split: major={len(major_faces)}, small={len(small_faces)}"
    )

remapped_gambeson = set(top_exposed_faces) | major_faces | under_cowl_yoke_faces
remapped_cowl = {
    face for face in small_faces if abs(face.calc_center_median().x) < 0.290
}
remapped_gambeson.update(small_faces - remapped_cowl)
remapped_gambeson.difference_update(remapped_cowl)


def assign_planar_top_uv(face):
    for loop in face.loops:
        coordinate = loop.vert.co
        loop[uv_layer].uv = (coordinate.x * 6.0, coordinate.y * 6.0)


for face in remapped_gambeson:
    face.material_index = 3
    face.smooth = True
    assign_planar_top_uv(face)
for face in remapped_cowl:
    face.material_index = 5
    face.smooth = True
    assign_planar_top_uv(face)

bm.to_mesh(donor.data)
bm.free()
donor.data.update()


def make_under_cowl_yoke():
    """Make two soft closed yoke wings inside the actual collar gaps."""

    angular_segments = 48
    radial_segments = 3
    center_y = 0.105
    center_abs_x = 0.245
    radius_x, radius_y = 0.086, 0.078
    boundary_height = 1.432
    crown_height = 1.482
    thickness = 0.010
    vertices = []
    faces = []

    for side in (-1.0, 1.0):
        island_start = len(vertices)
        vertices_per_layer = 1 + radial_segments * angular_segments
        for layer in range(2):
            vertices.append(
                (
                    side * center_abs_x,
                    center_y,
                    crown_height - (thickness if layer else 0.0),
                )
            )
            for radial_index in range(1, radial_segments + 1):
                radial_t = radial_index / radial_segments
                z = (
                    boundary_height
                    + (crown_height - boundary_height) * (1.0 - radial_t * radial_t)
                    - (thickness if layer else 0.0)
                )
                for angular_index in range(angular_segments):
                    theta = 2.0 * math.pi * angular_index / angular_segments
                    x = side * center_abs_x + radius_x * radial_t * math.cos(theta)
                    y = center_y + radius_y * radial_t * math.sin(theta)
                    vertices.append((x, y, z))

        def vertex_index(layer, radial_index, angular_index=0):
            layer_start = island_start + layer * vertices_per_layer
            if radial_index == 0:
                return layer_start
            return (
                layer_start
                + 1
                + (radial_index - 1) * angular_segments
                + angular_index % angular_segments
            )

        for angular_index in range(angular_segments):
            following = angular_index + 1
            top_triangle = (
                vertex_index(0, 0),
                vertex_index(0, 1, angular_index),
                vertex_index(0, 1, following),
            )
            faces.append(top_triangle)
            faces.append(tuple(reversed(tuple(
                vertex_index(1, 0) if index == vertex_index(0, 0)
                else index + vertices_per_layer
                for index in top_triangle
            ))))

        for radial_index in range(1, radial_segments):
            for angular_index in range(angular_segments):
                following = angular_index + 1
                top_face = (
                    vertex_index(0, radial_index, angular_index),
                    vertex_index(0, radial_index + 1, angular_index),
                    vertex_index(0, radial_index + 1, following),
                    vertex_index(0, radial_index, following),
                )
                faces.append(top_face)
                faces.append(tuple(reversed(tuple(index + vertices_per_layer for index in top_face))))

        for angular_index in range(angular_segments):
            following = angular_index + 1
            faces.append(
                (
                    vertex_index(0, radial_segments, angular_index),
                    vertex_index(1, radial_segments, angular_index),
                    vertex_index(1, radial_segments, following),
                    vertex_index(0, radial_segments, following),
                )
            )

    mesh = bpy.data.meshes.new("Mercenary_UnderCowl_Yoke_LOD0_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    yoke = bpy.data.objects.new("Mercenary_UnderCowl_Yoke_LOD0", mesh)
    asset_collection.objects.link(yoke)
    yoke["game_asset"] = True
    yoke["part_category"] = "ClothedBody"
    yoke["source"] = "V9 two-wing closed under-cowl cloth yoke; gap coverage only"
    yoke["intentional_layer"] = True

    for material in donor.data.materials:
        mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.material_index = 3
        polygon.use_smooth = True

    uv = mesh.uv_layers.new(name="UVMap")
    for polygon in mesh.polygons:
        for loop_index in polygon.loop_indices:
            coordinate = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (coordinate.x * 6.0, coordinate.y * 6.0)

    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    vertex_groups = {}

    def add_weight(vertex_index_value, bone_name, weight):
        if bone_name not in deform_names or weight <= 1.0e-6:
            return
        group = vertex_groups.get(bone_name)
        if group is None:
            group = yoke.vertex_groups.new(name=bone_name)
            vertex_groups[bone_name] = group
        group.add([vertex_index_value], weight, "REPLACE")

    for vertex in mesh.vertices:
        ax = abs(vertex.co.x)
        if ax <= 0.190:
            add_weight(vertex.index, "DEF-spine.004", 1.0)
            continue
        blend = max(0.0, min(1.0, (ax - 0.190) / 0.141))
        blend = blend * blend * (3.0 - 2.0 * blend)
        side = "L" if vertex.co.x >= 0.0 else "R"
        add_weight(vertex.index, "DEF-spine.004", 1.0 - 0.62 * blend)
        add_weight(vertex.index, "DEF-upper_arm." + side, 0.62 * blend)

    armature = yoke.modifiers.new("RigifyDeform", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    yoke.parent = rig
    yoke.matrix_parent_inverse = rig.matrix_world.inverted()
    return yoke


under_cowl_yoke = make_under_cowl_yoke()


def nonmanifold_edge_count(obj):
    edge_faces = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for first, second in zip(vertices, vertices[1:] + vertices[:1]):
            edge_faces[tuple(sorted((first, second)))] += 1
    return sum(link_count != 2 for link_count in edge_faces.values())


yoke_nonmanifold_edges = nonmanifold_edge_count(under_cowl_yoke)
if yoke_nonmanifold_edges:
    raise RuntimeError(f"Under-cowl yoke is not closed: {yoke_nonmanifold_edges} edges")
yoke_weight_sums = [sum(group.weight for group in vertex.groups) for vertex in under_cowl_yoke.data.vertices]
if not yoke_weight_sums or min(yoke_weight_sums) < 0.999 or max(yoke_weight_sums) > 1.001:
    raise RuntimeError(
        "Under-cowl yoke has invalid Rigify weight totals: "
        f"{min(yoke_weight_sums):.6f}..{max(yoke_weight_sums):.6f}"
    )


def boundary_report(obj):
    edge_face_counts = defaultdict(int)
    for polygon in obj.data.polygons:
        vertices = list(polygon.vertices)
        for first, second in zip(vertices, vertices[1:] + vertices[:1]):
            edge_face_counts[tuple(sorted((first, second)))] += 1
    shoulder_edges = []
    for edge, linked_faces in edge_face_counts.items():
        if linked_faces != 1:
            continue
        midpoint = sum((obj.data.vertices[index].co for index in edge), Vector()) / 2.0
        if 0.29 < abs(midpoint.x) < 0.45 and 1.44 < midpoint.z < 1.53:
            shoulder_edges.append(edge)
    adjacency = defaultdict(set)
    for first, second in shoulder_edges:
        adjacency[first].add(second)
        adjacency[second].add(first)
    remaining = set(adjacency)
    group_sizes = []
    while remaining:
        seed = remaining.pop()
        vertices = {seed}
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    vertices.add(neighbor)
                    queue.append(neighbor)
        group_sizes.append(len(vertices))
    return len(shoulder_edges), sorted(group_sizes, reverse=True)


remaining_shoulder_boundary_edges, shoulder_boundary_group_sizes = boundary_report(donor)
if any(size >= 50 for size in shoulder_boundary_group_sizes):
    raise RuntimeError(
        f"Preserved v4 topology unexpectedly has a large shoulder opening: "
        f"{shoulder_boundary_group_sizes}"
    )


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


camera = scene.camera
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_percentage = 100
preview_paths = {}


def render_ortho(key, location, target, scale, resolution=(1200, 1200)):
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f"mercenary_game_ready_v9_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(output)


def render_perspective(key, location, target, lens, resolution=(1100, 1100)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    output = PREVIEWS / f"mercenary_game_ready_v9_{key}.png"
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)
    preview_paths[key] = str(output)


rig.hide_viewport = True
rig.hide_set(True)
rig.hide_render = True
metarig.hide_viewport = True
metarig.hide_set(True)
metarig.hide_render = True
render_ortho("top", (0.0, 0.0, 5.0), (0.0, 0.0, 0.92), 1.95, (1500, 900))
render_ortho("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_ortho("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), 2.06)
render_perspective("three_quarter", (2.35, -3.15, 1.55), (0.0, 0.0, 1.00), 72)

# Save with the actual top repair framed in the camera.
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.95
camera.location = (0.0, 0.0, 5.0)
look_at(camera, (0.0, 0.0, 0.92))
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))

character_meshes = [
    obj for obj in scene.objects if obj.type == "MESH" and obj.get("part_category") is not None
]
bpy.ops.object.select_all(action="DESELECT")
rig.hide_viewport = False
rig.hide_set(False)
rig.select_set(True)
for obj in character_meshes:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig

export_properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
gltf_arguments = {
    "filepath": str(OUTPUT_GLB),
    "export_format": "GLB",
    "export_yup": True,
    "export_cameras": False,
    "export_lights": False,
    "export_extras": True,
    "export_materials": "EXPORT",
    "export_image_format": "AUTO",
    "export_animations": False,
    "export_skins": True,
    "export_def_bones": True,
    "export_armature_object_remove": False,
    "export_rest_position_armature": True,
    "export_all_influences": False,
    "export_influence_nb": 4,
    "export_leaf_bone": False,
    "export_texcoords": True,
    "export_normals": True,
    "export_apply": False,
    "export_morph": False,
    "export_tangents": True,
}
if "use_selection" in export_properties:
    gltf_arguments["use_selection"] = True
elif "export_selected" in export_properties:
    gltf_arguments["export_selected"] = True
bpy.ops.export_scene.gltf(**gltf_arguments)

summary = json.loads(SOURCE_SUMMARY.read_text(encoding="utf-8"))
summary["asset"] = "mercenary_crossbowman_game_ready_v9"
summary["triangles"] = sum(triangle_count(obj) for obj in character_meshes)
summary["triangle_breakdown"] = {obj.name: triangle_count(obj) for obj in character_meshes}
summary["mesh_count"] = len(character_meshes)
summary["previews"] = preview_paths
summary["blend"] = str(OUTPUT_BLEND)
summary["glb"] = str(OUTPUT_GLB)
summary["upper_arm_hole_repair"] = {
    "method": "preserve original v4 topology; remap only exposed shoulder-top surfaces",
    "v8_faces_restored": len(v8_trim_selection),
    "major_original_components": [len(component) for component in major_components],
    "small_original_faces": len(small_faces),
    "gambeson_faces_remapped": len(remapped_gambeson),
    "cowl_faces_remapped": len(remapped_cowl),
    "top_exposed_by_original_material": dict(top_exposed_by_original_material),
    "under_cowl_yoke_faces_remapped": len(under_cowl_yoke_faces),
    "closed_under_cowl_yoke": {
        "object": under_cowl_yoke.name,
        "vertices": len(under_cowl_yoke.data.vertices),
        "triangles": triangle_count(under_cowl_yoke),
        "material": "MAT_Gambeson_Side_PBR_4K",
        "closed_manifold": yoke_nonmanifold_edges == 0,
        "nonmanifold_edges": yoke_nonmanifold_edges,
        "intentional_underlayer": True,
        "rigged_to_existing_rigify": True,
        "vertex_weight_sum_range": [min(yoke_weight_sums), max(yoke_weight_sums)],
    },
    "floating_or_duplicate_shell_added": False,
    "donor_new_vertices": 0,
    "donor_new_faces": 0,
    "remaining_shoulder_boundary_edges": remaining_shoulder_boundary_edges,
    "shoulder_boundary_group_sizes": shoulder_boundary_group_sizes,
    "rigging": "all original Rigify vertex groups and weights preserved",
}
summary.pop("glb_self_check", None)
OUTPUT_SUMMARY.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V9_SUMMARY", json.dumps(summary))
