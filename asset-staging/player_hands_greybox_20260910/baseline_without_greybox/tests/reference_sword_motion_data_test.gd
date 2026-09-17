extends SceneTree
## Mathematical decoder/clock checks only. These short in-memory inputs carry
## no Windows provenance, are never installed, and are not animation delivery.

const DATA := preload("res://scripts/reference_sword_motion.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var source_hash := FileAccess.get_sha256(DATA.MANIFEST_PATH) if FileAccess.file_exists(DATA.MANIFEST_PATH) else "absent"
	var available := DATA.is_available()
	var arm_available := DATA.right_arm_available()
	var error := DATA.get_load_error()
	_test_decoder()
	_test_sample_inputs()
	_test_shared_clock()
	_check(DATA.is_available() == available and DATA.right_arm_available() == arm_available and DATA.get_load_error() == error, "Pure decoder/clock checks must not modify the production cache.")
	var after_hash := FileAccess.get_sha256(DATA.MANIFEST_PATH) if FileAccess.file_exists(DATA.MANIFEST_PATH) else "absent"
	_check(source_hash == after_hash, "Decoder tests must never install or modify a motion manifest.")
	if not arm_available:
		_check(DATA.sample_right_arm("overhead", 0.2).is_empty() and not DATA.has_right_arm("overhead"), "Missing or v1 delivery must never enable authored right-arm playback.")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD MOTION DATA %s: parser and shared clock only; actual_delivery_evaluated=false; production_arm_available=%s" % ["PASS" if failures.is_empty() else "FAIL", str(arm_available)])
	quit(0 if failures.is_empty() else 1)


func _test_decoder() -> void:
	_check(not bool(DATA._decode_manifest({}).ok), "Missing manifest metadata must fail.")
	_check(not bool(DATA._decode_manifest({"schema_version": 2.5, "status": "authored_windows_output"}).ok), "Fractional version numbers must not be truncated into version 2.")
	_check(not bool(DATA._decode_manifest({"schema_version": 2, "status": "authored_windows_review_output"}).ok), "An incomplete review must never become a version 2 production delivery.")
	var input := _analytic_clip()
	_check(not bool(DATA._decode_clips({"idle": input}, 2).ok), "One valid analytical clip must not stand in for all eight required clips.")
	var v1 := DATA._decode_clip("idle", input, 1)
	_check(not v1.is_empty() and not bool(v1.get("right_arm_available", true)) and not v1.has("right_arm"), "Legacy v1 pivots remain readable but cannot enable authored arm samples.")
	var valid := DATA._decode_clip("idle", input, 2)
	_check(not valid.is_empty() and bool(valid.get("right_arm_available", false)), "Exact source-length analytical joints must decode as v2 clip input.")
	var invalid: Dictionary = input.duplicate(true)
	invalid.erase("right_arm")
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Version 2 required clips must reject absent right_arm.")
	invalid = input.duplicate(true)
	invalid.tracks.erase("shield")
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Version 2 required clips must reject a missing shield.")
	invalid = input.duplicate(true)
	invalid.right_arm.pop_back()
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Arm sample count must match both pivot tracks.")
	invalid = input.duplicate(true)
	invalid.tracks.shield[1].time_seconds += 0.00001
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Both pivot tracks must share the arm timestamps.")
	invalid = input.duplicate(true)
	invalid.right_arm[1].wrist[0] += 0.002
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "A 2 mm authored wrist mismatch must fail.")
	invalid = input.duplicate(true)
	invalid.right_arm[1].shoulder[0] += 0.02
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "A stretched authored upper arm must fail.")
	invalid = input.duplicate(true)
	invalid.right_arm[1].elbow[0] = NAN
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Non-finite joints must fail.")
	invalid = input.duplicate(true)
	invalid.tracks.sword[1].rotation_xyzw = [0, 0, 0, 2]
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Non-unit pivot quaternions must fail.")
	invalid = input.duplicate(true)
	invalid.tracks.sword[1].time_seconds = "0.5"
	_check(DATA._decode_clip("idle", invalid, 2).is_empty(), "Version 2 sample time must be a numeric JSON value.")
	var loop := _analytic_clip(true)
	_check(not DATA._decode_clip("run", loop, 2).is_empty(), "Source-continuous loop joints must decode.")
	# Rotate the terminal upper-arm direction around its elbow, retaining exact
	# segment lengths and the wrist/pivots. Only the shoulder seam is broken.
	var endpoint: Dictionary = loop.right_arm[-1]
	var elbow := _vector(endpoint.elbow)
	var shoulder := _vector(endpoint.shoulder)
	endpoint.shoulder = _array(elbow + (shoulder - elbow).rotated(Vector3.UP, 0.04))
	_check(DATA._decode_clip("run", loop, 2).is_empty(), "A joint seam must fail even when lengths and pivot seams are valid.")


func _test_sample_inputs() -> void:
	var clip := DATA._decode_clip("idle", _analytic_clip(), 2)
	if clip.is_empty(): return
	for index in range(clip.right_arm.size()):
		var raw: Dictionary = clip.right_arm[index]
		var sampled := DATA._sample_right_arm_data(clip, raw.time_seconds)
		_check(bool(sampled.exact_sample) and not bool(sampled.interpolated_joints_require_runtime_ik), "Every exact input timestamp must retain its exact-sample flag.")
		for joint: String in ["shoulder", "elbow", "wrist"]:
			_check(sampled[joint] == raw[joint], "Exact joint coordinates must not be projected or normalized by the data module.")
		_check((sampled.raw_sword as Transform3D).is_equal_approx(clip.tracks.sword[index].transform), "Exact joints must return the same exact source sword sample.")
	var between := DATA._sample_right_arm_data(clip, 0.25)
	_check(not bool(between.exact_sample) and bool(between.interpolated_joints_require_runtime_ik), "Interpolated joint inputs must explicitly require runtime IK.")
	_check((between.raw_sword as Transform3D).is_equal_approx(DATA._sample_clip(clip, 0.25, "sword")), "Interpolated joints must carry the same-time sword from the production sampler.")
	var interpolated_length := (between.shoulder as Vector3).distance_to(between.elbow)
	_check(interpolated_length < ARM.REST_UPPER_LENGTH * 0.99, "Analytical rotation must expose joint-lerp shortening rather than falsely asserting fixed lengths.")
	_check(DATA._sample_right_arm_data(clip, INF).is_empty(), "Non-finite arm sample time must fail without a fallback pose.")
	var loop := DATA._decode_clip("run", _analytic_clip(true), 2)
	var terminal := DATA._sample_right_arm_data(loop, 1.0)
	_check(bool(terminal.exact_sample) and terminal.time_seconds == 1.0, "A positive complete loop must identify its exact closing sample.")
	var wrapped := DATA._sample_right_arm_data(loop, 1.25)
	var first_cycle := DATA._sample_right_arm_data(loop, 0.25)
	_check(wrapped.shoulder == first_cycle.shoulder and wrapped.raw_sword == first_cycle.raw_sword, "Arm data and raw sword must share loop wrapping.")
	var v1 := DATA._decode_clip("idle", _analytic_clip(), 1)
	_check(DATA._sample_right_arm_data(v1, 0.25).is_empty(), "Even an arm-shaped v1 payload must not become authored-arm playback.")


func _test_shared_clock() -> void:
	var timing := {"windup_seconds": 0.6, "active_seconds": 0.3, "hit_seconds": 0.12, "recovery_seconds": 0.65}
	var before := timing.duplicate(true)
	for paired in [false, true]:
		var hit := 0.145 if paired else 0.055
		var active_end := 0.30 if paired else 0.16
		for charge in [0.0, 1.0]:
			_check(is_equal_approx(DATA.authored_attack_time(timing, "windup", 0.22, charge, paired), 0.6), "Shared clock must retain the windup boundary.")
			_check(is_equal_approx(DATA.authored_attack_time(timing, "active", hit, charge, paired), 0.72), "Both combat variants must reach the authored contact at their real hit timestamp.")
			_check(is_equal_approx(DATA.authored_attack_time(timing, "active", active_end, charge, paired), DATA.authored_attack_time(timing, "recovery", 0.0, charge, paired)), "Shared clock must retain the active/recovery boundary.")
			_check(is_equal_approx(DATA.authored_attack_time(timing, "recovery", lerpf(0.47, 0.68, charge), charge, paired), 1.55), "Shared clock must retain the full recovery endpoint.")
		var previous := -1.0
		for index in range(301):
			var current := DATA.authored_attack_time(timing, "active", active_end * float(index) / 300.0, 0.0, paired)
			_check(current >= previous and current <= 0.900001, "Shared active clock must remain monotone and bounded.")
			previous = current
		var epsilon := 0.000001
		var contact := DATA.authored_attack_time(timing, "active", hit, 0.0, paired)
		var before_slope := (contact - DATA.authored_attack_time(timing, "active", hit - epsilon, 0.0, paired)) / epsilon
		var after_slope := (DATA.authored_attack_time(timing, "active", hit + epsilon, 0.0, paired) - contact) / epsilon
		_check(absf(before_slope - after_slope) < 0.001, "Extracting the clock must preserve the smooth contact derivative.")
	_check(timing == before, "Shared clock conversion must not mutate timing metadata.")
	_check(is_nan(DATA.authored_attack_time({}, "active", 0.1, 0.0, true)), "Missing timing must not create a valid authored time.")


func _analytic_clip(looped: bool = false) -> Dictionary:
	# Three analytical transformations of the preserved source rest chain.
	# Not a video-derived animation or a Windows provenance fixture.
	var sword: Array = []
	var shield: Array = []
	var joints: Array = []
	for index in range(3):
		var angle := 0.0 if index == 0 or (looped and index == 2) else PI * 0.5 * index
		var pose := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
		var q := pose.basis.get_rotation_quaternion()
		var time := float(index) / 2.0
		sword.append({"time_seconds": time, "position": _array(pose.origin), "rotation_xyzw": [q.x, q.y, q.z, q.w]})
		shield.append({"time_seconds": time, "position": [0, 0, 0], "rotation_xyzw": [0, 0, 0, 1]})
		joints.append({"time_seconds": time, "shoulder": _array(pose * ARM.REST_SHOULDER), "elbow": _array(pose * ARM.REST_ELBOW), "wrist": _array(pose * ARM.REST_WRIST)})
	return {"kind": "locomotion", "duration_seconds": 1.0, "loop": looped, "tracks": {"sword": sword, "shield": shield}, "right_arm": joints}


func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
