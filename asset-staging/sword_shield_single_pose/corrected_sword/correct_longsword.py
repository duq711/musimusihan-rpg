#!/usr/bin/env python3
"""Shorten only the imported grip/furniture; never import or replace production.

The actual GLB is Y-up, verified by its BladeTip/HandGrip markers. Furniture is
merged by the asset exporter, so welded triangle components identify the pear,
peen and ferrule. No vertex-height heuristic splits an overlapping component.
"""
import argparse
import collections
import copy
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[3]
COMPONENT = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def normalize(value):
    length = math.sqrt(sum(x * x for x in value))
    assert length > 1e-12
    return tuple(x / length for x in value)


def bounds(points):
    return {"min": [min(p[a] for p in points) for a in range(3)],
            "max": [max(p[a] for p in points) for a in range(3)]}


class GLB:
    def __init__(self, data):
        assert struct.unpack_from("<4sII", data) == (b"glTF", 2, len(data))
        self.chunks = []
        offset = 12
        while offset < len(data):
            size, kind = struct.unpack_from("<II", data, offset)
            self.chunks.append((kind, data[offset + 8:offset + 8 + size]))
            offset += 8 + size
        assert [c[0] for c in self.chunks[:2]] == [0x4E4F534A, 0x004E4942]
        self.doc = json.loads(self.chunks[0][1])
        self.bin = bytearray(self.chunks[1][1])
        assert len(self.doc["buffers"]) == 1 and not self.doc["buffers"][0].get("uri")

    def layout(self, accessor):
        spec = self.doc["accessors"][accessor]
        assert not spec.get("sparse")
        view = self.doc["bufferViews"][spec["bufferView"]]
        fmt = "<" + COMPONENT[spec["componentType"]] * WIDTH[spec["type"]]
        size = struct.calcsize(fmt)
        return spec, fmt, view.get("byteOffset", 0) + spec.get("byteOffset", 0), view.get("byteStride", size), size

    def raw(self, accessor, index=None):
        spec, _, offset, stride, size = self.layout(accessor)
        indices = range(spec["count"]) if index is None else [index]
        return b"".join(self.bin[offset + i * stride:offset + i * stride + size] for i in indices)

    def read(self, accessor):
        spec, fmt, offset, stride, _ = self.layout(accessor)
        return [struct.unpack_from(fmt, self.bin, offset + i * stride) for i in range(spec["count"])]

    def write(self, accessor, index, value):
        _, fmt, offset, stride, _ = self.layout(accessor)
        struct.pack_into(fmt, self.bin, offset + index * stride, *value)

    def refresh_bounds(self, accessor):
        spec = self.doc["accessors"][accessor]
        values = self.read(accessor)
        for name, fn in [("min", min), ("max", max)]:
            if name in spec:
                spec[name] = [fn(v[a] for v in values) for a in range(len(values[0]))]

    def encode(self):
        document = json.dumps(self.doc, ensure_ascii=False, separators=(",", ":")).encode()
        document += b" " * (-len(document) % 4)
        binary = bytes(self.bin) + b"\0" * (-len(self.bin) % 4)
        chunks = [(0x4E4F534A, document), (0x004E4942, binary)] + self.chunks[2:]
        payload = b"".join(struct.pack("<II", len(data), kind) + data for kind, data in chunks)
        return struct.pack("<4sII", b"glTF", 2, len(payload) + 12) + payload

    def named_node(self, name):
        result = [node for node in self.doc["nodes"] if node.get("name") == name]
        assert len(result) == 1, name
        return result[0]

    def mesh_hash(self, name):
        node = self.named_node(name)
        mesh = self.doc["meshes"][node["mesh"]]
        digest = hashlib.sha256(json.dumps({"node": node, "mesh": mesh}, sort_keys=True).encode())
        for primitive in mesh["primitives"]:
            for accessor in list(primitive["attributes"].values()) + [primitive["indices"]]:
                digest.update(json.dumps(self.doc["accessors"][accessor], sort_keys=True).encode())
                digest.update(self.raw(accessor))
        return digest.hexdigest()


def furniture_components(glb, mesh):
    parents, references, coordinates = {}, collections.defaultdict(list), {}

    def find(key):
        parents.setdefault(key, key)
        while parents[key] != key:
            parents[key] = parents[parents[key]]
            key = parents[key]
        return key

    def union(a, b):
        parents[find(b)] = find(a)

    for pi, primitive in enumerate(mesh["primitives"]):
        vertices = glb.read(primitive["attributes"]["POSITION"])
        keys = []
        for vi, point in enumerate(vertices):
            key = tuple(round(value, 6) for value in point)
            find(key)
            coordinates[key] = point
            references[key].append((pi, vi))
            keys.append(key)
        indices = [x[0] for x in glb.read(primitive["indices"])]
        for i in range(0, len(indices), 3):
            union(keys[indices[i]], keys[indices[i + 1]])
            union(keys[indices[i]], keys[indices[i + 2]])
    grouped = collections.defaultdict(list)
    for key in coordinates:
        grouped[find(key)].append(key)
    result = {}
    for keys in grouped.values():
        box = bounds([coordinates[k] for k in keys])
        low, high = box["min"][1], box["max"][1]
        span_x = box["max"][0] - box["min"][0]
        if low < -.34 and high < -.34:
            name = "FlushTangPeen"
        elif low < -.34 and -.271 < high < -.269:
            name = "PearPommel"
        elif -.272 < low < -.270 and -.261 < high < -.259:
            name = "PommelFerrule"
        elif span_x > .25 and low > -.03:
            name = "SymmetricSweptQuillons"
        elif low > -.03 and span_x < .06:
            name = "GuardCollar"
        else:
            raise ValueError(f"Unrecognized connected component: {box}")
        assert name not in result
        result[name] = {"bounds_before": box, "references": sorted({ref for k in keys for ref in references[k]})}
    assert set(result) == {"FlushTangPeen", "PearPommel", "PommelFerrule", "SymmetricSweptQuillons", "GuardCollar"}
    return result


def component_hash(glb, mesh, references):
    digest = hashlib.sha256()
    for pi, vi in references:
        primitive = mesh["primitives"][pi]
        for semantic, accessor in sorted(primitive["attributes"].items()):
            digest.update(semantic.encode())
            digest.update(glb.raw(accessor, vi))
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "godot-game/assets/3d/player/sword_shield/longsword.glb")
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("longsword.glb"))
    args = parser.parse_args()
    assert args.source.resolve() != args.output.resolve(), "Never replace the source model"
    source_data = args.source.read_bytes()
    before, after = GLB(source_data), GLB(source_data)
    for name, expected in [("BladeTip", [0, 1.035, 0]), ("HandGrip", [0, -.108, .002])]:
        node = after.named_node(name)
        assert max(abs(a - b) for a, b in zip(node["translation"], expected)) < 1e-6, "Input axes/markers changed"
    furniture_node = after.named_node("SwordsmanLongsword_Surface")
    assert not any(key in furniture_node for key in ["matrix", "scale", "rotation", "translation"])
    mesh = after.doc["meshes"][furniture_node["mesh"]]
    components = furniture_components(before, mesh)
    changes = {}
    for name in ["GripLeather", "GripBinding"]:
        node = after.named_node(name)
        assert not any(key in node for key in ["matrix", "scale", "rotation", "translation"])
        # y' = -.026 + .60 * (y + .026); leave transverse radii/UVs intact.
        node["scale"] = [1, .60, 1]
        node["translation"] = [0, -.026 * .40, 0]
        points = [p for primitive in after.doc["meshes"][node["mesh"]]["primitives"] for p in after.read(primitive["attributes"]["POSITION"])]
        changes[name] = {"bounds_before": bounds(points), "bounds_after": bounds([(p[0], -.026 + .60 * (p[1] + .026), p[2]) for p in points])}

    modified_accessors = set()
    for name, component in components.items():
        references = component["references"]
        component["vertex_data_sha256_before"] = component_hash(before, mesh, references)
        if name in ["PearPommel", "FlushTangPeen", "PommelFerrule"]:
            ferrule = name == "PommelFerrule"
            scale = (1, 1, 1) if ferrule else (.80, .65, .80)
            for pi, vi in references:
                attributes = mesh["primitives"][pi]["attributes"]
                position = before.read(attributes["POSITION"])[vi]
                if ferrule:
                    # Ferrule center -.2655 -> -.171; preserve its thickness.
                    value = (position[0], position[1] + .0945, position[2])
                else:
                    # Original pommel/peen top -.270 seats at new neck -.171.
                    value = (.80 * position[0], -.171 + .65 * (position[1] + .270), .80 * position[2])
                after.write(attributes["POSITION"], vi, value)
                modified_accessors.add(attributes["POSITION"])
                if not ferrule:
                    normal = normalize(tuple(n / s for n, s in zip(before.read(attributes["NORMAL"])[vi], scale)))
                    after.write(attributes["NORMAL"], vi, normal)
                    modified_accessors.add(attributes["NORMAL"])
                    if "TANGENT" in attributes:
                        old = before.read(attributes["TANGENT"])[vi]
                        tangent = [v * s for v, s in zip(old[:3], scale)]
                        along = sum(a * b for a, b in zip(tangent, normal))
                        tangent = normalize([v - along * n for v, n in zip(tangent, normal)])
                        after.write(attributes["TANGENT"], vi, (*tangent, old[3]))
                        modified_accessors.add(attributes["TANGENT"])
        points = [after.read(mesh["primitives"][pi]["attributes"]["POSITION"])[vi] for pi, vi in references]
        component["bounds_after"] = bounds(points)
        component["vertex_data_sha256_after"] = component_hash(after, mesh, references)
        component["vertex_count"] = len(references)
        del component["references"]
        if name in ["SymmetricSweptQuillons", "GuardCollar"]:
            assert component["vertex_data_sha256_before"] == component["vertex_data_sha256_after"], name
    for accessor in modified_accessors:
        after.refresh_bounds(accessor)

    protected = {}
    for name in ["PittedBlade", "FullerPolishedChannel"]:
        protected[name] = {"before": before.mesh_hash(name), "after": after.mesh_hash(name)}
        assert protected[name]["before"] == protected[name]["after"], name
    for name in ["HandGrip", "BladeTip", "SwordsmanLongsword"]:
        assert before.named_node(name) == after.named_node(name), name
    # Even within edited furniture, topology, UV atlas addressing and AO remain
    # byte-identical. Only the selected positions/normals/tangents were changed.
    for primitive in mesh["primitives"]:
        for semantic in ["TEXCOORD_0", "COLOR_0"]:
            assert before.raw(primitive["attributes"][semantic]) == after.raw(primitive["attributes"][semantic])
        assert before.raw(primitive["indices"]) == after.raw(primitive["indices"])
    output_data = after.encode()
    checked = GLB(output_data)
    assert checked.mesh_hash("PittedBlade") == before.mesh_hash("PittedBlade")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    backup = args.output.with_name("source_longsword.glb")
    if backup.exists():
        assert backup.read_bytes() == source_data, "Backup belongs to a different source revision"
    else:
        backup.write_bytes(source_data)
    args.output.write_bytes(output_data)
    assert args.source.read_bytes() == source_data, "Production source changed"
    report = {"source": str(args.source.resolve()), "output": str(args.output.resolve()), "source_sha256": sha(source_data), "output_sha256": sha(output_data), "source_preserved": True, "axis": "+Y, independently verified from the actual BladeTip and HandGrip GLB translations", "grip_scale_y": .60, "grip_pivot_y": -.026, "ferrule_center_y": -.171, "pommel_scale_xyz": [.80, .65, .80], "marker_nodes_unchanged": ["HandGrip", "BladeTip"], "blade_collision_identity_preserved": True, "protected_mesh_hashes": protected, "grip_bounds": changes, "furniture_components": components, "uv_colors_indices_preserved": True, "embedded_images_added": False}
    args.output.with_name("correction_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": report["output"], "source_sha256": report["source_sha256"], "output_sha256": report["output_sha256"], "blade_collision_identity_preserved": True, "source_preserved": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
