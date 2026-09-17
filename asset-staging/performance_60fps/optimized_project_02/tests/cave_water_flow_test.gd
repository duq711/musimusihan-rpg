extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const CAVE_PATH := "res://cave_dungeon.tscn"
const FEATURE := "cave_zone:west_pool"
const SCENE_TIMEOUT_MSEC := 120000
const LAYOUT := preload("res://scripts/cave_layout.gd")
const ART_TRIAL := preload("res://tests/cave_art_trial_checks.gd")
var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 547
	ExpeditionSession.hunger = 42.0
	ExpeditionSession.thirst = 68.0
	ExpeditionSession.stress = 23.0
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 11)
	var original_slots := original.slots.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	var found: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == FEATURE)
	_check(found.size() == 1 and found[0].action == "cave_zone" and found[0].payload == "west_pool", "water walking must have one executable actual cave visit in the test room")
	_check(sandbox.active and bag != original and paused and room.panel_open, "water trial must start inside a paused isolated expedition")
	for iteration in range(2):
		room.run_feature(FEATURE)
		if not await _wait_for_scene(CAVE_PATH):
			break
		var cave := current_scene as Node3D
		var player: DungeonPlayer = cave.player
		var water: Node = cave.cave_geometry.get("water_system")
		_check(water != null, "the test destination must contain the real cave water system")
		if water == null:
			break
		var expected := LAYOUT.room_position("west_pool")
		_check(Vector2(player.position.x, player.position.z).distance_to(Vector2(expected.x, expected.z)) < 0.5, "the actual player must begin beside the lower west pool")
		_check(cave.inventory == bag and sandbox.pending_cave_entry_room.is_empty(), "water entry must consume its position once and keep the sandbox bag")
		_check(cave.enemies_alive == 6 and cave.loot_chests.size() == 5, "water trial must keep the real playable mine rather than a demonstration scene")
		failures.append_array(await ART_TRIAL.inspect(cave))
		# Stop unrelated encounters, but retain real player movement and the
		# water node's production physics callback and bound-player tracking.
		cave.set_process(false)
		for actor in cave.get_children():
			if actor is DungeonEnemy:
				actor.set_physics_process(false)
		var initial: Dictionary = water.call("get_state_snapshot")
		_check(initial.pool_count == 6 and initial.total_ripples == 0, "each repeated water trial must construct six pools with a fresh ripple history")
		var wet_point := Vector3(-54.3, 0.0, -18.0)
		var surface: Dictionary = water.call("sample_surface", wet_point)
		_check(not surface.is_empty() and surface.get("id", "") == "lower_west_water", "walking fixture must use the actual shallow pool polygon")
		player.position = Vector3(wet_point.x, cave.cave_geometry.floor_height(Vector2(wet_point.x, wet_point.z)) + 0.91, wet_point.z)
		player.rotation = Vector3(0.0, PI, 0.0)
		player.velocity = Vector3.ZERO
		for frame in range(15):
			await physics_frame
		var ready: Dictionary = water.call("get_state_snapshot")
		var start := player.position
		# This macOS headless display cannot capture the cursor, so the input
		# gate deliberately refuses WASD. Drive the actual CharacterBody motion
		# at walking speed while leaving collision and the bound water callback
		# intact; no ripple is inserted directly by this integration test.
		player.set_physics_process(false)
		for frame in range(35):
			player.velocity = Vector3(0.0, -0.3, 3.0)
			player.move_and_slide()
			await physics_frame
		player.velocity = Vector3.ZERO
		for frame in range(12):
			await physics_frame
		var walked: Dictionary = water.call("get_state_snapshot")
		print("WATER FLOW WALK: start=%s end=%s velocity=%s grounded=%s mouse=%d ready=%s walked=%s" % [str(start), str(player.position), str(player.velocity), str(player.is_on_floor()), Input.mouse_mode, str(ready), str(walked)])
		_check(player.position.z - start.z > 1.0, "water trial must move the real CharacterBody through the pool using actual collision movement")
		_check(walked.total_ripples > ready.total_ripples and walked.ripple_count > 0 and walked.last_pool == "lower_west_water", "real grounded footsteps must emit visible-water ripple state through the bound player callback")
		var still_count: int = walked.total_ripples
		for frame in range(24):
			await physics_frame
		_check(water.call("get_state_snapshot").total_ripples == still_count, "standing still after walking must stop creating new ripples")
		paused = true
		var pause_clock: float = water.call("get_state_snapshot").clock
		await create_timer(0.05, true).timeout
		_check(is_equal_approx(water.call("get_state_snapshot").clock, pause_clock), "pausing the water trial must freeze its water simulation")
		paused = false
		bag.remove_item("wooden_arrow", 1)
		ExpeditionSession.crowns += 3
		_check(sandbox.saved_session == snapshot and original.slots == original_slots, "water footsteps and trial consumption must not change the saved original expedition")
		var f2 := InputEventKey.new()
		f2.keycode = KEY_F2
		f2.pressed = true
		sandbox._input(f2)
		if not await _wait_for_scene(ROOM_PATH):
			break
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 must restore the paused menu and current water-trial bag")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room.reset_room()
		_check(sandbox.pending_cave_entry_room.is_empty() and sandbox.saved_session == snapshot, "reset after water testing must clear only trial state")
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "water trial exit must restore original bag identity and all expedition fields")
	# Keep failures visible, but never leave a timed-out test expedition active.
	if sandbox.active:
		sandbox.finish()
	Input.action_release("move_forward")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("CAVE WATER FLOW PASS: actual art direction, torch comparison, water-edge visit, bound-player walking ripples, rest, pause, repeated F2 return, reset and complete expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _wait_for_scene(path: String) -> bool:
	var started := Time.get_ticks_msec()
	var deadline := started + SCENE_TIMEOUT_MSEC
	while true:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			print("WATER FLOW TRANSITION: %s completed in %.2fs" % [path, (Time.get_ticks_msec() - started) / 1000.0])
			await process_frame
			return true
		# A synchronous scene construction can complete inside one long frame.
		# Inspect completion before rejecting that frame for its elapsed time.
		if Time.get_ticks_msec() >= deadline:
			break
		await process_frame
	_check(false, "water trial scene transition timed out after %.2fs: %s (current=%s)" % [(Time.get_ticks_msec() - started) / 1000.0, path, current_scene.scene_file_path if is_instance_valid(current_scene) else "none"])
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
