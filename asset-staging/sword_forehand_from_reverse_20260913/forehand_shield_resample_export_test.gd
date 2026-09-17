extends SceneTree
const MOTION := preload("res://scripts/reference_sword_motion.gd")
const BASE := "res://../asset-staging/sword_forehand_from_reverse_20260913/"

func _init() -> void:
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"))
	var decoded := MOTION._decode_manifest(original)
	assert(bool(decoded.ok))
	MOTION._adopt_decoded_delivery(decoded, "authoring_baseline")
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(BASE + "forehand_timeline.json"))
	var result: Array = []
	for row: Dictionary in rows:
		var time := float(row.time_seconds)
		var pose := MOTION.sample("right_diagonal", time, "shield")
		var q := pose.basis.get_rotation_quaternion()
		result.append({"time_seconds": time, "position": [pose.origin.x, pose.origin.y, pose.origin.z], "rotation_xyzw": [q.x,q.y,q.z,q.w]})
	var out := FileAccess.open(BASE + "shield_samples.json", FileAccess.WRITE)
	assert(out != null)
	out.store_string(JSON.stringify(result))
	out.close()
	print("FOREHAND SHIELD RESAMPLE EXPORT PASS: baseline same-time shield curve sampled for synchronized clip data")
	quit()
