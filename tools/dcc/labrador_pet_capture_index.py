"""Measure original Labrador captures and rank source segments for retargeting.

This read-only analysis uses the dataset's absolute XYZ-position convention,
verified separately against Blender's bundled BVH importer. Coordinates here
remain source centimetres, Y up. Candidate ranges are zero-based raw frames;
they require visual review after mapping to the downloaded Labrador skin.
"""
import argparse
import json
from pathlib import Path

import numpy as np

from labrador_pet_bvh import read_bvh


BODY_JOINTS = (
    "b_Hips", "b_Spine", "b_Spine3", "b__Neck", "b_Head",
    "b_LeftArm", "b_LeftForeArm", "b_LeftHand", "b__LeftFinger",
    "b_RightArm", "b_RightForeArm", "b_RightHand", "b_RightFinger",
    "b_LeftLegUpper", "b_LeftLeg", "b_LeftLeg1", "b_LeftAnkle", "b_LeftToe",
    "b_RightLegUpper", "b_RightLeg", "b_RightLeg1", "b_RightAnkle", "b_RightToe",
)
PAWS = ("b__LeftFinger", "b_RightFinger", "b_LeftToe", "b_RightToe")


def evaluate_arrays(capture, step=1):
    """Vectorized source FK; do not silently add position channels to OFFSET."""
    rows = np.asarray(capture.frames, dtype=np.float64)[::step]
    n = len(rows); rotations = []; positions = []
    for joint in capture.joints:
        rotation = np.broadcast_to(np.eye(3), (n, 3, 3)).copy()
        translation = np.broadcast_to(np.asarray(joint.offset), (n, 3)).copy()
        for ci, channel in enumerate(joint.channels):
            values = rows[:, joint.channel_start + ci]
            axis = "XYZ".index(channel[0].upper())
            if channel.endswith("position"):
                translation[:, axis] = values
            elif channel.endswith("rotation"):
                a = np.radians(values); cosine = np.cos(a); sine = np.sin(a)
                elementary = np.broadcast_to(np.eye(3), (n, 3, 3)).copy()
                b = (axis + 1) % 3; d = (axis + 2) % 3
                elementary[:, b, b] = elementary[:, d, d] = cosine
                elementary[:, b, d] = -sine; elementary[:, d, b] = sine
                rotation = rotation @ elementary
            else:
                raise ValueError("Unexpected BVH channel " + channel)
        if joint.parent is not None:
            parent_rotation = rotations[joint.parent]
            translation = positions[joint.parent] + np.einsum("nij,nj->ni", parent_rotation, translation)
            rotation = parent_rotation @ rotation
        rotations.append(rotation); positions.append(translation)
    return {joint.name: positions[i] for i, joint in enumerate(capture.joints)}, {
        joint.name: rotations[i] for i, joint in enumerate(capture.joints)}


def consecutive_ranges(mask):
    edges = np.diff(np.r_[False, mask, False].astype(np.int8))
    return list(zip(np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)))


def body_features(positions):
    root = positions["b_Hips"]
    forward = positions["b_Spine3"] - root
    forward[:, 1] = 0
    forward /= np.maximum(1e-9, np.linalg.norm(forward, axis=1))[:, None]
    up = np.broadcast_to(np.array([0, 1, 0]), forward.shape)
    side = np.cross(up, forward)
    basis = np.stack((side, up, forward), axis=1)
    return np.concatenate([np.einsum("nij,nj->ni", basis, positions[name]-root)
                           for name in BODY_JOINTS], axis=1)


def loop_candidates(capture, positions, step):
    feature = body_features(positions)
    sample_fps = capture.fps / step
    min_seconds, max_seconds = (.25, .75) if "run" in capture.path.name else (.4, 1.25)
    lo = max(2, int(sample_fps * min_seconds)); hi = min(len(feature)-2, int(sample_fps * max_seconds))
    if hi < lo:
        return []
    root = positions["b_Hips"]
    speed = np.linalg.norm(np.gradient(root[:, (0, 2)], axis=0)*sample_fps, axis=1)
    cumulative_speed = np.r_[0, np.cumsum(speed)]
    forward = positions["b_Spine3"] - root
    heading = np.unwrap(np.arctan2(forward[:, 0], forward[:, 2]))
    candidates = []
    for lag in range(lo, hi+1):
        difference = feature[lag:] - feature[:-lag]
        rms = np.sqrt(np.mean(difference*difference, axis=1))
        velocity = np.gradient(feature, axis=0)*sample_fps
        v_rms = np.sqrt(np.mean((velocity[lag:]-velocity[:-lag])**2, axis=1))
        score = rms + .012*v_rms
        mean_speeds = (cumulative_speed[lag+1:] - cumulative_speed[:-(lag+1)])/(lag+1)
        heading_difference = np.abs(heading[lag:] - heading[:-lag])
        score[(mean_speeds < 30) | (heading_difference > np.radians(8))] = np.inf
        for index in np.argsort(score)[:6]:
            if not np.isfinite(score[index]):
                continue
            if index < 3 or index+lag >= len(feature)-3:
                continue
            mean_speed = float(mean_speeds[index])
            candidates.append({
                "start_frame": int(index*step), "end_frame": int((index+lag)*step),
                "duration_seconds": float(lag/sample_fps),
                "pose_rms_cm": float(rms[index]), "velocity_rms_cm_s": float(v_rms[index]),
                "root_speed_cm_s": mean_speed, "score": float(score[index]),
                "heading_difference_degrees": float(np.degrees(heading_difference[index])),
            })
    ranked = []
    for candidate in sorted(candidates, key=lambda item: item["score"]):
        if any(abs(candidate["start_frame"]-old["start_frame"]) < sample_fps*.12*step
               and abs(candidate["duration_seconds"]-old["duration_seconds"]) < .1 for old in ranked):
            continue
        ranked.append(candidate)
        if len(ranked) == 5:
            break
    return ranked


def analyze_file(path, step=4):
    capture = read_bvh(path)
    positions, rotations = evaluate_arrays(capture, step)
    fps = capture.fps/step; root = positions["b_Hips"]
    speed = np.linalg.norm(np.gradient(root[:, (0, 2)], axis=0)*fps, axis=1)
    head = positions["b_Head"]
    report = {
        "file": path.name, "frames": len(capture.frames), "fps": capture.fps,
        "duration_seconds": capture.duration, "joints": len(capture.joints),
        "animated_joints": sum(not j.end_site for j in capture.joints),
        "channels": capture.channel_count,
        "root_height_cm": {"min": float(root[:, 1].min()), "median": float(np.median(root[:, 1])), "max": float(root[:, 1].max())},
        "head_height_cm": {"min": float(head[:, 1].min()), "median": float(np.median(head[:, 1])), "max": float(head[:, 1].max())},
        "root_planar_speed_cm_s": {"median": float(np.median(speed)), "max": float(speed.max())},
        "paw_height_cm": {name: {"min": float(positions[name][:, 1].min()), "median": float(np.median(positions[name][:, 1]))} for name in PAWS},
        "ranges": {},
    }
    masks = {
        "low_hips_candidate": root[:, 1] < 35,
        "low_head_candidate": head[:, 1] < 25,
        "quiet_standing_candidate": (speed < 12) & (root[:, 1] > 45) & (root[:, 1] < 70),
    }
    for key, mask in masks.items():
        report["ranges"][key] = [
            {"start_frame": int(a*step), "end_frame": int(min(len(capture.frames)-1, (b-1)*step)),
             "duration_seconds": float((b-a-1)/fps)}
            for a, b in consecutive_ranges(mask) if (b-a-1)/fps >= .45
        ]
    if any(word in path.name for word in ("walk", "run")):
        report["loop_candidates"] = loop_candidates(capture, positions, step)
    return report, [(j.name, None if j.parent is None else capture.joints[j.parent].name) for j in capture.joints]


def main():
    parser = argparse.ArgumentParser(); parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True); parser.add_argument("--step", type=int, default=4)
    args = parser.parse_args()
    reports = []; skeletons = set()
    for path in sorted(args.source.glob("*.bvh")):
        report, hierarchy = analyze_file(path, args.step)
        reports.append(report); skeletons.add(tuple(hierarchy))
        print("ANALYZED", path.name, report["frames"], flush=True)
    result = {
        "coordinate_space": "Original source centimetres, Y up; position channels replace hierarchy OFFSET on their axes.",
        "source_fps": sorted(set(round(item["fps"], 4) for item in reports)),
        "files": len(reports), "unique_joint_hierarchies": len(skeletons),
        "joint_names": sorted(set.intersection(*[{name for name, parent in skeleton} for skeleton in skeletons])) if skeletons else [],
        "hierarchy_variants": [{"joints": len(skeleton), "names": [name for name, parent in skeleton]} for skeleton in sorted(skeletons, key=len)],
        "analysis_sample_step": args.step,
        "scope": "Source-capture analysis only. Labels indicate numerical candidates, not verified dog actions or finished model retargeting.",
        "captures": reports,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n")
    print("CAPTURE_ANALYSIS_COMPLETE", len(reports), flush=True)


if __name__ == "__main__":
    main()
