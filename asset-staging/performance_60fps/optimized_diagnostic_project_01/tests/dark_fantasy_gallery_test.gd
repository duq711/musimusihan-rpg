extends SceneTree

const GALLERY := preload("res://scripts/dark_fantasy_gallery.gd")
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const PREVIEW := preload("res://tests/dark_fantasy_gallery_preview.gd")
const ROOM_PATH := "res://test_room.tscn"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 13)
	ExpeditionSession.crowns = 739
	ExpeditionSession.hunger = 53.0
	ExpeditionSession.thirst = 44.0
	ExpeditionSession.stress = 23.0
	ExpeditionSession.apply_condition("bleeding", 34.0)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var gallery := GALLERY.new()
	root.add_child(gallery)
	var entries := CATALOG.entries()
	_check(not entries.any(func(entry: Dictionary) -> bool: return str(entry.id) in ["gravebound_player", "chest_hands"]), "user-completed player body and hands must stay excluded from the active art catalog")
	var ids: Array[String] = []
	var requested := OS.get_environment("DARK_FANTASY_TEST_OBJECTS").split(",", false)
	_check(entries.size() >= 20, "gallery must cover the full production object catalog, not just a player sample")
	for entry in entries:
		var id := str(entry.id)
		if not requested.is_empty() and id not in requested:
			continue
		_check(id.is_valid_filename() and id not in ids and not str(entry.get("factory", "")).is_empty(), "every gallery object needs a unique capture-safe id and production factory provenance: " + id)
		ids.append(id)
		print("GALLERY FACTORY CHECK: " + id)
		_check(gallery.select_object(id), "production factory must produce real nonempty volumetric geometry: " + id)
		if not is_instance_valid(gallery.object_root):
			continue
		_check(gallery.object_root.get_parent() == gallery.stage and gallery.object_root.get_world_3d() == gallery.viewport.find_world_3d(), "the actual object must belong to the isolated viewport: " + id)
		_check(_simulation_disabled(gallery.object_root), "object inspection must never run actor inputs, physics or simulation: " + id)
		_check(gallery.object_bounds.size.is_finite() and gallery.object_bounds.size.length() > 0.001, "capture bounds must come from finite real mesh geometry: " + id)
		for index in GALLERY.VIEWS.size():
			gallery.view_buttons[index].pressed.emit()
			_check(gallery.selected_view == GALLERY.VIEWS[index], "live view button must select its requested direction: " + id)
			var facing := (gallery.camera.position - gallery.object_bounds.get_center()).normalized()
			_check(facing.is_equal_approx(GALLERY.DIRECTIONS[index]), "six cameras must cover distinct front/back/left/right/top/bottom directions: " + id)
			_check(_bounds_in_camera(gallery), "the complete production mesh bounds must fit inside each camera: " + id + "/" + GALLERY.VIEWS[index])
		_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse_mode, "production object construction and six views must preserve expedition and cursor: " + id)
	_check(not gallery.select_object("missing_object") and not gallery.set_view("missing_view"), "invalid gallery selections must be rejected without replacing a valid object")
	gallery.hide()
	_check(gallery.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "hidden gallery must stop rendering")
	gallery.free()
	await process_frame
	_check(requested.is_empty() or ids.size() == requested.size(), "every requested subset object must exist in the active catalog")
	await _test_room_flow(original, snapshot, ids.back() if not ids.is_empty() else "")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("DARK FANTASY GALLERY PASS: %d production factories, actual mesh bounds and six complete views, disabled simulation, repeated paused test-room controls, F2/close/reset cleanup and original expedition restoration" % ids.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_room_flow(original: ExpeditionInventory, saved: Dictionary, selected_id: String) -> void:
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var sandbox := root.get_node("TestRoomSandbox")
	var trial: ExpeditionInventory = room.inventory
	_check(sandbox.active and trial != original and paused and room.panel_open, "gallery test must begin with the ordinary isolated paused test-room session")
	var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "dark_fantasy_gallery")
	_check(matches.size() == 1 and matches[0].action == "dark_fantasy_gallery", "test room must register one executable real-object gallery action")
	for iteration in range(2):
		var trial_before := ExpeditionSession.capture_snapshot()
		room.run_feature("dark_fantasy_gallery")
		await process_frame
		var gallery: Control = room.art_gallery
		_check(is_instance_valid(gallery) and paused and not room.panel_open and room.game_mode == room.GameMode.PAUSED, "gallery action must open the real viewer and keep combat/survival paused")
		if not is_instance_valid(gallery):
			continue
		var entries := CATALOG.entries()
		var selected_index := 0
		for entry_index in entries.size():
			if str(entries[entry_index].id) == selected_id:
				selected_index = entry_index
		gallery.selector.item_selected.emit(selected_index)
		_check(gallery.object_id == str(entries[selected_index].id), "the real object selector must instantiate the selected production factory")
		gallery.view_buttons[4].pressed.emit()
		_check(gallery.selected_view == "top" and gallery.can_process(), "live gallery controls must remain usable while gameplay is paused")
		_check(ExpeditionSession.capture_snapshot() == trial_before and sandbox.saved_session == saved, "inspection must preserve current trial state and the untouched original snapshot")
		var viewport_ref: WeakRef = weakref(gallery.viewport)
		if iteration == 0:
			await _press_f2()
		else:
			gallery.close_button.pressed.emit()
			await process_frame
		_check(room.panel_open and paused and not is_instance_valid(room.art_gallery) and viewport_ref.get_ref() == null, "F2 and the return button must close/free gallery rendering and restore the paused test menu")
	room.run_feature("dark_fantasy_gallery")
	room.reset_room()
	await process_frame
	_check(not is_instance_valid(room.art_gallery) and room.panel_open and paused and room.inventory != trial and sandbox.saved_session == saved, "reset must clean gallery, renew trial inventory and retain the original saved expedition")
	room.run_feature("dark_fantasy_gallery")
	var final_viewport: WeakRef = weakref(room.art_gallery.viewport)
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(final_viewport.get_ref() == null and not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved, "exit must free all gallery render resources and restore the exact original inventory and all expedition values")


func _simulation_disabled(node: Node) -> bool:
	if node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input() or node.process_mode != (Node.PROCESS_MODE_ALWAYS if node is CPUParticles3D else Node.PROCESS_MODE_DISABLED):
		return false
	for child in node.get_children():
		if not _simulation_disabled(child):
			return false
	return true


func _bounds_in_camera(gallery: Control) -> bool:
	for endpoint in range(8):
		var corner: Vector3 = gallery.object_bounds.get_endpoint(endpoint)
		var point: Vector2 = gallery.camera.unproject_position(corner)
		if not point.is_finite() or point.x < 0.0 or point.y < 0.0 or point.x > gallery.viewport.size.x or point.y > gallery.viewport.size.y:
			return false
	return true


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "gallery scene transition timed out: " + path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
