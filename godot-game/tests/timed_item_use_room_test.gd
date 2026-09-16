extends "res://tests/body_health_test_room_test.gd"

# Focused production test-room coverage; asynchronous hideout/menu streaming is
# covered independently by the complete body-health scene-route suite.
func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("black_salt", 3)
	ExpeditionSession.hunger = 43.0
	ExpeditionSession.apply_condition("curse", 93.0, "right_arm")
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var mouse_before := Input.mouse_mode
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original and paused, "Trial starts in an isolated paused expedition")
	_check_timed_use_trial()
	room.run_feature("timed_item_use")
	var count: int = room.inventory.count_item("healing_draught")
	var hp: float = room.player.get_body_health_snapshot().parts.left_arm.health
	room.hud.combat_panel.activate_slot(3)
	room.player.advance_item_use(3.0)
	_check(room.inventory.count_item("healing_draught") == count - 1 and room.player.get_body_health_snapshot().parts.left_arm.health > hp, "Actual trial completion consumes and heals exactly once")
	room.player.advance_item_use(3.0)
	_check(room.inventory.count_item("healing_draught") == count - 1, "Completed action cannot repeat")
	_check(original.slots == original_slots and sandbox.saved_session == original_snapshot, "Trial leaves original saved state untouched")
	paused = false
	room.free()
	current_scene = null
	sandbox.finish()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == original_snapshot and original.slots == original_slots, "Sandbox exit restores exact original session and inventory identity")
	_check(Input.mouse_mode == mouse_before, "Trial preserves cursor mode")
	for failure in failures:
		push_error(failure)
	print("TIMED ITEM USE ROOM %s: real catalog, quick slot, inventory, F cancellation, F2/reset, completion and sandbox restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
