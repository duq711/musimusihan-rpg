"""Fuse the donor-derived scarf folds and add tapered padded upper sleeves."""

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
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16aae_fused_scan_scarf_tapered_sleeves.blend"
REPORT = STAGING / "v16aae_fused_scan_scarf_tapered_sleeves_report.json"
COWL_NAME = "Mercenary_Cowl_LayeredClean_LOD0"
NEW_COWL_NAME = "Mercenary_FusedDonorFoldScarf_v16aae_LOD0"
SLEEVES_NAME = "Mercenary_TaperedQuiltedUpperSleeves_v16aae_LOD0"
REMOVE_UPPER = (
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            counts[tuple(sorted((a, b)))] += 1
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
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "overconnected_edges": sum(value > 2 for value in counts.values()),
    }


def build_weight_samples(obj, minimum_z=None):
    group_names = {group.index: group.name for group in obj.vertex_groups}
    samples = []
    for vertex in obj.data.vertices:
        if minimum_z is not None and vertex.co.z < minimum_z:
            continue
        weights = {
            group_names[item.group]: item.weight
            for item in vertex.groups
            if item.group in group_names and item.weight > 1.0e-6
        }
        if weights:
            samples.append((vertex.co.copy(), weights))
    tree = KDTree(len(samples))
    for index, (position, _weights) in enumerate(samples):
        tree.insert(position, index)
    tree.balance()
    return samples, tree


def assign_nearest_weights(obj, samples, tree):
    obj.vertex_groups.clear()
    groups = {}
    for vertex in obj.data.vertices:
        _co, sample_index, _distance = tree.find(vertex.co)
        ranked = sorted(samples[sample_index][1].items(), key=lambda item: item[1], reverse=True)[:4]
        total = sum(weight for _name, weight in ranked)
        if total <= 1.0e-8:
            ranked = [("DEF-spine.005", 1.0)]
            total = 1.0
        for name, weight in ranked:
            group = groups.get(name)
            if group is None:
                group = obj.vertex_groups.new(name=name)
                groups[name] = group
            group.add([vertex.index], weight / total, "REPLACE")


def add_armature(obj, rig):
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    modifier = obj.modifiers.new("RigifyDeform", "ARMATURE")
    modifier.object = rig
    modifier.use_deform_preserve_volume = True
    obj.parent = rig
    obj.matrix_parent_inverse = rig.matrix_world.inverted()


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects[COWL_NAME]
asset_collection = donor.users_collection[0]

# Remove the old stop-gap patches, but keep the donor body untouched.
removed_objects = []
for name in REMOVE_UPPER:
    obj = bpy.data.objects.get(name)
    if obj is None:
        continue
    mesh = obj.data
    bpy.data.objects.remove(obj, do_unlink=True)
    if mesh.users == 0:
        bpy.data.meshes.remove(mesh)
    removed_objects.append(name)

# Preserve original Rigify weights before voxel union.
cowl_samples, cowl_tree = build_weight_samples(cowl)
for modifier in list(cowl.modifiers):
    if modifier.type == "ARMATURE":
        cowl.modifiers.remove(modifier)
cowl.vertex_groups.clear()
cowl.name = NEW_COWL_NAME
cowl.data.name = "Mercenary_FusedDonorFoldScarf_v16aae_Mesh"

# The three donor-derived folds are 0.6–2.6 mm apart.  A 4 mm voxel union
# closes those microscopic gaps while retaining their photographed drape.
bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
cowl.data.remesh_voxel_size = 0.0040
cowl.data.remesh_voxel_adaptivity = 0.0
cowl.data.use_remesh_preserve_volume = True
bpy.ops.object.voxel_remesh()

# If a fold remained detached, one slightly coarser pass fuses the chain.
if topology(cowl)["components"] != 1:
    cowl.data.remesh_voxel_size = 0.0052
    bpy.ops.object.voxel_remesh()

# Relax voxel stair-stepping without erasing the broad donor folds.
bm = bmesh.new()
bm.from_mesh(cowl.data)
for _iteration in range(2):
    bmesh.ops.smooth_vert(
        bm, verts=list(bm.verts), factor=0.12,
        use_axis_x=True, use_axis_y=True, use_axis_z=True,
    )
bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()

# Keep the fused scarf efficient and within the game triangle target.
before_decimate = triangles(cowl)
if before_decimate > 30000:
    decimate = cowl.modifiers.new("GameReadyDecimate", "DECIMATE")
    decimate.ratio = 28000.0 / before_decimate
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)

# Rebuild UVs and material after remesh.
cowl.data.materials.clear()
cowl_material = bpy.data.materials.get("MAT_CowlWool_Side_PBR_4K")
if cowl_material is None:
    cowl_material = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
cowl.data.materials.append(cowl_material)
for poly in cowl.data.polygons:
    poly.material_index = 0
    poly.use_smooth = True
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.12, island_margin=0.012, area_weight=0.30)
bpy.ops.object.mode_set(mode="OBJECT")
assign_nearest_weights(cowl, cowl_samples, cowl_tree)
add_armature(cowl, rig)
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16AAE voxel-unified donor-derived natural scarf folds"
cowl["separate_cowl_rings"] = 0

# -------------------------------------------------------------------------
# Low-profile padded sleeves.  Each sleeve is a tapered, sloped cloth volume
# rather than the previous constant-radius rectangular cushion.
# -------------------------------------------------------------------------
donor_samples, donor_tree = build_weight_samples(donor, minimum_z=1.18)
AXIAL = 56
CIRC = 48
sleeve_vertices = []
sleeve_faces = []
sleeve_uv = []


def sleeve_point(side, t, theta):
    # t=0 is buried beneath the scarf/torso; t=1 overlaps the forearm.
    eased = t * t * (3.0 - 2.0 * t)
    x = side * (0.135 + 0.485 * t)
    center_y = 0.018 + side * 0.002 * math.sin(math.pi * t)
    center_z = 1.447 - 0.030 * eased + 0.004 * math.sin(math.pi * t)
    radius_y = 0.112 * (1.0 - eased) + 0.073 * eased
    radius_z = 0.101 * (1.0 - eased) + 0.068 * eased
    # Broad compression and small cloth creases break the tube silhouette.
    broad = 0.007 * math.sin(math.pi * t) * math.cos(2.0 * theta + 0.5 * side)
    crease = 0.0032 * math.sin(5.0 * math.pi * t + 1.8 * theta + 0.4 * side)
    crease *= math.sin(math.pi * t) ** 0.8
    radius_y += broad + crease
    radius_z += 0.62 * broad + 0.75 * crease
    y = center_y + radius_y * math.cos(theta)
    z = center_z + radius_z * math.sin(theta)
    # Slight twist gives the padded cloth an organic shoulder roll.
    y += 0.004 * math.sin(math.pi * t) * math.sin(theta + side * 0.7)
    z += 0.003 * math.sin(math.pi * t) * math.cos(theta - side * 0.5)
    return x, y, z


for side in (-1, 1):
    start = len(sleeve_vertices)
    for axial in range(AXIAL + 1):
        t = axial / AXIAL
        for circum in range(CIRC):
            theta = math.tau * circum / CIRC
            sleeve_vertices.append(sleeve_point(side, t, theta))
            sleeve_uv.append((t * 2.4, circum / CIRC * 2.0))
    inner_center = len(sleeve_vertices)
    sleeve_vertices.append(sleeve_point(side, 0.0, 0.0))
    sleeve_vertices[inner_center] = (
        side * 0.135, 0.018, 1.447
    )
    sleeve_uv.append((0.0, 1.0))
    outer_center = len(sleeve_vertices)
    sleeve_vertices.append(sleeve_point(side, 1.0, 0.0))
    sleeve_vertices[outer_center] = (
        side * 0.620, 0.018, 1.417
    )
    sleeve_uv.append((2.4, 1.0))

    def index(axial, circum):
        return start + axial * CIRC + (circum % CIRC)

    for axial in range(AXIAL):
        for circum in range(CIRC):
            nxt = (circum + 1) % CIRC
            sleeve_faces.append((
                index(axial, circum), index(axial + 1, circum),
                index(axial + 1, nxt), index(axial, nxt),
            ))
    for circum in range(CIRC):
        nxt = (circum + 1) % CIRC
        if side < 0:
            sleeve_faces.append((inner_center, index(0, circum), index(0, nxt)))
            sleeve_faces.append((outer_center, index(AXIAL, nxt), index(AXIAL, circum)))
        else:
            sleeve_faces.append((inner_center, index(0, nxt), index(0, circum)))
            sleeve_faces.append((outer_center, index(AXIAL, circum), index(AXIAL, nxt)))

sleeve_mesh = bpy.data.meshes.new("Mercenary_TaperedQuiltedUpperSleeves_v16aae_Mesh")
sleeve_mesh.from_pydata(sleeve_vertices, [], sleeve_faces)
sleeve_mesh.update()
sleeves = bpy.data.objects.new(SLEEVES_NAME, sleeve_mesh)
asset_collection.objects.link(sleeves)
gambeson_material = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
sleeve_mesh.materials.append(gambeson_material)
uv_layer = sleeve_mesh.uv_layers.new(name="UVMap")
for poly in sleeve_mesh.polygons:
    poly.material_index = 0
    poly.use_smooth = True
    for loop_index in poly.loop_indices:
        vertex_index = sleeve_mesh.loops[loop_index].vertex_index
        uv_layer.data[loop_index].uv = sleeve_uv[vertex_index]
assign_nearest_weights(sleeves, donor_samples, donor_tree)
add_armature(sleeves, rig)
sleeves["game_asset"] = True
sleeves["part_category"] = "ClothedBody"
sleeves["intentional_layer"] = True
sleeves["source"] = "V16AAE tapered sloped quilted shoulder sleeves"

# QA structure before rendering.
checks = {}
for obj, expected_components in ((cowl, 1), (sleeves, 2)):
    stats = topology(obj)
    weights = [sum(item.weight for item in vertex.groups) for vertex in obj.data.vertices]
    if stats["components"] != expected_components or stats["nonmanifold_edges"] != 0:
        raise RuntimeError(f"Topology failed: {obj.name}: {stats}")
    if min(weights) < 0.999 or max(weights) > 1.001:
        raise RuntimeError(f"Weights failed: {obj.name}: {min(weights)}..{max(weights)}")
    checks[obj.name] = {
        "triangles": triangles(obj), "topology": stats,
        "weight_sum_range": [min(weights), max(weights)],
        "rigify": any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers),
    }

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

lights = []
for name, location, energy, size, color in (
    ("V16AAE_QA_Key", (-2.2, -2.6, 3.3), 72.0, 2.5, (1.0, 0.82, 0.68)),
    ("V16AAE_QA_Fill", (2.4, -1.5, 2.5), 38.0, 2.2, (0.62, 0.76, 1.0)),
    ("V16AAE_QA_Rim", (0.3, 2.4, 2.7), 52.0, 2.0, (0.72, 0.82, 1.0)),
):
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy, data.shape, data.size, data.color = energy, "DISK", size, color
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = location
    look_at(light, (0.0, 0.01, 1.43))
    lights.append(light)

camera = scene.camera
PREVIEWS.mkdir(parents=True, exist_ok=True)


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16aae_fused_scan_{key}.png"
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
    obj for obj in scene.objects if obj.type == "MESH"
    and obj.get("part_category") is not None
    and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
if not 100000 <= total_triangles <= 150000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

report = {
    "source": str(SOURCE), "candidate": str(OUTPUT), "production_modified": False,
    "removed_stopgap_objects": removed_objects,
    "cowl": cowl.name, "sleeves": sleeves.name,
    "cowl_triangles_before_decimate": before_decimate,
    "checks": checks,
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "mesh_count": len(character_meshes), "total_triangles": total_triangles,
    "previews": previews,
}
for text_block in bpy.data.texts:
    text_block.use_module = False
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16AAE_REPORT=" + json.dumps(report, sort_keys=True))
