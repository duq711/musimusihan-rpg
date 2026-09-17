from __future__ import annotations

from collections import defaultdict, deque
from pathlib import Path
import json

import bpy
from mathutils import Vector


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
BLEND = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready/mercenary_crossbowman_game_ready_v16.blend"
OUT = ROOT / "asset-staging/blender_mercenary_crossbowman_game_ready/diagnostics_v16"
OUT.mkdir(parents=True, exist_ok=True)


def triangles(obj):
    return sum(max(1, len(p.vertices) - 2) for p in obj.data.polygons)


def topology(obj):
    counts = defaultdict(int)
    adjacency = defaultdict(set)
    for poly in obj.data.polygons:
        ids = list(poly.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            key = tuple(sorted((a, b)))
            counts[key] += 1
            adjacency[a].add(b)
            adjacency[b].add(a)
    unseen = set(range(len(obj.data.vertices)))
    components = 0
    sizes = []
    while unseen:
        components += 1
        seed = unseen.pop()
        queue = deque([seed])
        size = 1
        while queue:
            found = adjacency[queue.popleft()] & unseen
            unseen.difference_update(found)
            queue.extend(found)
            size += len(found)
        sizes.append(size)
    return {
        "components": components,
        "component_vertex_sizes": sorted(sizes, reverse=True),
        "boundary_edges": sum(value == 1 for value in counts.values()),
        "nonmanifold_edges": sum(value != 2 for value in counts.values()),
    }


def world_bounds(obj):
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    return {
        "min": [min(p[i] for p in points) for i in range(3)],
        "max": [max(p[i] for p in points) for i in range(3)],
    }


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


bpy.ops.wm.open_mainfile(filepath=str(BLEND))
scene = bpy.context.scene
records = []

for obj in sorted((o for o in scene.objects if o.type == "MESH"), key=lambda o: o.name):
    if obj.name.startswith(("WGT-", "PREVIEW_")):
        continue
    armatures = [m.object.name if m.object else None for m in obj.modifiers if m.type == "ARMATURE"]
    records.append(
        {
            "name": obj.name,
            "part_category": obj.get("part_category"),
            "triangles": triangles(obj),
            "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "topology": topology(obj),
            "bounds": world_bounds(obj),
            "materials": [m.name if m else None for m in obj.data.materials],
            "armatures": armatures,
            "visible": not obj.hide_get() and not obj.hide_viewport,
        }
    )

rig = bpy.data.objects.get("Mercenary_Rigify_Rig_v4")
pose_deviations = []
if rig is not None:
    for bone in rig.pose.bones:
        if (
            bone.location.length > 1e-7
            or bone.rotation_euler.to_matrix().to_quaternion().angle > 1e-7
            or any(abs(v - 1.0) > 1e-7 for v in bone.scale)
        ):
            pose_deviations.append(
                {
                    "bone": bone.name,
                    "location": list(bone.location),
                    "rotation_mode": bone.rotation_mode,
                    "rotation_euler": list(bone.rotation_euler),
                    "scale": list(bone.scale),
                }
            )

report = {
    "blend": str(BLEND),
    "mesh_records": records,
    "pose_deviation_count": len(pose_deviations),
    "pose_deviations": pose_deviations,
}
(OUT / "upper_structure_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

# Object-colour diagnostic renders reveal exactly which separated object creates a gap.
scene.render.engine = "BLENDER_WORKBENCH"
scene.display.shading.light = "STUDIO"
scene.display.shading.color_type = "OBJECT"
scene.display.shading.show_shadows = True
scene.display.shading.show_cavity = True
scene.display.shading.cavity_type = "WORLD"
scene.render.resolution_x = 1000
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.world.color = (0.025, 0.03, 0.04)

palette = [
    (0.75, 0.16, 0.12, 1),
    (0.12, 0.55, 0.85, 1),
    (0.15, 0.70, 0.34, 1),
    (0.92, 0.58, 0.10, 1),
    (0.58, 0.24, 0.78, 1),
    (0.10, 0.70, 0.68, 1),
    (0.82, 0.24, 0.52, 1),
    (0.55, 0.55, 0.55, 1),
]
visible_meshes = [r for r in records if r["visible"]]
for index, record in enumerate(visible_meshes):
    bpy.data.objects[record["name"]].color = palette[index % len(palette)]

camera = scene.camera
if camera is None:
    camera_data = bpy.data.cameras.new("DiagnosisCameraData")
    camera = bpy.data.objects.new("DiagnosisCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera

camera.data.type = "ORTHO"
views = {
    "front": ((0, -5.0, 1.25), (0, 0, 1.25), 2.3),
    "back": ((0, 5.0, 1.25), (0, 0, 1.25), 2.3),
    "upper_three_quarter": ((2.8, -3.7, 2.15), (0, 0, 1.35), 1.75),
    "top": ((0, -0.01, 5.2), (0, 0, 1.15), 2.25),
}
for key, (location, target, ortho_scale) in views.items():
    camera.location = location
    camera.data.ortho_scale = ortho_scale
    look_at(camera, target)
    scene.render.filepath = str(OUT / f"object_id_{key}.png")
    bpy.ops.render.render(write_still=True)

print("DIAG_REPORT", OUT / "upper_structure_report.json")
print("DIAG_POSE_DEVIATIONS", len(pose_deviations))
for record in records:
    print("DIAG_MESH", json.dumps(record, ensure_ascii=False))
