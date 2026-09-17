extends SceneTree
## Read the production sampler and imported blade; do not create a player,
## install a diagnostic clip, advance combat, or depend on staging being present.
## Compare corresponding times, never reverse playback. During the cut the
## forehand reflects camera X and local blade width X, retaining a proper basis
## and the reverse's blade height/depth. Original right-hand geometry is intact.
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
const SWEEP_END := 0.699
const CONTACT_TIME := 0.710
const SWEEP_INTERVALS := 78
const OPTIONAL_BASELINE := "../asset-staging/sword_followthrough_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
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
	var result := {"contract": "retained_approach_and_contact; horizontal_followthrough_outside_view; shared_idle", "aesthetic_quality_evaluated": false, "baseline": _test_optional_preservation()}
	if available:
		result["correspondence"] = _test_pose_correspondence()
		result["sweep"] = _test_sweep()
		result["recovery"] = _test_recovery_preservation()
		result["followthrough"] = _test_followthrough()
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


func _mirror(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, point.z)


func _test_pose_correspondence() -> Dictionary:
	var grip_error := 0.0
	var axis_error := 0.0
	for index in range(181):
		var time := 0.62 + 0.08 * float(index) / 180.0
		var right := MOTION.sample("right_diagonal", time)
		var left := MOTION.sample("left_reverse", time)
		for pose: Transform3D in [right, left]:
			_check(pose.origin.is_finite() and pose.basis.is_finite() and pose.basis.get_scale().distance_to(Vector3.ONE) < 0.00001 and absf(pose.basis.determinant() - 1.0) < 0.00001, "The actual sword and original hand must retain proper, unscaled rotations.")
		grip_error = maxf(grip_error, (right * GRIP.GRIP_CENTER).distance_to(_mirror(left * GRIP.GRIP_CENTER)))
		axis_error = maxf(axis_error, right.basis.x.distance_to(-_mirror(left.basis.x)))
		axis_error = maxf(axis_error, right.basis.y.distance_to(_mirror(left.basis.y)))
		axis_error = maxf(axis_error, right.basis.z.distance_to(_mirror(left.basis.z)))
	_check(grip_error < 0.00003 and axis_error < 0.00002, "The approach to contact must retain the accepted same-time reverse reflection.")
	var contact := MOTION.sample("right_diagonal", CONTACT_TIME)
	_check(contact.basis.y.x > 0.8 and contact.basis.y.y > 0.1 and contact.basis.y.z < -0.2, "At contact the forehand blade must point right/up/forward, rather than down and back toward the camera.")
	return {"samples": 181, "max_grip_m": grip_error, "max_axis_error": axis_error}


func _test_recovery_preservation() -> Dictionary:
	var ready := MOTION.sample("idle", 0.0)
	var ready_arm := MOTION.sample_right_arm("idle", 0.0)
	for time: float in [0.0, DURATION]:
		var pose := MOTION.sample("right_diagonal", time)
		_check(pose.origin.distance_to(ready.origin) < 0.00003 and pose.basis.is_equal_approx(ready.basis), "Mirrored forehand must start and finish at the real right-side idle, without leaving a 72cm READY handoff.")
		var arm := MOTION.sample_right_arm("right_diagonal", time)
		for joint: String in ["shoulder", "elbow", "wrist"]:
			_check((arm[joint] as Vector3).distance_to(ready_arm[joint]) < 0.00003, "The original right arm must also rejoin its real idle endpoint: " + joint)
	var peak_step := 0.0
	var previous := MOTION.sample("right_diagonal", 0.8)
	var peak_visible_step := 0.0
	for index in range(1, 621):
		var pose := MOTION.sample("right_diagonal", 0.8 + float(index) * 0.001)
		var step := (pose * GRIP.GRIP_CENTER).distance_to(previous * GRIP.GRIP_CENTER)
		peak_step = maxf(peak_step, step)
		if not (_outside_blade(previous) and _outside_blade(pose)): peak_visible_step = maxf(peak_visible_step, step)
		_check(pose.origin.is_finite() and pose.basis.is_finite() and pose.basis.get_scale().distance_to(Vector3.ONE) < 0.00001, "Recovery must remain finite and keep the original mesh dimensions.")
		previous = pose
	_check(peak_step < 0.035 and peak_visible_step < 0.015, "Recovery must remain continuous; faster repositioning must occur entirely outside the viewport.")
	return {"idle_and_arm_endpoints_checked": true, "samples": 621, "max_1ms_grip_step_m": peak_step, "max_visible_step_m": peak_visible_step}


func _test_sweep() -> Dictionary:
	var errors := {}
	var moving := 0
	for name: String in BLADE_POINTS:
		var point: Vector3 = BLADE_POINTS[name]
		var maximum := 0.0
		for index in range(SWEEP_INTERVALS + 1):
			var time := lerpf(SWEEP_START, SWEEP_END, float(index) / SWEEP_INTERVALS)
			var right := _point_velocity("right_diagonal", time, point)
			var left := _point_velocity("left_reverse", time, point)
			maximum = maxf(maximum, right.distance_to(_mirror(left)))
			if name == "center" and absf(left.x) > MIN_MOVING_SPEED:
				moving += 1
				_check(right.x * left.x < 0.0, "The same-phase blade center must move in opposite horizontal directions.")
		_check(maximum < 0.003, "Same-time blade-point velocities must be spatial reflections, including unchanged vertical/depth velocity: " + name)
		errors[name] = maximum
	_check(moving > 10, "The comparison must cover moving cut frames.")
	return {"max_reflected_velocity_error_m_per_s": errors, "moving_samples": moving}


func _point_velocity(clip: String, time: float, point: Vector3) -> Vector3:
	return (MOTION.sample(clip, time + DERIVATIVE_SECONDS) * point - MOTION.sample(clip, time - DERIVATIVE_SECONDS) * point) / (2.0 * DERIVATIVE_SECONDS)


func _test_wrist_anchors(clip: String) -> Dictionary:
	var count := 0
	var wrist_error := 0.0
	var length_error := 0.0
	var raw_clip: Dictionary = _manifest.get("clips", {}).get(clip, {})
	var rows: Array = raw_clip.get("tracks", {}).get("sword", [])
	var previous_time := -1.0
	var saw_start := false
	var saw_cut_start := false
	var saw_contact := false
	var saw_cut_end := false
	var saw_end := false
	# Exact source keys retain the original arm joints. Interior samples are
	# interpolation inputs, so fixed-length runtime IK is covered by player tests.
	for row: Dictionary in rows:
		var time := float(row.time_seconds)
		_check(time > previous_time, clip + ": source key times must be strictly increasing without duplicate boundary rows.")
		previous_time = time
		saw_start = saw_start or is_zero_approx(time)
		saw_cut_start = saw_cut_start or absf(time - 0.62) < 0.0000001
		saw_contact = saw_contact or absf(time - CONTACT_TIME) < 0.0000001
		saw_cut_end = saw_cut_end or absf(time - 0.80) < 0.0000001
		saw_end = saw_end or absf(time - DURATION) < 0.0000001
		var arm := MOTION.sample_right_arm(clip, time)
		_check(not arm.is_empty() and bool(arm.get("exact_sample", false)), clip + ": every authored joint key must remain available as an exact sample.")
		if arm.is_empty(): continue
		var pose := MOTION.sample(clip, time)
		wrist_error = maxf(wrist_error, (arm.wrist as Vector3).distance_to(pose * GRIP.REST_WRIST))
		length_error = maxf(length_error, absf((arm.shoulder as Vector3).distance_to(arm.elbow) - GRIP.REST_UPPER_LENGTH))
		length_error = maxf(length_error, absf((arm.elbow as Vector3).distance_to(arm.wrist) - GRIP.REST_FOREARM_LENGTH))
		count += 1
	_check(saw_start and saw_cut_start and saw_contact and saw_cut_end and saw_end and count == rows.size(), clip + ": the retained source keys must include unique clip/cut/contact endpoints with matching joint samples.")
	_check(wrist_error < 0.00003 and length_error < 0.00003, clip + ": all authored right-hand joint poses must preserve arm lengths and the original right-hand REST_WRIST anchor, without mirrored hand coordinates.")
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


func _outside_blade(pose: Transform3D) -> bool:
	# Actual 76-degree vertical FOV, 1280x720. A convex blade bound wholly
	# beyond one frustum side guarantees that the complete blade is hidden.
	var left := true
	var below := true
	var vertical := tan(deg_to_rad(38.0))
	for i in 8:
		var point := pose * BLADE_BOUNDS.get_endpoint(i)
		left = left and point.x < vertical * (1280.0 / 720.0) * point.z
		below = below and point.y < vertical * point.z
	return left or below


func _test_followthrough() -> Dictionary:
	var contact := MOTION.sample("right_diagonal", CONTACT_TIME)
	var previous := contact
	var max_angle := 0.0
	var max_height_axis_error := 0.0
	for index in range(1, 91):
		var pose := MOTION.sample("right_diagonal", CONTACT_TIME + float(index) * 0.001)
		max_angle = maxf(max_angle, rad_to_deg(previous.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())))
		max_height_axis_error = maxf(max_height_axis_error, absf(pose.basis.y.y - contact.basis.y.y))
		for point: Vector3 in [GRIP.GRIP_CENTER, BLADE_POINTS.center, BLADE_POINTS.tip]:
			_check((pose * point).x <= (previous * point).x + 0.0001, "After contact the grip, blade center and tip must continue left, without reversing inside the view.")
		previous = pose
	_check(max_angle < 2.5 and max_height_axis_error < 0.004, "Follow-through must keep the cutting plane and avoid the old rapid wrist flip.")
	_check(_outside_blade(previous), "The full blade must pass beyond the left viewport edge before recovery.")
	for index in range(401):
		var time := 0.8 + float(index) * 0.001
		_check(_outside_blade(MOTION.sample("right_diagonal", time)), "The blade must stay outside the view during lowered reorientation; time=" + str(time))
	var ready := MOTION.sample("idle", 0.0)
	for index in range(221):
		var pose := MOTION.sample("right_diagonal", 1.20 + float(index) * 0.001)
		_check(pose.basis.y.distance_to(ready.basis.y) < 0.0001 and pose.basis.z.distance_to(ready.basis.z) < 0.0001, "The returning blade must already have its idle orientation, with no visible last-moment bend.")
	return {"max_followthrough_1ms_angle_deg": max_angle, "max_cutting_plane_y_error": max_height_axis_error, "hidden_reset_samples": 401, "fixed_orientation_return_samples": 221}
