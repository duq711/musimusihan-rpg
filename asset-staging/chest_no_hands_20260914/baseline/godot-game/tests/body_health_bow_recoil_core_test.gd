extends "res://tests/bow_accuracy_test.gd"


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_mouse := Input.mouse_mode
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_test_recoil_and_true_aim()
	ExpeditionSession.restore_snapshot(original)
	Input.mouse_mode = original_mouse
	_check(ExpeditionSession.capture_snapshot() == original, "The targeted recoil fixture must restore the original expedition.")
	for failure in failures:
		push_error(failure)
	print("BODY HEALTH BOW RECOIL CORE TEST %s: original accuracy-suite recoil and true-aim function, same-pose impulse isolation, and session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
