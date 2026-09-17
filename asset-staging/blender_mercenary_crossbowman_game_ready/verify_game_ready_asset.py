#!/usr/bin/env python3
"""Validate the exported Godot-ready mercenary GLB with the standard library.

The validator reads the GLB container and its glTF JSON directly.  It checks
the production constraints that are easy to lose during export: triangle
budget, metre scale, actual skinning attributes, embedded or on-disk 4K maps,
the absence of excluded equipment, and the Rigify deform-bone count recorded
by ``build_summary.json``.

Usage::

    python3 verify_game_ready_asset.py
    python3 verify_game_ready_asset.py /path/to/asset.glb
    python3 verify_game_ready_asset.py --summary /path/to/build_summary.json

Any failed requirement produces a non-zero exit status.  The JSON report on
stdout is suitable for CI logs and remains useful when validation fails.
"""

from __future__ import annotations

import argparse
import base64
import json
import math
from pathlib import Path
import struct
import sys
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import unquote, unquote_to_bytes


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_GLB = (
    REPO_ROOT
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_game_ready_3d.glb"
)
DEFAULT_SUMMARY = SCRIPT_DIR / "build_summary_v3.json"
DEFAULT_TEXTURE_DIR = SCRIPT_DIR / "textures"

GLB_MAGIC = b"glTF"
GLB_VERSION = 2
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

TRIANGLE_MIN = 100_000
TRIANGLE_MAX = 150_000
TARGET_HEIGHT_M = 1.78
HEIGHT_TOLERANCE_M = 0.10
FOUR_K_EDGE = 4096
MIN_REASONABLE_DEFORM_BONES = 50
MAX_REASONABLE_DEFORM_BONES = 300

FORBIDDEN_NAME_TOKENS = (
    "crossbow",
    "sword",
    "dagger",
    "knife",
    "quiver",
    "arrow",
    "pouch",
    "satchel",
    "scabbard",
    "sheath",
    "weapon",
)
SKIN_TEXTURE_HINTS = ("skin", "face", "body")
CLOTHING_TEXTURE_HINTS = (
    "cloth",
    "gambeson",
    "wool",
    "outer",
    "coat",
    "cowl",
    "leather",
    "boot",
)

Vec3 = Tuple[float, float, float]
Mat4 = List[float]  # glTF matrices use OpenGL column-major order.

_COMPONENT_FORMAT = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
_TYPE_COMPONENTS = {
    "SCALAR": 1,
    "VEC2": 2,
    "VEC3": 3,
    "VEC4": 4,
    "MAT2": 4,
    "MAT3": 9,
    "MAT4": 16,
}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "glb",
        nargs="?",
        type=Path,
        default=DEFAULT_GLB,
        help="GLB to validate (default: final Godot export)",
    )
    parser.add_argument(
        "--summary",
        type=Path,
        default=DEFAULT_SUMMARY,
        help="build_summary.json emitted by the authoring script",
    )
    parser.add_argument(
        "--texture-dir",
        type=Path,
        default=DEFAULT_TEXTURE_DIR,
        help="fallback directory for external PNG/JPEG texture maps",
    )
    return parser.parse_args()


def _read_glb(path: Path) -> Tuple[Dict[str, Any], memoryview, Dict[str, Any]]:
    raw = path.read_bytes()
    if len(raw) < 20:
        raise ValueError("GLB is too short to contain a header and JSON chunk")

    magic, version, declared_length = struct.unpack_from("<4sII", raw, 0)
    if magic != GLB_MAGIC:
        raise ValueError("invalid GLB magic {!r}".format(magic))
    if version != GLB_VERSION:
        raise ValueError("unsupported GLB version {} (expected 2)".format(version))
    if declared_length != len(raw):
        raise ValueError(
            "GLB length mismatch: header says {}, file contains {} bytes".format(
                declared_length, len(raw)
            )
        )

    raw_view = memoryview(raw)
    offset = 12
    chunks: List[Dict[str, Any]] = []
    json_payload: Optional[bytes] = None
    binary: Optional[memoryview] = None
    while offset < declared_length:
        if offset + 8 > declared_length:
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", raw, offset)
        offset += 8
        end = offset + chunk_length
        if end > declared_length:
            raise ValueError("GLB chunk extends beyond declared file length")
        if chunk_length % 4:
            raise ValueError("GLB chunk length is not aligned to four bytes")

        payload = raw_view[offset:end]
        offset = end
        chunks.append(
            {
                "type": "JSON"
                if chunk_type == JSON_CHUNK
                else "BIN"
                if chunk_type == BIN_CHUNK
                else "0x{:08X}".format(chunk_type),
                "bytes": chunk_length,
            }
        )
        if chunk_type == JSON_CHUNK:
            if json_payload is not None:
                raise ValueError("GLB contains more than one JSON chunk")
            json_payload = bytes(payload)
        elif chunk_type == BIN_CHUNK:
            if binary is not None:
                raise ValueError("GLB contains more than one BIN chunk")
            binary = payload

    if not chunks or chunks[0]["type"] != "JSON":
        raise ValueError("the first GLB chunk must be JSON")
    if json_payload is None:
        raise ValueError("GLB has no JSON chunk")

    try:
        document = json.loads(
            json_payload.rstrip(b" \t\r\n\x00").decode("utf-8")
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid GLB JSON chunk: {}".format(exc)) from exc
    if not isinstance(document, dict):
        raise ValueError("glTF JSON root is not an object")

    binary = binary if binary is not None else memoryview(b"")
    buffers = document.get("buffers", [])
    if buffers:
        required_bytes = int(buffers[0].get("byteLength", 0))
        if required_bytes > len(binary):
            raise ValueError(
                "glTF buffer needs {} bytes, BIN chunk has {}".format(
                    required_bytes, len(binary)
                )
            )

    return (
        document,
        binary,
        {
            "magic": magic.decode("ascii"),
            "version": version,
            "declared_bytes": declared_length,
            "chunks": chunks,
            "binary_bytes": len(binary),
        },
    )


def _identity() -> Mat4:
    return [
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        0.0,
        1.0,
    ]


def _mat_mul(a: Sequence[float], b: Sequence[float]) -> Mat4:
    return [
        sum(a[k * 4 + row] * b[col * 4 + k] for k in range(4))
        for col in range(4)
        for row in range(4)
    ]


def _node_local_matrix(node: Dict[str, Any]) -> Mat4:
    matrix = node.get("matrix")
    if matrix is not None:
        if len(matrix) != 16:
            raise ValueError("node matrix does not contain 16 values")
        return [float(value) for value in matrix]

    translation = [float(v) for v in node.get("translation", (0.0, 0.0, 0.0))]
    scale = [float(v) for v in node.get("scale", (1.0, 1.0, 1.0))]
    rotation = [float(v) for v in node.get("rotation", (0.0, 0.0, 0.0, 1.0))]
    if len(translation) != 3 or len(scale) != 3 or len(rotation) != 4:
        raise ValueError("node contains malformed TRS data")

    x, y, z, w = rotation
    q_length = math.sqrt(x * x + y * y + z * z + w * w)
    if q_length <= 1.0e-12:
        x, y, z, w = 0.0, 0.0, 0.0, 1.0
    else:
        x, y, z, w = (value / q_length for value in (x, y, z, w))

    m00 = 1.0 - 2.0 * (y * y + z * z)
    m01 = 2.0 * (x * y - z * w)
    m02 = 2.0 * (x * z + y * w)
    m10 = 2.0 * (x * y + z * w)
    m11 = 1.0 - 2.0 * (x * x + z * z)
    m12 = 2.0 * (y * z - x * w)
    m20 = 2.0 * (x * z - y * w)
    m21 = 2.0 * (y * z + x * w)
    m22 = 1.0 - 2.0 * (x * x + y * y)
    sx, sy, sz = scale
    tx, ty, tz = translation
    return [
        m00 * sx,
        m10 * sx,
        m20 * sx,
        0.0,
        m01 * sy,
        m11 * sy,
        m21 * sy,
        0.0,
        m02 * sz,
        m12 * sz,
        m22 * sz,
        0.0,
        tx,
        ty,
        tz,
        1.0,
    ]


def _world_matrices(document: Dict[str, Any]) -> Tuple[Dict[int, Mat4], List[int]]:
    nodes = document.get("nodes", [])
    if not nodes:
        return {}, []

    scenes = document.get("scenes", [])
    scene_index = int(document.get("scene", 0)) if scenes else -1
    if 0 <= scene_index < len(scenes):
        roots = [int(index) for index in scenes[scene_index].get("nodes", [])]
    else:
        child_indices = {
            int(child) for node in nodes for child in node.get("children", [])
        }
        roots = [index for index in range(len(nodes)) if index not in child_indices]

    world: Dict[int, Mat4] = {}
    order: List[int] = []

    def visit(index: int, parent: Mat4, ancestry: set[int]) -> None:
        if not 0 <= index < len(nodes):
            raise ValueError("scene references invalid node {}".format(index))
        if index in ancestry:
            raise ValueError("cycle detected in glTF node hierarchy")
        if index in world:
            raise ValueError("glTF node {} has more than one parent".format(index))
        matrix = _mat_mul(parent, _node_local_matrix(nodes[index]))
        world[index] = matrix
        order.append(index)
        next_ancestry = set(ancestry)
        next_ancestry.add(index)
        for child in nodes[index].get("children", []):
            visit(int(child), matrix, next_ancestry)

    for root in roots:
        visit(root, _identity(), set())
    return world, order


def _transform_point(matrix: Sequence[float], point: Vec3) -> Vec3:
    x, y, z = point
    return (
        matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
        matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
        matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
    )


def _aabb_corners(lower: Sequence[float], upper: Sequence[float]) -> Iterable[Vec3]:
    for x in (lower[0], upper[0]):
        for y in (lower[1], upper[1]):
            for z in (lower[2], upper[2]):
                yield (float(x), float(y), float(z))


def _merge_point(
    lower: Optional[List[float]], upper: Optional[List[float]], point: Vec3
) -> Tuple[List[float], List[float]]:
    if lower is None or upper is None:
        return list(point), list(point)
    for axis in range(3):
        lower[axis] = min(lower[axis], point[axis])
        upper[axis] = max(upper[axis], point[axis])
    return lower, upper


def _accessor_layout(
    document: Dict[str, Any], accessor_index: int
) -> Tuple[Dict[str, Any], Dict[str, Any], int, int, int, str, int]:
    accessors = document.get("accessors", [])
    views = document.get("bufferViews", [])
    if not 0 <= accessor_index < len(accessors):
        raise ValueError("invalid accessor index {}".format(accessor_index))
    accessor = accessors[accessor_index]
    view_index = accessor.get("bufferView")
    if view_index is None or not 0 <= int(view_index) < len(views):
        raise ValueError("accessor {} has no readable bufferView".format(accessor_index))
    view = views[int(view_index)]
    if int(view.get("buffer", 0)) != 0:
        raise ValueError("accessor {} uses an external buffer".format(accessor_index))

    component_type = int(accessor.get("componentType", 0))
    accessor_type = str(accessor.get("type", ""))
    if component_type not in _COMPONENT_FORMAT:
        raise ValueError("unsupported component type {}".format(component_type))
    if accessor_type not in _TYPE_COMPONENTS:
        raise ValueError("unsupported accessor type {!r}".format(accessor_type))
    fmt, component_size = _COMPONENT_FORMAT[component_type]
    components = _TYPE_COMPONENTS[accessor_type]
    element_size = component_size * components
    stride = int(view.get("byteStride", element_size))
    if stride < element_size:
        raise ValueError("accessor byteStride is smaller than one element")
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    count = int(accessor.get("count", 0))
    if count <= 0:
        raise ValueError("accessor {} is empty".format(accessor_index))
    return accessor, view, start, count, stride, fmt, components


def _accessor_vec3_bounds(
    document: Dict[str, Any], binary: memoryview, accessor_index: int
) -> Tuple[Vec3, Vec3]:
    accessors = document.get("accessors", [])
    if not 0 <= accessor_index < len(accessors):
        raise ValueError("POSITION references invalid accessor {}".format(accessor_index))
    accessor = accessors[accessor_index]
    minimum, maximum = accessor.get("min"), accessor.get("max")
    if minimum is not None and maximum is not None:
        if len(minimum) != 3 or len(maximum) != 3:
            raise ValueError("POSITION accessor has malformed min/max")
        values = tuple(map(float, minimum)), tuple(map(float, maximum))
        if not all(math.isfinite(v) for part in values for v in part):
            raise ValueError("POSITION accessor min/max contains non-finite values")
        return values  # type: ignore[return-value]

    accessor, _, start, count, stride, fmt, components = _accessor_layout(
        document, accessor_index
    )
    if accessor.get("type") != "VEC3" or components != 3:
        raise ValueError("POSITION accessor is not VEC3")
    _, component_size = _COMPONENT_FORMAT[int(accessor["componentType"])]
    element_size = component_size * 3
    unpack = struct.Struct("<" + fmt * 3).unpack_from
    lower = [math.inf, math.inf, math.inf]
    upper = [-math.inf, -math.inf, -math.inf]
    for index in range(count):
        offset = start + index * stride
        if offset + element_size > len(binary):
            raise ValueError("POSITION accessor extends beyond BIN chunk")
        point = unpack(binary, offset)
        for axis in range(3):
            value = float(point[axis])
            lower[axis] = min(lower[axis], value)
            upper[axis] = max(upper[axis], value)
    return tuple(lower), tuple(upper)  # type: ignore[return-value]


def _accessor_has_nonzero(
    document: Dict[str, Any], binary: memoryview, accessor_index: int
) -> bool:
    accessor, _, start, count, stride, fmt, components = _accessor_layout(
        document, accessor_index
    )
    _, component_size = _COMPONENT_FORMAT[int(accessor["componentType"])]
    element_size = component_size * components
    unpack = struct.Struct("<" + fmt * components).unpack_from
    for index in range(count):
        offset = start + index * stride
        if offset + element_size > len(binary):
            raise ValueError("accessor extends beyond BIN chunk")
        if any(float(value) != 0.0 for value in unpack(binary, offset)):
            return True
    return False


def _primitive_triangle_count(
    document: Dict[str, Any], primitive: Dict[str, Any]
) -> int:
    accessors = document.get("accessors", [])
    if "indices" in primitive:
        accessor_index = int(primitive["indices"])
    else:
        accessor_index = int(primitive.get("attributes", {}).get("POSITION", -1))
    if not 0 <= accessor_index < len(accessors):
        return 0
    count = int(accessors[accessor_index].get("count", 0))
    mode = int(primitive.get("mode", 4))
    if mode == 4:  # TRIANGLES
        return count // 3
    if mode in (5, 6):  # TRIANGLE_STRIP / TRIANGLE_FAN
        return max(0, count - 2)
    return 0


def _inspect_geometry(
    document: Dict[str, Any], binary: memoryview
) -> Dict[str, Any]:
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    world, visited = _world_matrices(document)
    mesh_triangles = [
        sum(
            _primitive_triangle_count(document, primitive)
            for primitive in mesh.get("primitives", [])
        )
        for mesh in meshes
    ]

    lower: Optional[List[float]] = None
    upper: Optional[List[float]] = None
    scene_triangles = 0
    mesh_node_count = 0
    for node_index in visited:
        node = nodes[node_index]
        if "mesh" not in node:
            continue
        mesh_node_count += 1
        mesh_index = int(node["mesh"])
        if not 0 <= mesh_index < len(meshes):
            raise ValueError("node references invalid mesh {}".format(mesh_index))
        scene_triangles += mesh_triangles[mesh_index]
        for primitive in meshes[mesh_index].get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None:
                continue
            local_min, local_max = _accessor_vec3_bounds(
                document, binary, int(position_index)
            )
            for corner in _aabb_corners(local_min, local_max):
                lower, upper = _merge_point(
                    lower, upper, _transform_point(world[node_index], corner)
                )

    if lower is None or upper is None:
        raise ValueError("unable to determine scene bounds from POSITION accessors")
    extents = [upper[i] - lower[i] for i in range(3)]
    return {
        "mesh_count": len(meshes),
        "mesh_node_count": mesh_node_count,
        "primitive_count": sum(
            len(mesh.get("primitives", [])) for mesh in meshes
        ),
        "unique_mesh_triangles": sum(mesh_triangles),
        "instanced_scene_triangles": scene_triangles,
        "bounds_min": lower,
        "bounds_max": upper,
        "bounds_extents": extents,
        "height_m": extents[1],  # glTF is Y-up.
    }


def _inspect_rigging(
    document: Dict[str, Any], binary: memoryview, errors: List[str]
) -> Dict[str, Any]:
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    accessors = document.get("accessors", [])
    skins = document.get("skins", [])
    joint_indices: set[int] = set()
    skin_joint_counts: List[int] = []

    for skin_index, skin in enumerate(skins):
        joints = [int(index) for index in skin.get("joints", [])]
        skin_joint_counts.append(len(joints))
        if not joints:
            errors.append("skin {} has no joints".format(skin_index))
        for joint in joints:
            if not 0 <= joint < len(nodes):
                errors.append(
                    "skin {} references invalid joint node {}".format(skin_index, joint)
                )
            else:
                joint_indices.add(joint)

    skinned_mesh_nodes = 0
    skinned_primitives = 0
    paired_joint_weight_primitives = 0
    nonzero_weight_primitives = 0
    for node_index, node in enumerate(nodes):
        if "skin" not in node:
            continue
        skinned_mesh_nodes += 1
        skin_index = int(node["skin"])
        if not 0 <= skin_index < len(skins):
            errors.append(
                "node {} references invalid skin {}".format(node_index, skin_index)
            )
        if "mesh" not in node:
            errors.append("skinned node {} does not reference a mesh".format(node_index))
            continue
        mesh_index = int(node["mesh"])
        if not 0 <= mesh_index < len(meshes):
            errors.append(
                "skinned node {} references invalid mesh {}".format(
                    node_index, mesh_index
                )
            )
            continue

        for primitive_index, primitive in enumerate(
            meshes[mesh_index].get("primitives", [])
        ):
            skinned_primitives += 1
            attributes = primitive.get("attributes", {})
            joints_index = attributes.get("JOINTS_0")
            weights_index = attributes.get("WEIGHTS_0")
            if joints_index is None or weights_index is None:
                errors.append(
                    "skinned mesh {} primitive {} lacks JOINTS_0/WEIGHTS_0".format(
                        mesh_index, primitive_index
                    )
                )
                continue
            paired_joint_weight_primitives += 1
            position_index = attributes.get("POSITION")
            referenced = [int(joints_index), int(weights_index)]
            if position_index is not None:
                referenced.append(int(position_index))
            if any(not 0 <= index < len(accessors) for index in referenced):
                errors.append(
                    "mesh {} primitive {} references an invalid skinning accessor".format(
                        mesh_index, primitive_index
                    )
                )
                continue
            counts = [int(accessors[index].get("count", 0)) for index in referenced]
            if len(set(counts)) != 1:
                errors.append(
                    "mesh {} primitive {} has mismatched POSITION/joint/weight counts {}".format(
                        mesh_index, primitive_index, counts
                    )
                )
            if _accessor_has_nonzero(document, binary, int(weights_index)):
                nonzero_weight_primitives += 1
            else:
                errors.append(
                    "mesh {} primitive {} has only zero skin weights".format(
                        mesh_index, primitive_index
                    )
                )

    if not skins:
        errors.append("GLB has no skins")
    if not joint_indices:
        errors.append("GLB has no exported skin joints")
    if skinned_mesh_nodes == 0:
        errors.append("GLB has no mesh node bound to a skin")
    if paired_joint_weight_primitives == 0:
        errors.append("GLB has no primitive with JOINTS_0 and WEIGHTS_0")
    if nonzero_weight_primitives == 0:
        errors.append("GLB has no non-zero vertex skin weights")

    return {
        "skin_count": len(skins),
        "skin_joint_counts": skin_joint_counts,
        "unique_joint_nodes": len(joint_indices),
        "skinned_mesh_nodes": skinned_mesh_nodes,
        "skinned_primitives": skinned_primitives,
        "joint_weight_primitives": paired_joint_weight_primitives,
        "nonzero_weight_primitives": nonzero_weight_primitives,
    }


def _jpeg_dimensions(data: memoryview) -> Optional[Tuple[int, int]]:
    if len(data) < 4 or bytes(data[:2]) != b"\xFF\xD8":
        return None
    sof_markers = {
        0xC0,
        0xC1,
        0xC2,
        0xC3,
        0xC5,
        0xC6,
        0xC7,
        0xC9,
        0xCA,
        0xCB,
        0xCD,
        0xCE,
        0xCF,
    }
    offset = 2
    while offset + 4 <= len(data):
        while offset < len(data) and data[offset] != 0xFF:
            offset += 1
        while offset < len(data) and data[offset] == 0xFF:
            offset += 1
        if offset >= len(data):
            break
        marker = int(data[offset])
        offset += 1
        if marker in (0x01, 0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            continue
        if offset + 2 > len(data):
            break
        segment_length = struct.unpack_from(">H", data, offset)[0]
        if segment_length < 2 or offset + segment_length > len(data):
            break
        if marker in sof_markers and segment_length >= 7:
            height, width = struct.unpack_from(">HH", data, offset + 3)
            return int(width), int(height)
        offset += segment_length
    return None


def _image_dimensions(data: memoryview) -> Optional[Tuple[int, int]]:
    if len(data) >= 24 and bytes(data[:8]) == b"\x89PNG\r\n\x1a\n":
        width, height = struct.unpack_from(">II", data, 16)
        return int(width), int(height)
    return _jpeg_dimensions(data)


def _data_uri_payload(uri: str) -> bytes:
    header, separator, payload = uri.partition(",")
    if not separator:
        raise ValueError("malformed data URI")
    if ";base64" in header.casefold():
        return base64.b64decode(payload, validate=True)
    return unquote_to_bytes(payload)


def _embedded_image_records(
    document: Dict[str, Any], binary: memoryview, glb_path: Path
) -> Tuple[List[Dict[str, Any]], List[str]]:
    records: List[Dict[str, Any]] = []
    warnings: List[str] = []
    views = document.get("bufferViews", [])
    for image_index, image in enumerate(document.get("images", [])):
        name = str(image.get("name") or image.get("uri") or "image_{}".format(image_index))
        payload: Optional[memoryview] = None
        source = "GLB image"
        try:
            if "bufferView" in image:
                view_index = int(image["bufferView"])
                if not 0 <= view_index < len(views):
                    raise ValueError("invalid image bufferView {}".format(view_index))
                view = views[view_index]
                if int(view.get("buffer", 0)) != 0:
                    raise ValueError("image uses a non-GLB buffer")
                start = int(view.get("byteOffset", 0))
                end = start + int(view.get("byteLength", 0))
                if start < 0 or end > len(binary):
                    raise ValueError("image bufferView extends beyond BIN chunk")
                payload = binary[start:end]
            elif "uri" in image:
                uri = str(image["uri"])
                if uri.startswith("data:"):
                    decoded = _data_uri_payload(uri)
                    payload = memoryview(decoded)
                    source = "GLB data URI"
                else:
                    external = (glb_path.parent / unquote(uri)).resolve()
                    decoded = external.read_bytes()
                    payload = memoryview(decoded)
                    source = str(external)
            else:
                raise ValueError("image has neither bufferView nor URI")
            dimensions = _image_dimensions(payload)
            if dimensions is None:
                warnings.append("could not read dimensions for GLB image {!r}".format(name))
                width = height = None
            else:
                width, height = dimensions
            records.append(
                {
                    "name": name,
                    "source": source,
                    "mime_type": image.get("mimeType"),
                    "width": width,
                    "height": height,
                }
            )
        except (OSError, ValueError, struct.error) as exc:
            warnings.append("could not inspect GLB image {!r}: {}".format(name, exc))
    return records, warnings


def _file_image_records(texture_dir: Path) -> Tuple[List[Dict[str, Any]], List[str]]:
    records: List[Dict[str, Any]] = []
    warnings: List[str] = []
    if not texture_dir.is_dir():
        return records, ["texture fallback directory is missing: {}".format(texture_dir)]
    candidates = sorted(
        (
            path
            for path in texture_dir.iterdir()
            if path.suffix.casefold() in {".png", ".jpg", ".jpeg"}
        ),
        key=lambda path: path.name.casefold(),
    )
    for path in candidates:
        try:
            data = memoryview(path.read_bytes())
            dimensions = _image_dimensions(data)
            if dimensions is None:
                warnings.append("could not read dimensions for texture {}".format(path))
                width = height = None
            else:
                width, height = dimensions
            records.append(
                {
                    "name": path.name,
                    "source": str(path.resolve()),
                    "mime_type": "image/png"
                    if path.suffix.casefold() == ".png"
                    else "image/jpeg",
                    "width": width,
                    "height": height,
                }
            )
        except (OSError, ValueError, struct.error) as exc:
            warnings.append("could not inspect texture {}: {}".format(path, exc))
    return records, warnings


def _is_four_k(record: Dict[str, Any]) -> bool:
    width, height = record.get("width"), record.get("height")
    return (
        isinstance(width, int)
        and isinstance(height, int)
        and width >= FOUR_K_EDGE
        and height >= FOUR_K_EDGE
    )


def _inspect_textures(
    document: Dict[str, Any],
    binary: memoryview,
    glb_path: Path,
    texture_dir: Path,
    errors: List[str],
    warnings: List[str],
) -> Dict[str, Any]:
    records, image_warnings = _embedded_image_records(document, binary, glb_path)
    warnings.extend(image_warnings)

    def classify(items: Sequence[Dict[str, Any]]) -> Tuple[List[str], List[str], List[str]]:
        all_4k = [item["name"] for item in items if _is_four_k(item)]
        skin_4k = [
            item["name"]
            for item in items
            if _is_four_k(item)
            and any(hint in str(item["name"]).casefold() for hint in SKIN_TEXTURE_HINTS)
        ]
        clothing_4k = [
            item["name"]
            for item in items
            if _is_four_k(item)
            and any(
                hint in str(item["name"]).casefold()
                for hint in CLOTHING_TEXTURE_HINTS
            )
        ]
        return all_4k, skin_4k, clothing_4k

    all_4k, skin_4k, clothing_4k = classify(records)
    fallback_used = False
    if not all_4k or not skin_4k or not clothing_4k:
        fallback, file_warnings = _file_image_records(texture_dir)
        warnings.extend(file_warnings)
        records.extend(fallback)
        fallback_used = bool(fallback)
        all_4k, skin_4k, clothing_4k = classify(records)

    if not all_4k:
        errors.append("no actual 4096x4096-or-larger texture was found")
    if not skin_4k:
        errors.append("no 4K skin texture was found")
    if not clothing_4k:
        errors.append("no 4K clothing/leather texture was found")
    return {
        "gltf_texture_count": len(document.get("textures", [])),
        "gltf_image_count": len(document.get("images", [])),
        "fallback_directory_used": fallback_used,
        "four_k_images": all_4k,
        "four_k_skin_images": skin_4k,
        "four_k_clothing_images": clothing_4k,
        "records": records,
    }


def _inspect_forbidden_names(
    document: Dict[str, Any], errors: List[str]
) -> List[Dict[str, Any]]:
    matches: List[Dict[str, Any]] = []
    sections = (
        "nodes",
        "meshes",
        "materials",
        "images",
        "skins",
        "animations",
    )
    for section in sections:
        for index, entry in enumerate(document.get(section, [])):
            name = str(entry.get("name", ""))
            folded = name.casefold()
            for token in FORBIDDEN_NAME_TOKENS:
                if token in folded:
                    matches.append(
                        {
                            "section": section,
                            "index": index,
                            "name": name,
                            "token": token,
                        }
                    )
    if matches:
        errors.append(
            "excluded weapon/pouch names remain in GLB: {}".format(
                ", ".join(sorted({match["name"] for match in matches}))
            )
        )
    return matches


def _read_summary(path: Path) -> Dict[str, Any]:
    try:
        summary = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError("invalid build summary JSON: {}".format(exc)) from exc
    if not isinstance(summary, dict):
        raise ValueError("build summary root is not an object")
    return summary


def _inspect_summary(
    summary: Dict[str, Any], exported_joint_count: int, errors: List[str]
) -> Dict[str, Any]:
    rig = str(summary.get("rig", ""))
    if "rigify" not in rig.casefold():
        errors.append("build summary does not identify a Rigify rig")

    deform_value = summary.get("deform_bones")
    if isinstance(deform_value, bool) or not isinstance(deform_value, int):
        errors.append("build summary deform_bones is not an integer")
        deform_bones = 0
    else:
        deform_bones = deform_value
        if not MIN_REASONABLE_DEFORM_BONES <= deform_bones <= MAX_REASONABLE_DEFORM_BONES:
            errors.append(
                "Rigify deform bone count {} is outside [{}, {}]".format(
                    deform_bones,
                    MIN_REASONABLE_DEFORM_BONES,
                    MAX_REASONABLE_DEFORM_BONES,
                )
            )
    if deform_bones != exported_joint_count:
        errors.append(
            "summary deform_bones ({}) does not match exported unique skin joints ({})".format(
                deform_bones, exported_joint_count
            )
        )

    summary_height = summary.get("height_m")
    try:
        summary_height_f = float(summary_height)
    except (TypeError, ValueError):
        summary_height_f = math.nan
    if not math.isfinite(summary_height_f) or abs(summary_height_f - TARGET_HEIGHT_M) > 0.01:
        errors.append(
            "build summary height_m must record {:.2f} m".format(TARGET_HEIGHT_M)
        )

    pose = str(summary.get("rest_pose", ""))
    if pose.replace("-", "_").replace(" ", "_").upper() != "T_POSE":
        errors.append("build summary rest_pose is not T_POSE")

    triangles = summary.get("triangles")
    if isinstance(triangles, bool) or not isinstance(triangles, int):
        errors.append("build summary triangles is not an integer")
    elif not TRIANGLE_MIN <= triangles <= TRIANGLE_MAX:
        errors.append(
            "build summary triangles {} is outside [{}, {}]".format(
                triangles, TRIANGLE_MIN, TRIANGLE_MAX
            )
        )

    return {
        "asset": summary.get("asset"),
        "height_m": summary.get("height_m"),
        "rest_pose": summary.get("rest_pose"),
        "rig": rig,
        "triangles": triangles,
        "deform_bones": deform_bones,
        "declared_textures": summary.get("textures", {}),
        "declared_excluded": summary.get("excluded", []),
    }


def inspect_asset(
    glb_path: Path, summary_path: Path, texture_dir: Path
) -> Tuple[Dict[str, Any], List[str]]:
    errors: List[str] = []
    warnings: List[str] = []
    document, binary, header = _read_glb(glb_path)

    asset_version = str(document.get("asset", {}).get("version", ""))
    if not asset_version.startswith("2"):
        errors.append("glTF asset.version is not 2.x")

    geometry = _inspect_geometry(document, binary)
    triangles = int(geometry["unique_mesh_triangles"])
    if not TRIANGLE_MIN <= triangles <= TRIANGLE_MAX:
        errors.append(
            "GLB triangle count {} is outside [{}, {}]".format(
                triangles, TRIANGLE_MIN, TRIANGLE_MAX
            )
        )
    height = float(geometry["height_m"])
    if not math.isfinite(height) or abs(height - TARGET_HEIGHT_M) > HEIGHT_TOLERANCE_M:
        errors.append(
            "GLB height {:.4f} m is not approximately {:.2f} m (+/- {:.2f} m)".format(
                height, TARGET_HEIGHT_M, HEIGHT_TOLERANCE_M
            )
        )

    rigging = _inspect_rigging(document, binary, errors)
    textures = _inspect_textures(
        document, binary, glb_path, texture_dir, errors, warnings
    )
    forbidden_matches = _inspect_forbidden_names(document, errors)

    summary = _read_summary(summary_path)
    summary_report = _inspect_summary(
        summary, int(rigging["unique_joint_nodes"]), errors
    )

    report = {
        "status": "FAIL" if errors else "PASS",
        "files": {
            "glb": str(glb_path),
            "summary": str(summary_path),
            "texture_fallback_directory": str(texture_dir),
        },
        "requirements": {
            "triangle_range": [TRIANGLE_MIN, TRIANGLE_MAX],
            "target_height_m": TARGET_HEIGHT_M,
            "height_tolerance_m": HEIGHT_TOLERANCE_M,
            "minimum_texture_edge": FOUR_K_EDGE,
        },
        "container": header,
        "asset": document.get("asset", {}),
        "geometry": geometry,
        "rigging": rigging,
        "textures": textures,
        "forbidden_name_matches": forbidden_matches,
        "build_summary": summary_report,
        "warnings": warnings,
        "errors": errors,
    }
    return report, errors


def main() -> int:
    args = _parse_args()
    glb_path = args.glb.expanduser().resolve()
    summary_path = args.summary.expanduser().resolve()
    texture_dir = args.texture_dir.expanduser().resolve()
    try:
        if not glb_path.is_file():
            raise FileNotFoundError("required GLB does not exist: {}".format(glb_path))
        if not summary_path.is_file():
            raise FileNotFoundError(
                "required build summary does not exist: {}".format(summary_path)
            )
        report, errors = inspect_asset(glb_path, summary_path, texture_dir)
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        if errors:
            print("QA FAILED: {}".format("; ".join(errors)), file=sys.stderr)
            return 1
        print("QA PASSED: {}".format(glb_path))
        return 0
    except Exception as exc:
        print("QA FAILED: {}: {}".format(type(exc).__name__, exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
