extends SceneTree

const CATALOG := preload("res://scripts/test_room_catalog.gd")
const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const HIDDEN_CARDS := ["LocationCard", "SurvivalCard", "LivingGuide", "ControlLegend"]

var failures: Array[String] = []
var sandbox: Node
var room: Node3D
var trial_bag: ExpeditionInventory


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("liquor_hearth_brandy_normal", 2)
	ExpeditionSession.crowns = 637
	ExpeditionSession.hunger = 48.0
	ExpeditionSession.thirst = 37.0
	ExpeditionSession.stress = 29.0
	ExpeditionSession.apply_condition("bleeding", 93.0)
	var original_slots := original.slots.duplicate(true)
	var notifications: Array[int] = []
	var observer := func() -> void: notifications.append(1)
	original.changed.connect(observer)
	var snapshot := ExpeditionSession.capture_snapshot()
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	trial_bag = room.inventory
	_check(sandbox.active and trial_bag != original and room.panel_open and paused, "the HUD trial must begin in the paused isolated test room")
	var entries: Array = CATALOG.entries().filter(func(entry: Dictionary) -> bool: return str(entry.id) == "hideout")
	_check(entries.size() == 1 and str(entries[0].category) == "장면" and str(entries[0].action) == "scene" and str(entries[0].payload) == HIDEOUT_PATH, "the existing hideout trial must run the actual production scene")
	_check(entries.size() == 1 and str(entries[0].detail).contains("조준선") and str(entries[0].detail).contains("F2"), "the live trial must describe enlarged aiming and its repeatable return route")
	for visit in 2:
		if not await _enter_hideout():
			break
		var hideout := current_scene as SanctuaryHideout
		_check_clear_play_screen(hideout, "entry %d" % visit)
		if visit == 0:
			_test_contextual_controls(hideout)
		_check(original.slots == original_slots and notifications.is_empty(), "the real scene and its menus must not touch original inventory or notify its listeners")
		if not await _return_to_room():
			break
		var menu_snapshot := ExpeditionSession.capture_snapshot()
		var menu_position: Vector3 = room.player.global_position
		for frame in 3:
			await process_frame
		_check(paused and ExpeditionSession.capture_snapshot() == menu_snapshot and room.player.global_position == menu_position, "F2 menu must stop movement and survival between repeated HUD trials")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		var previous_bag := trial_bag
		room.reset_room()
		trial_bag = room.inventory
		_check(trial_bag != previous_bag and trial_bag != original and sandbox.saved_session == snapshot, "reset must replace only the trial inventory and preserve the original expedition snapshot")
		if await _enter_hideout():
			_check_clear_play_screen(current_scene as SanctuaryHideout, "entry after reset")
			await _return_to_room()
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "leaving must restore the exact original bag, equipment, wallet, stock and survival state")
	_check(original.slots == original_slots and original.changed.is_connected(observer) and notifications.is_empty(), "original items and inventory listeners must survive entry, F2, reset and exit")
	original.changed.disconnect(observer)
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("HIDEOUT HUD TEST PASS: hidden persistent cards/button, centered double-size dot, actual map/inventory/pause/workshop/cooking feedback, repeated F2/reset and exact original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT HUD TEST FAIL: " + failure)
		quit(1)


func _check_clear_play_screen(hideout: SanctuaryHideout, context: String) -> void:
	_check(hideout != null and hideout.scene_file_path == HIDEOUT_PATH and hideout.inventory == trial_bag and hideout.player.safe_zone_mode, "the HUD check must use the real safe-zone player and isolated bag: " + context)
	if hideout == null:
		return
	var hud := hideout.hideout_hud as HideoutHUD
	_check(hud != null and hud.visible and hideout.hideout_mode == SanctuaryHideout.HideoutMode.RUNNING and not paused, "normal play must restore the actual HUD and game mode: " + context)
	if hud == null:
		return
	for card_name in HIDDEN_CARDS:
		var card := hud.find_child(card_name, true, false) as Control
		_check(card != null and not card.visible and not card.is_visible_in_tree(), "persistent card must stay absent: " + card_name + "/" + context)
	_check(is_instance_valid(hideout.door_button) and not hideout.door_button.visible and not hideout.door_button.is_visible_in_tree(), "persistent map shortcut must stay absent: " + context)
	_check(hud.crosshair.visible and hud.crosshair.is_visible_in_tree() and hud.crosshair.text == "·" and hud.crosshair.get_theme_font_size("font_size") == 56, "the original aiming dot must remain visible at twice its former font size: " + context)
	_check(hud.crosshair.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER and hud.crosshair.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "the larger dot must align to the center on both axes: " + context)
	var hud_root := hud.crosshair.get_parent() as Control
	_check(hud.crosshair.get_global_rect().get_center().distance_to(hud_root.get_global_rect().get_center()) < 1.0, "the expanded aiming box must remain centered on the actual viewport: " + context)
	_check(not hud.interaction_panel.visible and not hud.overlay.visible and not hideout.destination_panel.visible and not hideout.inventory_overlay.is_open(), "contextual overlays must be closed during ordinary exploration: " + context)


func _test_contextual_controls(hideout: SanctuaryHideout) -> void:
	var hud := hideout.hideout_hud as HideoutHUD
	_send_key(hideout, KEY_M)
	_check(hideout.hideout_mode == SanctuaryHideout.HideoutMode.MAP and hideout.destination_panel.is_visible_in_tree() and paused, "M must open the actual travel map without the removed persistent button")
	_send_key(hideout, KEY_ESCAPE)
	_check_clear_play_screen(hideout, "map closed")
	_send_key(hideout, KEY_I)
	_check(hideout.hideout_mode == SanctuaryHideout.HideoutMode.INVENTORY and hideout.inventory_overlay.is_open() and paused, "I must still open the actual paused inventory")
	_send_key(hideout, KEY_ESCAPE)
	_check_clear_play_screen(hideout, "inventory closed")
	_send_key(hideout, KEY_ESCAPE)
	_check(hideout.hideout_mode == SanctuaryHideout.HideoutMode.PAUSED and hud.overlay.is_visible_in_tree() and paused, "Escape must still show the real pause overlay")
	_send_key(hideout, KEY_ESCAPE)
	_check_clear_play_screen(hideout, "pause resumed")
	var pot := hideout.find_child("CookingPotInteraction", true, false) as HideoutInteractable
	_check(pot != null, "the actual world must retain its E cooking interaction")
	if pot != null:
		pot.interact(hideout.player)
		_check(hideout.player.timed_interaction_owner == pot and hud.interaction_panel.is_visible_in_tree(), "using the real pot must show its existing timed interaction feedback")
		hideout.player.advance_timed_interaction(0.1)
		_check(hud.interaction_progress.value > 0.0 and hud.interaction_progress.value < hud.interaction_progress.max_value, "real interaction time must advance the visible progress meter")
		hideout.player.advance_timed_interaction(0.3)
		_check(hideout.hideout_mode == SanctuaryHideout.HideoutMode.COOKING and hideout.cooking_controller.is_open() and paused, "completing the real pot interaction must open the kitchen")
		hideout.cooking_controller.close_kitchen()
		_check_clear_play_screen(hideout, "cooking closed")
	hideout._open_blacksmith()
	_check(hideout.blacksmith_overlay.is_open() and paused, "the real smithing menu must remain available")
	hideout.blacksmith_overlay.close()
	_check_clear_play_screen(hideout, "smithing closed")
	hideout._open_alchemy()
	_check(hideout.alchemy_overlay.is_open() and paused, "the real alchemy menu must remain available")
	hideout.alchemy_overlay.close()
	_check_clear_play_screen(hideout, "alchemy closed")
	hud.update_survival(21.0, 32.0)
	hud.update_conditions({"bleeding": 10.0}, 1.2)
	hud.update_torch(false)
	_check_clear_play_screen(hideout, "status refreshed")


func _enter_hideout() -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "the live HUD trial must start from the actual test room")
		return false
	room = current_scene as Node3D
	room.run_feature("hideout")
	if not await _wait_for_scene(HIDEOUT_PATH):
		return false
	# Headless UI checks drive the actual timer directly, without requiring
	# pointer capture or allowing unrelated safe-zone physics between steps.
	current_scene.player.set_physics_process(false)
	return true


func _return_to_room() -> bool:
	var departing := current_scene
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.pressed = true
	sandbox._input(event)
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(not is_instance_valid(departing) and room.panel_open and paused and room.inventory == trial_bag, "F2 must free the hideout and return to the same isolated bag and paused trial menu")
	return returned


func _send_key(hideout: SanctuaryHideout, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	hideout._unhandled_input(event)


func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "actual HUD trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
