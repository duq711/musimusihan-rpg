extends SceneTree
## Read the production sampler and imported blade; do not create a player,
## install a diagnostic clip, advance combat, or depend on staging being present.
## Contract changed: the forehand now plays the preserved reverse poses in
## reverse time, without spatial reflection. The former fixed upper-right pose
## and <=5-degree blade-plane requirements are intentionally superseded; they
## described the rejected separate forehand design. This test checks geometry,
## source preservation and opposite playback, not animation aesthetics.
const MOTION := preload("res://scripts/reference_sword_motion.gd")
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const MODEL_PATH := "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
const MODEL_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const CLIPS := ["right_diagonal", "left_reverse"]
# Independently measured from all 726 source blade vertices after normalization:
# X is width, Y is length, Z is thickness. The broad face is XY, normal +/-Z.
const BLADE_BOUNDS := AABB(Vector3(-0.031, -0.010, -0.0045), Vector3(0.062, 1.045, 0.009))
const BLADE_POINTS := {
	"center": Vector3(0.0, 0.5125, 0.0),
	"blade_65cm": Vector3(0.0, 0.65, 0.0),
	"tip": Vector3(0.0, 1.035, 0.0),
}
const DERIVATIVE_SECONDS := 0.001
const MIN_MOVING_SPEED := 0.01
const DURATION := 1.42
const SWEEP_START := 0.621
const SWEEP_END := 0.799
const CONTACT_TIME := 0.710
const SWEEP_INTERVALS := 178
const OPTIONAL_BASELINE := "../asset-staging/sword_forehand_from_reverse_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
var failures: Array[String] = []
var _manifest: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)


func _run() -> void:
	var manifest_before := FileAccess.get_sha256(MOTION.MANIFEST_PATH)
	var model_before := FileAccess.get_sha256(MODEL_PATH)
	var cursor := Input.mouse_mode
	_check(model_before == MODEL_SHA256, "Edge alignment must retain the exact original SwordHold_Static GLB bytes.")
	_test_geometry()
	var available := true
	for clip: String in CLIPS:
		available = available and MOTION.has_track(clip, "sword") and MOTION.has_right_arm(clip)
	_check(available and MOTION.get_load_error().is_empty(), "Both production sword/right-arm tracks must load: " + MOTION.get_load_error())
	var result := {"contract": "preserved_reverse_poses_played_in_opposite_time", "aesthetic_quality_evaluated": false, "baseline": _test_optional_preservation()}
	if available:
		result["correspondence"] = _test_pose_correspondence()
		result["sweep"] = _test_sweep()
		for clip: String in CLIPS: result[clip + "_wrist"] = _test_wrist_anchors(clip)
	_check(manifest_before == FileAccess.get_sha256(MOTION.MANIFEST_PATH) and model_before == FileAccess.get_sha256(MODEL_PATH), "Sampling and geometry inspection must preserve the production manifest and original model.")
	_check(Input.mouse_mode == cursor, "Pure blade inspection must preserve mouse mode.")
	for message in failures: push_error(message)
	print("SWORD EDGE ALIGNMENT %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(result)])
	quit(0 if failures.is_empty() else 1)


func _test_geometry() -> void:
	var sword := GRIP.create_sword()
	var blade := sword.find_child("PittedBlade", true, false) as MeshInstance3D
	_check(blade != null and blade.mesh != null, "The real normalized PittedBlade must exist.")
	if blade != null and blade.mesh != null:
		var bounds := blade.mesh.get_aabb()
		_check(blade.transform.is_equal_approx(Transform3D.IDENTITY), "The blade's canonical axes must be the actual sword pivot axes.")
		_check(bounds.position.distance_to(BLADE_BOUNDS.position) < 0.00002 and bounds.size.distance_to(BLADE_BOUNDS.size) < 0.00002, "Actual blade geometry must remain X=62mm width, Y=1045mm length, Z=9mm thickness.")
		_check(bounds.get_center().distance_to(BLADE_POINTS.center) < 0.00002, "The sweep center must match the actual normalized blade center.")
		var tip := sword.get_node_or_null("BladeTip") as Marker3D
		_check(tip != null and tip.position.distance_to(BLADE_POINTS.tip) < 0.00002, "The tested tip must match the actual blade endpoint marker.")
	sword.free()


func _test_pose_correspondence() -> Dictionary:
	var position_error := 0.0
	var axis_error := 0.0
	var joint_error := 0.0
	# Include the whole preparation/recovery and interior cubic samples, not
	# merely matching row indices on potentially different timestamp grids.
	for index in range(285):
		var time := DURATION * float(index) / 284.0
		var right := MOTION.sample("right_diagonal", time)
		var left := MOTION.sample("left_reverse", DURATION - time)
		for pose: Transform3D in [right, left]:
			_check(pose.origin.is_finite() and pose.basis.is_finite() and pose.basis.get_scale().distance_to(Vector3.ONE) < 0.00001 and absf(pose.basis.determinant() - 1.0) < 0.00001 and (pose.basis.transposed() * pose.basis).is_equal_approx(Basis.IDENTITY), "Both sampled clips must retain finite, unscaled proper rotations without mirroring the original hand.")
		position_error = maxf(position_error, right.origin.distance_to(left.origin))
		for axis: int in range(3): axis_error = maxf(axis_error, right.basis[axis].distance_to(left.basis[axis]))
		var right_arm := MOTION.sample_right_arm("right_diagonal", time)
		var left_arm := MOTION.sample_right_arm("left_reverse", DURATION - time)
		for joint: String in ["shoulder", "elbow", "wrist"]:
			joint_error = maxf(joint_error, (right_arm[joint] as Vector3).distance_to(left_arm[joint]))
	_check(position_error < 0.00005 and axis_error < 0.00005 and joint_error < 0.00005, "The actual sampler must reproduce the same sword and arm poses at opposite times throughout the complete clips, without spatial reflection.")
	var right_contact := MOTION.sample("right_diagonal", CONTACT_TIME)
	var left_contact := MOTION.sample("left_reverse", CONTACT_TIME)
	_check(right_contact.origin.distance_to(left_contact.origin) < 0.00002 and right_contact.basis.is_equal_approx(left_contact.basis), "Both directions must retain exactly the same original contact pose at authored 710ms.")
	var right_meta := MOTION.clip_metadata("right_diagonal")
	var left_meta := MOTION.clip_metadata("left_reverse")
	_check(right_meta.timing == left_meta.timing and is_equal_approx(float(right_meta.duration_seconds), DURATION) and is_equal_approx(float(left_meta.duration_seconds), DURATION), "Opposite playback must preserve authored preparation, contact, active and recovery clocks.")
	return {"samples": 285, "max_position_m": position_error, "max_axis_error": axis_error, "max_joint_m": joint_error}


func _test_sweep() -> Dictionary:
	var report: Dictionary = {}
	for point_name: String in BLADE_POINTS:
		report[point_name] = {"moving_samples": 0, "before_contact": 0, "after_contact": 0, "max_velocity_sum_m_per_s": 0.0, "least_opposite_dot": -1.0}
	# Signed vector comparisons detect a copied same-direction swing and an
	# accidental spatial mirror, which speed magnitudes alone cannot distinguish.
	for index in range(SWEEP_INTERVALS + 1):
		var time := lerpf(SWEEP_START, SWEEP_END, float(index) / SWEEP_INTERVALS)
		for point_name: String in BLADE_POINTS:
			var point: Vector3 = BLADE_POINTS[point_name]
			var right := _point_velocity("right_diagonal", time, point)
			var left := _point_velocity("left_reverse", DURATION - time, point)
			_check(right.is_finite() and left.is_finite(), "Actual blade point velocities must remain finite: " + point_name)
			var values: Dictionary = report[point_name]
			values.max_velocity_sum_m_per_s = maxf(values.max_velocity_sum_m_per_s, (right + left).length())
			if minf(right.length(), left.length()) < MIN_MOVING_SPEED: continue
			values.moving_samples += 1
			if time < CONTACT_TIME - DERIVATIVE_SECONDS: values.before_contact += 1
			if time > CONTACT_TIME + DERIVATIVE_SECONDS: values.after_contact += 1
			values.least_opposite_dot = maxf(values.least_opposite_dot, right.normalized().dot(left.normalized()))
	for point_name: String in BLADE_POINTS:
		var values: Dictionary = report[point_name]
		_check(int(values.moving_samples) >= 20 and int(values.before_contact) > 0 and int(values.after_contact) > 0, point_name + ": the real sweep must contain moving samples before and after contact.")
		_check(float(values.max_velocity_sum_m_per_s) < 0.003 and float(values.least_opposite_dot) < -0.999, point_name + ": corresponding real blade-center/tip velocities must have equal magnitude and opposite direction.")
		var point: Vector3 = BLADE_POINTS[point_name]
		_check(_point_velocity("right_diagonal", CONTACT_TIME, point).length() > MIN_MOVING_SPEED and _point_velocity("left_reverse", CONTACT_TIME, point).length() > MIN_MOVING_SPEED, point_name + ": both contact samples must contain actual blade movement.")
	var right_grip := _point_velocity("right_diagonal", CONTACT_TIME, GRIP.GRIP_CENTER)
	var left_grip := _point_velocity("left_reverse", CONTACT_TIME, GRIP.GRIP_CENTER)
	_check(right_grip.x < -MIN_MOVING_SPEED and left_grip.x > MIN_MOVING_SPEED, "At the same contact pose, the actual forehand grip must travel left and the preserved reverse grip must travel right.")
	_check((right_grip + left_grip).length() < 0.003, "Opposite contact grip velocities must retain the same source speed.")
	report["contact_grip_x_m_per_s"] = {"right_diagonal": right_grip.x, "left_reverse": left_grip.x}
	return report


func _point_velocity(clip: String, time: float, point: Vector3) -> Vector3:
	var before := MOTION.sample(clip, time - DERIVATIVE_SECONDS)
	var after := MOTION.sample(clip, time + DERIVATIVE_SECONDS)
	return (after * point - before * point) / (2.0 * DERIVATIVE_SECONDS)


func _test_wrist_anchors(clip: String) -> Dictionary:
	var count := 0
	var wrist_error := 0.0
	var length_error := 0.0
	var raw_clip: Dictionary = _manifest.get("clips", {}).get(clip, {})
	# Exact source keys retain the original arm joints. Interior samples are
	# interpolation inputs, so fixed-length runtime IK is covered by player tests.
	for row: Dictionary in raw_clip.get("tracks", {}).get("sword", []):
		var time := float(row.time_seconds)
		var arm := MOTION.sample_right_arm(clip, time)
		_check(not arm.is_empty() and bool(arm.get("exact_sample", false)), clip + ": every authored joint key must remain available as an exact sample.")
		if arm.is_empty(): continue
		var pose := MOTION.sample(clip, time)
		wrist_error = maxf(wrist_error, (arm.wrist as Vector3).distance_to(pose * GRIP.REST_WRIST))
		length_error = maxf(length_error, absf((arm.shoulder as Vector3).distance_to(arm.elbow) - GRIP.REST_UPPER_LENGTH))
		length_error = maxf(length_error, absf((arm.elbow as Vector3).distance_to(arm.wrist) - GRIP.REST_FOREARM_LENGTH))
		count += 1
	_check(count == 174 and wrist_error < 0.00003 and length_error < 0.00003, clip + ": all 174 original joint poses must retain arm lengths and the original right-hand REST_WRIST anchor, without mirrored hand coordinates.")
	return {"exact_keys": count, "max_wrist_m": wrist_error, "max_segment_length_m": length_error}


func _test_optional_preservation() -> String:
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(MOTION.MANIFEST_PATH))
	_check(current is Dictionary, "The production manifest must remain readable JSON.")
	if not current is Dictionary: return "invalid_manifest"
	_manifest = current
	_check(str(current.get("source", {}).get("godot_model_sha256", "")) == MODEL_SHA256, "The authored track must identify the original sword model.")
	# Optional checkout audit: a project-only checkout still runs every geometry
	# and motion assertion above. No absolute workstation path is embedded.
	var baseline_path := ProjectSettings.globalize_path("res://").path_join(OPTIONAL_BASELINE).simplify_path()
	if not FileAccess.file_exists(baseline_path): return "not_available; geometry_and_motion_checked"
	var baseline: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	_check(baseline is Dictionary and baseline.get("clips") is Dictionary, "An available preservation baseline must be valid JSON.")
	if not baseline is Dictionary or not baseline.get("clips") is Dictionary: return "invalid_baseline"
	var original_clips: Dictionary = baseline.clips
	var current_clips: Dictionary = current.get("clips", {})
	_check(current_clips.size() == original_clips.size(), "Forehand reversal must preserve the original clip set.")
	for clip_name: String in original_clips:
		if clip_name != "right_diagonal":
			_check(current_clips.get(clip_name) == original_clips[clip_name], "Forehand reversal must preserve the original clip exactly, especially left_reverse: " + clip_name)
	var original_cut: Dictionary = original_clips.get("right_diagonal", {})
	var current_cut: Dictionary = current_clips.get("right_diagonal", {})
	_check(current_cut.get("timing") == original_cut.get("timing"), "Forehand reversal must preserve authored attack timing.")
	# The reversed sword timestamps use a different grid. Schema v2 requires
	# matching shield timestamps, so byte equality is no longer the contract:
	# the shield must preserve the old same-time curve after resampling.
	var original_data := MOTION._decode_clip("right_diagonal", original_cut, int(baseline.get("schema_version", 2)))
	_check(not original_data.is_empty(), "The optional original shield curve must decode before comparing its geometry.")
	if original_data.is_empty(): return "invalid_original_shield_curve"
	var max_position_error := 0.0
	var max_angle_error := 0.0
	var times: Array[float] = []
	for index in range(1421): times.append(float(index) * 0.001)
	for row: Dictionary in original_cut.get("tracks", {}).get("shield", []): times.append(float(row.time_seconds))
	for row: Dictionary in current_cut.get("tracks", {}).get("shield", []): times.append(float(row.time_seconds))
	for time: float in times:
		var expected := MOTION._sample_clip(original_data, time, "shield")
		var actual := MOTION.sample("right_diagonal", time, "shield")
		max_position_error = maxf(max_position_error, actual.origin.distance_to(expected.origin))
		max_angle_error = maxf(max_angle_error, rad_to_deg(actual.basis.get_rotation_quaternion().angle_to(expected.basis.get_rotation_quaternion())))
	_check(max_position_error <= 0.001 and max_angle_error <= 0.1, "Shield resampling must retain the original same-time geometry within 1mm and 0.1 degrees, including both old/new keys and interior samples.")
	print("SWORD EDGE SHIELD RESAMPLE ", JSON.stringify({"samples": times.size(), "max_position_m": max_position_error, "max_angle_degrees": max_angle_error}))
	return "all_other_clips_preserved; original_shield_curve_within_1mm_0.1deg"
