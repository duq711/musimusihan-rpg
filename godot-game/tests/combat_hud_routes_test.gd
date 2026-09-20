extends SceneTree
## Real test-room entry and menu routes, without unrelated scene streaming.

var failures: Array[String] = []
var room: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# These production routes set mouse mode and focus; only the dummy display
	# may execute them here. Visual verification uses the isolated preview.
	if DisplayServer.get_name() != "headless":
		push_error("Combat HUD route tests require run_headless_tests.sh.")
		quit(2)
		return
	root.gui_disable_input = true
	AudioServer.set_bus_mute(0, true)
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("black_salt", 3)
	ExpeditionSession.hunger = 43.0
	ExpeditionSession.apply_condition("curse", 93.0, "right_arm")
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.player.set_physics_process(false)
	var player: DungeonPlayer = room.player
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "Test-room entry starts in its isolated F2 menu")
	_check(room.hud.combat_enabled and is_instance_valid(room.hud.combat_panel), "Test-room entry initializes the new HUD before selecting any feature")
	if is_instance_valid(room.hud.combat_panel):
		_check_visibility(false, "Initial F2 menu")
		_f2()
		_check(not room.panel_open and not paused, "F2 resumes the default room without a dedicated HUD trial")
		_check_visibility(true, "Default room resume")
		for feature_id in ["movement", "dungeon_combat_hud", "movement"]:
			_f2()
			_check_visibility(false, "F2 menu before " + feature_id)
			room.run_feature(feature_id)
			_check(not room.panel_open and not paused, "Feature enters live play: " + feature_id)
			_check_visibility(true, "Feature keeps the new HUD: " + feature_id)
			_check(room.player == player and room.inventory == bag and room.hud.combat_panel.player == player and room.hud.combat_panel.bag == bag, "Feature preserves the actual HUD bindings: " + feature_id)
		_f2()
		_check_visibility(false, "F2 pauses an active trial")
		_f2()
		_check_visibility(true, "F2 resumes the same trial")
		room._open_inventory()
		_check(room.inventory_overlay.is_open() and paused, "Real inventory route opens and pauses")
		_check_visibility(false, "Inventory hides the combat HUD")
		room._close_inventory()
		_check(not room.inventory_overlay.is_open() and not paused, "Real inventory close resumes play")
		_check_visibility(true, "Inventory close restores the combat HUD")
		_check(room.hud.combat_panel.player == player and room.hud.combat_panel.bag == bag, "Menu cycles keep the original live player and inventory binding")
		_check_spell_and_quick_slot_routes()
	_check(original.slots == original_slots and sandbox.saved_session == original_snapshot, "Testing leaves the preserved expedition and its inventory untouched")
	paused = false
	room.suspend_stress_effects()
	room.free()
	current_scene = null
	sandbox.finish()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == original_snapshot and original.slots == original_slots, "Exiting restores the exact saved session and inventory identity")
	_check(Input.mouse_mode == mouse_before, "Headless route verification preserves cursor mode")
	for failure in failures:
		push_error(failure)
	print("COMBAT HUD ROUTES TEST %s: default test-room entry, feature changes, F2, inventory, spell/quick-slot methods and sandbox restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _f2() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_F2
	event.pressed = true
	room._unhandled_input(event)


func _check_spell_and_quick_slot_routes() -> void:
	# The dummy display keeps mouse_mode VISIBLE even after requesting CAPTURED.
	# Therefore the player's capture-gated _unhandled_input cannot be exercised
	# here. Check the real trial and the underlying spell/panel methods instead;
	# do not weaken the production gate or claim desktop input verification.
	var mouse_before := Input.mouse_mode
	_f2()
	room.run_feature("spell:fire_bolt")
	ExpeditionSession.learn_spell("water_bolt")
	var player: DungeonPlayer = room.player
	var bag: ExpeditionInventory = room.inventory
	_check(not paused and bag.equipment.weapon == "weathered_staff" and ExpeditionSession.selected_spell == "fire_bolt", "Actual spell trial prepares a staff and selected fire spell")
	# The spell fixture sets its staff directly instead of returning the old
	# weapon to the bag; explicitly supply a sword for this quick-slot check.
	if bag.count_item("rusted_sword") == 0:
		bag.add_item("rusted_sword", 1)
	var slots_before := bag.slots.duplicate(true)
	var equipment_before := bag.equipment.duplicate(true)
	_check(player.select_spell_by_slot(1) and ExpeditionSession.selected_spell == "water_bolt", "Production spell selection changes to the second learned spell")
	var event := InputEventKey.new()
	event.physical_keycode = KEY_2
	event.keycode = KEY_2
	event.pressed = true
	event.alt_pressed = true
	_check(not room.hud.combat_panel.handle_shortcut(event), "Combat quick slots leave Alt+2 unhandled for spell selection")
	_check(bag.equipment == equipment_before and bag.slots == slots_before, "Spell selection and ignored Alt+2 change no equipment or quantities")
	event.physical_keycode = KEY_1
	event.keycode = KEY_1
	event.alt_pressed = false
	_check(room.hud.combat_panel.handle_shortcut(event) and bag.equipment.weapon == "rusted_sword", "Production quick-slot handler equips the available sword on plain 1")
	_check(ExpeditionSession.selected_spell == "water_bolt", "The sword quick slot preserves the selected spell")
	_check_visibility(true, "Spell and item shortcuts retain the new HUD")
	Input.mouse_mode = mouse_before
	_check(Input.mouse_mode == mouse_before, "Spell/quick-slot verification preserves its incoming cursor mode")
	print("COMBAT HUD INPUT SCOPE: production spell and quick-slot methods checked; headless mouse capture does not support player._unhandled_input verification.")


func _check_visibility(expected: bool, context: String) -> void:
	# Run the production always-processing HUD update at this exact state.
	room.hud._process(0.0)
	_check(room.hud.combat_enabled and room.hud.combat_panel.is_visible_in_tree() == expected, context)
	_check(room.hud.crosshair.text.is_empty(), context + ": legacy center dot remains disabled")
	for legacy: Control in room.hud.legacy_panels:
		_check(not legacy.visible, context + ": legacy status cards remain hidden")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
