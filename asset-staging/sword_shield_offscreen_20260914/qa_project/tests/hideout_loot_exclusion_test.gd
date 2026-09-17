extends SceneTree

const LOOT := preload("res://scripts/loot_spawn_catalog.gd")
const CATALOG := preload("res://scripts/test_room_catalog.gd")
const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"

var failures: Array[String] = []
var sandbox: Node
var room: Node3D
var trial_bag: ExpeditionInventory
var stash_transform: Transform3D
var stash_path := NodePath()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog()
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
	_check(sandbox.active and trial_bag != original and room.panel_open and paused, "the existing hideout trial must begin in the isolated paused test room")
	for visit in 2:
		if not await _enter_hideout():
			break
		var hideout := current_scene as SanctuaryHideout
		_test_live_hideout(hideout, visit)
		_test_stash_interaction(hideout)
		_check(original.slots == original_slots and notifications.is_empty(), "living-area checks must not change or notify the original inventory")
		if not await _return_to_room():
			break
		var menu_snapshot := ExpeditionSession.capture_snapshot()
		var menu_position: Vector3 = room.player.global_position
		for frame in 3:
			await process_frame
		_check(paused and ExpeditionSession.capture_snapshot() == menu_snapshot and room.player.global_position == menu_position, "F2 must stop survival and movement before the next hideout visit")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		# Exercise a trial-only mutation so exact restoration cannot pass merely
		# because this exclusion check otherwise leaves the inventory untouched.
		trial_bag.add_item("linen_bandage", 2)
		ExpeditionSession.crowns = 124
		var previous_bag := trial_bag
		room.reset_room()
		trial_bag = room.inventory
		_check(trial_bag != previous_bag and trial_bag != original and sandbox.saved_session == snapshot, "reset must replace only the trial bag and retain the original expedition snapshot")
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "ending the living-area trial must restore the exact original bag, equipment, money and survival state")
	_check(original.slots == original_slots and original.changed.is_connected(observer) and notifications.is_empty(), "original items and inventory listeners must survive repeat entry, F2, reset and exit")
	original.changed.disconnect(observer)
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("HIDEOUT LOOT EXCLUSION TEST PASS: no hideout catalog sites or rolls, two live visits without dungeon loot, fixed personal stash and actual interaction retained, F2/reset and exact original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT LOOT EXCLUSION TEST FAIL: " + failure)
		quit(1)


func _test_catalog() -> void:
	_check(not LOOT.map_ids().has("hideout"), "the safe hideout must not be a random-loot dungeon")
	_check(LOOT.candidates("hideout").is_empty() and LOOT.occupancy_limits("hideout") == Vector2i.ZERO, "the hideout must have no loot sites or minimum spawn count")
	_check(LOOT.roll("hideout").is_empty(), "random entry into the hideout must never produce a loot selection")
	for seed_value in range(64):
		_check(LOOT.roll("hideout", seed_value).is_empty(), "an explicit reproducible seed must never enable hideout loot")
	for dungeon_id in ["reliquary", "blackwater_cave"]:
		_check(LOOT.map_ids().has(dungeon_id) and not LOOT.candidates(dungeon_id).is_empty() and not LOOT.roll(dungeon_id, 17).is_empty(), "the existing real dungeon remains eligible: " + dungeon_id)
	var hideout_entries: Array = CATALOG.entries().filter(func(entry: Dictionary) -> bool: return str(entry.id) == "hideout")
	_check(hideout_entries.size() == 1 and str(hideout_entries[0].category) == "장면" and str(hideout_entries[0].action) == "scene" and str(hideout_entries[0].payload) == HIDEOUT_PATH, "the existing hideout test must enter the actual living area")
	_check(hideout_entries.size() == 1 and str(hideout_entries[0].detail).contains("무작위 루팅 없음") and str(hideout_entries[0].detail).contains("개인 보관함 유지"), "the executable trial must explain the loot exclusion and preserved personal stash")
	for entry: Dictionary in CATALOG.entries():
		_check(not (str(entry.id).begins_with("loot_spawn:") and str(entry.payload) == HIDEOUT_PATH), "a random-loot trial must never route into the hideout")


func _test_live_hideout(hideout: SanctuaryHideout, visit: int) -> void:
	_check(hideout != null and hideout.scene_file_path == HIDEOUT_PATH and hideout.inventory == trial_bag and hideout.player.safe_zone_mode, "the test must inspect the production safe zone with its trial bag")
	if hideout == null:
		return
	var dungeon_chests := 0
	var loot_sites := 0
	var personal_stashes: Array[Node] = []
	for node: Node in hideout.find_children("*", "", true, false):
		if node is DungeonLootChest:
			dungeon_chests += 1
		if node.has_meta("loot_site_id"):
			loot_sites += 1
		if node.name == "PersistentStashVisual":
			personal_stashes.append(node)
	_check(dungeon_chests == 0 and loot_sites == 0, "actual hideout descendants must contain no dungeon loot boxes or random spawn sites on visit %d" % visit)
	_check(personal_stashes.size() == 1, "the hideout must keep exactly one fixed personal-stash visual on every visit")
	if personal_stashes.size() == 1:
		var stash := personal_stashes[0] as Node3D
		_check(stash != null and stash.find_children("*", "MeshInstance3D", true, false).size() > 0, "the personal stash must keep its real 3D model")
		if stash != null:
			if visit == 0:
				stash_transform = stash.global_transform
				stash_path = hideout.get_path_to(stash)
			else:
				_check(stash.global_transform.is_equal_approx(stash_transform) and hideout.get_path_to(stash) == stash_path, "the personal stash must retain the same fixed placement after re-entry")
	var stash_collisions := hideout.find_children("StashCollision_*", "StaticBody3D", true, false)
	_check(stash_collisions.size() == 1 and stash_collisions[0].find_children("*", "CollisionShape3D", true, false).size() == 1, "the existing personal-stash collision must remain")


func _test_stash_interaction(hideout: SanctuaryHideout) -> void:
	if hideout == null:
		return
	var stash := hideout.find_child("StashInteraction", true, false) as HideoutInteractable
	_check(stash != null and stash.action_id == "stash", "the existing E personal-stash action must remain usable")
	if stash == null:
		return
	var trial_slots := trial_bag.slots.duplicate(true)
	stash.interact(hideout.player)
	_check(hideout.player.timed_interaction_owner == stash, "the fixed personal stash must use its actual timed E action")
	hideout.player.advance_timed_interaction(stash.get_interaction_duration() + 0.1)
	_check(hideout.hideout_mode == SanctuaryHideout.HideoutMode.INVENTORY and hideout.inventory_overlay.is_open() and paused, "the existing stash action must still open the real inventory interface")
	_check(trial_bag.slots == trial_slots and hideout.inventory == trial_bag, "using the personal stash must not generate dungeon rewards or replace the trial inventory")
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	hideout._unhandled_input(event)
	_check(not hideout.inventory_overlay.is_open() and hideout.hideout_mode == SanctuaryHideout.HideoutMode.RUNNING and not paused, "closing the personal stash must resume the actual living area")


func _enter_hideout() -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "a repeated hideout trial must begin from the actual test room")
		return false
	room = current_scene as Node3D
	room.run_feature("hideout")
	if not await _wait_for_scene(HIDEOUT_PATH):
		return false
	# Headless tests advance the real interaction timer directly, without
	# pointer capture or unrelated player movement between assertions.
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
		_check(not is_instance_valid(departing) and room.panel_open and paused and room.inventory == trial_bag, "F2 must release the hideout and restore the paused test menu with the same trial bag")
	return returned


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
	_check(false, "actual hideout trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
