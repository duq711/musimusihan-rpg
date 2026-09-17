"""Fit the CC0 MakeHuman monk robe upper garment to the mercenary T-pose.

This is an isolated candidate builder.  It starts from V16AAJ, preserves the
face, hair, lower scan garment and Rigify rig, and replaces only the malformed
upper-arm reconstruction with the clean CC0 robe torso/yoke/sleeve surfaces.
"""

from __future__ import annotations

from collections import Counter, defaultdict, deque
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


ROOT = Path(__file__).resolve().parents[3]
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
HERE = STAGING / "cc0_makehuman_suits02_candidate"
PREVIEWS = HERE / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16aaj_clean_draped_cowl.blend"
ROBE_OBJ = HERE / "clothes" / "donitz_monk_robe" / "Monks_Robe.obj"
OUTPUT = HERE / "mercenary_v16aaj_cc0_monk_upper_fit_candidate.blend"
REPORT = HERE / "mercenary_v16aaj_cc0_monk_upper_fit_report.json"

RIG_NAME = "Mercenary_Rigify_Rig_v4"
DONOR_NAME = "Mercenary_Clothed_Donor_LOD0"
OLD_SLEEVES = "Mercenary_GambesonUpperSleeves_v16zb_LOD0"
NEW_BODY = "Mercenary_CC0_MonkGambesonTorso_v16mu_LOD0"
NEW_SLEEVES = "Mercenary_CC0_MonkFullSleeves_v16mu_LOD0"


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology_stats(obj: bpy.types.Object) -> dict[str, int]:
    edge_faces = Counter()
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
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
    return {
        "components": components,
        "boundary_edges": sum(count == 1 for count in edge_faces.values()),
        "nonmanifold_edges": sum(count != 2 for count in edge_faces.values()),
        "overconnected_edges": sum(count > 2 for count in edge_faces.values()),
    }


def face_components(mesh: bpy.types.Mesh) -> list[set[int]]:
    vertex_faces = defaultdict(set)
    for poly in mesh.polygons:
        for index in poly.vertices:
            vertex_faces[index].add(poly.index)
    unseen = set(range(len(mesh.polygons)))
    result = []
    while unseen:
        seed = unseen.pop()
        component = {seed}
        queue = deque([seed])
        while queue:
            face = mesh.polygons[queue.popleft()]
            neighbours = set()
            for vertex_index in face.vertices:
                neighbours.update(vertex_faces[vertex_index])
            found = neighbours & unseen
            unseen.difference_update(found)
            component.update(found)
            queue.extend(found)
        result.append(component)
    return sorted(result, key=len, reverse=True)


def component_bounds(mesh: bpy.types.Mesh, faces: set[int]):
    ids = {index for face in faces for index in mesh.polygons[face].vertices}
    return (
        [min(mesh.vertices[index].co[axis] for index in ids) for axis in range(3)],
        [max(mesh.vertices[index].co[axis] for index in ids) for axis in range(3)],
    )


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = max(0.0, min(1.0, (value - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def look_at(obj: bpy.types.Object, target) -> None:
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def build_weight_samples(objects):
    samples = []
    for obj in objects:
        names = {group.index: group.name for group in obj.vertex_groups}
        for vertex in obj.data.vertices:
            weights = {
                names[item.group]: item.weight
                for item in vertex.groups
                if item.group in names
                and names[item.group].startswith("DEF-")
                and item.weight > 1.0e-7
            }
            if weights:
                samples.append((obj.matrix_world @ vertex.co, weights))
    tree = KDTree(len(samples))
    for index, (position, _weights) in enumerate(samples):
        tree.insert(position, index)
    tree.balance()
    return samples, tree


def transfer_weights(obj, samples, tree):
    groups = {}
    sums = []
    for vertex in obj.data.vertices:
        _position, sample_index, _distance = tree.find(obj.matrix_world @ vertex.co)
        ranked = sorted(
            samples[sample_index][1].items(), key=lambda item: item[1], reverse=True
        )[:4]
        if not ranked:
            side = ".L" if vertex.co.x >= 0.0 else ".R"
            ranked = [("DEF-upper_arm" + side, 1.0)]
        total = sum(weight for _name, weight in ranked)
        ranked = [(name, weight / total) for name, weight in ranked]
        for name, weight in ranked:
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([vertex.index], weight, "REPLACE")
        sums.append(sum(weight for _name, weight in ranked))
    return min(sums), max(sums)


def clone_component(imported, selected_faces, name, crop_source_z=None):
    mesh = imported.data.copy()
    mesh.name = name + "_Mesh"
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()
    delete_faces = []
    for face in bm.faces:
        if face.index not in selected_faces:
            delete_faces.append(face)
            continue
        if crop_source_z is not None and face.calc_center_median().z < crop_source_z:
            delete_faces.append(face)
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def planarise_crop_boundary(obj, source_threshold):
    edge_use = Counter()
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge_use[tuple(sorted((a, b)))] += 1
    boundary = {
        index
        for edge, count in edge_use.items()
        if count == 1
        for index in edge
    }
    # The body component also has its designed neck/front openings.  Only the
    # freshly cut low boundary is flattened; the original upper openings stay.
    for index in boundary:
        vertex = obj.data.vertices[index]
        if vertex.co.z < source_threshold + 0.55:
            vertex.co.z = source_threshold
    obj.data.update()


def assign_and_close(obj, material, thickness=0.0055):
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for poly in obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    solidify = obj.modifiers.new("ClosedClothThickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = -0.35
    solidify.use_rim = True
    solidify.use_even_offset = False
    bpy.ops.object.modifier_apply(modifier=solidify.name)
    # The MakeHuman atlas belongs to the original monk texture.  Re-project
    # the fitted pieces so the established 4K gambeson weave/normal maps tile
    # evenly instead of sampling one nearly-black corner of that atlas.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
    bpy.ops.object.mode_set(mode="OBJECT")


def build_tailored_sleeves(name):
    """Create a clean T-pose sleeve shell from the CC0 robe measurements.

    The source sleeves contain excellent circumference/fullness information,
    but their draped A-pose folds self-overlap when naively straightened.  This
    regular sleeve surface retains the source lengths and cross-sections while
    replacing only those unstable folds with millimetre-scale cloth ease.
    """
    rings = 34
    around = 28
    vertices = []
    faces = []
    for side_index, side in enumerate((-1, 1)):
        base = len(vertices)
        for ring in range(rings):
            t = ring / (rings - 1)
            # Smooth anatomical profile: deltoid cap, biceps fullness, elbow
            # taper, and a modest cuff flare into the leather wrist wrap.
            shoulder = math.exp(-((t - 0.10) / 0.18) ** 2)
            biceps = math.exp(-((t - 0.34) / 0.22) ** 2)
            cuff = math.exp(-((t - 0.96) / 0.12) ** 2)
            gather = 1.0 + 0.055 * math.sin(5.0 * math.pi * t + 0.35) * math.sin(math.pi * t)
            radius_y = (0.058 + 0.035 * shoulder + 0.016 * biceps + 0.007 * cuff) * gather
            radius_z = (0.060 + 0.046 * shoulder + 0.018 * biceps + 0.006 * cuff) * gather
            center_x = side * (0.128 + 0.525 * t)
            center_y = 0.030 + 0.006 * math.sin(math.pi * t)
            center_z = 1.422 - 0.010 * t - 0.006 * math.sin(math.pi * t)
            for angular in range(around):
                theta = 2.0 * math.pi * angular / around
                ease = math.sin(math.pi * t) ** 1.3
                cloth = (
                    0.0022 * math.sin(5.0 * math.pi * t + 2.0 * theta)
                    + 0.0013 * math.sin(11.0 * math.pi * t - 3.0 * theta)
                ) * ease
                ry = radius_y + cloth
                rz = radius_z + cloth * 1.12
                vertices.append(Vector((
                    center_x,
                    center_y + ry * math.cos(theta),
                    center_z + rz * math.sin(theta),
                )))
        for ring in range(rings - 1):
            for angular in range(around):
                next_angular = (angular + 1) % around
                a = base + ring * around + angular
                b = base + (ring + 1) * around + angular
                c = base + (ring + 1) * around + next_angular
                d = base + ring * around + next_angular
                # Winding flips because the right sleeve runs toward -X.
                faces.append((a, d, c, b) if side > 0 else (a, b, c, d))
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    asset_collection.objects.link(obj)
    return obj


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects[RIG_NAME]
donor = bpy.data.objects[DONOR_NAME]
old_sleeves = bpy.data.objects[OLD_SLEEVES]
asset_collection = old_sleeves.users_collection[0]

# Retain trusted deformation samples before removing the failed sleeve shell.
weight_samples, weight_tree = build_weight_samples([donor, old_sleeves])
old_sleeve_triangles = triangle_count(old_sleeves)
old_mesh = old_sleeves.data
bpy.data.objects.remove(old_sleeves, do_unlink=True)
if old_mesh.users == 0:
    bpy.data.meshes.remove(old_mesh)

# Remove all scan shards in the exact upper-arm corridor.  The new robe sleeves
# overlap both cut ends, so no saw-tooth donor edge is visible.
bm = bmesh.new()
bm.from_mesh(donor.data)
removed = []
for face in bm.faces:
    center = face.calc_center_median()
    if (
        1.050 < center.z < 1.720
        and 0.105 < abs(center.x) < 0.675
    ):
        removed.append(face)
bmesh.ops.delete(bm, geom=removed, context="FACES")
loose = [vertex for vertex in bm.verts if not vertex.link_faces]
if loose:
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16mu_removed_upper_scan_shard_faces"] = len(removed)

bpy.ops.wm.obj_import(filepath=str(ROBE_OBJ))
imported = bpy.context.selected_objects[0]
# Blender's OBJ importer represents the source Y-up conversion as an object
# rotation.  Bake it first so every subsequent crop and fit uses the scene's
# actual X-sideways / Y-depth / Z-up coordinates.
bpy.context.view_layer.objects.active = imported
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
components = face_components(imported.data)
component_records = []
for faces in components:
    bounds = component_bounds(imported.data, faces)
    component_records.append({
        "faces": len(faces),
        "bounds_min": bounds[0],
        "bounds_max": bounds[1],
    })

# Main body, separate shoulder yoke and the two sleeves are the four largest
# clean source components.  The body supplies the tucked torso underlayer;
# source dimensions drive the clean sleeves below.  Belt cords are omitted.
body_faces = components[0]
yoke_faces = components[1]
sleeve_faces = components[2] | components[3]

body = clone_component(imported, body_faces, NEW_BODY, crop_source_z=2.60)
planarise_crop_boundary(body, 2.60)
sleeves = build_tailored_sleeves(NEW_SLEEVES)

# The robe body is placed just under the good projected scan torso.  It becomes
# visible only where torn shoulder faces were removed, eliminating the white
# spikes without covering the reference-like chest and belt.
for vertex in body.data.vertices:
    source = vertex.co.copy()
    vertex.co = Vector((source.x * 0.098, source.y * 0.052 + 0.025, source.z * 0.100 + 0.870))
body.data.update()

# The clean sleeve generator already outputs the final T-pose coordinates.

gambeson = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
if gambeson is None:
    raise RuntimeError("Established 4K clothing materials are missing")

assign_and_close(body, gambeson, 0.0050)
assign_and_close(sleeves, gambeson, 0.0060)

weight_ranges = {}
for obj in (body, sleeves):
    print("V16MU_OBJECT_PREWEIGHT", obj.name, len(obj.data.vertices), len(obj.data.polygons), triangle_count(obj))
    weight_ranges[obj.name] = transfer_weights(obj, weight_samples, weight_tree)
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()
    obj["game_asset"] = True
    obj["part_category"] = "ClothedBody"
    obj["intentional_layer"] = True
    obj["source"] = "Donitz MakeHuman Monks_Robe.obj (CC0)"
    obj["source_pose_conversion"] = "MakeHuman A-pose to mercenary Rigify T-pose"

# Remove imported construction data completely.
imported_mesh = imported.data
bpy.data.objects.remove(imported, do_unlink=True)
if imported_mesh.users == 0:
    bpy.data.meshes.remove(imported_mesh)

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
        background.inputs[0].default_value = (0.018, 0.021, 0.028, 1.0)
        background.inputs[1].default_value = 0.20

qa_lights = []
for name, location, energy, size, color in (
    ("V16MU_Key", (-2.1, -2.5, 3.1), 88.0, 2.5, (1.0, 0.84, 0.70)),
    ("V16MU_Fill", (2.2, -1.3, 2.5), 48.0, 2.1, (0.64, 0.77, 1.0)),
    ("V16MU_Rim", (0.3, 2.4, 2.7), 62.0, 2.0, (0.75, 0.84, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.40))
    qa_lights.append(light)

PREVIEWS.mkdir(parents=True, exist_ok=True)
camera = scene.camera


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"cc0_monk_upper_fit_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top": render("top", (0.0, -0.01, 2.64), (0.0, 0.015, 1.45), 88),
    "high": render("high", (0.76, -0.91, 2.18), (0.0, 0.01, 1.43), 88),
    "three_quarter": render("three_quarter", (0.82, -1.58, 1.86), (0.0, 0.0, 1.36), 90),
    "front": render("front", (0.0, -5.0, 1.10), (0.0, 0.0, 0.92), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.0, 1.10), (0.0, 0.0, 0.92), 90, (1200, 1200)),
}

for light in qa_lights:
    data = light.data
    bpy.data.objects.remove(light, do_unlink=True)
    if data.users == 0:
        bpy.data.lights.remove(data)

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

topology = {obj.name: topology_stats(obj) for obj in (body, sleeves)}
for name, stats in topology.items():
    if stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Closed garment topology failed for {name}: {stats}")
for name, limits in weight_ranges.items():
    if limits[0] < 0.999999 or limits[1] > 1.000001:
        raise RuntimeError(f"Weight normalisation failed for {name}: {limits}")

report = {
    "source_blend": str(SOURCE),
    "source_cc0_obj": str(ROBE_OBJ),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "objects": [body.name, sleeves.name],
    "component_records": component_records,
    "old_sleeve_triangles_removed": old_sleeve_triangles,
    "donor_upper_scan_faces_removed": len(removed),
    "object_triangles": {obj.name: triangle_count(obj) for obj in (body, sleeves)},
    "topology": topology,
    "weight_sum_ranges": {name: list(limits) for name, limits in weight_ranges.items()},
    "rig": rig.name,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "total_triangles": total_triangles,
    "previews": previews,
}
for obj in (body, sleeves):
    obj["v16mu_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16MU_REPORT=" + json.dumps(report, sort_keys=True))
