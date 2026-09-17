#!/usr/bin/env python3
"""Create a conservative commercial-use candidate from iskelet.glb.

Z-Anatomy's upstream credits say that a University of Dundee inner-ear model
(CC BY-NC-SA 4.0) was included/adapted.  The skeleton export contains the six
auditory-ossicle nodes below.  Their provenance is not documented at component
level, so this script physically removes their nodes, meshes, accessors,
bufferViews, and binary payload.  It intentionally aborts if the source layout
does not match the independently inspected file.

The output remains a derivative of BodyParts3D / Z-Anatomy and therefore remains
CC BY-SA 4.0.  Removing these nodes is a conservative provenance measure, not a
legal opinion or a relicensing operation.
"""

from __future__ import annotations

import json
import pathlib
import struct


ROOT = pathlib.Path(__file__).resolve().parent
SOURCE = ROOT / "iskelet.glb"
OUTPUT = ROOT / "iskelet_without_ossicles.glb"

EXPECTED_NODES = [
    "Incus.l",
    "Incus.r",
    "Malleus.l",
    "Malleus.r",
    "Stapes.l",
    "Stapes.r",
]
REMOVED_MESH_COUNT = 6
REMOVED_ACCESSOR_COUNT = 15
REMOVED_BUFFER_VIEW_COUNT = 15
REMOVED_BINARY_BYTES = 148_572


def read_glb(path: pathlib.Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    magic, version, total_length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2 and total_length == len(data)

    json_length, json_type = struct.unpack_from("<II", data, 12)
    assert json_type == 0x4E4F534A
    json_start = 20
    json_end = json_start + json_length
    document = json.loads(data[json_start:json_end])

    bin_length, bin_type = struct.unpack_from("<II", data, json_end)
    assert bin_type == 0x004E4942
    bin_start = json_end + 8
    payload = data[bin_start : bin_start + bin_length]
    return document, payload


def pad4(data: bytes, fill: bytes) -> bytes:
    return data + fill * ((-len(data)) % 4)


def write_glb(path: pathlib.Path, document: dict, payload: bytes) -> None:
    json_bytes = json.dumps(
        document, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    json_bytes = pad4(json_bytes, b" ")
    payload = pad4(payload, b"\x00")
    total_length = 12 + 8 + len(json_bytes) + 8 + len(payload)

    output = bytearray()
    output += struct.pack("<4sII", b"glTF", 2, total_length)
    output += struct.pack("<II", len(json_bytes), 0x4E4F534A)
    output += json_bytes
    output += struct.pack("<II", len(payload), 0x004E4942)
    output += payload
    path.write_bytes(output)


def main() -> None:
    document, payload = read_glb(SOURCE)

    assert [node.get("name") for node in document["nodes"][:6]] == EXPECTED_NODES
    assert [mesh.get("name") for mesh in document["meshes"][:6]] == [
        "Incus",
        "Incus",
        "Malleus",
        "Malleus",
        "Stapes",
        "Stapes",
    ]
    assert document["bufferViews"][REMOVED_BUFFER_VIEW_COUNT]["byteOffset"] == (
        REMOVED_BINARY_BYTES
    )
    assert len(payload) == document["buffers"][0]["byteLength"]

    document["nodes"] = document["nodes"][6:]
    document["meshes"] = document["meshes"][REMOVED_MESH_COUNT:]
    document["accessors"] = document["accessors"][REMOVED_ACCESSOR_COUNT:]
    document["bufferViews"] = document["bufferViews"][REMOVED_BUFFER_VIEW_COUNT:]
    payload = payload[REMOVED_BINARY_BYTES:]

    for scene in document["scenes"]:
        scene["nodes"] = [index - 6 for index in scene.get("nodes", []) if index >= 6]

    for node in document["nodes"]:
        if "mesh" in node:
            node["mesh"] -= REMOVED_MESH_COUNT
        if "children" in node:
            node["children"] = [index - 6 for index in node["children"]]

    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            if "indices" in primitive:
                primitive["indices"] -= REMOVED_ACCESSOR_COUNT
            primitive["attributes"] = {
                semantic: index - REMOVED_ACCESSOR_COUNT
                for semantic, index in primitive["attributes"].items()
            }

    for accessor in document["accessors"]:
        accessor["bufferView"] -= REMOVED_BUFFER_VIEW_COUNT

    for view in document["bufferViews"]:
        view["byteOffset"] -= REMOVED_BINARY_BYTES

    document["buffers"][0]["byteLength"] = len(payload)
    write_glb(OUTPUT, document, payload)

    check, check_payload = read_glb(OUTPUT)
    assert len(check["nodes"]) == 271
    assert len(check["meshes"]) == 227
    assert len(check["accessors"]) == 611
    assert len(check["bufferViews"]) == 611
    assert check["buffers"][0]["byteLength"] == len(check_payload)
    assert not any(
        node.get("name") in EXPECTED_NODES for node in check["nodes"]
    )
    print(OUTPUT)


if __name__ == "__main__":
    main()
