"""Report projected landmarks of actual delivered poses against observed video frames.

No poses are generated or adjusted. Numbers guide visual review; they are not a
similarity acceptance test and cannot detect surface occlusion or hollow sleeves.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path


POINTS = {"wrist_center": (0.0679751875, -0.1080001335, 0.0524637313),
          "guard_center": (0.0, -0.009, 0.0), "sword_tip": (0.0, 1.035, 0.0)}


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def point_camera(sample, point):
    q = sample["rotation_xyzw"]
    if len(q) != 4 or abs(sum(x*x for x in q) - 1) > 0.0002:
        raise ValueError("Invalid delivered quaternion")
    a = cross(q[:3], point)
    b = cross(q[:3], a)
    return [point[i] + 2*(q[3]*a[i]+b[i]) + sample["position"][i] for i in range(3)]


def project(point, fov):
    depth = -point[2]
    if depth <= 0.025:
        return None
    half_height = depth * math.tan(math.radians(fov) / 2)
    return [0.5 + point[0]/(2*half_height*16/9), 0.5 - point[1]/(2*half_height)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--review", type=Path, required=True)
    parser.add_argument("--observations", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Use a new report path; existing reviews are preserved")
    raw = args.review.read_bytes()
    review = json.loads(raw)
    observations = json.loads(args.observations.read_text())
    if review.get("status") != "authored_windows_review_output":
        raise ValueError("Requires an actual Windows overhead review delivery")
    samples = review["clips"]["overhead"]["tracks"]["sword"]
    fov = review["camera"]["vertical_fov_degrees"]
    rows = []
    for target in observations["frames"]:
        local_time = target["time_seconds"] - 1040/60
        sample = min(samples, key=lambda x: abs(x["time_seconds"]-local_time))
        if abs(sample["time_seconds"]-local_time) > 1/120 + 0.0001:
            raise ValueError("Required source frame has no nearby delivered sample")
        row = {"reference_time_seconds": target["time_seconds"],
               "actual_delivered_time_seconds": sample["time_seconds"], "landmarks": {}}
        for name, point in POINTS.items():
            expected = target[name]["normalized"]
            predicted = project(point_camera(sample, point), fov)
            difference = None if expected is None or predicted is None else [predicted[i]-expected[i] for i in range(2)]
            pixel_distance = None if difference is None else math.hypot(difference[0]*1280, difference[1]*720)
            row["landmarks"][name] = {"reference_normalized": expected,
                "reference_visibility": target[name]["visibility"],
                "predicted_normalized_without_surface_occlusion": predicted,
                "distance_in_reference_pixels": pixel_distance}
        row["required_arm_entry"] = target["arm_entry_observation"]
        rows.append(row)
    result = {"status": "projection_measurement_only", "similarity_pass_claimed": False,
              "source_review_sha256": hashlib.sha256(raw).hexdigest(),
              "canonical_landmarks": POINTS, "frames": rows,
              "limits": ["Reference coordinates are manual 2D observations, not recovered 3D joints.",
                         "Crossguard center is a mesh-derived estimate; wrist is a segment endpoint.",
                         "Projection does not test visible mesh occlusion, anatomy or screen-edge attachment."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
    print(json.dumps({"report": str(args.output.resolve()), "reference_frames": len(rows)}))


if __name__ == "__main__":
    main()
