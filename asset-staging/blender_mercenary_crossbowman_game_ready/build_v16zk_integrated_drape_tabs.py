"""Fuse compact organic front/back scarf drapes into the v16ze cowl.

This is an isolated candidate build. It never overwrites production files.
"""

from __future__ import annotations

from collections import defaultdict, deque
import bmesh
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
PREVIEWS = STAGING / "previews"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v16ze_integrated_upper_candidate.blend"
OUTPUT = STAGING / "mercenary_crossbowman_game_ready_v16zk_integrated_drape_tabs.blend"
REPORT = STAGING / "v16zk_integrated_drape_tabs_report.json"


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
    edge_faces = defaultdict(list)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        verts = list(poly.vertices)
        for a, b in zip(verts, verts[1:] + verts[:1]):
            edge_faces[tuple(sorted((a, b)))].append(poly.index)
            adjacency[a].add(b)
            adjacency[b].add(a)
    bad = sum(len(linked) != 2 for linked in edge_faces.values())
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    while unseen:
        components += 1
        seed = unseen.pop()
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for neighbour in adjacency[current]:
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    queue.append(neighbour)
    return bad, components


def remove_tiny_islands(obj, minimum_vertices=100):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    unseen = set(bm.verts)
    islands = []
    while unseen:
        seed = unseen.pop()
        queue = [seed]
        island = {seed}
        while queue:
            current = queue.pop()
            for edge in current.link_edges:
                neighbour = edge.other_vert(current)
                if neighbour in unseen:
                    unseen.remove(neighbour)
                    island.add(neighbour)
                    queue.append(neighbour)
        islands.append(island)
    discarded = [island for island in islands if len(island) < minimum_vertices]
    if discarded:
        bmesh.ops.delete(bm, geom=[v for island in discarded for v in island], context="VERTS")
        bm.to_mesh(obj.data)
        obj.data.update()
    bm.free()
    return [len(island) for island in discarded]


def make_drape(name, front, material, collection):
    """Create one closed, gently folded, tapered cloth tab."""
    nu, nv = 32, 22
    verts = []
    faces = []
    sign = -1.0 if front else 1.0
    for side in range(2):
        for j in range(nv):
            v = j / (nv - 1)
            for i in range(nu):
                u = -1.0 + 2.0 * i / (nu - 1)
                edge = abs(u) ** 1.65
                if front:
                    width = 0.144 * (1.0 - 0.23 * v) * (1.0 - 0.025 * math.sin(math.pi * v))
                    z_top = 1.505 + 0.006 * math.cos(math.pi * u)
                    z_bottom = 1.350 + 0.034 * edge + 0.006 * math.sin(2.2 * u + 0.4)
                    y_center = -0.116 - 0.020 * v + 0.004 * math.sin(2.0 * math.pi * v + 1.7 * u)
                    thickness = 0.026 - 0.006 * v
                else:
                    width = 0.137 * (1.0 - 0.28 * v)
                    z_top = 1.515 + 0.004 * math.sin(2.0 * u)
                    z_bottom = 1.382 + 0.026 * edge + 0.005 * math.sin(2.5 * u - 0.6)
                    y_center = 0.151 + 0.012 * v + 0.004 * math.sin(2.0 * math.pi * v - 1.4 * u)
                    thickness = 0.025 - 0.005 * v
                z = z_top * (1.0 - v) + z_bottom * v
                x = width * u + 0.006 * math.sin(math.pi * v) * math.sin(2.7 * u)
                fold = 0.0045 * (1.0 - u * u) * math.sin(3.0 * math.pi * v + 2.2 * u)
                y = y_center + sign * fold + sign * thickness * (0.5 - side)
                verts.append((x, y, z))

    stride = nu * nv
    for side in range(2):
        offset = side * stride
        for j in range(nv - 1):
            for i in range(nu - 1):
                a = offset + j * nu + i
                b = a + 1
                c = a + nu + 1
                d = a + nu
                faces.append((a, d, c, b) if side == 0 else (a, b, c, d))
    for i in range(nu - 1):
        a, b = i, i + 1
        aa, bb = stride + i, stride + i + 1
        faces.append((a, b, bb, aa))
        a, b = (nv - 1) * nu + i, (nv - 1) * nu + i + 1
        aa, bb = stride + a, stride + b
        faces.append((a, aa, bb, b))
    for j in range(nv - 1):
        a, b = j * nu, (j + 1) * nu
        aa, bb = stride + a, stride + b
        faces.append((a, aa, bb, b))
        a, b = j * nu + nu - 1, (j + 1) * nu + nu - 1
        aa, bb = stride + a, stride + b
        faces.append((a, b, bb, aa))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
scene = bpy.context.scene
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]
donor = bpy.data.objects["Mercenary_Clothed_Donor_LOD0"]
cowl = bpy.data.objects["Mercenary_IntegratedDrapedCowl_v16ze_LOD0"]
collection = donor.users_collection[0]
material = cowl.data.materials[0]

front_tab = make_drape("V16ZK_FrontScarfDrape", True, material, collection)
back_tab = make_drape("V16ZK_BackHoodDrape", False, material, collection)

for obj in (cowl, front_tab, back_tab):
    for modifier in list(obj.modifiers):
        if modifier.type == "ARMATURE":
            obj.modifiers.remove(modifier)
    obj.parent = None
    obj.matrix_world = obj.matrix_world

bpy.ops.object.select_all(action="DESELECT")
for obj in (cowl, front_tab, back_tab):
    obj.select_set(True)
bpy.context.view_layer.objects.active = cowl
bpy.ops.object.join()
cowl = bpy.context.active_object
cowl.name = "Mercenary_IntegratedDrapeCowl_v16zk_LOD0"
cowl.data.name = "Mercenary_IntegratedDrapeCowl_v16zk_Mesh"
cowl.data.materials.clear()
cowl.data.materials.append(material)

cowl.data.remesh_voxel_size = 0.00255
cowl.data.remesh_voxel_adaptivity = 0.0
bpy.ops.object.voxel_remesh()

relax = cowl.modifiers.new("V16ZK_ClothRelax", "SMOOTH")
relax.factor = 0.075
relax.iterations = 1
bpy.ops.object.modifier_apply(modifier=relax.name)

raw_triangles = triangles(cowl)
target_triangles = 28_500
if raw_triangles > target_triangles:
    decimate = cowl.modifiers.new("V16ZK_GameReadyDecimate", "DECIMATE")
    decimate.decimate_type = "COLLAPSE"
    decimate.ratio = target_triangles / raw_triangles
    decimate.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=decimate.name)

discarded_islands = remove_tiny_islands(cowl)
for poly in cowl.data.polygons:
    poly.use_smooth = True

bpy.context.view_layer.objects.active = cowl
cowl.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=1.08, island_margin=0.012, area_weight=0.30)
bpy.ops.object.mode_set(mode="OBJECT")

cowl.vertex_groups.clear()
groups = {name: cowl.vertex_groups.new(name=name) for name in (
    "DEF-spine.004", "DEF-spine.005", "DEF-spine.006")}
for vertex in cowl.data.vertices:
    z = vertex.co.z
    upper = smoothstep((z - 1.495) / 0.075)
    mid = smoothstep((z - 1.365) / 0.095)
    w006 = upper
    remaining = 1.0 - w006
    w004 = remaining * (0.58 * (1.0 - mid) + 0.16 * mid)
    w005 = remaining - w004
    groups["DEF-spine.004"].add([vertex.index], w004, "REPLACE")
    groups["DEF-spine.005"].add([vertex.index], w005, "REPLACE")
    groups["DEF-spine.006"].add([vertex.index], w006, "REPLACE")

armature = cowl.modifiers.new("RigifyDeform", "ARMATURE")
armature.object = rig
armature.use_deform_preserve_volume = True
cowl.parent = rig
cowl.matrix_parent_inverse = rig.matrix_world.inverted()
cowl["game_asset"] = True
cowl["part_category"] = "ClothedBody"
cowl["source"] = "V16ZK cowl with short organic front/back drapes as hidden fused interface"

bad_edges, components = topology(cowl)
weight_sums = [sum(group.weight for group in vertex.groups) for vertex in cowl.data.vertices]
if bad_edges or components != 1:
    raise RuntimeError(f"Cowl topology invalid: {bad_edges=}, {components=}")
if min(weight_sums) < 0.999 or max(weight_sums) > 1.001:
    raise RuntimeError(f"Cowl weights invalid: {min(weight_sums)}..{max(weight_sums)}")

for obj in scene.objects:
    if obj.name.startswith("WGT-") or obj.type == "ARMATURE" or (
        obj.type == "MESH" and obj.name.startswith("PREVIEW_")
    ):
        obj.hide_render = True

scene.render.engine = "BLENDER_EEVEE"
scene.render.image_settings.file_format = "PNG"
scene.render.resolution_percentage = 100
camera = scene.camera


def render(key, location, target, lens=86, resolution=(1200, 1000)):
    camera.data.type = "PERSP"
    camera.data.lens = lens
    camera.location = location
    look_at(camera, target)
    scene.render.resolution_x, scene.render.resolution_y = resolution
    path = PREVIEWS / f"diagnostic_v16zk_integrated_drape_tabs_{key}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return str(path)


previews = {
    "top_close": render("top_close", (0.0, -0.01, 2.63), (0.0, 0.015, 1.49), 85),
    "high_angle": render("high_angle", (0.66, -0.82, 2.16), (0.0, 0.01, 1.46), 86),
    "upper_three_quarter": render("upper_three_quarter", (0.70, -1.42, 1.84), (0.0, 0.0, 1.43), 88),
    "front": render("front", (0.0, -5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
    "back": render("back", (0.0, 5.1, 1.08), (0.0, 0.0, 0.91), 90, (1200, 1200)),
}

character_meshes = [
    obj for obj in scene.objects
    if obj.type == "MESH" and not obj.name.startswith("WGT-") and not obj.name.startswith("PREVIEW_")
]
total_triangles = sum(triangles(obj) for obj in character_meshes)
report = {
    "source": str(SOURCE),
    "candidate": str(OUTPUT),
    "production_modified": False,
    "cowl": cowl.name,
    "cowl_triangles": triangles(cowl),
    "cowl_components": components,
    "cowl_nonmanifold_edges": bad_edges,
    "cowl_weight_sum_range": [min(weight_sums), max(weight_sums)],
    "discarded_decimation_islands": discarded_islands,
    "cowl_bounds": {
        "min": [min(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
        "max": [max(vertex.co[i] for vertex in cowl.data.vertices) for i in range(3)],
    },
    "total_triangles": total_triangles,
    "previews": previews,
}
cowl["v16zk_validation"] = json.dumps(report, sort_keys=True)
for text in bpy.data.texts:
    text.use_module = False
bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT), check_existing=False)
REPORT.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
print("V16ZK_REPORT=" + json.dumps(report, sort_keys=True))
