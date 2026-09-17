extends SceneTree

var failures: Array[String] = []
var room: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_scale_and_rates()
	_test_elapsed_time_boundaries()
	await _test_actual_exploration_and_damage()
	await _test_actual_camp_relief()
	room.cancel_camp("", false)
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("STRESS SYSTEM TEST PASS: bounded persistent stress, exact gain/expiry/need thresholds, actual dungeon damage and pause gates, safe-zone recovery and three finite camp relief actions without partial or repeated rewards")
		quit(0)
	else:
		for failure in failures:
			push_error("STRESS SYSTEM TEST FAIL: " + failure)
		quit(1)


func _test_scale_and_rates() -> void:
	ExpeditionSession.begin_new_journey()
	_close(ExpeditionSession.stress, 0.0, "new journey starts without stress")
	for sample: Array in [[0.0, "안정"], [39.99, "안정"], [40.0, "불안"], [59.99, "불안"], [60.0, "동요"], [79.99, "동요"], [80.0, "극심"], [100.0, "극심"]]:
		_check(StressProfile.stage_name(sample[0]) == sample[1], "stage threshold must match " + str(sample))
	ExpeditionSession.set_stress(95.0)
	_close(ExpeditionSession.add_stress(20.0), 5.0, "increase returns only actual bounded change")
	_close(ExpeditionSession.stress, 100.0, "stress cannot exceed maximum")
	_close(ExpeditionSession.relieve_stress(120.0), 100.0, "relief reports actual bounded change")
	_close(ExpeditionSession.stress, 0.0, "stress cannot become negative")
	ExpeditionSession.set_stress(35.0)
	for invalid in [NAN, INF, -INF]:
		ExpeditionSession.set_stress(invalid)
		ExpeditionSession.add_stress(invalid)
		ExpeditionSession.relieve_stress(invalid)
		ExpeditionSession.advance_survival(invalid, {"torch_lit": false})
	ExpeditionSession.add_stress(-50.0)
	ExpeditionSession.relieve_stress(-50.0)
	_close(ExpeditionSession.stress, 35.0, "invalid values or negative changes cannot corrupt stress")
	var calm := {"torch_lit": true, "health_ratio": 1.0, "threatened": false}
	_close(StressProfile.gain_per_second(calm, 100, 100, 0), 0, "healthy lit exploration does not passively punish the player")
	_close(StressProfile.gain_per_second({"torch_lit": false}, 100, 100, 0), 0.09, "darkness rate")
	_close(StressProfile.gain_per_second({"health_ratio": 0.3}, 100, 100, 0), 0.07, "critical health rate")
	_close(StressProfile.gain_per_second(calm, 25, 25, 0), 0.08, "low food and water stack")
	_close(StressProfile.gain_per_second({"threatened": true}, 100, 100, 2), 0.13, "actual threat and conditions stack")
	_close(StressProfile.gain_per_second({"torch_lit": false, "health_ratio": 0.1, "threatened": true}, 0, 0, 30), 0.4, "sources have a per-second cap")
	_close(StressProfile.gain_per_second({"safe_zone": true, "torch_lit": false}, 0, 0, 3), 0, "safe zones cannot accumulate stress")
	_close(StressProfile.gain_per_second({}, 0, 0, 3), 0, "survival-only camp time does not accumulate stress")
	_check(StressProfile.audio_interval(100) < StressProfile.audio_interval(60) and StressProfile.vision_interval(100) < StressProfile.vision_interval(80), "higher stress increases perception frequency")


func _test_elapsed_time_boundaries() -> void:
	var outcomes: Array[Dictionary] = []
	for step: float in [120.0, 1.0, 1.0 / 60.0]:
		ExpeditionSession.begin_new_journey()
		ExpeditionSession.hunger = 26.0
		ExpeditionSession.thirst = 26.0
		ExpeditionSession.apply_condition("bleeding", 17.0)
		ExpeditionSession.apply_condition("curse", 31.0)
		var remaining := 120.0
		while remaining > 0.000001:
			var elapsed := minf(step, remaining)
			ExpeditionSession.advance_survival(elapsed, {"torch_lit": false, "health_ratio": 0.3, "threatened": true})
			remaining -= elapsed
		outcomes.append(ExpeditionSession.get_survival_snapshot())
	for result in outcomes:
		for key: String in ["stress", "hunger", "thirst"]:
			_close(float(result[key]), float(outcomes[0][key]), "large delta and frame updates agree through condition expiry and low-supply thresholds: " + key)
		_check(result.conditions.is_empty(), "expired conditions must no longer contribute")
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.hunger = 26.0
	ExpeditionSession.thirst = 26.0
	ExpeditionSession.advance_survival(60.0, {"torch_lit": true})
	_close(ExpeditionSession.stress, (60.0 - 54.0) * 0.04 + (60.0 - 36.0) * 0.04, "low-need stress begins at the exact crossing, not the start of a long tick")
	var saved := ExpeditionSession.capture_snapshot()
	ExpeditionSession.set_stress(99.0)
	ExpeditionSession.restore_snapshot(saved)
	_close(ExpeditionSession.stress, float(saved.stress), "session restoration includes the exact stress value")


func _test_actual_exploration_and_damage() -> void:
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process_unhandled_input(false)
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	await _reset_fixture("stress_audio")
	ExpeditionSession.set_stress(0.0)
	room._process(10.0)
	_close(ExpeditionSession.stress, 0.0, "actual healthy room remains calm")
	room.player.torch_enabled = false
	room._process(10.0)
	_close(ExpeditionSession.stress, 0.9, "actual dungeon uses torch state")
	room._pause_game()
	room._process(30.0)
	_close(ExpeditionSession.stress, 0.9, "pause freezes stress accumulation")
	room._resume_game()
	room._open_inventory()
	room._process(30.0)
	_close(ExpeditionSession.stress, 0.9, "inventory freezes stress accumulation")
	room._close_inventory()
	room.player.torch_enabled = true
	ExpeditionSession.set_stress(0.0)
	room.player.receive_environment_damage(20.0, "스트레스 검증")
	_close(ExpeditionSession.stress, 7.0, "actual damage contributes proportionally")
	room.player.blocking = true
	room.player.block_time = 0.0
	var guarded: Dictionary = room.player.receive_attack(20.0, room.player.global_position - room.player.global_basis.z * 2.0)
	_check(bool(guarded.parried), "fixture uses actual perfect shield guard")
	_close(ExpeditionSession.stress, 7.0, "perfect guard with no damage adds no stress")
	room.player.blocking = false
	room.player.health = 100.0
	room.player.receive_environment_damage(50.0, "큰 피해 검증")
	_close(ExpeditionSession.stress, 19.0, "single damage stress cannot exceed twelve")
	room.player.configure_safe_zone(true)
	room.player._physics_process(10.0)
	_close(ExpeditionSession.stress, 15.5, "actual safe-zone player gradually recovers")
	paused = true
	room.player._physics_process(10.0)
	_close(ExpeditionSession.stress, 15.5, "safe-zone menus do not silently advance recovery")
	paused = false
	room.player.configure_safe_zone(false)
	room._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	room._update_stress_presentation()
	_check(not room.stress_effects.active, "window focus loss suspends perception")
	room._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)


func _test_actual_camp_relief() -> void:
	for id: String in ["rest", "meal", "treat"]:
		await _reset_fixture("camping")
		ExpeditionSession.set_stress(80.0)
		if id in ["rest", "meal"]:
			room.player.health = 100.0
			room.player.stamina = 100.0
			ExpeditionSession.hunger = 100.0
			ExpeditionSession.thirst = 100.0
			ExpeditionSession.clear_conditions()
		var opened: Dictionary = room.camp.open_camp()
		_check(bool(opened.accepted), "real grounded camp must open: " + id)
		var started: Dictionary = room.camp.start_action(id)
		_check(bool(started.accepted), "real action must accept stress-only recovery or injury: " + id)
		if not bool(started.accepted):
			continue
		room.camp.advance_rest(room.camp.rest_duration / 2.0)
		_close(ExpeditionSession.stress, 80.0, "no partial relief and no stress gain during accelerated camp time: " + id)
		room.camp.advance_rest(room.camp.rest_duration)
		var expected := float(StressProfile.CAMP_RELIEF[id])
		_close(ExpeditionSession.stress, 80.0 - expected, "completion applies authored relief: " + id)
		_close(float(room.camp.last_result.get("stress_relieved", -1)), expected, "actual completion reports stress recovered")
		room.camp.advance_rest(300.0)
		_close(ExpeditionSession.stress, 80.0 - expected, "relief cannot repeat after completion")
		room.cancel_camp()
	await _reset_fixture("camping")
	ExpeditionSession.set_stress(80.0)
	room.camp.open_camp()
	room.camp.start_action("rest")
	room.camp.advance_rest(4.0)
	room.cancel_camp()
	_close(ExpeditionSession.stress, 80.0, "cancelling rest grants no free stress relief")


func _reset_fixture(id: String) -> void:
	room.run_feature(id)
	room.set_process(false)
	room.camp.set_process(false)
	room.player.set_physics_process(true)
	for _frame in range(40):
		await physics_frame
		if room.player.is_on_floor() and room.player.trap_lockout <= 0.0:
			break
	room.player.set_physics_process(false)
	_check(room.player.is_on_floor(), "fixture player must be grounded")


func _close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.003, message + " (actual=%f, expected=%f)" % [actual, expected])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
