extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const CAVE_PATH := "res://cave_dungeon.tscn"
const LAYOUT := preload("res://scripts/cave_layout.gd")
const ART_TRIAL := preload("res://tests/cave_art_trial_checks.gd")
var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 13)
	original.equipment["weapon"] = "hunting_bow"
	ExpeditionSession.crowns = 719
	ExpeditionSession.hunger = 61.0
	ExpeditionSession.thirst = 43.0
	ExpeditionSession.stress = 32.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "contact trials must start inside the paused isolated test room")
	for id in ["wall_equipment", "cave_zone:entrance"]:
		var found: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == id)
		_check(found.size() == 1, "contact feature must have exactly one executable catalog entry: " + id)
	var equipment := bag.equipment.duplicate(true)
	var slots := bag.slots.duplicate(true)
	room.run_feature("wall_equipment")
	room.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not room.panel_open and not paused and room.enemies_alive == 0 and room.loot_chests.is_empty(), "wall trial must resume play with unrelated encounters removed")
	_check(room.player.position.distance_to(Vector3(8.0, 1.0, -15.3)) < 0.02, "wall trial must position the real player at the actual north wall")
	var ray := PhysicsRayQueryParameters3D.create(room.player.camera.global_position, room.player.camera.global_position + Vector3(0.0, 0.0, -3.0), DungeonPlayer.WORLD_LAYER)
	var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(ray)
	_check(not hit.is_empty() and is_equal_approx(hit.position.z, -16.7), "wall trial must face a real colliding wall, not a mock result")
	_check(bag.equipment == equipment and bag.slots == slots, "wall trial must preserve current equipment and bag for all weapon comparisons")
	room.player.position.z = -16.29
	room.player.health = 37.0
	room._show_test_panel()
	var paused_hunger := ExpeditionSession.hunger
	await create_timer(0.04, true).timeout
	_check(paused and room.panel_open and is_equal_approx(ExpeditionSession.hunger, paused_hunger), "wall trial menu must pause survival")
	room.run_feature("wall_equipment")
	_check(room.player.health == 100.0 and room.player.position.distance_to(Vector3(8.0, 1.0, -15.3)) < 0.02, "wall trial must restore health and starting distance when reselected")
	_check(bag.equipment == equipment and bag.slots == slots, "wall trial reselection must keep selected equipment")
	for iteration in range(2):
		room._show_test_panel()
		room.run_feature("cave_zone:entrance")
		if not await _wait_for_scene(CAVE_PATH):
			break
		var cave := current_scene as Node3D
		cave.player.set_physics_process(false)
		var expected := LAYOUT.room_position("entrance")
		_check(Vector2(cave.player.position.x, cave.player.position.z).distance_to(Vector2(expected.x, expected.z)) < 0.45, "entry dressing trial must load the actual cave at its entrance")
		_check(cave.cave_geometry != null and cave.enemies_alive == 6 and cave.loot_chests.size() == 5, "entry contact trial must retain real mine geometry and encounters")
		_check(cave.inventory == bag and sandbox.pending_cave_entry_room.is_empty(), "entry trial must use only its sandbox bag and consume the visit once")
		failures.append_array(await ART_TRIAL.inspect(cave))
		_check(sandbox.saved_session == snapshot and original.slots == original_slots, "both contact trials must preserve the original expedition")
		bag.remove_item("wooden_arrow", 1)
		var f2 := InputEventKey.new()
		f2.keycode = KEY_F2
		f2.pressed = true
		sandbox._input(f2)
		if not await _wait_for_scene(ROOM_PATH):
			break
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 from contact inspection must restore the paused test room and current trial bag")
	if current_scene != null and current_scene.scene_file_path == ROOM_PATH:
		room.reset_room()
		_check(sandbox.pending_cave_entry_room.is_empty() and sandbox.saved_session == snapshot, "contact trial reset must clear one-shot positions and retain the original snapshot")
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "ending contact trials must restore original inventory identity and all saved expedition values")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("CONTACT TEST ROOM PASS: actual wall fixture, gear preservation, entrance art direction and torch comparison, repeated F2 return, reset and complete original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


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
	_check(false, "contact trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
