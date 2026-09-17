"""Build a clean upper-torso bridge under the selected one-piece cowl.

This remains an isolated review candidate.  It does not touch the production
GLB or the interactive viewer.
"""

from __future__ import annotations

from collections import defaultdict
import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16ze_integrated_upper_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zf_clean_upper_bridge_candidate.blend"
REPORT = STAGING / "v16zf_clean_upper_bridge_report.json"


def clamp(value, lo=0.0, hi=1.0):
    return max(lo, min(hi, value))


def smoothstep(value):
    value = clamp(value)
    return value * value * (3.0 - 2.0 * value)


def triangles(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def topology(obj):
    edge_faces = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        verts = list(poly.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            edge_faces[tuple(sorted((a, b)))] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        stack = [unseen.pop()]
        while stack:
            found = adjacency[stack.pop()] & unseen
            unseen.difference_update(found)
            stack.extend(found)
    return sum(count != 2 for count in edge_faces.values()), components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
asset_collection = donor.users_collection[0]

# Retire any earlier bridge if the script is re-run on an iterated candidate.
old = bpy.data.objects.get("Mercenary_CleanUpperGarmentBridge_v16zf_LOD0")
if old is not None:
    old_mesh = old.data
    bpy.data.objects.remove(old, do_unlink=True)
    if old_mesh.users == 0:
        bpy.data.meshes.remove(old_mesh)

# Remove only the torn scan fragments which sit under the new cowl/bridge.
# The threshold rises toward the arms, preserving the intact chest and outer
# forearms while eliminating the central spikes and the floating rear flap.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    central_cut = ax < 0.285 and center.z > 1.315
    shoulder_cut = 0.285 <= ax < 0.455 and center.z > (1.365 + 0.10 * (ax - 0.285))
    rear_flap = ax < 0.24 and center.y > 0.145 and center.z > 1.285
    if central_cut or shoulder_cut or rear_flap:
        remove_faces.append(face)
removed_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vert for vert in bm.verts if not vert.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zf_removed_hidden_upper_fragments"] = removed_faces

# A shallow, closed wool yoke bridges the cowl to the torso and shoulders.
# It is a single draped garment panel, not another circular scarf ring.
source_material = bpy.data.materials.get("MAT_OuterWool_Side_PBR_4K")
if source_material is None:
    source_material = bpy.data.materials.get("MAT_Cowl_CompactCrumpled_v16_4K")
if source_material is None:
    selected_cowl = bpy.data.objects.get("Mercenary_IntegratedDrapedCowl_v16ze_LOD0")
    if selected_cowl is not None and selected_cowl.data.materials:
        source_material = selected_cowl.data.materials[0]
if source_material is None:
    source_material = bpy.data.materials.get("MAT_Cowl_CoherentDarkWool_v16z_4K")
if source_material is None:
    source_material = bpy.data.materials.get("MAT_Cowl_HeavyWool_4K")
if source_material is None:
    raise RuntimeError("Missing dark wool material for upper garment bridge")
bridge_material = source_material.copy()
bridge_material.name = "MAT_UpperGarmentBridge_DarkWool_v16zf_4K"

ANG = 192
RADIAL = 11
THICKNESS = 0.009
vertices = []
faces = []


def bridge_point(theta, radial, underside=False):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    # Neck opening under the upright cowl.
    inner_rx = 0.118 + 0.006 * math.sin(2.0 * theta + 0.3)
    inner_ry = 0.092 + 0.008 * back
    # Draped shoulder outline.  Back coverage is intentionally deeper so the
    # old scan's rear collar seam can never be seen from above.
    outer_rx = 0.292 + 0.014 * side ** 5 + 0.004 * left
    outer_ry = 0.130 + 0.018 * front + 0.090 * back
    eased = smoothstep(radial)
    rx = inner_rx * (1.0 - eased) + outer_rx * eased
    ry = inner_ry * (1.0 - eased) + outer_ry * eased

    # The panel slopes gently from neck to shoulder.  Broad asymmetric sags
    # keep the silhouette cloth-like without making stacked concentric rings.
    inner_z = 1.442 + 0.010 * back - 0.004 * front
    outer_z = 1.315 + 0.020 * side + 0.010 * back - 0.008 * front
    z = inner_z * (1.0 - eased) + outer_z * eased
    z += math.sin(math.pi * radial) ** 1.35 * (
        0.007 * math.sin(theta - 0.8)
        + 0.0035 * math.sin(3.0 * theta + 1.2)
        - 0.005 * front
    )
    if underside:
        z -= THICKNESS
    return (-0.003 + rx * c, 0.018 + ry * s, z)


surface_size = ANG * RADIAL
for underside in (False, True):
    for ri in range(RADIAL):
        radial = ri / (RADIAL - 1)
        for ai in range(ANG):
            theta = math.tau * ai / ANG
            vertices.append(bridge_point(theta, radial, underside))

for ri in range(RADIAL - 1):
    for ai in range(ANG):
        nxt = (ai + 1) % ANG
        a = ri * ANG + ai
        b = (ri + 1) * ANG + ai
        c = (ri + 1) * ANG + nxt
        d = ri * ANG + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

outer_start = (RADIAL - 1) * ANG
for ai in range(ANG):
    nxt = (ai + 1) % ANG
    faces.append((ai, nxt, surface_size + nxt, surface_size + ai))
    faces.append((outer_start + ai, surface_size + outer_start + ai,
                  surface_size + outer_start + nxt, outer_start + nxt))

mesh = bpy.data.meshes.new("Mercenary_CleanUpperGarmentBridge_v16zf_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
bridge = bpy.data.objects.new("Mercenary_CleanUpperGarmentBridge_v16zf_LOD0", mesh)
asset_collection.objects.link(bridge)
mesh.materials.append(bridge_material)
for polygon in mesh.polygons:
    polygon.use_smooth = True

bpy.ops.object.select_all(action="DESELECT")
bridge.select_set(True)
bpy.context.view_layer.objects.active = bridge
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

groups = {name: bridge.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-shoulder.L", "DEF-shoulder.R",
)}
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    side = smoothstep((abs(x) - 0.17) / 0.17)
    upper = smoothstep((z - 1.37) / 0.08)
    shoulder = 0.58 * side * (1.0 - 0.30 * upper)
    spine5 = 0.46 + 0.38 * upper - 0.20 * side
    spine4 = max(0.0, 1.0 - shoulder - spine5)
    weights = {
        "DEF-spine.004": spine4,
        "DEF-spine.005": spine5,
        "DEF-shoulder.L": shoulder if x >= 0.0 else 0.0,
        "DEF-shoulder.R": shoulder if x < 0.0 else 0.0,
    }
    total = sum(weights.values())
    for name, weight in weights.items():
        if weight > 0.0:
            groups[name].add([vertex.index], weight / total, "REPLACE")

modifier = bridge.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_vertex_groups = True
bridge.parent = rig
bridge.matrix_parent_inverse = rig.matrix_world.inverted()
bridge["game_asset"] = True
bridge["part_category"] = "ClothedBody"
bridge["source"] = "V16ZF clean closed upper garment bridge under one-piece cowl"

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
scene.render.resolution_percentage = 100
scene.view_settings.look = "AgX - Medium High Contrast"
if scene.world and scene.world.use_nodes:
    background = scene.world.node_tree.nodes.get("Background")
    if background:
        background.inputs[0].default_value = (0.018, 0.020, 0.024, 1.0)
        background.inputs[1].default_value = 0.22

camera = scene.camera
camera.data.type = "PERSP"


def render(key, location, target, lens=82, resolution=(1200, 1000)):
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    path = PREVIEWS / f"diagnostic_v16zf_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
previews = {
    "top_close": render("clean_upper_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("clean_upper_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.46), 86),
    "upper_three_quarter": render("clean_upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.43), 88),
    "front": render("clean_upper_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("clean_upper_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

nonmanifold, components = topology(bridge)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in mesh.vertices]
character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and obj.get("part_category") is not None and not obj.hide_render
]
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "bridge": bridge.name,
    "bridge_triangles": triangles(bridge),
    "bridge_components": components,
    "bridge_nonmanifold_edges": nonmanifold,
    "bridge_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "removed_hidden_upper_fragments": removed_faces,
    "mesh_count": len(character_meshes),
    "total_triangles": sum(triangles(obj) for obj in character_meshes),
    "deform_bones": sum(1 for bone in rig.data.bones if bone.use_deform),
    "previews": previews,
}
bridge["v16zf_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZF_REPORT=" + json.dumps(report, sort_keys=True))
