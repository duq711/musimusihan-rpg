extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const SYSTEM := preload("res://scripts/alchemy_system.gd")
const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const TRIALS := {
	"alchemy_brewing": "ember_cordial", "alchemy_grinding": "red_mending",
	"alchemy_distillation": "moon_distillate", "alchemy_quality": "iron_salve",
}
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
	original.add_item("alchemy_wine", 3)
	original.add_item("alchemy_moonwort", 4)
	ExpeditionSession.crowns = 487
	ExpeditionSession.hunger = 53.0
	ExpeditionSession.thirst = 27.0
	ExpeditionSession.stress = 38.0
	ExpeditionSession.apply_condition("bleeding", 75.0)
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	bag = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "alchemy must begin inside the paused isolated test session")
	_test_catalog()
	_check(not sandbox.prepare_alchemy_trial("missing_recipe") and sandbox.pending_alchemy_trial.is_empty(), "invalid recipe routes must not leak a one-shot request")
	while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
		bag.add_item("rusted_sword", 1, false)
	room.run_feature("alchemy_grinding")
	_check("교체" in room.status_label.text and bag.slots.size() <= ExpeditionInventory.MAX_SLOTS - 3, "full-bag alchemy fixture must disclose replacements and reserve actual result space")
	_check_supplies()
	if await _wait_for_scene(HIDEOUT_PATH):
		await _test_workbench_interaction()
		await _test_close_resume()
		_test_brew_and_consume("red_mending")
		await _return_to_room()
	for trial in ["alchemy_brewing", "alchemy_distillation", "alchemy_quality", "alchemy_recipe:pilgrim_tonic"]:
		if await _enter_trial(trial):
			var recipe_id: String = str(TRIALS.get(trial, "pilgrim_tonic"))
			_test_brew_and_consume(recipe_id)
			if trial == "alchemy_quality":
				_test_quality_comparison()
			await _return_to_room()
	# A second actual visit starts a fresh batch; F2 must discard it without
	# refunding reagents and without ever changing the original inventory.
	if await _enter_trial("alchemy_grinding"):
		var overlay: CanvasLayer = current_scene.alchemy_overlay
		_act(overlay, "pour_base", "water")
		_act(overlay, "add_herb", {"herb_id": "redroot", "destination": "mortar"})
		_act(overlay, "grind")
		var spent_water := bag.count_item("alchemy_water")
		var spent_root := bag.count_item("alchemy_redroot")
		await _return_to_room()
		_check(bag.count_item("alchemy_water") == spent_water and bag.count_item("alchemy_redroot") == spent_root, "F2 must discard unfinished liquid and mortar work without refunding consumed reagents")
	_check(original.slots == original_slots and original.equipment == original_equipment and sandbox.saved_session == snapshot, "all physical recipe actions and repeated visits must leave the original expedition untouched")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		var previous_bag := bag
		room.reset_room()
		bag = room.inventory
		_check(bag != previous_bag and bag != original and sandbox.saved_session == snapshot, "reset must replace only the trial bag and preserve the original snapshot")
		_check(sandbox.pending_alchemy_trial.is_empty(), "reset must clear the one-shot alchemy route")
		if await _enter_trial("alchemy_recipe:pilgrim_tonic"):
			_test_brew_and_consume("pilgrim_tonic")
			await _return_to_room()
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "leaving alchemy trials must restore original inventory identity and its signals")
	_check(ExpeditionSession.capture_snapshot() == snapshot and original.slots == original_slots, "leaving must restore original money, materials, equipment, needs, stress and condition durations exactly")
	_check(sandbox.pending_alchemy_trial.is_empty(), "finished trial session must not retain an alchemy request")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("ALCHEMY TEST ROOM PASS: actual bench interaction, all five manual recipes and consumables, clock suspension, source-catalog supply, full-bag retries, F2 discard, reset and original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_catalog() -> void:
	for trial_id in TRIALS:
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == trial_id)
		_check(matches.size() == 1 and matches[0].action == "alchemy" and matches[0].payload == TRIALS[trial_id], "each alchemy technique must enter the actual hideout recipe: " + trial_id)
	for recipe_id in CATALOG.ordered_recipe_ids():
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "alchemy_recipe:" + recipe_id)
		_check(matches.size() == 1 and matches[0].action == ("distilling" if recipe_id in CATALOG.liquor_recipe_ids() else "alchemy") and matches[0].payload == recipe_id, "every source-catalog recipe must auto-register an executable trial: " + recipe_id)
	for item_id in SYSTEM.trial_supplies():
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:" + item_id)
		_check(matches.size() == 1 and matches[0].action == "item", "each alchemy reagent must appear once through the original item catalog: " + item_id)
		var stocked := false
		for chest in room.loot_chests:
			for stack in chest.container.items:
				stocked = stocked or (str(stack.id) == item_id and int(stack.quantity) > 0)
		_check(stocked, "automatic test supplies must contain each real alchemy reagent: " + item_id)


func _check_supplies() -> void:
	for item_id in SYSTEM.trial_supplies():
		_check(bag.count_item(item_id) == int(SYSTEM.trial_supplies()[item_id]), "re-entering must restock exact source-catalog alchemy supplies: " + item_id)


func _enter_trial(trial_id: String) -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "cannot select a new recipe without returning to the real test room")
		return false
	room = current_scene as Node3D
	room.run_feature(trial_id)
	_check_supplies()
	return await _wait_for_scene(HIDEOUT_PATH)


func _test_workbench_interaction() -> void:
	var hideout: Node = current_scene
	var overlay: CanvasLayer = hideout.alchemy_overlay
	_check(is_instance_valid(overlay) and overlay.is_open() and overlay.inventory_model == bag and overlay.system._bag == bag, "alchemy trial must open the production UI with only the sandbox inventory")
	_check(sandbox.pending_alchemy_trial.is_empty() and not is_instance_valid(hideout.blacksmith_overlay), "the actual hideout must consume alchemy routing once without opening the smith")
	_check(not hideout.world_root.visible and not hideout.player.visible and paused, "alchemy must pause shelter gameplay and hide its duplicate world and carried equipment rendering")
	overlay.close()
	_check(not paused and hideout.world_root.visible and hideout.player.visible, "closing alchemy must restore real hideout play and visibility")
	var actor: DungeonPlayer = hideout.player
	actor.set_physics_process(false)
	var bench := hideout.find_child("AlchemyBenchInteraction", true, false) as HideoutInteractable
	_check(bench != null and bench.action_id == "alchemy" and is_instance_valid(hideout.alchemy_world), "the new physical bench must expose an actual alchemy interaction")
	if bench == null:
		return
	await physics_frame
	await physics_frame
	var query := PhysicsRayQueryParameters3D.create(actor.camera.global_position, bench.global_position + bench.interaction_offset, DungeonPlayer.WORLD_LAYER | DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider.get_meta("interaction_owner", null) == bench, "normal approach must hit the alchemy bench before a wall, smith interaction or obstructing prop")
	bench.interact(actor)
	_check(actor.timed_interaction_owner == bench and not overlay.is_open(), "using the alchemy bench must begin the real timed interaction")
	actor.advance_timed_interaction(0.35)
	_check(overlay.is_open() and paused and hideout.alchemy_overlay == overlay, "completing normal E interaction must reopen the same production alchemy overlay")


func _test_close_resume() -> void:
	var hideout: Node = current_scene
	var overlay: CanvasLayer = hideout.alchemy_overlay
	overlay.set_process(false)
	_act(overlay, "pour_base", "water")
	_act(overlay, "add_herb", {"herb_id": "redroot", "destination": "cauldron"})
	_act(overlay, "turn_hourglass")
	var batch: Dictionary = overlay.system.snapshot()
	var supplies_before := bag.slots.duplicate(true)
	overlay.close()
	overlay._process(3.0)
	await process_frame
	_check(overlay.system.snapshot() == batch and bag.slots == supplies_before, "closed bench must freeze the real batch, hourglass and ingredients")
	hideout._open_alchemy()
	_check(overlay.is_open() and overlay.system.snapshot() == batch and overlay.inventory_model == bag and overlay.system._bag == bag, "reopening must preserve the exact unfinished batch without spending a second base")
	_act(overlay, "discard")
	_check(bag.slots == supplies_before, "explicit discard must clear a batch without refunding already used reagents")


func _test_brew_and_consume(recipe_id: String) -> void:
	var hideout: Node = current_scene
	var overlay: CanvasLayer = hideout.alchemy_overlay
	overlay.set_process(false)
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	var outcome := _brew(overlay, recipe_id)
	var output_id := str(outcome.get("item_id", ""))
	_check(str(outcome.get("quality", "")) == "strong", "following all actual recipe controls must yield strong quality: " + recipe_id + " / " + str(outcome.get("mistakes", [])))
	_check(output_id in recipe.outputs.values() and bag.count_item(output_id) > 0, "actual manual recipe must place its own finished bottle in the inventory: " + recipe_id)
	if output_id.is_empty():
		return
	var before_quantity := bag.count_item(output_id)
	hideout.player.health = 30.0
	ExpeditionSession.thirst = 20.0
	ExpeditionSession.stress = 70.0
	ExpeditionSession.apply_condition("bleeding", 120.0)
	var result: Dictionary = hideout.player.use_consumable(output_id, bag)
	_check(bool(result.get("accepted", false)) and bag.count_item(output_id) == before_quantity - 1, "finished bottle must use the ordinary inventory consumable path exactly once: " + recipe_id)
	_check(hideout.player.health > 30.0 or ExpeditionSession.thirst > 20.0 or ExpeditionSession.stress < 70.0 or not ExpeditionSession.active_conditions.has("bleeding"), "manufactured bottle must cause a real recovery effect: " + recipe_id)


func _test_quality_comparison() -> void:
	var overlay: CanvasLayer = current_scene.alchemy_overlay
	var strong_id := str(CATALOG.recipe("iron_salve").outputs.strong)
	var normal_id := str(CATALOG.recipe("iron_salve").outputs.normal)
	var strong_left := bag.count_item(strong_id)
	var normal_before := bag.count_item(normal_id)
	var imperfect := _brew(overlay, "iron_salve", true)
	_check(str(imperfect.get("quality", "")) == "normal" and str(imperfect.get("item_id", "")) == normal_id, "quality experiment must create a genuinely weaker bottle when both flowers are only partially ground")
	_check(not (imperfect.get("mistakes", []) as Array).is_empty() and bag.count_item(normal_id) == normal_before + 1 and bag.count_item(strong_id) == strong_left, "quality differences must be explained in the real manufacture log and preserved as distinct actual inventory results")


func _brew(overlay: CanvasLayer, recipe_id: String, incomplete_grinding := false) -> Dictionary:
	# The test operates only production actions and elapsed time. It never
	# writes quality, ingredients, boil counters or completion state directly.
	overlay.select_recipe(recipe_id)
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	_act(overlay, "pour_base", recipe.base)
	var milestones: Array = recipe.milestones
	var index := 0
	while index < milestones.size():
		var step: Dictionary = milestones[index]
		_heat_to_turns(overlay, float(step.boil_before))
		_act(overlay, "set_cauldron_lowered", false)
		if step.has("max_temp"):
			_cool_to(overlay, float(step.max_temp))
		if step.form == "ground":
			var herb := str(step.herb)
			while index < milestones.size() and milestones[index].herb == herb and milestones[index].form == "ground":
				_act(overlay, "add_herb", {"herb_id": herb, "destination": "mortar"})
				index += 1
			for stroke in range(2 if incomplete_grinding else 3):
				_act(overlay, "grind")
			_act(overlay, "pour_mortar")
		else:
			_act(overlay, "add_herb", {"herb_id": str(step.herb), "destination": "cauldron"})
			index += 1
	for stir in range(int(recipe.stirs)):
		_act(overlay, "stir")
	_heat_to_turns(overlay, float(recipe.boil_target))
	_act(overlay, "set_cauldron_lowered", false)
	if recipe.finish == "distill":
		_act(overlay, "start_distillation")
		_act(overlay, "set_cauldron_lowered", true)
		for tick_index in range(5000):
			var state: Dictionary = overlay.system.snapshot()
			if float(state.get("distill_progress", 0.0)) >= 1.0:
				break
			_advance_heating(overlay)
	else:
		_cool_to(overlay, float(recipe.finish_max_temp))
		if recipe.has("steep_seconds"):
			overlay.system.tick(float(recipe.steep_seconds) + 0.1)
	return _act(overlay, "bottle")


func _heat_to_turns(overlay: CanvasLayer, turns: float) -> void:
	if float(overlay.system.snapshot().get("boil_turns", 0.0)) >= turns:
		return
	_act(overlay, "set_cauldron_lowered", true)
	for tick_index in range(10000):
		if float(overlay.system.snapshot().get("boil_turns", 0.0)) >= turns:
			return
		_advance_heating(overlay)
	_check(false, "actual heated batch did not reach requested boiling time")


func _advance_heating(overlay: CanvasLayer) -> void:
	var state: Dictionary = overlay.system.snapshot()
	var boiling_point := float(state.boiling_point)
	# Operate the same two manual thermal controls as a player. Raising the
	# cauldron briefly prevents scorching while the fire remains alive.
	if bool(state.cauldron_lowered) and float(state.temperature) >= boiling_point + 10.0:
		_act(overlay, "set_cauldron_lowered", false)
	elif not bool(state.cauldron_lowered) and float(state.temperature) <= boiling_point + 2.0:
		_act(overlay, "set_cauldron_lowered", true)
	if float(state.heat) < (boiling_point - 20.0) / 1.4 + 3.0:
		_act(overlay, "pump_bellows")
	overlay.system.tick(0.05)


func _cool_to(overlay: CanvasLayer, temperature: float) -> void:
	for tick_index in range(5000):
		if float(overlay.system.snapshot().get("temperature", 20.0)) <= temperature:
			return
		overlay.system.tick(0.05)
	_check(false, "raised cauldron did not cool to the recipe temperature")


func _act(overlay: CanvasLayer, action: String, payload: Variant = null) -> Dictionary:
	var result: Dictionary = overlay.perform_action(action, payload)
	_check(bool(result.get("accepted", false)), "real alchemy action must succeed: " + action + " / " + str(result.get("message", "missing_result")))
	return result


func _return_to_room() -> bool:
	var old_overlay: CanvasLayer = current_scene.alchemy_overlay
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	_check(not old_overlay.is_open() and old_overlay.system.stage == "empty", "F2 transition must immediately stop the UI and clear its liquid, heat, mortar and timer state before freeing the scene")
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 from alchemy must return to the paused test menu with the same trial inventory")
		_check(not is_instance_valid(old_overlay) and sandbox.pending_alchemy_trial.is_empty(), "F2 must destroy local batch/UI state and clear recipe routing")
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
	_check(false, "alchemy trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
