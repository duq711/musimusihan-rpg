#!/usr/bin/env python3
"""Build exact BodyParts3D FJ-node names, runtime groups, and local bounds.

Canonical anatomy names are derived only from DBCLS's official IS-A tables.  For
each element mesh, the unique deepest concept containing that element is its
canonical name.  All 202 selected skeleton elements resolve to exactly one such
concept; the script aborts if that invariant changes.
"""

from __future__ import annotations

import csv
import json
import pathlib
from collections import defaultdict


ROOT = pathlib.Path(__file__).resolve().parent
OBJ_DIR = ROOT / "complete_skeleton_obj_99"
ELEMENTS = ROOT / "isa_element_parts.txt"
RELATIONS = ROOT / "isa_inclusion_relation_list.txt"
CSV_OUTPUT = ROOT / "bodyparts3d_node_mapping.csv"
JSON_OUTPUT = ROOT / "bodyparts3d_runtime_mapping.json"
SUMMARY_OUTPUT = ROOT / "bodyparts3d_node_summary.txt"


HAND_BONES = {
    "capitate",
    "hamate",
    "lunate",
    "pisiform",
    "scaphoid",
    "trapezium",
    "trapezoid",
    "triquetral",
}
FOOT_BONES = {
    "calcaneus",
    "cuboid",
    "talus",
}
SKULL_TERMS = {
    "ethmoid",
    "hyoid",
    "frontal",
    "nasal",
    "lacrimal",
    "maxilla",
    "palatine",
    "parietal",
    "temporal",
    "zygomatic",
    "mandible",
    "occipital",
    "sphenoid",
    "vomer",
    "concha",
}


def source_names() -> dict[str, tuple[str, str]]:
    by_element: defaultdict[str, set[str]] = defaultdict(set)
    names: dict[str, str] = {}
    children: defaultdict[str, set[str]] = defaultdict(set)

    with ELEMENTS.open(encoding="utf-8") as source:
        next(source)
        for line in source:
            concept_id, name, element_id = line.rstrip("\n").split("\t")
            by_element[element_id].add(concept_id)
            names[concept_id] = name

    with RELATIONS.open(encoding="utf-8") as source:
        next(source)
        for line in source:
            parent_id, parent_name, child_id, child_name = line.rstrip("\n").split(
                "\t"
            )
            children[parent_id].add(child_id)
            names[parent_id] = parent_name
            names[child_id] = child_name

    resolved: dict[str, tuple[str, str]] = {}
    for element_id, concepts in by_element.items():
        deepest = [
            concept_id
            for concept_id in concepts
            if not (children[concept_id] & concepts)
        ]
        if len(deepest) == 1:
            concept_id = deepest[0]
            resolved[element_id] = (concept_id, names[concept_id])
    return resolved


def side_for(name: str) -> str:
    lowered = name.lower()
    if "left" in lowered:
        return "left"
    if "right" in lowered:
        return "right"
    return "midline"


def region_and_segment(name: str, side: str) -> tuple[str, str]:
    lowered = name.lower()
    suffix = "_l" if side == "left" else "_r" if side == "right" else ""

    if (
        "finger" in lowered
        or "thumb" in lowered
        or "metacarpal" in lowered
        or any(term in lowered for term in HAND_BONES)
    ):
        return "hand", f"hand{suffix}"
    if (
        "toe" in lowered
        or "metatarsal" in lowered
        or "cuneiform" in lowered
        or "navicular bone of" in lowered
        or any(term in lowered for term in FOOT_BONES)
    ):
        return "foot", f"foot{suffix}"
    if "clavicle" in lowered or "scapula" in lowered:
        return "arm", f"shoulder{suffix}"
    if "humerus" in lowered:
        return "arm", f"upper_arm{suffix}"
    if "radius" in lowered or "ulna" in lowered:
        return "arm", f"forearm{suffix}"
    if "femur" in lowered:
        return "leg", f"thigh{suffix}"
    if "patella" in lowered:
        return "leg", f"knee{suffix}"
    if "tibia" in lowered or "fibula" in lowered:
        return "leg", f"lower_leg{suffix}"
    if "rib" in lowered or lowered in {
        "body of sternum",
        "manubrium",
        "xiphoid process",
    }:
        return "rib_cage", "rib_cage"
    if "vertebra" in lowered or lowered in {"atlas", "axis"}:
        if "cervical" in lowered or lowered in {"atlas", "axis"}:
            return "spine", "spine_cervical"
        if "thoracic" in lowered:
            return "spine", "spine_thoracic"
        return "spine", "spine_lumbar"
    if "hip bone" in lowered or lowered == "sacrum":
        return "pelvis", "pelvis"
    if any(term in lowered for term in SKULL_TERMS):
        return "skull", "skull"
    raise ValueError(f"Unclassified anatomy node: {name}")


def godot_bounds(obj_path: pathlib.Path) -> tuple[list[float], list[float]]:
    points: list[tuple[float, float, float]] = []
    with obj_path.open(encoding="utf-8", errors="replace") as source:
        for line in source:
            if not line.startswith("v "):
                continue
            x, source_y, source_z = map(float, line.split()[1:4])
            # Same root conversion stored in bodyparts3d_skeleton_cc_by_4.glb:
            # millimetres/Z-up -> metres/Y-up by X rotation -90 degrees.
            points.append((x * 0.001, source_z * 0.001, -source_y * 0.001))
    if not points:
        raise ValueError(f"No vertices: {obj_path}")
    minimum = [min(point[axis] for point in points) for axis in range(3)]
    maximum = [max(point[axis] for point in points) for axis in range(3)]
    return minimum, maximum


def main() -> None:
    names = source_names()
    obj_paths = sorted(OBJ_DIR.glob("FJ*.obj"), key=lambda path: int(path.stem[2:]))
    if len(obj_paths) != 202:
        raise ValueError(f"Expected 202 OBJ elements, found {len(obj_paths)}")

    rows: list[dict] = []
    for obj_path in obj_paths:
        node_id = obj_path.stem
        if node_id not in names:
            raise ValueError(f"No unique deepest IS-A concept for {node_id}")
        fma_id, canonical_name = names[node_id]
        side = side_for(canonical_name)
        region, segment = region_and_segment(canonical_name, side)
        minimum, maximum = godot_bounds(obj_path)
        center = [(minimum[i] + maximum[i]) * 0.5 for i in range(3)]
        rows.append(
            {
                "node_id": node_id,
                "fma_id": fma_id,
                "canonical_name": canonical_name,
                "side": side,
                "region": region,
                "segment": segment,
                "min_x": minimum[0],
                "min_y": minimum[1],
                "min_z": minimum[2],
                "max_x": maximum[0],
                "max_y": maximum[1],
                "max_z": maximum[2],
                "center_x": center[0],
                "center_y": center[1],
                "center_z": center[2],
            }
        )

    fieldnames = list(rows[0])
    with CSV_OUTPUT.open("w", encoding="utf-8", newline="") as destination:
        writer = csv.DictWriter(destination, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(
                {
                    key: f"{value:.6f}" if isinstance(value, float) else value
                    for key, value in row.items()
                }
            )

    global_minimum = [min(row[f"min_{axis}"] for row in rows) for axis in "xyz"]
    global_maximum = [max(row[f"max_{axis}"] for row in rows) for axis in "xyz"]
    groups: defaultdict[str, list[str]] = defaultdict(list)
    for row in rows:
        groups[row["segment"]].append(row["node_id"])

    runtime = {
        "asset": "bodyparts3d_skeleton_cc_by_4_baked.glb",
        "node_count": len(rows),
        "node_name_rule": "FJ element file ID; canonical names resolved from official IS-A tables",
        "coordinate_system": {
            "units": "metres",
            "up": "+Y",
            "anterior_character_forward": "+Z",
            "posterior": "-Z",
            "anatomical_left": "+X",
            "anatomical_right": "-X",
            "godot_default_forward_note": "Rotate model root 180 degrees around Y if gameplay expects Godot -Z forward.",
            "grounding_note": "Native minimum Y is -0.070480 m; add +0.070480 m to place the lowest vertex at Y=0.",
            "node_space_note": "The _baked.glb stores these coordinates directly in every FJ mesh under an identity root, so suggested pivots can be used as written.",
        },
        "bounds_metres": {
            "minimum": global_minimum,
            "maximum": global_maximum,
            "size": [global_maximum[i] - global_minimum[i] for i in range(3)],
            "center": [
                (global_minimum[i] + global_maximum[i]) * 0.5 for i in range(3)
            ],
        },
        "suggested_pivots_metres_native_local": {
            "pelvis_root": [0.0, 0.840, 0.070],
            "neck": [0.0, 1.460, 0.064],
            "shoulder_l": [0.180, 1.315, 0.076],
            "shoulder_r": [-0.180, 1.315, 0.076],
            "elbow_l": [0.220, 1.040, 0.085],
            "elbow_r": [-0.220, 1.040, 0.085],
            "wrist_l": [0.240, 0.810, 0.092],
            "wrist_r": [-0.240, 0.810, 0.092],
            "hip_l": [0.075, 0.820, 0.080],
            "hip_r": [-0.075, 0.820, 0.080],
            "knee_l": [0.070, 0.370, 0.082],
            "knee_r": [-0.070, 0.370, 0.082],
            "ankle_l": [0.075, -0.005, 0.085],
            "ankle_r": [-0.075, -0.005, 0.085],
        },
        "segment_nodes": dict(sorted(groups.items())),
        "nodes": {
            row["node_id"]: {
                key: value
                for key, value in row.items()
                if key not in {"node_id"}
            }
            for row in rows
        },
    }
    JSON_OUTPUT.write_text(
        json.dumps(runtime, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    counts: defaultdict[str, int] = defaultdict(int)
    for row in rows:
        counts[row["segment"]] += 1
    summary_lines = [
        "BodyParts3D skeleton node summary",
        "=================================",
        "",
        "Node names in the GLB are official BodyParts3D element IDs (`FJ…`).",
        "Canonical English and FMA names come from `isa_element_parts.txt` plus",
        "`isa_inclusion_relation_list.txt`; every selected node had one unique",
        "deepest IS-A concept.",
        "",
        f"Native metre/Y-up bounds: min={global_minimum}, max={global_maximum}",
        "Anatomical forward/front: +Z; left: +X; right: -X; up: +Y.",
        "Rotate the GLB root 180° around Y for Godot's conventional -Z forward.",
        "",
        "Segments:",
    ]
    summary_lines.extend(
        f"- {segment}: {count} nodes" for segment, count in sorted(counts.items())
    )
    summary_lines.extend(["", "Nodes:"])
    summary_lines.extend(
        f"{row['node_id']}\t{row['fma_id']}\t{row['canonical_name']}\t{row['side']}\t{row['region']}\t{row['segment']}"
        for row in rows
    )
    SUMMARY_OUTPUT.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    print(CSV_OUTPUT)
    print(JSON_OUTPUT)
    print(SUMMARY_OUTPUT)


if __name__ == "__main__":
    main()
