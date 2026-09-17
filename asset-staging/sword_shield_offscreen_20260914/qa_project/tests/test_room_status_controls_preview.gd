extends SceneTree

var room: Node3D
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Status controls preview requires a native display")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.grab_focus()
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process_unhandled_input(false)
	room.player.set_process_unhandled_input(false)
	await process_frame
	await process_frame
	room._hide_test_panel()
	for _frame in range(40):
		await physics_frame
		if room.player.is_on_floor():
			break
	room.player.set_physics_process(false)
	room.set_process(false)
	room._show_test_panel()
	room.set_process_unhandled_input(true)
	root.grab_focus()
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _click(room.stat_controls_button.get_global_rect().get_center())
	_check(room.selected_category == "생존" and is_instance_valid(room.status_controls), "actual top shortcut must open the status adjustment card")
	if not is_instance_valid(room.status_controls):
		await _finish()
		return
	var widget: Control = room.status_controls
	await _capture("test_room_status_controls_opened.png")
	_check_visible_rows()
	var slider: HSlider = widget.sliders.stress
	await _click(slider.get_global_rect().get_center())
	_check(ExpeditionSession.stress >= 45.0 and ExpeditionSession.stress <= 55.0, "actual mouse click on slider changes the real stress value: %s" % ExpeditionSession.stress)
	var position_before: Vector3 = room.player.global_position
	var slots_before: Array = room.inventory.slots.duplicate(true)
	var enemies_before: Array[Node] = get_nodes_in_group("enemy")
	for pair: Array in [["health", "35"], ["stamina", "11"], ["hunger", "12"], ["thirst", "8"], ["stress", "90"]]:
		await _type_number(widget.spin_boxes[pair[0]], pair[1])
		await _key(KEY_ENTER)
	_check(room.player.health == 35.0 and room.player.stamina == 11.0 and ExpeditionSession.hunger == 12.0 and ExpeditionSession.thirst == 8.0 and ExpeditionSession.stress == 90.0, "actual text entry and Enter must apply all five independent values")
	_check(room.player.global_position == position_before and room.inventory.slots == slots_before and get_nodes_in_group("enemy") == enemies_before, "adjustment must preserve location, bag and current targets")
	room.resume_button.grab_focus()
	room.entry_scroll.scroll_vertical = 0
	await _capture("test_room_status_controls.png")
	_check_visible_rows()
	# Leave a numeric edit unsubmitted. F2 must commit it exactly once before
	# hiding the menu, even though SpinBox also reacts to focus loss.
	await _type_number(widget.spin_boxes.stress, "87")
	await _key(KEY_F2)
	await process_frame
	_check(not room.panel_open and not paused and ExpeditionSession.stress == 87.0, "native F2 from the number field must commit 87 without Enter or stale replay")
	root.grab_focus()
	await process_frame
	await process_frame
	room._update_stress_presentation()
	room.stress_effects.set_process(false)
	room.stress_effects.advance(2.05)
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and room.stress_effects.audio_player.playing, "custom high stress must drive real perception on resuming captured gameplay: capture=%s focused=%s active=%s stress=%s" % [Input.mouse_mode, room._window_focused, room.stress_effects.active, ExpeditionSession.stress])
	await _capture("test_room_status_controls_applied.png")
	await _key(KEY_F2)
	_check(room.panel_open and paused and not room.stress_effects.audio_player.playing, "reopening controls pauses the world and clears audio")
	await _type_number(room.status_controls.spin_boxes.stress, "0")
	await _key(KEY_ENTER)
	_check(ExpeditionSession.stress == 0.0, "zero stress is directly selectable")
	room.set_test_stat("stress", 79.6)
	room.status_controls.spin_boxes.stress.get_line_edit().grab_focus()
	await process_frame
	room.resume_button.grab_focus()
	await process_frame
	_check(ExpeditionSession.stress == 79.6, "native focus without an edit must preserve actual fractional stress")
	await _type_number(room.status_controls.spin_boxes.stress, "80")
	await _key(KEY_ENTER)
	_check(ExpeditionSession.stress == 80.0, "explicit native input must reach exact vision threshold even when the previous fractional value also displayed as 80")
	room.set_test_stat("stress", 0.0)
	# Resizing the actual logical viewport verifies the compact layout, not
	# merely a scaled-down image of the original 1280-wide menu.
	root.content_scale_size = Vector2i(640, 480)
	root.size = Vector2i(640, 480)
	await process_frame
	await process_frame
	room.entry_scroll.ensure_control_visible(room.status_controls.sliders.stress)
	room.resume_button.grab_focus()
	await _capture("test_room_status_controls_small.png")
	_check(root.get_visible_rect().encloses(room.panel_actions.get_global_rect()), "compact footer actions must remain inside the viewport")
	var small_slider: HSlider = room.status_controls.sliders.stress
	_check(room.entry_scroll.get_global_rect().encloses(small_slider.get_global_rect()), "scrolling must expose the full stress slider on a small viewport")
	await _click(small_slider.get_global_rect().get_center())
	_check(ExpeditionSession.stress >= 45.0 and ExpeditionSession.stress <= 55.0, "compact slider remains directly operable")
	if OS.get_environment("STATUS_CONTROLS_QA_INTERACTIVE") == "1":
		room.player.set_physics_process(true)
		room.player.set_process_unhandled_input(true)
		room.set_process(true)
		room.stress_effects.set_process(true)
		return
	await _finish()


func _check_visible_rows() -> void:
	for id: String in ["health", "stamina", "hunger", "thirst", "stress"]:
		var slider: HSlider = room.status_controls.sliders[id]
		var number: SpinBox = room.status_controls.spin_boxes[id]
		_check(room.entry_scroll.get_global_rect().encloses(slider.get_global_rect()) and room.entry_scroll.get_global_rect().encloses(number.get_global_rect()), "all five input rows must fit at 1280x720: " + id)


func _type_number(number: SpinBox, text_value: String) -> void:
	var edit := number.get_line_edit()
	room.entry_scroll.ensure_control_visible(edit)
	await process_frame
	edit.grab_focus()
	edit.select_all()
	for index in text_value.length():
		await _key(text_value.unicode_at(index), text_value.unicode_at(index))


func _key(code: int, unicode_value := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode_value
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _click(at: Vector2) -> void:
	# Keep the native pointer at the injected click location so an OS motion
	# event cannot drag a held slider back to an unrelated desktop position.
	Input.warp_mouse(at)
	await process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.position = at
		button.global_position = at
		button.pressed = pressed
		root.push_input(button, true)
	await process_frame
	await process_frame


func _capture(file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name)) == OK, "native capture saved: " + file_name)


func _finish() -> void:
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("TEST ROOM STATUS CONTROLS PREVIEW PASS: actual button, slider clicks, numeric typing/Enter/F2 commit, real stress playback, fixture preservation and compact scrolling layout")
		quit(0)
	else:
		for failure in failures:
			push_error("STATUS CONTROLS PREVIEW FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
