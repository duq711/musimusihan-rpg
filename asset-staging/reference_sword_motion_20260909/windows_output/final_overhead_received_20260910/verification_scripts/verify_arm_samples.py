#!/usr/bin/env python3
"""Independently audit a Blender-evaluated arm sidecar; stdlib only.

Usage: python verify_arm_samples.py arm_pose_samples.json --output report.json
Exit 0: numerical checks plus per-frame grip marker evidence pass.
Exit 1: malformed input or numerical failure. Exit 2: incomplete grip evidence.

This is a sample-consistency audit, not proof of execution, mesh preservation,
GLB replay, source video likeness, skin deformation or sleeve surface closure.
No samples, provenance, missing coordinates or visual acceptance are invented.
Additional optional evidence per frame:
  evaluated_grip_camera: {sword: [x,y,z], glove: [x,y,z]}
Both are the same canonical G landmark evaluated through each actual object's
dependency-graph transform, not a fresh copy of the sword-pose calculation.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import sys


def add(a, b):
    return [a[i] + b[i] for i in range(3)]


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def mul(a, s):
    return [v * s for v in a]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def length(a):
    return math.sqrt(dot(a, a))


def unit(a):
    n = length(a)
    if n < 1e-12:
        raise ValueError("Cannot normalize a degenerate vector")
    return mul(a, 1.0 / n)


def distance(a, b):
    return length(sub(a, b))


def eye():
    return [[1., 0., 0.], [0., 1., 0.], [0., 0., 1.]]


def transpose(a):
    return [list(v) for v in zip(*a)]


def matvec(a, v):
    return [dot(row, v) for row in a]


def matmul(a, b):
    bt = transpose(b)
    return [[dot(row, col) for col in bt] for row in a]


def matrix_error(a, b):
    return max(abs(a[i][j]-b[i][j]) for i in range(3) for j in range(3))


def transform(m, p):
    return add(matvec(m[0], p), m[1])


def compose(a, b):
    return (matmul(a[0], b[0]), transform(a, b[1]))


def inverse_rigid(m):
    r = transpose(m[0])
    return r, mul(matvec(r, m[1]), -1)


def determinant(m):
    return dot(m[0], cross(m[1], m[2]))


def number(v, label):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v):
        raise ValueError(label + " must be a finite number")
    return float(v)


def vector(v, n, label):
    if not isinstance(v, list) or len(v) != n:
        raise ValueError(label + " must be a list of length " + str(n))
    return [number(x, label) for x in v]


def pose(value, label):
    p = vector(value["position"], 3, label + ".position")
    q = vector(value["rotation_xyzw"], 4, label + ".rotation_xyzw")
    n = math.sqrt(dot(q, q))
    if n < 1e-12:
        raise ValueError(label + " quaternion is zero")
    x, y, z, w = [v/n for v in q]
    r = [[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]]
    return (r, p), abs(n - 1.0)


def part(value, label):
    cols = value["basis_columns"]
    if not isinstance(cols, list) or len(cols) != 3:
        raise ValueError(label + ".basis_columns must have three columns")
    cols = [vector(c, 3, label + ".basis_columns") for c in cols]
    return transpose(cols), vector(value["position"], 3, label + ".position")


def shortest_rotation(u, v):
    c = max(-1., min(1., dot(u, v)))
    ax = cross(u, v)
    s = length(ax)
    if s <= 1e-9:
        if c >= 0:
            return eye()
        seed = min(eye(), key=lambda e: abs(dot(e, u)))
        ax = unit(cross(u, seed))
        return [[2*ax[i]*ax[j] - float(i == j) for j in range(3)] for i in range(3)]
    ax = mul(ax, 1/s)
    angle = math.atan2(s, c)
    ca, sa = math.cos(angle), math.sin(angle)
    skew = [[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]]
    return [[ca*float(i == j) + (1-ca)*ax[i]*ax[j] + sa*skew[i][j]
             for j in range(3)] for i in range(3)]


def fit_segment(a0, b0, a1, b1):
    d0, d1 = sub(b0, a0), sub(b1, a1)
    l0, l1 = length(d0), length(d1)
    if min(l0, l1) < 1e-5:
        return eye(), [0., 0., 0.]
    u, v = mul(d0, 1/l0), mul(d1, 1/l1)
    k = l1/l0
    stretch = [[float(i == j)+(k-1)*u[i]*u[j] for j in range(3)] for i in range(3)]
    b = matmul(shortest_rotation(u, v), stretch)
    return b, sub(a1, matvec(b, a0))


def gram_schmidt_columns(b):
    x, y, z = transpose(b)
    qx = unit(x)
    qy = unit(sub(y, mul(qx, dot(qx, y))))
    qz = unit(sub(sub(z, mul(qx, dot(qx, z))), mul(qy, dot(qy, z))))
    return transpose([qx, qy, qz])


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def audit(data, constants):
    required = {"schema_version": 1, "status": "authored_windows_output", "clip_id": "overhead",
                "coordinate_space": "godot_camera_local_x_right_y_up_minus_z_forward",
                "geometry_space": "canonical_source_ready_inverse",
                "seconds_basis": "original_authored_clip_seconds"}
    failures = []
    for key, value in required.items():
        if data.get(key) != value:
            failures.append({"check": "metadata", "field": key, "expected": value, "actual": data.get(key)})
    frames = data.get("frames")
    if not isinstance(frames, list) or len(frames) < 2:
        raise ValueError("frames must contain at least two actual evaluated samples")
    points = constants["canonical_points"]
    w0, e0, h0, g0 = [points[k] for k in ("W0", "E0", "H0", "G")]
    f_len, u_len = distance(w0, e0), distance(e0, h0)
    sr = constants["SOURCE_READY_rows"]
    source_ready = ([r[:3] for r in sr[:3]], [r[3] for r in sr[:3]])
    rest_shoulder = transform(source_ready, h0)
    endpoint_tol = constants["thresholds"]["max_joint_endpoint_error_m"]
    grip_tol = constants["thresholds"]["max_grip_error_m"]
    length_tol = constants["thresholds"]["max_length_relative_deviation"]
    # Numeric tolerances for floating-point basis/quaternion storage are audit
    # tolerances, not new artistic allowances in the receiving contract.
    basis_tol, quaternion_tol = 3e-5, 1e-5
    records, times, missing_grip = [], [], []

    def check(name, value, limit, i):
        if value > limit:
            failures.append({"frame_index": i, "time_seconds": times[-1], "check": name,
                             "measured": value, "maximum": limit})

    for i, frame in enumerate(frames):
        t = number(frame["time_seconds"], "time_seconds")
        times.append(t)
        sword, sword_qerror = pose(frame["sword"], "sword")
        _, shield_qerror = pose(frame["shield"], "shield")
        arm = frame["right_arm"]
        h, e, w = [vector(arm[k], 3, "right_arm."+k) for k in ("shoulder", "elbow", "wrist")]
        actual = {k: part(arm["parts_camera"][k], k) for k in ("forearm", "upper_arm", "cuff")}
        inv = inverse_rigid(sword)
        local_h, local_e = transform(inv, h), transform(inv, e)
        expected_f = fit_segment(w0, e0, w0, local_e)
        expected_u = fit_segment(e0, h0, local_e, local_h)
        expected_q = gram_schmidt_columns(expected_f[0])
        expected_c = expected_q, sub(w0, matvec(expected_q, w0))
        expected = {"forearm": compose(sword, expected_f), "upper_arm": compose(sword, expected_u),
                    "cuff": compose(sword, expected_c)}
        endpoint = {
            "wrist_from_sword": distance(transform(sword, w0), w),
            "forearm_wrist": distance(transform(actual["forearm"], w0), w),
            "forearm_elbow": distance(transform(actual["forearm"], e0), e),
            "upper_arm_elbow": distance(transform(actual["upper_arm"], e0), e),
            "upper_arm_shoulder": distance(transform(actual["upper_arm"], h0), h),
            "elbow_seam": distance(transform(actual["forearm"], e0), transform(actual["upper_arm"], e0)),
            "cuff_wrist": distance(transform(actual["cuff"], w0), w)
        }
        fr, ur = distance(w, e)/f_len, distance(e, h)/u_len
        cuff_cols = transpose(actual["cuff"][0])
        cuff_scale_error = max(abs(length(c)-1) for c in cuff_cols)
        cuff_orthogonal_error = max(abs(dot(cuff_cols[j], cuff_cols[k])) for j,k in ((0,1),(0,2),(1,2)))
        cuff_det_error = abs(determinant(actual["cuff"][0])-1)
        matrix_errors = {k: {"basis_max_abs": matrix_error(actual[k][0], expected[k][0]),
                             "position_m": distance(actual[k][1], expected[k][1])} for k in actual}
        for k, value in endpoint.items():
            check(k, value, endpoint_tol, i)
        check("forearm_length_relative_deviation", abs(fr-1), length_tol, i)
        check("upper_arm_length_relative_deviation", abs(ur-1), length_tol, i)
        check("sword_quaternion_norm_error", sword_qerror, quaternion_tol, i)
        check("shield_quaternion_norm_error", shield_qerror, quaternion_tol, i)
        check("cuff_scale_error", cuff_scale_error, basis_tol, i)
        check("cuff_orthogonality_error", cuff_orthogonal_error, basis_tol, i)
        check("cuff_determinant_error", cuff_det_error, basis_tol, i)
        for k, v in matrix_errors.items():
            check(k+"_shortest_rotation_basis_error", v["basis_max_abs"], basis_tol, i)
            check(k+"_fit_position_error_m", v["position_m"], endpoint_tol, i)
        grip = frame.get("evaluated_grip_camera")
        grip_errors = None
        if grip is None:
            missing_grip.append(i)
        else:
            sg, gg = vector(grip["sword"],3,"evaluated_grip_camera.sword"), vector(grip["glove"],3,"evaluated_grip_camera.glove")
            target = transform(sword, g0)
            grip_errors = {"sword_to_TG_m": distance(sg,target), "glove_to_TG_m": distance(gg,target),
                           "sword_to_glove_m": distance(sg,gg)}
            for k,v in grip_errors.items():
                check(k, v, grip_tol, i)
        records.append({"frame_index": i, "time_seconds": t,
                        "forearm_length_m": distance(w,e), "upper_arm_length_m": distance(e,h),
                        "forearm_length_ratio": fr, "upper_arm_length_ratio": ur,
                        "shoulder_displacement_from_source_ready_m": distance(h,rest_shoulder),
                        "endpoints_error_m": endpoint, "grip_errors": grip_errors,
                        "cuff_scale_error": cuff_scale_error, "cuff_orthogonality_error": cuff_orthogonal_error,
                        "cuff_determinant_error": cuff_det_error, "fit_segment_comparison": matrix_errors,
                        "sword_quaternion_norm_error": sword_qerror, "shield_quaternion_norm_error": shield_qerror})
    deltas = [b-a for a,b in zip(times,times[1:])]
    if any(d <= 0 for d in deltas):
        failures.append({"check": "strictly_increasing_sample_times", "minimum_delta_seconds": min(deltas)})
    max_step = 1/constants["clip"]["minimum_sample_rate_hz"]
    if max(deltas) > max_step+1e-8:
        failures.append({"check": "minimum_60hz_sampling", "max_delta_seconds": max(deltas), "maximum": max_step})
    if abs(times[0]) > 1e-8 or abs(times[-1]-constants["clip"]["duration_seconds"]) > 1e-8:
        failures.append({"check": "original_1_55s_clip_extent", "first_seconds": times[0], "last_seconds": times[-1]})
    endpoint_max = max(v for r in records for v in r["endpoints_error_m"].values())
    grip_values = [v for r in records if r["grip_errors"] is not None for v in r["grip_errors"].values()]
    result = {"schema_version": 1, "status": "FAIL" if failures else ("INCOMPLETE" if missing_grip else "PASS"),
              "numerical_checks_pass": not failures,
              "scope": "Independent numerical audit of supplied sidecar values; no Blender process run by this verifier",
              "sample_count": len(frames),
              "sampling": {"first_seconds": times[0], "last_seconds": times[-1], "max_interval_seconds": max(deltas),
                           "minimum_local_sample_rate_hz": 1/max(deltas) if max(deltas)>0 else None,
                           "nominal_average_hz": (len(frames)-1)/(times[-1]-times[0]) if times[-1]>times[0] else None},
              "reference_lengths_m": {"forearm": f_len, "upper_arm": u_len},
              "maxima": {"endpoint_error_m": endpoint_max,
                         "forearm_length_relative_deviation": max(abs(r["forearm_length_ratio"]-1) for r in records),
                         "upper_arm_length_relative_deviation": max(abs(r["upper_arm_length_ratio"]-1) for r in records),
                         "shoulder_displacement_from_source_ready_m": max(r["shoulder_displacement_from_source_ready_m"] for r in records),
                         "grip_error_m": max(grip_values) if grip_values else None,
                         "cuff_scale_error": max(r["cuff_scale_error"] for r in records),
                         "fit_segment_basis_error": max(v["basis_max_abs"] for r in records for v in r["fit_segment_comparison"].values())},
              "grip_evidence": {"status": "NOT_MEASURABLE" if len(missing_grip)==len(frames) else ("PARTIAL" if missing_grip else "PRESENT_ALL_FRAMES"),
                                "missing_frame_indices": missing_grip,
                                "limit": "Same-landmark transform evidence does not alone prove unchanged mesh vertices or texture."},
              "shoulder_review": "Maximum is reported; contract sets no numeric threshold. Small body-attached movement requires visual review.",
              "not_verified": ["Actual Blender execution provenance and dependency graph extraction", "Source file hashes and geometry preservation",
                               "Source-ready mesh overlap", "GLB animation reimport", "Surface closure and cuff open rim exposure",
                               "1st-person / side-view silhouettes and source-video likeness", "Any skin deformation not representable by part matrices"],
              "thresholds": {"joint_endpoint_error_m": endpoint_tol, "grip_error_m": grip_tol,
                             "length_relative_deviation": length_tol, "basis_numeric_abs_error": basis_tol,
                             "quaternion_norm_numeric_error": quaternion_tol},
              "failures": failures, "frames": records}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("samples", type=Path)
    parser.add_argument("--constants", type=Path, default=Path(__file__).resolve().parents[1]/"contracts"/"constants.json")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        data = json.loads(args.samples.read_text(encoding="utf-8-sig"))
        constants = json.loads(args.constants.read_text(encoding="utf-8-sig"))
        report = audit(data, constants)
        report["inputs"] = {"samples": str(args.samples.resolve()), "samples_sha256": sha256(args.samples),
                            "constants": str(args.constants.resolve()), "constants_sha256": sha256(args.constants),
                            "verifier_sha256": sha256(Path(__file__))}
    except (OSError, ValueError, KeyError, TypeError, IndexError, ZeroDivisionError) as exc:
        report = {"schema_version": 1, "status": "FAIL", "error": type(exc).__name__+": "+str(exc),
                  "scope": "Input parsing / numeric audit; no samples synthesized"}
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)+"\n", encoding="utf-8")
    summary = {k:v for k,v in report.items() if k not in ("frames", "failures")}
    if "failures" in report:
        summary["failure_count"] = len(report["failures"])
        summary["first_failures"] = report["failures"][:8]
    print(json.dumps(summary, ensure_ascii=False, indent=2, allow_nan=False))
    return 0 if report["status"]=="PASS" else (2 if report["status"]=="INCOMPLETE" else 1)


if __name__ == "__main__":
    sys.exit(main())
