"""Read-only evaluated nail/skin surface gap measurements at extreme joint poses."""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Matrix
from mathutils.bvhtree import BVHTree

DIGITS = ("thumb", "index", "middle", "ring", "little")
LIMITS = {digit: [60, 70, 80] if digit == "thumb" else [90, 110, 80] for digit in DIGITS}


def evaluated(obj):
    item = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = item.to_mesh()
    points = [item.matrix_world @ vertex.co for vertex in mesh.vertices]
    polygons = [list(polygon.vertices) for polygon in mesh.polygons]
    item.to_mesh_clear()
    return points, polygons


def measure(scene, side="left"):
    rigs = sorted((obj for obj in scene.objects if obj.type == "ARMATURE"), key=lambda obj: obj.matrix_world.translation.x)
    rig = rigs[0 if side == "left" else -1]
    skin = next(obj for obj in scene.objects if obj.type == "MESH" and "anatomicalhand" in obj.name.lower()
                and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers))
    nails = {digit: next(obj for obj in scene.objects if obj.name.startswith("Nail_" + digit)
                         and any(mod.type == "ARMATURE" and mod.object == rig for mod in obj.modifiers)) for digit in DIGITS}
    rest = {bone.name: bone.matrix_basis.copy() for bone in rig.pose.bones}
    pose_defs = {"neutral": {}, "full_flex": {digit + str(j): LIMITS[digit][j] for digit in DIGITS for j in range(3)},
                 "thumb_1_max": {"thumb1": 70}, **{digit + "_2_max": {digit + "2": 80} for digit in DIGITS}}
    report = {}
    groups = {group.index: group.name for group in skin.vertex_groups}
    owners = [groups[max(vertex.groups, key=lambda group: group.weight).group] for vertex in skin.data.vertices]
    for pose_name, angles in pose_defs.items():
        for bone in rig.pose.bones:
            bone.matrix_basis = rest[bone.name]
        if skin.data.shape_keys:
            for key in skin.data.shape_keys.key_blocks:
                key.value = 0
        for name, degrees in angles.items():
            rig.pose.bones[name].matrix_basis = rest[name] @ Matrix.Rotation(-math.radians(degrees), 4, "X")
            if skin.data.shape_keys:
                skin.data.shape_keys.key_blocks[f"Joint_{name[:-1]}_{name[-1]}"].value = degrees / LIMITS[name[:-1]][int(name[-1])]
        bpy.context.view_layer.update()
        points, polygons = evaluated(skin)
        row = {}
        for digit, nail in nails.items():
            faces = [polygon for polygon in polygons if any(owners[i].startswith(digit) for i in polygon)]
            tree = BVHTree.FromPolygons(points, faces, all_triangles=False)
            nail_points, nail_faces = evaluated(nail)
            from mathutils import Vector
            samples = nail_points + [sum((nail_points[i] for i in face), Vector()) / len(face) for face in nail_faces]
            distances, signed = [], []
            for point in samples:
                closest, normal, index, distance = tree.find_nearest(point)
                distances.append(distance)
                signed.append((point - closest).dot(normal))
            row[digit] = {"max_surface_distance_mm": max(distances) * 1000,
                          "vertex_max_surface_distance_mm": max(distances[:len(nail_points)]) * 1000,
                          "face_center_max_surface_distance_mm": max(distances[len(nail_points):]) * 1000,
                          "vertex_samples": len(nail_points), "face_center_samples": len(nail_faces),
                          "mean_surface_distance_mm": sum(distances) / len(distances) * 1000,
                          "max_outward_gap_mm": max(signed) * 1000,
                          "max_inward_depth_mm": -min(signed) * 1000}
        report[pose_name] = row
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--side", choices=("left", "right"), default="left")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    assert bpy.app.background
    bpy.ops.wm.open_mainfile(filepath=str(args.blend.resolve()))
    scene = bpy.data.scenes.get("Bilateral_Articulated_Review") or bpy.data.scenes["Bilateral_Detailed_Review"]
    bpy.context.window.scene = scene
    report = measure(scene, args.side)
    args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    for pose, row in report.items():
        print(pose, {finger: round(data["max_surface_distance_mm"], 3) for finger, data in row.items()})


if __name__ == "__main__":
    main()
