from pathlib import Path
import json

import bpy


obj_path = Path(__file__).parent / "clothes" / "donitz_monk_robe" / "Monks_Robe.obj"
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(obj_path))
obj = bpy.context.active_object
mesh = obj.data

adjacent = [set() for _ in mesh.vertices]
for edge in mesh.edges:
    a, b = edge.vertices
    adjacent[a].add(b)
    adjacent[b].add(a)

unseen = set(range(len(mesh.vertices)))
components = []
while unseen:
    start = unseen.pop()
    stack = [start]
    found = [start]
    while stack:
        current = stack.pop()
        for neighbor in adjacent[current]:
            if neighbor in unseen:
                unseen.remove(neighbor)
                found.append(neighbor)
                stack.append(neighbor)
    xs = [mesh.vertices[i].co.x for i in found]
    ys = [mesh.vertices[i].co.y for i in found]
    zs = [mesh.vertices[i].co.z for i in found]
    abs_xs = [abs(value) for value in xs]
    mean_x = sum(abs_xs) / len(abs_xs)
    mean_y = sum(ys) / len(ys)
    variance_x = sum((value - mean_x) ** 2 for value in abs_xs)
    slope = (
        sum((value - mean_x) * (height - mean_y) for value, height in zip(abs_xs, ys))
        / variance_x
        if variance_x
        else 0.0
    )
    intercept = mean_y - slope * mean_x
    residuals = [height - (intercept + slope * value) for value, height in zip(abs_xs, ys)]
    mean_z = sum(zs) / len(zs)
    slope_z = (
        sum((value - mean_x) * (depth - mean_z) for value, depth in zip(abs_xs, zs))
        / variance_x
        if variance_x
        else 0.0
    )
    intercept_z = mean_z - slope_z * mean_x
    residuals_z = [depth - (intercept_z + slope_z * value) for value, depth in zip(abs_xs, zs)]
    components.append(
        {
            "vertices": len(found),
            "bbox": {
                "x": [min(xs), max(xs)],
                "y": [min(ys), max(ys)],
                "z": [min(zs), max(zs)],
            },
            "y_from_abs_x": [slope, intercept],
            "residual_y": [min(residuals), max(residuals)],
            "z_from_abs_x": [slope_z, intercept_z],
            "residual_z": [min(residuals_z), max(residuals_z)],
        }
    )

components.sort(key=lambda item: item["vertices"], reverse=True)
print(json.dumps(components, indent=2))
