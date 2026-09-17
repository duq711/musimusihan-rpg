extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const SYSTEM := preload("res://scripts/smithing_system.gd")
var failures: Array[String] = []
var sandbox: Node
var room: Node3D
var bag: ExpeditionInventory


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("iron_ingot", 5)
	original.equipment_data["weapon"] = {
		"item_id": "rusted_sword", "uid": "original-sword-preserve",
		"smithing": {"quality": 61.0, "grip": "balanced_grip", "reinforcement": "silver_edge", "sockets": 1, "runes": ["ember_rune"], "drill_progress": 0.0},
	}
	ExpeditionSession.crowns = 719
	ExpeditionSession.hunger = 61.0
	ExpeditionSession.thirst = 43.0
	ExpeditionSession.stress = 32.0
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var original_metadata := original.equipment_data.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	bag = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "smithing trials must start in the paused isolated test room")
	_test_catalog()
	# A full bag must still allow a complete craft, including its result slot.
	while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
		bag.add_item("rusted_sword", 1, false)
	room.run_feature("smithing_forge")
	_check("교체" in room.status_label.text, "full-bag trial replacement must be disclosed")
	_check(bag.slots.size() < ExpeditionInventory.MAX_SLOTS, "forge fixture must reserve a result slot even when the trial bag was full")
	_check_supplies()
	if await _wait_for_scene(HIDEOUT_PATH):
		await _test_forge()
		await _return_to_room()
	for station in ["grip", "blade", "rune"]:
		if await _enter_station(station):
			_test_upgrade(station)
			await _return_to_room()
	# Repeat the capped rune operation: a fresh comparison weapon must be
	# provisioned while the previously upgraded individual sword stays owned.
	if await _enter_station("rune"):
		var smith: CanvasLayer = current_scene.blacksmith_overlay
		var mods: Dictionary = bag.get_equipment_instance("weapon").smithing
		_check(int(mods.sockets) == 0 and (mods.runes as Array).is_empty(), "repeat rune trial must begin with a fresh unmodified comparison sword")
		_test_upgrade("rune")
		_act(smith, "start", "iron_arming_sword")
		var spent_iron := bag.count_item("iron_ingot")
		await _return_to_room()
		_check(bag.count_item("iron_ingot") == spent_iron, "F2 must discard unfinished work without refunding consumed materials")
	_check(sandbox.saved_session == snapshot and original.slots == original_slots and original.equipment_data == original_metadata, "smithing crafts, upgrades and repeated scene visits must not mutate the original expedition")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		var prior_bag := bag
		room.reset_room()
		bag = room.inventory
		_check(bag != prior_bag and bag != original, "reset must create a separate fresh trial inventory")
		_check(not bag.get_equipment_instance("weapon").has("smithing"), "reset must not inherit prior trial weapon upgrades")
		_check(sandbox.pending_blacksmith_trial.is_empty() and sandbox.saved_session == snapshot, "reset must clear one-shot workshop entry while preserving the original snapshot")
		if await _enter_station("grip"):
			_test_upgrade("grip")
			await _return_to_room()
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "leaving smithing trials must restore original inventory identity")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "leaving smithing trials must restore every original expedition value")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_metadata, "original per-weapon rune, grip, quality and blade metadata must survive all trial work exactly")
	_check(sandbox.pending_blacksmith_trial.is_empty(), "completed test session must not leak a requested workshop station")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("BLACKSMITH TEST ROOM PASS: real hideout forge, grip/blade/rune effects, automatic catalogs, full-bag supplies, repeated F2, reset and complete original weapon-instance restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_catalog() -> void:
	for station in ["forge", "grip", "blade", "rune"]:
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "smithing_" + station)
		_check(matches.size() == 1 and matches[0].action == "smithing" and matches[0].payload == station, "each smithing station must have one executable real-scene catalog entry: " + station)
	for item_id in SYSTEM.trial_supplies():
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:" + item_id)
		_check(matches.size() == 1 and matches[0].action == "item", "smithing material must auto-register from the original item catalog: " + item_id)
		var stocked := false
		for chest in room.loot_chests:
			for stack in chest.container.items:
				stocked = stocked or (str(stack.id) == item_id and int(stack.quantity) > 0)
		_check(stocked, "original-catalog trial supply chests must contain smithing material: " + item_id)


func _check_supplies() -> void:
	for item_id in SYSTEM.trial_supplies():
		_check(bag.count_item(item_id) == int(SYSTEM.trial_supplies()[item_id]), "actual trial bag must receive exact catalog material supply: " + item_id)


func _enter_station(station: String) -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "cannot begin station without returning to the real test room: " + station)
		return false
	room = current_scene as Node3D
	room.run_feature("smithing_" + station)
	_check_supplies()
	return await _wait_for_scene(HIDEOUT_PATH)


func _test_forge() -> void:
	var hideout: Node = current_scene
	var smith: CanvasLayer = hideout.blacksmith_overlay
	_check(is_instance_valid(smith) and smith.is_open() and smith.system.inventory == bag, "forge trial must open the production overlay with only the sandbox bag")
	_check(sandbox.pending_blacksmith_trial.is_empty(), "actual hideout must consume the requested station exactly once")
	await _test_workbench_interaction(hideout, smith)
	_check(not hideout.world_root.visible and not hideout.player.visible, "full-screen workshop must suspend hidden shelter and carried-weapon rendering")
	smith.set_process(false)
	var before_iron := bag.count_item("iron_ingot")
	var before_swords := bag.count_item("forged_longsword")
	_act(smith, "start", "iron_longsword")
	_check(bag.count_item("iron_ingot") == before_iron - 3 and smith.system.stage == "fire", "starting real forge must consume the selected recipe and place its iron in the fire")
	var early: Dictionary = smith.perform_action("quench")
	_check(not early.accepted and smith.system.stage == "fire", "workshop UI must reject quenching an unshaped blade")
	for pump in range(6):
		_act(smith, "pump_bellows")
	_act(smith, "move_to_anvil")
	for face in range(2):
		for section in range(3):
			for hit in range(2):
				_act(smith, "hammer", {"section": section, "accuracy": 1.0})
		if face == 0:
			_act(smith, "flip_blade")
	_check(smith.system.hammer_count == 12 and smith.system.shaping_complete(), "both faces and all three blade sections must be physically worked before completion")
	_act(smith, "quench")
	_check(smith.system.stage == "quenched" and is_equal_approx(smith.system.temperature, 20.0), "actual quench must cool and harden the shaped workpiece")
	var finished := _act(smith, "finish")
	_check(bag.count_item("forged_longsword") == before_swords + 1, "production workshop completion must add an equippable real crafted weapon")
	var crafted_index := -1
	for index in range(bag.slots.size()):
		if str((bag.slots[index].get("instance", {}) as Dictionary).get("uid", "")) == str(finished.get("uid", "no-result")):
			crafted_index = index
	_check(crafted_index >= 0, "crafted result must preserve unique per-weapon metadata in the real bag")
	if crafted_index >= 0:
		_check(bag.equip_from_slot(crafted_index).accepted, "crafted result must equip through the normal inventory path")
		_check(str(bag.equipment.weapon) == "forged_longsword" and hideout.player.get_melee_damage() > 31.0, "crafted quality must affect the actual player's melee damage")
	await process_frame


func _test_workbench_interaction(hideout: Node, smith: CanvasLayer) -> void:
	# Headless cannot emulate hardware pointer capture. Keep the real collision
	# query and timed interaction, while advancing only its public timer here.
	smith.close()
	_check(not paused and not smith.is_open(), "closing the workshop must resume the actual hideout")
	var actor: DungeonPlayer = hideout.player
	actor.set_physics_process(false)
	var workbench := hideout.find_child("WorkbenchInteraction", true, false) as HideoutInteractable
	_check(is_instance_valid(workbench) and workbench.action_id == "workbench", "the visible blacksmith corner must expose the production workbench interaction")
	if workbench == null:
		return
	await physics_frame
	await physics_frame
	var start := actor.camera.global_position
	var target := workbench.global_position + workbench.interaction_offset
	var query := PhysicsRayQueryParameters3D.create(start, target, DungeonPlayer.WORLD_LAYER | DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider.get_meta("interaction_owner", null) == workbench, "normal player approach must reach the workbench interaction before a blocking wall or prop")
	workbench.interact(actor)
	_check(actor.timed_interaction_owner == workbench and not smith.is_open(), "normal workbench use must begin the actual 0.3-second interaction before opening")
	actor.advance_timed_interaction(0.35)
	_check(smith.is_open() and paused and hideout.blacksmith_overlay == smith, "normal timed workbench completion must open the production overlay and pause hideout play")


func _test_upgrade(station: String) -> void:
	var hideout: Node = current_scene
	var smith: CanvasLayer = hideout.blacksmith_overlay
	_check(is_instance_valid(smith) and smith.is_open() and smith.system.inventory == bag, "upgrade trial must use the real production workshop: " + station)
	smith.set_process(false)
	var base_damage: float = hideout.player.get_melee_damage()
	var base_stamina: float = hideout.player.get_melee_stamina_cost()
	match station:
		"grip":
			var leather := bag.count_item("grip_leather")
			_act(smith, "replace_grip", "leather_grip")
			_check(bag.count_item("grip_leather") == leather - 2 and hideout.player.get_melee_stamina_cost() < base_stamina, "grip UI must consume real leather and reduce actual attack stamina")
		"blade":
			var iron := bag.count_item("iron_ingot")
			_act(smith, "reinforce_blade", "steel_edge")
			_check(bag.count_item("iron_ingot") == iron - 1 and is_equal_approx(hideout.player.get_melee_damage(), base_damage + 5.0), "blade UI must consume real metal and increase actual melee damage")
		"rune":
			var runes := bag.count_item("rune_fragment")
			var fittings := bag.count_item("steel_fitting")
			var rejected: Dictionary = smith.perform_action("insert_rune", "rune_fragment")
			_check(not rejected.accepted and bag.count_item("rune_fragment") == runes, "rune UI must reject insertion before drilling without consuming a fragment")
			for turn in range(3):
				_act(smith, "drill_socket", 1.0)
			_check(int(bag.get_equipment_instance("weapon").smithing.sockets) == 1 and bag.count_item("steel_fitting") == fittings - 1, "three real drill operations must create one socket with one tool material")
			_act(smith, "insert_rune", "rune_fragment")
			_check(bag.count_item("rune_fragment") == runes - 1 and is_equal_approx(hideout.player.get_melee_damage(), base_damage + 3.0), "installed rune must consume a fragment and alter actual weapon damage")
			hideout.player.health = 60.0
			hideout.player.apply_smithing_on_hit()
			_check(is_equal_approx(hideout.player.health, 62.0), "installed rune must connect to the actual player on-hit recovery")


func _act(smith: CanvasLayer, action: String, payload: Variant = null) -> Dictionary:
	var result: Dictionary = smith.perform_action(action, payload)
	_check(bool(result.get("accepted", false)), "real workshop action must succeed: " + action + " / " + str(result.get("reason", "missing_result")))
	return result


func _return_to_room() -> bool:
	var previous_overlay: CanvasLayer = current_scene.blacksmith_overlay
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 from the actual workshop must return to the paused test menu with the same trial bag")
		_check(not is_instance_valid(previous_overlay), "F2 must destroy the old workshop and its unfinished local state")
		_check(sandbox.pending_blacksmith_trial.is_empty(), "F2 must clear the one-shot station request")
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
	_check(false, "blacksmith trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
