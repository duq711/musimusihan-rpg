extends SceneTree

var room: Node3D
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Camp preview requires a rendering display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process_unhandled_input(false)
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room.run_feature("camping")
	for frame in range(20):
		await physics_frame
		if room.player.is_on_floor() and room.player.trap_lockout <= 0.0:
			break
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _capture("camp_test_fixture.png")
	if OS.get_environment("CAMP_QA_INTERACTIVE") == "1":
		room.set_process_unhandled_input(true)
		room.player.set_process_unhandled_input(true)
		return
	room.set_process(false)
	room.camp.set_process(false)
	_key(KEY_C)
	_check(room.camp.is_open() and paused and room.player.camping, "real C input must open the camp plan")
	if not room.camp.is_open():
		_fail_and_exit()
		return
	await _capture("camp_plan.png")
	var panel := room.camp.overlay.panel_root as Control
	_check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(panel.get_global_rect()), "camp panel must fit the rendered viewport")
	var visual := room.camp.camp_visual as Node3D
	var fire_point: Vector2 = room.player.camera.unproject_position(visual.global_position + Vector3(0, 0.35, 0))
	_check(not panel.get_global_rect().has_point(fire_point) and root.get_visible_rect().has_point(fire_point), "real campfire must remain visible beside its menu")
	var initial_kit: int = room.inventory.count_item("camp_kit")
	room.camp.overlay.action_buttons["treat"].pressed.emit()
	_check(room.camp.state == "resting" and not paused, "actual treatment button must start live rest")
	room.camp.advance_rest(3.0)
	CampVisuals.animate(visual, 3.0, room.camp.warmth)
	await _capture("camp_treating.png")
	_check(room.camp.overlay.progress_bar.value > 0.4 and room.camp.overlay.action_buttons["meal"].disabled, "rendered progress and disabled actions must reflect active rest")
	room.camp.advance_rest(3.0)
	await _capture("camp_treated.png")
	_check(paused and room.camp.state == "planning" and not ExpeditionSession.has_condition("bleeding") and is_equal_approx(room.player.health, 53.0), "completed treatment must heal the real player and clear bleeding")
	room.camp.overlay.action_buttons["meal"].pressed.emit()
	room.camp.advance_rest(7.0)
	CampVisuals.animate(visual, 10.0, room.camp.warmth)
	await _capture("camp_meal_rest.png")
	room.camp.advance_rest(7.0)
	await _capture("camp_recovered.png")
	_check(paused and room.camp.warmth == 0 and is_equal_approx(room.player.health, 98.0) and is_equal_approx(room.player.stamina, 100.0), "meal must recover health and stamina and exhaust the remaining warmth")
	_check(room.inventory.count_item("camp_kit") == initial_kit - 1 and room.inventory.count_item("pilgrim_ration") == 1 and room.inventory.count_item("boiled_rainwater") == 1 and room.inventory.count_item("linen_bandage") == 1, "two activities must spend one kit total and each selected supply once")
	_check(room.camp.overlay.action_buttons["rest"].disabled, "spent warmth must visibly prevent unlimited recovery")
	room.camp.overlay.leave_button.pressed.emit()
	await _capture("camp_return_to_dungeon.png")
	_check(not paused and not room.player.camping and room.player.weapon_pivot.visible and room.camp.camp_visual == null, "leave button must remove camp and restore exploration")
	room._show_test_panel()
	room._select_category("생존")
	await _capture("camp_test_menu.png")
	room.cancel_camp("", false)
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fail_and_exit()


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	room._unhandled_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _fail_and_exit() -> void:
	if failures.is_empty():
		print("CAMP PREVIEW PASS: actual C and UI actions, rendered campfire, treatment, live rest progress, meal recovery, finite supplies/warmth and safe dungeon return")
		quit(0)
	else:
		for failure in failures:
			push_error("CAMP PREVIEW FAIL: " + failure)
		quit(1)


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name))
	_check(result == OK, "could not save preview: " + file_name)
