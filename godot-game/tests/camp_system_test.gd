extends SceneTree

const CAMP_TEST := preload("res://tests/camp_test_helpers.gd")

const CAMP := preload("res://scripts/camp_controller.gd")

var failures: Array[String] = []


class CampFixtureGame:
	extends Node3D
	var camp: DungeonCamp
	var scene_failure := ""
	func _camp_open_failure() -> String:
		return scene_failure
	func cancel_camp(reason := "", restore_controls := true) -> void:
		camp.cancel_camp(reason, restore_controls)


class RejectingSupplies:
	extends ExpeditionInventory
	var blocked_id := "boiled_rainwater"
	func remove_item(item_id: String, quantity := 1, notify := true) -> bool:
		if item_id == blocked_id:
			return false
		return super.remove_item(item_id, quantity, notify)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	await _test_planning_and_actual_actions()
	await _test_atomic_resources_and_no_effect()
	await _test_rebind_reentrancy_and_condition_only_rest()
	await _test_warmth_and_one_kit()
	await _test_time_scale_and_pause()
	await _test_open_guards_and_placement()
	await _test_actual_trap_placement_guard()
	await _test_enemy_approach_and_interruption()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("CAMP SYSTEM TEST PASS: real grounded player and camp model, three actual rewards, atomic resources/warmth, one kit per camp, time-scaled survival, pause/one-shot completion, placement/combat/enemy gates and interruption without refunds")
		quit(0)
	else:
		for failure in failures:
			push_error("CAMP SYSTEM TEST FAIL: " + failure)
		quit(1)


func _fixture(model: ExpeditionInventory = null) -> Dictionary:
	paused = false
	ExpeditionSession.begin_new_journey()
	var inventory := model if model != null else ExpeditionSession.get_inventory()
	if model != null:
		inventory.seed_default_loadout()
	for id: String in ["camp_kit", "pilgrim_ration", "boiled_rainwater", "linen_bandage"]:
		var count := inventory.count_item(id)
		if count > 0:
			# Test setup bypasses a deliberately rejecting inventory transaction.
			for index in range(inventory.slots.size() - 1, -1, -1):
				if str(inventory.slots[index].id) == id:
					inventory.slots.remove_at(index)
		inventory.add_item(id, 2, false)
	var world := CampFixtureGame.new()
	root.add_child(world)
	var floor_body := _body(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	world.add_child(floor_body)
	var player := DungeonPlayer.new()
	player.setup(world, null, inventory)
	player.position = Vector3(0, 0.91, 0)
	world.add_child(player)
	player.set_physics_process(false)
	for _frame in range(20):
		await physics_frame
		await process_frame
		player._physics_process(1.0 / 60.0)
		if player.is_on_floor():
			break
	_check(player.is_on_floor(), "camp fixture must use a real physics-grounded player")
	player.health = 30.0
	player.stamina = 20.0
	ExpeditionSession.hunger = 25.0
	ExpeditionSession.thirst = 25.0
	var camp := CAMP.new()
	world.camp = camp
	camp.setup(world, player, inventory)
	world.add_child(camp)
	camp.set_process(false)
	camp.opened.connect(func() -> void:
		player.set_camping(true)
		paused = true)
	camp.rest_started.connect(func() -> void: paused = false)
	camp.rest_finished.connect(func(_result: Dictionary) -> void: paused = true)
	camp.closed.connect(func(_reason: String, restore_controls: bool) -> void:
		player.set_camping(false)
		if restore_controls:
			paused = false)
	return {"world": world, "player": player, "inventory": inventory, "camp": camp, "floor": floor_body}


func _cleanup(fixture: Dictionary) -> void:
	fixture.camp.cancel_camp("", false)
	paused = false
	fixture.world.free()


func _test_planning_and_actual_actions() -> void:
	for id: String in ["rest", "meal", "treat"]:
		var fixture := await _fixture()
		var camp: DungeonCamp = fixture.camp
		var player: DungeonPlayer = fixture.player
		var inventory: ExpeditionInventory = fixture.inventory
		var starting_health := 220.0 if id == "treat" else 30.0
		player.health = starting_health
		if id == "treat":
			ExpeditionSession.apply_condition("bleeding", 180.0, "left_arm")
		var before := inventory.slots.duplicate(true)
		_check(bool(CAMP_TEST.deploy_and_open(camp).accepted) and camp.is_open() and camp.state == "planning" and paused, "opening must enter the real paused planning state")
		_check(inventory.count_item("camp_kit") == 1 and inventory.slots != before and camp.warmth == 3 and camp.kit_spent, "confirmed installation must spend one kit before tent planning without spending warmth")
		_check(is_instance_valid(camp.camp_visual) and camp.camp_visual.get_node_or_null("Flame") != null and camp.camp_visual.get_node_or_null("Bedroll") != null and camp.camp_visual.get_node_or_null("FireRingStone0") != null, "planning must retain the deployed campfire, bedroll and stone-ring model")
		_check(is_instance_valid(camp.overlay) and camp.get_snapshot().actions.size() == CAMP.ordered_action_ids().size(), "controller must expose the three existing activities plus every catalog cooking recipe")
		var completions: Array[Dictionary] = []
		camp.rest_finished.connect(func(result: Dictionary) -> void: completions.append(result))
		var started := camp.start_action(id)
		_check(bool(started.accepted) and camp.state == "resting" and not paused and inventory.count_item("camp_kit") == 1 and camp.kit_spent, "starting the first action must reuse the installed kit and resume the live world")
		_check(camp.warmth == 3 - int(CAMP.ACTIONS[id].warmth), "action warmth must be committed at start")
		if id == "meal":
			_check(inventory.count_item("pilgrim_ration") == 1 and inventory.count_item("boiled_rainwater") == 1, "meal must consume exactly one ration and water together at start")
		elif id == "treat":
			_check(inventory.count_item("linen_bandage") == 1, "treatment must consume exactly one bandage at start")
		camp.advance_rest(camp.rest_duration * 0.5)
		var partial_damage := 7.5 if id == "treat" else 0.0
		_check(is_equal_approx(player.health, starting_health - partial_damage) and is_equal_approx(player.stamina, 20.0) and completions.is_empty(), "partial progress must apply actual bleeding but no completion healing or stamina")
		_check(is_equal_approx(float(camp.get_snapshot().progress), 0.5), "overlay progress must track actual elapsed rest time")
		camp.advance_rest(camp.rest_duration)
		var expected_health := starting_health + float(CAMP.ACTIONS[id].health) - (15.0 if id == "treat" else 0.0)
		var expected_stamina := minf(100.0, 20.0 + float(CAMP.ACTIONS[id].stamina))
		_check(is_equal_approx(player.health, expected_health) and is_equal_approx(player.stamina, expected_stamina), "completed action must apply the exact authored player rewards once: " + id)
		_check(camp.state == "planning" and paused and completions.size() == 1 and bool(camp.last_result.completed), "completion must return to paused planning and emit exactly one result")
		var seconds := float(CAMP.ACTIONS[id].survival)
		var multiplier := 1.6 if id == "treat" else 1.0
		var expected_hunger := 25.0 - seconds * 100.0 / 5400.0 * multiplier + (32.0 if id == "meal" else 0.0)
		var expected_thirst := 25.0 - seconds * 100.0 / 3600.0 * multiplier + (38.0 if id == "meal" else 0.0)
		_check(is_equal_approx(ExpeditionSession.hunger, expected_hunger) and is_equal_approx(ExpeditionSession.thirst, expected_thirst), "real survival and catalog food/water effects must match elapsed game time: " + id)
		_check(is_equal_approx(float(camp.last_result.survival_seconds), seconds), "large final delta must not advance more than the action's authored survival time")
		if id == "treat":
			_check(not ExpeditionSession.has_condition("bleeding") and bool(camp.last_result.bleeding_cleared), "completed treatment must remove the actual bleeding condition")
		var needs_before := ExpeditionSession.get_survival_snapshot()
		camp.advance_rest(100.0)
		_check(completions.size() == 1 and is_equal_approx(player.health, expected_health) and ExpeditionSession.get_survival_snapshot() == needs_before, "duplicate updates after completion must not repeat rewards or survival time")
		camp.cancel_camp()
		_check(camp.state == "closed" and not player.camping and not paused and camp.camp_visual == null, "closing must restore controls and remove all camp props")
		_cleanup(fixture)


func _test_atomic_resources_and_no_effect() -> void:
	for failure: String in ["meal_supply", "bandage", "no_effect", "blacked_only", "invalid_action", "late_transaction"]:
		var model: ExpeditionInventory = RejectingSupplies.new() if failure == "late_transaction" else null
		var fixture := await _fixture(model)
		var camp: DungeonCamp = fixture.camp
		var player: DungeonPlayer = fixture.player
		var inventory: ExpeditionInventory = fixture.inventory
		if failure == "blacked_only":
			player.reset_body_health()
			player.apply_body_damage("left_arm", 60.0)
		_check(bool(CAMP_TEST.deploy_and_open(camp).accepted), "resource failure fixture must open planning")
		var action := "meal"
		match failure:
			"no_kit": inventory.remove_item("camp_kit", 2)
			"meal_supply": inventory.remove_item("boiled_rainwater", 2)
			"bandage":
				inventory.remove_item("linen_bandage", 2)
				action = "treat"
			"no_effect":
				player.health = DungeonPlayer.MAX_HEALTH
				player.stamina = 100.0
				ExpeditionSession.hunger = 100.0
				ExpeditionSession.thirst = 100.0
			"invalid_action": action = "unknown"
			"blacked_only": action = "treat"
		var slots_before := inventory.slots.duplicate(true)
		var changed: Array[bool] = []
		inventory.changed.connect(func() -> void: changed.append(true))
		var result := camp.start_action(action)
		_check(not bool(result.accepted) and camp.state == "planning" and camp.warmth == 3 and camp.kit_spent, "invalid or unaffordable action must not commit state or warmth: " + failure)
		_check(inventory.slots == slots_before and changed.is_empty(), "all resource removal, including a late rejected transaction, must be atomic and silent: " + failure)
		camp.cancel_camp()
		_check(inventory.slots == slots_before, "cleaning a paid camp must not consume or refund more items")
		_cleanup(fixture)


func _test_warmth_and_one_kit() -> void:
	var fixture := await _fixture()
	var camp: DungeonCamp = fixture.camp
	_check(bool(CAMP_TEST.deploy_and_open(camp).accepted), "warmth test must open planning")
	for _action in range(3):
		_check(bool(camp.start_action("rest").accepted), "remaining warmth must allow another useful rest")
		camp.advance_rest(8.0)
		_check(fixture.inventory.count_item("camp_kit") == 1, "later actions in the same camp must never consume another kit")
	var before: Array = fixture.inventory.slots.duplicate(true)
	_check(camp.warmth == 0 and str(camp.start_action("rest").reason) == "no_warmth" and fixture.inventory.slots == before, "spent warmth must block further rest without further resource use")
	_check(camp.is_open() and is_instance_valid(camp.camp_visual), "an exhausted camp must retain its result and props until explicitly dismantled")
	_cleanup(fixture)


func _test_rebind_reentrancy_and_condition_only_rest() -> void:
	var fixture := await _fixture()
	var camp: DungeonCamp = fixture.camp
	var old_inventory: ExpeditionInventory = fixture.inventory
	var next_inventory := ExpeditionInventory.new()
	next_inventory.seed_default_loadout()
	fixture.player.bind_inventory(next_inventory)
	camp.setup(fixture.world, fixture.player, next_inventory)
	camp.setup(fixture.world, fixture.player, next_inventory)
	_check(not old_inventory.changed.is_connected(camp.refresh) and next_inventory.changed.is_connected(camp.refresh) and camp.inventory == next_inventory, "repeated setup after a test-room reset must rebind the new inventory and disconnect the old session")
	var refresh_connections := 0
	for connection in next_inventory.changed.get_connections():
		if connection.callable == Callable(camp, "refresh"):
			refresh_connections += 1
	_check(refresh_connections == 1, "repeated setup must not duplicate inventory-to-overlay notifications")
	var original_slots := old_inventory.slots.duplicate(true)
	CAMP_TEST.deploy_and_open(camp)
	_check(bool(camp.start_action("rest").accepted) and old_inventory.slots == original_slots and next_inventory.count_item("camp_kit") == 0, "rest after a rebind must consume only the new session's kit")
	_cleanup(fixture)
	fixture = await _fixture()
	camp = fixture.camp
	CAMP_TEST.deploy_and_open(camp)
	var starts: Array[bool] = []
	camp.rest_started.connect(func() -> void: starts.append(true))
	fixture.inventory.changed.connect(func() -> void: camp.cancel_camp("inventory observer interruption"))
	var started := camp.start_action("meal")
	_check(bool(started.get("interrupted", false)) and starts.is_empty() and not camp.is_open(), "a synchronous inventory observer that cancels after commit must prevent a misleading rest-started signal")
	_check(fixture.inventory.count_item("camp_kit") == 1 and camp.warmth == 1 and is_equal_approx(fixture.player.health, 30.0), "observer interruption must retain committed cost without granting any rewards")
	_cleanup(fixture)
	for id: String in ["rest", "meal"]:
		fixture = await _fixture()
		camp = fixture.camp
		fixture.player.health = DungeonPlayer.MAX_HEALTH
		fixture.player.stamina = 100.0
		ExpeditionSession.hunger = 100.0
		ExpeditionSession.thirst = 100.0
		ExpeditionSession.apply_condition("curse", 50.0)
		CAMP_TEST.deploy_and_open(camp)
		_check(bool(camp.start_action(id).accepted), "rest must remain useful at full stats when a timed condition can expire: " + id)
		camp.advance_rest(camp.rest_duration)
		_check(not ExpeditionSession.has_condition("curse") and str(camp.get_snapshot().conditions) == "안정", "condition-only rest must advance actual condition timers and display the stable state afterward")
		_cleanup(fixture)
	fixture = await _fixture()
	camp = fixture.camp
	CAMP_TEST.deploy_and_open(camp)
	fixture.player.position.x += 1.0
	var before: Array = fixture.inventory.slots.duplicate(true)
	_check(str(camp.start_action("rest").reason) == "moving" and fixture.inventory.slots == before and camp.warmth == 3, "action start must revalidate that the player has not moved away during planning")
	_cleanup(fixture)


func _test_time_scale_and_pause() -> void:
	for fps: int in [1, 30, 60, 144]:
		var fixture := await _fixture()
		var camp: DungeonCamp = fixture.camp
		ExpeditionSession.apply_condition("curse", 20.0)
		CAMP_TEST.deploy_and_open(camp)
		camp.start_action("rest")
		for _frame in range(4 * fps):
			camp.advance_rest(1.0 / fps)
		var expected_hunger := 25.0 - 100.0 / 5400.0 * (20.0 * 1.5 + 10.0)
		_check(absf(ExpeditionSession.hunger - expected_hunger) < 0.00001 and is_equal_approx(camp.rest_elapsed, 4.0), "time scaling must be frame-rate independent across an expiring condition at %s FPS" % fps)
		var survival_before := ExpeditionSession.get_survival_snapshot()
		paused = true
		camp.advance_rest(100.0)
		_check(is_equal_approx(camp.rest_elapsed, 4.0) and ExpeditionSession.get_survival_snapshot() == survival_before and is_equal_approx(fixture.player.health, 30.0), "paused direct updates must not consume survival time or grant completion rewards")
		paused = false
		camp.advance_rest(-10.0)
		_check(is_equal_approx(camp.rest_elapsed, 4.0) and ExpeditionSession.get_survival_snapshot() == survival_before, "negative elapsed time must not reverse or advance camp progress")
		camp.cancel_camp("manual test")
		_check(bool(camp.last_result.cancelled) and is_equal_approx(float(camp.last_result.survival_seconds), 30.0), "mid-rest cancellation must retain exactly the survival time already elapsed")
		camp.advance_rest(100.0)
		_check(is_equal_approx(fixture.player.health, 30.0) and is_equal_approx(fixture.player.stamina, 20.0) and fixture.inventory.count_item("camp_kit") == 1 and camp.warmth == 2, "cancellation must give neither rewards nor resource/warmth refunds")
		_cleanup(fixture)


func _test_open_guards_and_placement() -> void:
	for gate: String in ["paused", "safe_zone", "dead", "combat", "bow", "trap", "airborne", "scene", "wall", "ledge"]:
		var fixture := await _fixture()
		var player: DungeonPlayer = fixture.player
		match gate:
			"paused": paused = true
			"safe_zone": player.configure_safe_zone(true)
			"dead": player.combat_state = DungeonPlayer.CombatState.DEAD
			"combat": player.combat_state = DungeonPlayer.CombatState.ACTIVE
			"bow": player.bow_drawing = true
			"trap": player.current_trap = Node.new()
			"airborne":
				player.position.y += 2.0
				player._physics_process(0.01)
			"scene": fixture.world.scene_failure = "moving"
			"wall":
				fixture.world.add_child(_body(Vector3(0, 0.9, -1.6), Vector3(0.6, 1.8, 0.6)))
				await physics_frame
				await process_frame
			"ledge":
				fixture.floor.free()
				fixture.world.add_child(_body(Vector3(0, -0.1, 0), Vector3(3.0, 0.2, 1.0)))
				await physics_frame
				await process_frame
		var before: Array = fixture.inventory.slots.duplicate(true)
		var result: Dictionary = CAMP_TEST.deploy_and_open(fixture.camp)
		_check(not bool(result.accepted) and fixture.camp.state in ["closed", "placing"] and fixture.camp.camp_visual == null and fixture.inventory.slots == before, "unsafe opening must fail without a camp model or resource cost: " + gate)
		if gate == "trap":
			player.current_trap.free()
			player.current_trap = null
		_cleanup(fixture)


func _test_enemy_approach_and_interruption() -> void:
	var fixture := await _fixture()
	var enemy := _enemy(fixture, Vector3(-7.0, 0.9, 0.0))
	fixture.world.add_child(_body(Vector3(-3.0, 1.0, 0), Vector3(0.2, 2, 5)))
	_check(str(CAMP_TEST.deploy_and_open(fixture.camp).reason) == "enemy_nearby", "an actual living enemy inside 8m must block camping even behind a wall")
	enemy.health = 0.0
	enemy.ai_state = DungeonEnemy.AIState.DEAD
	_check(bool(CAMP_TEST.deploy_and_open(fixture.camp).accepted), "a dead enemy must not block camping")
	fixture.camp.cancel_camp()
	enemy.health = 80.0
	enemy.ai_state = DungeonEnemy.AIState.IDLE
	enemy.position = Vector3(-10, 0.9, 0)
	CAMP_TEST.deploy_and_open(fixture.camp)
	fixture.camp.start_action("meal")
	fixture.camp.advance_rest(2.0)
	var needs_before := ExpeditionSession.get_survival_snapshot()
	enemy.position = Vector3(-5.9, 0.9, 0)
	fixture.camp.advance_rest(100.0)
	_check(not fixture.camp.is_open() and bool(fixture.camp.last_result.cancelled) and ExpeditionSession.get_survival_snapshot() == needs_before, "enemy approach inside 6m must cancel before processing any further elapsed time")
	_check(is_equal_approx(fixture.player.health, 30.0) and fixture.inventory.count_item("pilgrim_ration") == 1 and fixture.inventory.count_item("boiled_rainwater") == 1, "interrupted meal must not restore health or refund its prepaid supplies")
	_cleanup(fixture)
	for interruption: String in ["damage", "death", "movement"]:
		fixture = await _fixture()
		CAMP_TEST.deploy_and_open(fixture.camp)
		fixture.camp.start_action("treat")
		fixture.camp.advance_rest(1.0)
		match interruption:
			"damage": fixture.player.receive_environment_damage(1.0, "test")
			"death": fixture.player.receive_environment_damage(100.0, "test")
			"movement": fixture.player.position.x += 1.0
		fixture.camp.advance_rest(10.0)
		_check(not fixture.camp.is_open() and bool(fixture.camp.last_result.cancelled) and fixture.inventory.count_item("linen_bandage") == 1, "interruption must cancel the actual controller without refunding treatment: " + interruption)
		_cleanup(fixture)


func _test_actual_trap_placement_guard() -> void:
	for trap_state: int in [RuneTrap.TrapState.ARMED, RuneTrap.TrapState.INSPECTING, RuneTrap.TrapState.DISARMING, RuneTrap.TrapState.DISARMED, RuneTrap.TrapState.TRIGGERED]:
		var fixture := await _fixture()
		var trap := RuneTrap.new()
		trap.setup(null, fixture.world)
		trap.position = Vector3(-0.55, 0.0, -1.6)
		fixture.world.add_child(trap)
		trap.set_process(false)
		trap.state = trap_state
		var slots_before: Array = fixture.inventory.slots.duplicate(true)
		var result: Dictionary = CAMP_TEST.deploy_and_open(fixture.camp)
		if trap_state in [RuneTrap.TrapState.ARMED, RuneTrap.TrapState.INSPECTING, RuneTrap.TrapState.DISARMING]:
			_check(not bool(result.accepted) and str(result.reason) == "unsafe_ground" and fixture.camp.camp_visual == null, "actual active/inspecting/disarming rune plates must block camp placement despite using Area3D collisions")
		else:
			_check(bool(result.accepted), "disarmed or already-triggered rune plates must not permanently block a safe camp")
		_check((fixture.inventory.slots == slots_before if not bool(result.accepted) else fixture.inventory.count_item("camp_kit") == 1), "rejected trap placement must be free; confirmed safe placement must consume one kit")
		_cleanup(fixture)
	var fixture := await _fixture()
	var trap := RuneTrap.new()
	trap.setup(null, fixture.world)
	trap.position = Vector3(-0.55, 0.0, -1.6)
	fixture.world.add_child(trap)
	trap.set_process(false)
	trap.state = RuneTrap.TrapState.DISARMED
	_check(bool(CAMP_TEST.deploy_and_open(fixture.camp).accepted), "a cleared trap must initially allow planning")
	trap.state = RuneTrap.TrapState.ARMED
	_check(str(fixture.camp.start_action("rest").reason) == "unsafe_ground" and fixture.inventory.count_item("camp_kit") == 1, "action start must recheck newly armed nearby traps without consuming more than the installed kit")
	trap.state = RuneTrap.TrapState.DISARMED
	fixture.camp.start_action("rest")
	fixture.camp.advance_rest(1.0)
	var needs_before := ExpeditionSession.get_survival_snapshot()
	trap.state = RuneTrap.TrapState.ARMED
	fixture.camp.advance_rest(10.0)
	_check(not fixture.camp.is_open() and bool(fixture.camp.last_result.cancelled) and ExpeditionSession.get_survival_snapshot() == needs_before, "a dangerous trap reactivated during rest must interrupt before more time or completion healing")
	_cleanup(fixture)


func _enemy(fixture: Dictionary, at: Vector3) -> DungeonEnemy:
	var enemy := DungeonEnemy.new()
	enemy.configure("야영 위험 시험", 80.0, 18.0, 2.0, Color(0.2, 0.15, 0.1))
	enemy.setup(fixture.player, null, fixture.world)
	enemy.position = at
	fixture.world.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _body(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = 2
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
