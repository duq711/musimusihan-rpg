extends SceneTree

const COOKING := preload("res://scripts/camp_cooking_catalog.gd")
const EXPECTED := {
	"roast_meat": {"resources": {"raw_meat": 1}, "duration": 8.0, "survival": 60.0, "warmth": 1, "health": 18.0, "stamina": 35.0, "hunger": 40.0, "thirst": 0.0, "stress": 12.0},
	"mushroom_soup": {"resources": {"edible_mushroom": 2, "boiled_rainwater": 1}, "duration": 10.0, "survival": 90.0, "warmth": 1, "health": 12.0, "stamina": 30.0, "hunger": 30.0, "thirst": 45.0, "stress": 16.0},
	"trail_stew": {"resources": {"raw_meat": 1, "edible_mushroom": 1, "boiled_rainwater": 1}, "duration": 14.0, "survival": 120.0, "warmth": 2, "health": 35.0, "stamina": 65.0, "hunger": 65.0, "thirst": 35.0, "stress": 24.0},
}
const SUPPLIES := ["camp_kit", "raw_meat", "edible_mushroom", "boiled_rainwater"]

class CookingFixtureGame:
	extends Node3D
	var camp: DungeonCamp
	func _camp_open_failure() -> String:
		return ""
	func cancel_camp(reason := "", restore_controls := true) -> void:
		camp.cancel_camp(reason, restore_controls)

class RejectingIngredient:
	extends ExpeditionInventory
	var rejected_id := "boiled_rainwater"
	func remove_item(id: String, quantity := 1, notify := true) -> bool:
		if id == rejected_id:
			return false
		return super.remove_item(id, quantity, notify)

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_test_catalog_and_ingredient_availability()
	print("COOKING CHECK: real recipe transactions and recovery", " at ", Time.get_ticks_msec(), " ms")
	await _test_all_actual_recipes(false)
	await _test_all_actual_recipes(true)
	await _test_atomic_failures_and_unhelpful_cooking()
	await _test_warmth_and_one_kit()
	print("COOKING CHECK: reentrancy, stale actions and interruptions", " at ", Time.get_ticks_msec(), " ms")
	await _test_reentrant_start_and_observer_cancel()
	await _test_rebind_and_stale_actions()
	await _test_pause_time_and_interruptions()
	print("COOKING CHECK: real scene controls and seeded supply site", " at ", Time.get_ticks_msec(), " ms")
	await _test_real_scene_controls_and_supplies()
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original, "cooking tests must restore the exact original expedition without adding persistent recipe or dish fields")
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("COOKING SYSTEM PASS: three catalog recipes, actual ingredient transactions/eating/recovery, caps, no stored output, one kit/warmth, atomic failures, reentrancy, rebind, pause/interruptions, C/F2, scene cleanup and supply availability")
		quit(0)
		return
	for failure in failures:
		push_error("COOKING SYSTEM FAIL: " + failure)
	quit(1)


func _test_catalog_and_ingredient_availability() -> void:
	ExpeditionSession.begin_new_journey()
	_check(COOKING.ordered_recipe_ids() == ["roast_meat", "mushroom_soup", "trail_stew"], "cooking catalog must expose the three authored recipe IDs in order")
	for id: String in EXPECTED:
		var recipe: Dictionary = COOKING.get_recipe(id)
		_check(COOKING.action_id(id) == "cook:" + id and recipe.recipe_id == id and not str(recipe.title).is_empty(), "recipes must map to distinct executable cooking action IDs")
		for key: String in EXPECTED[id]:
			_check(recipe[key] == EXPECTED[id][key], "recipe must preserve its exact authored %s: %s" % [key, id])
		var ingredient: String = recipe.resources.keys()[0]
		recipe.resources[ingredient] = 999
		_check(COOKING.get_recipe(id).resources == EXPECTED[id].resources, "returned recipes must not alias nested authoritative ingredient costs")
	_check(COOKING.get_recipe("unknown").is_empty(), "unknown recipes must not resolve to an arbitrary valid dish")
	var bag := ExpeditionSession.get_inventory()
	_check(bag.count_item("raw_meat") == 1 and bag.count_item("edible_mushroom") == 2, "fresh adventures must provide the authored starter cooking ingredients")
	_check(ExpeditionInventory.ITEM_DEFINITIONS.has("raw_meat") and ExpeditionInventory.ITEM_DEFINITIONS.has("edible_mushroom"), "ingredients must exist in the authoritative item catalog")
	_check(ExpeditionSession.get_stock_quantity("raw_meat") == 6 and ExpeditionSession.get_buy_price("raw_meat") == 10, "merchant must sell the authored meat stock and price")
	_check(ExpeditionSession.get_stock_quantity("edible_mushroom") == 8 and ExpeditionSession.get_buy_price("edible_mushroom") == 5, "merchant must sell the authored mushroom stock and price")
	var session_snapshot := ExpeditionSession.capture_snapshot()
	_check(session_snapshot.size() == 11 and session_snapshot.has("body_health"), "session must include body health while immediately eaten camp meals add no persistent cooking fields")


func _fixture(model: ExpeditionInventory = null) -> Dictionary:
	paused = false
	ExpeditionSession.begin_new_journey()
	var inventory := model if model != null else ExpeditionSession.get_inventory()
	if model != null:
		inventory.seed_default_loadout()
	for id: String in SUPPLIES:
		_set_count(inventory, id, 4)
	var world := CookingFixtureGame.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.position = Vector3(0.0, -0.1, 0.0)
	floor_body.collision_layer = 2
	floor_body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(30.0, 0.2, 30.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	floor_body.add_child(collider)
	world.add_child(floor_body)
	var player := DungeonPlayer.new()
	player.setup(world, null, inventory)
	player.position = Vector3(0.0, 0.91, 0.0)
	world.add_child(player)
	player.set_physics_process(false)
	for frame in 20:
		await physics_frame
		await process_frame
		player._physics_process(1.0 / 60.0)
		if player.is_on_floor():
			break
	_check(player.is_on_floor(), "cooking fixture must be grounded on the real physics floor")
	player.health = 30.0
	player.stamina = 20.0
	ExpeditionSession.hunger = 25.0
	ExpeditionSession.thirst = 25.0
	ExpeditionSession.set_stress(90.0)
	var camp := DungeonCamp.new()
	world.camp = camp
	camp.setup(world, player, inventory)
	world.add_child(camp)
	camp.set_process(false)
	camp.opened.connect(func() -> void: player.set_camping(true); paused = true)
	camp.rest_started.connect(func() -> void: paused = false)
	camp.rest_finished.connect(func(_result: Dictionary) -> void: paused = true)
	camp.closed.connect(func(_reason: String, restore_controls: bool) -> void:
		player.set_camping(false)
		if restore_controls:
			paused = false)
	return {"world": world, "player": player, "inventory": inventory, "camp": camp}


func _cleanup(fixture: Dictionary) -> void:
	fixture.camp.cancel_camp("", false)
	paused = false
	fixture.world.free()


func _test_all_actual_recipes(capped: bool) -> void:
	for id: String in EXPECTED:
		var fixture := await _fixture()
		var camp: DungeonCamp = fixture.camp
		var player: DungeonPlayer = fixture.player
		var bag: ExpeditionInventory = fixture.inventory
		var recipe: Dictionary = EXPECTED[id]
		if capped:
			player.health = 95.0
			player.stamina = 95.0
			ExpeditionSession.hunger = 95.0
			ExpeditionSession.thirst = 95.0
			ExpeditionSession.set_stress(5.0)
		while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
			bag.add_item("reliquary")
		var before := _actual_values(player)
		var before_slots := bag.slots.duplicate(true)
		var before_equipment := bag.equipment.duplicate(true)
		var counts := _item_counts(bag)
		_check(bool(camp.open_camp().accepted) and paused and bag.slots == before_slots, "opening cooking plans must not consume or move items")
		var actions: Array = camp.get_snapshot().actions
		var visible_recipe_ids: Array[String] = []
		for action: Dictionary in actions:
			if str(action.id).begins_with("cook:"):
				visible_recipe_ids.append(action.id)
				_check(str(action.get("category", "")) == "cooking", "recipe actions must be identified as cooking in the actual camp snapshot")
				var action_recipe: Dictionary = EXPECTED[str(action.id).trim_prefix("cook:")]
				for ingredient: String in action_recipe.resources:
					var required := int(action_recipe.resources[ingredient])
					_check(int(action.resources[ingredient]) == required and str(action.cost).contains("%s %d" % [ExpeditionInventory.get_item_name(ingredient), required]), "snapshot must expose the exact ingredient quantity, including two mushrooms")
					_check(str(action.ingredient_text).contains("%s %d / %d" % [ExpeditionInventory.get_item_name(ingredient), bag.count_item(ingredient), required]), "recipe readiness text must show current owned/required quantities")
		_check(actions.size() == 6 and visible_recipe_ids.size() == 3, "camp must retain the three existing activities and expose all three recipes")
		var cooking_tools := camp.camp_visual.get_node("CookingTools") as Node3D
		_check(not cooking_tools.visible, "idle camp plans must not show an actively cooking dish")
		var completions: Array[Dictionary] = []
		camp.rest_finished.connect(func(result: Dictionary) -> void: completions.append(result))
		var started := camp.start_action(COOKING.action_id(id))
		_check(bool(started.accepted) and camp.state == "resting" and not paused and player.camping, "cooking must run as a real live camp activity")
		var costs: Dictionary = recipe.resources.duplicate(true)
		costs.camp_kit = 1
		_check(started.resources_spent == costs and camp.warmth == 3 - int(recipe.warmth), "cooking must commit exact authored ingredient quantities and warmth once")
		_check_counts_after_costs(bag, counts, costs, id)
		var snapshot := camp.get_snapshot()
		_check(bool(snapshot.is_cooking) and snapshot.recipe_id == id and snapshot.active_action_id == COOKING.action_id(id) and not str(snapshot.action_title).is_empty(), "actual cooking state must identify the active recipe for UI and visuals")
		_check(is_instance_valid(camp.camp_visual), "cooking must retain the real camp model")
		_check(cooking_tools.is_visible_in_tree() and str(cooking_tools.get_meta("recipe_id", "")) == id, "starting a real recipe must activate its actual cooking geometry")
		_check((cooking_tools.get_node("RoastingSpit") as Node3D).visible == (id == "roast_meat") and (cooking_tools.get_node("SoupPot") as Node3D).visible == (id != "roast_meat"), "meat must use a spit while both liquid recipes use a cooking pot")
		var moving_part := cooking_tools.get_node("RoastingSpit/SpitSkewer" if id == "roast_meat" else "SoupPot/SoupBubble0") as Node3D
		var initial_pose := moving_part.transform
		camp.advance_rest(float(recipe.duration) * 0.5)
		_check(moving_part.transform != initial_pose and is_equal_approx(float(cooking_tools.get_meta("progress", -1.0)), 0.5), "actual cooking progress must animate roasting/boiling geometry from the shared activity clock")
		_check(cooking_tools.find_children("*", "CollisionObject3D", true, false).is_empty(), "cooking presentation must not add combat or interaction bodies")
		_check(player.health == before.health and player.stamina == before.stamina and ExpeditionSession.stress == before.stress and completions.is_empty(), "unfinished cooking must not feed, heal, refill stamina or reduce stress")
		_check(ExpeditionSession.hunger < before.hunger and ExpeditionSession.thirst < before.thirst, "cooking must advance actual survival time before food is eaten")
		var paid_slots := bag.slots.duplicate(true)
		camp.advance_rest(10000.0)
		_check(camp.state == "planning" and paused and completions.size() == 1 and bool(camp.last_result.completed), "cooking completion must emit once and return to planning")
		_check(not bool(camp.get_snapshot().is_cooking), "completed cooking must stop its active-recipe visual state")
		_check(not cooking_tools.visible and bool(camp.last_result.get("cooked_and_eaten", false)) and camp.last_result.recipe_id == id, "completion must mark the dish eaten and stop visible cooking rather than leaving a phantom serving")
		var hunger := minf(100.0, float(before.hunger) - float(recipe.survival) * 100.0 / 5400.0 + float(recipe.hunger))
		var thirst := minf(100.0, float(before.thirst) - float(recipe.survival) * 100.0 / 3600.0 + float(recipe.thirst))
		_check(is_equal_approx(player.health, minf(DungeonPlayer.MAX_HEALTH, float(before.health) + float(recipe.health))) and is_equal_approx(player.stamina, minf(100.0, float(before.stamina) + float(recipe.stamina))), "eating must apply exact health/stamina recovery with caps: " + id)
		_check(is_equal_approx(ExpeditionSession.hunger, hunger) and is_equal_approx(ExpeditionSession.thirst, thirst) and is_equal_approx(ExpeditionSession.stress, maxf(0.0, float(before.stress) - float(recipe.stress))), "eating must apply exact needs/stress effects after exactly one survival interval: " + id)
		_check(is_equal_approx(float(camp.last_result.survival_seconds), float(recipe.survival)), "oversized final delta must not exceed the recipe's authored survival time")
		_check(bag.slots == paid_slots and bag.equipment == before_equipment, "immediately eaten dishes must not add a stored output or require an extra slot even with a full bag")
		var finished_values := _actual_values(player)
		camp.advance_rest(10000.0)
		_check(completions.size() == 1 and _actual_values(player) == finished_values and bag.slots == paid_slots, "stale completion updates must not duplicate eating effects or inventory changes")
		_cleanup(fixture)


func _test_atomic_failures_and_unhelpful_cooking() -> void:
	for missing: String in ["camp_kit", "raw_meat", "edible_mushroom", "boiled_rainwater", "soup_second_mushroom", "late_rejection", "warmth", "unknown", "no_effect"]:
		var fixture := await _fixture(RejectingIngredient.new() if missing == "late_rejection" else null)
		var camp: DungeonCamp = fixture.camp
		var bag: ExpeditionInventory = fixture.inventory
		_check(bool(camp.open_camp().accepted), "invalid cooking fixture must still open the real planning screen")
		var action_id := "cook:trail_stew"
		if missing in SUPPLIES:
			_set_count(bag, missing, 0)
		elif missing == "soup_second_mushroom":
			_set_count(bag, "edible_mushroom", 1)
			action_id = "cook:mushroom_soup"
		elif missing == "warmth":
			camp.warmth = 1
		elif missing == "unknown":
			action_id = "cook:unknown"
		elif missing == "no_effect":
			fixture.player.health = DungeonPlayer.MAX_HEALTH
			fixture.player.stamina = 100.0
			ExpeditionSession.hunger = 100.0
			ExpeditionSession.thirst = 100.0
			ExpeditionSession.set_stress(0.0)
		var slots := bag.slots.duplicate(true)
		var warmth := camp.warmth
		var values := _actual_values(fixture.player)
		var notifications: Array[bool] = []
		bag.changed.connect(func() -> void: notifications.append(true))
		var result := camp.start_action(action_id)
		_check(not bool(result.accepted) and camp.state == "planning" and camp.warmth == warmth and not camp.kit_spent, "invalid cooking must reject without committing state: " + missing)
		_check(bag.slots == slots and notifications.is_empty() and _actual_values(fixture.player) == values, "missing or rejected ingredient must roll back all resources silently, including the kit: " + missing)
		_cleanup(fixture)
	for benefit: String in ["stress", "hunger", "thirst", "condition", "roast_thirst_only"]:
		var fixture := await _fixture()
		fixture.player.health = DungeonPlayer.MAX_HEALTH
		fixture.player.stamina = 100.0
		ExpeditionSession.hunger = 80.0 if benefit == "hunger" else 100.0
		ExpeditionSession.thirst = 80.0 if benefit in ["thirst", "roast_thirst_only"] else 100.0
		ExpeditionSession.set_stress(10.0 if benefit == "stress" else 0.0)
		if benefit == "condition":
			ExpeditionSession.apply_condition("curse", 20.0)
		fixture.camp.open_camp()
		var slots: Array = fixture.inventory.slots.duplicate(true)
		var result: Dictionary = fixture.camp.start_action("cook:roast_meat" if benefit == "roast_thirst_only" else "cook:mushroom_soup")
		if benefit in ["condition", "roast_thirst_only"]:
			_check(not bool(result.accepted) and str(result.reason) == "no_effect" and fixture.inventory.slots == slots, "cooking must not waste ingredients just to wait out a condition or prepare dry meat for thirst alone: " + benefit)
		else:
			_check(bool(result.accepted), "cooking must remain useful for an applicable needs/stress-only deficit: " + benefit)
		_cleanup(fixture)


func _test_warmth_and_one_kit() -> void:
	var fixture := await _fixture()
	var camp: DungeonCamp = fixture.camp
	camp.open_camp()
	for id: String in ["roast_meat", "mushroom_soup"]:
		_check(bool(camp.start_action(COOKING.action_id(id)).accepted), "remaining warmth must allow repeated distinct recipes")
		camp.advance_rest(100.0)
		_check(fixture.inventory.count_item("camp_kit") == 3, "all recipes at the same fire must share the one already-spent kit")
	var slots: Array = fixture.inventory.slots.duplicate(true)
	_check(camp.warmth == 1 and str(camp.start_action("cook:trail_stew").reason) == "no_warmth" and fixture.inventory.slots == slots, "a two-warmth stew must not start with one warmth or consume its ingredients")
	_cleanup(fixture)


func _test_reentrant_start_and_observer_cancel() -> void:
	for interrupt in [false, true]:
		var fixture := await _fixture()
		var camp: DungeonCamp = fixture.camp
		camp.open_camp()
		var nested: Array[Dictionary] = []
		var starts: Array[bool] = []
		camp.rest_started.connect(func() -> void: starts.append(true))
		fixture.inventory.changed.connect(func() -> void:
			if interrupt:
				camp.cancel_camp("요리 재료 관찰자 중단")
			else:
				nested.append(camp.start_action("cook:trail_stew")))
		var result := camp.start_action("cook:trail_stew")
		_check(fixture.inventory.count_item("camp_kit") == 3 and fixture.inventory.count_item("raw_meat") == 3 and camp.warmth == 1, "synchronous inventory callbacks must not double-spend cooking resources or warmth")
		if interrupt:
			_check(bool(result.get("interrupted", false)) and not camp.is_open() and starts.is_empty(), "notification-time cancellation must suppress stale cooking-start signals")
		else:
			_check(bool(result.accepted) and starts.size() == 1 and nested.size() == 1 and not bool(nested[0].accepted), "reentrant recipe requests must see committed busy state and fail without another start")
		_cleanup(fixture)


func _test_rebind_and_stale_actions() -> void:
	var fixture := await _fixture()
	var camp: DungeonCamp = fixture.camp
	var old_inventory: ExpeditionInventory = fixture.inventory
	camp.open_camp()
	camp.start_action("cook:roast_meat")
	camp.advance_rest(2.0)
	var old_slots := old_inventory.slots.duplicate(true)
	var fresh := ExpeditionInventory.new()
	fresh.seed_default_loadout()
	fixture.player.bind_inventory(fresh)
	camp.setup(fixture.world, fixture.player, fresh)
	camp.setup(fixture.world, fixture.player, fresh)
	_check(not camp.is_open() and not old_inventory.changed.is_connected(camp.refresh) and fresh.changed.is_connected(camp.refresh), "rebinding inventory must cancel cooking and disconnect the old trial")
	var subscriptions := 0
	for connection: Dictionary in fresh.changed.get_connections():
		if connection.callable == Callable(camp, "refresh"):
			subscriptions += 1
	_check(subscriptions == 1, "repeated setup must not duplicate recipe refresh callbacks")
	var values := _actual_values(fixture.player)
	camp.advance_rest(100.0)
	_check(_actual_values(fixture.player) == values and old_inventory.slots == old_slots, "a stale cooking completion must not affect either old or rebound inventory")
	paused = false
	camp.open_camp()
	_check(bool(camp.start_action("cook:roast_meat").accepted) and fresh.count_item("raw_meat") == 0 and fresh.count_item("camp_kit") == 0 and old_inventory.slots == old_slots, "cooking after rebind must consume only the fresh inventory ingredients and kit")
	_cleanup(fixture)


func _test_pause_time_and_interruptions() -> void:
	for cause: String in ["manual", "damage", "enemy", "movement", "safe_zone", "scene_exit"]:
		var fixture := await _fixture()
		var camp: DungeonCamp = fixture.camp
		camp.open_camp()
		camp.start_action("cook:trail_stew")
		camp.advance_rest(3.5)
		var values := _actual_values(fixture.player)
		var slots: Array = fixture.inventory.slots.duplicate(true)
		var bubble := camp.camp_visual.get_node("CookingTools/SoupPot/SoupBubble0") as Node3D
		var paused_pose := bubble.transform
		paused = true
		camp.advance_rest(1000.0)
		camp._process(1000.0)
		_check(_actual_values(fixture.player) == values and is_equal_approx(camp.rest_elapsed, 3.5), "paused cooking must neither advance survival nor feed the player")
		_check(bubble.transform == paused_pose and is_equal_approx(float(camp.camp_visual.get_node("CookingTools").get_meta("progress")), 0.25), "paused cooking geometry must stay on the same shared progress with no independent stirring timer")
		paused = false
		camp.advance_rest(-10.0)
		_check(is_equal_approx(camp.rest_elapsed, 3.5), "negative elapsed time must not alter cooking progress")
		match cause:
			"manual": camp.cancel_camp("수동 중단")
			"damage": fixture.player.receive_environment_damage(1.0, "요리 중 피격")
			"enemy":
				var enemy := DungeonEnemy.new()
				enemy.configure("요리 중 접근", 80.0, 18.0, 2.0, Color(0.2, 0.15, 0.1))
				enemy.setup(fixture.player, null, fixture.world)
				enemy.position = Vector3(0.0, 0.9, 5.0)
				fixture.world.add_child(enemy)
				enemy.set_physics_process(false)
			"movement": fixture.player.position.x += 1.0
			"safe_zone": fixture.player.safe_zone_mode = true
			"scene_exit":
				fixture.world.free()
				await process_frame
				_check(ExpeditionSession.hunger == values.hunger and ExpeditionSession.thirst == values.thirst and ExpeditionSession.stress == values.stress, "destroying the cooking scene must not grant delayed meal effects")
				paused = false
				continue
		camp.advance_rest(1000.0)
		_check(not camp.is_open() and bool(camp.last_result.cancelled) and fixture.inventory.slots == slots and camp.warmth == 1, "interrupted cooking must stop without refunding committed costs: " + cause)
		_check(fixture.player.health <= values.health and fixture.player.stamina == values.stamina and ExpeditionSession.hunger == values.hunger and ExpeditionSession.thirst == values.thirst and ExpeditionSession.stress >= values.stress, "interrupted cooking must not grant any eating reward: " + cause)
		_check(is_equal_approx(float(camp.last_result.survival_seconds), 30.0), "interruption must preserve only the actual elapsed quarter of stew survival time")
		_cleanup(fixture)


func _test_real_scene_controls_and_supplies() -> void:
	paused = false
	ExpeditionSession.begin_new_journey()
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	game.loot_spawn_seed = preload("res://tests/loot_test_helpers.gd").seed_with_items("reliquary", ["raw_meat", "edible_mushroom", "boiled_rainwater"])
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	var entrance := preload("res://tests/loot_test_helpers.gd").chest_with_item(game, "raw_meat")
	_check(is_instance_valid(entrance), "a seeded visit containing cooking supplies must create its real supply container")
	var entrance_counts: Dictionary = {}
	if is_instance_valid(entrance):
		for stack: Dictionary in entrance.container.items:
			entrance_counts[stack.id] = int(entrance_counts.get(stack.id, 0)) + int(stack.quantity)
	_check(entrance_counts.get("raw_meat", 0) == 2 and entrance_counts.get("edible_mushroom", 0) == 3 and entrance_counts.get("boiled_rainwater", 0) == 2, "actual dungeon entrance chest must provide the authored cooking ingredients and water")
	game.queue_free()
	await process_frame
	var sandbox: Node = root.get_node("TestRoomSandbox")
	var snapshot := ExpeditionSession.capture_snapshot()
	var room := (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	room.set_process(false)
	room.camp.set_process(false)
	room.run_feature("camping")
	for id: String in SUPPLIES:
		_set_count(room.inventory, id, 4)
	for frame in 60:
		await physics_frame
		if room.player.is_on_floor():
			break
	room.player.set_physics_process(false)
	for key: Key in [KEY_C, KEY_F2]:
		if room.panel_open:
			room._hide_test_panel()
		_key(room, KEY_C)
		_check(room.camp.is_open() and paused, "real C input must open cooking plans on a valid test-room floor")
		room.camp.overlay.category_buttons["cooking"].pressed.emit()
		_check(room.camp.overlay.selected_category == "cooking" and room.camp.overlay.action_cards["cook:roast_meat"].visible, "actual cooking tab must expose the real recipe button")
		room.camp.overlay.action_buttons["cook:roast_meat"].pressed.emit()
		_check(room.camp.state == "resting" and bool(room.camp.get_snapshot().is_cooking), "actual recipe button must start the production cooking action")
		room.camp.advance_rest(2.0)
		var paid_slots: Array = room.inventory.slots.duplicate(true)
		var before := _actual_values(room.player)
		_key(room, key)
		_check(not room.camp.is_open() and not room.player.camping and room.inventory.slots == paid_slots, "actual C/F2 controls must cancel cooking without refunding ingredients")
		room.camp.advance_rest(100.0)
		_check(_actual_values(room.player) == before, "actual menu/camp cancellation must suppress every delayed cooking reward")
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == snapshot, "cooking in the actual test room must preserve and restore the original session")
	room.queue_free()
	await process_frame
	paused = false


func _set_count(bag: ExpeditionInventory, id: String, count: int) -> void:
	for index in range(bag.slots.size() - 1, -1, -1):
		if str(bag.slots[index].id) == id:
			bag.slots.remove_at(index)
	if count > 0:
		bag.add_item(id, count, false)


func _item_counts(bag: ExpeditionInventory) -> Dictionary:
	var result: Dictionary = {}
	for item_id: String in ExpeditionInventory.ITEM_DEFINITIONS:
		result[item_id] = bag.count_item(item_id)
	return result


func _check_counts_after_costs(bag: ExpeditionInventory, before: Dictionary, costs: Dictionary, context: String) -> void:
	for item_id: String in before:
		_check(bag.count_item(item_id) == int(before[item_id]) - int(costs.get(item_id, 0)), "recipe must spend only exact requested resources: %s / %s" % [context, item_id])


func _actual_values(player: DungeonPlayer) -> Dictionary:
	return {"health": player.health, "stamina": player.stamina, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress}


func _key(scene: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	scene._unhandled_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
