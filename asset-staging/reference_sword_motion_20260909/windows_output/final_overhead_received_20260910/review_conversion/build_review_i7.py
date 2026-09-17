"""Lossless projection of actual Blender sidecar samples into the Mac review schema.

This does not author, interpolate, round, normalize, or transform motion samples.
The input sidecar remains the authority for part matrices and raw values.
Run with the MCP runtime Python, which provides jsonschema.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from datetime import datetime
from pathlib import Path

import jsonschema

SPACE = "godot_camera_local_x_right_y_up_minus_z_forward"
SWORD_NORMALIZATION = "camera_motion_delta_times_source_ready"
SHIELD_NORMALIZATION = "camera_motion_delta_times_production_shield_idle"
SOURCE_BLEND_SHA = "3a94649c5363a362cb55513672ce6f4d91fc377ec32fe11ee0cc5bd145273df1"
SOURCE_GLB_SHA = "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
W0 = [0.0679751875, -0.1080001335, 0.0524637313]
E0 = [0.2366280243, -0.1080001099, 0.2503430693]
H0 = [0.4571740416, -0.1080000789, 0.5091083575]
H_CAMERA = [0.248202859842, -0.169864125386, 0.078819999963]


def read_json(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(a, b)))


def finite_vector(value, size, label):
    if not isinstance(value, list) or len(value) != size:
        raise ValueError(f"{label} must contain exactly {size} numbers")
    if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in value):
        raise ValueError(f"{label} contains a non-finite/non-numeric value")


def transform_quaternion(pose, point):
    x, y, z, w = pose["rotation_xyzw"]
    vx, vy, vz = point
    tx, ty, tz = 2*(y*vz-z*vy), 2*(z*vx-x*vz), 2*(x*vy-y*vx)
    rotated = [vx+w*tx+y*tz-z*ty, vy+w*ty+z*tx-x*tz, vz+w*tz+x*ty-y*tx]
    return [r+p for r, p in zip(rotated, pose["position"])]


def transform_part(part, point):
    cols = part["basis_columns"]
    return [sum(cols[j][i]*point[j] for j in range(3))+part["position"][i] for i in range(3)]


def field(data, aliases, label):
    for name in aliases:
        if name in data:
            return data[name]
    raise ValueError(f"Actual execution record lacks {label}; accepted fields: {aliases}")


def build_provenance(execution, authoring_report):
    data = dict(execution)
    # The process wrapper owns timing/argv; the executed Blender script owns
    # bpy.app.version_string and before/after input hash verification.
    for key in ("blender_version", "source_preserved"):
        if key not in data and key in authoring_report:
            data[key] = authoring_report[key]
    if "provenance" in execution:
        data.update(execution["provenance"])
    if "runs" in execution:
        candidates = [r for r in execution["runs"] if r.get("mode") in ("author", "authoring", "build", "export")]
        if len(candidates) != 1:
            raise ValueError("Execution report must identify exactly one successful authoring run")
        data.update(candidates[0])
    result = {
        "execution_os": field(data, ("execution_os", "os"), "execution OS"),
        "hostname": field(data, ("hostname",), "hostname"),
        "blender_executable": field(data, ("blender_executable", "blender_binary"), "Blender executable"),
        "blender_version": field(data, ("blender_version",), "actual Blender version"),
        "command_argv": field(data, ("command_argv", "argv"), "executed argv"),
        "working_directory": field(data, ("working_directory", "cwd"), "execution cwd"),
        "started_at_utc": field(data, ("started_at_utc", "start_utc", "started_utc"), "actual start UTC"),
        "completed_at_utc": field(data, ("completed_at_utc", "end_utc", "completed_utc"), "actual end UTC"),
        "exit_code": field(data, ("exit_code",), "process exit code"),
        "source_preserved": field(data, ("source_preserved",), "verified source preservation"),
    }
    start = datetime.fromisoformat(result["started_at_utc"].replace("Z", "+00:00"))
    end = datetime.fromisoformat(result["completed_at_utc"].replace("Z", "+00:00"))
    if start.tzinfo is None or end.tzinfo is None or end < start:
        raise ValueError("Actual execution timestamps must be ordered and timezone-aware")
    if start.utcoffset().total_seconds() != 0 or end.utcoffset().total_seconds() != 0:
        raise ValueError("Execution UTC fields must use UTC offsets")
    if result["execution_os"] != "Windows" or result["exit_code"] != 0 or result["source_preserved"] is not True:
        raise ValueError("Authoring must be an actual successful Windows run with preserved sources")
    return result


def validate_samples(sidecar):
    required = {
        "schema_version": 1,
        "status": "authored_windows_surface_finished_output",
        "clip_id": "overhead",
        "coordinate_space": SPACE,
        "geometry_space": "canonical_source_ready_inverse",
        "seconds_basis": "original_authored_clip_seconds",
    }
    for key, value in required.items():
        if sidecar.get(key) != value:
            raise ValueError(f"Sidecar {key!r} must be {value!r}")
    frames = sidecar["frames"]
    if len(frames) != 187:
        raise ValueError(f"Expected actual 120 Hz, 1.55-second samples including both endpoints: 187; got {len(frames)}")
    maxima = {"wrist_m": 0.0, "forearm_ratio_change": 0.0, "upper_arm_ratio_change": 0.0,
              "part_endpoint_m": 0.0, "cuff_unit_scale_error": 0.0, "shoulder_displacement_m": 0.0,
              "quaternion_unit_norm_error": 0.0}
    frame_audits = []
    for index, sample in enumerate(frames):
        t = sample["time_seconds"]
        if not math.isfinite(t) or abs(t-index/120) > 1e-10:
            raise ValueError(f"Sample {index}: time must equal index/120; got {t}")
        for track in ("sword", "shield"):
            pose = sample[track]
            finite_vector(pose["position"], 3, f"{index}.{track}.position")
            finite_vector(pose["rotation_xyzw"], 4, f"{index}.{track}.rotation_xyzw")
            error = abs(math.sqrt(sum(x*x for x in pose["rotation_xyzw"]))-1)
            maxima["quaternion_unit_norm_error"] = max(maxima["quaternion_unit_norm_error"], error)
            if error > 1e-5:
                raise ValueError(f"Sample {index}: {track} quaternion is not unit length")
        arm = sample["right_arm"]
        for joint in ("shoulder", "elbow", "wrist"):
            finite_vector(arm[joint], 3, f"{index}.{joint}")
        wrist_error = distance(transform_quaternion(sample["sword"], W0), arm["wrist"])
        forearm = distance(arm["wrist"], arm["elbow"])
        upper = distance(arm["elbow"], arm["shoulder"])
        f_change, u_change = abs(forearm/0.26-1), abs(upper/0.34-1)
        shoulder_change = distance(arm["shoulder"], H_CAMERA)
        for name, value in (("wrist_m", wrist_error), ("forearm_ratio_change", f_change),
                            ("upper_arm_ratio_change", u_change), ("shoulder_displacement_m", shoulder_change)):
            maxima[name] = max(maxima[name], value)
        parts = arm["parts_camera"]
        for part_name in ("forearm", "upper_arm", "cuff"):
            part = parts[part_name]
            finite_vector(part["position"], 3, f"{index}.{part_name}.position")
            if len(part["basis_columns"]) != 3:
                raise ValueError(f"Sample {index}: {part_name} requires three basis columns")
            for col in part["basis_columns"]:
                finite_vector(col, 3, f"{index}.{part_name}.basis_column")
        connections = [("forearm", W0, "wrist"), ("forearm", E0, "elbow"),
                       ("upper_arm", E0, "elbow"), ("upper_arm", H0, "shoulder"), ("cuff", W0, "wrist")]
        endpoint_error = max(distance(transform_part(parts[part], point), arm[joint]) for part, point, joint in connections)
        maxima["part_endpoint_m"] = max(maxima["part_endpoint_m"], endpoint_error)
        cuff = parts["cuff"]["basis_columns"]
        cuff_error = max(abs(sum(cuff[i][k]*cuff[j][k] for k in range(3))-(1 if i == j else 0)) for i in range(3) for j in range(3))
        maxima["cuff_unit_scale_error"] = max(maxima["cuff_unit_scale_error"], cuff_error)
        if wrist_error > 0.001 or f_change > 0.01 or u_change > 0.01 or endpoint_error > 0.00003 or cuff_error > 0.0001:
            raise ValueError(f"Sample {index} violates arm constraints: wrist={wrist_error}, forearm={f_change}, upper={u_change}, endpoint={endpoint_error}, cuff={cuff_error}")
        frame_audits.append({"time_seconds": t, "forearm_m": forearm, "upper_arm_m": upper,
                             "forearm_ratio": forearm/0.26, "upper_arm_ratio": upper/0.34,
                             "wrist_error_m": wrist_error, "part_endpoint_error_m": endpoint_error,
                             "shoulder_displacement_m": shoulder_change})
    for seam in (40/60, 42/60, 46/60, 1.55):
        if not any(abs(frame["time_seconds"]-seam) < 1e-12 for frame in frames):
            raise ValueError(f"Missing exact phase/hit/endpoint sample at {seam}")
    return maxima, frame_audits


def write_new_or_identical(path, data):
    content = json.dumps(data, ensure_ascii=False, separators=(",", ":"), allow_nan=False)+"\n"
    if path.exists() and path.read_text(encoding="utf-8") != content:
        raise FileExistsError(f"Refusing to overwrite a different saved review file: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples", required=True, type=Path)
    parser.add_argument("--execution", required=True, type=Path)
    parser.add_argument("--authoring-log", required=True, type=Path)
    parser.add_argument("--authoring-report", type=Path,
                        help="Defaults to authoring_report.json beside the raw sidecar")
    parser.add_argument("--source-blend", required=True, type=Path)
    parser.add_argument("--source-glb", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--shield-contract", required=True, type=Path,
                        help="Explicit normalization evidence for already-normalized shield samples")
    parser.add_argument("--shield-confirmation", type=Path,
                        help="Separate later confirmation record; does not alter the immutable baseline used during authoring")
    parser.add_argument("--allow-local-shield-baseline", action="store_true",
                        help="Disclose that the Mac source hash is not verified; use documented local paired-shield baseline for this review")
    parser.add_argument("--artifact", action="append", default=[], metavar="KIND=PATH")
    args = parser.parse_args()
    raw = read_json(args.samples)
    execution = read_json(args.execution)
    authoring_path = args.authoring_report or args.samples.with_name("authoring_report.json")
    authoring = read_json(authoring_path)
    import re
    log_text = args.authoring_log.read_text(encoding="utf-8", errors="replace")
    version_match = re.search(r"^Blender ([^\r\n]+?) \(hash ", log_text, re.MULTILINE)
    if version_match is None:
        raise ValueError("Actual finalization log lacks a Blender version line")
    authoring["blender_version"] = version_match.group(1)
    sidecar_artifact = authoring.get("artifacts", {}).get(args.samples.name, {})
    if sidecar_artifact.get("sha256") != sha256(args.samples):
        raise ValueError("Actual authoring report must identify this exact raw sidecar SHA256")
    shield_contract = read_json(args.shield_contract)
    shield_confirmation = read_json(args.shield_confirmation) if args.shield_confirmation else None
    if shield_confirmation:
        if shield_confirmation.get("baseline_contract_sha256") != sha256(args.shield_contract):
            raise ValueError("Later shield confirmation refers to a different authoring baseline")
        if not shield_confirmation.get("reported_by") or not shield_confirmation.get("evidence_scope"):
            raise ValueError("Later shield confirmation must preserve its source and scope")
    if sha256(args.source_blend) != SOURCE_BLEND_SHA or sha256(args.source_glb) != SOURCE_GLB_SHA:
        raise ValueError("Original input hashes do not match the preserved source contract")
    if shield_contract.get("normalization") != SHIELD_NORMALIZATION:
        raise ValueError("Shield contract does not declare the receiving normalization")
    if raw.get("shield_normalization") != SHIELD_NORMALIZATION:
        raise ValueError("Sidecar shield transforms have not been declared normalized to the receiving shield idle")
    if raw.get("shield_idle_contract_sha256") != sha256(args.shield_contract):
        raise ValueError("Sidecar must name the exact shield normalization evidence hash used for authoring")
    mac_verified = shield_contract.get("mac_source_match_verified") is True
    if not mac_verified and not args.allow_local_shield_baseline:
        raise ValueError("Mac shield idle source equivalence remains unverified. Explicitly choose the documented local review baseline or obtain Mac confirmation")
    shield_note = ("Mac shield idle source equivalence verified by accompanying contract." if mac_verified else
                   "Shield normalization uses the documented local paired-sword/shield idle baseline; Mac current-source equivalence remains unverified and must be checked before integration.")
    if shield_confirmation and shield_confirmation.get("mac_idle_matrix_match_reported") is True:
        shield_note = ("The coordinating root subsequently reported that the local shield idle matrix matches the supplied Mac matrix within "
                       + str(shield_confirmation["reported_max_matrix_difference"]) + ". "
                       "That source report is preserved separately; Mac source hashes and actual runtime equivalence were not independently verified by this converter.")
    maxima, frame_audits = validate_samples(raw)
    frames = raw["frames"]
    tracks = {name: [{"time_seconds": frame["time_seconds"],
                      "position": copy.deepcopy(frame[name]["position"]),
                      "rotation_xyzw": copy.deepcopy(frame[name]["rotation_xyzw"])} for frame in frames]
              for name in ("sword", "shield")}
    right_arm = [{"time_seconds": frame["time_seconds"],
                  **{joint: copy.deepcopy(frame["right_arm"][joint]) for joint in ("shoulder", "elbow", "wrist")}}
                 for frame in frames]
    document = {
        "schema_version": 1, "status": "authored_windows_review_output",
        "reference_video_url": "https://youtu.be/sU7jk2OQlgc",
        "source": {"godot_model_path": "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
                   "godot_model_sha256": SOURCE_GLB_SHA, "blender_input_path": str(args.source_blend.resolve()),
                   "blender_input_sha256": SOURCE_BLEND_SHA},
        "coordinate_system": {"space": SPACE, "units": "meters", "position_order": "xyz", "quaternion_order": "xyzw",
                              "transform_semantics": "absolute_pivot_local_to_camera", "scale": [1, 1, 1],
                              "sword_normalization": SWORD_NORMALIZATION, "shield_normalization": SHIELD_NORMALIZATION,
                              "interpolation": "linear_position_shortest_slerp_rotation"},
        "camera": {"vertical_fov_degrees": 76.0, "aspect_ratio": [16, 9], "animated": False},
        "provenance": build_provenance(execution, authoring),
        "clips": {"overhead": {
            "kind": "attack", "duration_seconds": 1.55, "loop": False, "nominal_sample_hz": 120,
            "tracks": tracks,
            "timing": {"windup_seconds": 40/60, "active_seconds": 6/60, "hit_seconds": 2/60,
                       "recovery_seconds": 47/60, "runtime_mapping": "phase_resample", "reference_charge": 0.0},
            "reference_segments": [{"start_seconds": 1040/60, "end_seconds": 1133/60,
                                    "observations": "Actual decoded 60 fps reference: rise during frames 1040-1047; hold offscreen; visible downward pass at 1080-1086; recovery to 1133."}],
            "notes": "hit_seconds=2/60 is a selected review/game checkpoint at source frame 1082 (18.033333 s), not evidence of actual contact in the source video. Original 1.55-second rhythm is preserved; runtime phase remapping has not been applied."
        }},
        "right_arm": right_arm,
        "notes": "Lossless review projection of the latest finished iteration_07, exactly one 1.55-second overhead. The eight controller samples and joints preserve the approved i4 trajectory. The finished continuous sleeve additionally REQUIRES the complete final GLB hierarchy: one Skin, seven sleeve bones, bind transforms, the overhead animation, and three skinned meshes (RightArm_ContinuousSleeve_Surface, RightArm_Forearm_Surface, RightArm_WristCuff_Surface). This review JSON and its three part matrices CANNOT reproduce the finished skin; do not substitute rigid part transforms for the skinned surface. Actual sample values are not rounded or transformed. The provenance is the actual i7 finalization run, whose direct Blender input was the preserved i4 blend. Do not install this review file as an eight-clip production motion manifest. "
                 + shield_note
    }
    if args.artifact:
        artifacts = []
        for specification in args.artifact:
            kind, separator, path_text = specification.partition("=")
            if not separator:
                raise ValueError("Each --artifact must be KIND=PATH")
            path = Path(path_text).resolve()
            relative = Path(__import__("os").path.relpath(path, args.output.parent.resolve())).as_posix()
            artifacts.append({"kind": kind, "relative_path": relative, "sha256": sha256(path)})
        document["artifacts"] = artifacts
    schema = read_json(Path(__file__).with_name("overhead_review.schema.json"))
    validator = jsonschema.Draft202012Validator(schema, format_checker=jsonschema.FormatChecker())
    validator.validate(document)
    serialized = json.loads(json.dumps(document, allow_nan=False))
    assert serialized["clips"]["overhead"]["tracks"] == tracks
    assert serialized["right_arm"] == right_arm
    report = {"status": "pass", "schema_validation": "pass", "semantic_validation": "pass",
              "samples": len(frames), "nominal_sample_hz": 120, "duration_seconds": 1.55,
              "lossless_projection": True, "numbers_rounded": False, "transforms_changed": False,
              "arm_length_tolerance_ratio": 0.01, "wrist_tolerance_m": 0.001, "part_endpoint_tolerance_m": 0.00003,
              "maxima": maxima, "all_187_frames_validated": True, "per_frame_audit_rows_omitted_for_transfer": True,
              "raw_sidecar_sha256": sha256(args.samples), "execution_sha256": sha256(args.execution),
              "authoring_report_sha256": sha256(authoring_path),
              "authoring_log_sha256": sha256(args.authoring_log),
              "source_status": raw["status"],
              "finished_skin_required": True, "finished_skin_count": 1,
              "finished_skin_bones": 7, "finished_skinned_meshes": 3,
              "shield_contract_sha256": sha256(args.shield_contract), "mac_shield_source_match_verified": mac_verified,
              "limits": ["Numeric and schema checks do not establish visual silhouette quality.",
                         "This converter does not independently prove depsgraph evaluation or GLB playback; inspect authoring and fresh-import reports.",
                         "Part transforms are retained in the raw sidecar, not inserted into the motion track schema.",
                         "Final i7 surface playback requires the complete Skin/bind/seven-bone hierarchy and three skinned meshes; review JSON alone is insufficient."]}
    if shield_confirmation:
        report["later_shield_confirmation"] = copy.deepcopy(shield_confirmation)
        report["later_shield_confirmation_sha256"] = sha256(args.shield_confirmation)
    write_new_or_identical(args.output, document)
    report["review_sha256"] = sha256(args.output)
    report_path = args.output.with_name("overhead_review_validation_compact.json")
    write_new_or_identical(report_path, report)
    print(json.dumps({"status": "pass", "output": str(args.output.resolve()), "bytes": args.output.stat().st_size,
                      "sha256": report["review_sha256"], "samples": len(frames), "maxima": maxima,
                      "mac_shield_source_match_verified": mac_verified}, ensure_ascii=False))


if __name__ == "__main__":
    main()
