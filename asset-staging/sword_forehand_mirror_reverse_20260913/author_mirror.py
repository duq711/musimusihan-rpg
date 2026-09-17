"""Mac Blender delivery: same-time forehand reflection of the retained reverse.

Only candidate_01 is written. The production project, source manifest, source
shield delivery and original model files are read-only inputs. Blender stores
control keys; Godot's continuous playback and rendered appearance remain a
separate integration check owned by the parent task.
"""
import copy
import hashlib
import json
import math
import platform
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector


ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent.parent
SOURCE = ROOT / "baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
SHIELD_SOURCE = PROJECT / "asset-staging/sword_reverse_match_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
OUT = ROOT / "candidate_01"
GRIP = Vector((0.0, -0.108, 0.002))
WRIST = Vector((0.0679751875, -0.1080001335, 0.0524637313))
MIRROR = Matrix.Diagonal(Vector((-1.0, 1.0, 1.0)))
UPPER = 0.34000002959
FOREARM = 0.26000002263
MIN_REACH = UPPER - FOREARM
MAX_REACH = UPPER + FOREARM
DIRECTION_EPS = 0.000001
HINT_EPS = 0.00001
LIMIT_EPS = 0.000001
MIRROR_PLATEAU_START = 0.60
MIRROR_PLATEAU_END = 0.82
DURATION = 1.42
MODEL_PATHS = [
    PROJECT / "godot-game/assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
    PROJECT / "godot-game/assets/3d/player/sword_shield/left_arm.glb",
    PROJECT / "godot-game/assets/3d/player/sword_shield/right_arm.glb",
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def semantic_sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def smooth(value):
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def pose(row):
    x, y, z, w = row["rotation_xyzw"]
    return Vector(row["position"]), Quaternion((w, x, y, z)).normalized()


def rotation_distance(a, b):
    relative = (a.inverted() @ b).normalized()
    return 2.0 * math.atan2(Vector((relative.x, relative.y, relative.z)).length, abs(relative.w))


def reflected(p, q):
    # World-X and local-width-X reflections cancel handedness. Sword length
    # Y and face normal Z have exactly the world reflection of their source.
    basis = MIRROR @ q.to_matrix() @ MIRROR
    rotation = basis.to_quaternion().normalized()
    grip = MIRROR @ (p + q @ GRIP)
    return grip - rotation @ GRIP, rotation


def perpendicular(axis):
    guide = Vector((1.0, 0.0, 0.0))
    if abs(axis.y) < abs(axis.x):
        guide = Vector((0.0, 1.0, 0.0))
    if abs(axis.z) < abs(axis.dot(guide)):
        guide = Vector((0.0, 0.0, 1.0))
    return (guide - axis * guide.dot(axis)).normalized()


def coincident_axis(hint, previous):
    if hint.length > DIRECTION_EPS:
        return hint.normalized()
    if previous.length > DIRECTION_EPS:
        retained = previous.normalized()
        forward = Vector((0.0, 0.0, -1.0))
        forward -= retained * forward.dot(retained)
        return forward.normalized() if forward.length > DIRECTION_EPS else perpendicular(retained)
    return Vector((0.0, 0.0, -1.0))


def solve_arm(shoulder, hint, wrist, previous):
    """The finite-input branch of scripts/reference_sword_arm.gd, unchanged."""
    requested = shoulder.copy()
    offset = wrist - shoulder
    distance = offset.length
    axis = offset / distance if distance > 0.0 else coincident_axis(hint - wrist, previous)
    reach = min(MAX_REACH, max(MIN_REACH, distance))
    reach_adjusted = distance < MIN_REACH or distance > MAX_REACH
    if reach_adjusted:
        shoulder = wrist - axis * reach
    at_limit = reach - MIN_REACH <= LIMIT_EPS or MAX_REACH - reach <= LIMIT_EPS
    hinted = hint - shoulder
    hinted -= axis * hinted.dot(axis)
    retained = previous - axis * previous.dot(axis)
    if not at_limit and hinted.length > HINT_EPS:
        bend = hinted.normalized()
    elif retained.length > DIRECTION_EPS:
        bend = retained.normalized()
    elif hinted.length > HINT_EPS:
        bend = hinted.normalized()
    else:
        bend = perpendicular(axis)
    along = (UPPER * UPPER - FOREARM * FOREARM + reach * reach) / (2.0 * reach)
    height = math.sqrt(max(0.0, UPPER * UPPER - along * along))
    elbow = shoulder + axis * along + bend * height
    return {
        "shoulder": shoulder,
        "elbow": elbow,
        "wrist": wrist,
        "bend": bend,
        "requested_shoulder": requested,
        "shoulder_adjustment_m": (shoulder - requested).length,
        "reach_adjusted": reach_adjusted,
    }


def make_control(name, display_type="PLAIN_AXES"):
    control = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(control)
    control.empty_display_type = display_type
    control.empty_display_size = 0.045
    control.rotation_mode = "QUATERNION"
    return control


def main():
    assert platform.system() == "Darwin", "This delivery is authored on Mac only."
    OUT.mkdir(exist_ok=True)
    input_hashes = {str(path.relative_to(PROJECT)): sha(path) for path in [SOURCE, SHIELD_SOURCE, *MODEL_PATHS]}
    original = json.loads(SOURCE.read_text())
    manifest = copy.deepcopy(original)
    reverse = original["clips"]["left_reverse"]
    ready = original["clips"]["idle"]["tracks"]["sword"][0]
    ready_arm = original["clips"]["idle"]["right_arm"][0]
    shield = json.loads(SHIELD_SOURCE.read_text())["clips"]["right_diagonal"]["tracks"]["shield"]
    rows = reverse["tracks"]["sword"]
    times = [row["time_seconds"] for row in rows]
    assert len(rows) == 174 and len(reverse["right_arm"]) == 174
    assert times == [row["time_seconds"] for row in reverse["right_arm"]]
    assert times == [row["time_seconds"] for row in shield]
    assert all(a < b for a, b in zip(times, times[1:]))
    assert reverse["timing"] == {"windup_seconds": 0.62, "active_seconds": 0.18, "hit_seconds": 0.09, "recovery_seconds": 0.62}
    forehand = copy.deepcopy(reverse)
    forehand["tracks"]["shield"] = copy.deepcopy(shield)
    manifest["clips"]["right_diagonal"] = forehand
    ready_p, ready_q = pose(ready)
    ready_grip = ready_p + ready_q @ GRIP
    mirror_ready_p, mirror_ready_q = reflected(ready_p, ready_q)
    ready_offset = ready_grip - (mirror_ready_p + mirror_ready_q @ GRIP)
    ready_rotation = (ready_q @ mirror_ready_q.inverted()).normalized()
    if ready_rotation.w < 0.0:
        ready_rotation.negate()

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    scene = bpy.context.scene
    scene.render.fps = 120
    scene.frame_start = 1
    scene.frame_end = math.ceil(times[-1] * 120.0 + 1.0)
    scene["coordinate_system"] = "Godot camera local: X right, Y up, -Z forward; meters"
    scene["delivery_scope"] = "Source control keys; runtime interpolation and actual screen QA are performed in Godot separately."
    controls = {name: make_control("right_diagonal_" + name) for name in ["sword", "grip", "shoulder", "elbow", "wrist", "requested_shoulder", "elbow_hint"]}
    controls["sword"].empty_display_type = "ARROWS"
    controls["sword"]["original_mesh_unmodified"] = True
    controls["sword"]["reflection"] = "MworldX * source_rotation * MlocalWidthX; proper rotation only"
    previous_q = None
    previous_bend = Vector((0.0, 0.0, 0.0))
    diagnostics = []
    max_values = {key: 0.0 for key in ["active_grip_m", "active_axis", "grip_anchor_m", "wrist_anchor_m", "upper_length_m", "forearm_length_m", "determinant", "unit_quaternion", "shoulder_adjustment_m"]}

    for index, source_row in enumerate(rows):
        time = source_row["time_seconds"]
        source_p, source_q = pose(source_row)
        p, q = reflected(source_p, source_q)
        # Include neighboring keys outside ACTIVE, since Godot's continuous
        # position/rotation tangents also read those neighbors at the boundary.
        weight = 1.0 - smooth(time / MIRROR_PLATEAU_START) if time < MIRROR_PLATEAU_START else smooth((time - MIRROR_PLATEAU_END) / (DURATION - MIRROR_PLATEAU_END)) if time > MIRROR_PLATEAU_END else 0.0
        target_grip = p + q @ GRIP + ready_offset * weight
        q = (Quaternion().slerp(ready_rotation, weight) @ q).normalized()
        p = target_grip - q @ GRIP
        # Remove roundoff from the analytically exact shared ready endpoints.
        if index in (0, len(rows) - 1):
            p, q = ready_p.copy(), ready_q.copy()
            target_grip = ready_grip.copy()
        if previous_q is not None and previous_q.dot(q) < 0.0:
            q.negate()
        previous_q = q.copy()
        source_arm = reverse["right_arm"][index]
        requested_shoulder = Vector(source_arm["shoulder"])
        source_elbow = Vector(source_arm["elbow"])
        elbow_hint = (MIRROR @ source_elbow).lerp(source_elbow, weight)
        wrist = p + q @ WRIST
        solved = solve_arm(requested_shoulder, elbow_hint, wrist, previous_bend)
        previous_bend = solved["bend"].copy()
        row = copy.deepcopy(source_row)
        row["position"] = list(p)
        row["rotation_xyzw"] = [q.x, q.y, q.z, q.w]
        forehand["tracks"]["sword"][index] = row
        forehand["right_arm"][index] = {"time_seconds": time, **{joint: list(solved[joint]) for joint in ["shoulder", "elbow", "wrist"]}}

        frame = time * 120.0 + 1.0
        controls["sword"].location = p
        controls["sword"].rotation_quaternion = q
        controls["sword"].keyframe_insert("location", frame=frame)
        controls["sword"].keyframe_insert("rotation_quaternion", frame=frame)
        values = {"grip": target_grip, "elbow_hint": elbow_hint, **solved}
        for name in ["grip", "shoulder", "elbow", "wrist", "requested_shoulder", "elbow_hint"]:
            controls[name].location = values[name]
            controls[name].keyframe_insert("location", frame=frame)

        basis = q.to_matrix()
        active = 0.62 <= time <= 0.80
        active_grip_error = ((p + q @ GRIP) - MIRROR @ (source_p + source_q @ GRIP)).length if active else 0.0
        active_axis_error = max((basis.col[axis] - ((-1.0 if axis == 0 else 1.0) * (MIRROR @ source_q.to_matrix().col[axis]))).length for axis in range(3)) if active else 0.0
        errors = {
            "active_grip_m": active_grip_error,
            "active_axis": active_axis_error,
            "grip_anchor_m": ((p + q @ GRIP) - target_grip).length,
            "wrist_anchor_m": (solved["wrist"] - (p + q @ WRIST)).length,
            "upper_length_m": abs((solved["shoulder"] - solved["elbow"]).length - UPPER),
            "forearm_length_m": abs((solved["elbow"] - solved["wrist"]).length - FOREARM),
            "determinant": abs(basis.determinant() - 1.0),
            "unit_quaternion": abs(q.magnitude - 1.0),
            "shoulder_adjustment_m": solved["shoulder_adjustment_m"],
        }
        for key, value in errors.items():
            max_values[key] = max(max_values[key], value)
        assert all(math.isfinite(value) for value in errors.values())
        diagnostics.append({"time_seconds": time, "ready_correction_weight": weight, "requested_shoulder": list(requested_shoulder), "solved_shoulder": list(solved["shoulder"]), "elbow_hint": list(elbow_hint), "shoulder_adjustment_m": solved["shoulder_adjustment_m"], "reach_adjusted": solved["reach_adjusted"]})

    assert all(max_values[key] < 0.000002 for key in ["active_grip_m", "active_axis", "grip_anchor_m", "wrist_anchor_m", "upper_length_m", "forearm_length_m", "determinant", "unit_quaternion"]), max_values
    endpoint_errors = []
    for index in [0, len(rows) - 1]:
        p, q = pose(forehand["tracks"]["sword"][index])
        joints = forehand["right_arm"][index]
        entry = {"time_seconds": times[index], "pivot_m": (p - ready_p).length, "grip_m": ((p + q @ GRIP) - ready_grip).length, "rotation_rad": rotation_distance(ready_q, q), "max_joint_m": max((Vector(joints[name]) - Vector(ready_arm[name])).length for name in ["shoulder", "elbow", "wrist"])}
        assert max(entry[key] for key in ["pivot_m", "grip_m", "rotation_rad", "max_joint_m"]) < 0.000002, entry
        endpoint_errors.append(entry)

    preserved = {}
    for name, data in original["clips"].items():
        if name != "right_diagonal":
            assert manifest["clips"][name] == data
            preserved[name] = semantic_sha(data)
    assert forehand["tracks"]["shield"] == shield
    assert forehand["timing"] == reverse["timing"]
    assert times == [row["time_seconds"] for row in forehand["tracks"]["sword"]]
    assert all(pose(forehand["tracks"]["sword"][i])[1].dot(pose(forehand["tracks"]["sword"][i + 1])[1]) >= 0.0 for i in range(len(rows) - 1))
    assert input_hashes == {str(path.relative_to(PROJECT)): sha(path) for path in [SOURCE, SHIELD_SOURCE, *MODEL_PATHS]}
    historical = {}
    for key in list(manifest):
        if key == "forehand_from_reverse" or "edge_alignment" in key:
            historical[key] = manifest.pop(key)
    if historical:
        manifest.setdefault("superseded_motion_provenance", []).append({"status": "historical_superseded", "reason": "Same-time spatial reflection replaces prior time-reversal and post-entry direction correction.", "records": historical})
    provenance = {
        "date": "2026-09-13", "execution_os": platform.system(), "blender_version": bpy.app.version_string,
        "source_manifest_sha256": sha(SOURCE), "source_reverse_semantic_sha256": semantic_sha(reverse),
        "shield_source_manifest_sha256": sha(SHIELD_SOURCE), "shield_track_semantic_sha256": semantic_sha(shield),
        "author_script_sha256": sha(Path(__file__)), "source_samples": len(rows), "source_time_order_preserved": True,
        "cut_transform": "same-time camera-X reflection; proper basis MworldX*R*MlocalWidthX; active source [0.62,0.80] exactly reflected",
        "ready_join": "grip offset and left-multiplied ready quaternion correction; weight 1-smooth(t/.60) before plateau, smooth((t-.82)/.60) after plateau",
        "exact_mirror_plateau_seconds": [MIRROR_PLATEAU_START, MIRROR_PLATEAU_END],
        "arm": "original right-side shoulder request; mirror elbow hint blended back by ready weight; actual wrist from unchanged model; reference_sword_arm fixed-length solve",
        "preserved": "all nine other clips including left_reverse; original GLBs; specified forehand shield samples; source timestamps, duration and timings",
        "shoulder_limit_policy": "The identical runtime solver preserves wrist and minimally compensates shoulder only when the requested reach is outside its fixed-length shell.",
    }
    manifest["forehand_mirror_reverse"] = provenance
    qa = {
        "status": "PASS", "scope": "Blender candidate source-key arithmetic and original-input preservation; no Godot execution, runtime interpolation or screen quality claim",
        "source_samples": len(rows), "active_samples": sum(0.62 <= t <= 0.80 for t in times), "exact_mirror_plateau_seconds": [MIRROR_PLATEAU_START, MIRROR_PLATEAU_END], "max_errors": max_values,
        "shared_ready_endpoints": endpoint_errors, "preserved_clip_semantic_sha256": preserved,
        "preserved_shield_track_semantic_sha256": semantic_sha(shield), "input_sha256": input_hashes,
        "shoulder_reach_adjusted_samples": sum(row["reach_adjusted"] for row in diagnostics),
        "largest_shoulder_adjustments": sorted(diagnostics, key=lambda item: item["shoulder_adjustment_m"], reverse=True)[:5],
    }
    # Save all requested-shoulder observations separately; keep the QA summary short.
    (OUT / "requested_shoulder_diagnostics.json").write_text(json.dumps(diagnostics, indent=2) + "\n")
    (OUT / "motion_manifest.json").write_text(json.dumps(manifest, separators=(",", ":")))
    qa["candidate_manifest_sha256"] = sha(OUT / "motion_manifest.json")
    (OUT / "qa.json").write_text(json.dumps(qa, indent=2) + "\n")
    scene["provenance_json"] = json.dumps(provenance, sort_keys=True)
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "Forehand_Mirror_Reverse.blend"))
    print("FOREHAND MIRROR AUTHOR PASS " + json.dumps({"source_samples": len(rows), "max_errors": max_values, "endpoint_errors": endpoint_errors, "shoulder_reach_adjusted_samples": qa["shoulder_reach_adjusted_samples"]}, sort_keys=True))


if __name__ == "__main__":
    main()
