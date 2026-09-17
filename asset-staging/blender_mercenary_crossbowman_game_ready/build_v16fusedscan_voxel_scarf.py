"""Preserve the scanned folds and connect them with a hidden dark wool liner.

This isolated v16j-derived comparison avoids remeshing the three visible scan
folds.  A narrow, vertical, closed liner intersects them from behind and an
exact union makes one closed component.  Shallow quilted shoulder-cap patches
sit under the donor garment instead of replacing the upper arms with tubes.
Production files and all donor faces remain untouched.
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
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16fusedscan2_dark_lined_candidate.blend"
REPORT = STAGING / "v16fusedscan2_dark_lined_report.json"

SOURCE_COWL = "Mercenary_Cowl_LayeredClean_LOD0"
FUSED_COWL = "Mercenary_DarkLinedScanScarf_v16fusedscan2_LOD0"
SLEEVES = "Mercenary_ShallowShoulderCaps_v16fusedscan2_LOD0"
HELPERS_TO_REMOVE = (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)

    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        queue = deque([unseen.pop()])
        while queue:
            neighbours = adjacency[queue.popleft()] & unseen
            unseen.difference_update(neighbours)
            queue.extend(neighbours)
    return {
        "components": components,
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "loose_vertices": sum(not adjacency[index] for index in range(len(obj.data.vertices))),
        "zero_area_faces": sum(poly.area <= 1.0e-12 for poly in obj.data.polygons),
    }


def bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "x": [min(point.x for point in points), max(point.x for point in points)],
        "y": [min(point.y for point in points), max(point.y for point in points)],
        "z": [min(point.z for point in points), max(point.z for point in points)],
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def clear_vertex_groups(obj):
    while obj.vertex_groups:
        obj.vertex_groups.remove(obj.vertex_groups[0])


def nearest_deform_weights(source, target, rig, fallback_name):
    """Transfer at most four normalized deform weights from nearest vertices."""
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    source_group_names = {group.index: group.name for group in source.vertex_groups}
    tree = KDTree(len(source.data.vertices))
    for vertex in source.data.vertices:
        tree.insert(vertex.co, vertex.index)
    tree.balance()

    clear_vertex_groups(target)
    target_groups = {}
    distances = []
    influence_counts = []
    for vertex in target.data.vertices:
        _co, source_index, distance = tree.find(vertex.co)
        distances.append(distance)
        transferred = []
        for item in source.data.vertices[source_index].groups:
            name = source_group_names.get(item.group)
            if name in deform_names and item.weight > 1.0e-7:
                transferred.append((name, item.weight))
        transferred.sort(key=lambda pair: pair[1], reverse=True)
        transferred = transferred[:4]
        if not transferred:
            transferred = [(fallback_name(vertex.co), 1.0)] if callable(fallback_name) else [(fallback_name, 1.0)]
        total = sum(weight for _name, weight in transferred)
        influence_counts.append(len(transferred))
        for name, weight in transferred:
            group = target_groups.get(name)
            if group is None:
                group = target.vertex_groups.new(name=name)
                target_groups[name] = group
            group.add([vertex.index], weight / total, "REPLACE")
    return {
        "max_nearest_distance": max(distances),
        "mean_nearest_distance": sum(distances) / len(distances),
        "max_influences": max(influence_counts),
        "groups_used": sorted(target_groups),
    }


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
source_cowl = bpy.data.objects[SOURCE_COWL]
asset_collection = source_cowl.users_collection[0]

donor_before = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangles(donor),
}
source_cowl_stats = topology(source_cowl)
source_cowl_bounds = bounds(source_cowl)
source_cowl_triangles = triangles(source_cowl)

# Duplicate the actual scanned folds without remeshing their visible surfaces.
fused = source_cowl.copy()
fused.data = source_cowl.data.copy()
asset_collection.objects.link(fused)
fused.name = FUSED_COWL
fused.data.name = "Mercenary_DarkLinedScanScarf_v16fusedscan2_Mesh"
for modifier in list(fused.modifiers):
    fused.modifiers.remove(modifier)

# Split the three source components only for robust sequential boolean
# evaluation.  Their vertex positions are not changed.
bpy.ops.object.select_all(action="DESELECT")
fused.select_set(True)
bpy.context.view_layer.objects.active = fused
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.separate(type="LOOSE")
bpy.ops.object.mode_set(mode="OBJECT")
scan_parts = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
if len(scan_parts) != 3:
    raise RuntimeError(f"Expected three source scan folds, got {len(scan_parts)}")
for index, part in enumerate(sorted(scan_parts, key=lambda obj: bounds(obj)["z"][0])):
    part.name = f"Mercenary_ScanFold_v16fusedscan2_TEMP_{index}"

# A narrow vertical liner sits behind the three folds.  Its outward surface
# follows the fold stack while its inner surface is only 12 mm inward.  It is
# neither a horizontal shoulder plate nor a second visible collar; it exists
# to turn black see-through slots into deep, dark-wool cloth creases.
LINER_SEGMENTS = 64
LINER_ROWS = 13
LINER_THICKNESS = 0.012
liner_vertices = []
liner_faces = []
for surface in range(2):
    for row in range(LINER_ROWS):
        u = row / (LINER_ROWS - 1)
        rx = 0.197 * (1.0 - u) + 0.137 * u - surface * LINER_THICKNESS
        ry = 0.145 * (1.0 - u) + 0.100 * u - surface * LINER_THICKNESS
        base_z = 1.455 + 0.105 * u
        for segment in range(LINER_SEGMENTS):
            phi = math.tau * segment / LINER_SEGMENTS
            front = max(0.0, -math.sin(phi))
            back = max(0.0, math.sin(phi))
            z = base_z - 0.006 * front * (1.0 - u) + 0.003 * back * (1.0 - u)
            liner_vertices.append((rx * math.cos(phi), ry * math.sin(phi), z))

surface_stride = LINER_ROWS * LINER_SEGMENTS
for surface in range(2):
    for row in range(LINER_ROWS - 1):
        for segment in range(LINER_SEGMENTS):
            nxt = (segment + 1) % LINER_SEGMENTS
            a = surface * surface_stride + row * LINER_SEGMENTS + segment
            b = surface * surface_stride + (row + 1) * LINER_SEGMENTS + segment
            c = surface * surface_stride + (row + 1) * LINER_SEGMENTS + nxt
            d = surface * surface_stride + row * LINER_SEGMENTS + nxt
            liner_faces.append((a, b, c, d) if surface == 0 else (a, d, c, b))
for segment in range(LINER_SEGMENTS):
    nxt = (segment + 1) % LINER_SEGMENTS
    outer_bottom = segment
    outer_bottom_nxt = nxt
    inner_bottom = surface_stride + segment
    inner_bottom_nxt = surface_stride + nxt
    liner_faces.append((outer_bottom, inner_bottom, inner_bottom_nxt, outer_bottom_nxt))
    outer_top = (LINER_ROWS - 1) * LINER_SEGMENTS + segment
    outer_top_nxt = (LINER_ROWS - 1) * LINER_SEGMENTS + nxt
    inner_top = surface_stride + (LINER_ROWS - 1) * LINER_SEGMENTS + segment
    inner_top_nxt = surface_stride + (LINER_ROWS - 1) * LINER_SEGMENTS + nxt
    liner_faces.append((outer_top, outer_top_nxt, inner_top_nxt, inner_top))

liner_mesh = bpy.data.meshes.new("Mercenary_DarkWoolLiner_v16fusedscan2_Mesh")
liner_mesh.from_pydata(liner_vertices, [], liner_faces)
liner_mesh.update()
liner = bpy.data.objects.new("Mercenary_DarkWoolLiner_v16fusedscan2_TEMP", liner_mesh)
asset_collection.objects.link(liner)
bm = bmesh.new()
bm.from_mesh(liner_mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(liner_mesh)
bm.free()

# Exact boolean union preserves the scan folds far better than a voxel remesh.
# Sequential evaluation is used because Blender does not robustly union one
# operand containing three disconnected shells in a single modifier.
fused = liner
fused.name = FUSED_COWL
fused.data.name = "Mercenary_DarkLinedScanScarf_v16fusedscan2_Mesh"
for index, part in enumerate(scan_parts):
    bpy.ops.object.select_all(action="DESELECT")
    fused.select_set(True)
    bpy.context.view_layer.objects.active = fused
    boolean = fused.modifiers.new(f"ScanFoldExactUnion_{index}", "BOOLEAN")
    boolean.operation = "UNION"
    boolean.solver = "EXACT"
    boolean.object = part
    bpy.ops.object.modifier_apply(modifier=boolean.name)
    part_mesh = part.data
    bpy.data.objects.remove(part, do_unlink=True)
    if part_mesh.users == 0:
        bpy.data.meshes.remove(part_mesh)

bm = bmesh.new()
bm.from_mesh(fused.data)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(fused.data)
bm.free()
fused.data.update()

cowl_weight_transfer = nearest_deform_weights(
    source_cowl,
    fused,
    rig,
    "DEF-spine.005",
)

# One dark 4K wool material removes the gray side-face patchwork while keeping
# the original scan relief as geometry.
cowl_material = bpy.data.materials.get("MAT_CowlWool_Side_PBR_4K")
if cowl_material is None:
    raise RuntimeError("Missing generic cowl wool material")
cowl_material = cowl_material.copy()
cowl_material.name = "MAT_DarkLinedScan_CowlWool_PBR_4K"
fused.data.materials.clear()
fused.data.materials.append(cowl_material)
for poly in fused.data.polygons:
    poly.material_index = 0
    poly.use_smooth = True

bpy.ops.object.select_all(action="DESELECT")
fused.select_set(True)
bpy.context.view_layer.objects.active = fused
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.08, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

# Rebuild a single clean Rigify modifier after the exact union.
for modifier in list(fused.modifiers):
    fused.modifiers.remove(modifier)
modifier = fused.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_vertex_groups = True
fused.parent = rig
fused.matrix_parent_inverse = rig.matrix_world.inverted()
fused["game_asset"] = True
fused["part_category"] = "ClothedBody"
fused["source"] = "V16FUSEDSCAN2 original scanned folds plus hidden exact-union dark liner"
fused["separate_ring_objects"] = 0

# Shallow upper-surface caps sit a few millimetres below the donor shoulder
# envelope.  They show only through damaged gaps, so the intact donor sleeve
# remains the visible silhouette and no second cylindrical arm is introduced.
AXIAL = 25
CROSS = 17
sleeve_vertices = []
sleeve_faces = []
for sign in (-1.0, 1.0):
    first = len(sleeve_vertices)
    for surface in range(2):
        for axial in range(AXIAL):
            t = axial / (AXIAL - 1)
            eased = t * t * (3.0 - 2.0 * t)
            x_abs = 0.150 + 0.350 * t
            center_y = 0.092 - 0.004 * t
            center_z = 1.535 - 0.074 * eased
            half_y = 0.108 * (1.0 - t) + 0.083 * t
            for cross in range(CROSS):
                s = -1.0 + 2.0 * cross / (CROSS - 1)
                arch = math.sqrt(max(0.0, 1.0 - s * s))
                quilt = 0.0015 * math.sin(7.0 * math.pi * t + 2.0 * math.pi * s) * arch
                top_z = center_z - 0.038 * (1.0 - arch) + quilt
                thickness = 0.010
                sleeve_vertices.append((
                    sign * x_abs,
                    center_y + half_y * s,
                    top_z - surface * thickness,
                ))

    surface_stride = AXIAL * CROSS
    for surface in range(2):
        offset = first + surface * surface_stride
        for axial in range(AXIAL - 1):
            for cross in range(CROSS - 1):
                a = offset + axial * CROSS + cross
                b = offset + (axial + 1) * CROSS + cross
                c = offset + (axial + 1) * CROSS + cross + 1
                d = offset + axial * CROSS + cross + 1
                sleeve_faces.append((a, b, c, d) if surface == 0 else (a, d, c, b))

    # Close the two long side rails and both axial ends.
    for axial in range(AXIAL - 1):
        for cross in (0, CROSS - 1):
            top_a = first + axial * CROSS + cross
            top_b = first + (axial + 1) * CROSS + cross
            bottom_a = first + surface_stride + axial * CROSS + cross
            bottom_b = first + surface_stride + (axial + 1) * CROSS + cross
            sleeve_faces.append((top_a, bottom_a, bottom_b, top_b))
    for axial in (0, AXIAL - 1):
        for cross in range(CROSS - 1):
            top_a = first + axial * CROSS + cross
            top_b = top_a + 1
            bottom_a = first + surface_stride + axial * CROSS + cross
            bottom_b = bottom_a + 1
            sleeve_faces.append((top_a, top_b, bottom_b, bottom_a))

sleeve_mesh = bpy.data.meshes.new("Mercenary_ShallowShoulderCaps_v16fusedscan2_Mesh")
sleeve_mesh.from_pydata(sleeve_vertices, [], sleeve_faces)
sleeve_mesh.update()
sleeves = bpy.data.objects.new(SLEEVES, sleeve_mesh)
asset_collection.objects.link(sleeves)
bm = bmesh.new()
bm.from_mesh(sleeve_mesh)
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(sleeve_mesh)
bm.free()
sleeve_mesh.update()
for poly in sleeve_mesh.polygons:
    poly.use_smooth = True

sleeve_material = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
if sleeve_material is None:
    raise RuntimeError("Missing 4K gambeson material")
sleeve_mesh.materials.append(sleeve_material)
bpy.ops.object.select_all(action="DESELECT")
sleeves.select_set(True)
bpy.context.view_layer.objects.active = sleeves
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.08, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

sleeve_weight_transfer = nearest_deform_weights(
    donor,
    sleeves,
    rig,
    lambda co: "DEF-upper_arm.L" if co.x >= 0.0 else "DEF-upper_arm.R",
)
sleeve_modifier = sleeves.modifiers.new("RigifyDeform", "ARMATURE")
sleeve_modifier.object = rig
sleeve_modifier.use_vertex_groups = True
sleeves.parent = rig
sleeves.matrix_parent_inverse = rig.matrix_world.inverted()
sleeves["game_asset"] = True
sleeves["part_category"] = "ClothedBody"
sleeves["source"] = "V16FUSEDSCAN2 shallow closed quilted shoulder-cap underpatches"
sleeves["donor_faces_deleted"] = 0

# Retire the original separate scan shells and helper plate/collar objects only
# after weight transfer.  The textured donor garment itself is never edited.
removed_helpers = []
for name in HELPERS_TO_REMOVE:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        removed_helpers.append({"name": name, "triangles": triangles(obj)})
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
source_data = source_cowl.data
bpy.data.objects.remove(source_cowl, do_unlink=True)
if source_data.users == 0:
    bpy.data.meshes.remove(source_data)

# Hard validation before rendering.
fused_stats = topology(fused)
sleeve_stats = topology(sleeves)
fused_weights = [sum(item.weight for item in vertex.groups) for vertex in fused.data.vertices]
sleeve_weights = [sum(item.weight for item in vertex.groups) for vertex in sleeves.data.vertices]
for obj, stats, components, weights in (
    (fused, fused_stats, 1, fused_weights),
    (sleeves, sleeve_stats, 2, sleeve_weights),
):
    if stats["components"] != components:
        raise RuntimeError(f"Component validation failed on {obj.name}: {stats}")
    if stats["nonmanifold_edges"] or stats["loose_vertices"] or stats["zero_area_faces"]:
        raise RuntimeError(f"Closed topology failed on {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weight normalization failed on {obj.name}: {min(weights)}..{max(weights)}")
    if not any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers):
        raise RuntimeError(f"Rigify modifier missing on {obj.name}")

donor_after = {
    "vertices": len(donor.data.vertices),
    "polygons": len(donor.data.polygons),
    "triangles": triangles(donor),
}
if donor_after != donor_before:
    raise RuntimeError(f"Donor garment changed: {donor_before} -> {donor_after}")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.film_transparent = False
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.038, 0.043, 0.052, 1.0)
        background.inputs[1].default_value = 0.20

lights = []
for name, location, energy, size, color in (
    ("V16FUSEDSCAN2_QA_Key", (-2.2, -2.6, 3.3), 76.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16FUSEDSCAN2_QA_Fill", (2.4, -1.5, 2.5), 40.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16FUSEDSCAN2_QA_Rim", (0.3, 2.4, 2.7), 54.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("V16FUSEDSCAN2_DiagnosticCamera")
    camera = bpy.data.objects.new("V16FUSEDSCAN2_DiagnosticCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
camera.data.type = "PERSP"
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16fusedscan2_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.63), (0.0, 0.02, 1.49), 86),
    "high": render("high", (0.70, -0.86, 2.14), (0.0, 0.015, 1.46), 86),
    "three_quarter": render("three_quarter", (0.74, -1.48, 1.82), (0.0, 0.0, 1.42), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

for light in lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Rigify deform bone count changed: {deform_bones}")

report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "donor_unchanged": True,
    "donor_before": donor_before,
    "donor_after": donor_after,
    "source_cowl_components": source_cowl_stats["components"],
    "source_cowl_triangles": source_cowl_triangles,
    "source_cowl_bounds": source_cowl_bounds,
    "visible_scan_geometry_preserved_without_voxel_remesh": True,
    "hidden_liner": {
        "segments": LINER_SEGMENTS,
        "rows": LINER_ROWS,
        "thickness_m": LINER_THICKNESS,
        "bottom_outer_radii_m": [0.197, 0.145],
        "top_outer_radii_m": [0.137, 0.100],
        "z_range_m": [1.449, 1.563],
    },
    "fused_cowl": fused.name,
    "fused_cowl_triangles": triangles(fused),
    "fused_cowl_bounds": bounds(fused),
    "fused_cowl_topology": fused_stats,
    "fused_cowl_weight_sum_range": [min(fused_weights), max(fused_weights)],
    "fused_cowl_weight_transfer": cowl_weight_transfer,
    "fused_cowl_rigify": True,
    "removed_helpers": removed_helpers,
    "sleeves": sleeves.name,
    "sleeve_triangles": triangles(sleeves),
    "sleeve_bounds": bounds(sleeves),
    "sleeve_topology": sleeve_stats,
    "sleeve_weight_sum_range": [min(sleeve_weights), max(sleeve_weights)],
    "sleeve_weight_transfer": sleeve_weight_transfer,
    "sleeve_rigify": True,
    "deform_bones": deform_bones,
    "character_meshes": len(character_meshes),
    "total_triangles": total_triangles,
    "previews": previews,
}
fused["v16fusedscan_validation"] = json.dumps(report, sort_keys=True)
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16FUSEDSCAN2_REPORT=" + json.dumps(report, sort_keys=True))
