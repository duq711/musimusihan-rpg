extends SceneTree
## Explicit in-memory parser fixtures only. No Windows action was executed,
## no manifest is written by this test. Optional OVERHEAD_PARTIAL_MANIFEST
## validates a received file read-only, without adopting it into the cache.

const DATA := preload("res://scripts/reference_sword_motion.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
var failures: Array[String] = []
var received_file_report := {"checked": false, "execution_verified": false}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := {"loaded": DATA._loaded, "clips": DATA._clips, "error": DATA._load_error,
		"arm": DATA._right_arm_available, "complete": DATA._full_delivery_available, "scope": DATA._delivery_scope}
	var hashes := _manifest_hashes()
	var fixture := _analytical_partial()
	_test_rejections(fixture)
	var json_fixture: Variant = JSON.parse_string(JSON.stringify(fixture))
	_check(json_fixture is Dictionary and bool(DATA._decode_partial_manifest(json_fixture).get("ok", false)), "A valid partial fixture must survive real JSON parsing, including floating-point scale/aspect numeric arrays.")
	var decoded := DATA._decode_partial_manifest(fixture)
	_check(bool(decoded.get("ok", false)), "An explicitly partial analytical overhead must decode.")
	if bool(decoded.get("ok", false)):
		DATA._loaded = true
		DATA._load_error = ""
		DATA._adopt_decoded_delivery(decoded, "<in-memory analytical fixture; no execution>")
		_check(DATA.is_available() and DATA.right_arm_available(), "A valid partial fixture exposes its actual motion and arm availability.")
		_check(not DATA.full_delivery_available(), "One valid overhead must never report all eight clips complete.")
		_check(DATA.has_track("overhead", "sword") and DATA.has_track("overhead", "shield") and DATA.has_right_arm("overhead"), "Only the decoded overhead channels may be available.")
		for absent: String in ["idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse"]:
			_check(not DATA.has_clip(absent) and not DATA.has_track(absent) and not DATA.has_right_arm(absent) and DATA.sample_right_arm(absent, 0.2).is_empty(), "Partial loading must never fill in an absent clip: " + absent)
		var scope := DATA.get_delivery_scope()
		_check(scope.kind == "partial" and scope.clips == ["overhead"] and scope.schema_version == 2 and not scope.full_delivery_available and scope.right_arm_available, "Delivery scope must explicitly describe one partial v2 clip.")
		scope.clips.append("not_delivered")
		_check(DATA.get_delivery_scope().clips == ["overhead"], "Caller edits must not mutate cached delivery scope.")
		var sampled := DATA.sample_right_arm("overhead", 0.0)
		_check(bool(sampled.exact_sample) and (sampled.raw_sword as Transform3D).is_equal_approx(DATA.sample("overhead", 0.0)), "Partial sampling must preserve the existing exact-key and same-time sword contract.")
		var metadata := DATA.clip_metadata("overhead")
		_check(not metadata.has("tracks") and not metadata.has("right_arm"), "Lightweight metadata must not duplicate the sample arrays.")
		var contact_time := DATA.authored_attack_time(metadata.timing, "active", 0.145, 0.0, true)
		_check(DATA.retimed_attack("active", 0.145, 0.0, "overhead", true).is_equal_approx(DATA.sample("overhead", contact_time)), "Partial playback must reuse the existing shared attack clock.")
	DATA._loaded = original.loaded
	DATA._clips = original.clips
	DATA._load_error = original.error
	DATA._right_arm_available = original.arm
	DATA._full_delivery_available = original.complete
	DATA._delivery_scope = original.scope
	_check(DATA._loaded == original.loaded and DATA._clips == original.clips and DATA._load_error == original.error and DATA._right_arm_available == original.arm and DATA._full_delivery_available == original.complete and DATA._delivery_scope == original.scope, "Every original production cache field must be restored.")
	_check(_manifest_hashes() == hashes, "Neither full nor partial production manifest may be written by a parser test.")
	_test_optional_received_file()
	_check(DATA._loaded == original.loaded and DATA._clips == original.clips and DATA._load_error == original.error and DATA._right_arm_available == original.arm and DATA._full_delivery_available == original.complete and DATA._delivery_scope == original.scope, "Read-only received-file validation must not modify any production cache field.")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD PARTIAL DATA %s: analytical scope fixtures; optional received-file parser report=%s; no gameplay or Windows execution claim" % [("PASS" if failures.is_empty() else "FAIL"), JSON.stringify(received_file_report)])
	quit(0 if failures.is_empty() else 1)


func _test_optional_received_file() -> void:
	var path := OS.get_environment("OVERHEAD_PARTIAL_MANIFEST").strip_edges()
	if path.is_empty(): return
	_check(path.is_absolute_path() and FileAccess.file_exists(path), "OVERHEAD_PARTIAL_MANIFEST must name an existing absolute file path.")
	if not path.is_absolute_path() or not FileAccess.file_exists(path): return
	var before_hash := FileAccess.get_sha256(path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary, "Received partial file must be a JSON object.")
	if not parsed is Dictionary: return
	var decoded := DATA._decode_partial_manifest(parsed)
	received_file_report = {"checked": true, "path": path, "sha256": before_hash, "parser_ok": bool(decoded.get("ok", false)), "execution_verified": false, "gameplay_checked": false}
	_check(bool(decoded.get("ok", false)), "Received partial file must pass the real parser: " + str(decoded.get("error", "")))
	if bool(decoded.get("ok", false)):
		var clip: Dictionary = decoded.clips.overhead
		_check(decoded.clips.size() == 1 and is_equal_approx(float(clip.duration_seconds), 1.55), "Received iteration07 data must remain overhead-only and 1.55 seconds.")
		received_file_report["samples"] = clip.right_arm.size()
		var timing: Dictionary = clip.timing
		var time := DATA.authored_attack_time(timing, "active", 0.145, 0.0, true)
		var arm := DATA._sample_right_arm_data(clip, time)
		_check(bool(arm.get("exact_sample", false)), "Received overhead contact must address an explicit authored arm key.")
		_check((arm.raw_sword as Transform3D).is_equal_approx(DATA._sample_clip(clip, time, "sword")), "Received arm and sword must share the contact clock.")
	_check(FileAccess.get_sha256(path) == before_hash, "Received-file validation must preserve the file bytes.")


func _test_rejections(fixture: Dictionary) -> void:
	_check(not bool(DATA._decode_partial_manifest({}).ok), "Missing partial metadata must fail.")
	_check(not bool(DATA._decode_manifest(fixture).ok), "The full loader must not accept partial status.")
	_check(not bool(DATA._decode_clips(fixture.clips, 2).ok), "Full v2 validation must continue requiring all eight clips.")
	var invalid: Dictionary = fixture.duplicate(true)
	invalid.status = "authored_windows_review_output"
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "A review cannot silently become an applied partial delivery.")
	invalid = fixture.duplicate(true)
	invalid.status = "authored_windows_output"
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Full status cannot bypass the explicit partial contract.")
	invalid = fixture.duplicate(true)
	invalid.schema_version = 1
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Partial output must use v2 authored-arm samples.")
	invalid = fixture.duplicate(true)
	invalid.delivered_clips = ["overhead", "run"]
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Partial declaration must name exactly overhead.")
	invalid = fixture.duplicate(true)
	invalid.clips["run"] = invalid.clips.overhead.duplicate(true)
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Undeclared additional clips must not be registered.")
	invalid = fixture.duplicate(true)
	invalid.source.godot_model_sha256 = "incorrect"
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Source hash mismatch must fail.")
	invalid = fixture.duplicate(true)
	invalid.coordinate_system.units = "centimeters"
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Partial data must retain the exact camera-local meter contract.")
	invalid = fixture.duplicate(true)
	invalid.provenance.exit_code = []
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Malformed provenance must be rejected before numeric conversion.")
	invalid = fixture.duplicate(true)
	invalid.camera.animated = true
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "An animated camera must not be accepted as fixed camera-local data.")
	invalid = fixture.duplicate(true)
	invalid.clips.overhead.erase("right_arm")
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "A pivot-only partial clip must fail.")
	invalid = fixture.duplicate(true)
	invalid.clips.overhead.right_arm[0].wrist[0] += 0.002
	_check(not bool(DATA._decode_partial_manifest(invalid).ok), "Partial loading must retain the v2 wrist tolerance.")


func _analytical_partial() -> Dictionary:
	# Two identical source-rest frames are sufficient to isolate parser and
	# routing behavior. These are not an authored motion or Windows provenance.
	var pose := ARM.SOURCE_READY
	var q := pose.basis.get_rotation_quaternion()
	var pivots: Array = []
	var joints: Array = []
	for time in [0.0, 1.55]:
		pivots.append({"time_seconds": time, "position": _array(pose.origin), "rotation_xyzw": [q.x, q.y, q.z, q.w]})
		joints.append({"time_seconds": time, "shoulder": _array(pose * ARM.REST_SHOULDER), "elbow": _array(pose * ARM.REST_ELBOW), "wrist": _array(pose * ARM.REST_WRIST)})
	return {"schema_version": 2, "status": "authored_windows_partial_output",
		"delivered_clips": ["overhead"], "reference_video_url": "https://youtu.be/sU7jk2OQlgc",
		"source": {"godot_model_path": "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb", "godot_model_sha256": DATA.SOURCE_SHA256},
		"coordinate_system": {"space": "godot_camera_local_x_right_y_up_minus_z_forward", "units": "meters", "position_order": "xyz", "quaternion_order": "xyzw", "transform_semantics": "absolute_pivot_local_to_camera", "scale": [1, 1, 1]},
		"camera": {"vertical_fov_degrees": 76.0, "aspect_ratio": [16, 9], "animated": false},
		"provenance": {"execution_os": "Windows", "exit_code": 0, "source_preserved": true, "hostname": "ANALYTICAL_PARSER_FIXTURE_NO_EXECUTION"},
		"clips": {"overhead": {"kind": "attack", "duration_seconds": 1.55, "loop": false,
			"tracks": {"sword": pivots, "shield": pivots.duplicate(true)}, "right_arm": joints,
			"timing": {"windup_seconds": 0.6, "active_seconds": 0.3, "hit_seconds": 0.12, "recovery_seconds": 0.65}}}}


func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _manifest_hashes() -> Dictionary:
	var result := {}
	for path: String in [DATA.MANIFEST_PATH, DATA.PARTIAL_MANIFEST_PATH]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
