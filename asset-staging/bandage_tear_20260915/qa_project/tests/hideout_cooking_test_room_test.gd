extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const COOKING := preload("res://scripts/camp_cooking_catalog.gd")
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
	original.add_item("raw_meat", 4)
	original.add_item("edible_mushroom", 3)
	ExpeditionSession.crowns = 713
	ExpeditionSession.hunger = 62.0
	ExpeditionSession.thirst = 47.0
	ExpeditionSession.stress = 31.0
	ExpeditionSession.apply_condition("curse", 180.0)
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var original_metadata := original.equipment_data.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	bag = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "hearth cooking must begin in the paused isolated test room")
	_test_catalog()
	# Remove ingredients before filling the bag, so the fixture must make room
	# for actual catalog supplies rather than merely top up existing stacks.
	for item_id in _supplies():
		_set_count(item_id, 0)
	_set_count("camp_kit", 0)
	while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
		bag.add_item("reliquary", 1, false)
	room.run_feature("hideout_cooking")
	_check("교체" in room.status_label.text and bag.slots.size() == ExpeditionInventory.MAX_SLOTS, "full-bag cooking fixture must disclose bounded replacement and preserve a playable full bag")
	_check_supplies()
	if await _wait_for_scene(HIDEOUT_PATH):
		await _test_hearth_interaction()
		_test_all_recipes()
		await _return_to_room()
	if await _enter_kitchen():
		_test_missing_ingredient()
		await _return_to_room()
	if await _enter_kitchen():
		_test_cancelled_recipe()
		await _return_to_room()
	if await _enter_kitchen():
		var controller: Node = current_scene.cooking_controller
		controller.set_process(false)
		_press_recipe(controller, "trail_stew")
		controller.advance_cooking(2.0)
		var spent_counts := _counts()
		var interrupted_needs := Vector3(ExpeditionSession.hunger, ExpeditionSession.thirst, ExpeditionSession.stress)
		await _return_to_room()
		_check(_counts() == spent_counts, "F2 during cooking must retain consumed ingredients without adding a completed meal")
		_check(Vector3(ExpeditionSession.hunger, ExpeditionSession.thirst, ExpeditionSession.stress) == interrupted_needs, "F2 must retain only elapsed recipe time and grant no delayed eating effect: before=%s after=%s" % [interrupted_needs, Vector3(ExpeditionSession.hunger, ExpeditionSession.thirst, ExpeditionSession.stress)])
	_check(sandbox.saved_session == snapshot and original.slots == original_slots and original.equipment_data == original_metadata, "repeated meals, failed starts and interrupted cooking must not mutate the original expedition")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room = current_scene as Node3D
		var previous_bag := bag
		sandbox.prepare_cooking_trial()
		room.reset_room()
		bag = room.inventory
		_check(bag != previous_bag and bag != original and not sandbox.pending_cooking_trial, "test reset must discard the cooking request and allocate a fresh isolated inventory")
		_check(sandbox.saved_session == snapshot, "reset must preserve the original expedition snapshot")
		if await _enter_kitchen():
			var controller: Node = current_scene.cooking_controller
			controller.set_process(false)
			_press_recipe(controller, "mushroom_soup")
			controller.advance_cooking(100.0)
			_check(bool(controller.last_result.get("cooked_and_eaten", false)), "a reset test session must still complete a real meal")
			await _return_to_room()
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "leaving hearth trials must restore the exact original inventory object")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "leaving hearth trials must restore all original expedition values and conditions")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_metadata, "original items, equipment and instance metadata must survive cooking trials unchanged")
	_check(not sandbox.pending_cooking_trial and not sandbox.prepare_cooking_trial(), "finished sessions must clear and reject pending kitchen requests")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("HIDEOUT COOKING TEST ROOM PASS: central hearth interaction, three real recipe buttons, exact costs/time/eating, full-bag catalog supplies, no kit/warmth, fire and ingredient failures, cancellation, repeated F2/reset and original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT COOKING TEST ROOM FAIL: " + failure)
		quit(1)


func _test_catalog() -> void:
	var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "hideout_cooking")
	_check(matches.size() == 1 and matches[0].category == "장면" and matches[0].action == "hideout_cooking", "the real hearth kitchen must have one executable scene catalog entry")
	for item_id in _supplies():
		matches = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:" + item_id)
		_check(matches.size() == 1 and matches[0].action == "item", "every ingredient must remain automatically registered from the original item catalog: " + item_id)
		var stocked := false
		for chest in room.loot_chests:
			for stack in chest.container.items:
				stocked = stocked or (str(stack.id) == item_id and int(stack.quantity) > 0)
		_check(stocked, "original-catalog supply chests must contain every cooking ingredient: " + item_id)


func _test_hearth_interaction() -> void:
	var hideout: Node = current_scene
	var controller: Node = hideout.cooking_controller
	_check(controller.state == "planning" and controller.inventory == bag and paused, "trial entry must open the real paused kitchen with the isolated inventory")
	_check(not sandbox.pending_cooking_trial and not sandbox.consume_cooking_trial(), "hideout must consume the one-shot cooking request exactly once")
	_check(hideout.player.health == 35.0 and hideout.player.stamina == 20.0 and ExpeditionSession.hunger == 15.0 and ExpeditionSession.thirst == 20.0 and ExpeditionSession.stress == 55.0 and ExpeditionSession.active_conditions.is_empty(), "actual hideout entry must apply reproducible wounded/hungry/thirsty/stressed cooking values")
	controller.close_kitchen()
	var actor: DungeonPlayer = hideout.player
	actor.set_physics_process(false)
	var pot := hideout.find_child("CookingPotInteraction", true, false) as HideoutInteractable
	var hearth := hideout.find_child("HearthInteraction", true, false) as HideoutInteractable
	_check(is_instance_valid(pot) and pot.action_id == "meal" and is_equal_approx(pot.interaction_duration, 0.3), "the central cooking apparatus must expose the actual timed meal interaction")
	_check(hideout.hearth_light.position.y < 0.60 and hideout.hearth_light.position.y > 0.39, "hearth light stays above the logs and below the cauldron floor instead of inside its cavity")
	_check(is_instance_valid(hideout.cooking_world) and hideout.cooking_world.is_visible_in_tree(), "the lit central hearth must show its actual persistent cooking equipment")
	if pot == null or hearth == null:
		return
	_check(pot.global_position.distance_to(hideout.hearth_root.global_position) < 1.5, "the usable cooking pot must be at the central hearth")
	await physics_frame
	await physics_frame
	var start := actor.camera.global_position
	var target := pot.global_position + pot.interaction_offset
	var query := PhysicsRayQueryParameters3D.create(start, target, DungeonPlayer.WORLD_LAYER | DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider.get_meta("interaction_owner", null) == pot, "the prepared player must reach the cooking interaction through the real world ray without a blocking prop or hearth area")
	var normal_query := PhysicsRayQueryParameters3D.create(start, start - actor.camera.global_transform.basis.z * 3.0, DungeonPlayer.INTERACT_LAYER)
	normal_query.collide_with_areas = true
	normal_query.collide_with_bodies = false
	var normal_hit := actor.get_world_3d().direct_space_state.intersect_ray(normal_query)
	_check(not normal_hit.is_empty() and normal_hit.collider.get_meta("interaction_owner", null) == pot, "the trial camera must place the pot inside the player's actual three-metre interaction ray")
	pot.interact(actor)
	_check(actor.timed_interaction_owner == pot and controller.state == "closed", "E at the pot must start its actual preparation timer before opening the menu")
	actor.advance_timed_interaction(0.35)
	_check(controller.state == "planning" and paused, "normal timed interaction completion must open the actual kitchen and pause hideout movement")
	controller.close_kitchen()
	actor.set_physics_process(false)
	hearth.interact(actor)
	actor.advance_timed_interaction(0.4)
	_check(not hideout.brazier_lit, "the original hearth interaction must still extinguish the fire")
	var unlit_counts := _counts()
	var rejected: Dictionary = controller.open_kitchen()
	_check(not bool(rejected.get("accepted", false)) and str(rejected.get("reason", "")) == "fire_unlit" and controller.state == "closed" and _counts() == unlit_counts, "an extinguished hearth must reject cooking without spending any ingredients")
	pot.interact(actor)
	actor.advance_timed_interaction(0.35)
	_check(controller.state == "closed" and _counts() == unlit_counts, "using the actual pot while the fire is out must not bypass the lit-fire requirement")
	hearth.interact(actor)
	actor.advance_timed_interaction(0.4)
	_check(hideout.brazier_lit, "original hearth interaction must relight the cooking fire")
	pot.interact(actor)
	actor.advance_timed_interaction(0.35)
	_check(controller.state == "planning" and paused, "relit hearth must reopen through the same actual pot interaction")


func _test_all_recipes() -> void:
	var hideout: Node = current_scene
	var controller: Node = hideout.cooking_controller
	controller.set_process(false)
	var equipment := bag.equipment.duplicate(true)
	for recipe_id in COOKING.ordered_recipe_ids():
		var recipe := COOKING.get_recipe(recipe_id)
		var before := _values(hideout.player)
		var before_counts := _counts()
		controller.advance_cooking(100.0)
		_check(paused and _values(hideout.player) == before and _counts() == before_counts, "planning must not advance survival time or consume ingredients")
		_press_recipe(controller, recipe_id)
		_check(controller.state == "cooking" and paused, "pressing a stocked recipe button must start the actual timed kitchen while hideout play remains paused: " + recipe_id)
		for item_id in before_counts:
			_check(bag.count_item(item_id) == int(before_counts[item_id]) - int(recipe.resources.get(item_id, 0)), "recipe start must spend exactly the catalog ingredients and no additional kit: " + recipe_id + "/" + item_id)
		var paid_slots := bag.slots.duplicate(true)
		controller.advance_cooking(float(recipe.duration) * 0.5)
		_check(hideout.player.health == before.health and hideout.player.stamina == before.stamina and ExpeditionSession.stress == before.stress, "unfinished dishes must grant no health/stamina/stress recovery")
		_check(ExpeditionSession.hunger < before.hunger and ExpeditionSession.thirst < before.thirst, "actual kitchen timer must advance catalog survival time before eating")
		controller.advance_cooking(10000.0)
		var expected_hunger := clampf(float(before.hunger) - float(recipe.survival) * ExpeditionSession.MAX_NEED / ExpeditionSession.HUNGER_FULL_DURATION_SECONDS + float(recipe.hunger), 0.0, 100.0)
		var expected_thirst := clampf(float(before.thirst) - float(recipe.survival) * ExpeditionSession.MAX_NEED / ExpeditionSession.THIRST_FULL_DURATION_SECONDS + float(recipe.thirst), 0.0, 100.0)
		_check(controller.state == "planning" and paused and bool(controller.last_result.get("cooked_and_eaten", false)) and str(controller.last_result.get("recipe_id", "")) == recipe_id, "a finished meal must be eaten once and return to the real kitchen planning menu")
		_check(is_equal_approx(hideout.player.health, minf(100.0, float(before.health) + float(recipe.health))) and is_equal_approx(hideout.player.stamina, minf(100.0, float(before.stamina) + float(recipe.stamina))), "hearth meal completion must grant exact catalog health and stamina with caps: " + recipe_id)
		_check(is_equal_approx(ExpeditionSession.hunger, expected_hunger) and is_equal_approx(ExpeditionSession.thirst, expected_thirst) and is_equal_approx(ExpeditionSession.stress, maxf(0.0, float(before.stress) - float(recipe.stress))), "actual eating must grant exact needs/stress effects after one survival interval: " + recipe_id)
		_check(is_equal_approx(float(controller.last_result.get("survival_seconds", -1.0)), float(recipe.survival)) and bag.slots == paid_slots and bag.equipment == equipment, "completion must clamp time and consume food directly without a stored item or extra bag slot")
		_check(controller.overlay.status_label.visible and "조리·식사 완료" in controller.overlay.status_label.text and controller.overlay.status_label.get_index() < controller.overlay.action_list.get_index(), "meal completion feedback stays visible above the recipe list")
		var completed_values := _values(hideout.player)
		controller.advance_cooking(10000.0)
		_check(_values(hideout.player) == completed_values and bag.slots == paid_slots, "a stale completion update must not repeat meal effects or inventory changes")
	_check(bag.count_item("camp_kit") == 0, "all three dishes at the existing hearth must cook without supplying or spending a camp kit")
	for item_id in _supplies():
		_check(bag.count_item(item_id) == 1, "one comparison of every recipe must leave exactly its documented spare ingredient: " + item_id)


func _test_missing_ingredient() -> void:
	var controller: Node = current_scene.cooking_controller
	controller.set_process(false)
	_set_count("edible_mushroom", 1)
	var before := _counts()
	var values := _values(current_scene.player)
	var rejected: Dictionary = controller.start_recipe("mushroom_soup")
	_check(not bool(rejected.get("accepted", false)) and controller.state == "planning" and _counts() == before and _values(current_scene.player) == values, "missing the second mushroom must reject atomically without consuming water or time")
	var button := controller.overlay.action_buttons[COOKING.action_id("mushroom_soup")] as Button
	_check(button.disabled, "the actual recipe button must show that missing ingredients block cooking")


func _test_cancelled_recipe() -> void:
	var controller: Node = current_scene.cooking_controller
	controller.set_process(false)
	_press_recipe(controller, "roast_meat")
	controller.advance_cooking(2.0)
	var spent := _counts()
	var before := _values(current_scene.player)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	current_scene._unhandled_input(escape)
	controller.advance_cooking(100.0)
	_check(controller.state == "closed" and not paused and _counts() == spent and _values(current_scene.player) == before, "closing active cooking must stop time and retain spent ingredients without any meal reward")
	controller.open_kitchen()
	_check(controller.state == "planning" and paused and _counts() == spent, "reopening after cancellation must start a fresh kitchen without refunding or resuming the interrupted dish")


func _press_recipe(controller: Node, recipe_id: String) -> void:
	var action_id := COOKING.action_id(recipe_id)
	_check(controller.overlay.action_buttons.has(action_id), "every authoritative recipe must have an actual kitchen action button: " + recipe_id)
	if not controller.overlay.action_buttons.has(action_id):
		return
	var button := controller.overlay.action_buttons[action_id] as Button
	_check(button.is_visible_in_tree() and not button.disabled, "a stocked recipe must be visible and usable in the actual kitchen: " + recipe_id)
	button.pressed.emit()


func _enter_kitchen() -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "new cooking trial must start from the actual test room")
		return false
	room = current_scene as Node3D
	room.run_feature("hideout_cooking")
	_check_supplies()
	return await _wait_for_scene(HIDEOUT_PATH)


func _return_to_room() -> bool:
	var previous_controller: Node = current_scene.cooking_controller
	var previous_player: DungeonPlayer = current_scene.player
	var needs_before := ExpeditionSession.get_survival_snapshot()
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	_check(paused, "F2 loading must immediately pause the departing hideout")
	# Force the real safe-zone update that otherwise depends on whether a
	# physics frame happens to land inside the loading interval.
	previous_player._physics_process(1.0 / 60.0)
	_check(ExpeditionSession.get_survival_snapshot() == needs_before, "the departing player must not change hunger, thirst, stress or conditions while F2 loads the test room")
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 must return to the paused test menu with the same trial inventory")
		_check(not is_instance_valid(previous_controller) and not sandbox.pending_cooking_trial, "F2 must destroy the kitchen timer and clear its one-shot trial request")
		_check(ExpeditionSession.get_survival_snapshot() == needs_before, "the complete F2 transition must preserve the exact interrupted cooking needs and conditions")
	return returned


func _supplies() -> Dictionary:
	var supplies: Dictionary = {}
	for recipe_id in COOKING.ordered_recipe_ids():
		var recipe := COOKING.get_recipe(recipe_id)
		for item_id in recipe.resources:
			supplies[item_id] = int(supplies.get(item_id, 1)) + int(recipe.resources[item_id])
	return supplies


func _check_supplies() -> void:
	for item_id in _supplies():
		_check(bag.count_item(item_id) == int(_supplies()[item_id]), "trial must supply every catalog recipe once plus one spare ingredient: " + item_id)


func _set_count(item_id: String, count: int) -> void:
	var current := bag.count_item(item_id)
	if current > count:
		bag.remove_item(item_id, current - count)
	elif current < count:
		bag.add_item(item_id, count - current)


func _counts() -> Dictionary:
	var result: Dictionary = {}
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		result[item_id] = bag.count_item(item_id)
	return result


func _values(actor: DungeonPlayer) -> Dictionary:
	return {"health": actor.health, "stamina": actor.stamina, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress}


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
	_check(false, "hearth cooking trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
