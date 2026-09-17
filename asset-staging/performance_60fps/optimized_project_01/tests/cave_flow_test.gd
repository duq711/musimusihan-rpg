extends SceneTree

const CAVE_PATH := "res://cave_dungeon.tscn"
const ROOM_PATH := "res://test_room.tscn"
const LAYOUT := preload("res://scripts/cave_layout.gd")
const SCENE_TIMEOUT_MSEC := 45000

var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	_check(ResourceLoader.exists(CAVE_PATH), "the new cave must be an executable scene")
	if not ResourceLoader.exists(CAVE_PATH):
		_finish()
		return
	await _test_hideout_entry()
	await _clear_current_scene()
	await _test_sandbox_roundtrip()
	await _clear_current_scene()
	await _test_landmark_entries()
	await _clear_current_scene()
	_finish()


func _test_hideout_entry() -> void:
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 73
	var original := ExpeditionSession.get_inventory()
	var hideout := (load("res://hideout.tscn") as PackedScene).instantiate() as SanctuaryHideout
	root.add_child(hideout)
	current_scene = hideout
	await process_frame
	await process_frame
	_check(not hideout.destination_panel.visible, "the travel map must still start closed")
	hideout.door_button.pressed.emit()
	var cave_button := hideout.destination_cave_button
	_check(cave_button != null and cave_button.is_visible_in_tree(), "the hideout map must expose the cave as a playable destination")
	_check(cave_button.text.contains("검은 물길 동굴") and cave_button.text.contains("131m × 139m"), "the new destination must show its name and exact dimensions")
	_check(_within_viewport(cave_button), "the cave destination must fit the map at 1280 by 720")
	_check(not cave_button.get_global_rect().intersects(hideout.destination_dungeon_button.get_global_rect()) and not cave_button.get_global_rect().intersects(hideout.destination_merchant_button.get_global_rect()), "the new destination must not cover the existing destination actions")
	_check(hideout.destination_dungeon_button.text.contains("성물실") and hideout.destination_merchant_button.text.contains("중개인"), "the original dungeon and merchant must remain selectable")
	_check(hideout.get_viewport().gui_get_focus_owner() == hideout.destination_merchant_button, "the safe merchant destination must retain default keyboard focus")
	_check(hideout.destination_merchant_button.focus_neighbor_right == NodePath("../CaveDestinationButton") and cave_button.focus_neighbor_top == NodePath("../DungeonDestinationButton"), "the cave and original destinations must be connected for keyboard navigation")
	await _send_navigation_key(KEY_RIGHT)
	_check(hideout.get_viewport().gui_get_focus_owner() == cave_button, "right arrow from the merchant must focus the cave")
	await _send_navigation_key(KEY_UP)
	_check(hideout.get_viewport().gui_get_focus_owner() == hideout.destination_dungeon_button, "up arrow from the cave must focus the original dungeon")
	hideout.transition_duration = 0.0
	cave_button.pressed.emit()
	_check(cave_button.disabled and hideout.destination_dungeon_button.disabled and hideout.destination_merchant_button.disabled, "travel must disable all destination actions together")
	if not await _wait_for_scene(CAVE_PATH):
		return
	var cave := current_scene as Node3D
	_check(cave.get_node_or_null("Player") is DungeonPlayer, "the map action must enter the actual realtime cave with a player")
	_check(cave.enemies_alive > 0 and not cave.loot_chests.is_empty(), "the map action must enter a cave with actual encounters and loot")
	_check(cave.inventory == original and ExpeditionSession.crowns == 73, "normal cave travel must keep the active expedition bag and wallet")
	_check(not sandbox.active, "ordinary cave travel must not start a test session")


func _test_sandbox_roundtrip() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 9)
	original.equipment["weapon"] = "hunting_bow"
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	ExpeditionSession.crowns = 257
	ExpeditionSession.hunger = 42.5
	ExpeditionSession.thirst = 57.25
	ExpeditionSession.set_stress(37.5)
	ExpeditionSession.apply_condition("curse", 87.0)
	ExpeditionSession.learn_spell("water_bolt")
	var original_snapshot := ExpeditionSession.capture_snapshot()
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	_check(sandbox.active and room.inventory != original, "cave testing must begin in an isolated trial inventory")
	_check(room.panel_open and paused, "the initial test menu must pause the trial")
	var found := 0
	for entry in room.feature_entries:
		if entry.id == "cave_dungeon":
			found += 1
			_check(entry.category == "장면" and entry.action == "scene" and entry.payload == CAVE_PATH, "the cave catalog entry must connect the real scene through run_feature")
	_check(found == 1, "the cave must have exactly one executable scene catalog entry")
	var trial_inventory: ExpeditionInventory = room.inventory
	room.run_feature("cave_dungeon")
	if not await _wait_for_scene(CAVE_PATH):
		return
	var cave := current_scene as Node3D
	var cave_id := cave.get_instance_id()
	var initial_enemy_count: int = cave.enemies_alive
	var initial_chest_count: int = cave.loot_chests.size()
	_check(cave.inventory == trial_inventory and cave.inventory != original, "run_feature must carry only the trial bag into the actual cave")
	_check(initial_enemy_count > 0 and initial_chest_count > 0, "cave testing must prepare actual enemies and unopened chests")
	_check(sandbox.return_banner.visible, "the connected cave must expose the test return banner")
	var arrows_before := trial_inventory.count_item("wooden_arrow")
	trial_inventory.remove_item("wooden_arrow", 2)
	ExpeditionSession.crowns = 345
	ExpeditionSession.set_stress(66.0)
	_check(original.slots == original_slots and original.equipment == original_equipment, "cave trial consumption must not affect the saved bag or equipment")
	_send_f2()
	if not await _wait_for_scene(ROOM_PATH):
		return
	room = current_scene as Node3D
	_check(room.panel_open and paused and room.player.health == 100.0, "F2 must return to a healthy player and paused test menu")
	_check(room.inventory == trial_inventory and room.inventory.count_item("wooden_arrow") == arrows_before - 2 and ExpeditionSession.crowns == 345, "F2 must keep the cave trial's item consumption and wallet")
	var pause_hunger := ExpeditionSession.hunger
	await create_timer(0.08, true).timeout
	_check(is_equal_approx(ExpeditionSession.hunger, pause_hunger), "the returned test menu must stop survival progression")
	room.run_feature("cave_dungeon")
	if not await _wait_for_scene(CAVE_PATH):
		return
	cave = current_scene as Node3D
	_check(cave.get_instance_id() != cave_id and cave.enemies_alive == initial_enemy_count and cave.loot_chests.size() == initial_chest_count, "reselecting the cave must create a fresh full encounter and loot setup")
	_check(cave.inventory == trial_inventory, "repeated cave entry must preserve the current trial inventory")
	cave.player.receive_environment_damage(999, "동굴 사망 복귀 시험")
	await create_timer(0.35, true).timeout
	_check(cave.game_mode == cave.GameMode.DEAD, "the actual cave must produce the death result")
	var dead_cave_id := cave.get_instance_id()
	var restart_event := InputEventAction.new()
	restart_event.action = "restart"
	restart_event.pressed = true
	cave._unhandled_input(restart_event)
	if not await _wait_for_scene(CAVE_PATH):
		return
	cave = current_scene as Node3D
	_check(cave.get_instance_id() != dead_cave_id and cave.game_mode == cave.GameMode.RUNNING, "R after cave death must restart this cave with a living player")
	_check(cave.inventory != trial_inventory and cave.inventory != original and sandbox.active, "cave restart must refresh only the sandbox journey")
	trial_inventory = cave.inventory
	_check(sandbox.saved_session == original_snapshot, "restarting the cave must not overwrite the saved original expedition")
	cave.player.receive_environment_damage(999, "동굴 재시험 사망 복귀")
	await create_timer(0.35, true).timeout
	_send_f2()
	if not await _wait_for_scene(ROOM_PATH):
		return
	room = current_scene as Node3D
	_check(room.panel_open and room.player.health == 100.0 and room.inventory == trial_inventory, "F2 after cave death must restore a playable test room without touching the original journey")
	room.reset_room()
	_check(room.inventory != trial_inventory and room.inventory != original and ExpeditionSession.crowns == 9999, "reset after cave death must renew only the trial inventory")
	_check(sandbox.saved_session == original_snapshot, "cave travel, death and reset must retain the original saved session")
	room.leave_room()
	if not await _wait_for_scene("res://main_menu.tscn"):
		return
	await process_frame
	_check(not sandbox.active and not sandbox.return_banner.visible, "leaving the trial must finish the sandbox and hide its return control")
	_check(ExpeditionSession.get_inventory() == original and original.slots == original_slots and original.equipment == original_equipment, "leaving cave testing must restore original inventory identity, contents and equipment")
	_check(ExpeditionSession.capture_snapshot() == original_snapshot, "leaving cave testing must restore every original expedition field exactly")


func _test_landmark_entries() -> void:
	var original := ExpeditionSession.get_inventory()
	var snapshot := ExpeditionSession.capture_snapshot()
	_check(not sandbox.prepare_cave_entry("grand_quarry") and sandbox.consume_cave_entry_room().is_empty(), "ordinary play must reject sandbox-only landmark visits")
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var trial_inventory: ExpeditionInventory = room.inventory
	var zones: Array[String] = ["grand_quarry", "bone_cavern", "upper_pool", "pillar_shrine", "hoistroom", "longlake", "workshops"]
	for zone in zones:
		var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "cave_zone:" + zone)
		_check(matching.size() == 1 and matching[0].action == "cave_zone" and matching[0].payload == zone, "every major mine landmark must have one executable test-room action: " + zone)
		room.run_feature("cave_zone:" + zone)
		if not await _wait_for_scene(CAVE_PATH):
			return
		var cave := current_scene as Node3D
		var expected := LAYOUT.room_position(zone)
		var actual: Vector3 = cave.player.global_position
		_check(Vector2(actual.x, actual.z).distance_to(Vector2(expected.x, expected.z)) < 0.45, "landmark action must enter the actual mine at the authored chamber: " + zone)
		_check(cave.enemies_alive == 6 and cave.loot_chests.size() == 5 and cave.get_dungeon_info().chambers == 18, "landmark visits must contain the complete real rebuilt mine and gameplay")
		_check(sandbox.pending_cave_entry_room.is_empty() and sandbox.consume_cave_entry_room().is_empty(), "landmark entry must be consumed once and never survive a restart")
		_check(cave.inventory == trial_inventory and cave.inventory != original and sandbox.saved_session == snapshot, "landmark visits must remain in the isolated test expedition")
		_send_f2()
		if not await _wait_for_scene(ROOM_PATH):
			return
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == trial_inventory, "F2 after landmark inspection must restore the paused test menu and trial bag")
	_check(not sandbox.prepare_cave_entry("missing_room") and sandbox.pending_cave_entry_room.is_empty(), "invalid landmark ids must not leave a pending trial teleport")
	_check(sandbox.prepare_cave_entry("longlake"), "a valid landmark can be prepared inside the sandbox")
	room.reset_room()
	_check(sandbox.pending_cave_entry_room.is_empty() and sandbox.saved_session == snapshot, "test-room reset must clear a queued landmark without changing the saved original")
	sandbox.prepare_cave_entry("workshops")
	room.leave_room()
	if not await _wait_for_scene("res://main_menu.tscn"):
		return
	_check(not sandbox.active and sandbox.pending_cave_entry_room.is_empty(), "leaving landmark tests must clear all pending entry state")
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "landmark tests must restore exact original inventory identity and every expedition field")


func _send_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)


func _send_navigation_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await process_frame


func _wait_for_scene(scene_path: String) -> bool:
	var deadline := Time.get_ticks_msec() + SCENE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		if current_scene != null and current_scene.scene_file_path == scene_path and not _loading_screen_is_present():
			# SceneTree.process_frame resumes before node _process callbacks.
			# Let the sandbox observe overlay dismissal and update its banner.
			await process_frame
			return true
		await process_frame
	_check(false, "scene transition must complete before timeout: " + scene_path)
	return false


func _loading_screen_is_present() -> bool:
	for child in root.get_children():
		if bool(child.get_meta(&"sanctuary_loading_host", false)):
			return true
	return current_scene is SanctuaryLoadingScreen


func _clear_current_scene() -> void:
	paused = false
	if is_instance_valid(current_scene):
		var old_scene := current_scene
		current_scene = null
		old_scene.queue_free()
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
		print("CAVE FLOW TEST PASS: hideout destination, real cave action, seven direct landmark visits, F2, reentry, death recovery, one-shot entry cleanup and complete expedition restoration")
		quit(0)
		return
	for failure in failures:
		push_error("CAVE FLOW TEST FAIL: " + failure)
	quit(1)
