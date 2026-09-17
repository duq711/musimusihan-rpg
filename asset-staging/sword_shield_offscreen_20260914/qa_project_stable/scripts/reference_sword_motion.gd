extends RefCounted
class_name ReferenceSwordMotion
## Authored camera-space samples (MacBook production; legacy Windows supported). Presentation only: never advances combat,
## spends stamina, moves the character, or changes camera-owned aim.

const MANIFEST_PATH := "res://assets/animations/reference_sword_motion/motion_manifest.json"
const PARTIAL_MANIFEST_PATH := "res://assets/animations/reference_sword_motion/overhead_manifest.json"
const SOURCE_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const REQUIRED_CLIPS := ["run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"]
const RIGHT_ARM_REQUIRED_CLIPS := ["idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"]
const ATTACK_CLIPS := ["right_diagonal", "left_reverse", "overhead"]
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const WRIST_TOLERANCE_METERS := 0.001
const ARM_LENGTH_RELATIVE_TOLERANCE := 0.01
const SAMPLE_TIME_TOLERANCE := 0.0000001

static var _loaded := false
static var _clips: Dictionary = {}
static var _load_error := ""
static var _right_arm_available := false
static var _full_delivery_available := false
static var _delivery_scope: Dictionary = {"kind": "none", "clips": [], "schema_version": 0,
	"manifest_path": "", "full_delivery_available": false, "right_arm_available": false}


static func is_available() -> bool:
	_ensure_loaded()
	return not _clips.is_empty()


static func has_clip(clip: String) -> bool:
	_ensure_loaded()
	return _clips.has(clip)


static func has_track(clip: String, track: String = "sword") -> bool:
	_ensure_loaded()
	return _clips.has(clip) and (_clips[clip].tracks as Dictionary).has(track)


static func right_arm_available() -> bool:
	_ensure_loaded()
	return _right_arm_available


static func has_right_arm(clip: String) -> bool:
	return right_arm_available() and _clips.has(clip) and bool(_clips[clip].get("right_arm_available", false))


static func full_delivery_available() -> bool:
	_ensure_loaded()
	return _full_delivery_available


static func get_delivery_scope() -> Dictionary:
	_ensure_loaded()
	return _delivery_scope.duplicate(true)


static func clip_metadata(clip: String) -> Dictionary:
	_ensure_loaded()
	if not _clips.has(clip):
		return {}
	var result: Dictionary = (_clips[clip] as Dictionary).duplicate()
	result.erase("tracks")
	result.erase("right_arm")
	return result.duplicate(true)


static func get_load_error() -> String:
	_ensure_loaded()
	return _load_error


static func sample(clip: String, time_seconds: float, track: String = "sword") -> Transform3D:
	if not has_track(clip, track) or not is_finite(time_seconds):
		return Transform3D.IDENTITY
	return _sample_clip(_clips[clip], time_seconds, track)


static func _sample_clip(data: Dictionary, time_seconds: float, track: String) -> Transform3D:
	var duration: float = data.duration_seconds
	var looped := bool(data.loop)
	var time := fposmod(time_seconds, duration) if looped else clampf(time_seconds, 0.0, duration)
	var samples: Array = data.tracks[track]
	# Keep exact authored endpoints. A positive whole loop addresses its closing
	# sample; neighboring samples below still wrap around the same physical seam.
	if time == 0.0:
		return samples[-1].transform if looped and time_seconds > 0.0 else samples[0].transform
	if time == duration:
		return samples[-1].transform
	var lower := 0
	var upper := samples.size() - 1
	while upper - lower > 1:
		var middle := (lower + upper) / 2
		if float(samples[middle].time_seconds) <= time:
			lower = middle
		else:
			upper = middle
	var before: Dictionary = samples[lower]
	var after: Dictionary = samples[upper]
	var a: Transform3D = before.transform
	var b: Transform3D = after.transform
	var a_time := float(before.time_seconds)
	var interval := float(after.time_seconds) - a_time
	if time == a_time:
		return a
	var amount := clampf((time - a_time) / interval, 0.0, 1.0)
	var pre: Dictionary = samples[maxi(lower - 1, 0)]
	var post: Dictionary = samples[mini(upper + 1, samples.size() - 1)]
	var pre_time := float(pre.time_seconds) - a_time
	var post_time := float(post.time_seconds) - a_time
	if looped and lower == 0:
		# The closing endpoint duplicates index 0; use the preceding unique
		# sample from the previous cycle, retaining its actual (possibly uneven) dt.
		pre = samples[samples.size() - 2]
		pre_time = float(pre.time_seconds) - duration - a_time
	if looped and upper == samples.size() - 1:
		post = samples[1]
		post_time = float(post.time_seconds) + duration - a_time
	var pre_pose: Transform3D = pre.transform
	var post_pose: Transform3D = post.transform
	# Godot's time-aware cubics take B/pre-A/post-B times relative to A. For
	# nonloops, repeating the boundary pose at its boundary time clamps its
	# endpoint tangent to zero and agrees with holding the pose outside the clip.
	# Uneven explicit contact timestamps must not be treated as uniform frames.
	var position := a.origin.cubic_interpolate_in_time(b.origin, pre_pose.origin, post_pose.origin, amount, interval, pre_time, post_time)
	# Spherical Bezier tangents share the same angular velocity at each knot.
	# Godot's squad time interpolation visibly kinks at inserted, uneven hit keys.
	var qa: Quaternion = before.rotation
	var qb: Quaternion = after.rotation
	var va := _rotation_velocity(pre.rotation, qa, qb, -pre_time, interval)
	var vb := _rotation_velocity(qa, qb, post.rotation, interval, post_time - interval)
	var ca := qa * _rotation_exp(va * interval / 3.0)
	var cb := qb * _rotation_exp(-vb * interval / 3.0)
	var ab := qa.slerp(ca, amount)
	var bc := ca.slerp(cb, amount)
	var cd := cb.slerp(qb, amount)
	var rotation := ab.slerp(bc, amount).slerp(bc.slerp(cd, amount), amount).normalized()
	return Transform3D(Basis(rotation), position)


static func _rotation_log(q: Quaternion) -> Vector3:
	if q.w < 0.0: q = -q
	var v := Vector3(q.x, q.y, q.z)
	return v * (2.0 * atan2(v.length(), q.w) / v.length()) if v.length() > 0.00000001 else Vector3.ZERO

static func _rotation_exp(v: Vector3) -> Quaternion:
	return Quaternion(v.normalized(), v.length()) if v.length() > 0.00000001 else Quaternion.IDENTITY

static func _rotation_velocity(a: Quaternion, b: Quaternion, c: Quaternion, before: float, after: float) -> Vector3:
	if minf(before, after) <= 0.0000001: return Vector3.ZERO
	return (-_rotation_log(b.inverse() * a) / before * after + _rotation_log(b.inverse() * c) / after * before) / (before + after)


static func sample_right_arm(clip: String, time_seconds: float) -> Dictionary:
	if not has_right_arm(clip) or not is_finite(time_seconds):
		return {}
	return _sample_right_arm_data(_clips[clip], time_seconds)


static func _sample_right_arm_data(data: Dictionary, time_seconds: float) -> Dictionary:
	if not bool(data.get("right_arm_available", false)) or not is_finite(time_seconds):
		return {}
	var frames: Array = data.right_arm
	var duration: float = data.duration_seconds
	var looped := bool(data.loop)
	var time := fposmod(time_seconds, duration) if looped else clampf(time_seconds, 0.0, duration)
	var exact := -1
	if time == 0.0:
		exact = frames.size() - 1 if looped and time_seconds > 0.0 else 0
	elif time == duration:
		exact = frames.size() - 1
	var lower := 0
	var upper := frames.size() - 1
	while exact < 0 and upper - lower > 1:
		var middle := (lower + upper) / 2
		if float(frames[middle].time_seconds) <= time: lower = middle
		else: upper = middle
	if exact < 0:
		for index in [lower, upper]:
			if absf(float(frames[index].time_seconds) - time) <= SAMPLE_TIME_TOLERANCE:
				exact = index
				break
	var result := {}
	if exact >= 0:
		result = (frames[exact] as Dictionary).duplicate()
		# Use the same exact source pivot, including the positive loop endpoint.
		result["raw_sword"] = data.tracks.sword[exact].transform
	else:
		var weight := (time - float(frames[lower].time_seconds)) / (float(frames[upper].time_seconds) - float(frames[lower].time_seconds))
		result["time_seconds"] = time
		for joint: String in ["shoulder", "elbow", "wrist"]:
			result[joint] = (frames[lower][joint] as Vector3).lerp(frames[upper][joint], weight)
		result["raw_sword"] = _sample_clip(data, time_seconds, "sword")
	result["exact_sample"] = exact >= 0
	# These vectors are interpolation input. The player owns the final wrist,
	# fixed-length IK and gameplay overlays; no length claim is made here.
	result["interpolated_joints_require_runtime_ik"] = exact < 0
	return result


static func retimed_attack(phase: String, elapsed: float, charge: float, variant: String, paired: bool, track: String = "sword") -> Transform3D:
	if not has_track(variant, track) or not ATTACK_CLIPS.has(variant):
		return Transform3D.IDENTITY
	return sample(variant, authored_attack_time(_clips[variant].timing, phase, elapsed, charge, paired), track)


static func authored_attack_time(timing: Dictionary, phase: String, elapsed: float, charge: float, paired: bool) -> float:
	# Pure shared clock conversion: no cache access, loading or state advance.
	if not is_finite(elapsed) or not is_finite(charge):
		return NAN
	for key: String in ["windup_seconds", "active_seconds", "hit_seconds", "recovery_seconds"]:
		if not _finite_number(timing.get(key)) or float(timing[key]) <= 0.0:
			return NAN
	if float(timing.hit_seconds) >= float(timing.active_seconds):
		return NAN
	var windup: float = timing.windup_seconds
	var active: float = timing.active_seconds
	var hit: float = timing.hit_seconds
	var recovery: float = timing.recovery_seconds
	var time := 0.0
	match phase:
		"windup":
			time = windup * clampf(elapsed / 0.22, 0.0, 1.0)
		"active":
			var runtime_hit := 0.145 if paired else 0.055
			var runtime_active := 0.30 if paired else 0.16
			time = windup + _retime_active(elapsed, runtime_hit, runtime_active, hit, active)
		"recovery":
			time = windup + active + recovery * clampf(elapsed / lerpf(0.47, 0.68, clampf(charge, 0.0, 1.0)), 0.0, 1.0)
	return time


static func _retime_active(elapsed: float, runtime_hit: float, runtime_end: float, authored_hit: float, authored_end: float) -> float:
	if elapsed <= 0.0:
		return 0.0
	if elapsed >= runtime_end:
		return authored_end
	if elapsed == runtime_hit:
		return authored_hit
	var before_duration := runtime_hit
	var after_duration := runtime_end - runtime_hit
	var before_slope := authored_hit / before_duration
	var after_slope := (authored_end - authored_hit) / after_duration
	# Three-knot PCHIP: both intervals share this weighted harmonic derivative
	# at contact. Positive secants keep time moving forward through the exact
	# gameplay hit instead of abruptly switching between two playback speeds.
	var before_weight := 2.0 * after_duration + before_duration
	var after_weight := after_duration + 2.0 * before_duration
	var contact_slope := (before_weight + after_weight) / (before_weight / before_slope + after_weight / after_slope)
	var start_slope := ((2.0 * before_duration + after_duration) * before_slope - before_duration * after_slope) / runtime_end
	var end_slope := ((2.0 * after_duration + before_duration) * after_slope - after_duration * before_slope) / runtime_end
	start_slope = clampf(start_slope, 0.0, 3.0 * before_slope)
	end_slope = clampf(end_slope, 0.0, 3.0 * after_slope)
	if elapsed < runtime_hit:
		return _scalar_hermite(0.0, authored_hit, start_slope, contact_slope, before_duration, elapsed / before_duration)
	return _scalar_hermite(authored_hit, authored_end, contact_slope, end_slope, after_duration, (elapsed - runtime_hit) / after_duration)


static func _scalar_hermite(a: float, b: float, a_slope: float, b_slope: float, interval: float, amount: float) -> float:
	var t2 := amount * amount
	var t3 := t2 * amount
	return (2.0 * t3 - 3.0 * t2 + 1.0) * a + (t3 - 2.0 * t2 + amount) * interval * a_slope + (-2.0 * t3 + 3.0 * t2) * b + (t3 - t2) * interval * b_slope


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# An absent delivery is expected while Windows authoring is in progress.
	# No retry, disk read or diagnostic spam is performed from per-frame calls.
	var full_exists := FileAccess.file_exists(MANIFEST_PATH)
	var path := MANIFEST_PATH if full_exists else PARTIAL_MANIFEST_PATH
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_load_error = "Cannot read reference sword motion manifest."
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	# An invalid or unreadable full file must remain a visible failure. Only a
	# genuinely absent full file permits the explicit partial fallback.
	var decoded := _decode_manifest(parsed) if full_exists else _decode_partial_manifest(parsed)
	if not bool(decoded.get("ok", false)):
		_load_error = str(decoded.error)
		return
	_adopt_decoded_delivery(decoded, path)


static func _adopt_decoded_delivery(decoded: Dictionary, path: String) -> void:
	_clips = decoded.clips
	_right_arm_available = bool(decoded.right_arm_available)
	_full_delivery_available = bool(decoded.get("full_delivery_available", false))
	var names: Array = _clips.keys()
	names.sort()
	_delivery_scope = {"kind": str(decoded.get("kind", "none")), "clips": names,
		"schema_version": int(decoded.schema_version), "manifest_path": path,
		"full_delivery_available": _full_delivery_available,
		"right_arm_available": _right_arm_available}


static func _decode_manifest(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _decode_failure("Reference sword motion manifest must contain a JSON object.")
	var manifest: Dictionary = value
	var raw_version: Variant = manifest.get("schema_version")
	if not _finite_number(raw_version) or float(raw_version) not in [1.0, 2.0] or str(manifest.get("status", "")) not in ["authored_windows_output", "authored_macos_output"]:
		return _decode_failure("Reference sword motion manifest is not a supported authored delivery.")
	var version := int(raw_version)
	var metadata_error := _metadata_error(manifest, version)
	if not metadata_error.is_empty():
		return _decode_failure(metadata_error)
	var raw_clips: Variant = manifest.get("clips")
	if not raw_clips is Dictionary:
		return _decode_failure("Reference sword motion clips are missing.")
	return _decode_clips(raw_clips, version)


static func _metadata_error(manifest: Dictionary, version: int) -> String:
	var source: Variant = manifest.get("source")
	var coordinates: Variant = manifest.get("coordinate_system")
	var provenance: Variant = manifest.get("provenance")
	if not source is Dictionary or str(source.get("godot_model_sha256", "")) != SOURCE_SHA256:
		return "Reference sword motion source does not match the preserved static grip."
	if not provenance is Dictionary or str(provenance.get("execution_os", "")) != ("Darwin" if str(manifest.get("status", "")) == "authored_macos_output" else "Windows") or int(provenance.get("exit_code", -1)) != 0:
		return "Reference sword motion requires successful matching authoring provenance."
	if not coordinates is Dictionary or str(coordinates.get("space", "")) != "godot_camera_local_x_right_y_up_minus_z_forward" or str(coordinates.get("quaternion_order", "")) != "xyzw" or str(coordinates.get("transform_semantics", "")) != "absolute_pivot_local_to_camera":
		return "Reference sword motion coordinate contract does not match the player."
	if version == 2 and (str(coordinates.get("units", "")) != "meters" or str(coordinates.get("position_order", "")) != "xyz" or not _numeric_array_matches(coordinates.get("scale"), [1, 1, 1])):
		return "Version 2 requires camera-local xyz meters with unit scale."
	return ""


static func _decode_partial_manifest(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _decode_failure("Partial motion manifest must contain a JSON object.")
	var manifest: Dictionary = value
	if not _finite_number(manifest.get("schema_version")) or float(manifest.schema_version) != 2.0 or str(manifest.get("status", "")) != "authored_windows_partial_output":
		return _decode_failure("Partial motion requires explicitly labeled version 2 partial output.")
	if manifest.get("delivered_clips") != ["overhead"]:
		return _decode_failure("Partial output must declare exactly the delivered overhead clip.")
	if str(manifest.get("reference_video_url", "")) != "https://youtu.be/sU7jk2OQlgc":
		return _decode_failure("Partial output must identify the agreed reference video.")
	var raw_provenance: Variant = manifest.get("provenance")
	if not raw_provenance is Dictionary or not _finite_number(raw_provenance.get("exit_code")) or float(raw_provenance.exit_code) != 0.0 or raw_provenance.get("source_preserved") != true:
		return _decode_failure("Partial output requires successful source-preservation metadata.")
	var metadata_error := _metadata_error(manifest, 2)
	if not metadata_error.is_empty():
		return _decode_failure(metadata_error)
	var source: Dictionary = manifest.source
	if str(source.get("godot_model_path", "")) != "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb":
		return _decode_failure("Partial output must identify the preserved source model path.")
	var camera: Variant = manifest.get("camera")
	if not camera is Dictionary or not _finite_number(camera.get("vertical_fov_degrees")) or float(camera.vertical_fov_degrees) != 76.0 or not _numeric_array_matches(camera.get("aspect_ratio"), [16, 9]) or camera.get("animated") != false:
		return _decode_failure("Partial output must retain the fixed 76-degree 16:9 camera contract.")
	var raw_clips: Variant = manifest.get("clips")
	if not raw_clips is Dictionary or raw_clips.size() != 1 or not raw_clips.has("overhead"):
		return _decode_failure("Partial output must contain only its declared overhead clip.")
	var clip := _decode_clip("overhead", raw_clips.overhead, 2)
	if clip.is_empty() or str(clip.get("kind", "")) != "attack":
		return _decode_failure("Partial overhead requires valid matching sword, shield and right-arm samples.")
	return {"ok": true, "kind": "partial", "clips": {"overhead": clip},
		"schema_version": 2, "right_arm_available": true, "full_delivery_available": false}


static func _decode_clips(raw_clips: Dictionary, version: int) -> Dictionary:
	if version not in [1, 2]:
		return _decode_failure("Unsupported motion clip schema version.")
	var decoded := {}
	var required := RIGHT_ARM_REQUIRED_CLIPS if version == 2 else REQUIRED_CLIPS
	for clip: String in required:
		if not raw_clips.has(clip):
			return _decode_failure("Reference sword motion required clip is missing: " + clip)
	for clip: String in raw_clips:
		var data := _decode_clip(clip, raw_clips[clip], version)
		if data.is_empty():
			return _decode_failure("Invalid reference sword motion clip: " + clip)
		decoded[clip] = data
	var complete := true
	for clip: String in RIGHT_ARM_REQUIRED_CLIPS:
		if not decoded.has(clip): complete = false
	return {"ok": true, "kind": "full_v%d" % version, "clips": decoded, "schema_version": version,
		"right_arm_available": version == 2, "full_delivery_available": complete}


static func _decode_failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "right_arm_available": false, "full_delivery_available": false}


static func _decode_clip(clip: String, value: Variant, schema_version: int = 1) -> Dictionary:
	if not value is Dictionary:
		return {}
	var data: Dictionary = value
	if schema_version == 2 and (not _finite_number(data.get("duration_seconds")) or not data.get("loop") is bool):
		return {}
	var duration := float(data.get("duration_seconds", 0.0))
	if not is_finite(duration) or duration <= 0.0 or not data.get("tracks") is Dictionary:
		return {}
	var looped := bool(data.get("loop", false))
	if REQUIRED_CLIPS.has(clip) and looped != (clip in ["run", "air"]):
		return {}
	if schema_version == 2 and clip == "idle" and looped:
		return {}
	var tracks: Dictionary = data.tracks
	var arm_required := schema_version == 2 and RIGHT_ARM_REQUIRED_CLIPS.has(clip)
	if not tracks.has("sword") or (arm_required and not tracks.has("shield")):
		return {}
	var decoded := {}
	for track: String in tracks:
		if not track in ["sword", "shield"] or not tracks[track] is Array:
			return {}
		var samples: Array = tracks[track]
		if samples.size() < 2:
			return {}
		var frames: Array = []
		var previous_time := -1.0
		var previous_rotation := Quaternion.IDENTITY
		for entry: Variant in samples:
			if not entry is Dictionary:
				return {}
			if schema_version == 2 and not _finite_number(entry.get("time_seconds")):
				return {}
			var time := float(entry.get("time_seconds", -1.0))
			var position: Variant = entry.get("position")
			var rotation: Variant = entry.get("rotation_xyzw")
			if not is_finite(time) or time < 0.0 or time <= previous_time or time > duration + 0.00001 or not _numeric_array(position, 3) or not _numeric_array(rotation, 4):
				return {}
			var origin := Vector3(position[0], position[1], position[2])
			var quaternion := Quaternion(rotation[0], rotation[1], rotation[2], rotation[3])
			if absf(quaternion.length() - 1.0) > 0.001:
				return {}
			quaternion = quaternion.normalized()
			if not frames.is_empty() and previous_rotation.dot(quaternion) < 0.0:
				if schema_version == 2:
					return {}
				quaternion = -quaternion
			frames.append({"time_seconds": time, "transform": Transform3D(Basis(quaternion), origin), "rotation": quaternion})
			previous_time = time
			previous_rotation = quaternion
		if absf(float(frames[0].time_seconds)) > 0.00001 or absf(previous_time - duration) > 0.00001:
			return {}
		if looped:
			var start: Transform3D = frames[0].transform
			var end: Transform3D = frames[-1].transform
			if start.origin.distance_to(end.origin) > 0.001 or start.basis.get_rotation_quaternion().angle_to(end.basis.get_rotation_quaternion()) > 0.002:
				return {}
		decoded[track] = frames
	var result := {"duration_seconds": duration, "loop": looped, "tracks": decoded, "kind": str(data.get("kind", "")), "right_arm_available": false}
	if ATTACK_CLIPS.has(clip):
		var timing: Variant = data.get("timing")
		if not timing is Dictionary:
			return {}
		for key: String in ["windup_seconds", "active_seconds", "hit_seconds", "recovery_seconds"]:
			if schema_version == 2 and not _finite_number(timing.get(key)):
				return {}
			var number := float(timing.get(key, 0.0))
			if not is_finite(number) or number <= 0.0:
				return {}
		if float(timing.hit_seconds) >= float(timing.active_seconds) or absf(float(timing.windup_seconds) + float(timing.active_seconds) + float(timing.recovery_seconds) - duration) > 0.00001:
			return {}
		result["timing"] = timing.duplicate(true)
	if schema_version == 2 and (arm_required or data.has("right_arm")):
		var arm := _decode_right_arm(data.get("right_arm"), decoded, looped)
		if arm.is_empty():
			return {}
		result["right_arm"] = arm
		result["right_arm_available"] = true
	return result


static func _decode_right_arm(value: Variant, tracks: Dictionary, looped: bool) -> Array[Dictionary]:
	var decoded: Array[Dictionary] = []
	if not value is Array or not tracks.has_all(["sword", "shield"]):
		return decoded
	var sword: Array = tracks.sword
	var shield: Array = tracks.shield
	if sword.size() < 2 or value.size() != sword.size() or value.size() != shield.size():
		return decoded
	for index in range(value.size()):
		var entry: Variant = value[index]
		if not entry is Dictionary or not _finite_number(entry.get("time_seconds")):
			return []
		var time := float(entry.time_seconds)
		if absf(time - float(sword[index].time_seconds)) > SAMPLE_TIME_TOLERANCE or absf(time - float(shield[index].time_seconds)) > SAMPLE_TIME_TOLERANCE:
			return []
		var frame := {"time_seconds": float(sword[index].time_seconds)}
		for joint: String in ["shoulder", "elbow", "wrist"]:
			if not _numeric_array(entry.get(joint), 3):
				return []
			var numbers: Array = entry[joint]
			frame[joint] = Vector3(numbers[0], numbers[1], numbers[2])
		var shoulder: Vector3 = frame.shoulder
		var elbow: Vector3 = frame.elbow
		var wrist: Vector3 = frame.wrist
		var sword_pose: Transform3D = sword[index].transform
		if wrist.distance_to(sword_pose * ARM.REST_WRIST) >= WRIST_TOLERANCE_METERS:
			return []
		if absf(shoulder.distance_to(elbow) - ARM.REST_UPPER_LENGTH) > ARM.REST_UPPER_LENGTH * ARM_LENGTH_RELATIVE_TOLERANCE or absf(elbow.distance_to(wrist) - ARM.REST_FOREARM_LENGTH) > ARM.REST_FOREARM_LENGTH * ARM_LENGTH_RELATIVE_TOLERANCE:
			return []
		decoded.append(frame)
	if looped:
		for joint: String in ["shoulder", "elbow", "wrist"]:
			if (decoded[0][joint] as Vector3).distance_to(decoded[-1][joint]) >= WRIST_TOLERANCE_METERS:
				return []
	return decoded


static func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


static func _numeric_array(value: Variant, size: int) -> bool:
	if not value is Array or value.size() != size:
		return false
	for number: Variant in value:
		if not number is float and not number is int:
			return false
		if not is_finite(float(number)):
			return false
	return true


static func _numeric_array_matches(value: Variant, expected: Array) -> bool:
	# JSON decodes numbers as floats. Array equality also compares element
	# types, so valid [1.0, 1.0, 1.0] must be checked by its numeric values.
	if not _numeric_array(value, expected.size()):
		return false
	for index in expected.size():
		if float(value[index]) != float(expected[index]):
			return false
	return true
