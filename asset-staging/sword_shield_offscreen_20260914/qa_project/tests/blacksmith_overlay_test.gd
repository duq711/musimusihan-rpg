extends SceneTree
const OVERLAY := preload("res://scripts/blacksmith_overlay.gd")
const SYSTEM := preload("res://scripts/smithing_system.gd")
const PREVIEW := preload("res://tests/blacksmith_preview.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	for id: String in SYSTEM.trial_supplies(): bag.add_item(id, SYSTEM.trial_supplies()[id])
	var smith := OVERLAY.new()
	root.add_child(smith)
	smith.open_for_inventory(bag)
	smith.set_process(false)
	_check(smith.is_open() and smith.scene_viewport.own_world_3d, "production workbench UI must open into a real independent 3D viewport")
	_check(smith.scene_viewport.get_camera_3d() == smith.camera and smith.visual.get_meta("blacksmith_real_geometry", false), "UI must contain production geometry and camera")
	_check(smith.perform_action("start", "iron_longsword").accepted, "real UI action must consume recipe")
	for index in 6: smith.perform_action("pump_bellows")
	_check(smith.perform_action("move_to_anvil").accepted, "real UI must move heated iron")
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(400, 330)
	smith._work_surface_input(down)
	smith._held_time = 0.75
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	smith._work_surface_input(up)
	_check(float(smith.system.sections[0][1]) == 0.5, "mouse press/release timing must drive real selected blade section")
	_check(smith.progress_label.text.contains("8%"), "normalized six-section progress must display percent")
	for tab in ["grip", "blade"]:
		smith.show_station(tab)
		var pending: Dictionary = smith.system.snapshot()
		smith._work_surface_input(down)
		smith._held_time = 0.75
		smith._work_surface_input(up)
		for key in [KEY_SPACE, KEY_E, KEY_R, KEY_F, KEY_Q]:
			var key_event := InputEventKey.new()
			key_event.physical_keycode = key
			key_event.pressed = true
			smith._input(key_event)
		_check(smith.system.snapshot() == pending and not smith.rhythm.visible, "upgrade tab input must not change a hidden unfinished forge workpiece")
	smith.show_station("rune")
	var rune_pending: Dictionary = smith.system.snapshot()
	var return_key := InputEventKey.new()
	return_key.physical_keycode = KEY_F
	return_key.pressed = true
	smith._input(return_key)
	_check(smith.system.snapshot() == rune_pending, "rune tab must not accept forge keyboard shortcuts")
	smith.show_station("forge")
	var heat: float = smith.system.temperature
	smith.close()
	smith._process(30)
	_check(smith.system.temperature == heat and smith.scene_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "closed workshop must stop processing/cooling/rendering while preserving work")
	smith.open_for_inventory(bag)
	_check(smith.system.stage == "anvil", "reopening same hideout workbench must preserve unfinished craft")
	smith.cancel_work()
	_check(smith.system.stage == "idle" and not smith.is_open(), "sandbox cleanup must discard pending work without reopening cursor")
	var bow_bag := ExpeditionInventory.new()
	bow_bag.equipment["weapon"] = "hunting_bow"
	bow_bag.add_item("rusted_sword")
	bow_bag.add_item("grip_leather", 4)
	smith.open_for_inventory(bow_bag)
	smith.show_station("grip")
	_check(smith.weapon_picker.item_count == 1 and not (smith.system.snapshot().selected_weapon as Dictionary).is_empty(), "sole bag sword displayed while bow equipped must be a real selected workpiece")
	_check(smith.perform_action("replace_grip", "leather_grip").accepted, "non-sword loadout must still allow modification of the sole visible bag sword")
	smith.close()
	smith.open_for_inventory(bow_bag)
	smith.show_station("rune")
	_check(not (smith.system.snapshot().selected_weapon as Dictionary).is_empty(), "reopened same inventory must keep its valid sword selection")
	smith.queue_free()
	await process_frame
	_check(Input.mouse_mode == cursor and ExpeditionSession.capture_snapshot() == original, "isolated UI must preserve original expedition and mouse")
	for failure in failures: push_error(failure)
	print("BLACKSMITH OVERLAY %s: production scene, mapped timed input, progress, resume, cancel, hidden renderer contract and state isolation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
