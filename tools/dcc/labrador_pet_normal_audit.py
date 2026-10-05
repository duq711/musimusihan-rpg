"""Read-only Blender comparison of original GLB and exported FBX skin normals.

Run with background Blender, -- --source original.glb --fbx model.fbx
--report audit.json. No models, materials, importers or scenes are saved.
The optional production transform defaults match the audited Labrador export.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree


def import_skin(path, kind):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if kind == "glb":
        bpy.ops.import_scene.gltf(filepath=str(path))
    else:
        bpy.ops.import_scene.fbx(filepath=str(path), use_custom_normals=True)
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            obj.animation_data_clear()
            obj.data.pose_position = "REST"
        if obj.type == "MESH" and obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                key.value = 0
    bpy.context.view_layer.update()
    obj = max((o for o in bpy.context.scene.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
    mesh = obj.data
    normal_matrix = obj.matrix_world.to_3x3().inverted().transposed()
    positions = [obj.matrix_world @ v.co for v in mesh.vertices]
    normals = [(normal_matrix @ n.vector).normalized() for n in mesh.corner_normals]
    vertices = [loop.vertex_index for loop in mesh.loops]
    faces = []
    for poly in mesh.polygons:
        face_normal = (normal_matrix @ poly.normal).normalized()
        faces.append({"index": poly.index, "center": list(obj.matrix_world @ poly.center),
                      "corner_face_dots": [normals[i].dot(face_normal) for i in poly.loop_indices]})
    summary = {"name": obj.name, "vertices": len(mesh.vertices), "loops": len(mesh.loops),
               "polygons": len(mesh.polygons), "custom_normals": mesh.has_custom_normals,
               "flat_polygons": sum(not p.use_smooth for p in mesh.polygons),
               "matrix_world": [list(row) for row in obj.matrix_world],
               "bounds": {"min": [min(p[i] for p in positions) for i in range(3)],
                          "max": [max(p[i] for p in positions) for i in range(3)]}}
    return positions, normals, vertices, faces, summary, mesh


def original_tangents(path, mesh):
    raw = path.read_bytes()
    size = struct.unpack_from("<I", raw, 12)[0]
    document = json.loads(raw[20:20 + size])
    binary = raw[28 + size:]
    primitive = max((p for m in document["meshes"] for p in m["primitives"]),
                    key=lambda p: document["accessors"][p["attributes"]["POSITION"]]["count"])
    def accessor(index):
        item = document["accessors"][index]
        view = document["bufferViews"][item["bufferView"]]
        dimensions = {"VEC3": 3, "VEC4": 4}[item["type"]]
        if item["componentType"] != 5126:
            raise ValueError("Original tangent audit requires float32 attributes")
        offset = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        stride = view.get("byteStride", dimensions * 4)
        return [struct.unpack_from("<" + "f" * dimensions, binary, offset + i * stride) for i in range(item["count"])]
    attrs = primitive["attributes"]
    if "TANGENT" not in attrs:
        return {"available": False}
    positions = accessor(attrs["POSITION"])
    tangents = accessor(attrs["TANGENT"])
    mesh.calc_tangents(uvmap=mesh.uv_layers[0].name)
    # This asset's glTF Y-up coordinates become Blender Z-up coordinates.
    rotation = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
    angles, body, position_errors = [], [], []
    sign_differences = 0
    for loop in mesh.loops:
        vertex = mesh.vertices[loop.vertex_index]
        tangent = rotation @ Vector(tangents[vertex.index][:3])
        angle = math.degrees(tangent.angle(loop.tangent))
        angles.append(angle)
        position_errors.append(((rotation @ Vector(positions[vertex.index])) - vertex.co).length)
        sign_differences += tangents[vertex.index][3] != loop.bitangent_sign
        if -.8 < vertex.co.y < 1.8 and .6 < vertex.co.z < 2.5:
            body.append(angle)
    def stats(values):
        return {"loops": len(values), "mean_angle_degrees": sum(values) / len(values),
                "max_angle_degrees": max(values), "over_10_degrees": sum(a > 10 for a in values)}
    return {"available": True, "all": stats(angles), "body_region": stats(body),
            "position_transform_max_error": max(position_errors), "raw_sign_differences": sign_differences,
            "sign_note": "Original glTF and Blender UV V directions differ; raw handedness counts are not a corruption test."}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--fbx", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--production-scale", type=float, default=.3)
    parser.add_argument("--production-z-offset", type=float, default=.00495)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    source_hash, fbx_hash = (hashlib.sha256(p.read_bytes()).hexdigest() for p in (args.source, args.fbx))
    sp, sn, si, sf, source, source_mesh = import_skin(args.source, "glb")
    tangent_report = original_tangents(args.source, source_mesh)
    fp, fn, fi, ff, fbx, _ = import_skin(args.fbx, "fbx")
    sp = [p * args.production_scale + Vector((0, 0, args.production_z_offset)) for p in sp]
    tree = KDTree(len(sp))
    for i, p in enumerate(sp):
        tree.insert(p, i)
    tree.balance()
    by_vertex = defaultdict(list)
    for i, normal in zip(si, sn):
        by_vertex[i].append(normal)
    angles, distances = [], []
    for vertex, normal in zip(fi, fn):
        _, _, distance = tree.find(fp[vertex])
        distances.append(distance)
        # Include coincident UV/normal seam vertices instead of choosing an arbitrary duplicate.
        candidates = [i for _, i, _ in tree.find_range(fp[vertex], max(1e-6, distance + 1e-8))]
        angles.append(min(math.degrees(normal.angle(n)) for i in candidates for n in by_vertex[i]))
    opposed = [f["center"] for f in sf if any(d < 0 for d in f["corner_face_dots"])]
    report = {"source": source, "fbx": fbx, "source_sha256": source_hash, "fbx_sha256": fbx_hash,
              "rest_geometry": {"max_nearest_distance_m": max(distances), "corners_over_1micron": sum(d > 1e-6 for d in distances)},
              "corner_normals": {"loops": len(angles), "max_degrees": max(angles), "mean_degrees": sum(angles) / len(angles),
                                 "over_1_degree": sum(a > 1 for a in angles)},
              "winding": {"source_opposed_polygons": len(opposed),
                          "fbx_opposed_polygons": sum(any(d < 0 for d in f["corner_face_dots"]) for f in ff),
                          "source_torso_opposed": sum(-.8 < p[1] < 1.8 and .6 < p[2] < 2.5 for p in opposed)},
              "tangents": tangent_report, "limitations": "Static original/imported normals and tangent data only. Unity shader/texture decoding is evaluated separately."}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    if any(hashlib.sha256(p.read_bytes()).hexdigest() != expected for p, expected in ((args.source, source_hash), (args.fbx, fbx_hash))):
        raise RuntimeError("Read-only input changed during audit")
    print(json.dumps({"report": str(args.report), "corner_normals": report["corner_normals"],
                      "rest_geometry": report["rest_geometry"], "winding": report["winding"]}, indent=2))


if __name__ == "__main__":
    main()
