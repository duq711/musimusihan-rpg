"""Create an isolated v16w cowl/hair candidate from v15.

The old six concentric collars and all shoulder repair patches are removed.
The replacement is one closed voxel-unioned cloth shell: a compact draped
base with a single continuous helical fold fused into it.  The canonical game
asset and web viewer are deliberately not touched.
"""

from __future__ import annotations

from collections import defaultdict, deque
import json
import math
import random
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v15.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16ad_tailored_shoulders_cowl.blend"
REPORT = STAGING / "build_summary_v16ad_tailored_shoulders_cowl.json"

REMOVE_NAMES = (
    "Mercenary_Cowl_LayeredClean_LOD0",
    "Mercenary_UnderCowl_Yoke_LOD0",
    "Mercenary_ShoulderCowl_Gussets_LOD0",
    "Mercenary_RearShoulder_NotchPatches_LOD0",
    "Mercenary_InnerCowl_RolledCollar_LOD0",
)


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def smoothstep(v):
    v = clamp(v)
    return v * v * (3.0 - 2.0 * v)


def triangle_count(obj):
    return sum(max(1, len(poly.vertices) - 2) for poly in obj.data.polygons)


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
camera = scene.camera
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
asset_collection = donor.users_collection[0]
cloth_material = bpy.data.materials["MAT_CowlTop_SelectiveCharcoal_PBR_4K"].copy()
cloth_material.name = "MAT_Cowl_HeavyWool_Dark_v16x_4K"
# Preserve the existing 4K base/normal/ORM maps and tint only the albedo to
# the near-black brown wool in the reference.
nodes = cloth_material.node_tree.nodes
links = cloth_material.node_tree.links
bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
base_socket = bsdf.inputs["Base Color"]
old_link = base_socket.links[0] if base_socket.links else None
if old_link is not None:
    source_socket = old_link.from_socket
    links.remove(old_link)
    tint = nodes.new("ShaderNodeMixRGB")
    tint.name = "DarkWoolTint"
    tint.blend_type = "MULTIPLY"
    tint.inputs[0].default_value = 1.0
    tint.inputs[2].default_value = (0.36, 0.32, 0.28, 1.0)
    links.new(source_socket, tint.inputs[1])
    links.new(tint.outputs[0], base_socket)
gambeson_material = bpy.data.materials["MAT_Gambeson_Side_PBR_4K"]

for name in REMOVE_NAMES:
    obj = bpy.data.objects.get(name)
    if obj is not None:
        mesh = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

# The photogrammetry donor has a branching open collar boundary.  Tuck only
# the central/rear shoulder-root boundary and a short transition zone beneath
# the new cowl.  This removes the torn halo without adding patch meshes or
# altering the sleeves/deltoids.
donor_mesh_backup = donor.data.copy()
edge_count = defaultdict(int)
adjacency = defaultdict(set)
for poly in donor.data.polygons:
    vs = list(poly.vertices)
    for a, b in zip(vs, vs[1:] + vs[:1]):
        key = tuple(sorted((a, b)))
        edge_count[key] += 1
        adjacency[a].add(b)
        adjacency[b].add(a)
boundary = {v for edge, count in edge_count.items() if count == 1 for v in edge}
seeds = {
    index for index in boundary
    if donor.data.vertices[index].co.z > 1.365
    and abs(donor.data.vertices[index].co.x) < 0.360
    and donor.data.vertices[index].co.y > -0.060
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
settled_donor_vertices = 0
for index, rings in distance.items():
    co = donor.data.vertices[index].co
    if abs(co.x) >= 0.405 or co.y <= -0.085 or co.z <= 1.315:
        continue
    fade = (1.0 - rings / 5.0) ** 2
    spatial = 1.0 - smoothstep((abs(co.x) - 0.300) / 0.105)
    influence = fade * spatial
    if influence <= 0.001:
        continue
    target_x = clamp(co.x, -0.270, 0.270)
    target_y = min(co.y, 0.105 + 0.035 * smoothstep((abs(co.x) - 0.20) / 0.15))
    target_z = min(co.z, 1.350 + 0.045 * smoothstep((abs(co.x) - 0.18) / 0.16))
    co.x = co.x * (1.0 - influence) + target_x * influence
    co.y = co.y * (1.0 - influence) + target_y * influence
    co.z = co.z * (1.0 - influence) + target_z * influence
    settled_donor_vertices += 1
donor.data.update()
donor["v16y_tucked_upper_boundary_vertices"] = settled_donor_vertices
# The displacement experiment above is retained as a measured diagnostic, but
# direct movement stretches the donor's long projection triangles into spikes.
# Restore the untouched donor and let the cowl's low, tapered side lobes cover
# the shoulder roots instead.
modified_donor_mesh = donor.data
donor.data = donor_mesh_backup
if modified_donor_mesh.users == 0:
    bpy.data.meshes.remove(modified_donor_mesh)
settled_donor_vertices = 0
donor["v16y_tucked_upper_boundary_vertices"] = 0

# Remove only the torn, central collar scan fragments.  The replacement shell
# below includes its own sloped shoulder-root cloth, so this no longer leaves
# the open void seen in v16aa.  Sleeve and deltoid faces remain untouched.
reclothed_donor_faces = 0
bm = bmesh.new()
bm.from_mesh(donor.data)
doomed = []
for face in bm.faces:
    co = face.calc_center_median()
    if (
        co.z > 1.375
        and abs(co.x) < 0.465
        and co.y > -0.115
    ):
        doomed.append(face)
removed_donor_collar_faces = len(doomed)
if doomed:
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
bm.to_mesh(donor.data)
bm.free()
donor.data.update()
donor["v16ad_removed_torn_collar_faces"] = removed_donor_collar_faces


# ---------------------------------------------------------------------------
# One connected draped cowl.  A compact base seals the donor neckline.  One
# non-cyclic ribbon winds upward through two turns and physically intersects
# the base; voxel remesh fuses both into one manifold shell.
# ---------------------------------------------------------------------------
vertices = []
faces = []

ANG = 192
ROWS = 29


def base_point(theta, u, inner=False):
    c, s = math.cos(theta), math.sin(theta)
    front = max(0.0, -s)
    back = max(0.0, s)
    side = abs(c)
    left = max(0.0, -c)
    right = max(0.0, c)

    eased = smoothstep(u)
    # Narrow neck opening, then a late shoulder/clavicle drape.  The lower
    # envelope never reaches the deltoid ends and therefore cannot read as a
    # flat poncho or shoulder pad.
    rx_top = 0.126 + 0.006 * math.sin(3.0 * theta + 0.4)
    ry_top = 0.103 + 0.007 * math.sin(2.0 * theta - 0.2)
    rx_bottom = 0.185 + 0.029 * side ** 6 + 0.006 * left
    ry_bottom = 0.150 + 0.018 * front + 0.074 * back
    rx = rx_top * (1.0 - eased) + rx_bottom * eased
    ry = ry_top * (1.0 - eased) + ry_bottom * eased

    # Broad wandering folds are relief in the same sheet, not stacked rings.
    fold_a = 0.27 + 0.16 * math.sin(theta + 0.5) + 0.050 * math.sin(3.0 * theta)
    fold_b = 0.64 + 0.15 * math.sin(theta - 0.9) - 0.040 * math.sin(2.0 * theta)
    ridge_a = math.exp(-((u - fold_a) / 0.105) ** 2)
    ridge_b = math.exp(-((u - fold_b) / 0.115) ** 2)
    valley_a = math.exp(-((u - fold_a - 0.13) / 0.09) ** 2)
    valley_b = math.exp(-((u - fold_b - 0.14) / 0.10) ** 2)
    relief = 0.019 * ridge_a + 0.024 * ridge_b - 0.008 * valley_a - 0.010 * valley_b
    relief += math.sin(math.pi * u) ** 1.4 * (
        0.0025 * math.sin(5.0 * theta + 7.0 * u)
        + 0.0015 * math.sin(11.0 * theta - 4.0 * u)
    )

    if inner:
        rx -= 0.0090
        ry -= 0.0080
        relief *= 0.45

    x = -0.004 + (rx + relief) * c
    y = 0.015 + (ry + relief * 0.75) * s

    # Vertical drape: high hood mass behind the neck, low clavicle coverage in
    # front, slightly lower on the left for the reference's asymmetry.
    top_z = 1.555 + 0.078 * back ** 2 - 0.012 * front + 0.005 * right
    # A visibly dropped front hem and uneven side height remove the rigid,
    # horizontal lampshade silhouette of earlier tests.
    bottom_z = (
        1.413 + 0.005 * back - 0.022 * front ** 3
        + 0.010 * side - 0.007 * left + 0.004 * right
        + 0.006 * math.sin(3.0 * theta + 0.7)
    )
    z = top_z * (1.0 - eased) + bottom_z * eased
    z += math.sin(math.pi * u) ** 1.25 * (
        0.014 * ridge_a + 0.018 * ridge_b
        + 0.003 * math.sin(4.0 * theta + 5.0 * u)
    )
    if inner:
        z -= 0.0025 * math.sin(math.pi * u)
    return (x, y, z)


surface_size = ANG * ROWS
for inner in (False, True):
    for row in range(ROWS):
        u = row / (ROWS - 1)
        for ai in range(ANG):
            theta = math.tau * ai / ANG
            vertices.append(base_point(theta, u, inner))

for row in range(ROWS - 1):
    for ai in range(ANG):
        nxt = (ai + 1) % ANG
        a = row * ANG + ai
        b = (row + 1) * ANG + ai
        c = (row + 1) * ANG + nxt
        d = row * ANG + nxt
        faces.append((a, b, c, d))
        faces.append((surface_size + d, surface_size + c, surface_size + b, surface_size + a))

# Seal the top and bottom rims of the base sheet.
bottom = (ROWS - 1) * ANG
for ai in range(ANG):
    nxt = (ai + 1) % ANG
    faces.append((ai, nxt, surface_size + nxt, surface_size + ai))
    faces.append((bottom + ai, surface_size + bottom + ai,
                  surface_size + bottom + nxt, bottom + nxt))


def shell_outer_point(theta, u):
    # Used to seat the integrated spiral fold on the base surface.
    return Vector(base_point(theta, u, False))


N = 480
CROSS = 12
ribbon_start = len(vertices)
path = []
half_widths = []
half_thicknesses = []
for i in range(N):
    t = i / (N - 1)
    # Start and finish behind the neck; exactly one continuous, two-turn wrap.
    theta = 0.5 * math.pi + math.tau * t
    # One wandering wrap only.  It crosses the front once and changes height
    # continuously, so it cannot read as a stack of circular belts.
    u = 0.72 - 0.44 * t + 0.060 * math.sin(theta + 0.45) + 0.024 * math.sin(3.0 * theta - 0.8)
    p = shell_outer_point(theta, u)
    c, s = math.cos(theta), math.sin(theta)
    radial = Vector((c, s, 0.0)).normalized()
    # Raise the relief just enough to read as compressed cloth; the lower half
    # penetrates the base so the voxel union is guaranteed.
    end_bury = 0.022 * (math.exp(-t / 0.050) + math.exp(-(1.0 - t) / 0.050))
    p += radial * (0.0020 + 0.0012 * math.sin(5.0 * theta + 1.1) - end_bury)
    p.z += 0.003 * math.sin(3.0 * theta - 0.4)
    path.append(p)
    endpoint_taper = smoothstep(t / 0.09) * smoothstep((1.0 - t) / 0.09)
    half_widths.append((0.005 + 0.009 * endpoint_taper) + 0.0012 * math.sin(4.0 * theta))
    half_thicknesses.append((0.0028 + 0.0018 * endpoint_taper) + 0.0006 * math.sin(3.0 * theta + 0.8))

for i, p in enumerate(path):
    prev = path[i - 1] if i else path[i]
    nxt = path[i + 1] if i < N - 1 else path[i]
    tangent = (nxt - prev).normalized()
    radial = Vector((p.x + 0.004, p.y - 0.015, 0.0))
    if radial.length < 1.0e-8:
        radial = Vector((1.0, 0.0, 0.0))
    radial.normalize()
    width_dir = tangent.cross(radial)
    if width_dir.length < 1.0e-8:
        width_dir = Vector((0.0, 0.0, 1.0))
    width_dir.normalize()
    if width_dir.z < 0.0:
        width_dir.negate()
    thick_dir = width_dir.cross(tangent).normalized()
    if thick_dir.dot(radial) < 0.0:
        thick_dir.negate()
    for ci in range(CROSS):
        phi = math.tau * ci / CROSS
        # Superellipse profile: a broad, flattened fabric band rather than a
        # round tube.  Rounded corners keep the fold soft after remeshing.
        sv = math.copysign(math.sqrt(abs(math.sin(phi))), math.sin(phi))
        st = math.copysign(math.sqrt(abs(math.cos(phi))), math.cos(phi))
        co = p + width_dir * (half_widths[i] * sv) + thick_dir * (half_thicknesses[i] * st)
        vertices.append(tuple(co))

for i in range(N - 1):
    for ci in range(CROSS):
        cn = (ci + 1) % CROSS
        faces.append((ribbon_start + i * CROSS + ci,
                      ribbon_start + (i + 1) * CROSS + ci,
                      ribbon_start + (i + 1) * CROSS + cn,
                      ribbon_start + i * CROSS + cn))

# Rounded-ish end caps are buried at the rear after union.
for end_i, reverse in ((0, True), (N - 1, False)):
    center = len(vertices)
    vertices.append(tuple(path[end_i]))
    ring = ribbon_start + end_i * CROSS
    for ci in range(CROSS):
        tri = (center, ring + ci, ring + (ci + 1) % CROSS)
        faces.append(tuple(reversed(tri)) if reverse else tri)


# Two low tapered shoulder-root bridges are fused into the same shell.  They
# sit underneath the donor cloth, fill only the seam voids, and terminate in
# rounded points before the deltoids.  The shallow, sloping profile prevents
# them from reading as a poncho, pad, wing, or rear shelf.
BRIDGE_STEPS = 72
BRIDGE_CROSS = 12
for sign in ():
    start = len(vertices)
    centers = []
    widths = []
    heights = []
    for i in range(BRIDGE_STEPS):
        t = i / (BRIDGE_STEPS - 1)
        eased_t = smoothstep(t)
        x = sign * (0.155 + 0.245 * eased_t)
        y = 0.036 + 0.020 * math.sin(math.pi * t) + 0.008 * sign * math.sin(2.0 * math.pi * t)
        z = 1.425 + 0.018 * math.sin(math.pi * t) - 0.018 * eased_t
        centers.append(Vector((x, y, z)))
        taper = 1.0 - smoothstep((t - 0.72) / 0.28)
        widths.append(0.073 * (0.82 + 0.18 * math.sin(math.pi * t)) * (0.52 + 0.48 * taper))
        heights.append(0.047 * (0.82 + 0.18 * math.sin(math.pi * t)) * (0.42 + 0.58 * taper))
    for i, center_bridge in enumerate(centers):
        for ci in range(BRIDGE_CROSS):
            phi = math.tau * ci / BRIDGE_CROSS
            yoff = widths[i] * math.cos(phi)
            zoff = heights[i] * math.sin(phi)
            vertices.append((center_bridge.x, center_bridge.y + yoff, center_bridge.z + zoff))
    for i in range(BRIDGE_STEPS - 1):
        for ci in range(BRIDGE_CROSS):
            cn = (ci + 1) % BRIDGE_CROSS
            faces.append((start + i * BRIDGE_CROSS + ci,
                          start + (i + 1) * BRIDGE_CROSS + ci,
                          start + (i + 1) * BRIDGE_CROSS + cn,
                          start + i * BRIDGE_CROSS + cn))
    for end_i, reverse in ((0, True), (BRIDGE_STEPS - 1, False)):
        cap_center = len(vertices)
        vertices.append(tuple(centers[end_i]))
        ring = start + end_i * BRIDGE_CROSS
        for ci in range(BRIDGE_CROSS):
            tri = (cap_center, ring + ci, ring + (ci + 1) % BRIDGE_CROSS)
            faces.append(tuple(reversed(tri)) if reverse else tri)


mesh = bpy.data.meshes.new("Mercenary_CompactVerticalCowl_v16ad_LOD0_Mesh")
mesh.from_pydata(vertices, [], faces)
mesh.update()
cowl = bpy.data.objects.new("Mercenary_CompactVerticalCowl_v16ad_LOD0", mesh)
asset_collection.objects.link(cowl)

bpy.ops.object.select_all(action="DESELECT")
cowl.select_set(True)
bpy.context.view_layer.objects.active = cowl
mesh.remesh_voxel_size = 0.00265
mesh.remesh_voxel_adaptivity = 0.0
bpy.ops.object.voxel_remesh()

relax = cowl.modifiers.new("V16W_ClothRelax", "SMOOTH")
relax.factor = 0.16
relax.iterations = 2
bpy.ops.object.modifier_apply(modifier=relax.name)

current_triangles = triangle_count(cowl)
target_triangles = 25_500
if current_triangles > target_triangles:
    dec = cowl.modifiers.new("V16W_GameReadyDecimate", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = target_triangles / current_triangles
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dec.name)

# Voxel/decimate can occasionally leave a microscopic two-triangle fleck.
# Keep only the principal connected vertex island before UVs and weighting.
bm = bmesh.new()
bm.from_mesh(cowl.data)
remaining = set(bm.verts)
islands = []
while remaining:
    seed = remaining.pop()
    island = {seed}
    stack = [seed]
    while stack:
        current = stack.pop()
        for edge in current.link_edges:
            other = edge.other_vert(current)
            if other in remaining:
                remaining.remove(other)
                island.add(other)
                stack.append(other)
    islands.append(island)
largest_island = max(islands, key=len)
discard = [vertex for island in islands if island is not largest_island for vertex in island]
if discard:
    bmesh.ops.delete(bm, geom=discard, context="VERTS")
bm.to_mesh(cowl.data)
bm.free()
cowl.data.update()

for poly in cowl.data.polygons:
    poly.use_smooth = True
cowl.data.materials.append(cloth_material)
for poly in cowl.data.polygons:
    poly.material_index = 0

bpy.context.view_layer.objects.active = cowl
cowl.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.10, island_margin=0.012, area_weight=0.30)
bpy.ops.object.mode_set(mode="OBJECT")

# Measured Rigify profile from the neighbouring v15 cloth.  Upper-arm
# influence is deliberately clamped below 0.25 so T-pose shoulders do not tear.
groups = {name: cowl.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006",
    "DEF-upper_arm.L", "DEF-upper_arm.R")}
for vertex in cowl.data.vertices:
    x, _y, z = vertex.co
    upper = smoothstep((z - 1.500) / 0.065)
    outer = smoothstep((abs(x) - 0.205) / 0.070)
    arm = 0.22 * outer * (1.0 - 0.72 * upper)
    remaining = max(0.0, 1.0 - upper - arm)
    mid = smoothstep((z - 1.445) / 0.070)
    low_fraction = (0.48 * (1.0 - mid) + 0.15 * mid) * (1.0 - outer) + 0.82 * outer
    w004 = remaining * low_fraction
    w005 = remaining - w004
    values = {"DEF-spine.004": w004, "DEF-spine.005": w005, "DEF-spine.006": upper}
    if arm > 0.0:
        values["DEF-upper_arm.L" if x >= 0.0 else "DEF-upper_arm.R"] = arm
    total = sum(values.values())
    for name, value in values.items():
        if value > 1.0e-8:
            groups[name].add([vertex.index], value / total, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["intentional_layer"] = True
cowl["source"] = "V16AD compact vertical cowl; tailored sleeve connectors replace torn shoulder scans"
cowl["old_six_rings_removed"] = True


# ---------------------------------------------------------------------------
# Tailored quilted sleeve-root connectors.  These follow the arm axis instead
# of spreading horizontally from the cowl, so they read as sleeves rather than
# shoulder pads.  Their outer ends overlap the intact donor sleeves; their
# inner ends disappear beneath the cowl and vest.
# ---------------------------------------------------------------------------
shoulder_connectors = []
SLEEVE_SECTIONS = 64
SLEEVE_RING = 24
for sign, side_name in ((-1.0, "R"), (1.0, "L")):
    sleeve_vertices = []
    sleeve_faces = []
    for si in range(SLEEVE_SECTIONS):
        t = si / (SLEEVE_SECTIONS - 1)
        et = smoothstep(t)
        x = sign * (0.155 + 0.375 * et)
        cy = 0.018 + 0.008 * math.sin(math.pi * t + sign * 0.45)
        cz = 1.414 + 0.010 * math.sin(math.pi * t) - 0.006 * et
        grow = 0.80 + 0.20 * smoothstep(t / 0.24)
        ry = (0.104 + 0.008 * math.sin(math.pi * t)) * grow
        rz = (0.108 + 0.010 * math.sin(math.pi * t)) * grow
        for ri in range(SLEEVE_RING):
            phi = math.tau * ri / SLEEVE_RING
            cloth_variation = 1.0 + 0.022 * math.sin(5.0 * phi + 3.0 * math.pi * t + sign)
            sleeve_vertices.append((
                x,
                cy + ry * cloth_variation * math.cos(phi),
                cz + rz * cloth_variation * math.sin(phi),
            ))
    for si in range(SLEEVE_SECTIONS - 1):
        for ri in range(SLEEVE_RING):
            rn = (ri + 1) % SLEEVE_RING
            sleeve_faces.append((si * SLEEVE_RING + ri,
                                 (si + 1) * SLEEVE_RING + ri,
                                 (si + 1) * SLEEVE_RING + rn,
                                 si * SLEEVE_RING + rn))
    for end_si, reverse in ((0, True), (SLEEVE_SECTIONS - 1, False)):
        cap = len(sleeve_vertices)
        ring_center = Vector((0.0, 0.0, 0.0))
        for ri in range(SLEEVE_RING):
            ring_center += Vector(sleeve_vertices[end_si * SLEEVE_RING + ri])
        ring_center /= SLEEVE_RING
        sleeve_vertices.append(tuple(ring_center))
        ring_start = end_si * SLEEVE_RING
        for ri in range(SLEEVE_RING):
            tri = (cap, ring_start + ri, ring_start + (ri + 1) % SLEEVE_RING)
            sleeve_faces.append(tuple(reversed(tri)) if reverse else tri)

    sleeve_mesh = bpy.data.meshes.new(f"Mercenary_TailoredShoulder_{side_name}_v16ad_Mesh")
    sleeve_mesh.from_pydata(sleeve_vertices, [], sleeve_faces)
    sleeve_mesh.update()
    sleeve = bpy.data.objects.new(f"Mercenary_TailoredShoulder_{side_name}_v16ad", sleeve_mesh)
    asset_collection.objects.link(sleeve)
    sleeve_mesh.materials.append(gambeson_material)
    for poly in sleeve_mesh.polygons:
        poly.use_smooth = True

    bpy.ops.object.select_all(action="DESELECT")
    sleeve.select_set(True)
    bpy.context.view_layer.objects.active = sleeve
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=1.05, island_margin=0.012, area_weight=0.25)
    bpy.ops.object.mode_set(mode="OBJECT")

    spine_group = sleeve.vertex_groups.new(name="DEF-spine.004")
    arm_name = "DEF-upper_arm.L" if sign > 0.0 else "DEF-upper_arm.R"
    arm_group = sleeve.vertex_groups.new(name=arm_name)
    for vertex in sleeve.data.vertices:
        t = clamp((abs(vertex.co.x) - 0.155) / 0.375)
        arm_weight = 0.18 + 0.82 * smoothstep(t)
        spine_group.add([vertex.index], 1.0 - arm_weight, "REPLACE")
        arm_group.add([vertex.index], arm_weight, "REPLACE")

    sleeve_armature = sleeve.modifiers.new("RigifyDeform", "ARMATURE")
    sleeve_armature.object = rig
    sleeve_armature.use_deform_preserve_volume = True
    sleeve.parent = rig
    sleeve.matrix_parent_inverse = rig.matrix_world.inverted()
    sleeve["game_asset"] = True
    sleeve["part_category"] = "ClothedBody"
    sleeve["source"] = "V16AD procedural tailored gambeson sleeve-root connector"
    shoulder_connectors.append(sleeve)


# ---------------------------------------------------------------------------
# Hair is deliberately left byte-for-byte as in v15 in this cowl candidate.
# The separate crown/hair fix can therefore be merged without overlapping or
# undoing topology/material work.
# ---------------------------------------------------------------------------
head_hair_faces = 0
lock_count = 0
hair = None


def topology(obj):
    edge_faces = defaultdict(list)
    for poly in obj.data.polygons:
        vs = list(poly.vertices)
        for a, b in zip(vs, vs[1:] + vs[:1]):
            edge_faces[tuple(sorted((a, b)))].append(poly.index)
    adjacency = defaultdict(set)
    for linked in edge_faces.values():
        for a in linked:
            adjacency[a].update(i for i in linked if i != a)
    remaining = set(range(len(obj.data.polygons)))
    sizes = []
    while remaining:
        seed = remaining.pop()
        queue = deque([seed])
        size = 1
        while queue:
            cur = queue.popleft()
            for nxt in adjacency[cur]:
                if nxt in remaining:
                    remaining.remove(nxt)
                    queue.append(nxt)
                    size += 1
        sizes.append(size)
    bad = sum(len(linked) != 2 for linked in edge_faces.values())
    return bad, sorted(sizes, reverse=True)


bad_edges, components = topology(cowl)
if bad_edges or len(components) != 1:
    raise RuntimeError(f"Cowl topology failed: bad_edges={bad_edges}, components={components}")

weight_sums = [sum(g.weight for g in vertex.groups) for vertex in cowl.data.vertices]
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights not normalized: {min(weight_sums)}..{max(weight_sums)}")

character_meshes = [o for o in scene.objects if o.type == "MESH" and o.get("part_category") is not None]
total_triangles = sum(triangle_count(o) for o in character_meshes)
if not 100_000 <= total_triangles <= 150_000:
    raise RuntimeError(f"Triangle budget failed: {total_triangles}")

for name in ("Mercenary_Rigify_Rig_v4", "metarig_mercenary_v4"):
    obj = bpy.data.objects.get(name)
    if obj:
        obj.hide_render = True
        obj.hide_viewport = True
        obj.hide_set(True)

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100


def render(key, location, target, ortho_scale=None, lens=80, resolution=(1200, 1000)):
    if ortho_scale is None:
        camera.data.type = "PERSP"
        camera.data.lens = lens
    else:
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = ortho_scale
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16ad_tailored_shoulders_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {}
previews["top_close"] = render("top_close", (0.0, 0.0, 5.2), (0.0, 0.02, 1.49), ortho_scale=0.88, resolution=(1200, 900))
previews["user_high_three_quarter"] = render("user_high_three_quarter", (0.60, -0.60, 5.50), (0.0, 0.04, 1.02), lens=80, resolution=(1400, 1000))
previews["upper_three_quarter"] = render("upper_three_quarter", (0.74, -1.22, 2.07), (0.0, 0.0, 1.49), lens=86, resolution=(1200, 1000))
previews["front"] = render("front", (0.0, -5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06, resolution=(1200, 1200))
previews["back"] = render("back", (0.0, 5.2, 0.89), (0.0, 0.0, 0.89), ortho_scale=2.06, resolution=(1200, 1200))
previews["cowl_close"] = render("cowl_close", (0.64, -1.12, 1.96), (0.0, 0.0, 1.49), lens=88, resolution=(1200, 1000))

bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT))

points = [cowl.matrix_world @ v.co for v in cowl.data.vertices]
summary = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "removed_objects": list(REMOVE_NAMES),
    "cowl_object": cowl.name,
    "cowl_triangles": triangle_count(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_bounds": {
        "min": [min(p[i] for p in points) for i in range(3)],
        "max": [max(p[i] for p in points) for i in range(3)],
    },
    "cowl_materials": [m.name for m in cowl.data.materials],
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "head_faces_reclassified_as_hair": head_hair_faces,
    "settled_donor_upper_boundary_vertices": settled_donor_vertices,
    "removed_occluded_donor_collar_faces": removed_donor_collar_faces,
    "reclothed_upper_donor_faces": reclothed_donor_faces,
    "tailored_shoulder_objects": [obj.name for obj in shoulder_connectors],
    "tailored_shoulder_triangles": sum(triangle_count(obj) for obj in shoulder_connectors),
    "hair_cards": lock_count,
    "hair_triangles": 0,
    "total_triangles": total_triangles,
    "previews": previews,
}
REPORT.write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("V16AD_SUMMARY", json.dumps(summary))
