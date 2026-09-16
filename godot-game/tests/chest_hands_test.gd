extends SceneTree

var failures: Array[String] = []
var game: Node3D
var player: DungeonPlayer
var chest: DungeonLootChest
var chest_position := Vector3.ZERO


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_process_unhandled_input(false)
	player = game.player as DungeonPlayer
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	# This suite verifies the preserved reliquary's authored wood contacts.
	# Production occupancy and supplied variants have their own loot tests.
	chest_position = Vector3(-7.1, 0.0, 5.0)
	_new_chest()
	await process_frame
	await physics_frame
	_check(is_instance_valid(player.get("chest_hands")), "real dungeon player must own the actual chest-hand visual model")
	if is_instance_valid(player.get("chest_hands")):
		await _test_phases_and_completion()
		_test_rotated_approaches_and_continuous_contacts()
		_test_reach_rules()
		_test_loadouts_and_full_bag()
		await _test_cancellation_boundaries()
		_test_duration_scaling_and_pause()
		_test_container_equipment_change()
		_test_generic_interaction_remains_generic()
		_test_victory_cleanup()
		await _test_scene_cleanup()
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	paused = false
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original, "all chest-hand tests must restore the exact original expedition snapshot")
	_finish()


func _test_phases_and_completion() -> void:
	_position_player()
	var slots_before := player.inventory_model.slots.duplicate(true)
	var equipment_before := player.inventory_model.equipment.duplicate(true)
	var torch_before := player.torch_enabled
	chest.interact(player)
	_check(player.is_timed_interacting() and chest.state == DungeonLootChest.ChestState.OPENING and not chest.opened, "actual chest interaction must begin the ordinary timed opening")
	_check(is_equal_approx(player.timed_interaction_duration, 1.2), "Opening must retain its existing 1.2-second clock.")
	var hand_poses := [player.chest_hands.left_hand.transform, player.chest_hands.right_hand.transform]
	for frame in range(1, 72):
		player.advance_timed_interaction(1.0 / 60.0)
		_check(not player.chest_hands.active and not player.chest_hands.is_visible_in_tree(), "No chest hand rig may activate at any opening frame.")
		_check(not player.chest_hands.left_hand.is_visible_in_tree() and not player.chest_hands.right_hand.is_visible_in_tree(), "Both chest hands must stay hidden.")
		_check(player.chest_hands.left_hand.transform == hand_poses[0] and player.chest_hands.right_hand.transform == hand_poses[1], "Opening must not animate hidden hands either.")
	_check(chest.lid_pivot.rotation.x > 0.1 and not chest.opened, "The real lid must still lift before timed completion.")
	_check(not game.inventory_overlay.is_open() and not paused, "Partial opening must not prematurely reveal inventory.")
	_check(player.inventory_model.slots == slots_before and player.inventory_model.equipment == equipment_before and player.torch_enabled == torch_before, "Opening must preserve inventory, equipment and torch state.")
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION)
	_check(chest.opened and chest.container.ever_opened and chest.state == DungeonLootChest.ChestState.OPENED, "the ordinary completed interaction must persist the chest opened state")
	_check(not player.is_timed_interacting() and not player.chest_hands.active, "completion must clear transient interaction and hand poses")
	_check(game.inventory_overlay.is_open() and game.game_mode == game.GameMode.INVENTORY and paused and game.active_loot_chest == chest, "completion must open the real paused loot interface")
	_check_stowed("paused chest inventory")
	await process_frame
	_check_stowed("paused chest inventory after frame")
	game.inventory_overlay.close()
	_check(not paused and game.game_mode == game.GameMode.RUNNING, "closing actual chest inventory must restore normal exploration")
	_check_restored("closing chest inventory")
	var units_before := chest.container.item_count()
	chest.interact(player)
	_check(game.inventory_overlay.is_open() and paused and not player.is_timed_interacting() and not player.chest_hands.active, "an already-opened chest must still reopen immediately without replaying the lock animation")
	_check_stowed("reopening an already-opened chest")
	_check(chest.container.item_count() == units_before, "reopening must not regenerate chest resources")
	game._close_inventory()
	_check_restored("closing a reopened chest")


func _test_reach_rules() -> void:
	_new_chest()
	for yaw: float in [0.0, PI * 0.5, PI]:
		chest.rotation.y = yaw
		for offset: Vector3 in [Vector3(0.0, 0.9, -1.6), Vector3(0.0, 0.9, 1.6), Vector3(-1.8, 0.9, 0.0), Vector3(1.8, 0.9, 0.0)]:
			player.global_position = chest.to_global(offset)
			_check(chest.is_within_hand_reach(player), "ordinary front/back/side opening distance must remain reachable after chest rotation")
		player.global_position = chest.to_global(Vector3(0.0, 0.9, -2.6))
		_check(not chest.is_within_hand_reach(player), "a distant closed chest must require approach rather than multi-metre arms")
		player.global_position = chest.to_global(Vector3(0.0, 2.5, -1.6))
		_check(not chest.is_within_hand_reach(player), "opening must not reach through a large vertical gap")
	chest.opened = true
	_check(chest.is_within_hand_reach(player), "already-open chests retain the previous focus-ray inspection range")
	chest.opened = false


func _test_loadouts_and_full_bag() -> void:
	while player.inventory_model.slots.size() < ExpeditionInventory.MAX_SLOTS:
		player.inventory_model.add_item("reliquary")
	var full_slots := player.inventory_model.slots.duplicate(true)
	for weapon_id: String in ["rusted_sword", "hunting_bow", "chain_flail", "weathered_staff", ""]:
		_new_chest()
		_equip(weapon_id)
		player.set_torch_enabled(weapon_id != "hunting_bow")
		var gear := player.inventory_model.equipment.duplicate(true)
		var torch_before := player.torch_enabled
		chest.interact(player)
		player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.5)
		_check_stowed("loadout " + weapon_id)
		_check(not player.chest_hands.active and not player.chest_hands.left_hand.is_visible_in_tree(), "all loadouts, including empty hands, must open chests without hand animation")
		_check(player.inventory_model.slots == full_slots and player.inventory_model.equipment == gear and player.torch_enabled == torch_before, "full-bag stowing must not attempt an inventory transaction: " + weapon_id)
		player.cancel_timed_interaction()
		_check_cancelled("loadout cancellation " + weapon_id)
		_check_restored("loadout cancellation " + weapon_id)
		_check(player.inventory_model.slots == full_slots and player.inventory_model.equipment == gear and player.torch_enabled == torch_before, "restoration must preserve exact loadout and torch setting: " + weapon_id)
	_equip("rusted_sword")
	player.set_torch_enabled(true)


func _test_rotated_approaches_and_continuous_contacts() -> void:
	for yaw: float in [0.0, 37.0, -121.0, 180.0]:
		for offset: Vector3 in [Vector3(0, 1, -1.6), Vector3(0, 1, 1.6), Vector3(-1.6, 1, 0), Vector3(1.6, 1, 0)]:
			_new_chest()
			chest.rotation.y = deg_to_rad(yaw)
			player.global_position = chest.to_global(offset)
			chest.interact(player)
			_check(player.is_timed_interacting(), "Rotated chests must still open from each approach.")
			player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.85)
			_check(chest.lid_pivot.rotation.x > 0.1 and not player.chest_hands.active and not player.chest_hands.visible, "Lid animation must work from every approach without hand contact motion.")
			player.cancel_timed_interaction()


func _test_cancellation_boundaries() -> void:
	for reason: String in ["explicit", "damage", "inventory", "pause", "focus", "safe_zone", "camp", "death"]:
		_new_chest()
		chest.interact(player)
		player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.86)
		_check(chest.lid_pivot.rotation.x > 0.1, "cancellation fixture must start after the actual lid has begun moving: " + reason)
		match reason:
			"explicit": player.cancel_timed_interaction("시험 취소")
			"damage": player.receive_environment_damage(1.0, "상자 개봉 피격 시험")
			"inventory": game._open_inventory()
			"pause": game._pause_game()
			"focus": player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"safe_zone": player.configure_safe_zone(true)
			"camp": player.set_camping(true)
			"death": player.receive_environment_damage(1000.0, "상자 개봉 사망 시험")
		_check_cancelled(reason)
		if reason == "death":
			await create_timer(0.27, true).timeout
			_check(game.game_mode == game.GameMode.DEAD and paused, "the actual delayed death result must retain cleared chest hands and pause normally")
		if reason == "safe_zone":
			_check(not player.weapon_pivot.visible and not player.shield_pivot.visible, "safe-zone cancellation must preserve that zone's weapon and shield hiding policy")
			player.configure_safe_zone(false)
		elif reason == "camp":
			_check(not player.weapon_pivot.visible and not player.shield_pivot.visible and not player.torch_pivot.visible, "camp cancellation must not restore equipment through camping's hidden state")
			player.set_camping(false)
		if game.game_mode == game.GameMode.INVENTORY:
			game._close_inventory()
		elif game.game_mode != game.GameMode.RUNNING:
			game._resume_game()
		player.health = player.MAX_HEALTH
		player.combat_state = DungeonPlayer.CombatState.READY
		player.configure_safe_zone(false)
		player.set_camping(false)
		player._sync_equipped_weapon()
		_check_restored("after " + reason)
	_new_chest()
	chest.interact(player)
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.5)
	game.loot_chests.erase(chest)
	chest.free()
	chest = null
	player.advance_timed_interaction(0.1)
	_check(not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "a freed owner must immediately release hands and equipment without calling a dangling chest")
	_check_restored("invalid owner")
	await process_frame


func _test_duration_scaling_and_pause() -> void:
	_new_chest()
	player.interaction_duration_scale = 2.0
	chest.interact(player)
	_check(is_equal_approx(player.timed_interaction_duration, 2.4), "duration scaling must remain authoritative for hand animation")
	player.advance_timed_interaction(1.2)
	_check(is_equal_approx(player.get_timed_interaction_progress(), 0.5) and not player.chest_hands.active, "scaled opening must use normalized progress, not an independent hand timer")
	var elapsed_before := player.timed_interaction_elapsed
	var left_before: Transform3D = player.chest_hands.left_hand.transform
	var lid_before := chest.lid_pivot.rotation.x
	paused = true
	player.advance_timed_interaction(100.0)
	player._physics_process(100.0)
	_check(player.timed_interaction_elapsed == elapsed_before and player.chest_hands.left_hand.transform == left_before and chest.lid_pivot.rotation.x == lid_before and not chest.opened, "paused opening must not advance the shared clock, hand animation or lid")
	paused = false
	player.cancel_timed_interaction()
	_check_cancelled("scaled opening cancellation")
	for scale: float in [0.0, -1.0]:
		_new_chest()
		player.interaction_duration_scale = scale
		chest.interact(player)
		_check(chest.opened and paused and game.inventory_overlay.is_open() and not player.is_timed_interacting() and not player.chest_hands.active, "zero or clamped-negative duration must open once with no lingering hand state")
		_check_stowed("instant opened container")
		game._close_inventory()
		_check_restored("instant container close")
	player.interaction_duration_scale = 1.0


func _test_container_equipment_change() -> void:
	_new_chest()
	_equip("rusted_sword")
	chest.interact(player)
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION)
	_check_stowed("before changing paused loadout")
	_equip("hunting_bow")
	_check_stowed("after changing paused loadout")
	game._close_inventory()
	_check_restored("closing with a newly equipped bow")
	_check(player.bow_visual_root.visible and not player.sword_visual_root.visible and not player.shield_pivot.visible, "container close must restore current bow visuals, not the sword cached when opening began")
	chest.interact(player)
	_equip("")
	_check_stowed("unequipping while chest inventory is open")
	game.inventory_overlay.close()
	_check_restored("closing with an empty weapon slot")
	_check(str(player.inventory_model.equipment.weapon).is_empty(), "closing an empty-handed container must never equip a fallback weapon")
	_equip("rusted_sword")


func _test_generic_interaction_remains_generic() -> void:
	var owner := Node.new()
	game.add_child(owner)
	_check(player.begin_timed_interaction(owner, 2.0, "일반 상호작용"), "generic timed interactions must remain accepted")
	_check(not player.chest_hands.active and not player.chest_equipment_stowed, "non-chest timed actions must not incorrectly stow gear or spawn chest hands")
	player.cancel_timed_interaction()
	owner.queue_free()


func _test_victory_cleanup() -> void:
	_new_chest()
	chest.interact(player)
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.86)
	var enemies_before: int = game.enemies_alive
	var equipment_before := player.inventory_model.equipment.duplicate(true)
	var slots_before := player.inventory_model.slots.duplicate(true)
	game.enemies_alive = 1
	game._on_extraction_body_entered(player)
	_check(game.game_mode == game.GameMode.RUNNING and player.is_timed_interacting() and not player.chest_hands.active, "a sealed extraction must leave an in-progress chest interaction intact")
	game.enemies_alive = 0
	game._on_extraction_body_entered(player)
	_check(game.game_mode == game.GameMode.WON and paused, "actual unsealed extraction callback must reach the paused victory result")
	_check_cancelled("victory callback")
	_check_restored("victory callback")
	player.advance_timed_interaction(100.0)
	_check(not chest.opened and not player.chest_hands.active and not player.chest_equipment_stowed, "victory must not leave a delayed chest completion or temporary equipment hold")
	_check(player.inventory_model.equipment == equipment_before and player.inventory_model.slots == slots_before, "victory cleanup must preserve equipment and actual inventory resources")
	game.enemies_alive = enemies_before
	game._resume_game()


func _test_scene_cleanup() -> void:
	_new_chest()
	chest.interact(player)
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.85)
	var surviving_chest := chest
	game.loot_chests.erase(surviving_chest)
	surviving_chest.reparent(root, true)
	game.queue_free()
	await process_frame
	_check(is_instance_valid(surviving_chest) and surviving_chest.state == DungeonLootChest.ChestState.CLOSED and not surviving_chest.opened and is_zero_approx(surviving_chest.lid_pivot.rotation.x), "player scene exit must cancel and reset an unfinished owner that survives the player")
	surviving_chest.queue_free()
	await process_frame


func _new_chest() -> void:
	if game.game_mode == game.GameMode.INVENTORY:
		game._close_inventory()
	if game.game_mode != game.GameMode.RUNNING:
		game._resume_game()
	player.cancel_timed_interaction()
	if is_instance_valid(chest):
		game.loot_chests.erase(chest)
		chest.queue_free()
	chest = DungeonLootChest.new().configure("맨손 개봉 검증", [{"id": "linen_bandage", "quantity": 2}])
	chest.position = chest_position
	chest.open_requested.connect(game._open_container)
	game.add_child(chest)
	game.loot_chests.append(chest)
	_position_player()


func _position_player() -> void:
	player.position = chest_position + Vector3(0.0, 1.0, 2.4)
	player.rotation = Vector3.ZERO
	player.head.rotation.x = deg_to_rad(-20.0)
	player._pitch = player.head.rotation.x
	player.velocity = Vector3.ZERO
	player.health = player.MAX_HEALTH
	player.combat_state = DungeonPlayer.CombatState.READY
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _equip(id: String) -> void:
	player.inventory_model.equipment["weapon"] = id
	player.inventory_model.changed.emit()


func _check_stowed(context: String) -> void:
	_check(player.chest_equipment_stowed and not player.weapon_pivot.visible and not player.shield_pivot.visible and not player.torch_pivot.visible, context + " must hide weapon, shield and torch without unequipping")


func _check_cancelled(context: String) -> void:
	_check(not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_hands.visible, context + " must clear timed ownership and all transient hands")
	_check(chest.state == DungeonLootChest.ChestState.CLOSED and not chest.opened and not chest.container.ever_opened and is_zero_approx(chest.lid_pivot.rotation.x), context + " must return an unfinished chest and actual lid to closed state")


func _check_restored(context: String) -> void:
	var weapon := str(player.inventory_model.equipment.get("weapon", ""))
	_check(not player.chest_equipment_stowed and not player.chest_hands.active, context + " must release the temporary chest presentation hold")
	_check((player.weapon_pivot.visible or weapon.is_empty()) and player.torch_pivot.visible == player.torch_enabled and player.shield_pivot.visible == (weapon not in ["hunting_bow", "chain_flail"]), context + " must restore allowed current equipment visibility")
	_check(player.sword_visual_root.visible == (weapon == "rusted_sword") and player.bow_visual_root.visible == (weapon == "hunting_bow") and player.flail_visual_root.visible == (weapon == "chain_flail") and player.staff_visual_root.visible == (weapon == "weathered_staff"), context + " must preserve the exact current weapon type including an empty slot")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("CHEST HANDS PASS: no hand animation, unchanged timed opening and moving lid, container hold/restore, all loadouts/full bag, cancellation, pause/scaled timing and scene cleanup")
		quit(0)
		return
	for failure in failures:
		push_error("CHEST HANDS FAIL: " + failure)
	quit(1)
