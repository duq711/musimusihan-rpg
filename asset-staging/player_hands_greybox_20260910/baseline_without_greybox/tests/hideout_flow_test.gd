extends SceneTree

const SCENE_TRANSITION_TIMEOUT_MSEC := 30000

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists("res://assets/ui/sanctuary_route_map.png"), "destination map artwork must exist")
	var packed := load("res://hideout.tscn") as PackedScene
	_check(packed != null, "hideout scene must load")
	if packed == null:
		_finish()
		return

	ExpeditionSession.begin_new_journey()
	var session_inventory := ExpeditionSession.get_inventory()
	ExpeditionSession.crowns = 73
	var hideout := packed.instantiate() as SanctuaryHideout
	root.add_child(hideout)
	current_scene = hideout
	await process_frame
	await process_frame

	_check(hideout != null and hideout.scene_file_path == "res://hideout.tscn", "hideout.tscn must instantiate as SanctuaryHideout")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "hideout must release the mouse")
	_check(hideout.door_button != null and hideout.door_button.name == "SanctuaryDoorButton", "hideout must expose a clickable sanctuary door")
	_check(hideout.door_button.visible and hideout.door_button.is_visible_in_tree(), "sanctuary door must be visible when the hideout opens")
	_check(hideout.door_button.tooltip_text.contains("지도"), "sanctuary door must explain that it opens the travel map")
	_check(_within_viewport(hideout.door_button), "sanctuary door click target must fit the 1280 by 720 viewport")
	_check(hideout.destination_panel != null and not hideout.destination_panel.visible, "destination map must start hidden inside the hideout")
	_check(hideout.modal_scrim != null and not hideout.modal_scrim.visible and hideout.current_panel == null, "hideout must start without the destination modal")
	_check(hideout.find_child("StartGameButton", true, false) == null, "hideout must not repeat the boot-menu start action")

	hideout.door_button.pressed.emit()
	_check(hideout.modal_scrim.visible and hideout.destination_panel.visible and hideout.current_panel == hideout.destination_panel, "clicking the sanctuary door must reveal the destination map")
	_check(hideout.destination_dungeon_button != null and hideout.destination_merchant_button != null and hideout.destination_cancel_button != null, "destination map must expose dungeon, merchant, and close actions")
	_check(hideout.destination_dungeon_button.text.contains("성물실") and hideout.destination_merchant_button.text.contains("중개인"), "destination actions must clearly identify the dungeon and merchant")
	var destination_art := hideout.destination_panel.find_child("DestinationMapArtwork", true, false) as TextureRect
	_check(destination_art != null and destination_art.texture != null, "destination map must render the authored sanctuary artwork")
	if destination_art != null and destination_art.texture != null:
		_check(destination_art.texture.resource_path == "res://assets/ui/sanctuary_route_map.png", "destination map must use the authored sanctuary artwork")
		_check(destination_art.texture.get_size() == Vector2(1122, 1402), "destination map must retain the authored image dimensions")
		_check(destination_art.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "destination map must preserve artwork proportions")
	_check(hideout.destination_panel.find_child("DestinationLeftRail", true, false) != null and hideout.destination_panel.find_child("DestinationRightRail", true, false) != null, "destination map must provide navigation and detail rails")
	_check(_within_viewport(hideout.destination_panel) and _within_viewport(hideout.destination_dungeon_button) and _within_viewport(hideout.destination_merchant_button), "destination map and location actions must fit the 1280 by 720 viewport")
	_check(hideout.get_viewport().gui_get_focus_owner() == hideout.destination_merchant_button, "destination map must focus the safe merchant choice")
	_check(ExpeditionSession.get_inventory() == session_inventory and ExpeditionSession.crowns == 73, "opening the destination map must preserve the active session")

	_send_escape(hideout)
	_check(not hideout.modal_scrim.visible and not hideout.destination_panel.visible and hideout.current_panel == null, "Escape from the destination map must return to the hideout")
	_check(hideout.get_viewport().gui_get_focus_owner() == null, "closing the destination map must release GUI focus before gameplay resumes")
	await _send_space_through_input()
	_check(not hideout.modal_scrim.visible and not hideout.destination_panel.visible and hideout.current_panel == null, "jumping after Escape must not reopen the destination map")

	hideout.door_button.pressed.emit()
	hideout.destination_cancel_button.pressed.emit()
	_check(not hideout.modal_scrim.visible and not hideout.destination_panel.visible and hideout.current_panel == null, "the map close button must return to the hideout")

	hideout.transition_duration = 0.0
	hideout.door_button.pressed.emit()
	hideout.destination_dungeon_button.pressed.emit()
	var dungeon_transition := await _wait_for_scene("res://main.tscn")
	_check(bool(dungeon_transition.get("saw_loading", false)), "dungeon travel must visibly pass through the animated loading screen")
	_check(current_scene != null and current_scene.scene_file_path == "res://main.tscn", "the dungeon destination must transition to the realtime dungeon scene")
	_check(get_first_node_in_group("player") != null, "dungeon destination must spawn the realtime player")
	_check(get_first_node_in_group("enemy") != null, "dungeon destination must spawn realtime encounters")
	_check(ExpeditionSession.get_inventory() == session_inventory and ExpeditionSession.crowns == 73, "entering the dungeon from the hideout must preserve the active session")

	_finish()


func _wait_for_scene(scene_path: String, timeout_msec := SCENE_TRANSITION_TIMEOUT_MSEC) -> Dictionary:
	var saw_loading := _loading_screen_is_present()
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		saw_loading = saw_loading or _loading_screen_is_present()
		var scene := current_scene
		if scene != null and scene.scene_file_path == scene_path and not _loading_screen_is_present():
			return {"reached": true, "saw_loading": saw_loading}
		await process_frame
	_check(false, "scene transition to %s must finish and dismiss its loading overlay before the timeout" % scene_path)
	return {"reached": false, "saw_loading": saw_loading}


func _loading_screen_is_present() -> bool:
	if current_scene is SanctuaryLoadingScreen:
		return true
	for node in root.find_children("*", "", true, false):
		if node is SanctuaryLoadingScreen:
			return true
	return false


func _send_escape(hideout: SanctuaryHideout) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	hideout._unhandled_input(event)


func _send_space_through_input() -> void:
	var pressed_event := InputEventKey.new()
	pressed_event.keycode = KEY_SPACE
	pressed_event.physical_keycode = KEY_SPACE
	pressed_event.pressed = true
	Input.parse_input_event(pressed_event)
	await process_frame
	var released_event := InputEventKey.new()
	released_event.keycode = KEY_SPACE
	released_event.physical_keycode = KEY_SPACE
	released_event.pressed = false
	Input.parse_input_event(released_event)
	await process_frame


func _within_viewport(control: Control) -> bool:
	var rect := control.get_global_rect()
	return rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 1280.0 and rect.end.y <= 720.0


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("HIDEOUT FLOW TEST PASS: hidden map, door reveal, close actions, and dungeon transition")
		quit(0)
		return
	for failure in failures:
		push_error("HIDEOUT FLOW TEST FAIL: %s" % failure)
	quit(1)
