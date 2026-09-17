#!/usr/bin/env python3
"""Validate a received motion delivery without executing Blender or its files.

Uses only the Python standard library. The JSON report validates declared
provenance fields, not the truth of Windows execution or visual quality.
"""

import argparse
import hashlib
import json
import math
import re
import sys
from datetime import datetime, timezone
from pathlib import Path, PureWindowsPath


SOURCE_SHA256 = "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
SOURCE_PATH = "assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
REQUIRED = {"idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"}
ATTACKS = {"right_diagonal", "left_reverse", "overhead"}
TIME_TOL = 1e-5
POSITION_TOL = 1e-3
ANGLE_TOL = 2e-3
UNIT_TOL = 1e-3
REST_WRIST = (0.0679751875, -0.1080001335, 0.0524637313)
UPPER_LENGTH = 0.34000002959
FOREARM_LENGTH = 0.26000002263


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result


def read_json(path):
    def reject_constant(value):
        raise ValueError("non-finite JSON constant: " + value)
    return json.loads(path.read_text(encoding="utf-8-sig"),
                      object_pairs_hook=unique_object, parse_constant=reject_constant)


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def norm(value):
    return math.hypot(*value)


def json_equal(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(json_equal(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(json_equal(a[k], b[k]) for k in a)
    return a == b


def schema_errors(value, schema, document, path="$"):
    """Strict subset covering our saved schema; unsupported keywords fail closed."""
    if isinstance(schema, bool):
        return [] if schema else [path + ": disallowed by schema"]
    supported = {"$schema", "$id", "$defs", "$ref", "title", "description", "type", "const", "enum",
                 "allOf", "not", "required", "properties", "additionalProperties", "items", "minItems",
                 "maxItems", "minLength", "pattern", "format", "minimum", "exclusiveMinimum"}
    if not isinstance(schema, dict) or set(schema) - supported:
        raise ValueError("unsupported or invalid schema at " + path)
    errors = []
    if "$ref" in schema:
        reference = schema["$ref"]
        if not reference.startswith("#/"):
            raise ValueError("only local schema references are supported")
        target = document
        for key in reference[2:].split("/"):
            target = target[key.replace("~1", "/").replace("~0", "~")]
        errors.extend(schema_errors(value, target, document, path))
    for child in schema.get("allOf", []):
        errors.extend(schema_errors(value, child, document, path))
    if "not" in schema and not schema_errors(value, schema["not"], document, path):
        errors.append(path + ": matches forbidden schema")
    types = {"object": isinstance(value, dict), "array": isinstance(value, list),
             "string": isinstance(value, str), "boolean": isinstance(value, bool),
             "number": type(value) in (int, float), "integer": type(value) is int}
    if "type" in schema and not types.get(schema["type"], False):
        return errors + [path + ": expected " + str(schema["type"])]
    if "const" in schema and not json_equal(value, schema["const"]):
        errors.append(path + ": differs from required constant")
    if "enum" in schema and not any(json_equal(value, choice) for choice in schema["enum"]):
        errors.append(path + ": value outside schema enum")
    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                errors.append(path + ": required property missing: " + key)
        properties = schema.get("properties", {})
        for key, child in value.items():
            errors.extend(schema_errors(child, properties.get(key, schema.get("additionalProperties", True)), document, path + "." + key))
    if isinstance(value, list):
        if len(value) < schema.get("minItems", 0) or len(value) > schema.get("maxItems", math.inf):
            errors.append(path + ": invalid array length")
        for index, child in enumerate(value):
            errors.extend(schema_errors(child, schema.get("items", True), document, "%s[%d]" % (path, index)))
    if isinstance(value, str):
        if len(value) < schema.get("minLength", 0) or ("pattern" in schema and not re.search(schema["pattern"], value)):
            errors.append(path + ": string length or pattern mismatch")
        if "format" in schema:
            if schema["format"] != "date-time":
                raise ValueError("unsupported schema format: " + schema["format"])
            try:
                stamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
                if stamp.tzinfo is None or "T" not in value.upper():
                    raise ValueError("timezone required")
            except ValueError:
                errors.append(path + ": invalid date-time")
    if type(value) in (int, float):
        if value < schema.get("minimum", -math.inf) or value <= schema.get("exclusiveMinimum", -math.inf):
            errors.append(path + ": numeric bound violated")
    return errors


def difference(a, b):
    return [x - y for x, y in zip(a, b)]


def normalized(q):
    return [value / norm(q) for value in q]


def transformed_point(sample, point):
    x, y, z, w = normalized(sample["rotation_xyzw"])
    uv = [y*point[2]-z*point[1], z*point[0]-x*point[2], x*point[1]-y*point[0]]
    uuv = [y*uv[2]-z*uv[1], z*uv[0]-x*uv[2], x*uv[1]-y*uv[0]]
    return [point[i] + 2.0*(w*uv[i]+uuv[i]) + sample["position"][i] for i in range(3)]


def right_arm_errors(clip):
    errors, metrics = [], {"sample_count": len(clip.get("right_arm", []))}
    arms, sword, shield = clip.get("right_arm", []), clip["tracks"]["sword"], clip["tracks"]["shield"]
    if len(arms) != len(sword) or len(arms) != len(shield):
        return ["joint and pivot sample counts differ"], metrics
    worst = {"wrist_error_meters": 0.0, "upper_length_relative_error": 0.0, "forearm_length_relative_error": 0.0}
    for index, (arm, weapon, offhand) in enumerate(zip(arms, sword, shield)):
        if any(abs(arm["time_seconds"] - p["time_seconds"]) > TIME_TOL for p in (weapon, offhand)):
            errors.append("joint/pivot times differ at sample %d" % index)
        if abs(norm(weapon["rotation_xyzw"]) - 1.0) > UNIT_TOL:
            continue  # Pivot validation reports invalid quaternions separately.
        worst["wrist_error_meters"] = max(worst["wrist_error_meters"], norm(difference(arm["wrist"], transformed_point(weapon, REST_WRIST))))
        worst["upper_length_relative_error"] = max(worst["upper_length_relative_error"], abs(norm(difference(arm["shoulder"], arm["elbow"])) / UPPER_LENGTH - 1.0))
        worst["forearm_length_relative_error"] = max(worst["forearm_length_relative_error"], abs(norm(difference(arm["elbow"], arm["wrist"])) / FOREARM_LENGTH - 1.0))
    metrics.update(worst)
    for key, tolerance in (("wrist_error_meters", POSITION_TOL), ("upper_length_relative_error", 0.01), ("forearm_length_relative_error", 0.01)):
        if worst[key] > tolerance:
            errors.append("%s exceeds tolerance: %.9g" % (key, worst[key]))
    if clip["loop"] and arms:
        seam = max(norm(difference(arms[0][joint], arms[-1][joint])) for joint in ("shoulder", "elbow", "wrist"))
        metrics["loop_joint_error_meters"] = seam
        if seam > POSITION_TOL:
            errors.append("loop joint endpoints differ")
    return errors, metrics


def angular_velocity(a, b, delta):
    # q_b * inverse(q_a), with rotations in xyzw order and camera coordinates.
    x, y, z, w = normalized(b)
    u, v, s, t = normalized(a)
    relative = [-w*u + x*t - y*s + z*v,
                -w*v + x*s + y*t - z*u,
                -w*s - x*v + y*u + z*t]
    scalar = w*t + x*u + y*v + z*s
    if scalar < 0:
        relative, scalar = [-v for v in relative], -scalar
    sine = norm(relative)
    if sine < 1e-12:
        return [0.0, 0.0, 0.0]
    factor = 2.0 * math.atan2(sine, scalar) / (sine * delta)
    return [value * factor for value in relative]


def seam_velocity(samples, at_end, rotation=False):
    chosen = samples[-3:] if at_end else samples[:3]
    rates, intervals = [], []
    for a, b in zip(chosen, chosen[1:]):
        delta = b["time_seconds"] - a["time_seconds"]
        intervals.append(delta)
        rates.append(angular_velocity(a["rotation_xyzw"], b["rotation_xyzw"], delta)
                     if rotation else [v / delta for v in difference(b["position"], a["position"])])
    if len(rates) == 1:
        return rates[0]
    h1, h2 = intervals
    # Uneven-step, one-sided quadratic derivative; exact phase samples can
    # shorten a nominal interval, so assuming equal spacing would be incorrect.
    weights = (-h2 / (h1+h2), (h1+2*h2) / (h1+h2)) if at_end else ((2*h1+h2) / (h1+h2), -h1 / (h1+h2))
    return [weights[0]*a + weights[1]*b for a, b in zip(*rates)]


def pose_error(a, b):
    distance = norm(difference(a["position"], b["position"]))
    cosine = min(1.0, abs(dot(normalized(a["rotation_xyzw"]), normalized(b["rotation_xyzw"]))))
    return distance, 2.0 * math.acos(cosine)


def validate(args):
    manifest_path = args.manifest.resolve()
    artifact_root = args.artifact_root.resolve()
    report = {
        "status": "fail", "manifest": str(manifest_path), "artifact_root": str(artifact_root),
        "schema": str(args.schema.resolve()), "errors": [], "clips": {}, "artifacts": [],
        "scope": "Independent schema, numeric continuity, timing, and received-file hash checks. Provenance is declared metadata; Windows execution, Blender actions, source preservation on Windows, and visual similarity are not established by this report.",
        "tolerances": {"time_seconds": TIME_TOL, "position_meters": POSITION_TOL,
                       "rotation_radians": ANGLE_TOL, "quaternion_length": UNIT_TOL,
                       "loop_linear_velocity": "0.02 m/s + 20% of larger endpoint speed",
                       "loop_angular_velocity": "0.1 rad/s + 20% of larger endpoint speed"},
    }
    errors = report["errors"]

    def check(condition, message):
        if not condition:
            errors.append(message)

    def finite_tree(value, path="$"):
        if type(value) in (int, float):
            try:
                finite = math.isfinite(value)
            except OverflowError:
                finite = False
            if not finite:
                errors.append(path + ": numeric value is outside finite floating-point range")
        elif isinstance(value, dict):
            for key, child in value.items():
                finite_tree(child, path + "." + key)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                finite_tree(child, "%s[%d]" % (path, index))

    try:
        schema, manifest = read_json(args.schema), read_json(manifest_path)
        finite_tree(manifest)
        if errors:
            return report
        report["schema_validator"] = "stdlib subset for saved schema keywords; unsupported keywords rejected"
        errors.extend(schema_errors(manifest, schema, schema))
        report["manifest_sha256"] = sha256(manifest_path)
        report["schema_sha256"] = sha256(args.schema)
        if errors:
            return report
    except (OSError, ValueError) as error:
        errors.append("Cannot load manifest/schema: " + str(error))
        return report
    except Exception as error:
        errors.append("Schema validation failed: %s: %s" % (type(error).__name__, error))
        return report

    source = manifest["source"]
    check(source["godot_model_sha256"] == SOURCE_SHA256, "source: canonical GLB SHA-256 differs")
    check(source["godot_model_path"] == "res://" + SOURCE_PATH, "source: canonical Godot model path differs")
    try:
        actual = sha256(args.source_file)
        report["canonical_source"] = {"path": str(args.source_file.resolve()), "actual_sha256": actual}
        check(actual == SOURCE_SHA256, "source: actual preserved local GLB does not match the canonical hash")
    except OSError as error:
        errors.append("Cannot independently hash canonical source: " + str(error))

    provenance = manifest["provenance"]
    report["declared_provenance"] = provenance
    check(provenance["execution_os"] == "Windows" and provenance["exit_code"] == 0 and provenance["source_preserved"] is True,
          "provenance: successful Windows execution and source-preserved declarations are required")
    for key in ("blender_executable", "working_directory"):
        check(PureWindowsPath(provenance[key]).is_absolute(), "provenance.%s must be an absolute Windows path" % key)
    try:
        started = datetime.fromisoformat(provenance["started_at_utc"].replace("Z", "+00:00"))
        completed = datetime.fromisoformat(provenance["completed_at_utc"].replace("Z", "+00:00"))
        check(started.utcoffset() == timezone.utc.utcoffset(started) and completed.utcoffset() == timezone.utc.utcoffset(completed),
              "provenance: UTC timestamps must have zero timezone offset")
        check(completed >= started, "provenance: completion precedes start")
    except (ValueError, TypeError) as error:
        errors.append("provenance: invalid UTC chronology: " + str(error))

    clips = manifest["clips"]
    check(REQUIRED <= set(clips), "clips: missing required clips: " + ", ".join(sorted(REQUIRED - set(clips))))
    for name, clip in clips.items():
        duration, tracks = clip["duration_seconds"], clip["tracks"]
        if name in REQUIRED:
            check({"sword", "shield"} <= set(tracks), name + ": required sword and shield tracks are missing")
            check(clip["kind"] == ("attack" if name in ATTACKS else "locomotion"), name + ": unexpected clip kind")
        if name in REQUIRED - {"idle"}:
            check(clip["loop"] == (name in {"run", "air"}), name + ": unexpected loop setting")
        for segment in clip["reference_segments"]:
            check(segment["end_seconds"] > segment["start_seconds"], name + ": reference segment must have positive duration")
        boundaries = [0.0, duration]
        if clip["kind"] == "attack":
            timing = clip.get("timing")
            check(timing is not None, name + ": attack timing is missing")
            if timing:
                windup, active, hit, recovery = [timing[key + "_seconds"] for key in ("windup", "active", "hit", "recovery")]
                check(0 < hit < active, name + ": hit must be strictly inside active phase")
                check(abs(windup + active + recovery - duration) <= TIME_TOL, name + ": timing sum differs from duration")
                boundaries.extend([windup, windup + hit, windup + active])
        else:
            check("timing" not in clip, name + ": locomotion clip must not declare attack timing")
        report["clips"][name] = {"duration_seconds": duration, "tracks": {}}
        if manifest["schema_version"] == 2:
            arm_errors, arm_metrics = right_arm_errors(clip)
            errors.extend(name + ".right_arm: " + error for error in arm_errors)
            report["clips"][name]["right_arm"] = arm_metrics
        for track_name, samples in tracks.items():
            prefix = name + "." + track_name
            times = [sample["time_seconds"] for sample in samples]
            valid_times = all(0 <= t <= duration + TIME_TOL for t in times) and all(b > a for a, b in zip(times, times[1:]))
            check(valid_times, prefix + ": sample times must strictly increase within the clip")
            check(abs(times[0]) <= TIME_TOL and abs(times[-1] - duration) <= TIME_TOL, prefix + ": track endpoints must be zero and duration")
            check(all(any(abs(t - boundary) <= TIME_TOL for t in times) for boundary in boundaries), prefix + ": exact attack phase/contact boundary sample is missing")
            quats = [sample["rotation_xyzw"] for sample in samples]
            valid_quats = all(abs(norm(q) - 1.0) <= UNIT_TOL for q in quats)
            check(valid_quats, prefix + ": quaternion is not unit length")
            check(all(dot(a, b) >= -1e-8 for a, b in zip(quats, quats[1:])), prefix + ": quaternion signs are not continuous")
            metrics = {"sample_count": len(samples)}
            report["clips"][name]["tracks"][track_name] = metrics
            if not valid_times or not valid_quats:
                continue
            max_gap = max(b - a for a, b in zip(times, times[1:]))
            metrics["max_sample_gap_seconds"] = max_gap
            check(max_gap <= 1.0 / clip["nominal_sample_hz"] + TIME_TOL, prefix + ": samples do not sustain the declared nominal rate")
            if clip["loop"]:
                distance, angle = pose_error(samples[0], samples[-1])
                metrics["loop_position_error_meters"] = distance if math.isfinite(distance) else None
                metrics["loop_rotation_error_radians"] = angle if math.isfinite(angle) else None
                check(distance <= POSITION_TOL and angle <= ANGLE_TOL, prefix + ": loop endpoint transforms differ")
                for rotation, tolerance, label in ((False, 0.02, "linear"), (True, 0.1, "angular")):
                    first, last = seam_velocity(samples, False, rotation), seam_velocity(samples, True, rotation)
                    error = norm(difference(first, last))
                    limit = tolerance + 0.2 * max(norm(first), norm(last))
                    metrics["loop_%s_velocity_error" % label] = error if math.isfinite(error) else None
                    check(math.isfinite(error) and math.isfinite(limit) and error <= limit, prefix + ": loop %s velocity is discontinuous (%.6g > %.6g)" % (label, error, limit))
            if name == "land" or clip["kind"] == "attack":
                idle = clips.get("idle", {}).get("tracks", {}).get(track_name, [])
                if idle and abs(norm(idle[0]["rotation_xyzw"]) - 1.0) <= UNIT_TOL:
                    for endpoint in ([0, -1] if clip["kind"] == "attack" else [-1]):
                        distance, angle = pose_error(samples[endpoint], idle[0])
                        check(distance <= POSITION_TOL and angle <= ANGLE_TOL,
                              prefix + ": %s endpoint differs from shared idle pose" % ("first" if endpoint == 0 else "last"))

    seen_paths, kinds = set(), set()
    for artifact in manifest["artifacts"]:
        relative = artifact["relative_path"].replace("\\", "/")
        item = dict(artifact)
        report["artifacts"].append(item)
        kinds.add(artifact["kind"])
        try:
            check(relative.casefold() not in seen_paths, "artifact: duplicate path: " + relative)
            seen_paths.add(relative.casefold())
            if not relative or relative.startswith("/") or PureWindowsPath(relative).drive or any(part in {"", ".", ".."} for part in relative.split("/")):
                raise ValueError("path must be relative without traversal or drive prefixes")
            path = (artifact_root / relative).resolve()
            path.relative_to(artifact_root)
            if not path.is_file():
                raise ValueError("artifact is not a regular file")
            if path == manifest_path:
                raise ValueError("manifest cannot list its own recursively dependent hash")
            item["actual_sha256"] = sha256(path)
            item["size_bytes"] = path.stat().st_size
            check(item["actual_sha256"] == artifact["sha256"], "artifact SHA-256 mismatch: " + relative)
        except (OSError, ValueError) as error:
            errors.append("artifact %s: %s" % (relative, error))
    check({"blend", "execution_log", "validation_report"} <= kinds, "artifacts: editable blend, execution log and validation report are required")
    check(bool(kinds & {"preview_video", "preview_image"}), "artifacts: an actual-render preview file must be declared")
    report["status"] = "pass" if not errors else "fail"
    return report


def main():
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--artifact-root", type=Path, required=True)
    parser.add_argument("--schema", type=Path, default=here / "motion_manifest.v2.schema.json")
    parser.add_argument("--source-file", type=Path, default=here.parents[1] / "godot-game" / SOURCE_PATH)
    parser.add_argument("--report", type=Path, help="Also write the JSON report to this file.")
    args = parser.parse_args()
    report = validate(args)
    output = json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)
    print(output)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(output + "\n", encoding="utf-8")
    return 0 if report["status"] == "pass" else 1


if __name__ == "__main__":
    sys.exit(main())
