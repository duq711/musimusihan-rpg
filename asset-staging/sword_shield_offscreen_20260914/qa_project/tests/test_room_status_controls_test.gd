extends SceneTree

# Headless cannot capture a pointer. Only that platform boundary is replaced;
# perception thresholds, generated audio, placement and cleanup remain real.
class CapturedStressPerception extends StressPerception:
	func _has_input_capture() -> bool:
		return true if DisplayServer.get_name() == "headless" else super._has_input_capture()


const STAT_IDS := ["health", "stamina", "hunger", "thirst", "stress"]

var failures: Array[String] = []
var room: Node3D
var sandbox: Node
var emitted_edits: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original_inventory := ExpeditionSession.get_inventory()
	original_inventory.add_item("wooden_arrow", 9)
	original_inventory.equipment["weapon"] = "hunting_bow"
	ExpeditionSession.hunger = 37.5
	ExpeditionSession.thirst = 46.25
	ExpeditionSession.set_stress(68.75)
	ExpeditionSession.apply_condition("curse", 83.0)
	ExpeditionSession.crowns = 273
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original_inventory.slots.duplicate(true)
	var original_equipment := original_inventory.equipment.duplicate(true)
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	room.set_process(false)
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original_inventory, "status controls must run inside a separate trial inventory")
	_check(room.panel_open and paused, "test room must begin with paused controls")
	if not room.has_method("set_test_stat") or not room.has_method("_refresh_test_status_controls"):
		_check(false, "test room must provide the actual stat-edit and refresh APIs")
	else:
		await _test_catalog_and_non_reset_open()
		_test_bounds_and_isolation()
		await _test_widget_editing_and_pause()
		await _test_live_readouts_and_reopen()
		await _test_fractional_values()
		await _test_perception_after_resume()
		await _test_guardrails_and_reset()
	_check(original_inventory.slots == original_slots and original_inventory.equipment == original_equipment, "trial slider edits and reset must never change original inventory contents or equipment")
	sandbox.finish()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original_inventory, "leaving controls must restore the original inventory identity")
	_check(ExpeditionSession.capture_snapshot() == original_snapshot, "leaving must restore exact original nonzero stress, hunger, thirst, conditions, wallet and all session fields")
	room.queue_free()
	await process_frame
	paused = false
	_finish()


func _test_catalog_and_non_reset_open() -> void:
	var matches := 0
	for entry: Dictionary in room.feature_entries:
		if entry.id == "survival_controls":
			matches += 1
			_check(entry.category == "생존" and entry.action == "survival_controls", "direct adjustment must have an executable survival catalog entry")
	_check(matches == 1, "direct status controls must be registered exactly once")
	# Open the new action from an existing archery fixture. It is an editor,
	# not another fixture, and must preserve targets, resources and position.
	room.run_feature("archery")
	room.player.health = 51.0
	room.player.stamina = 23.0
	ExpeditionSession.hunger = 31.0
	ExpeditionSession.thirst = 42.0
	ExpeditionSession.set_stress(85.0)
	ExpeditionSession.apply_condition("bleeding", 137.0)
	var fixture_position: Vector3 = room.player.position
	var fixture_rotation: Vector3 = room.player.rotation
	var bag: Array = room.inventory.slots.duplicate(true)
	var target := get_nodes_in_group("enemy")[0] as DungeonEnemy
	target.health = 91.0
	var before := _values()
	room.run_feature("survival_controls")
	await process_frame
	_check(room.panel_open and paused and room.selected_category == "생존", "controls action must open the paused survival tab")
	_check(is_instance_valid(room.status_controls) and room.status_controls.is_visible_in_tree(), "survival tab must expose visible direct controls")
	_check(room.entry_list.get_child(0) == room.status_controls, "direct controls must be immediately available above survival presets")
	_check(_values() == before and ExpeditionSession.active_conditions == {"bleeding": 137.0}, "opening controls must preserve all five values and current conditions")
	_check(room.player.position == fixture_position and room.player.rotation == fixture_rotation and room.inventory.slots == bag, "opening direct controls must not teleport, reset inventory or refill arrows")
	_check(is_instance_valid(target) and not target.is_queued_for_deletion() and target.health == 91.0 and target.is_in_group("enemy"), "opening direct controls must preserve the current real target and damage")
	var sliders: Dictionary = room.status_controls.sliders
	var spins: Dictionary = room.status_controls.spin_boxes
	_check(sliders.size() == 5 and spins.size() == 5, "all five values need both a slider and a numeric input")
	for id: String in STAT_IDS:
		_check(sliders.has(id) and sliders[id] is HSlider and spins.has(id) and spins[id] is SpinBox, "each real stat must have usable paired controls: " + id)
		if sliders.has(id) and spins.has(id):
			_check(sliders[id].min_value == (1.0 if id == "health" else 0.0) and sliders[id].max_value == (DungeonPlayer.MAX_HEALTH if id == "health" else 100.0), "slider range must match live safe limits: " + id)
			_check(spins[id].min_value == sliders[id].min_value and spins[id].max_value == sliders[id].max_value, "number input must match its slider limits: " + id)
	room.status_controls.stat_changed.connect(func(id: String, value: float) -> void: emitted_edits.append({"id": id, "value": value}))


func _test_bounds_and_isolation() -> void:
	var position_before: Vector3 = room.player.position
	var slots_before: Array = room.inventory.slots.duplicate(true)
	var conditions_before := ExpeditionSession.active_conditions.duplicate(true)
	for id: String in STAT_IDS:
		var others := _values()
		_check(room.set_test_stat(id, -500.0), "known stat must accept a finite low value: " + id)
		_check(_value(id) == (1.0 if id == "health" else 0.0), "low input must clamp without killing the test player: " + id)
		_check(room.set_test_stat(id, 500.0) and _value(id) == (DungeonPlayer.MAX_HEALTH if id == "health" else 100.0), "high input must clamp to maximum: " + id)
		for other: String in STAT_IDS:
			if other != id:
				_check(_value(other) == others[other], "editing %s must not change %s" % [id, other])
	_check(room.player.health == DungeonPlayer.MAX_HEALTH and room.player.combat_state != DungeonPlayer.CombatState.DEAD, "health range changes must not trigger death flow")
	for invalid: float in [NAN, INF, -INF]:
		var before := _values()
		for id: String in STAT_IDS:
			_check(not room.set_test_stat(id, invalid), "nonfinite input must be rejected: " + id)
		_check(_values() == before, "nonfinite input must leave all actual stats intact")
	var before_unknown := _values()
	_check(not room.set_test_stat("unknown", 42.0) and _values() == before_unknown, "unknown stat IDs must not mutate the trial")
	_check(room.player.position == position_before and room.inventory.slots == slots_before and ExpeditionSession.active_conditions == conditions_before, "scalar controls must not reset position, supplies or active conditions")


func _test_widget_editing_and_pause() -> void:
	var desired := {"health": 47.0, "stamina": 23.0, "hunger": 31.0, "thirst": 42.0, "stress": 85.0}
	for id: String in STAT_IDS:
		var before_count := emitted_edits.size()
		(room.status_controls.sliders[id] as HSlider).value = desired[id]
		_check(_value(id) == desired[id], "slider signal must immediately modify the actual value: " + id)
		_check((room.status_controls.spin_boxes[id] as SpinBox).value == desired[id], "slider edits must synchronize the numeric input: " + id)
		_check(emitted_edits.size() == before_count + 1, "one slider edit must emit once without paired-control feedback loops: " + id)
	var before_refresh := emitted_edits.size()
	for repeat in 3:
		room._refresh_test_status_controls()
	_check(emitted_edits.size() == before_refresh, "reading live status into controls must never emit edit signals")
	var hunger_input := room.status_controls.spin_boxes.hunger as SpinBox
	hunger_input.get_line_edit().text = "19"
	hunger_input.get_line_edit().text_submitted.emit("19")
	_check(ExpeditionSession.hunger == 19.0 and (room.status_controls.sliders.hunger as HSlider).value == 19.0, "typing and submitting a numeric value must update live hunger and its slider")
	for invalid_text: String in ["", "not a number", "nan", "inf"]:
		hunger_input.get_line_edit().text = invalid_text
		hunger_input.get_line_edit().text_submitted.emit(invalid_text)
		_check(ExpeditionSession.hunger == 19.0 and hunger_input.get_line_edit().text == "19", "malformed numeric text must keep and redisplay the last confirmed value")
	var health_input := room.status_controls.spin_boxes.health as SpinBox
	health_input.get_line_edit().text = "-100"
	health_input.get_line_edit().text_submitted.emit("-100")
	_check(room.player.health == 1.0 and health_input.value == 1.0 and room.player.combat_state != DungeonPlayer.CombatState.DEAD, "typed health below zero must safely clamp to one without triggering a death result")
	room.set_test_stat("health", 47.0)
	var paused_values := _values()
	var paused_conditions := ExpeditionSession.active_conditions.duplicate(true)
	room.player.set_physics_process(true)
	room._process(60.0)
	await create_timer(0.08, true).timeout
	_check(paused and _values() == paused_values and ExpeditionSession.active_conditions == paused_conditions, "editing inside F2 must pause hunger, thirst, stress, stamina and condition timers: paused=%s before=%s after=%s conditions=%s/%s" % [paused, paused_values, _values(), paused_conditions, ExpeditionSession.active_conditions])
	room.player.set_physics_process(false)
	var stress_input := room.status_controls.spin_boxes.stress as SpinBox
	stress_input.get_line_edit().grab_focus()
	stress_input.get_line_edit().text = "73"
	stress_input.get_line_edit().text_changed.emit("73")
	await _press_key(KEY_F2)
	_check(not room.panel_open and not paused and ExpeditionSession.stress == 73.0, "closing F2 with an unfinished numeric edit must commit it before resuming: panel=%s paused=%s stress=%s text=%s" % [room.panel_open, paused, ExpeditionSession.stress, stress_input.get_line_edit().text])
	room._show_test_panel()
	_check((room.status_controls.spin_boxes.stress as SpinBox).value == 73.0, "reopening must retain the committed numeric value")


func _test_live_readouts_and_reopen() -> void:
	var expected := {"health": 57.0, "stamina": 28.0, "hunger": 35.0, "thirst": 46.0, "stress": 86.0}
	for id: String in STAT_IDS:
		_check(room.set_test_stat(id, expected[id]), "paused editor must accept the intended live status: " + id)
	_check(room.hud.health_bar.value == 57.0 and room.hud.stamina_bar.value == 28.0, "direct edits must immediately refresh actual health and stamina HUD meters")
	_check(room.hud.hunger_bar.value == 35.0 and room.hud.thirst_bar.value == 46.0 and room.hud.stress_bar.value == 86.0, "direct edits must immediately refresh all session HUD meters")
	_check(room.hud.stress_label.text.contains("극심"), "stress edits must immediately update the actual stage caption")
	room._hide_test_panel()
	room._open_inventory()
	await process_frame
	_check(room.inventory_overlay.is_open() and paused, "comparison must use the actual paused inventory overlay")
	_check(room.inventory_overlay.stamina_bar.value == 28.0 and room.inventory_overlay.hunger_bar.value == 35.0 and room.inventory_overlay.thirst_bar.value == 46.0 and room.inventory_overlay.stress_bar.value == 86.0, "inventory must show edited player/session values rather than a mock preview")
	var before := _values()
	_check(not room.set_test_stat("stress", 1.0) and _values() == before, "hidden F2 controls must not edit while another paused menu owns input")
	room._close_inventory()
	# Simulate subsequent legitimate gameplay changes, then reopen F2. The
	# controls must read the new values instead of replaying stale form data.
	room.player.health = 64.0
	room.player.stamina = 39.0
	ExpeditionSession.hunger = 26.0
	ExpeditionSession.thirst = 17.0
	ExpeditionSession.set_stress(61.0)
	room._show_test_panel()
	for id: String in STAT_IDS:
		_check((room.status_controls.sliders[id] as HSlider).value == _value(id) and (room.status_controls.spin_boxes[id] as SpinBox).value == _value(id), "reopened controls must refresh from latest actual status: " + id)
	room._select_category("기본")
	room._select_category("생존")
	for id: String in STAT_IDS:
		_check((room.status_controls.spin_boxes[id] as SpinBox).value == _value(id), "switching tabs must preserve current actual values: " + id)


func _test_perception_after_resume() -> void:
	var old_effects := room.stress_effects as Node
	room.remove_child(old_effects)
	old_effects.queue_free()
	var effects := CapturedStressPerception.new()
	effects.setup(room.player)
	room.add_child(effects)
	room.stress_effects = effects
	effects.set_process(false)
	room.run_feature("stress_vision")
	room.player.set_physics_process(true)
	for frame in 60:
		await physics_frame
		if room.player.is_on_floor():
			break
	room.player.set_physics_process(false)
	_check(room.player.is_on_floor(), "perception comparison must use the actual settled test-room floor")
	room.run_feature("survival_controls")
	room.set_test_stat("stress", 59.6)
	room._hide_test_panel()
	room._update_stress_presentation()
	_check(ExpeditionSession.stress == 59.6 and not effects.trigger_event("whisper") and not effects.trigger_event("vision"), "rounded display must preserve fractional actual stress below the audio threshold and suppress hallucinations")
	room._show_test_panel()
	_submit_number("stress", "60")
	_check(ExpeditionSession.stress == 60.0, "explicit 60 Enter must apply exactly even when 59.6 already displayed as 60")
	_check(not effects.active and not effects.audio_player.playing, "editing stress while paused must not start sound")
	room._hide_test_panel()
	room._update_stress_presentation()
	_check(effects.trigger_event("whisper") and effects.audio_player.playing and effects.audio_player.stream is AudioStreamWAV, "setting stress to 60 must enable real positional audio after resume")
	_check(not effects.trigger_event("vision"), "audio threshold must not prematurely enable visions")
	room._show_test_panel()
	_check(not effects.active and not effects.audio_player.playing, "opening controls must immediately silence existing hallucinations")
	room.set_test_stat("stress", 79.6)
	room._hide_test_panel()
	room._update_stress_presentation()
	_check(ExpeditionSession.stress == 79.6 and not effects.trigger_event("vision"), "displaying rounded 80 must not turn fractional 79.6 into an actual vision trigger")
	room._show_test_panel()
	_submit_number("stress", "80")
	_check(ExpeditionSession.stress == 80.0, "explicit 80 Enter must cross the actual vision threshold even when the rounded display already read 80")
	room._hide_test_panel()
	room._update_stress_presentation()
	effects.rng.seed = 711
	_check(effects.trigger_event("vision") and is_instance_valid(effects.ghost), "setting stress to 80 must enable the real harmless 3D vision after resume")
	room._show_test_panel()
	# Gameplay thresholds use exact comparisons, so approximately equal values
	# must still emit a deliberate edit when that edit crosses 60 or 80.
	for threshold_case: Dictionary in [{"raw": 59.9999, "target": 60.0, "kind": "whisper"}, {"raw": 79.9999, "target": 80.0, "kind": "vision"}]:
		room.set_test_stat("stress", threshold_case.raw)
		room._hide_test_panel()
		room._update_stress_presentation()
		_check(ExpeditionSession.stress == threshold_case.raw and not effects.trigger_event(threshold_case.kind), "an almost-threshold raw value must remain below its actual perception gate")
		room._show_test_panel()
		_submit_number("stress", str(roundi(float(threshold_case.target))))
		_check(ExpeditionSession.stress == threshold_case.target, "explicit integer confirmation must apply even when the raw fraction is approximately equal to the threshold")
		room._hide_test_panel()
		room._update_stress_presentation()
		effects.rng.seed = 711
		_check(effects.trigger_event(threshold_case.kind), "an exact threshold confirmed from an almost-equal raw value must enable the actual perception effect")
		room._show_test_panel()
	room.set_test_stat("stress", 0.0)
	room._hide_test_panel()
	room._update_stress_presentation()
	_check(not is_instance_valid(effects.ghost) and not effects.audio_player.playing and not effects.trigger_event("vision") and not effects.trigger_event("whisper"), "editing stress back to zero must remove previous effects and disable new hallucinations")
	room._show_test_panel()


func _test_fractional_values() -> void:
	var expected := {"health": 47.4, "stamina": 28.3, "hunger": 35.2, "thirst": 46.1, "stress": 79.6}
	for id: String in STAT_IDS:
		_check(room.set_test_stat(id, expected[id]), "core editor must preserve finite actual fractional values: " + id)
	room._refresh_test_status_controls()
	_check(_values() == expected, "reading fractional actual state into integer controls must not round the actual game values")
	await _press_key(KEY_F2)
	_check(not paused and _values() == expected, "closing untouched controls must preserve fractional values instead of committing rounded displays")
	room._show_test_panel()
	for id: String in STAT_IDS:
		(room.status_controls.spin_boxes[id] as SpinBox).get_line_edit().grab_focus()
		await process_frame
		await _press_key(KEY_F2)
		_check(not paused and _values() == expected, "focusing an unedited number and closing F2 must not quantize actual state: " + id)
		room._show_test_panel()
	for id: String in STAT_IDS:
		_submit_number(id, "not a number")
		_check(_values() == expected, "invalid numeric text must preserve the exact actual fraction, not just its rounded display: " + id)
		_check((room.status_controls.spin_boxes[id] as SpinBox).get_line_edit().text == str(roundi(float(expected[id]))), "invalid text must restore the normal rounded display without modifying real values: " + id)
	for id: String in STAT_IDS:
		var integer := float(roundi(float(expected[id])))
		_submit_number(id, str(roundi(integer)))
		expected[id] = integer
		_check(_values() == expected, "explicit Enter must apply an integer in the same display bin and preserve other fractional values: " + id)
	await process_frame
	_check(_values() == expected, "deferred native number callbacks must not replay fractional values after explicit integer confirmation")
	room.set_test_stat("health", 47.4)
	var health_input := room.status_controls.spin_boxes.health as SpinBox
	health_input.get_line_edit().text_submitted.emit("47")
	_check(room.player.health == 47.0, "pressing Enter explicitly confirms the displayed integer even without typing different text")
	room.set_test_stat("stress", 79.6)
	var local_edits := [0]
	room.status_controls.stat_changed.connect(func(_id: String, _value: float) -> void: local_edits[0] += 1)
	var stress_slider := room.status_controls.sliders.stress as HSlider
	stress_slider.drag_ended.emit(false)
	_check(ExpeditionSession.stress == 80.0 and local_edits[0] == 1, "deliberately selecting the same rounded slider position must confirm its actual integer exactly once")
	stress_slider.value = 81.0
	stress_slider.drag_ended.emit(true)
	_check(ExpeditionSession.stress == 81.0 and local_edits[0] == 2, "drag-end confirmation must not duplicate an already emitted slider value change")


func _test_guardrails_and_reset() -> void:
	var before := _values()
	room._hide_test_panel()
	_check(not room.set_test_stat("hunger", 1.0) and _values() == before, "direct test edits must be rejected during active gameplay")
	room._show_test_panel()
	sandbox.active = false
	_check(not room.set_test_stat("stress", 99.0) and _values() == before, "controls must reject writes when the isolated trial is inactive")
	sandbox.active = true
	room.player.health = 0.0
	room.player.combat_state = DungeonPlayer.CombatState.DEAD
	_check(not room.set_test_stat("health", 100.0) and room.player.health == 0.0, "direct adjustment must not bypass the normal death/reset flow")
	room.player.combat_state = DungeonPlayer.CombatState.READY
	room.player.health = 25.0
	room.set_test_stat("hunger", 7.0)
	room.set_test_stat("thirst", 9.0)
	room.set_test_stat("stress", 94.0)
	_set_pending_number("health", "3")
	_set_pending_number("stress", "99")
	room._recover_player()
	await process_frame
	_check(room.player.health == DungeonPlayer.MAX_HEALTH and room.player.stamina == 100.0 and ExpeditionSession.stress == 0.0, "recovery must discard stale pending health/stress edits after applying the actual recovery")
	_check(ExpeditionSession.hunger == 7.0 and ExpeditionSession.thirst == 9.0, "ordinary recovery after editing must not silently refill unrelated needs")
	_set_pending_number("health", "5")
	_set_pending_number("hunger", "2")
	_set_pending_number("thirst", "3")
	_set_pending_number("stress", "97")
	var old_inventory: ExpeditionInventory = room.inventory
	room.reset_room()
	await process_frame
	_check(room.inventory != old_inventory and room.inventory == ExpeditionSession.get_inventory(), "reset after editing must still allocate a fresh isolated trial inventory")
	_check(room.player.health == DungeonPlayer.MAX_HEALTH and room.player.stamina == 100.0 and ExpeditionSession.hunger == 100.0 and ExpeditionSession.thirst == 100.0 and ExpeditionSession.stress == 0.0, "reset must restore the normal fresh trial values")
	room.run_feature("survival_controls")
	for id: String in STAT_IDS:
		_check((room.status_controls.spin_boxes[id] as SpinBox).value == _value(id), "reset must discard stale edited widget values: " + id)


func _set_pending_number(id: String, value: String) -> void:
	var edit := (room.status_controls.spin_boxes[id] as SpinBox).get_line_edit()
	edit.text = value
	edit.text_changed.emit(value)


func _submit_number(id: String, value: String) -> void:
	_set_pending_number(id, value)
	(room.status_controls.spin_boxes[id] as SpinBox).get_line_edit().text_submitted.emit(value)


func _value(id: String) -> float:
	match id:
		"health": return room.player.health
		"stamina": return room.player.stamina
		"hunger": return ExpeditionSession.hunger
		"thirst": return ExpeditionSession.thirst
		"stress": return ExpeditionSession.stress
	return NAN


func _values() -> Dictionary:
	var result: Dictionary = {}
	for id: String in STAT_IDS:
		result[id] = _value(id)
	return result


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("TEST ROOM STATUS CONTROLS PASS: five live sliders/numeric inputs, commit, clamping, pause, HUD/inventory sync, real resumed hallucinations, existing fixture preservation, reset and exact original session restoration")
		quit(0)
		return
	for failure in failures:
		push_error("TEST ROOM STATUS CONTROLS FAIL: " + failure)
	quit(1)
