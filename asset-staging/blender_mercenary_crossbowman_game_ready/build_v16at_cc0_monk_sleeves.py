"""Build clean gambeson upper sleeves from a CC0 MakeHuman monk robe.

Only the already-reconstructed rectangular V16ZB sleeves are replaced.  The
underlying TripoSR donor in V16ZO already has exactly the torn upper-arm faces
removed, so torso, forearms, hands, face, cowl, and Rigify rig remain intact.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16zo_realistic_singlepiece_cowl.blend"
ANATOMY_SOURCE = STAGING / "cc0_makehuman_suits02_candidate/clothes/donitz_monk_robe/Monks_Robe.obj"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16at_cc0_monk_sleeves_candidate.blend"
REPORT = STAGING / "v16at_cc0_monk_sleeves_report.json"

OLD_SLEEVES = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
NEW_SLEEVES = "Mercenary_CC0MonkGambesonUpperSleeves_v16at_LOD0"
BODY_NAME = "Monks_Robe"


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        vertices = list(poly.vertices)
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def build_weight_samples(obj: bpy.types.Object):
    group_names = {group.index: group.name for group in obj.vertex_groups}
    samples = []
    for vertex in obj.data.vertices:
        weights = {
            group_names[item.group]: item.weight
            for item in vertex.groups
            if item.group in group_names and item.weight > 1.0e-7
        }
        if weights:
            samples.append((vertex.co.copy(), weights))
    tree = KDTree(len(samples))
    for index, (position, _weights) in enumerate(samples):
        tree.insert(position, index)
    tree.balance()
    return samples, tree


def transfer_weights(obj: bpy.types.Object, samples, tree) -> tuple[float, float]:
    groups = {}
    sums = []
    for vertex in obj.data.vertices:
        _position, sample_index, _distance = tree.find(vertex.co)
        ranked = sorted(
            samples[sample_index][1].items(), key=lambda item: item[1], reverse=True
        )[:4]
        total = sum(weight for _name, weight in ranked)
        if total < 1.0e-9:
            ranked = [("DEF-upper_arm.L" if vertex.co.x >= 0.0 else "DEF-upper_arm.R", 1.0)]
            total = 1.0
        normalised = [(name, weight / total) for name, weight in ranked]
        for name, weight in normalised:
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([vertex.index], weight, "REPLACE")
        sums.append(sum(weight for _name, weight in normalised))
    return min(sums), max(sums)


def face_components(face_indices, polygons):
    vertex_to_faces = defaultdict(set)
    for face_index in face_indices:
        for vertex_index in polygons[face_index].vertices:
            vertex_to_faces[vertex_index].add(face_index)
    unseen = set(face_indices)
    components = []
    while unseen:
        component = set()
        queue = deque([unseen.pop()])
        while queue:
            face_index = queue.popleft()
            component.add(face_index)
            neighbours = set()
            for vertex_index in polygons[face_index].vertices:
                neighbours.update(vertex_to_faces[vertex_index])
            found = neighbours & unseen
            unseen.difference_update(found)
            queue.extend(found)
        components.append(component)
    return sorted(components, key=len, reverse=True)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
old_sleeves = bpy.data.objects[OLD_SLEEVES]
asset_collection = old_sleeves.users_collection[0]

# V16ZB removed the obvious upper-facing fins.  A few lower armpit/cuff scan
# shards remain below that old z-threshold; remove only faces fully inside the
# volume that the new sleeves cover.  Torso (|x| < .15), forearms (|x| > .56),
# hands and every other body region are left untouched.
donor_bm = bmesh.new()
donor_bm.from_mesh(donor.data)
additional_torn_faces = []
for face in donor_bm.faces:
    center = face.calc_center_median()
    side = 1 if center.x >= 0.0 else -1
    shoulder = Vector((side * 0.166, 0.024, 1.425))
    cuff = Vector((side * 0.535, 0.084, 1.425))
    axis = cuff - shoulder
    t = (center - shoulder).dot(axis) / axis.length_squared
    radial = (center - shoulder - axis * t).length
    if (
        0.0 <= t <= 1.045
        and 0.145 < abs(center.x) < 0.555
        and 1.275 < center.z < 1.505
        and radial < 0.145
    ):
        additional_torn_faces.append(face)
additional_torn_donor_faces = len(additional_torn_faces)
if additional_torn_faces:
    bmesh.ops.delete(donor_bm, geom=additional_torn_faces, context="FACES")
    loose = [vertex for vertex in donor_bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(donor_bm, geom=loose, context="VERTS")
donor_bm.to_mesh(donor.data)
donor_bm.free()
donor.data.update()
donor["v16at_additional_torn_upper_arm_faces_removed"] = additional_torn_donor_faces

# Preserve the proven Rigify deformation of V16ZB before deleting its blocky
# geometry.  Nearest transfer keeps the replacement bound to the same bones.
weight_samples, weight_tree = build_weight_samples(old_sleeves)
old_sleeve_triangles = triangle_count(old_sleeves)
old_sleeve_mesh = old_sleeves.data
bpy.data.objects.remove(old_sleeves, do_unlink=True)
if old_sleeve_mesh.users == 0:
    bpy.data.meshes.remove(old_sleeve_mesh)

# Import only the CC0 monk robe as an unsaved construction source.  Normalize
# MakeHuman's OBJ coordinates to a centred 1.78 m Blender character.
before_import = set(bpy.data.objects)
bpy.ops.wm.obj_import(
    filepath=str(ANATOMY_SOURCE), forward_axis="NEGATIVE_Z", up_axis="Y"
)
imported = [
    obj for obj in bpy.data.objects if obj not in before_import and obj.type == "MESH"
]
if len(imported) != 1:
    raise RuntimeError(f"Expected one CC0 monk robe mesh, found {len(imported)}")
anatomy = imported[0]
anatomy.name = BODY_NAME
source_points_raw = [anatomy.matrix_world @ vertex.co for vertex in anatomy.data.vertices]
source_min = Vector(tuple(min(point[i] for point in source_points_raw) for i in range(3)))
source_max = Vector(tuple(max(point[i] for point in source_points_raw) for i in range(3)))
source_scale = 1.78 / (source_max.z - source_min.z)
source_center = 0.5 * (source_min + source_max)
source_points = [
    Vector((
        (point.x - source_center.x) * source_scale,
        (point.y - source_center.y) * source_scale,
        (point.z - source_min.z) * source_scale,
    ))
    for point in source_points_raw
]

# The robe is a relaxed A-pose.  Its own cloth sleeve surface is rotated and
# length-fitted onto the current Rigify T-pose upper-arm axis.
source_axes = {}
target_axes = {}
for side in (-1, 1):
    source_shoulder = Vector((side * 0.245, 0.000, 1.535))
    source_elbow = Vector((side * 0.445, 0.015, 1.295))
    target_shoulder = Vector((side * 0.166, 0.024, 1.425))
    target_cuff = Vector((side * 0.535, 0.084, 1.425))
    source_axes[side] = (source_shoulder, source_elbow)
    target_axes[side] = (target_shoulder, target_cuff)

# Select the largest connected cloth surface patch for each upper arm.
selected_by_side = {}
for side in (-1, 1):
    shoulder, elbow = source_axes[side]
    axis = elbow - shoulder
    axis_length = axis.length
    axis_unit = axis.normalized()
    candidates = []
    for polygon in anatomy.data.polygons:
        center = sum((source_points[index] for index in polygon.vertices), Vector()) / len(polygon.vertices)
        if side * center.x < 0.185:
            continue
        relative = center - shoulder
        t = relative.dot(axis_unit) / axis_length
        radial = (relative - axis_unit * relative.dot(axis_unit)).length
        if not (0.025 <= t <= 1.02 and radial <= 0.155):
            continue
        # Reject cape/torso polygons whose centres happen to lie near the arm.
        safe = True
        for vertex_index in polygon.vertices:
            point = source_points[vertex_index]
            vertex_relative = point - shoulder
            vertex_t = vertex_relative.dot(axis_unit) / axis_length
            vertex_radial = (
                vertex_relative - axis_unit * vertex_relative.dot(axis_unit)
            ).length
            if side * point.x < 0.130 or not (-0.08 <= vertex_t <= 1.10) or vertex_radial > 0.205:
                safe = False
                break
        if safe:
            candidates.append(polygon.index)
    components = face_components(candidates, anatomy.data.polygons)
    if not components:
        raise RuntimeError(f"No anatomical upper-arm faces selected for side {side}")
    selected_by_side[side] = components[0]

selected_faces = selected_by_side[-1] | selected_by_side[1]
used_source_vertices = sorted({
    vertex_index
    for face_index in selected_faces
    for vertex_index in anatomy.data.polygons[face_index].vertices
})
source_to_new = {source_index: new_index for new_index, source_index in enumerate(used_source_vertices)}


def transform_source_point(point: Vector) -> Vector:
    side = 1 if point.x >= 0.0 else -1
    source_shoulder, source_elbow = source_axes[side]
    target_shoulder, target_cuff = target_axes[side]
    source_axis = source_elbow - source_shoulder
    target_axis = target_cuff - target_shoulder
    source_unit = source_axis.normalized()
    target_unit = target_axis.normalized()
    rotation = source_unit.rotation_difference(target_unit)
    relative = point - source_shoulder
    longitudinal = relative.dot(source_unit)
    radial = relative - source_unit * longitudinal
    # Length is fitted to the current character, while the robe's transverse
    # cloth fullness remains intact.
    return (
        target_shoulder
        + target_unit * (longitudinal * target_axis.length / source_axis.length)
        + (rotation @ radial) * 1.08
    )


vertices = [transform_source_point(source_points[index]) for index in used_source_vertices]
faces = [
    tuple(source_to_new[index] for index in anatomy.data.polygons[face_index].vertices)
    for face_index in sorted(selected_faces)
]

mesh = bpy.data.meshes.new("Mercenary_CC0MonkGambesonUpperSleeves_v16at_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
sleeves = bpy.data.objects.new(NEW_SLEEVES, mesh)
asset_collection.objects.link(sleeves)

# Align the irregular polygon cut to two clean planes perpendicular to the
# target arm.  This retains the sampled anatomical surface while removing the
# saw-tooth tabs caused by selecting whole source quads at the two cuts.
edge_use = defaultdict(int)
for polygon in mesh.polygons:
    ids = list(polygon.vertices)
    for a, b in zip(ids, ids[1:] + ids[:1]):
        edge_use[tuple(sorted((a, b)))] += 1
boundary_vertices = {
    vertex_index
    for edge, count in edge_use.items()
    if count == 1
    for vertex_index in edge
}
boundary_adjacency = defaultdict(set)
for (a, b), count in edge_use.items():
    if count == 1:
        boundary_adjacency[a].add(b)
        boundary_adjacency[b].add(a)
boundary_components = []
boundary_component_sets = []
unseen_boundary = set(boundary_vertices)
while unseen_boundary:
    component = set()
    queue = deque([unseen_boundary.pop()])
    while queue:
        vertex_index = queue.popleft()
        component.add(vertex_index)
        found = boundary_adjacency[vertex_index] & unseen_boundary
        unseen_boundary.difference_update(found)
        queue.extend(found)
    component_ts = []
    for vertex_index in component:
        point = mesh.vertices[vertex_index].co
        side = 1 if point.x >= 0.0 else -1
        shoulder, cuff = target_axes[side]
        axis = cuff - shoulder
        component_ts.append((point - shoulder).dot(axis) / axis.length_squared)
    boundary_components.append({
        "vertices": len(component),
        "t_min": min(component_ts),
        "t_max": max(component_ts),
    })
    boundary_component_sets.append((component, min(component_ts), max(component_ts)))
print("V16AT_BOUNDARY_COMPONENTS=" + json.dumps(boundary_components, sort_keys=True))

# The MakeHuman shoulder is welded into the torso, so extracting only the arm
# leaves one small, closed armpit opening on each side.  Fill only those two
# components (they span the first half of the sleeve); keep the true cuff loops
# open for Solidify to create a clean cloth rim.
fill_component_sets = [
    component
    for component, t_min, t_max in boundary_component_sets
    if t_min < 0.20 and t_max > 0.50
]
bm_fill = bmesh.new()
bm_fill.from_mesh(mesh)
bm_fill.verts.ensure_lookup_table()
bm_fill.edges.ensure_lookup_table()
fill_edges = [
    edge
    for edge in bm_fill.edges
    if edge.is_boundary
    and any(edge.verts[0].index in component and edge.verts[1].index in component for component in fill_component_sets)
]
fill_result = bmesh.ops.holes_fill(bm_fill, edges=fill_edges, sides=0)
if fill_result.get("faces"):
    bmesh.ops.triangulate(
        bm_fill,
        faces=list(fill_result["faces"]),
        quad_method="BEAUTY",
        ngon_method="BEAUTY",
    )
bmesh.ops.recalc_face_normals(bm_fill, faces=list(bm_fill.faces))
bm_fill.to_mesh(mesh)
bm_fill.free()
mesh.update()

# Recompute the remaining boundary after the armpit closures, then align the
# two cuff cuts to planes perpendicular to their target arm axes.
edge_use_after_fill = defaultdict(int)
for polygon in mesh.polygons:
    ids = list(polygon.vertices)
    for a, b in zip(ids, ids[1:] + ids[:1]):
        edge_use_after_fill[tuple(sorted((a, b)))] += 1
boundary_vertices_after_fill = {
    vertex_index
    for edge, count in edge_use_after_fill.items()
    if count == 1
    for vertex_index in edge
}
boundary_t_values = []
mid_boundary_vertices = 0
for vertex_index in boundary_vertices_after_fill:
    vertex = mesh.vertices[vertex_index]
    side = 1 if vertex.co.x >= 0.0 else -1
    shoulder, cuff = target_axes[side]
    axis = cuff - shoulder
    t = (vertex.co - shoulder).dot(axis) / axis.length_squared
    boundary_t_values.append(t)
    if t < 0.34:
        vertex.co += axis * (0.035 - t)
    elif t > 0.66:
        vertex.co += axis * (1.005 - t)
    else:
        mid_boundary_vertices += 1
mesh.update()
if mid_boundary_vertices:
    raise RuntimeError(
        f"Unexpected residual hole in anatomical sleeve surface: {mid_boundary_vertices} boundary vertices"
    )

# Recalculate clean anatomical normals, add modest padded-cloth ease, then
# solidify.  Fullness peaks over the biceps and disappears into cowl/cuff.
bm = bmesh.new()
bm.from_mesh(mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(mesh)
bm.free()
mesh.update()
for vertex in mesh.vertices:
    side = 1 if vertex.co.x >= 0.0 else -1
    shoulder, cuff = target_axes[side]
    axis = cuff - shoulder
    t = max(0.0, min(1.0, (vertex.co - shoulder).dot(axis) / axis.length_squared))
    ease = math.sin(math.pi * t) ** 1.25
    # A shallow irregularity reads as padded linen, without turning the arm
    # back into a tube or a stack of quilted cushions.
    angle = math.atan2(vertex.co.z - 1.425, vertex.co.y - (0.024 + 0.053 * t))
    wrinkle = 0.0013 * math.sin(5.0 * math.pi * t + 2.0 * angle) * ease
    vertex.co += vertex.normal * (0.012 + 0.009 * ease + wrinkle)
mesh.update()

bpy.ops.object.select_all(action="DESELECT")
sleeves.select_set(True)
bpy.context.view_layer.objects.active = sleeves
solidify = sleeves.modifiers.new("AnatomicalClothThickness", "SOLIDIFY")
solidify.thickness = 0.0065
solidify.offset = -0.15
solidify.use_rim = True
# Even-offset correction can diverge at the anatomical armpit crease; a
# constant normal offset is both safer and more cloth-like here.
solidify.use_even_offset = False
bpy.ops.object.modifier_apply(modifier=solidify.name)

# Smooth only enough to soften the cut cuffs; the CC0 anatomy stays intact.
# The anatomy source already has smooth, dense edge loops.  Keeping them
# avoids bevel artefacts along the two non-planar cut cuffs.

# Collapse the cap/solidify construction to a single watertight cloth volume.
# This removes the one over-connected edge that Blender's Solidify can create
# where the filled armpit patch meets its rim, while preserving the sampled
# deltoid and biceps silhouette.
sleeves.data.remesh_voxel_size = 0.0032
sleeves.data.remesh_voxel_adaptivity = 0.0
sleeves.data.use_remesh_preserve_volume = True
bpy.ops.object.voxel_remesh()
bm_relax = bmesh.new()
bm_relax.from_mesh(sleeves.data)
# Voxelisation can retain a tiny sealed sliver from the doubled hidden armpit
# cap.  Keep the two large arm volumes and discard only those internal crumbs.
unseen_voxel = set(bm_relax.verts)
voxel_components = []
while unseen_voxel:
    component = set()
    queue = deque([unseen_voxel.pop()])
    while queue:
        vertex = queue.popleft()
        component.add(vertex)
        neighbours = {edge.other_vert(vertex) for edge in vertex.link_edges}
        found = neighbours & unseen_voxel
        unseen_voxel.difference_update(found)
        queue.extend(found)
    voxel_components.append(component)
voxel_component_sizes = sorted((len(component) for component in voxel_components), reverse=True)
for component in sorted(voxel_components, key=len, reverse=True)[2:]:
    bmesh.ops.delete(bm_relax, geom=list(component), context="VERTS")
for _iteration in range(2):
    bmesh.ops.smooth_vert(
        bm_relax,
        verts=list(bm_relax.verts),
        factor=0.075,
        use_axis_x=True,
        use_axis_y=True,
        use_axis_z=True,
    )
bmesh.ops.recalc_face_normals(bm_relax, faces=list(bm_relax.faces))
bm_relax.to_mesh(sleeves.data)
bm_relax.free()
sleeves.data.update()
pre_decimate_triangles = triangle_count(sleeves)
if pre_decimate_triangles > 6500:
    decimate = sleeves.modifiers.new("GameReadyAnatomyDecimate", "DECIMATE")
    decimate.ratio = 6500.0 / pre_decimate_triangles
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)

material = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
if material is None:
    raise RuntimeError("Established 4K gambeson material is missing")
mesh = sleeves.data
mesh.materials.clear()
mesh.materials.append(material)
for polygon in mesh.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.014, area_weight=0.35)
bpy.ops.object.mode_set(mode="OBJECT")

weight_min, weight_max = transfer_weights(sleeves, weight_samples, weight_tree)
armature = sleeves.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
sleeves.parent = rig
sleeves.matrix_parent_inverse = rig.matrix_world.inverted()
sleeves["game_asset"] = True
sleeves["part_category"] = "ClothedBody"
sleeves["intentional_layer"] = True
sleeves["source"] = "CC0 MakeHuman Suits02 Donitz monk robe upper-sleeve cloth"
sleeves["source_pose_conversion"] = "A-pose upper arms fitted to Rigify T-pose axes"

# Delete the imported construction object/data so it cannot appear or export.
anatomy_mesh = anatomy.data
bpy.data.objects.remove(anatomy, do_unlink=True)
if anatomy_mesh.users == 0:
    bpy.data.meshes.remove(anatomy_mesh)

topology = topology_stats(sleeves)
if topology["components"] != 2 or topology["nonmanifold_edges"] != 0:
    raise RuntimeError(f"Anatomical sleeve topology failed: {topology}")
if weight_min < 0.999999 or weight_max > 1.000001:
    raise RuntimeError(f"Anatomical sleeve weights failed: {weight_min}..{weight_max}")
if not any(mod.type == "ARMATURE" and mod.object == rig for mod in sleeves.modifiers):
    raise RuntimeError("Rigify modifier missing on anatomical sleeves")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.025, 0.028, 0.034, 1.0)
        background.inputs[1].default_value = 0.14

qa_lights = []
for name, location, energy, size, color in (
    ("V16AS_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AS_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AS_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    light_data = bpy.data.lights.new(name + "_Data", "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    qa_lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)) -> str:
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16at_cc0_monk_sleeves_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.48), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

for light in qa_lights:
    light_data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if light_data.users == 0:
        bpy.data.lights.remove(light_data)

character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-")
    and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

donor_removed_faces = donor.get("v16zb_removed_torn_upper_sleeve_faces", 0)
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "anatomy_source": str(ANATOMY_SOURCE),
    "anatomy_object": BODY_NAME,
    "construction": "CC0 monk-robe upper sleeves extracted in A-pose, fitted to current T-pose, padded and solidified",
    "selected_source_faces": {
        "left": len(selected_by_side[1]),
        "right": len(selected_by_side[-1]),
    },
    "preserved_existing_removed_torn_donor_faces": donor_removed_faces,
    "additional_torn_donor_faces_removed": additional_torn_donor_faces,
    "replaced_rectangular_sleeve_triangles": old_sleeve_triangles,
    "anatomical_sleeve_triangles": triangle_count(sleeves),
    "topology": topology,
    "weight_sum_range": [weight_min, weight_max],
    "rigify_modifier": True,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes),
    "total_triangles": total_triangles,
    "bounds": {
        "min": [min(vertex.co[i] for vertex in sleeves.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in sleeves.data.vertices) for i in range(3)],
    },
    "pre_solidify_boundary": {
        "vertices": len(boundary_vertices),
        "t_range": [min(boundary_t_values), max(boundary_t_values)],
        "mid_arm_boundary_vertices": mid_boundary_vertices,
        "projected_inner_t": 0.055,
        "projected_outer_t": 1.005,
    },
    "previews": previews,
}
sleeves["v16at_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AT_REPORT=" + json.dumps(report, sort_keys=True))
