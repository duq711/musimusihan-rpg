"""Quantify v9 cowl exposure and collar-clearance geometry for the v11 repair."""

from __future__ import annotations

from collections import Counter, deque
import json
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Users/duq711gmail.com/Documents/ChatGPT/무시무시한 rpg")
STAGING = ROOT / "asset-staging" / "blender_mercenary_crossbowman_game_ready"
SOURCE = STAGING / "mercenary_crossbowman_game_ready_v9.blend"
OUTPUT = STAGING / "diagnostic_v9_cowl_for_v11.json"

bpy.ops.wm.open_mainfile(filepath=str(SOURCE))
cowl = bpy.data.objects["Mercenary_Cowl_LayeredClean_LOD0"]
head = bpy.data.objects["Mercenary_Male_HeadNeck_LOD0"]
yoke = bpy.data.objects["Mercenary_UnderCowl_Yoke_LOD0"]
rig = bpy.data.objects["Mercenary_Rigify_Rig_v4"]


def bounds(obj):
    coords = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    return {
        "min": [min(co[axis] for co in coords) for axis in range(3)],
        "max": [max(co[axis] for co in coords) for axis in range(3)],
    }


bm = bmesh.new()
bm.from_mesh(cowl.data)
bm.faces.ensure_lookup_table()
bm.faces.index_update()
bvh = BVHTree.FromBMesh(bm, epsilon=1.0e-7)

# The clean cowl contains three closed draped components.  Keep their identity
# in the report so the top-only material selection can be audited per layer.
remaining = set(bm.faces)
components = []
while remaining:
    seed = remaining.pop()
    component = {seed}
    queue = deque([seed])
    while queue:
        face = queue.popleft()
        for edge in face.edges:
            for neighbor in edge.link_faces:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
    components.append(component)
components.sort(key=len, reverse=True)

top_exposed = set()
for face in bm.faces:
    center = face.calc_center_median()
    if face.normal.z <= 0.20:
        continue
    _location, _normal, index, _distance = bvh.ray_cast(
        Vector((center.x, center.y, 2.4)), Vector((0.0, 0.0, -1.0))
    )
    if index == face.index:
        top_exposed.add(face)

component_for_face = {}
for component_index, component in enumerate(components):
    for face in component:
        component_for_face[face.index] = component_index

report = {
    "objects": {
        "cowl": {"bounds": bounds(cowl), "vertices": len(cowl.data.vertices), "faces": len(cowl.data.polygons)},
        "head": {"bounds": bounds(head), "vertices": len(head.data.vertices), "faces": len(head.data.polygons)},
        "yoke": {"bounds": bounds(yoke), "vertices": len(yoke.data.vertices), "faces": len(yoke.data.polygons)},
    },
    "cowl_materials": [material.name if material else None for material in cowl.data.materials],
    "cowl_material_counts": dict(Counter(face.material_index for face in bm.faces)),
    "components": [],
    "top_exposed": {
        "count": len(top_exposed),
        "materials": dict(Counter(face.material_index for face in top_exposed)),
        "components": dict(Counter(component_for_face[face.index] for face in top_exposed)),
        "center_bounds": {
            "min": [min(face.calc_center_median()[axis] for face in top_exposed) for axis in range(3)],
            "max": [max(face.calc_center_median()[axis] for face in top_exposed) for axis in range(3)],
        },
    },
    "deform_bones": [bone.name for bone in rig.data.bones if bone.use_deform],
}

head_world = [head.matrix_world @ vertex.co for vertex in head.data.vertices]
report["head_low_slices"] = []
for upper_z in (1.495, 1.500, 1.510, 1.525, 1.550):
    sample = [co for co in head_world if co.z <= upper_z]
    report["head_low_slices"].append(
        {
            "upper_z": upper_z,
            "count": len(sample),
            "min": [min(co[axis] for co in sample) for axis in range(3)] if sample else None,
            "max": [max(co[axis] for co in sample) for axis in range(3)] if sample else None,
        }
    )

low_group_weights = Counter()
for vertex in head.data.vertices:
    world = head.matrix_world @ vertex.co
    if world.z > 1.515:
        continue
    for assignment in vertex.groups:
        low_group_weights[head.vertex_groups[assignment.group].name] += assignment.weight
report["head_base_weight_totals"] = dict(low_group_weights.most_common(12))

for index, component in enumerate(components):
    centers = [face.calc_center_median() for face in component]
    report["components"].append(
        {
            "index": index,
            "faces": len(component),
            "materials": dict(Counter(face.material_index for face in component)),
            "center_min": [min(center[axis] for center in centers) for axis in range(3)],
            "center_max": [max(center[axis] for center in centers) for axis in range(3)],
            "top_exposed": sum(face in top_exposed for face in component),
        }
    )

bm.free()
OUTPUT.write_text(json.dumps(report, indent=2), encoding="utf-8")
print(json.dumps(report, indent=2))
