extends "res://tests/body_health_test_room_test.gd"
## Bounded real test-room coverage; unrelated hideout loading is tested separately.
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
	_check(room.inventory != original and sandbox.active, "trial must use an isolated bag")
	_check_splint_trial()
	room.run_feature("splint_forearm")
	room.player._update_viewmodel(3.0)
	room.player.advance_item_use(3.0)
	room.player.handle_torch_action()
	_check(room.inventory.count_item("splint") == 3 and ExpeditionSession.condition_affects_part("fracture", "left_arm") and not room.player.splint_hands.active, "real F dispatch cancels without consuming or curing")
	_f2_menu()
	room.run_feature("splint_forearm")
	room._recover_player()
	_check(not room.player.is_item_use_active() and not room.player.splint_hands.active, "recovery clears timer and temporary geometry")
	room.reset_room()
	_check(not room.player.is_item_use_active() and not room.player.splint_hands.active, "reset clears presentation")
	paused = false
	room.queue_free()
	current_scene = null
	await process_frame
	sandbox.finish()
	print("SPLINT_RESTORE state=", ExpeditionSession.capture_snapshot() == original_snapshot, " bag=", ExpeditionSession.get_inventory() == original, " slots=", original.slots == original_slots, " cursor=", Input.mouse_mode, "/", cursor)
	var restored := ExpeditionSession.capture_snapshot()
	for key in original_snapshot:
		if restored.get(key) != original_snapshot[key]: print("SPLINT_RESTORE_DIFFERENCE ", key)
	_check(ExpeditionSession.capture_snapshot() == original_snapshot and ExpeditionSession.get_inventory() == original and original.slots == original_slots and Input.mouse_mode == cursor, "original expedition, bag identity, contents and cursor restore exactly")
	for failure in failures: push_error(failure)
	print("SPLINT TEST ROOM %s: catalog, timed use, F/F2, repeat, recovery, reset, exact restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
