extends "res://tests/body_health_test_room_test.gd"

func _run() -> void:
	var original := ExpeditionSession.get_inventory()
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var cursor := Input.mouse_mode
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.player.set_physics_process(false)
	_check(room.inventory != original and sandbox.active, "Trial must use an isolated bag")
	var trial_entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "jerky_eat")
	_check(trial_entries.size() == 1 and trial_entries[0].action == "jerky_eat" and trial_entries[0].category == "생존", "Jerky has one executable survival trial")
	var item_entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:beef_jerky")
	_check(item_entries.size() == 1, "Jerky item is automatically registered exactly once")
	var stocked_in_chest := false
	for chest: DungeonLootChest in room.loot_chests:
		for stack: Dictionary in chest.container.items:
			if stack.id == "beef_jerky" and int(stack.quantity) > 0: stocked_in_chest = true
	_check(stocked_in_chest, "Production item catalog also stocks jerky in a trial supply chest")
	room.run_feature("jerky_eat")
	_check(room.player.jerky_hands.active and room.player.is_item_use_active() and room.inventory.count_item("beef_jerky") == 3, "Trial starts actual player food use with three portions")
	_check(ExpeditionSession.hunger == 35.0, "Trial prepares repeatable hunger")
	room.player._update_viewmodel(1.0)
	room.player.advance_item_use(1.0)
	_check(room.player.jerky_hands.equipment_hidden() and not room.player.weapon_pivot.visible and not room.player.shield_pivot.visible, "Eating puts actual weapons away")
	_f2_menu()
	_check(not room.player.jerky_hands.active and not room.player.is_item_use_active() and room.inventory.count_item("beef_jerky") == 3 and ExpeditionSession.hunger == 35.0, "F2 cancels without consuming or feeding")
	room.run_feature("jerky_eat")
	for frame in 81:
		room.player._update_viewmodel(0.1)
		room.player.advance_item_use(0.1)
	_check(room.inventory.count_item("beef_jerky") == 2 and is_equal_approx(ExpeditionSession.hunger, 67.0), "Production completion consumes one and applies existing food effect")
	_check(not room.player.is_item_use_active() and not room.player.jerky_hands.active and room.player.weapon_pivot.visible, "Completion clears temporary hands and restores weapons")
	_f2_menu()
	room.run_feature("jerky_eat")
	_check(room.inventory.count_item("beef_jerky") == 3 and ExpeditionSession.hunger == 35.0, "Reselecting restocks the exact fixture")
	room.player._update_viewmodel(3.0)
	room.player.advance_item_use(3.0)
	room.player.handle_torch_action()
	_check(room.inventory.count_item("beef_jerky") == 3 and ExpeditionSession.hunger == 35.0 and not room.player.jerky_hands.active, "Actual F dispatch cancels the meal and motion")
	_f2_menu()
	room.run_feature("jerky_eat")
	room._recover_player()
	_check(not room.player.is_item_use_active() and not room.player.jerky_hands.active, "Recovery clears timer and temporary geometry")
	room.run_feature("jerky_eat")
	room.reset_room()
	_check(not room.player.is_item_use_active() and not room.player.jerky_hands.active, "Reset clears the meal presentation")
	_check(original.slots == original_slots and sandbox.saved_session == original_snapshot, "All trials leave the saved original expedition untouched")
	paused = false
	room.queue_free()
	current_scene = null
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original_snapshot and ExpeditionSession.get_inventory() == original and original.slots == original_slots and Input.mouse_mode == cursor, "Original expedition, bag identity, contents and cursor restore exactly")
	for failure in failures: push_error(failure)
	print("육포 테스트룸 검사 / JERKY TEST ROOM %s: auto catalog, real food use, weapon return, F/F2, repeat, recovery, reset and exact restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
