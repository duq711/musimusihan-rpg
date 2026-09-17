extends SceneTree
const DATA := preload("res://scripts/reference_sword_motion.gd")

func _init() -> void:
	var path := OS.get_environment("REFERENCE_SWORD_MOTION_QA_MANIFEST")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var decoded := DATA._decode_manifest(raw)
	if not bool(decoded.get("ok", false)):
		push_error(str(decoded.get("error", "candidate cannot decode")))
		quit(1)
		return
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/sword_cut_baseline_20260913.json"))
	for name: String in baseline.clips:
		if name != "right_diagonal" and raw.clips[name] != baseline.clips[name]:
			push_error("Candidate altered accepted clip: " + name)
			quit(1)
			return
	print("SWORD CUT CANDIDATE PASS: authored schema, joints and preserved other clips; no visual acceptance claim")
	quit()
