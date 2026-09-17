extends SceneTree
const CREEP := preload("res://scripts/creep_enemy.gd")
const REEL := preload("res://tests/creep_motion_reel.gd")
var failures: Array[String] = []
func _init() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
func run() -> void:
	if not CREEP.is_available():
		print("CREEP MOTION REEL TEST PASS: source-dependent checks SKIPPED (licensed asset missing)")
		quit()
		return
	var actor := CREEP.new()
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.move_speed = 2.2
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var transform := actor.transform
	var seen: Array[String] = []
	for segment: Dictionary in REEL.SEGMENTS:
		seen.append(segment.id)
		var changed := false
		REEL.sample(actor, segment.id, 0.0)
		var first: Array[Transform3D] = []
		for bone in actor.skeleton.get_bone_count(): first.append(actor.skeleton.get_bone_global_pose(bone))
		for step in ceili(float(segment.duration) * REEL.FPS):
			var pose := REEL.sample(actor, segment.id, float(step) / REEL.FPS)
			check(pose.clip == segment.id and pose.sample >= 0.0, "reel displays the labeled production clip")
			for bone in first.size(): changed = changed or not first[bone].is_equal_approx(actor.skeleton.get_bone_global_pose(bone))
		check(changed, "actual bones move in " + str(segment.id))
	check(seen == ["idle", "walk", "bite", "punch", "hit", "death"], "five gameplay clips and retained source death are included")
	check(is_equal_approx(REEL.sample(actor, "bite", 1.0).sample, 1.0), "bite contact retains production timing")
	check(is_equal_approx(REEL.sample(actor, "punch", 0.64).sample, 0.64), "second punch retains production timing")
	check(is_equal_approx(REEL.sample(actor, "death", 3.3).sample, 2.4), "death freezes at the source ending")
	check(actor.transform == transform and cursor == Input.mouse_mode and before == ExpeditionSession.capture_snapshot(), "presentation does not move the body, cursor or expedition state")
	actor.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("CREEP MOTION REEL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": five gameplay clips and source death, moving bones, contact timing, death hold and preserved state")
	quit(0 if failures.is_empty() else 1)
