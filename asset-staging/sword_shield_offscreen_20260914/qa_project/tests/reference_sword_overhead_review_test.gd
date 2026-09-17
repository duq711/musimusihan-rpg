extends SceneTree
## Harness checks never invent a Windows clip. Optional actual delivery checks
## run only when OVERHEAD_REVIEW_MANIFEST names a received review file.

const DATA := preload("res://tests/reference_sword_overhead_review_data.gd")
const PREVIEW := preload("res://tests/reference_sword_overhead_review_preview.gd")
const PRODUCTION := preload("res://scripts/reference_sword_motion.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sources := PREVIEW.source_hashes()
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var original_pause := paused
	var available := PRODUCTION.is_available()
	var load_error := PRODUCTION.get_load_error()
	_check(DATA.FPS == 60 and DATA.FRAME_COUNT == 94 and is_equal_approx(DATA.frame_time(93), 1.55), "Single overhead review must retain authored 1.55 seconds at 60 Hz.")
	_check(DATA.frame_time(0) == 0.0 and is_equal_approx(DATA.frame_time(60), 1.0), "Review clock must not remap seconds through combat phases.")
	_check(not bool(DATA.decode_review({}).ok), "Missing review data must fail explicitly.")
	_check(not bool(DATA.decode_review({"schema_version": 1, "status": "authored_windows_output"}).ok), "Completed-delivery status must not be accepted as a single-clip review.")
	_check(not bool(DATA.read_review("").ok), "Missing external review path must fail without fallback.")
	_check(not bool(DATA.read_review(ProjectSettings.globalize_path(PRODUCTION.MANIFEST_PATH)).ok), "Review harness must not reinterpret the production manifest.")
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	_check(PREVIEW.prepare_fixture(fixture), "Review must instantiate actual production sword, shield, and original static-grip arm.")
	await process_frame
	_check(viewport.own_world_3d and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "Review must isolate rendering and disable automatic hardware input.")
	var state := PREVIEW.gameplay_state(player)
	var rejected := PREVIEW.apply_review_pose(player, Transform3D.IDENTITY, Transform3D.IDENTITY, {})
	_check(not bool(rejected.get("finite", true)) and PREVIEW.gameplay_state(player) == state, "Absent authored joints must be rejected before changing the player.")
	var review_path := OS.get_environment("OVERHEAD_REVIEW_MANIFEST").strip_edges()
	var checked_delivery := not review_path.is_empty()
	if checked_delivery:
		var review := DATA.read_review(review_path)
		_check(bool(review.get("ok", false)), "Received overhead review must validate: " + str(review.get("error", "")))
		if bool(review.get("ok", false)):
			for frame in range(DATA.FRAME_COUNT):
				var time := DATA.frame_time(frame)
				var metrics := PREVIEW.apply_review_pose(player, DATA.sample(review, time, "sword"), DATA.sample(review, time, "shield"), DATA.sample_right_arm(review, time))
				_check(bool(metrics.get("finite", false)) and float(metrics.get("grip_error", 1)) < 0.00001, "Received pivot must preserve the actual glove's sword grip at frame %d." % frame)
				_check(float(metrics.get("authored_wrist_error", 1)) < DATA.WRIST_TOLERANCE_METERS, "Received wrist must match T_sword * REST_WRIST within 1 mm at frame %d." % frame)
				_check(float(metrics.get("authored_joint_fit_error", 1)) < DATA.WRIST_TOLERANCE_METERS, "Actual original arm meshes must follow authored shoulder/elbow at frame %d." % frame)
				_check(not bool(metrics.get("arm_length_outside_source_range", true)), "Received original-arm lengths must stay within +/-1%% at frame %d." % frame)
				_check(PREVIEW.gameplay_state(player) == state, "Authored-time playback must preserve gameplay clocks, resources, camera, equipment, and mesh resources.")
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor and paused == original_pause, "Single-clip review must preserve original expedition, cursor, and pause.")
	_check(PRODUCTION.is_available() == available and PRODUCTION.get_load_error() == load_error and PREVIEW.source_hashes() == sources, "Review data must never install or replace production motion data.")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD OVERHEAD REVIEW %s: isolated harness, original meshes, authored 1.55s clock, strict missing-data rejection; actual_delivery_checked=%s" % ["PASS" if failures.is_empty() else "FAIL", str(checked_delivery)])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
