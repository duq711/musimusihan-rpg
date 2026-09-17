extends RefCounted
## Review-only decoder. It never writes the game manifest or populates the
## production loader's static clip cache.

const PRODUCTION := preload("res://scripts/reference_sword_motion.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const STATUS := "authored_windows_review_output"
const DURATION := 1.55
const FPS := 60
const FRAME_COUNT := 94
const WRIST_TOLERANCE_METERS := 0.001
const UPPER_LENGTH_METERS := 0.34
const FOREARM_LENGTH_METERS := 0.26
const LENGTH_RELATIVE_TOLERANCE := 0.01


static func read_review(path: String) -> Dictionary:
	if path.is_empty() or not path.is_absolute_path() or not FileAccess.file_exists(path):
		return _failure("An existing absolute review JSON path is required.")
	if path == ProjectSettings.globalize_path(PRODUCTION.MANIFEST_PATH):
		return _failure("The production motion manifest is not a single-clip review input.")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result := decode_review(parsed)
	if bool(result.get("ok", false)):
		result["input_path"] = path
		result["input_sha256"] = FileAccess.get_sha256(path)
	return result


static func decode_review(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return _failure("Review JSON must contain an object.")
	var data: Dictionary = value
	if not data.has_all(["schema_version", "status", "reference_video_url", "source", "coordinate_system", "camera", "provenance", "clips", "right_arm"]):
		return _failure("Incomplete review metadata or missing explicit right_arm payload.")
	if int(data.get("schema_version", 0)) != 1 or str(data.get("status", "")) != STATUS:
		return _failure("Only explicitly labeled Windows review output is accepted.")
	if str(data.reference_video_url) != "https://youtu.be/sU7jk2OQlgc":
		return _failure("Review must identify the agreed reference video.")
	var source: Variant = data.get("source")
	if not source is Dictionary or str(source.get("godot_model_sha256", "")) != PRODUCTION.SOURCE_SHA256:
		return _failure("Review source must match the preserved static glove/sword hash.")
	var provenance: Variant = data.get("provenance")
	if not provenance is Dictionary or str(provenance.get("execution_os", "")) != "Windows" or int(provenance.get("exit_code", -1)) != 0:
		return _failure("Successful Windows provenance metadata is required.")
	var coordinates: Variant = data.get("coordinate_system")
	if not coordinates is Dictionary or str(coordinates.get("space", "")) != "godot_camera_local_x_right_y_up_minus_z_forward" or str(coordinates.get("quaternion_order", "")) != "xyzw" or str(coordinates.get("transform_semantics", "")) != "absolute_pivot_local_to_camera":
		return _failure("Review pivot coordinates must use the existing camera-local contract.")
	if str(coordinates.get("units", "")) != "meters" or str(coordinates.get("position_order", "")) != "xyz":
		return _failure("Review positions must use camera-local xyz meters.")
	var camera: Variant = data.camera
	if not camera is Dictionary or float(camera.get("vertical_fov_degrees", 0)) != 76.0 or not PRODUCTION._numeric_array_matches(camera.get("aspect_ratio"), [16, 9]) or camera.get("animated") != false:
		return _failure("Review camera must be fixed 76-degree vertical FOV and 16:9.")
	var clips: Variant = data.get("clips")
	if not clips is Dictionary or clips.size() != 1 or not clips.has("overhead"):
		return _failure("This isolated review accepts exactly one overhead clip.")
	var raw: Variant = clips.overhead
	if not raw is Dictionary or str(raw.get("kind", "")) != "attack" or bool(raw.get("loop", true)):
		return _failure("Overhead must be a non-looping attack clip.")
	var duration := float(raw.get("duration_seconds", 0.0))
	var rate := float(raw.get("nominal_sample_hz", 0.0))
	if not is_finite(duration) or absf(duration - DURATION) > 0.00001 or not is_finite(rate) or rate < FPS:
		return _failure("Review duration must be 1.55 seconds with at least 60 Hz samples.")
	# Reuse the production rigid-transform checks, without calling its loader.
	var clip := PRODUCTION._decode_clip("overhead", raw)
	if clip.is_empty() or not clip.tracks.has("sword") or not clip.tracks.has("shield"):
		return _failure("Both complete finite sword/shield tracks and attack timing are required.")
	for track: String in ["sword", "shield"]:
		var frames: Array = clip.tracks[track]
		for index in range(1, frames.size()):
			if float(frames[index].time_seconds) - float(frames[index - 1].time_seconds) > 1.0 / rate + 0.00001:
				return _failure("Review track has a gap beyond its declared sample rate: " + track)
	var raw_arm: Variant = data.get("right_arm")
	var sword_frames: Array = clip.tracks.sword
	var shield_frames: Array = clip.tracks.shield
	if not raw_arm is Array or raw_arm.size() != sword_frames.size() or raw_arm.size() != shield_frames.size():
		return _failure("Explicit right_arm joints must share every sword/shield sample timestamp.")
	var arm_frames: Array[Dictionary] = []
	for index in range(raw_arm.size()):
		var entry: Variant = raw_arm[index]
		if not entry is Dictionary:
			return _failure("Every right_arm sample must be an object.")
		if not entry.get("time_seconds") is float and not entry.get("time_seconds") is int:
			return _failure("A right_arm sample is missing its numeric time.")
		var time := float(entry.time_seconds)
		if not is_finite(time) or absf(time - float(sword_frames[index].time_seconds)) > 0.00001 or absf(time - float(shield_frames[index].time_seconds)) > 0.00001:
			return _failure("A right_arm sample timestamp differs from sword/shield tracks.")
		var decoded := {"time_seconds": time}
		for joint: String in ["shoulder", "elbow", "wrist"]:
			if not PRODUCTION._numeric_array(entry.get(joint), 3):
				return _failure("Every authored right_arm sample needs finite shoulder/elbow/wrist positions.")
			var coordinates_value: Array = entry[joint]
			decoded[joint] = Vector3(coordinates_value[0], coordinates_value[1], coordinates_value[2])
		var shoulder: Vector3 = decoded.shoulder
		var elbow: Vector3 = decoded.elbow
		var wrist: Vector3 = decoded.wrist
		var sword_pose: Transform3D = sword_frames[index].transform
		if wrist.distance_to(sword_pose * ARM.REST_WRIST) >= WRIST_TOLERANCE_METERS:
			return _failure("Authored wrist must agree with the actual glove within 1 mm at sample %d." % index)
		if absf(shoulder.distance_to(elbow) - UPPER_LENGTH_METERS) > UPPER_LENGTH_METERS * LENGTH_RELATIVE_TOLERANCE or absf(elbow.distance_to(wrist) - FOREARM_LENGTH_METERS) > FOREARM_LENGTH_METERS * LENGTH_RELATIVE_TOLERANCE:
			return _failure("Authored arm lengths exceed the declared +/-1%% tolerance at sample %d." % index)
		arm_frames.append(decoded)
	return {"ok": true, "clip": clip, "declared_provenance": provenance.duplicate(true),
		"right_arm": arm_frames,
		"review_status": STATUS, "arm_playback": "authored_right_arm_joints_on_original_meshes",
		"incomplete_delivery": true, "gameplay_timing_remapped": false}


static func frame_time(frame: int) -> float:
	return clampf(float(frame) / FPS, 0.0, DURATION)


static func sample(review: Dictionary, time_seconds: float, track: String) -> Transform3D:
	if not bool(review.get("ok", false)) or not is_finite(time_seconds):
		return Transform3D.IDENTITY
	var frames: Array = review.clip.tracks.get(track, [])
	if frames.is_empty():
		return Transform3D.IDENTITY
	var time := clampf(time_seconds, 0.0, DURATION)
	if time <= 0.0: return frames[0].transform
	if time >= DURATION: return frames[-1].transform
	var lower := 0
	var upper := frames.size() - 1
	while upper - lower > 1:
		var middle := (lower + upper) / 2
		if float(frames[middle].time_seconds) <= time: lower = middle
		else: upper = middle
	var start: Dictionary = frames[lower]
	var end: Dictionary = frames[upper]
	var weight := (time - float(start.time_seconds)) / (float(end.time_seconds) - float(start.time_seconds))
	return (start.transform as Transform3D).interpolate_with(end.transform, weight)


static func sample_right_arm(review: Dictionary, time_seconds: float) -> Dictionary:
	if not bool(review.get("ok", false)) or not is_finite(time_seconds):
		return {}
	var frames: Array = review.get("right_arm", [])
	if frames.is_empty(): return {}
	var time := clampf(time_seconds, 0.0, DURATION)
	if time <= 0.0: return frames[0].duplicate()
	if time >= DURATION: return frames[-1].duplicate()
	var lower := 0
	var upper := frames.size() - 1
	while upper - lower > 1:
		var middle := (lower + upper) / 2
		if float(frames[middle].time_seconds) <= time: lower = middle
		else: upper = middle
	var weight := (time - float(frames[lower].time_seconds)) / (float(frames[upper].time_seconds) - float(frames[lower].time_seconds))
	var result := {"time_seconds": time}
	for joint: String in ["shoulder", "elbow", "wrist"]:
		result[joint] = (frames[lower][joint] as Vector3).lerp(frames[upper][joint], weight)
	return result


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "incomplete_delivery": true}
