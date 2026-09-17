extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_failure_gates_and_equipment()
	await _test_melee_and_returning_throw()
	await _test_short_click_and_cancellation()
	await _test_dungeon_pause()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("FLAIL SYSTEM TEST PASS: starter equipment, gates, timed melee, rotating charge, queued short release, physical hit and return, one-time costs, cancellation, pause and ordinary weapons")
		quit(0)
	else:
		for failure in failures:
			push_error("FLAIL SYSTEM TEST FAIL: " + failure)
		quit(1)


func _fixture() -> Dictionary:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var world := Node3D.new()
	root.add_child(world)
	var hud := DungeonHUD.new()
	world.add_child(hud)
	var player := DungeonPlayer.new()
	player.setup(world, hud, inventory)
	world.add_child(player)
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return {"world": world, "player": player, "inventory": inventory, "hud": hud}


func _equip(inventory: ExpeditionInventory, item_id: String) -> bool:
	for index in range(inventory.slots.size()):
		if inventory.slots[index].id == item_id:
			return bool(inventory.equip_from_slot(index).get("accepted", false))
	return false


func _enemy(fixture: Dictionary, at: Vector3) -> DungeonEnemy:
	var enemy := DungeonEnemy.new()
	enemy.configure("굶주린 철퇴 표적", 200.0, 18.0, 2.0, Color(0.2, 0.15, 0.1))
	enemy.setup(fixture.player, fixture.hud, fixture.world)
	enemy.position = at
	fixture.world.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _projectiles(world: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child in world.get_children():
		if child is FlailProjectile and not child.is_queued_for_deletion():
			result.append(child)
	return result


func _test_failure_gates_and_equipment() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_check(inventory.count_item("chain_flail") == 1, "starter bag must contain one flail")
	_check(not bool(player.begin_flail_melee().accepted) and not bool(player.begin_flail_spin().accepted), "ordinary sword equipment must not start flail actions")
	_check(_equip(inventory, "chain_flail"), "flail must equip using the actual inventory action")
	_check(player._is_flail_equipped() and player.flail_visual_root.visible and not player.sword_visual_root.visible and not player.bow_visual_root.visible and not player.staff_visual_root.visible, "equipping a flail must switch the real first-person weapon")
	_check(not player.shield_pivot.visible, "flail RMB rotation must not display a guarding shield")
	player.stamina = 17.0
	_check(not bool(player.begin_flail_melee().accepted), "melee must reject insufficient stamina")
	player.stamina = 23.0
	_check(not bool(player.begin_flail_spin().accepted), "rotation must reject insufficient upfront stamina")
	player.stamina = 100.0
	player.configure_safe_zone(true)
	_check(not bool(player.begin_flail_melee().accepted) and not bool(player.begin_flail_spin().accepted), "safe zones must block both flail attacks")
	player.configure_safe_zone(false)
	paused = true
	_check(not bool(player.begin_flail_spin().accepted), "paused gameplay must not start rotating")
	paused = false
	player.combat_state = DungeonPlayer.CombatState.GUARD_BREAK
	_check(not bool(player.begin_flail_melee().accepted), "a staggered player must not attack with a flail")
	player.combat_state = DungeonPlayer.CombatState.READY
	_check(_equip(inventory, "rusted_sword") and player.sword_visual_root.visible and not player.flail_visual_root.visible, "switching back must restore the ordinary sword visual")
	_check(_equip(inventory, "hunting_bow") and player.bow_visual_root.visible, "switching to the bow must preserve the existing bow")
	_check(bool(player.begin_bow_draw().accepted), "ordinary archery must still begin after flail equipment changes")
	player.cancel_bow_draw()
	fixture.world.free()


func _test_melee_and_returning_throw() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_equip(inventory, "chain_flail")
	var near_target := _enemy(fixture, Vector3(0, 0, -2))
	await physics_frame
	await physics_frame
	var initial_slots := inventory.slots.duplicate(true)
	var initial_flail_count := inventory.count_item("chain_flail")
	_check(bool(player.begin_flail_melee().accepted) and player.flail_state == "melee" and is_equal_approx(player.stamina, 82.0), "left attack must enter a timed melee action and spend exactly 18 stamina")
	_check(not bool(player.begin_flail_spin().accepted), "rotation must not overlap an active melee strike")
	player._update_flail(0.19)
	_check(is_equal_approx(near_target.health, 200.0), "melee must not hit before its 0.20-second strike point")
	player._update_flail(0.02)
	_check(is_equal_approx(near_target.health, 168.0), "actual melee collision must apply 32 damage once")
	player._update_flail(0.6)
	_check(player.flail_state == "ready" and is_equal_approx(near_target.health, 168.0), "a completed melee animation must rearm without repeat hits")
	near_target.free()
	var target := _enemy(fixture, Vector3(0, 0, -8))
	await physics_frame
	await physics_frame
	player.stamina = 100.0
	_check(bool(player.begin_flail_spin().accepted), "RMB action must begin right-side rotation")
	var phase := player.flail_spin_phase
	player._update_flail(0.6)
	_check(is_equal_approx(player.get_flail_charge(), 0.5) and player.flail_spin_phase != phase, "half charge must advance the actual rotating head's phase")
	player._update_flail(1.8)
	_check(is_equal_approx(player.get_flail_charge(), 1.0) and is_equal_approx(player.stamina, 76.0) and not player.blocking, "held rotation must clamp charge and spend no additional stamina or enter shield guard")
	var shot := player.release_flail_throw()
	_check(bool(shot.get("accepted", false)) and _projectiles(fixture.world).size() == 1, "release must throw exactly one physical head")
	_check(not bool(player.begin_flail_melee().accepted) and not bool(player.begin_flail_spin().accepted), "new attacks must be gated while the head is away")
	_check(not bool(player.release_flail_throw().accepted) and _projectiles(fixture.world).size() == 1, "duplicate release must not throw a second head")
	for frame in range(180):
		await physics_frame
		player._update_flail(1.0 / 60.0)
		if player.flail_state == "ready":
			break
	_check(is_equal_approx(target.health, 140.0), "full throw must collide with a real enemy for 60 damage exactly once, including its return")
	_check(player.flail_state == "ready" and _projectiles(fixture.world).is_empty() and is_equal_approx(player.stamina, 76.0), "returned flail must recover and rearm without extra stamina")
	_check(inventory.slots == initial_slots and inventory.count_item("chain_flail") == initial_flail_count and inventory.equipment.weapon == "chain_flail", "flail melee, throw and return must preserve all inventory quantities and the equipped weapon")
	fixture.world.free()


func _test_short_click_and_cancellation() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	_equip(fixture.inventory, "chain_flail")
	player.begin_flail_spin()
	var queued := player.release_flail_throw()
	_check(bool(queued.get("accepted", false)) and bool(queued.get("queued", false)) and _projectiles(fixture.world).is_empty(), "a short RMB click must queue release until the minimum visible spin finishes")
	player._update_flail(0.34)
	_check(player.flail_state == "spinning" and _projectiles(fixture.world).is_empty(), "queued release must not fire before 0.35 seconds")
	player._update_flail(0.02)
	_check(_projectiles(fixture.world).size() == 1 and is_equal_approx(player.stamina, 76.0), "the queued short click must throw once without another stamina charge")
	player.cancel_flail_action()
	await process_frame
	_check(player.flail_state == "ready" and _projectiles(fixture.world).is_empty() and is_equal_approx(player.stamina, 76.0), "cancel must restore an outbound head without refunding spent stamina")
	player.stamina = 100.0
	player.begin_flail_spin()
	player._update_flail(0.2)
	var elapsed_spin := player.flail_spin_time
	paused = true
	player._update_flail(1.0)
	_check(is_equal_approx(player.flail_spin_time, elapsed_spin) and _projectiles(fixture.world).is_empty(), "paused action updates must not advance or release a spin")
	paused = false
	player.prepare_for_inventory()
	_check(player.flail_state == "ready" and is_equal_approx(player.stamina, 76.0), "opening inventory must cancel a spin and retain its upfront cost")
	player.begin_flail_spin()
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(player.flail_state == "ready", "losing window focus must cancel a held spin")
	player.stamina = 100.0
	player.begin_flail_spin()
	player.receive_environment_damage(1.0, "test")
	_check(player.flail_state == "ready", "taking damage must interrupt the flail action")
	player.stamina = 100.0
	player.begin_flail_spin()
	_equip(fixture.inventory, "hunting_bow")
	_check(player.flail_state == "ready" and not player.flail_visual_root.visible and _projectiles(fixture.world).is_empty(), "equipment changes must cancel flail state and restore the selected weapon")
	fixture.world.free()


func _test_dungeon_pause() -> void:
	ExpeditionSession.begin_new_journey()
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	await process_frame
	var player := game.player as DungeonPlayer
	player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	_equip(game.inventory, "chain_flail")
	player.begin_flail_spin()
	player._update_flail(0.5)
	game._pause_game()
	_check(paused and player.flail_state == "ready" and is_equal_approx(player.stamina, 76.0), "ordinary dungeon pause must cancel the spin without refunding its cost")
	game._resume_game()
	player.stamina = 100.0
	player.begin_flail_spin()
	player._update_flail(1.2)
	player.release_flail_throw()
	_check(_projectiles(game).size() == 1, "ordinary dungeon pause regression must start with an actual outbound flail")
	game._pause_game()
	await process_frame
	_check(paused and player.flail_state == "ready" and _projectiles(game).is_empty(), "ordinary dungeon pause must also recall and clean an outbound head")
	game._resume_game()
	current_scene = null
	game.queue_free()
	await process_frame
	paused = false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
