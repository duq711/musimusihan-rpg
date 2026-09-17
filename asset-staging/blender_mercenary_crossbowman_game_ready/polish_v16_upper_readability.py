"""Polish the repaired v16 upper body without reopening legacy candidates.

Dry run renders visual QA only. Pass ``-- --commit`` to update the final Blend
and canonical Godot GLB after all structural checks pass.
"""

from __future__ import annotations

import bmesh
import bpy
import json
import math
import sys
from pathlib import Path

from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
WORK = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready"
BLEND = WORK / "mercenary_crossbowman_game_ready_v16.blend"
GLB = ROOT / "godot-game/assets/3d/dark_fantasy/mercenary_crossbowman_game_ready_3d.glb"
SUMMARY = WORK / "build_summary_v16.json"
PREVIEW_DIR = WORK / "visual_polish_preview"
REPORT = PREVIEW_DIR / "report.json"
RIG_NAME = "Mercenary_Rigify_Rig_v4"
TUNIC_NAME = "Mercenary_ContinuousGambesonTunic_LOD0"
COMMIT = "--commit" in sys.argv


def active_object(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    active_object(obj)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(0, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.verts.ensure_lookup_table()
    boundary = sum(len(edge.link_faces) == 1 for edge in bm.edges)
    overconnected = sum(len(edge.link_faces) > 2 for edge in bm.edges)
    nonmanifold = sum(len(edge.link_faces) != 2 for edge in bm.edges)
    unseen = set(vertex.index for vertex in bm.verts)
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            vertex = bm.verts[stack.pop()]
            for edge in vertex.link_edges:
                other = edge.other_vert(vertex).index
                if other in unseen:
                    unseen.remove(other)
                    stack.append(other)
    bm.free()
    return {
        "components": components,
        "boundary_edges": boundary,
        "nonmanifold_edges": nonmanifold,
        "overconnected_edges": overconnected,
    }


def weight_stats(obj: bpy.types.Object) -> dict[str, float | int]:
    sums = [sum(group.weight for group in vertex.groups) for vertex in obj.data.vertices]
    influences = [sum(group.weight > 1.0e-6 for group in vertex.groups) for vertex in obj.data.vertices]
    return {
        "minimum_sum": min(sums),
        "maximum_sum": max(sums),
        "maximum_influences": max(influences),
        "unweighted_vertices": sum(value < 0.999 for value in sums),
    }


def remove_object_and_mesh(obj: bpy.types.Object) -> None:
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge1 <= edge0:
        return float(value >= edge1)
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def polish_underarm_silhouette(obj: bpy.types.Object) -> int:
    """Pull low batwing gussets toward the torso while retaining shoulder volume."""
    changed = 0
    for vertex in obj.data.vertices:
        x, _y, z = vertex.co
        ax = abs(x)
        if not (0.225 < ax < 0.55 and 1.00 < z < 1.38):
            continue
        shoulder_rise = smoothstep(1.08, 1.38, z)
        target_half_width = 0.225 + 0.135 * shoulder_rise
        if ax <= target_half_width:
            continue
        pull = 0.94 * (1.0 - smoothstep(1.28, 1.38, z))
        new_ax = target_half_width + (ax - target_half_width) * (1.0 - pull)
        vertex.co.x = math.copysign(new_ax, x)
        changed += 1
    obj.data.update()
    return changed


def create_rounded_glove(side: int, rig: bpy.types.Object, leather: bpy.types.Material) -> bpy.types.Object:
    """Create a rounded five-lobed glove with no spear-like fingertip."""
    pieces: list[bpy.types.Object] = []

    def add_ellipsoid(location, scale, rotation_z=0.0):
        bpy.ops.mesh.primitive_uv_sphere_add(
            segments=28,
            ring_count=18,
            location=location,
            rotation=(0.0, 0.0, rotation_z),
        )
        piece = bpy.context.active_object
        piece.scale = scale
        active_object(piece)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        pieces.append(piece)

    # A shallow rounded finger block avoids both the former spear-like tip and
    # the later over-separated finger-lobe silhouette.
    add_ellipsoid((side * 0.806, -0.019, 1.424), (0.028, 0.044, 0.030))
    add_ellipsoid((side * 0.855, -0.019, 1.424), (0.050, 0.041, 0.024))
    add_ellipsoid((side * 0.907, -0.019, 1.421), (0.050, 0.034, 0.018))
    add_ellipsoid(
        (side * 0.858, -0.052, 1.414),
        (0.030, 0.014, 0.012),
        -side * math.radians(50.0),
    )

    active_object(pieces[0])
    for piece in pieces:
        piece.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    glove = bpy.context.active_object
    suffix = "L" if side > 0 else "R"
    glove.name = f"Mercenary_LeatherGlove_{suffix}_LOD0"
    glove.data.name = glove.name + "_Mesh"

    glove.data.remesh_voxel_size = 0.0032
    glove.data.remesh_voxel_adaptivity = 0.0
    glove.data.use_remesh_preserve_volume = True
    active_object(glove)
    bpy.ops.object.voxel_remesh()

    bm = bmesh.new()
    bm.from_mesh(glove.data)
    for _ in range(2):
        bmesh.ops.smooth_vert(
            bm,
            verts=list(bm.verts),
            factor=0.10,
            use_axis_x=True,
            use_axis_y=True,
            use_axis_z=True,
        )
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(glove.data)
    bm.free()
    glove.data.update()

    current_triangles = triangle_count(glove)
    if current_triangles > 2600:
        decimate = glove.modifiers.new("Glove_GameReady_Decimate", "DECIMATE")
        decimate.ratio = 2400.0 / current_triangles
        decimate.use_collapse_triangulate = True
        apply_modifier(glove, decimate)

    for polygon in glove.data.polygons:
        polygon.use_smooth = True
    active_object(glove)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")

    glove.data.materials.clear()
    glove.data.materials.append(leather)
    hand_name = f"DEF-hand.{suffix}"
    forearm_name = f"DEF-forearm.{suffix}.001"
    hand_group = glove.vertex_groups.new(name=hand_name)
    forearm_group = glove.vertex_groups.new(name=forearm_name)
    for vertex in glove.data.vertices:
        outward = side * vertex.co.x
        blend = max(0.0, min(1.0, (outward - 0.790) / 0.055))
        smooth = blend * blend * (3.0 - 2.0 * blend)
        hand_weight = 0.74 + 0.26 * smooth
        hand_group.add([vertex.index], hand_weight, "REPLACE")
        forearm_group.add([vertex.index], 1.0 - hand_weight, "REPLACE")
    glove.parent = rig
    glove.matrix_parent_inverse = rig.matrix_world.inverted()
    armature = glove.modifiers.new("Mercenary_Rigify_Deform", "ARMATURE")
    armature.object = rig
    armature.use_deform_preserve_volume = True
    glove["part_category"] = "ClothedBody"
    glove["construction"] = "Closed rounded five-lobed leather glove"
    return glove


def look_at(camera: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene
rig = bpy.data.objects.get(RIG_NAME)
tunic = bpy.data.objects.get(TUNIC_NAME)
if rig is None or tunic is None:
    raise RuntimeError("Final rig or repaired tunic is missing")

gambeson = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
outer_wool = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
leather = (
    bpy.data.materials.get("MAT_Leather_Side_PBR_4K")
    or bpy.data.materials.get("MAT_Leather_Worn_4K")
    or bpy.data.materials.get("MAT_Leather_Worn_4K.003")
)
if gambeson is None or outer_wool is None or leather is None:
    raise RuntimeError("Required production materials are missing")

underarm_vertices_adjusted = polish_underarm_silhouette(tunic)

# The previous near-black polygon islands were structurally closed but could
# look like empty space on the dark viewer. Keep the visible upper garment one
# coherent quilted material. Only the hidden lower backing stays dark wool.
tunic.data.materials.clear()
tunic.data.materials.append(gambeson)
for polygon in tunic.data.polygons:
    polygon.material_index = 0
    polygon.use_smooth = True

for side, suffix in ((1, "L"), (-1, "R")):
    old_glove = bpy.data.objects.get(f"Mercenary_LeatherGlove_{suffix}_LOD0")
    if old_glove is not None:
        remove_object_and_mesh(old_glove)
gloves = [create_rounded_glove(1, rig, leather), create_rounded_glove(-1, rig, leather)]

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None
]
deform_bones = sum(bone.use_deform for bone in rig.data.bones)
total_triangles = sum(triangle_count(obj) for obj in character_meshes)
new_part_topology = {obj.name: topology_stats(obj) for obj in [tunic, *gloves]}
new_part_weights = {obj.name: weight_stats(obj) for obj in [tunic, *gloves]}

if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")
if deform_bones != 160:
    raise RuntimeError(f"Deform bone count failed: {deform_bones}")
for name, stats in new_part_topology.items():
    if stats != {
        "components": 1,
        "boundary_edges": 0,
        "nonmanifold_edges": 0,
        "overconnected_edges": 0,
    }:
        raise RuntimeError(f"Topology failed for {name}: {stats}")
for name, stats in new_part_weights.items():
    if stats["unweighted_vertices"] or stats["maximum_influences"] > 4:
        raise RuntimeError(f"Weighting failed for {name}: {stats}")

# Temporary neutral-light QA stage.
PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
scene.render.film_transparent = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("Visual_Polish_QA_World")
scene.world.use_nodes = True
world_background = scene.world.node_tree.nodes.get("Background")
world_background.inputs[0].default_value = (0.17, 0.18, 0.20, 1.0)
world_background.inputs[1].default_value = 0.34

qa_objects: list[bpy.types.Object] = []
for name, location, energy, size, color in (
    ("VisualPolish_Key", (-2.2, -2.7, 3.4), 620.0, 2.6, (1.0, 0.86, 0.73)),
    ("VisualPolish_Fill", (2.5, -1.4, 2.5), 380.0, 2.3, (0.68, 0.80, 1.0)),
    ("VisualPolish_Rim", (0.4, 2.6, 2.8), 500.0, 2.0, (0.75, 0.86, 1.0)),
    ("VisualPolish_Top", (0.0, 0.0, 4.1), 320.0, 2.0, (1.0, 0.95, 0.86)),
):
    light_data = bpy.data.lights.new(name + "_Data", "AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_data.color = color
    light = bpy.data.objects.new(name, light_data)
    scene.collection.objects.link(light)
    light.location = location
    qa_objects.append(light)

camera_data = bpy.data.cameras.new("VisualPolish_Camera_Data")
camera = bpy.data.objects.new("VisualPolish_Camera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
qa_objects.append(camera)
camera.data.type = "PERSP"
camera.data.lens = 72

previews = {}
views = {
    "front": ((0.0, -4.0, 1.10), (0.0, 0.0, 0.98)),
    "back": ((0.0, 4.0, 1.10), (0.0, 0.0, 0.98)),
    "high": ((2.55, -3.20, 2.55), (0.0, 0.0, 1.05)),
    "top": ((0.0, -0.02, 5.2), (0.0, 0.0, 1.05)),
}
for label, (location, target) in views.items():
    camera.location = location
    look_at(camera, target)
    path = PREVIEW_DIR / f"{label}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    previews[label] = str(path)

report = {
    "saved_production": COMMIT,
    "triangles": total_triangles,
    "deform_bones": deform_bones,
    "tunic_material_policy": "single continuous 4K gambeson; no black hole-like islands",
    "underarm_vertices_adjusted": underarm_vertices_adjusted,
    "topology": new_part_topology,
    "weights": new_part_weights,
    "glove_triangles": {obj.name: triangle_count(obj) for obj in gloves},
    "previews": previews,
}
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("VISUAL_POLISH_REPORT", json.dumps(report, sort_keys=True))

if COMMIT:
    for obj in qa_objects:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if getattr(data, "users", 1) == 0:
            if isinstance(data, bpy.types.Light):
                bpy.data.lights.remove(data)
            elif isinstance(data, bpy.types.Camera):
                bpy.data.cameras.remove(data)

    for text_block in bpy.data.texts:
        text_block.use_module = False
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

    bpy.context.preferences.filepaths.save_version = 0
    active_object(tunic)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)

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

    properties = set(bpy.ops.export_scene.gltf.get_rna_type().properties.keys())
    export_arguments = {
        "filepath": str(GLB),
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
    active_object(tunic)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), check_existing=False)

    summary = json.loads(SUMMARY.read_text(encoding="utf-8"))
    summary["triangles"] = total_triangles
    summary["triangle_breakdown"] = {
        obj.name: triangle_count(obj)
        for obj in sorted(character_meshes, key=lambda item: item.name)
    }
    summary["previews"] = previews
    summary.setdefault("continuous_upper_repair", {})["visual_polish"] = {
        "removed_near_black_upper_islands": True,
        "rounded_closed_gloves": [obj.name for obj in gloves],
        "topology": new_part_topology,
        "weights": new_part_weights,
    }
    SUMMARY.write_text(json.dumps(summary, indent=2, sort_keys=True), encoding="utf-8")
    print("VISUAL_POLISH_COMMIT_BLEND", BLEND)
    print("VISUAL_POLISH_COMMIT_GLB", GLB)
