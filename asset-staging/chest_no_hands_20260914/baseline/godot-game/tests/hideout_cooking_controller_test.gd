extends SceneTree

const CONTROLLER := preload("res://scripts/hideout_cooking_controller.gd")
const OVERLAY := preload("res://scripts/hideout_cooking_overlay.gd")
const COOKING := preload("res://scripts/camp_cooking_catalog.gd")

class FixtureGame:
	extends Node3D
	var brazier_lit := true

class FixturePlayer:
	extends DungeonPlayer
	func _ready() -> void:
		set_physics_process(false)
	func _refresh_survival_hud() -> void:
		pass

class FixtureVisual:
	extends Node3D
	var recipe_id := ""
	var progress := 0.0
	var active := false
	func set_cooking(id: String, value: float, enabled: bool) -> void:
		recipe_id = id
		progress = value
		active = enabled

class RejectingIngredient:
	extends ExpeditionInventory
	func remove_item(id: String, quantity := 1, notify := true) -> bool:
		if id == "boiled_rainwater":
			return false
		return super.remove_item(id, quantity, notify)

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	_test_every_recipe(false)
	_test_every_recipe(true)
	_test_failures_and_atomic_payment()
	_test_reentrant_callbacks()
	_test_cancel_fire_death_and_rebind()
	await _test_small_overlay()
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original, "controller tests restore the exact original expedition")
	paused = false
	if failures.is_empty():
		print("HIDEOUT COOKING CONTROLLER PASS: catalog recipes, atomic ingredients, paused-time cooking/eating, caps, reentrancy, fire/death/cancellation, listener cleanup and responsive recipe UI")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT COOKING CONTROLLER FAIL: " + failure)
		quit(1)


func _fixture(bag: ExpeditionInventory = null) -> Dictionary:
	paused = false
	ExpeditionSession.begin_new_journey()
	var inventory := bag if bag != null else ExpeditionSession.get_inventory()
	inventory.slots.clear()
	for recipe_id: String in COOKING.ordered_recipe_ids():
		for item_id: String in COOKING.get_recipe(recipe_id).resources:
			if inventory.count_item(item_id) == 0:
				inventory.add_item(item_id, 5, false)
	var world := FixtureGame.new()
	root.add_child(world)
	var player := FixturePlayer.new()
	player.safe_zone_mode = true
	player.health = 25.0
	player.stamina = 20.0
	world.add_child(player)
	ExpeditionSession.hunger = 25.0
	ExpeditionSession.thirst = 25.0
	ExpeditionSession.stress = 80.0
	var visual := FixtureVisual.new()
	world.add_child(visual)
	var kitchen := CONTROLLER.new()
	kitchen.setup(world, player, inventory, visual)
	world.add_child(kitchen)
	kitchen.set_process(false)
	kitchen.opened.connect(func() -> void: paused = true)
	kitchen.closed.connect(func(_reason: String, restore_controls: bool) -> void:
		if restore_controls:
			paused = false)
	return {"world": world, "player": player, "bag": inventory, "visual": visual, "kitchen": kitchen}


func _cleanup(fixture: Dictionary) -> void:
	fixture.kitchen.close_kitchen("", false)
	fixture.world.free()
	paused = false


func _test_every_recipe(capped: bool) -> void:
	for recipe_id: String in COOKING.ordered_recipe_ids():
		var f := _fixture()
		var kitchen: Node = f.kitchen
		var bag: ExpeditionInventory = f.bag
		var player: DungeonPlayer = f.player
		var recipe := COOKING.get_recipe(recipe_id)
		if capped:
			player.health = 98.0
			player.stamina = 98.0
			ExpeditionSession.hunger = 98.0
			ExpeditionSession.thirst = 98.0
			ExpeditionSession.stress = 2.0
		var before := _values(player)
		var slots := bag.slots.duplicate(true)
		var equipment := bag.equipment.duplicate(true)
		var completions: Array[Dictionary] = []
		kitchen.cooking_finished.connect(func(result: Dictionary) -> void: completions.append(result))
		_check(bool(kitchen.open_kitchen().accepted) and paused and bag.slots == slots and _values(player) == before, "opening preserves all ingredients and player/session values")
		var snapshot: Dictionary = kitchen.get_snapshot()
		_check(snapshot.actions.size() == COOKING.ordered_recipe_ids().size() and not snapshot.inventory_counts.has("camp_kit"), "menu derives recipe and ingredient rows from the original catalog")
		_check(kitchen.overlay.selected_category == "cooking" and not kitchen.overlay.category_tabs.visible and kitchen.overlay.title_label.text.contains("화롯불"), "actual UI opens directly to hideout recipes")
		for action: Dictionary in snapshot.actions:
			_check(not action.resources.has("camp_kit") and not str(action.cost).contains("온기") and str(action.ingredient_text).contains(" / "), "ingredient cards show actual owned/required quantities with no camp payment")
		kitchen.overlay._on_action_pressed(COOKING.action_id(recipe_id))
		_check(kitchen.state == "cooking" and paused and player.safe_zone_mode and bool(f.visual.active), "actual recipe button begins cooking while hideout world remains paused and safe")
		_check(kitchen.get_snapshot().state == "resting" and kitchen.get_snapshot().kitchen_state == "cooking", "overlay adapter preserves explicit kitchen state")
		for item_id: String in recipe.resources:
			_check(bag.count_item(item_id) == 5 - int(recipe.resources[item_id]), "start removes precisely the catalog ingredient quantity")
		var paid := bag.slots.duplicate(true)
		_check(not bool(kitchen.start_recipe(recipe_id).accepted) and bag.slots == paid, "repeated start cannot spend another serving")
		kitchen.advance_cooking(NAN)
		kitchen.advance_cooking(INF)
		kitchen.advance_cooking(-2.0)
		_check(kitchen.cooking_elapsed == 0.0 and _values(player) == before, "invalid and negative deltas cannot change cooking or survival")
		kitchen.advance_cooking(float(recipe.duration) * 0.5)
		_check(player.health == before.health and player.stamina == before.stamina and ExpeditionSession.stress == before.stress and completions.is_empty(), "unfinished food grants no health, stamina or stress recovery")
		_check(is_equal_approx(f.visual.progress, 0.5) and kitchen.overlay.progress_bar.visible and is_equal_approx(kitchen.overlay.progress_bar.value, 0.5), "recipe clock drives actual progress bar and visual")
		_check(ExpeditionSession.hunger < before.hunger and ExpeditionSession.thirst < before.thirst, "paused-world recipe manually advances survival before eating")
		kitchen.advance_cooking(10000.0)
		_check(kitchen.state == "planning" and paused and completions.size() == 1 and not f.visual.active and kitchen.last_result.cooked_and_eaten, "completion eats once and returns to paused menu")
		var expected_hunger := minf(100.0, float(before.hunger) - float(recipe.survival) * 100.0 / ExpeditionSession.HUNGER_FULL_DURATION_SECONDS + float(recipe.hunger))
		var expected_thirst := minf(100.0, float(before.thirst) - float(recipe.survival) * 100.0 / ExpeditionSession.THIRST_FULL_DURATION_SECONDS + float(recipe.thirst))
		_check(is_equal_approx(player.health, minf(DungeonPlayer.MAX_HEALTH, float(before.health) + float(recipe.health))) and is_equal_approx(player.stamina, minf(100.0, float(before.stamina) + float(recipe.stamina))), "food applies authored health/stamina effects and caps")
		_check(is_equal_approx(ExpeditionSession.hunger, expected_hunger) and is_equal_approx(ExpeditionSession.thirst, expected_thirst) and is_equal_approx(ExpeditionSession.stress, maxf(0.0, float(before.stress) - float(recipe.stress))), "food applies exact need drain/recovery and stress relief")
		_check(is_equal_approx(float(kitchen.last_result.survival_seconds), float(recipe.survival)) and kitchen.last_result.resources_spent == recipe.resources, "result records exact recipe time and spent ingredients")
		var completed := _values(player)
		kitchen.advance_cooking(999.0)
		_check(_values(player) == completed and completions.size() == 1 and bag.slots == paid and bag.equipment == equipment, "stale updates cannot duplicate food or store an extra dish")
		_cleanup(f)


func _test_failures_and_atomic_payment() -> void:
	for mode: String in ["missing", "late_reject", "invalid", "full", "thirst_only", "dead", "fire"]:
		var f := _fixture(RejectingIngredient.new() if mode == "late_reject" else null)
		f.kitchen.open_kitchen()
		var recipe_id := "trail_stew"
		if mode == "missing":
			f.bag.remove_item("boiled_rainwater", 5, false)
		elif mode == "invalid":
			recipe_id = "unknown"
		elif mode in ["full", "thirst_only"]:
			f.player.health = DungeonPlayer.MAX_HEALTH
			f.player.stamina = 100.0
			ExpeditionSession.hunger = 100.0
			ExpeditionSession.thirst = 25.0 if mode == "thirst_only" else 100.0
			ExpeditionSession.stress = 0.0
			recipe_id = "roast_meat"
		elif mode == "dead":
			f.player.health = 0.0
		elif mode == "fire":
			f.world.brazier_lit = false
		var slots: Array = f.bag.slots.duplicate(true)
		var values := _values(f.player)
		var notices: Array[bool] = []
		f.bag.changed.connect(func() -> void: notices.append(true))
		var result: Dictionary = f.kitchen.start_recipe(recipe_id)
		_check(not result.accepted and f.kitchen.state == "planning" and f.bag.slots == slots and notices.is_empty() and _values(f.player) == values, "invalid start or failed late ingredient leaves exact state untouched: " + mode)
		_cleanup(f)
	var f := _fixture()
	f.world.brazier_lit = false
	_check(f.kitchen.open_kitchen().reason == "fire_unlit" and f.kitchen.state == "closed", "unlit hearth refuses opening without consuming anything")
	_cleanup(f)


func _test_reentrant_callbacks() -> void:
	var f := _fixture()
	f.kitchen.open_kitchen()
	var repeats: Array[Dictionary] = []
	var listener := func() -> void: repeats.append(f.kitchen.start_recipe("trail_stew"))
	f.bag.changed.connect(listener)
	f.kitchen.start_recipe("trail_stew")
	_check(repeats.size() == 1 and not repeats[0].accepted and f.bag.count_item("raw_meat") == 4, "inventory listeners cannot recursively spend recipe resources")
	f.bag.changed.disconnect(listener)
	var completions: Array[Dictionary] = []
	f.kitchen.cooking_finished.connect(func(result: Dictionary) -> void:
		completions.append(result)
		f.kitchen.advance_cooking(100.0))
	f.kitchen.advance_cooking(100.0)
	_check(completions.size() == 1 and f.player.health == 60.0, "completion observer cannot recursively award the dish")
	_cleanup(f)
	f = _fixture()
	f.kitchen.open_kitchen()
	f.bag.changed.connect(func() -> void: f.kitchen.close_kitchen("시험 중단"), CONNECT_ONE_SHOT)
	var before := _values(f.player)
	var started: Dictionary = f.kitchen.start_recipe("trail_stew")
	f.kitchen.advance_cooking(100.0)
	_check(started.accepted and started.interrupted and f.kitchen.state == "closed" and f.kitchen.last_result.cancelled and _values(f.player) == before and f.bag.count_item("raw_meat") == 4, "inventory observer cancellation retains payment but grants no recovery")
	_cleanup(f)


func _test_cancel_fire_death_and_rebind() -> void:
	for mode: String in ["button", "fire", "death", "departure", "rebind", "exit"]:
		var f := _fixture()
		f.kitchen.open_kitchen()
		f.kitchen.start_recipe("trail_stew")
		f.kitchen.advance_cooking(1.0)
		var before := _values(f.player)
		var original_bag: ExpeditionInventory = f.bag
		if mode == "button":
			f.kitchen.overlay.leave_button.pressed.emit()
		elif mode == "fire":
			f.world.brazier_lit = false
		elif mode == "death":
			f.player.combat_state = DungeonPlayer.CombatState.DEAD
		elif mode == "departure":
			f.player.safe_zone_mode = false
		elif mode == "rebind":
			var replacement := ExpeditionInventory.new()
			f.kitchen.setup(f.world, f.player, replacement, f.visual)
			_check(not original_bag.changed.is_connected(f.kitchen.refresh) and replacement.changed.is_connected(f.kitchen.refresh), "rebinding disconnects original bag and attaches only the replacement")
		elif mode == "exit":
			f.world.remove_child(f.kitchen)
			_check(not original_bag.changed.is_connected(f.kitchen.refresh), "exiting disconnects inventory listeners")
		f.kitchen.advance_cooking(100.0)
		_check(f.kitchen.state == "closed" and not f.visual.active and _values(f.player) == before and original_bag.count_item("raw_meat") == 4, "cancel/departure/death/exit grants no later effects or refunds: " + mode)
		if mode == "exit":
			f.kitchen.free()
			f.world.free()
			paused = false
		else:
			_cleanup(f)


func _test_small_overlay() -> void:
	var f := _fixture()
	f.kitchen.open_kitchen()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	var overlay := OVERLAY.new()
	viewport.add_child(overlay)
	overlay.set_snapshot(f.kitchen.get_snapshot())
	overlay.show_camp()
	for frame in 3:
		await process_frame
	_check(overlay.panel_root.get_rect().end.x <= 640 and overlay.panel_root.get_rect().end.y <= 360 and overlay.leave_button.get_global_rect().end.y <= 360, "small cooking panel keeps close button inside viewport")
	_check(overlay.action_scroll.get_v_scroll_bar().max_value > overlay.action_scroll.size.y and overlay.action_buttons.size() == COOKING.ordered_recipe_ids().size(), "small cooking UI scrolls through every original recipe")
	viewport.free()
	_cleanup(f)


func _values(player: DungeonPlayer) -> Dictionary:
	return {"health": player.health, "stamina": player.stamina, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
