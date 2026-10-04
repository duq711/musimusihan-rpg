"""Read-only Blender/FBX numeric QA for the Shepherd pet animation package.

Blender --background --disable-autoexec --python shepherd_pet_validate.py --
    --base asset-staging/shepherd-pet-20261005

Only the JSON report is written. Evaluated mesh tests cover integer frames;
they are not a substitute for silhouette/contact visual review or Unity import.
"""
import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path

import bpy
from mathutils import Vector

EXPECTED_CLIPS = (
    "IdleFriendly", "Walk", "Run", "CombatBite", "SearchSniff", "SearchWalk",
    "SearchFound", "RetrievePickup", "RetrieveCarryWalk", "RetrieveDrop",
    "EatStart", "EatLoop", "EatEnd", "PetSit", "PetEnjoy", "PetRise",
)
LOCOMOTION = {"Walk", "Run", "SearchWalk", "RetrieveCarryWalk"}
TOES = ("DEF-front_toe.L", "DEF-front_toe.R", "DEF-toe.L", "DEF-toe.R")
POSE_M = .001
ANGLE_RAD = math.radians(1)
VELOCITY_M_S = .05
VELOCITY_RAD_S = math.radians(30)
GROUND_M = -.002


def digest(path):
    sha = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def set_action(rig, action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action.slots:
        rig.animation_data.action_slot = action.slots[0]
    bpy.context.view_layer.update()


def frame_pose(rig, frame):
    bpy.context.scene.frame_set(int(frame), subframe=frame - int(frame))
    bpy.context.view_layer.update()
    return {bone.name: rig.matrix_world @ bone.matrix for bone in rig.pose.bones}


def angle(a, b):
    q = a.to_quaternion().rotation_difference(b.to_quaternion())
    return min(q.angle, 2 * math.pi - q.angle)


def angular_velocity(a, b, fps):
    q = a.to_quaternion().rotation_difference(b.to_quaternion())
    q.normalize()
    # atan2 retains precision for the tiny quaternion vectors measured at
    # subframes; acos(w) can round their angles to zero in float32 matrices.
    if q.w < 0:
        q.negate()
    vector = Vector((q.x, q.y, q.z))
    if vector.length < 1e-12:
        return Vector((0, 0, 0))
    value = 2 * math.atan2(vector.length, q.w)
    return vector * (value * fps / vector.length)


def compare_poses(a, b):
    common = sorted(set(a) & set(b))
    if not common:
        return {"pass": False, "common_bones": 0, "missing_bones": sorted(set(a) | set(b))}
    distances = {name: (a[name].translation - b[name].translation).length for name in common}
    angles = {name: angle(a[name], b[name]) for name in common}
    scales = {name: (a[name].to_scale() - b[name].to_scale()).length for name in common}
    dname, aname = max(distances, key=distances.get), max(angles, key=angles.get)
    missing = sorted(set(a) ^ set(b))
    return {
        "pass": not missing and distances[dname] <= POSE_M and angles[aname] <= ANGLE_RAD,
        "common_bones": len(common), "missing_bones": missing,
        "max_position_m": distances[dname], "position_bone": dname,
        "max_rotation_degrees": math.degrees(angles[aname]), "rotation_bone": aname,
        "max_world_scale_difference": max(scales.values()),
    }


def loop_velocity(poses, start, end, fps):
    first, next_pose, previous, last = poses[start], poses[start + 1], poses[end - 1], poses[end]
    position, rotation = {}, {}
    for name in first:
        incoming = (last[name].translation - previous[name].translation) * fps
        outgoing = (next_pose[name].translation - first[name].translation) * fps
        position[name] = (incoming - outgoing).length
        rotation[name] = (angular_velocity(previous[name], last[name], fps) - angular_velocity(first[name], next_pose[name], fps)).length
    pbone, rbone = max(position, key=position.get), max(rotation, key=rotation.get)
    return {
        "pass": position[pbone] <= VELOCITY_M_S and rotation[rbone] <= VELOCITY_RAD_S,
        "max_position_velocity_difference_m_s": position[pbone], "position_bone": pbone,
        "max_angular_velocity_difference_degrees_s": math.degrees(rotation[rbone]), "rotation_bone": rbone,
        "method": "one-frame finite differences across the integer-frame seam; sampled linear curves",
    }


def loop_tangent(rig, start, end, fps, step_frames=.01):
    """Measure the actual subframe endpoint derivative of the evaluated rig.

    A full-frame chord over an articulated arc can differ substantially on
    either side of a continuous tangent. This uses 1/100 frame and keeps the
    full-frame chord result separately as playback diagnostics.
    """
    first = frame_pose(rig, start)
    near_first = frame_pose(rig, start + step_frames)
    near_last = frame_pose(rig, end - step_frames)
    last = frame_pose(rig, end)
    inverse_seconds = fps / step_frames
    position, rotation = {}, {}
    for name in first:
        incoming = (last[name].translation - near_last[name].translation) * inverse_seconds
        outgoing = (near_first[name].translation - first[name].translation) * inverse_seconds
        position[name] = (incoming - outgoing).length
        rotation[name] = (angular_velocity(near_last[name], last[name], inverse_seconds)
                          - angular_velocity(first[name], near_first[name], inverse_seconds)).length
    pbone, rbone = max(position, key=position.get), max(rotation, key=rotation.get)
    return {
        "pass": position[pbone] <= VELOCITY_M_S and rotation[rbone] <= VELOCITY_RAD_S,
        "step_frames": step_frames, "step_seconds": step_frames / fps,
        "max_position_velocity_difference_m_s": position[pbone], "position_bone": pbone,
        "max_angular_velocity_difference_degrees_s": math.degrees(rotation[rbone]), "rotation_bone": rbone,
        "method": "Evaluated world pose at start, start+0.01 frame, end-0.01 frame and end; small-angle quaternion logarithms. Full-frame chords are recorded separately.",
        "limitation": "One-sided numerical derivative at finite dt; float32 transform precision and residual arc curvature remain. A tangent pass does not establish visually acceptable acceleration or anatomical motion.",
    }


def key_channels(action, bone_names):
    curves = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                curves.extend(bag.fcurves)
    expected = {
        (f'pose.bones["{name}"].{prop}', index)
        for name in bone_names
        for prop, count in (("location", 3), ("rotation_quaternion", 4), ("scale", 3))
        for index in range(count)
    }
    actual = {(curve.data_path, curve.array_index) for curve in curves}
    bad_keys = []
    key_count = 0
    for curve in curves:
        for key in curve.keyframe_points:
            key_count += 1
            if not all(math.isfinite(value) for value in key.co):
                bad_keys.append([curve.data_path, curve.array_index])
    return {
        "curve_count": len(curves), "expected_bone_channels": len(expected), "key_count": key_count,
        "missing_channels": sorted([list(value) for value in expected - actual]),
        "nonfinite_keys": bad_keys,
        "pass": not (expected - actual) and not bad_keys,
    }


def mesh_clearance(mesh, frame):
    bpy.context.scene.frame_set(frame)
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    data = evaluated.to_mesh()
    try:
        lowest = min(data.vertices, key=lambda v: (evaluated.matrix_world @ v.co).z)
        z = (evaluated.matrix_world @ lowest.co).z
        group_weights = []
        if lowest.index < len(mesh.data.vertices):
            group_weights = sorted(
                [(mesh.vertex_groups[group.group].name, group.weight) for group in mesh.data.vertices[lowest.index].groups],
                key=lambda pair: pair[1], reverse=True,
            )[:3]
        return {"frame": frame, "min_vertex_z_m": z, "vertex_index": lowest.index, "dominant_vertex_groups": group_weights}
    finally:
        evaluated.to_mesh_clear()


def toe_contacts(poses, start, clip):
    names = TOES[:2] if clip in {"PetSit", "PetRise"} else TOES
    errors = {}
    for name in names:
        reference = poses[start][name]
        distances = {frame: (pose[name].translation - reference.translation).length for frame, pose in poses.items()}
        rotations = {frame: angle(pose[name], reference) for frame, pose in poses.items()}
        worst = max(distances, key=distances.get)
        errors[name] = {
            "max_position_m": distances[worst], "worst_frame": worst,
            "max_rotation_degrees": math.degrees(max(rotations.values())),
        }
    hind_height = {
        name: max(abs(pose[name].translation.z - poses[start][name].translation.z) for pose in poses.values())
        for name in TOES[2:]
    }
    return {
        "pass": all(row["max_position_m"] <= POSE_M and row["max_rotation_degrees"] <= 1 for row in errors.values())
            and all(value <= POSE_M for value in hind_height.values()),
        "stationary_toes": errors, "hind_max_vertical_drift_m": hind_height,
        "note": "Sitting/rising hind feet intentionally reposition horizontally; forefeet and hind height are checked independently. Toe joint locations are contact proxies, not skin contact surfaces.",
    }


def regression(samples):
    xs, ys = zip(*samples)
    mean_x, mean_y = statistics.mean(xs), statistics.mean(ys)
    denominator = sum((x - mean_x) ** 2 for x in xs)
    if denominator <= 1e-15:
        return None
    slope = sum((x - mean_x) * (y - mean_y) for x, y in samples) / denominator
    residual = math.sqrt(statistics.mean((y - (mean_y + slope * (x - mean_x))) ** 2 for x, y in samples))
    return slope, residual


def locomotion_speed(poses, fps):
    windows = []
    frames = sorted(poses)
    for name in TOES:
        height = min(poses[frame][name].translation.z for frame in frames)
        run = []
        for frame in frames:
            point = poses[frame][name].translation
            if point.z <= height + .012:
                run.append((frame / fps, point.y))
            else:
                if len(run) >= 3:
                    fit = regression(run)
                    if fit and fit[0] > .02:
                        windows.append({"toe": name, "start_frame": round(run[0][0] * fps), "end_frame": round(run[-1][0] * fps), "speed_m_s": fit[0], "fit_residual_m": fit[1]})
                run = []
        if len(run) >= 3:
            fit = regression(run)
            if fit and fit[0] > .02:
                windows.append({"toe": name, "start_frame": round(run[0][0] * fps), "end_frame": round(run[-1][0] * fps), "speed_m_s": fit[0], "fit_residual_m": fit[1]})
    speeds = [window["speed_m_s"] for window in windows]
    return {
        "estimated_intended_speed_m_s": statistics.median(speeds) if speeds else None,
        "speed_window_min_m_s": min(speeds) if speeds else None,
        "speed_window_max_m_s": max(speeds) if speeds else None,
        "stance_windows": windows,
        "method": "Median positive armature-world toe Y slope over >=3 consecutive low toe frames (minimum per-toe height +12 mm). Dog forward is -Y, so a positive stance slope suggests forward controller speed.",
        "limitation": "Approximate stride estimate from toe-joint proxies; requires floor contact and controller-translated visual playback to establish foot sliding. Low toe height alone does not prove stance. Not a validated gameplay speed.",
    }


def validate(base, output):
    blend = base / "production/ShepherdPet_Animations.blend"
    before = digest(blend)
    manifest = json.loads((base / "export/animation-manifest.json").read_text())
    expected = {clip["name"]: clip for clip in manifest["clips"]}
    bpy.ops.wm.open_mainfile(filepath=str(blend))
    scene = bpy.context.scene
    rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    mesh = next(obj for obj in scene.objects if obj.type == "MESH")
    fps = scene.render.fps / scene.render.fps_base
    original_actions = {name: bpy.data.actions.get(name) for name in EXPECTED_CLIPS}
    report = {
        "schema": 1, "blender": bpy.app.version_string, "fps": fps,
        "production_blend": str(blend), "production_sha256_before": before,
        "manifest_names_match": set(expected) == set(EXPECTED_CLIPS),
        "expected_clip_count": 16, "authored_clip_count": sum(action is not None for action in original_actions.values()),
        "armature_world_scale": list(rig.matrix_world.to_scale()),
        "thresholds": {"pose_position_m": POSE_M, "pose_rotation_degrees": 1, "loop_velocity_m_s": VELOCITY_M_S, "loop_velocity_degrees_s": 30, "mesh_min_z_m": GROUND_M},
        "clips": {}, "boundaries": {}, "fbx_roundtrip": {}, "errors": [], "warnings": [],
        "limitations": [
            "This is Blender evaluated pose/mesh and FBX reimport QA; Unity Generic importer/playback is a separate check.",
            "Mesh clearance covers every integer frame; interframe interpolation can still contain penetration.",
            "Toe joints proxy foot contacts; toes staying fixed does not prove skin contact, balance or anatomical quality.",
            "Loop endpoint tangents use 0.01-frame one-sided quaternion-log/position differences; one-frame chord velocities are retained as separate diagnostics. Neither is an analytical fcurve derivative.",
            "The test does not implement item attachment, feeding, player hands, damage or pet AI.",
        ],
    }
    poses_by_clip = {}
    for name, action in original_actions.items():
        if action is None:
            report["errors"].append("Missing action: " + name)
            continue
        set_action(rig, action)
        start, end = (int(round(value)) for value in action.frame_range)
        poses = {frame: frame_pose(rig, frame) for frame in range(start, end + 1)}
        poses_by_clip[name] = poses
        nonfinite = [[frame, bone] for frame, pose in poses.items() for bone, matrix in pose.items() if not all(math.isfinite(value) for row in matrix for value in row)]
        channels = key_channels(action, rig.pose.bones.keys())
        spec = expected.get(name, {})
        duration = (end - start) / fps
        slot = rig.animation_data.action_slot
        slot_ok = slot is not None and any(candidate == slot for candidate in action.slots)
        samples = list(range(start, end + 1))
        clearances = [mesh_clearance(mesh, frame) for frame in samples]
        minimum = min(clearances, key=lambda row: row["min_vertex_z_m"])
        row = {
            "frames": [start, end], "frame_count": len(poses), "duration_seconds": duration,
            "length_matches_manifest": [start, end] == spec.get("frames") and abs(duration - spec.get("duration", -1)) < 1e-6,
            "slot": slot.identifier if slot else None, "slot_assignment_valid": slot_ok,
            "action_slot_count": len(action.slots), "channels": channels,
            "nonfinite_bone_transforms": nonfinite,
            "root_world_translation_range_m": max((pose["DEF-spine.004"].translation - poses[start]["DEF-spine.004"].translation).length for pose in poses.values()),
            "mesh_clearance": {"pass": minimum["min_vertex_z_m"] >= GROUND_M, "minimum": minimum, "samples": clearances},
        }
        if spec.get("loop"):
            row["loop_pose"] = compare_poses(poses[start], poses[end])
            row["loop_velocity_one_frame_diagnostic"] = loop_velocity(poses, start, end, fps)
            row["loop_velocity"] = loop_tangent(rig, start, end, fps)
            if not row["loop_pose"]["pass"]:
                report["errors"].append(name + ": loop pose seam exceeds tolerance")
            if not row["loop_velocity"]["pass"]:
                report["errors"].append(name + ": evaluated endpoint tangent exceeds unchanged velocity threshold")
        if name in LOCOMOTION:
            row["locomotion_estimate"] = locomotion_speed(poses, fps)
        else:
            row["toe_contacts"] = toe_contacts(poses, start, name)
            if not row["toe_contacts"]["pass"]:
                report["errors"].append(name + ": stationary toe contact exceeds tolerance")
        if not row["mesh_clearance"]["pass"]:
            report["errors"].append(name + ": sampled mesh below floor tolerance")
        if not (row["length_matches_manifest"] and slot_ok and channels["pass"] and not nonfinite):
            report["errors"].append(name + ": frame/channel/slot/finite check failed")
        report["clips"][name] = row
        print("VALIDATED", name, "min_z_m", round(minimum["min_vertex_z_m"], 6), flush=True)
    for left, right in (("EatStart", "EatLoop"), ("EatLoop", "EatEnd"), ("PetSit", "PetEnjoy"), ("PetEnjoy", "PetRise")):
        if left in poses_by_clip and right in poses_by_clip:
            a, b = poses_by_clip[left], poses_by_clip[right]
            comparison = compare_poses(a[max(a)], b[min(b)])
            report["boundaries"][left + " -> " + right] = comparison
            if not comparison["pass"]:
                report["errors"].append(left + " -> " + right + ": pose continuity exceeds tolerance")
    for name in EXPECTED_CLIPS:
        path = base / "export/Animations" / (name + ".fbx")
        if not path.exists():
            report["errors"].append("Missing FBX: " + name)
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = int(manifest["fps"])
        # Blender's importer defaults to a +1-frame animation offset. Exported
        # frame 1 then becomes frame 2 unless the offset is explicitly zero.
        bpy.ops.import_scene.fbx(filepath=str(path), use_anim=True, anim_offset=0)
        armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
        if len(armatures) != 1 or not armatures[0].animation_data or not armatures[0].animation_data.action:
            report["fbx_roundtrip"][name] = {"pass": False, "armature_count": len(armatures)}
            report["errors"].append(name + ": FBX armature/action missing")
            continue
        imported = armatures[0]
        action = imported.animation_data.action
        set_action(imported, action)
        frames = list(action.frame_range)
        source = poses_by_clip[name]
        chosen = sorted({min(source), round((min(source) + max(source)) / 2), max(source)})
        comparisons = {str(frame): compare_poses(source[frame], frame_pose(imported, frame)) for frame in chosen}
        imported_slot = imported.animation_data.action_slot
        roundtrip = {
            "import_animation_offset_frames": 0,
            "frames": frames, "action_count": len(bpy.data.actions), "slot_count": len(action.slots),
            "assigned_slot": imported_slot.identifier if imported_slot else None,
            "armature_world_scale": list(imported.matrix_world.to_scale()),
            "sample_comparisons": comparisons,
            "pass": frames == list(expected[name]["frames"]) and len(bpy.data.actions) == 1 and all(item["pass"] for item in comparisons.values()),
        }
        report["fbx_roundtrip"][name] = roundtrip
        if not roundtrip["pass"]:
            report["errors"].append(name + ": FBX roundtrip differs from production")
        print("ROUNDTRIP", name, roundtrip["pass"], flush=True)
    report["production_sha256_after"] = digest(blend)
    report["production_unchanged"] = before == report["production_sha256_after"]
    if not report["production_unchanged"]:
        report["errors"].append("Production blend changed during validation")
    if fps != 30 or report["authored_clip_count"] != 16 or not report["manifest_names_match"]:
        report["errors"].append("Package count/FPS/manifest mismatch")
    if any(abs(value - .01) > 1e-5 for value in report["armature_world_scale"]):
        report["errors"].append("Expected production armature world scale 0.01")
    report["status"] = "passed" if not report["errors"] else "failed"
    report["integer_pose_frames_checked"] = sum(row["frame_count"] for row in report["clips"].values())
    report["mesh_frames_sampled"] = sum(len(row["mesh_clearance"]["samples"]) for row in report["clips"].values())
    report["roundtrip_pose_samples"] = sum(len(row.get("sample_comparisons", {})) for row in report["fbx_roundtrip"].values())
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print("SHEPHERD_QA", report["status"], "errors", len(report["errors"]), "warnings", len(report["warnings"]), "report", output, flush=True)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    package = args.base.resolve()
    validate(package, args.output or package / "validation/numeric-validation.json")
