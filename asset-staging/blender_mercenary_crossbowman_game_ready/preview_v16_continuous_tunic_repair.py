"""Preview a continuous CC0 Viking-tunic underlayer fitted to the V16 rig.

This diagnostic opens the current production blend, replaces the disconnected
three-piece upper only in memory, and renders multi-angle QA images.  It does
not save a blend or export a GLB.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
SOURCE_BLEND = STAGING / "mercenary_crossbowman_game_ready_v16.blend"
TUNIC_OBJ = (
    STAGING
    / "cc0_makehuman_suits02_candidate/clothes/rehmanpolanski_viking_tunic"
    / "tunicviking.obj"
)
OUTPUT_DIR = STAGING / "continuous_tunic_preview"
REPORT_PATH = OUTPUT_DIR / "report.json"
SUMMARY_PATH = STAGING / "build_summary_v16.json"
OUTPUT_GLB = (
    ROOT
    / "godot-game/assets/3d/dark_fantasy"
    / "mercenary_crossbowman_game_ready_3d.glb"
)
COMMIT = "--commit" in sys.argv

RIG_NAME = "Mercenary_Rigify_Rig_v4"
OLD_UPPER_NAME = "Mercenary_CC0_MonkRobe_CleanUpper_LOD0"
NEW_UPPER_NAME = "Mercenary_ContinuousGambesonTunic_LOD0"


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return float(value >= edge1)
    value = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return value * value * (3.0 - 2.0 * value)


def triangle_count(obj: bpy.types.Object) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    edge_faces: dict[tuple[int, int], int] = defaultdict(int)
    adjacency: dict[int, set[int]] = defaultdict(set)
    for polygon in obj.data.polygons:
        ids = list(polygon.vertices)
        for first, second in zip(ids, ids[1:] + ids[:1]):
            edge_faces[tuple(sorted((first, second)))] += 1
            adjacency[first].add(second)
            adjacency[second].add(first)

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
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def isolate_largest_component(obj: bpy.types.Object) -> dict[str, int]:
    mesh = obj.data
    adjacency = [set() for _ in mesh.vertices]
    for edge in mesh.edges:
        first, second = edge.vertices
        adjacency[first].add(second)
        adjacency[second].add(first)

    unseen = set(range(len(mesh.vertices)))
    components: list[set[int]] = []
    while unseen:
        start = unseen.pop()
        queue = [start]
        found = {start}
        while queue:
            for neighbor in adjacency[queue.pop()]:
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    found.add(neighbor)
                    queue.append(neighbor)
        components.append(found)
    components.sort(key=len, reverse=True)
    keep = components[0]

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    remove = [vertex for vertex in bm.verts if vertex.index not in keep]
    if remove:
        bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return {
        "source_components": len(components),
        "kept_vertices": len(keep),
        "removed_vertices": sum(len(component) for component in components[1:]),
    }


def body_height(source_y: float) -> float:
    # Preserve the fitted chest, then lengthen the hidden skirt so every tear
    # in the projected outer coat has cloth behind it instead of background.
    if source_y >= 1.5:
        return 0.120 * source_y + 0.696
    return 0.876 + (source_y - 1.5) * 0.2061


def affine_position(source: Vector) -> Vector:
    return Vector((0.119 * source.x, 0.075 * source.z - 0.044, body_height(source.y)))


def fit_continuous_tunic(obj: bpy.types.Object) -> dict[str, float]:
    """Straighten the authored sleeves while retaining shared shoulder verts."""
    source_positions = [vertex.co.copy() for vertex in obj.data.vertices]
    masks = []

    for vertex, source in zip(obj.data.vertices, source_positions):
        side = 1.0 if source.x >= 0.0 else -1.0
        shoulder_source = Vector((side * 1.45, 6.20, 0.34))
        cuff_source = Vector((side * 4.708, 2.7968, 1.8636))
        source_axis = cuff_source - shoulder_source
        source_length_squared = source_axis.length_squared
        source_u = max(
            0.0,
            min(1.0, (source - shoulder_source).dot(source_axis) / source_length_squared),
        )
        # Include the source garment's entire loose under-arm panel in the
        # sleeve deformation.  A distance-only mask leaves a hanging batwing;
        # X/Y gating cleanly separates that panel from the low skirt while
        # retaining a broad, blended shoulder transition.
        arm_mask = (
            smoothstep(1.55, 2.40, abs(source.x))
            * smoothstep(2.00, 2.48, source.y)
        )
        if source_u > 0.88 and abs(source.x) > 4.15:
            arm_mask = 1.0
        masks.append(arm_mask)

        body = affine_position(source)
        shoulder_target = affine_position(shoulder_source)
        cuff_target = Vector((side * 0.803, -0.019, 1.425))

        body_shoulder = affine_position(shoulder_source)
        body_cuff = affine_position(cuff_source)
        body_axis = body_cuff - body_shoulder
        body_axis_unit = body_axis.normalized()
        target_axis = cuff_target - shoulder_target
        target_axis_unit = target_axis.normalized()
        rotation = body_axis_unit.rotation_difference(target_axis_unit)

        body_axis_point = body_shoulder + body_axis * source_u
        radial = rotation @ (body - body_axis_point)

        # The Viking source deliberately has loose, hanging sleeves.  For this
        # character they must read as a padded gambeson wrapped around a human
        # arm, so compress the cross-section into a tapered ellipse while
        # retaining the source folds through a smooth tanh response.
        vertical_axis = Vector((0.0, 0.0, 1.0))
        vertical_axis -= target_axis_unit * vertical_axis.dot(target_axis_unit)
        vertical_axis.normalize()
        depth_axis = target_axis_unit.cross(vertical_axis).normalized()
        if depth_axis.dot(Vector((0.0, 1.0, 0.0))) < 0.0:
            depth_axis.negate()
        vertical_radius = 0.102 - 0.050 * source_u
        depth_radius = 0.108 - 0.058 * source_u
        vertical_offset = vertical_radius * math.tanh(
            radial.dot(vertical_axis) / vertical_radius
        )
        depth_offset = depth_radius * math.tanh(radial.dot(depth_axis) / depth_radius)
        straight = (
            shoulder_target
            + target_axis * source_u
            + vertical_axis * vertical_offset
            + depth_axis * depth_offset
        )
        vertex.co = body.lerp(straight, arm_mask)

    obj.data.update()
    return {
        "mask_min": min(masks),
        "mask_max": max(masks),
        "mask_mean": sum(masks) / len(masks),
    }


def active_object(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    active_object(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def remove_broken_donor_arms(obj: bpy.types.Object) -> int:
    """Remove the torn scan arms and hands replaced by clean closed parts."""
    before = triangle_count(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    remove_faces = []
    for face in bm.faces:
        center = face.calc_center_median()
        if abs(center.x) > 0.225 and 1.155 < center.z < 1.575:
            remove_faces.append(face)
    if remove_faces:
        bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    return before - triangle_count(obj)


def normalized_blend(value: float, low: float, high: float) -> float:
    return smoothstep(low, high, value)


def coordinate_weights(coordinate: Vector) -> dict[str, float]:
    """Deterministic Rigify weights for the continuous cloth shell."""
    x, _y, z = coordinate
    side = "L" if x >= 0.0 else "R"
    ax = abs(x)
    weights: dict[str, float] = {}

    def add(name: str, value: float) -> None:
        if value > 1.0e-6:
            weights[name] = weights.get(name, 0.0) + value

    if ax > 0.195 and z > 1.16:
        if ax < 0.315:
            factor = normalized_blend(ax, 0.195, 0.315)
            add("DEF-spine.004", 1.0 - factor)
            add("DEF-shoulder." + side, 0.35 * factor)
            add("DEF-upper_arm." + side, 0.65 * factor)
        elif ax < 0.455:
            factor = normalized_blend(ax, 0.315, 0.455)
            add("DEF-upper_arm." + side, 1.0 - 0.62 * factor)
            add("DEF-upper_arm." + side + ".001", 0.62 * factor)
        elif ax < 0.610:
            factor = normalized_blend(ax, 0.455, 0.610)
            add("DEF-upper_arm." + side + ".001", 1.0 - factor)
            add("DEF-forearm." + side, factor)
        elif ax < 0.735:
            factor = normalized_blend(ax, 0.610, 0.735)
            add("DEF-forearm." + side, 1.0 - 0.70 * factor)
            add("DEF-forearm." + side + ".001", 0.70 * factor)
        else:
            factor = normalized_blend(ax, 0.735, 0.810)
            add("DEF-forearm." + side + ".001", 1.0 - 0.25 * factor)
            add("DEF-hand." + side, 0.25 * factor)
    elif z < 0.98 and ax > 0.035:
        factor = normalized_blend(z, 0.38, 0.92)
        add("DEF-thigh." + side, 0.42 + 0.18 * factor)
        add("DEF-thigh." + side + ".001", 0.10 + 0.08 * factor)
        add("DEF-spine", 0.48 - 0.26 * factor)
    elif z < 1.08:
        add("DEF-spine", 0.66)
        add("DEF-pelvis." + side, 0.34)
    elif z < 1.22:
        factor = normalized_blend(z, 1.08, 1.22)
        add("DEF-spine.001", 1.0 - factor)
        add("DEF-spine.002", factor)
    elif z < 1.36:
        factor = normalized_blend(z, 1.22, 1.36)
        add("DEF-spine.003", 1.0 - factor)
        add("DEF-spine.004", factor)
    elif z < 1.50:
        factor = normalized_blend(z, 1.36, 1.50)
        add("DEF-spine.004", 1.0 - 0.55 * factor)
        add("DEF-spine.005", 0.55 * factor)
    else:
        add("DEF-spine.005", 0.65)
        add("DEF-spine.006", 0.35)

    total = sum(weights.values())
    if total <= 1.0e-8:
        return {"DEF-spine": 1.0}
    return {name: value / total for name, value in weights.items()}


def bind_tunic_to_rig(obj: bpy.types.Object, rig: bpy.types.Object) -> None:
    deform_names = {bone.name for bone in rig.data.bones if bone.use_deform}
    obj.vertex_groups.clear()
    groups: dict[str, bpy.types.VertexGroup] = {}
    for vertex in obj.data.vertices:
        weights = coordinate_weights(obj.matrix_world @ vertex.co)
        for bone_name, value in weights.items():
            if bone_name not in deform_names:
                raise RuntimeError(f"Missing deform bone: {bone_name}")
            group = groups.get(bone_name)
            if group is None:
                group = obj.vertex_groups.new(name=bone_name)
                groups[bone_name] = group
            group.add([vertex.index], value, "REPLACE")
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    modifier = obj.modifiers.new("Mercenary_Rigify_Deform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True


def weight_stats(obj: bpy.types.Object) -> dict[str, float | int]:
    sums = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    influences = [sum(item.weight > 1.0e-6 for item in vertex.groups) for vertex in obj.data.vertices]
    return {
        "minimum_sum": min(sums),
        "maximum_sum": max(sums),
        "maximum_influences": max(influences),
        "unweighted_vertices": sum(value < 0.999 for value in sums),
    }


def create_glove(side: int, rig: bpy.types.Object) -> bpy.types.Object:
    """Create one clean, closed leather glove overlapping the tunic cuff."""
    pieces = []
    specifications = [
        ((side * 0.836, -0.019, 1.424), (0.066, 0.044, 0.047), 0.0),
    ]
    # Four compact finger volumes preserve a readable hand silhouette from
    # oblique/top views without the old scan's torn finger geometry.
    for index, depth_offset in enumerate((-0.021, -0.007, 0.007, 0.021)):
        finger_length = 0.056 - 0.003 * abs(index - 1.5)
        specifications.append(
            (
                (side * 0.895, -0.019 + depth_offset, 1.426 - 0.002 * abs(index - 1.5)),
                (finger_length, 0.0145, 0.0145),
                0.0,
            )
        )
    specifications.append(
        (
            (side * 0.844, -0.047, 1.394),
            (0.036, 0.019, 0.017),
            side * math.radians(32.0),
        )
    )
    for location, scale, rotation_y in specifications:
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=28,
            ring_count=16,
            location=location,
            rotation=(0.0, rotation_y, 0.0),
        )
        piece = bpy.context.active_object
        piece.scale = scale
        active_object(piece)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        pieces.append(piece)

    active_object(pieces[0])
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    glove = bpy.context.active_object
    suffix = "L" if side > 0 else "R"
    glove.name = f"Mercenary_LeatherGlove_{suffix}_LOD0"
    glove.data.name = glove.name + "_Mesh"

    glove.data.remesh_voxel_size = 0.0042
    glove.data.remesh_voxel_adaptivity = 0.0
    glove.data.use_remesh_preserve_volume = True
    active_object(glove)
    bpy.ops.object.voxel_remesh()

    bm = bmesh.new()
    bm.from_mesh(glove.data)
    for _iteration in range(3):
        bmesh.ops.smooth_vert(
            bm,
            verts=list(bm.verts),
            factor=0.18,
            use_axis_x=True,
            use_axis_y=True,
            use_axis_z=True,
        )
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(glove.data)
    bm.free()
    glove.data.update()

    if triangle_count(glove) > 3200:
        modifier = glove.modifiers.new("Glove_GameReady_Decimate", "DECIMATE")
        modifier.ratio = 3000.0 / triangle_count(glove)
        modifier.use_collapse_triangulate = True
        apply_modifier(glove, modifier)

    for polygon in glove.data.polygons:
        polygon.use_smooth = True
    active_object(glove)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    leather = (
        bpy.data.materials.get("MAT_Leather_Side_PBR_4K")
        or bpy.data.materials.get("MAT_Leather_Worn_4K")
        or bpy.data.materials.get("MAT_Leather_Worn_4K.003")
    )
    if leather is None:
        raise RuntimeError("Required leather material is missing")
    glove.data.materials.clear()
    glove.data.materials.append(leather)

    hand_name = f"DEF-hand.{suffix}"
    forearm_name = f"DEF-forearm.{suffix}.001"
    hand_group = glove.vertex_groups.new(name=hand_name)
    forearm_group = glove.vertex_groups.new(name=forearm_name)
    for vertex in glove.data.vertices:
        outward = side * vertex.co.x
        blend = smoothstep(0.790, 0.835, outward)
        hand_group.add([vertex.index], 0.72 + 0.28 * blend, "REPLACE")
        forearm_group.add([vertex.index], 0.28 * (1.0 - blend), "REPLACE")
    glove.parent = rig
    glove.matrix_parent_inverse = rig.matrix_world.inverted()
    armature = glove.modifiers.new("Mercenary_Rigify_Deform", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    glove["part_category"] = "ClothedBody"
    glove["construction"] = "Closed voxel-union leather glove"
    return glove


bpy.ops.wm.open_mainfile(filepath=str(SOURCE_BLEND))
scene = bpy.context.scene

donor = bpy.data.objects.get("Mercenary_Clothed_Donor_LOD0")
if donor is None:
    raise RuntimeError("Missing clothed donor")
removed_broken_donor_arm_triangles = remove_broken_donor_arms(donor)

old_upper = bpy.data.objects.get(OLD_UPPER_NAME)
if old_upper is None:
    raise RuntimeError(f"Missing old upper: {OLD_UPPER_NAME}")
old_upper_triangles = triangle_count(old_upper)
old_upper_mesh = old_upper.data
bpy.data.objects.remove(old_upper, do_unlink=True)
if old_upper_mesh.users == 0:
    bpy.data.meshes.remove(old_upper_mesh)

bpy.ops.object.select_all(action="DESELECT")
bpy.ops.wm.obj_import(filepath=str(TUNIC_OBJ))
imported = [obj for obj in bpy.context.selected_objects if obj.type == "MESH"]
if not imported:
    raise RuntimeError("Viking tunic import produced no mesh")
if len(imported) > 1:
    active_object(imported[0])
    for obj in imported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = imported[0]
    bpy.ops.object.join()
tunic = bpy.context.active_object
tunic.name = NEW_UPPER_NAME
tunic.rotation_euler = (0.0, 0.0, 0.0)
tunic.scale = (1.0, 1.0, 1.0)

component_report = isolate_largest_component(tunic)
fit_report = fit_continuous_tunic(tunic)

gambeson = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
outer_wool = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if gambeson is None or outer_wool is None:
    raise RuntimeError("Required 4K materials are missing")
tunic.data.materials.clear()
tunic.data.materials.append(gambeson)
tunic.data.materials.append(outer_wool)
for polygon in tunic.data.polygons:
    center = polygon.center
    # Beige padded sleeves and center panel; dark hidden skirt/side lining.
    is_sleeve = abs(center.x) > 0.25 and center.z > 1.18
    is_center_panel = abs(center.x) < 0.115 and center.y < -0.015 and center.z > 0.64
    polygon.material_index = 0 if (is_sleeve or is_center_panel) else 1
    polygon.use_smooth = True

solidify = tunic.modifiers.new("Continuous_Cloth_Thickness", "SOLIDIFY")
solidify.thickness = 0.0040
solidify.offset = 0.0
solidify.use_rim = True
solidify.use_even_offset = False
apply_modifier(tunic, solidify)

tunic["part_category"] = "ClothedBody"
tunic["source_license"] = "CC0"
tunic["construction"] = "Single connected authored torso and sleeves; T-pose fitted"

rig = bpy.data.objects.get(RIG_NAME)
if rig is None:
    raise RuntimeError("Missing Rigify rig")
bind_tunic_to_rig(tunic, rig)
gloves = [create_glove(1, rig), create_glove(-1, rig)]

# Hide authoring helpers and rig widgets, but retain all visible character parts.
for obj in scene.objects:
    if obj.type == "ARMATURE" or obj.name.startswith(("WGT-", "PREVIEW_")):
        obj.hide_render = True
    elif obj.type == "MESH" and obj.get("part_category") is not None:
        obj.hide_render = False
        obj.hide_set(False)

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
scene.render.resolution_x = 1100
scene.render.resolution_y = 1100
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.film_transparent = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("Continuous_Tunic_QA_World")
scene.world.use_nodes = True
background = scene.world.node_tree.nodes.get("Background")
background.inputs[0].default_value = (0.12, 0.135, 0.16, 1.0)
background.inputs[1].default_value = 0.28

qa_objects = []
for name, location, energy, size, color in (
    ("Continuous_QA_Key", (-2.2, -2.7, 3.4), 620.0, 2.6, (1.0, 0.84, 0.70)),
    ("Continuous_QA_Fill", (2.5, -1.4, 2.5), 360.0, 2.3, (0.64, 0.78, 1.0)),
    ("Continuous_QA_Rim", (0.4, 2.6, 2.8), 480.0, 2.0, (0.73, 0.84, 1.0)),
    ("Continuous_QA_Top", (0.0, 0.0, 4.1), 300.0, 2.0, (1.0, 0.94, 0.84)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.0, 1.18))
    qa_objects.append(light)

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("Continuous_QA_Camera_Data")
    camera = bpy.data.objects.new("Continuous_QA_Camera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera


def render(name, location, target, *, lens=76, ortho=None, size=(1100, 1100)):
    if ortho is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = size
    path = OUTPUT_DIR / f"{name}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "front": render("front", (0.0, -4.0, 1.10), (0.0, 0.0, 0.98), lens=72),
    "back": render("back", (0.0, 4.0, 1.10), (0.0, 0.0, 0.98), lens=72),
    "side": render("side", (4.0, 0.0, 1.10), (0.0, 0.0, 1.02), lens=72),
    "high": render("high", (1.25, -2.15, 2.45), (0.0, 0.0, 1.18), lens=72),
    "top": render("top", (0.0, 0.0, 4.2), (0.0, 0.0, 1.18), lens=72),
}

character_meshes = [
    obj
    for obj in scene.objects
    if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith(("WGT-", "PREVIEW_"))
]
new_part_topology = {
    obj.name: topology_stats(obj) for obj in [tunic, *gloves]
}
new_part_weights = {
    obj.name: weight_stats(obj) for obj in [tunic, *gloves]
}
for name, stats in new_part_topology.items():
    if stats != {
        "components": 1,
        "boundary_edges": 0,
        "nonmanifold_edges": 0,
        "overconnected_edges": 0,
    }:
        raise RuntimeError(f"Closed-part topology check failed for {name}: {stats}")
for name, stats in new_part_weights.items():
    if (
        stats["minimum_sum"] < 0.998
        or stats["maximum_sum"] > 1.002
        or stats["maximum_influences"] > 4
        or stats["unweighted_vertices"]
    ):
        raise RuntimeError(f"Rig weights check failed for {name}: {stats}")

total_triangles = sum(triangle_count(obj) for obj in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
deform_bones = sum(1 for bone in rig.data.bones if bone.use_deform)
if deform_bones != 160:
    raise RuntimeError(f"Unexpected Rigify deform-bone count: {deform_bones}")

report = {
    "source_blend": str(SOURCE_BLEND),
    "tunic_source": str(TUNIC_OBJ),
    "saved_production": COMMIT,
    "old_upper_triangles": old_upper_triangles,
    "removed_broken_donor_arm_triangles": removed_broken_donor_arm_triangles,
    "new_upper_triangles": triangle_count(tunic),
    "glove_triangles": {glove.name: triangle_count(glove) for glove in gloves},
    "total_triangles": total_triangles,
    "deform_bones": deform_bones,
    "component_isolation": component_report,
    "fit": fit_report,
    "topology": topology_stats(tunic),
    "new_part_topology": new_part_topology,
    "new_part_weights": new_part_weights,
    "bounds": {
        "min": [min(v.co[index] for v in tunic.data.vertices) for index in range(3)],
        "max": [max(v.co[index] for v in tunic.data.vertices) for index in range(3)],
    },
    "previews": previews,
}
REPORT_PATH.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("CONTINUOUS_TUNIC_PREVIEW_REPORT", json.dumps(report, sort_keys=True))

if COMMIT:
    # Candidate-only lights must not clutter the delivered authoring scene.
    for obj in qa_objects:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data.users == 0:
            bpy.data.lights.remove(data)

    donor["continuous_tunic_repair"] = True
    donor["removed_broken_arm_triangles"] = removed_broken_donor_arm_triangles
    tunic["source_asset"] = str(TUNIC_OBJ)
    tunic["source_license_file"] = str(
        TUNIC_OBJ.with_name("rehmanpolanski_viking_tunic.mhclo")
    )
    tunic["rest_pose"] = "T_POSE"

    # Keep embedded helper scripts inert when the user opens the file.
    for text_block in bpy.data.texts:
        text_block.use_module = False

    # Put the saved camera on a useful full-body front view.
    camera.data.type = "PERSP"
    camera.data.lens = 72
    camera.location = (0.0, -4.0, 1.10)
    look_at(camera, (0.0, 0.0, 0.98))

    for obj in scene.objects:
        helper = obj.type == "ARMATURE" or obj.name.startswith(("WGT-", "PREVIEW_"))
        obj.hide_render = helper
        if helper:
            obj.hide_viewport = True
            try:
                obj.hide_set(True)
            except RuntimeError:
                pass
        elif obj.type == "MESH" and obj.get("part_category") is not None:
            obj.hide_viewport = False
            obj.hide_set(False)

    bpy.ops.object.select_all(action="DESELECT")
    tunic.select_set(True)
    bpy.context.view_layer.objects.active = tunic
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND), check_existing=False)

    # Export only production meshes and the deform rig.  Textures remain
    # embedded in the GLB for a single Godot-ready deliverable.
    bpy.ops.object.select_all(action="DESELECT")
    rig.hide_viewport = False
    rig.hide_set(False)
    rig.hide_render = False
    rig.select_set(True)
    for obj in character_meshes:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig

    OUTPUT_GLB.parent.mkdir(parents=True, exist_ok=True)
    properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    export_arguments = {
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
        "export_tangents": True,
        "export_apply": False,
        "export_morph": False,
    }
    if "use_selection" in properties:
        export_arguments["use_selection"] = True
    elif "export_selected" in properties:
        export_arguments["export_selected"] = True
    bpy.ops.export_scene.gltf(**export_arguments)

    rig.hide_render = True
    rig.hide_viewport = True
    rig.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    tunic.select_set(True)
    bpy.context.view_layer.objects.active = tunic
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE_BLEND), check_existing=False)

    summary = {
        "asset": "mercenary_crossbowman_game_ready_v16",
        "purpose": "Godot game character",
        "style": "photoreal medieval commoner mercenary",
        "height_m": 1.78,
        "rest_pose": "T_POSE",
        "expression": "neutral",
        "triangles": total_triangles,
        "triangle_budget": [100000, 150000],
        "triangle_breakdown": {
            obj.name: triangle_count(obj) for obj in sorted(character_meshes, key=lambda item: item.name)
        },
        "mesh_count": len(character_meshes),
        "deform_bones": deform_bones,
        "rig": RIG_NAME,
        "blend": str(SOURCE_BLEND),
        "glb": str(OUTPUT_GLB),
        "previews": previews,
        "continuous_upper_repair": {
            "upper": NEW_UPPER_NAME,
            "gloves": [obj.name for obj in gloves],
            "removed_disconnected_upper": OLD_UPPER_NAME,
            "removed_broken_donor_arm_triangles": removed_broken_donor_arm_triangles,
            "topology": new_part_topology,
            "weights": new_part_weights,
            "upper_bounds": report["bounds"],
        },
        "license": {
            "garment_source": str(TUNIC_OBJ),
            "license": "CC0",
            "license_file": str(TUNIC_OBJ.with_name("rehmanpolanski_viking_tunic.mhclo")),
        },
        "excluded_equipment": ["crossbow", "sword", "dagger", "quiver", "pouches"],
        "textures": {
            "skin": "4K",
            "clothing": "4K gambeson, wool and leather",
        },
    }
    SUMMARY_PATH.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    print("CONTINUOUS_TUNIC_COMMIT_BLEND", SOURCE_BLEND)
    print("CONTINUOUS_TUNIC_COMMIT_GLB", OUTPUT_GLB)
    print("CONTINUOUS_TUNIC_COMMIT_SUMMARY", SUMMARY_PATH)
