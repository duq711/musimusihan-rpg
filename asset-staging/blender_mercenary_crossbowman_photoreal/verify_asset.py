#!/usr/bin/env python3
"""Validate the photoreal mercenary asset in Blender or as an exported GLB.

Blender mode (opens and inspects the final authoring file)::

    blender --background --python verify_asset.py

Normal Python mode (parses the GLB header and JSON without third-party modules)::

    python3 verify_asset.py

An alternate target can be supplied after ``--`` in Blender, or directly when
using Python. ``--blend`` and ``--glb`` are also accepted explicitly.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import struct
import sys
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_BLEND = SCRIPT_DIR / "mercenary_crossbowman_photoreal_3d.blend"
DEFAULT_GLB = (
    REPO_ROOT
    / "godot-game"
    / "assets"
    / "3d"
    / "dark_fantasy"
    / "mercenary_crossbowman_photoreal_3d.glb"
)

REQUIRED_NAME_RULES = {
    "CHARACTER_ROOT": lambda name: name.casefold() == "character_root",
    "crossbow": lambda name: "crossbow" in name.casefold(),
    "quiver": lambda name: "quiver" in name.casefold(),
    "dagger": lambda name: "dagger" in name.casefold(),
}

GLB_MAGIC = b"glTF"
GLB_VERSION = 2
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

Vec3 = Tuple[float, float, float]
Mat4 = List[float]  # glTF/OpenGL column-major order


def _cli_args(in_blender: bool) -> argparse.Namespace:
    if in_blender:
        raw = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    else:
        raw = sys.argv[1:]

    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("target", nargs="?", help="Alternate .blend or .glb target")
    parser.add_argument("--blend", type=Path, help="Authoring .blend to inspect")
    parser.add_argument("--glb", type=Path, help="Exported .glb to inspect")
    args, unknown = parser.parse_known_args(raw)
    if unknown:
        raise ValueError("unrecognized arguments: {}".format(" ".join(unknown)))
    return args


def _required_matches(names: Iterable[str]) -> Dict[str, List[str]]:
    name_list = sorted(set(names), key=str.casefold)
    return {
        label: [name for name in name_list if rule(name)]
        for label, rule in REQUIRED_NAME_RULES.items()
    }


def _validate_bounds(bounds_min: Vec3, bounds_max: Vec3, vertical_axis: int) -> List[str]:
    errors: List[str] = []
    values = tuple(bounds_min) + tuple(bounds_max)
    if not all(math.isfinite(value) for value in values):
        return ["bounds contain a non-finite value"]

    extents = tuple(bounds_max[i] - bounds_min[i] for i in range(3))
    if any(extent <= 0.01 for extent in extents):
        errors.append("bounds are degenerate: extents={!r}".format(extents))
    if any(extent > 10.0 for extent in extents):
        errors.append("bounds exceed the expected metre scale: extents={!r}".format(extents))

    height = extents[vertical_axis]
    ground = bounds_min[vertical_axis]
    top = bounds_max[vertical_axis]
    if not 1.20 <= height <= 2.80:
        errors.append("character height {:.4f} m is outside [1.20, 2.80] m".format(height))
    if not -0.75 <= ground <= 0.75:
        errors.append("lowest vertical bound {:.4f} m is implausibly far from ground".format(ground))
    if not 1.20 <= top <= 3.20:
        errors.append("highest vertical bound {:.4f} m is outside [1.20, 3.20] m".format(top))
    if any(abs(value) > 20.0 for value in values):
        errors.append("bounds contain a coordinate outside the +/-20 m safety range")
    return errors


def _identity() -> Mat4:
    return [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    ]


def _mat_mul(a: Sequence[float], b: Sequence[float]) -> Mat4:
    """Return a*b for two column-major 4x4 matrices."""
    return [
        sum(a[k * 4 + row] * b[col * 4 + k] for k in range(4))
        for col in range(4)
        for row in range(4)
    ]


def _transform_point(matrix: Sequence[float], point: Vec3) -> Vec3:
    x, y, z = point
    return (
        matrix[0] * x + matrix[4] * y + matrix[8] * z + matrix[12],
        matrix[1] * x + matrix[5] * y + matrix[9] * z + matrix[13],
        matrix[2] * x + matrix[6] * y + matrix[10] * z + matrix[14],
    )


def _node_local_matrix(node: Dict[str, Any]) -> Mat4:
    matrix = node.get("matrix")
    if matrix is not None:
        if len(matrix) != 16:
            raise ValueError("node matrix does not contain 16 values")
        return [float(value) for value in matrix]

    translation = [float(value) for value in node.get("translation", (0.0, 0.0, 0.0))]
    scale = [float(value) for value in node.get("scale", (1.0, 1.0, 1.0))]
    quaternion = [float(value) for value in node.get("rotation", (0.0, 0.0, 0.0, 1.0))]
    if len(translation) != 3 or len(scale) != 3 or len(quaternion) != 4:
        raise ValueError("node contains malformed TRS data")

    x, y, z, w = quaternion
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
        m00 * sx, m10 * sx, m20 * sx, 0.0,
        m01 * sy, m11 * sy, m21 * sy, 0.0,
        m02 * sz, m12 * sz, m22 * sz, 0.0,
        tx, ty, tz, 1.0,
    ]


def _merge_point(
    bounds_min: Optional[List[float]],
    bounds_max: Optional[List[float]],
    point: Vec3,
) -> Tuple[List[float], List[float]]:
    if bounds_min is None or bounds_max is None:
        return list(point), list(point)
    for axis in range(3):
        bounds_min[axis] = min(bounds_min[axis], point[axis])
        bounds_max[axis] = max(bounds_max[axis], point[axis])
    return bounds_min, bounds_max


def _aabb_corners(bounds_min: Sequence[float], bounds_max: Sequence[float]) -> Iterable[Vec3]:
    for x in (bounds_min[0], bounds_max[0]):
        for y in (bounds_min[1], bounds_max[1]):
            for z in (bounds_min[2], bounds_max[2]):
                yield (float(x), float(y), float(z))


def _read_glb(path: Path) -> Tuple[Dict[str, Any], bytes, Dict[str, Any]]:
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

    offset = 12
    json_bytes: Optional[bytes] = None
    binary = b""
    chunk_count = 0
    while offset < declared_length:
        if offset + 8 > declared_length:
            raise ValueError("truncated GLB chunk header")
        chunk_length, chunk_type = struct.unpack_from("<II", raw, offset)
        offset += 8
        end = offset + chunk_length
        if end > declared_length:
            raise ValueError("GLB chunk extends beyond the declared file length")
        payload = raw[offset:end]
        offset = end
        chunk_count += 1
        if chunk_type == JSON_CHUNK:
            if json_bytes is not None:
                raise ValueError("GLB contains more than one JSON chunk")
            json_bytes = payload
        elif chunk_type == BIN_CHUNK:
            binary += payload

    if json_bytes is None:
        raise ValueError("GLB has no JSON chunk")
    try:
        document = json.loads(json_bytes.rstrip(b" \t\r\n\x00").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError("invalid GLB JSON chunk: {}".format(exc)) from exc
    header = {
        "magic": magic.decode("ascii"),
        "version": version,
        "declared_bytes": declared_length,
        "chunk_count": chunk_count,
        "binary_bytes": len(binary),
    }
    return document, binary, header


_COMPONENT_FORMAT = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}


def _accessor_vec3_bounds(
    document: Dict[str, Any], binary: bytes, accessor_index: int
) -> Tuple[Vec3, Vec3]:
    accessors = document.get("accessors", [])
    if not 0 <= accessor_index < len(accessors):
        raise ValueError("POSITION references invalid accessor {}".format(accessor_index))
    accessor = accessors[accessor_index]
    minimum, maximum = accessor.get("min"), accessor.get("max")
    if minimum is not None and maximum is not None:
        if len(minimum) != 3 or len(maximum) != 3:
            raise ValueError("POSITION accessor has malformed min/max")
        return tuple(map(float, minimum)), tuple(map(float, maximum))  # type: ignore[return-value]

    if accessor.get("type") != "VEC3":
        raise ValueError("POSITION accessor is not VEC3")
    view_index = accessor.get("bufferView")
    views = document.get("bufferViews", [])
    if view_index is None or not 0 <= int(view_index) < len(views):
        raise ValueError("POSITION accessor has no readable bufferView")
    view = views[int(view_index)]
    if int(view.get("buffer", 0)) != 0:
        raise ValueError("POSITION accessor uses an external buffer; bounds are unavailable")

    component_type = int(accessor.get("componentType", 0))
    if component_type not in _COMPONENT_FORMAT:
        raise ValueError("unsupported POSITION component type {}".format(component_type))
    fmt, component_size = _COMPONENT_FORMAT[component_type]
    element_size = component_size * 3
    stride = int(view.get("byteStride", element_size))
    if stride < element_size:
        raise ValueError("POSITION byteStride is smaller than one VEC3")
    start = int(view.get("byteOffset", 0)) + int(accessor.get("byteOffset", 0))
    count = int(accessor.get("count", 0))
    if count <= 0:
        raise ValueError("POSITION accessor is empty")

    unpack = struct.Struct("<" + fmt * 3).unpack_from
    lower = [math.inf, math.inf, math.inf]
    upper = [-math.inf, -math.inf, -math.inf]
    for index in range(count):
        offset = start + index * stride
        if offset + element_size > len(binary):
            raise ValueError("POSITION accessor extends beyond the GLB binary chunk")
        point = unpack(binary, offset)
        for axis in range(3):
            value = float(point[axis])
            lower[axis] = min(lower[axis], value)
            upper[axis] = max(upper[axis], value)
    return tuple(lower), tuple(upper)  # type: ignore[return-value]


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


def _glb_world_matrices(document: Dict[str, Any]) -> Tuple[Dict[int, Mat4], List[int]]:
    nodes = document.get("nodes", [])
    if not nodes:
        return {}, []

    scenes = document.get("scenes", [])
    scene_index = int(document.get("scene", 0)) if scenes else -1
    if 0 <= scene_index < len(scenes):
        roots = [int(index) for index in scenes[scene_index].get("nodes", [])]
    else:
        children = {
            int(child)
            for node in nodes
            for child in node.get("children", [])
        }
        roots = [index for index in range(len(nodes)) if index not in children]

    world: Dict[int, Mat4] = {}
    order: List[int] = []

    def visit(index: int, parent: Mat4, ancestry: set) -> None:
        if not 0 <= index < len(nodes):
            raise ValueError("scene references invalid node {}".format(index))
        if index in ancestry:
            raise ValueError("cycle detected in the glTF node hierarchy")
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


def inspect_glb(path: Path) -> Tuple[Dict[str, Any], List[str]]:
    document, binary, header = _read_glb(path)
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    world, visited = _glb_world_matrices(document)

    mesh_triangles = [
        sum(_primitive_triangle_count(document, primitive) for primitive in mesh.get("primitives", []))
        for mesh in meshes
    ]
    primitive_count = sum(len(mesh.get("primitives", [])) for mesh in meshes)
    unique_triangles = sum(mesh_triangles)
    scene_triangles = 0
    bounds_min: Optional[List[float]] = None
    bounds_max: Optional[List[float]] = None

    for node_index in visited:
        node = nodes[node_index]
        if "mesh" not in node:
            continue
        mesh_index = int(node["mesh"])
        if not 0 <= mesh_index < len(meshes):
            raise ValueError("node references invalid mesh {}".format(mesh_index))
        scene_triangles += mesh_triangles[mesh_index]
        matrix = world[node_index]
        for primitive in meshes[mesh_index].get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None:
                continue
            local_min, local_max = _accessor_vec3_bounds(document, binary, int(position_index))
            for corner in _aabb_corners(local_min, local_max):
                bounds_min, bounds_max = _merge_point(
                    bounds_min, bounds_max, _transform_point(matrix, corner)
                )

    errors: List[str] = []
    matches = _required_matches(str(node.get("name", "")) for node in nodes)
    for label, found in matches.items():
        if not found:
            errors.append("missing required named node/object: {}".format(label))
    if not meshes or unique_triangles <= 0:
        errors.append("GLB contains no triangulated mesh geometry")
    if bounds_min is None or bounds_max is None:
        errors.append("unable to determine scene bounds")
        safe_min = (0.0, 0.0, 0.0)
        safe_max = (0.0, 0.0, 0.0)
    else:
        safe_min = tuple(bounds_min)
        safe_max = tuple(bounds_max)
        # glTF is Y-up; Blender's exporter converts the authoring Z-up scene.
        errors.extend(_validate_bounds(safe_min, safe_max, vertical_axis=1))

    pivot_positions: Dict[str, List[Dict[str, Any]]] = {}
    for label, found in matches.items():
        entries = []
        for name in found:
            for index, node in enumerate(nodes):
                if str(node.get("name", "")) != name:
                    continue
                matrix = world.get(index, _node_local_matrix(node))
                entries.append(
                    {
                        "name": name,
                        "world_position": [matrix[12], matrix[13], matrix[14]],
                    }
                )
        pivot_positions[label] = entries

    report = {
        "mode": "glb",
        "file": str(path),
        "header": header,
        "asset": document.get("asset", {}),
        "coordinate_system": "glTF Y-up",
        "counts": {
            "nodes": len(nodes),
            "meshes": len(meshes),
            "primitives": primitive_count,
            "materials": len(document.get("materials", [])),
            "textures": len(document.get("textures", [])),
            "images": len(document.get("images", [])),
            "unique_mesh_triangles": unique_triangles,
            "instanced_scene_triangles": scene_triangles,
        },
        "bounds": {
            "min": list(safe_min),
            "max": list(safe_max),
            "extents": [safe_max[i] - safe_min[i] for i in range(3)],
        },
        "required_names": matches,
        "required_world_positions": pivot_positions,
    }
    return report, errors


def inspect_blend(path: Path) -> Tuple[Dict[str, Any], List[str]]:
    import bpy  # type: ignore
    from mathutils import Vector  # type: ignore

    if Path(bpy.data.filepath).resolve() != path.resolve():
        bpy.ops.wm.open_mainfile(filepath=str(path))

    scene = bpy.context.scene
    scene_objects = list(scene.objects)
    character_root = next(
        (obj for obj in scene_objects if obj.name.casefold() == "character_root"), None
    )
    if character_root is None:
        objects = scene_objects
    else:
        objects = [character_root]
        pending = list(character_root.children)
        while pending:
            child = pending.pop()
            objects.append(child)
            pending.extend(child.children)
    names = [obj.name for obj in objects]
    matches = _required_matches(names)
    geometry_types = {"MESH", "CURVE", "SURFACE", "FONT", "META"}
    geometry_objects = [obj for obj in objects if obj.type in geometry_types]

    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangle_count = 0
    triangle_count_by_type: Dict[str, int] = {}
    bounds_min: Optional[List[float]] = None
    bounds_max: Optional[List[float]] = None

    for obj in geometry_objects:
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            point = evaluated.matrix_world @ Vector(corner)
            bounds_min, bounds_max = _merge_point(
                bounds_min, bounds_max, (float(point.x), float(point.y), float(point.z))
            )
        try:
            evaluated_mesh = evaluated.to_mesh(
                preserve_all_data_layers=False, depsgraph=depsgraph
            )
        except (RuntimeError, TypeError):
            evaluated_mesh = None
        if evaluated_mesh is not None:
            evaluated_mesh.calc_loop_triangles()
            count = len(evaluated_mesh.loop_triangles)
            triangle_count += count
            triangle_count_by_type[obj.type] = triangle_count_by_type.get(obj.type, 0) + count
            evaluated.to_mesh_clear()

    used_materials = {
        slot.material.name
        for obj in geometry_objects
        for slot in obj.material_slots
        if slot.material is not None
    }
    file_images = [
        image
        for image in bpy.data.images
        if image.name != "Render Result" and (image.packed_file or image.filepath)
    ]

    errors: List[str] = []
    for label, found in matches.items():
        if not found:
            errors.append("missing required named node/object: {}".format(label))
    if not geometry_objects or triangle_count <= 0:
        errors.append(".blend contains no triangulated geometry")
    if bounds_min is None or bounds_max is None:
        errors.append("unable to determine scene bounds")
        safe_min = (0.0, 0.0, 0.0)
        safe_max = (0.0, 0.0, 0.0)
    else:
        safe_min = tuple(bounds_min)
        safe_max = tuple(bounds_max)
        errors.extend(_validate_bounds(safe_min, safe_max, vertical_axis=2))

    pivot_positions: Dict[str, List[Dict[str, Any]]] = {}
    for label, found in matches.items():
        pivot_positions[label] = [
            {
                "name": name,
                "type": bpy.data.objects[name].type,
                "world_position": list(bpy.data.objects[name].matrix_world.translation),
            }
            for name in found
        ]

    report = {
        "mode": "blend",
        "file": str(path),
        "blender_version": bpy.app.version_string,
        "coordinate_system": "Blender Z-up",
        "counts": {
            "scene_objects": len(scene_objects),
            "objects": len(objects),
            "geometry_objects": len(geometry_objects),
            "meshes": sum(obj.type == "MESH" for obj in objects),
            "mesh_objects": sum(obj.type == "MESH" for obj in objects),
            "materials": len(used_materials),
            "materials_in_file": len(bpy.data.materials),
            "materials_used_by_scene_geometry": len(used_materials),
            "textures": len(file_images),
            "textures_or_file_images": len(file_images),
            "evaluated_triangles": triangle_count,
            "evaluated_triangles_by_object_type": triangle_count_by_type,
        },
        "bounds": {
            "min": list(safe_min),
            "max": list(safe_max),
            "extents": [safe_max[i] - safe_min[i] for i in range(3)],
        },
        "required_names": matches,
        "required_world_positions": pivot_positions,
    }
    return report, errors


def main() -> int:
    try:
        import bpy  # type: ignore  # noqa: F401
        in_blender = True
    except ImportError:
        in_blender = False

    try:
        args = _cli_args(in_blender)
        if in_blender:
            selected = args.blend or (Path(args.target) if args.target else DEFAULT_BLEND)
            path = selected.expanduser().resolve()
            if path.suffix.casefold() != ".blend":
                raise ValueError("Blender mode requires a .blend target, got {}".format(path))
        else:
            selected = args.glb or (Path(args.target) if args.target else DEFAULT_GLB)
            path = selected.expanduser().resolve()
            if path.suffix.casefold() != ".glb":
                raise ValueError("normal Python mode requires a .glb target, got {}".format(path))

        if not path.is_file():
            raise FileNotFoundError("required asset file does not exist: {}".format(path))

        report, errors = inspect_blend(path) if in_blender else inspect_glb(path)
        report["status"] = "FAIL" if errors else "PASS"
        report["errors"] = errors
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
        if errors:
            print("QA FAILED: {}".format("; ".join(errors)), file=sys.stderr)
            return 1
        print("QA PASSED: {}".format(path))
        return 0
    except Exception as exc:
        print("QA FAILED: {}: {}".format(type(exc).__name__, exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
