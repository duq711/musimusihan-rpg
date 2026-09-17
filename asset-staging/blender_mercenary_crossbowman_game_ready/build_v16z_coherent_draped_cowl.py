"""Build a compact, coherent medieval wool cowl candidate.

This is an isolated candidate build.  It never overwrites the canonical GLB,
viewer preview, or the last accepted Blender file.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16j_darkbrown_hair_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zd_coherent_upper_candidate.blend"
REPORT = STAGING / "v16zd_coherent_upper_report.json"

REMOVE_NAMES = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


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
    nonmanifold = sum(1 for count in edge_faces.values() if count != 2)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        seed = unseen.pop()
        stack = [seed]
        while stack:
            current = stack.pop()
            for neighbour in adjacency[current]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    stack.append(neighbour)
    return nonmanifold, components


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
asset_collection = donor.users_collection[0]

for name in REMOVE_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)

# Pull only the broken, open collar boundary under the replacement.  The arm
# silhouette itself is left untouched.
edge_count = defaultdict(int)
adjacency = defaultdict(set)
for poly in donor.data.polygons:
    verts = list(poly.vertices)
    for a, b in zip(verts, verts[1:] + verts[:1]):
        key = tuple(sorted((a, b)))
        edge_count[key] += 1
        adjacency[a].add(b)
        adjacency[b].add(a)
boundary = {v for edge, count in edge_count.items() if count == 1 for v in edge}
seeds = {
    index for index in boundary
    if donor.data.vertices[index].co.z > 1.345
    and abs(donor.data.vertices[index].co.x) < 0.405
}
distance = {index: 0 for index in seeds}
queue = deque(seeds)
while queue:
    current = queue.popleft()
    if distance[current] >= 4:
        continue
    for neighbour in adjacency[current]:
        if neighbour not in distance:
            distance[neighbour] = distance[current] + 1
            queue.append(neighbour)

settled = 0
for index, ring in distance.items():
    co = donor.data.vertices[index].co
    if co.z < 1.30 or abs(co.x) > 0.435:
        continue
    ring_fade = (1.0 - ring / 5.0) ** 2
    horizontal_fade = 1.0 - smoothstep((abs(co.x) - 0.315) / 0.12)
    influence = ring_fade * horizontal_fade
    if influence <= 0.001:
        continue
    side = smoothstep((abs(co.x) - 0.16) / 0.22)
    target_x = clamp(co.x, -0.292, 0.292)
    target_y = clamp(co.y, -0.115, 0.155)
    target_z = 1.325 + 0.085 * side
    co.x = co.x * (1.0 - influence) + target_x * influence
    co.y = co.y * (1.0 - influence) + target_y * influence
    co.z = co.z * (1.0 - influence) + min(co.z, target_z) * influence
    settled += 1
donor.data.update()
donor["v16z_tucked_open_collar_vertices"] = settled

# The scan also contains tall, paper-thin spikes inside the shoulder roots.
# Compress that hidden zone to a smooth human shoulder envelope.  The visible
# outer sleeves and hands remain outside this mask.
compressed_shoulder_vertices = 0
for vertex in donor.data.vertices:
    co = vertex.co
    ax = abs(co.x)
    if ax >= 0.455 or co.z <= 1.425:
        continue
    if ax < 0.155:
        allowed_z = 1.455
    else:
        allowed_z = 1.515 - 0.17 * (ax - 0.155)
    if co.z > allowed_z:
        edge_fade = 1.0 - smoothstep((ax - 0.395) / 0.060)
        co.z = co.z * (1.0 - edge_fade) + allowed_z * edge_fade
        compressed_shoulder_vertices += 1
donor.data.update()
donor["v16z_compressed_scan_shoulder_vertices"] = compressed_shoulder_vertices

# Relax the remaining reconstructed shoulder-root triangles in place.  This
# preserves the donor's UVs and skinning while removing the crystalline scan
# spikes that were visible from above.
relax_region = {
    vertex.index for vertex in donor.data.vertices
    if abs(vertex.co.x) < 0.505 and vertex.co.z > 1.285
}
for _iteration in range(8):
    updates = {}
    for index in relax_region:
        neighbours = [n for n in adjacency[index] if n in relax_region]
        if not neighbours:
            continue
        co = donor.data.vertices[index].co
        average = sum((donor.data.vertices[n].co for n in neighbours), Vector()) / len(neighbours)
        ax = abs(co.x)
        strength = 0.48 * (1.0 - smoothstep((ax - 0.405) / 0.10))
        updates[index] = Vector((
            co.x * (1.0 - 0.10 * strength) + average.x * (0.10 * strength),
            co.y * (1.0 - 0.62 * strength) + average.y * (0.62 * strength),
            co.z * (1.0 - strength) + average.z * strength,
        ))
    for index, value in updates.items():
        donor.data.vertices[index].co = value
donor.data.update()
donor["v16z_relaxed_scan_shoulder_vertices"] = len(relax_region)

# Remove only the reconstructed upper-sleeve faces that still form torn fins.
# Their whole visible region is replaced below by clean, rigged gambeson
# sleeves that overlap the untouched forearms and torso.
bm = bmesh.new()
bm.from_mesh(donor.data)
remove_faces = []
for face in bm.faces:
    center = face.calc_center_median()
    ax = abs(center.x)
    if 0.160 < ax < 0.505 and center.z > 1.360:
        remove_faces.append(face)
deleted_donor_faces = len(remove_faces)
if remove_faces:
    bmesh.ops.delete(bm, geom=remove_faces, context="FACES")
    loose = [vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16zb_removed_torn_upper_sleeve_faces"] = deleted_donor_faces

# Reuse the 4K cloth maps while giving the scarf a dark charcoal-brown tint.
source_material = bpy.data.materials.get("MAT_CowlTop_SelectiveCharcoal_PBR_4K")
if source_material is None:
    source_material = bpy.data.materials.get("MAT_Cowl_HeavyWool_4K")
material = source_material.copy()
material.name = "MAT_Cowl_CoherentDarkWool_v16z_4K"
if material.use_nodes:
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    bsdf = next((node for node in nodes if node.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None:
        base = bsdf.inputs.get("Base Color")
        if base is not None and base.links:
            old = base.links[0]
            from_socket = old.from_socket
            links.remove(old)
            tint = nodes.new("ShaderNodeMixRGB")
            tint.name = "V16Z_DarkWoolTint"
            tint.blend_type = "MULTIPLY"
            tint.inputs[0].default_value = 1.0
            tint.inputs[2].default_value = (0.72, 0.66, 0.60, 1.0)
            links.new(from_socket, tint.inputs[1])
            links.new(tint.outputs[0], base)
        rough = bsdf.inputs.get("Roughness")
        if rough is not None and not rough.links:
            rough.default_value = 0.82

# A single closed annular sheet.  Three low-amplitude, wandering relief bands
# are sculpted into the same surface; there are no separate torus objects.
ANG = 224
ROWS = 34
THICK_X = 0.0090
THICK_Y = 0.0085
vertices = []
faces = []


def surface_point(theta, u, inner=False):
    c = math.cos(theta)
    s = math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)

    eased = smoothstep(u)
    rx_top = 0.127 + 0.004 * math.sin(3.0 * theta + 0.2)
    ry_top = 0.116 + 0.004 * math.sin(2.0 * theta - 0.6)
    rx_bottom = 0.205 + 0.040 * side ** 7 + 0.004 * left
    ry_bottom = 0.182 + 0.039 * front + 0.057 * back
    rx = rx_top * (1.0 - eased) + rx_bottom * eased
    ry = ry_top * (1.0 - eased) + ry_bottom * eased

    # Broad, uneven folds.  Each centre wanders independently around the neck
    # so the result reads as compressed cloth, not concentric rings.
    f1 = 0.22 + 0.075 * math.sin(theta + 0.4) + 0.022 * math.sin(3.0 * theta)
    f2 = 0.50 + 0.090 * math.sin(theta - 1.0) - 0.025 * math.sin(2.0 * theta)
    f3 = 0.76 + 0.065 * math.sin(theta + 1.4) + 0.020 * math.sin(4.0 * theta)
    r1 = math.exp(-((u - f1) / 0.105) ** 2)
    r2 = math.exp(-((u - f2) / 0.115) ** 2)
    r3 = math.exp(-((u - f3) / 0.120) ** 2)
    v1 = math.exp(-((u - f1 - 0.105) / 0.075) ** 2)
    v2 = math.exp(-((u - f2 - 0.115) / 0.080) ** 2)
    relief = 0.010 * r1 + 0.017 * r2 + 0.014 * r3 - 0.0045 * v1 - 0.006 * v2
    relief += math.sin(math.pi * u) ** 1.4 * (
        0.0022 * math.sin(5.0 * theta + 6.0 * u)
        + 0.0012 * math.sin(11.0 * theta - 4.0 * u)
    )

    top_z = 1.548 + 0.078 * back ** 2 - 0.021 * front + 0.006 * right
    bottom_z = (
        1.405 - 0.050 * front ** 2 + 0.027 * side
        - 0.008 * back - 0.006 * left
        + 0.004 * math.sin(3.0 * theta + 0.8)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += math.sin(math.pi * u) ** 1.2 * (
        0.008 * r1 + 0.012 * r2 + 0.008 * r3
        + 0.002 * math.sin(4.0 * theta + 5.0 * u)
    )

    if inner:
        rx -= THICK_X
        ry -= THICK_Y
        relief *= 0.45
        z -= 0.0020 * math.sin(math.pi * u)

    x = -0.003 + (rx + relief) * c
    y = 0.014 + (ry + 0.78 * relief) * s
    return (x, y, z)


surface_size = ANG * ROWS
for inner in (False, True):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for ai in range(ANG):
            theta = math.tau * ai / ANG
            vertices.append(surface_point(theta, u, inner))

for row in range(ROWS - 1):
    for ai in range(ANG):
        nxt = (ai + 1) % ANG
        a = row * ANG + ai
        b = (row + 1) * ANG + ai
        c = (row + 1) * ANG + nxt
        d = row * ANG + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

bottom = (ROWS - 1) * ANG
for ai in range(ANG):
    nxt = (ai + 1) % ANG
    faces.append((ai, nxt, surface_size + nxt, surface_size + ai))
    faces.append((bottom + ai, surface_size + bottom + ai,
                  surface_size + bottom + nxt, bottom + nxt))

mesh = bpy.data.meshes.new("Mercenary_CoherentDrapedCowl_v16z_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new("Mercenary_CoherentDrapedCowl_v16z_LOD0", mesh)
asset_collection.objects.link(cowl)
for poly in mesh.polygons:
    poly.use_smooth = True
mesh.materials.append(material)

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

# Rigify-compatible deformation weights.
groups = {name: cowl.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-shoulder.L", "DEF-shoulder.R",
    "DEF-upper_arm.L", "DEF-upper_arm.R",
)}
for vertex in mesh.vertices:
    x, _y, z = vertex.co
    side = smoothstep((abs(x) - 0.19) / 0.115)
    upper = smoothstep((z - 1.46) / 0.12)
    arm = 0.16 * side * (1.0 - 0.70 * upper)
    shoulder = 0.40 * side * (1.0 - 0.30 * upper)
    chest = (0.70 * (1.0 - side) + 0.34 * side) * (1.0 - upper)
    neck = max(0.0, 1.0 - chest - 2.0 * shoulder - 2.0 * arm)
    weights = {
        "DEF-spine.004": chest,
        "DEF-spine.005": neck,
        "DEF-shoulder.L": shoulder if x >= 0.0 else 0.0,
        "DEF-shoulder.R": shoulder if x < 0.0 else 0.0,
        "DEF-upper_arm.L": arm if x >= 0.0 else 0.0,
        "DEF-upper_arm.R": arm if x < 0.0 else 0.0,
    }
    total = sum(weights.values())
    if total <= 1.0e-8:
        weights["DEF-spine.005"] = 1.0
        total = 1.0
    for name, weight in weights.items():
        if weight > 0.0:
            groups[name].add([vertex.index], weight / total, "REPLACE")

modifier = cowl.modifiers.new("RigifyDeform", "ARMATURE")
modifier.object = rig
modifier.use_vertex_groups = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16Z coherent one-piece draped wool cowl"
cowl["old_six_rings_removed"] = True

# Two clean, closed gambeson sleeves replace the scan's torn shoulder roots
# and blend into the existing forearms.  These are ordinary clothing panels,
# not a duplicate body mesh.
shoulder_material = bpy.data.materials.get("MAT_Gambeson_Side_PBR_4K")
if shoulder_material is None:
    shoulder_material = material
SHOULDER_AXIAL = 33
SHOULDER_RING = 32
shoulder_vertices = []
shoulder_faces = []
side_ranges = []
for sign in (-1.0, 1.0):
    first = len(shoulder_vertices)
    for ai in range(SHOULDER_AXIAL):
        t = ai / (SHOULDER_AXIAL - 1)
        x_abs = 0.100 + 0.410 * t
        shoulder_bulge = math.sin(math.pi * t) ** 0.72
        center_z = 1.425 - 0.007 * t + 0.003 * math.sin(math.pi * t)
        center_y = 0.022 + 0.012 * t
        radius_y = 0.085 + 0.015 * shoulder_bulge - 0.008 * t
        radius_z = 0.075 + 0.014 * shoulder_bulge - 0.006 * t
        for ri in range(SHOULDER_RING):
            phi = math.tau * ri / SHOULDER_RING
            # A slightly flattened sleeve section, with a softly padded top.
            cp = math.cos(phi)
            sp = math.sin(phi)
            wrinkle = 1.0 + 0.018 * math.sin(5.0 * math.pi * t + 2.0 * phi) * math.sin(math.pi * t)
            y = center_y + radius_y * wrinkle * cp
            z = center_z + radius_z * wrinkle * sp + 0.005 * max(0.0, sp) ** 2
            x = sign * x_abs
            shoulder_vertices.append((x, y, z))
    for ai in range(SHOULDER_AXIAL - 1):
        for ri in range(SHOULDER_RING):
            nxt = (ri + 1) % SHOULDER_RING
            a = first + ai * SHOULDER_RING + ri
            b = first + (ai + 1) * SHOULDER_RING + ri
            c = first + (ai + 1) * SHOULDER_RING + nxt
            d = first + ai * SHOULDER_RING + nxt
            shoulder_faces.append((a, b, c, d) if sign > 0.0 else (d, c, b, a))
    # Close both ends inside the scarf/sleeve overlap zones.
    inner_center = len(shoulder_vertices)
    shoulder_vertices.append((sign * 0.100, 0.022, 1.425))
    outer_center = len(shoulder_vertices)
    shoulder_vertices.append((sign * 0.510, 0.034, 1.418))
    inner_ring = first
    outer_ring = first + (SHOULDER_AXIAL - 1) * SHOULDER_RING
    for ri in range(SHOULDER_RING):
        nxt = (ri + 1) % SHOULDER_RING
        inner_tri = (inner_center, inner_ring + nxt, inner_ring + ri)
        outer_tri = (outer_center, outer_ring + ri, outer_ring + nxt)
        if sign < 0.0:
            inner_tri = tuple(reversed(inner_tri))
            outer_tri = tuple(reversed(outer_tri))
        shoulder_faces.append(inner_tri)
        shoulder_faces.append(outer_tri)
    side_ranges.append((sign, first, len(shoulder_vertices)))

shoulder_mesh = bpy.data.meshes.new("Mercenary_GambesonUpperSleeves_v16zb_Mesh")
shoulder_mesh.from_pydata(shoulder_vertices, [], shoulder_faces)
shoulder_mesh.update()
shoulders = bpy.data.objects.new("Mercenary_GambesonUpperSleeves_v16zb_LOD0", shoulder_mesh)
asset_collection.objects.link(shoulders)
for poly in shoulder_mesh.polygons:
    poly.use_smooth = True
shoulder_mesh.materials.append(shoulder_material)

bpy.ops.object.select_all(action="DESELECT")
shoulders.select_set(True)
bpy.context.view_layer.objects.active = shoulders
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.25)
bpy.ops.object.mode_set(mode="OBJECT")

shoulder_groups = {name: shoulders.vertex_groups.new(name=name) for name in (
    "DEF-shoulder.L", "DEF-shoulder.R", "DEF-upper_arm.L", "DEF-upper_arm.R",
)}
for vertex in shoulder_mesh.vertices:
    x = vertex.co.x
    t = clamp((abs(x) - 0.100) / 0.410)
    upper_arm_weight = 0.28 + 0.62 * smoothstep(t)
    shoulder_weight = 1.0 - upper_arm_weight
    suffix = ".L" if x >= 0.0 else ".R"
    shoulder_groups["DEF-shoulder" + suffix].add([vertex.index], shoulder_weight, "REPLACE")
    shoulder_groups["DEF-upper_arm" + suffix].add([vertex.index], upper_arm_weight, "REPLACE")

shoulder_modifier = shoulders.modifiers.new("RigifyDeform", "ARMATURE")
shoulder_modifier.object = rig
shoulder_modifier.use_vertex_groups = True
shoulders.parent = rig
shoulders.matrix_parent_inverse = rig.matrix_world.inverted()
shoulders["game_asset"] = True
shoulders["part_category"] = "ClothedBody"
shoulders["source"] = "V16ZB clean closed gambeson upper sleeves"

# Keep preview-only objects and control shapes out of diagnostics.
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
world = scene.world
if world and world.use_nodes:
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs[0].default_value = (0.018, 0.020, 0.024, 1.0)
        bg.inputs[1].default_value = 0.22

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("V16Z_DiagnosticCamera")
    camera = bpy.data.objects.new("V16Z_DiagnosticCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
camera.data.type = "PERSP"


def render(key, location, target, lens=78, resolution=(1200, 1000)):
    camera.location = location
    camera.data.lens = lens
    look_at(camera, target)
    scene.render.resolution_x = resolution[0]
    scene.render.resolution_y = resolution[1]
    path = PREVIEWS / f"diagnostic_v16z_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


PREVIEWS.mkdir(parents=True, exist_ok=True)
preview_paths = {
    "top_close": render("coherent_cowl_top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("coherent_cowl_high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.46), 86),
    "upper_three_quarter": render("coherent_cowl_upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.43), 88),
    "front": render("coherent_cowl_front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("coherent_cowl_back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

bad_edges, components = topology(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in mesh.vertices]
mesh_objects = [obj for obj in scene.objects if obj.type == "MESH" and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")]
total_triangles = sum(triangles(obj) for obj in mesh_objects)
points = [cowl.matrix_world @ vertex.co for vertex in mesh.vertices]
report = {
    "candidate": str(OUTPUT),
    "source": str(SOURCE),
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "total_triangles": total_triangles,
    "mesh_count": len(mesh_objects),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "cowl_bounds": {
        "min": [min(point[i] for point in points) for i in range(3)],
        "max": [max(point[i] for point in points) for i in range(3)],
    },
    "settled_donor_vertices": settled,
    "compressed_shoulder_vertices": compressed_shoulder_vertices,
    "deleted_torn_donor_faces": deleted_donor_faces,
    "shoulder_bridge": shoulders.name,
    "shoulder_bridge_triangles": triangles(shoulders),
    "removed_old_upper_objects": list(REMOVE_NAMES),
    "previews": preview_paths,
}
cowl["v16z_validation"] = json.dumps(report, sort_keys=True)

for text in bpy.data.texts:
    text.use_module = False

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16Z_REPORT=" + json.dumps(report, sort_keys=True))
