"""Report upper-torso boundary topology in the v8 candidate."""

from __future__ import annotations

from collections import defaultdict, deque
from pathlib import Path

import bpy
from mathutils import Vector


WORKSPACE = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = WORKSPACE / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
BLEND = STAGING / "mercenary_crossbowman_game_ready_v8.blend"
PREVIEWS = STAGING / "previews"

bpy.ops.wm.open_mainfile(filepath=str(BLEND))


def components(items, adjacency):
    remaining = set(items)
    groups = []
    while remaining:
        seed = remaining.pop()
        group = {seed}
        queue = deque([seed])
        while queue:
            current = queue.popleft()
            for neighbor in adjacency[current]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    group.add(neighbor)
                    queue.append(neighbor)
        groups.append(group)
    return groups


for obj in [o for o in bpy.context.scene.objects if o.type == "MESH" and o.get("part_category")]:
    mesh = obj.data
    print("MATERIALS", obj.name, [slot.material.name if slot.material else None for slot in obj.material_slots])
    edge_faces = defaultdict(list)
    for polygon in mesh.polygons:
        vertices = list(polygon.vertices)
        for a, b in zip(vertices, vertices[1:] + vertices[:1]):
            edge_faces[tuple(sorted((a, b)))].append(polygon.index)
    boundary_edges = [edge for edge, faces in edge_faces.items() if len(faces) == 1]
    upper_edges = [
        edge for edge in boundary_edges
        if max(mesh.vertices[index].co.z for index in edge) > 1.30
    ]
    adjacency = defaultdict(set)
    for a, b in upper_edges:
        adjacency[a].add(b)
        adjacency[b].add(a)
    groups = components(adjacency.keys(), adjacency)
    print(
        "OBJECT",
        obj.name,
        "verts", len(mesh.vertices),
        "polys", len(mesh.polygons),
        "boundary", len(boundary_edges),
        "upper_boundary", len(upper_edges),
        "groups", len(groups),
    )
    for group in sorted(groups, key=len, reverse=True)[:20]:
        coordinates = [mesh.vertices[index].co for index in group]
        mins = Vector((min(v.x for v in coordinates), min(v.y for v in coordinates), min(v.z for v in coordinates)))
        maxs = Vector((max(v.x for v in coordinates), max(v.y for v in coordinates), max(v.z for v in coordinates)))
        print(
            " GROUP", len(group),
            "bounds",
            tuple(round(value, 4) for value in mins),
            tuple(round(value, 4) for value in maxs),
        )

    all_adjacency = defaultdict(set)
    for a, b in boundary_edges:
        all_adjacency[a].add(b)
        all_adjacency[b].add(a)
    all_groups = components(all_adjacency.keys(), all_adjacency)
    for group in sorted(all_groups, key=len, reverse=True)[:12]:
        coordinates = [mesh.vertices[index].co for index in group]
        mins = Vector((min(v.x for v in coordinates), min(v.y for v in coordinates), min(v.z for v in coordinates)))
        maxs = Vector((max(v.x for v in coordinates), max(v.y for v in coordinates), max(v.z for v in coordinates)))
        print(
            " ALL_GROUP", len(group),
            "bounds",
            tuple(round(value, 4) for value in mins),
            tuple(round(value, 4) for value in maxs),
        )
    if obj.name == "Mercenary_Clothed_Donor_LOD0":
        for side_label, low_x, high_x in (("R", 0.26, 0.95), ("L", -0.95, -0.26)):
            counts = defaultdict(int)
            bounds = {}
            for polygon in mesh.polygons:
                center = polygon.center
                if not (low_x <= center.x <= high_x and center.z > 1.18):
                    continue
                counts[(polygon.material_index, "up" if polygon.normal.z > 0.15 else "other")] += 1
                key = polygon.material_index
                current = bounds.get(key)
                if current is None:
                    bounds[key] = [center.copy(), center.copy()]
                else:
                    for axis in range(3):
                        current[0][axis] = min(current[0][axis], center[axis])
                        current[1][axis] = max(current[1][axis], center[axis])
            print("ARM_FACE_COUNTS", side_label, dict(sorted(counts.items())))
            print(
                "ARM_MATERIAL_BOUNDS",
                side_label,
                {
                    key: (
                        tuple(round(value, 4) for value in value[0]),
                        tuple(round(value, 4) for value in value[1]),
                    )
                    for key, value in sorted(bounds.items())
                },
            )


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


for obj in bpy.context.scene.objects:
    if obj.type == "ARMATURE":
        obj.hide_render = True
camera = bpy.context.scene.camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = 1.95
camera.location = (0.0, 0.0, 5.0)
look_at(camera, (0.0, 0.0, 0.92))
bpy.context.scene.render.resolution_x = 1500
bpy.context.scene.render.resolution_y = 900
bpy.context.scene.render.resolution_percentage = 100
bpy.context.scene.render.filepath = str(PREVIEWS / "diagnostic_v8_top.png")
bpy.ops.render.render(write_still=True)
bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
bpy.context.scene.display.shading.light = "STUDIO"
bpy.context.scene.display.shading.color_type = "SINGLE"
bpy.context.scene.display.shading.single_color = (0.46, 0.30, 0.18)
bpy.context.scene.display.shading.show_shadows = True
bpy.context.scene.display.shading.show_cavity = True
bpy.context.scene.display.shading.cavity_type = "BOTH"
bpy.context.scene.render.filepath = str(PREVIEWS / "diagnostic_v8_top_clay.png")
bpy.ops.render.render(write_still=True)
