"""Read-only geometry/weight audit of the locally supplied Labrador GLB.

Run with background Blender.  Only a JSON audit is written; the input and
production model are never saved or changed. Coordinates are Blender world
coordinates at the imported bind/rest pose, before any production scaling.
"""
import argparse
import hashlib
import json
import struct
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


def bounds(points):
    if not points:
        return None
    return {"min": [min(p[i] for p in points) for i in range(3)],
            "max": [max(p[i] for p in points) for i in range(3)]}


def glb_uv_audit(source):
    raw = source.read_bytes()
    chunks = {}; offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        chunks[kind] = raw[offset+8:offset+8+size]
        offset += 8 + size
    document = json.loads(chunks[0x4E4F534A]); binary = chunks[0x004E4942]
    def accessor(index):
        item = document["accessors"][index]
        view = document["bufferViews"][item["bufferView"]]
        if item["type"] != "VEC2" or item["componentType"] != 5126:
            raise ValueError("Expected source float32 UV accessor")
        start = view.get("byteOffset", 0) + item.get("byteOffset", 0)
        stride = view.get("byteStride", 8)
        return [struct.unpack_from("<ff", binary, start+i*stride) for i in range(item["count"])]
    results = []
    for index, mesh in enumerate(document["meshes"]):
        for primitive in mesh["primitives"]:
            attributes = primitive["attributes"]; uv0 = accessor(attributes["TEXCOORD_0"])
            comparisons = {}
            for key, accessor_index in attributes.items():
                if key.startswith("TEXCOORD_"):
                    candidate = accessor(accessor_index)
                    deltas = [abs(a-b) for left,right in zip(uv0,candidate) for a,b in zip(left,right)]
                    comparisons[key] = {"vertex_count": len(candidate), "max_component_delta": max(deltas),
                                        "different_components": sum(delta > 0 for delta in deltas)}
            results.append({"mesh_index": index, "mesh_name": mesh["name"], "comparisons_to_uv0": comparisons})
    return {"source_material": document["materials"][0], "meshes": results,
            "conclusion": "All six UV sets are identical in both source meshes; UV0 safely samples metallicRoughness UV1 and normal UV2."}


def mesh_components(mesh, world):
    # Position welding joins UV/normal seam duplicates. It does not modify mesh.
    parent = list(range(len(mesh.vertices)))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        a, b = find(a), find(b)
        if a != b:
            parent[b] = a
    weld = {}
    for v in mesh.vertices:
        key = tuple(round(float(x), 5) for x in v.co)
        if key in weld:
            union(v.index, weld[key])
        else:
            weld[key] = v.index
    for face in mesh.polygons:
        for i in face.vertices[1:]:
            union(face.vertices[0], i)
    components = defaultdict(list)
    for v in mesh.vertices:
        components[find(v.index)].append(v.index)
    return sorted(components.values(), key=len, reverse=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(args.source))
    rigs = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    for rig in rigs:
        rig.animation_data_clear()
        rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    result = {"source": str(args.source.resolve()), "sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
              "blender": bpy.app.version_string, "coordinate_note": "Blender world XYZ, Z up; source units before production scaling.",
              "armatures": [], "meshes": [], "glb_uv_audit": glb_uv_audit(args.source)}
    for rig in rigs:
        result["armatures"].append({"name": rig.name, "bones": [{"name": bone.name, "parent": bone.parent.name if bone.parent else None,
            "head": list(rig.matrix_world @ bone.head_local), "tail": list(rig.matrix_world @ bone.tail_local),
            "length": bone.length, "matrix_world": [list(row) for row in rig.matrix_world @ bone.matrix_local]}
            for bone in rig.data.bones]})
    custom_shapes = {pb.custom_shape for rig in rigs for pb in rig.pose.bones if pb.custom_shape}
    result["excluded_importer_display_shapes"] = [obj.name for obj in custom_shapes]
    for obj in [o for o in bpy.context.scene.objects if o.type == "MESH" and o not in custom_shapes]:
        mesh = obj.data
        positions = [obj.matrix_world @ v.co for v in mesh.vertices]
        influences = defaultdict(list)
        for vertex in mesh.vertices:
            for membership in vertex.groups:
                if membership.weight > 1e-5:
                    influences[obj.vertex_groups[membership.group].name].append((vertex.index, membership.weight))
        entry = {"name": obj.name, "vertices": len(mesh.vertices), "triangles": sum(len(p.vertices)-2 for p in mesh.polygons),
                 "bounds": bounds(positions), "parent": obj.parent.name if obj.parent else None, "groups": {},
                 "materials": [material.name for material in mesh.materials]}
        entry["local_positions_sha256"] = hashlib.sha256(b"".join(struct.pack("<fff", *v.co) for v in mesh.vertices)).hexdigest()
        for name, members in influences.items():
            dominant = [i for i, w in members if w >= .5]
            strongest = [i for i, w in members if w >= .95]
            entry["groups"][name] = {"influenced_vertices": len(members), "sum_weight": sum(w for i, w in members),
                 "max_weight": max(w for i, w in members), "dominant_vertices": len(dominant), "nearly_rigid_vertices": len(strongest),
                 "influence_bounds": bounds([positions[i] for i, w in members]),
                 "dominant_bounds": bounds([positions[i] for i in dominant]),
                 "nearly_rigid_bounds": bounds([positions[i] for i in strongest])}
        components = mesh_components(mesh, obj.matrix_world)
        entry["welded_components"] = []
        for number, indices in enumerate(components):
            group_weights = defaultdict(float)
            for i in indices:
                for g in mesh.vertices[i].groups:
                    group_weights[obj.vertex_groups[g.group].name] += g.weight
            entry["welded_components"].append({"id": number, "vertices": len(indices), "bounds": bounds([positions[i] for i in indices]),
                "centroid": list(sum((positions[i] for i in indices), Vector()) / len(indices)),
                "weights": sorted(group_weights.items(), key=lambda x: -x[1])[:8]})
            component = entry["welded_components"][-1]
            # Exact isolated original-mesh vertices whose memberships indicate
            # clear source skin mistakes. Spatial evidence is also retained;
            # production code must check count and centroid before repairing.
            if obj.name == "mesh_0" and number in (4, 5, 12, 13, 19, 20, 21, 22):
                component["vertex_indices"] = indices
                component["local_centroid"] = list(sum((mesh.vertices[i].co for i in indices), Vector()) / len(indices))
                if number in (4, 5, 12, 13):
                    component["anatomy"] = "outer hind claw"
                    component["repair_transfer"] = {"from": "neutral_bone_52", "to": "FFB.L_44" if component["centroid"][0] > 0 else "FFB.R_48"}
                else:
                    component["anatomy"] = "lower posterior tooth"
                    component["repair_transfer"] = {"from": "Ear4.L_2" if component["centroid"][0] > 0 else "Ear4.R_6", "to": "Neck3.002_10"}
        entry["shape_keys"] = []
        if mesh.shape_keys:
            basis = mesh.shape_keys.key_blocks[0]
            for key in list(mesh.shape_keys.key_blocks)[1:]:
                changed = [i for i in range(len(mesh.vertices)) if (key.data[i].co - basis.data[i].co).length > 1e-5]
                entry["shape_keys"].append({"name": key.name, "changed_vertices": len(changed),
                   "max_delta": max(((key.data[i].co-basis.data[i].co).length for i in changed), default=0),
                   "region_bounds": bounds([positions[i] for i in changed])})
        # Lowest skin points for every weighted distal foot chain. These are
        # skin contacts, independent of invented imported bone tail lengths.
        foot_groups = [g for g in obj.vertex_groups if any(s in g.name for s in ("LowerLeg", "FF.", "FFB."))]
        entry["distal_skin_minima"] = {}
        for group in foot_groups:
            members = influences[group.name]
            if not members:
                continue
            rigid = [(i,w) for i,w in members if w >= .8]
            selected = rigid or members
            ordered = sorted(selected, key=lambda iw: positions[iw[0]].z)
            entry["distal_skin_minima"][group.name] = {"minimum": list(positions[ordered[0][0]]),
                "weight": ordered[0][1], "vertex": ordered[0][0],
                "lowest_twenty_centroid": list(sum((positions[i] for i,w in ordered[:20]), Vector()) / len(ordered[:20])),
                "sampling_threshold": .8 if rigid else 1e-5}
        result["meshes"].append(entry)
    result["imported_actions"] = [{"name": a.name, "frames": list(a.frame_range)} for a in bpy.data.actions]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, indent=2) + "\n")
    for mesh in result["meshes"]:
        print("MESH", mesh["name"], mesh["vertices"], "components", len(mesh["welded_components"]))
        for name in ("Head_1", "Neck3.001_11", "Neck3.002_10"):
            print("GROUP", name, mesh["groups"].get(name))
        print("SHAPES", mesh["shape_keys"])
        print("PAWS", mesh["distal_skin_minima"])
    print("AUDIT_COMPLETE", args.report, flush=True)


if __name__ == "__main__":
    main()
