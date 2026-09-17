extends SceneTree

const System := preload("res://scripts/alchemy_system.gd")
const Catalog := preload("res://scripts/alchemy_catalog.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_resource_and_mortar_rules()
	_test_heat_and_independent_hourglass()
	_test_all_recipes_and_real_use()
	_test_quality_failures_and_order()
	_test_atomic_capacity_and_repeat_finish()
	_test_catalog_and_normal_supply()
	if failures.is_empty():
		print("ALCHEMY SYSTEM TEST PASS: five medicines and two liquors, independent heat/time, grinding, order, cooling, distillation, four qualities, real consumption, atomic capacity and supplies")
		quit(0)
	else:
		for failure in failures:
			push_error("ALCHEMY SYSTEM TEST FAIL: %s" % failure)
		quit(1)


func _fixture() -> ExpeditionInventory:
	var bag := ExpeditionInventory.new()
	for id in System.trial_supplies():
		bag.add_item(str(id), int(System.trial_supplies()[id]), false)
	return bag


func _test_resource_and_mortar_rules() -> void:
	var empty := ExpeditionInventory.new()
	var missing := System.new().setup(empty)
	_check(not missing.pour_base("water").accepted and missing.stage == "empty", "absent base must reject without starting a batch")
	var bag := _fixture()
	var system := System.new().setup(bag)
	var before := bag.slots.duplicate(true)
	_check(not system.add_herb("redroot").accepted and not system.pour_base("missing").accepted and bag.slots == before, "invalid or dry actions must preserve bag")
	_check(system.pour_base("water").accepted and bag.count_item("alchemy_water") == 3, "pouring must consume exactly one actual base")
	before = bag.slots.duplicate(true)
	_check(not system.pour_base("wine").accepted and not system.select_recipe("iron_salve").accepted and bag.slots == before, "busy recipe and second base must not reset or double-charge batch")
	_check(not system.add_herb("redroot", "invalid").accepted and bag.slots == before, "invalid destination must never consume herbs")
	system.add_herb("dawnleaf", "mortar")
	system.grind()
	system.add_herb("dawnleaf", "mortar")
	_check(system.mortar.size() == 2 and system.ingredients.is_empty() and bag.count_item("alchemy_dawnleaf") == 10, "multiple handfuls consume individually while remaining in mortar")
	system.grind()
	system.grind()
	_check(str(system.mortar[0].form) == "ground" and str(system.mortar[1].form) == "bruised", "freshly added handful must not inherit earlier grinding strokes")
	system.grind()
	before = bag.slots.duplicate(true)
	_check(not system.grind().accepted and bag.slots == before, "fully ground herbs cannot farm additional strokes or costs")
	system.pour_mortar()
	_check(system.ingredients.size() == 2 and system.mortar.is_empty() and bag.slots == before, "pouring mortar transfers prepared herbs without consuming them twice")
	var copy := system.snapshot()
	copy.ingredients[0].form = "whole"
	copy.history[0].action = "corrupt"
	_check(str(system.ingredients[0].form) == "ground" and str(system.history[0].action) == "base", "UI snapshots cannot corrupt recipe history or preparation")
	system.discard()
	system.discard()
	_check(system.stage == "empty" and bag.count_item("alchemy_water") == 3 and bag.count_item("alchemy_dawnleaf") == 10, "discard is repeatable and never refunds consumed ingredients")
	_check(system.select_recipe("moon_distillate").accepted, "discard must allow recipe selection for retry")


func _test_heat_and_independent_hourglass() -> void:
	var system := System.new().setup(_fixture())
	system.pour_base("water")
	system.turn_hourglass()
	system.tick(8.0)
	_check(not system.hourglass_running and system.hourglass_remaining == 0.0 and system.boil_turns == 0.0, "hourglass must empty while cold without adding any boiling turns")
	system.turn_hourglass()
	system.tick(3.0)
	system.turn_hourglass()
	_check(is_equal_approx(system.hourglass_remaining, 8.0) and system.boil_turns == 0.0, "manual hourglass flip must restart only the independent timer")
	system.pump_bellows()
	system.pump_bellows()
	system.pump_bellows()
	system.tick(1.0)
	_check(system.temperature == 20.0 and system.boil_turns == 0.0, "fire under a raised cauldron must not heat its contents")
	system.set_cauldron_lowered(true)
	system.tick(1.0)
	_check(system.temperature > 20.0 and system.boil_turns == 0.0, "warming time below boiling must not count as recipe boiling")
	_boil_until(system, 0.6)
	_check(system.boil_turns + 0.00001 >= 0.6 and system.temperature >= 100.0, "real heat and lowering must eventually produce actual counted boiling")
	system.set_cauldron_lowered(false)
	var prior_turns := system.boil_turns
	var prior_temp := system.temperature
	var prior_heat := system.heat
	system.tick(2.0)
	_check(system.boil_turns == prior_turns and system.temperature < prior_temp and system.heat < prior_heat, "lifting must stop counted boiling while liquid and fire cool over actual time")
	var elapsed := system.elapsed
	system.tick(-10.0)
	system.tick(NAN)
	_check(system.elapsed == elapsed, "invalid deltas may not reverse or corrupt elapsed time")


func _test_all_recipes_and_real_use() -> void:
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	for id in Catalog.ordered_recipe_ids():
		var bag := _fixture()
		var system := System.new().setup(bag)
		_prepare_recipe(system, id)
		if str(Catalog.recipe(id).finish) == "distill":
			_check(not system.bottle().accepted and system.stage == "distilling", "unfinished distillation must reject instant bottling")
			var progress := system.distill_progress
			system.tick(3.0)
			_check(system.distill_progress == progress, "a raised unheated still must not collect distillate")
			_distill_until_ready(system)
		var result := system.bottle()
		_check(result.accepted and str(result.get("quality", "")) == "strong", "%s exact recipe must yield strong medicine: %s" % [id, result])
		if not result.has("item_id") or str(result.item_id).is_empty():
			continue
		var output_id := str(result.item_id)
		_check(bag.count_item(output_id) == 2 and bag.count_item("alchemy_empty_bottle") == 6, "%s strong craft must produce two actual bottles and consume two empty bottles" % id)
		if id in Catalog.liquor_recipe_ids():
			_check(ExpeditionInventory.get_item_definition(output_id).category == "treasure", "distilled liquor must be a saleable trade good")
			continue
		var player := DungeonPlayer.new()
		player.health = 20.0
		ExpeditionSession.thirst = 20.0
		ExpeditionSession.apply_condition("bleeding", 120.0)
		var use_result := player.use_consumable(output_id, bag)
		_check(bool(use_result.get("accepted", false)) and bag.count_item(output_id) == 1, "%s product must be usable and consumed through the real player inventory action" % id)
		var effect := str(ExpeditionInventory.get_item_definition(output_id).effect)
		if effect == "restore_thirst":
			_check(ExpeditionSession.thirst > 20.0, "cold tonic must actually restore player thirst")
		else:
			_check(player.health > 20.0, "%s must actually restore player health" % id)
		if effect == "bandage":
			_check(not ExpeditionSession.has_condition("bleeding"), "%s must actually stop bleeding" % id)
		player.free()
	ExpeditionSession.restore_snapshot(original)


func _test_quality_failures_and_order() -> void:
	for omitted_stirs in [0, 2]:
		var system := System.new().setup(_fixture())
		_prepare_cold(system, false, 2 - omitted_stirs)
		var result := system.bottle()
		var expected := "normal" if omitted_stirs == 0 else "weak"
		_check(str(result.get("quality", "")) == expected, "wrong preparation plus missed stirring must create %s potency, not perfect medicine: %s" % [expected, result])
	var wrong_base_bag := _fixture()
	var wrong_base := System.new().setup(wrong_base_bag)
	wrong_base.select_recipe("pilgrim_tonic")
	wrong_base.pour_base("wine")
	wrong_base.add_herb("dawnleaf", "mortar")
	_grind(wrong_base)
	wrong_base.pour_mortar()
	wrong_base.add_herb("bittermint")
	wrong_base.add_herb("bittermint")
	wrong_base.stir()
	wrong_base.stir()
	wrong_base.tick(8.0)
	var failed := wrong_base.bottle()
	_check(failed.accepted and str(failed.quality) == "failed" and int(failed.quantity) == 0, "wrong base must ruin finished batch and yield no potion")
	_check(wrong_base_bag.count_item("alchemy_wine") == 3 and wrong_base_bag.count_item("alchemy_empty_bottle") == 8, "failed medicine must retain consumed herbs/base without wasting an unused bottle")
	var wrong_order := System.new().setup(_fixture())
	wrong_order.select_recipe("pilgrim_tonic")
	wrong_order.pour_base("water")
	wrong_order.add_herb("bittermint")
	wrong_order.add_herb("bittermint")
	wrong_order.add_herb("dawnleaf", "mortar")
	_grind(wrong_order)
	wrong_order.pour_mortar()
	wrong_order.stir()
	wrong_order.stir()
	wrong_order.tick(8.0)
	_check(str(wrong_order.bottle().quality) == "failed", "correct totals in the wrong order must fail sequence-sensitive recipe")
	var skipped_boiling := System.new().setup(_fixture())
	skipped_boiling.pour_base("water")
	skipped_boiling.add_herb("redroot")
	skipped_boiling.add_herb("dawnleaf", "mortar")
	skipped_boiling.add_herb("dawnleaf", "mortar")
	_grind(skipped_boiling)
	skipped_boiling.pour_mortar()
	skipped_boiling.stir()
	skipped_boiling.turn_hourglass()
	skipped_boiling.tick(16.0)
	_check(str(skipped_boiling.bottle().quality) == "failed", "waiting with a cold hourglass must not replace actual boiling and the timed ingredient milestone")
	var wrong_finish := System.new().setup(_fixture())
	_prepare_recipe(wrong_finish, "moon_distillate", false)
	_check(str(wrong_finish.bottle().quality) == "failed", "direct bottling must fail a recipe requiring distillation")
	var burnt := System.new().setup(_fixture())
	_prepare_cold(burnt, true, 2)
	burnt.set_cauldron_lowered(true)
	for index in 80:
		burnt.pump_bellows()
		burnt.tick(1.0)
	_check(str(burnt.bottle().quality) == "failed", "sustained extreme heating and excess boiling must irreversibly ruin medicine")


func _test_atomic_capacity_and_repeat_finish() -> void:
	var bag := _fixture()
	var system := System.new().setup(bag)
	_prepare_cold(system)
	bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	var before := bag.slots.duplicate(true)
	_check(not system.bottle().accepted and bag.slots == before and system.stage == "brewing", "insufficient total capacity must preserve every slot, empty bottle and completed batch")
	bag.remove_item("rusted_sword")
	var result := system.bottle()
	_check(result.accepted and str(result.quality) == "strong", "freeing capacity must allow the held finished batch to complete")
	before = bag.slots.duplicate(true)
	_check(not system.bottle().accepted and bag.slots == before, "repeating completion must never duplicate or charge another potion")
	_check(system.select_recipe("red_mending").accepted, "finished batch must permit a new recipe without requiring destructive bag changes")
	bag = _fixture()
	system = System.new().setup(bag)
	_prepare_cold(system)
	bag.remove_item("alchemy_empty_bottle", 7)
	before = bag.slots.duplicate(true)
	_check(not system.bottle().accepted and bag.slots == before, "strong output requires two actual empty bottles and cannot partially consume one")
	bag.add_item("alchemy_empty_bottle")
	bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	_check(system.bottle().accepted, "fully consumed bottle stack must free its slot for potion output in an otherwise full bag")
	var reentrant_bag := _fixture()
	var reentrant_system := System.new().setup(reentrant_bag)
	_prepare_cold(reentrant_system)
	var reentrant_results: Array[Dictionary] = []
	var listener := func() -> void:
		if reentrant_results.is_empty():
			reentrant_results.append({})
			reentrant_results[0] = reentrant_system.bottle()
	reentrant_bag.changed.connect(listener)
	_check(reentrant_system.bottle().accepted and reentrant_bag.count_item("alchemy_pilgrim_tonic_strong") == 2, "inventory notification listeners may not duplicate completed potions by reentering bottle")
	_check(reentrant_results.size() == 1 and not bool(reentrant_results[0].accepted), "completion state must be finalized before emitting inventory changed")
	reentrant_bag.changed.disconnect(listener)


func _test_catalog_and_normal_supply() -> void:
	_check(Catalog.medicine_recipe_ids().size() == 5 and Catalog.liquor_recipe_ids().size() == 2 and Catalog.ordered_recipe_ids().size() == 7 and Catalog.BASES.size() == 4, "production catalog must expose five original medicines, two liquors and four distinct bases")
	for id in System.trial_supplies():
		_check(ExpeditionInventory.ITEM_DEFINITIONS.has(id), "%s supply must belong to canonical inventory catalog" % id)
		_check(ExpeditionSession.DEFAULT_MERCHANT_STOCK.has(id), "%s supply must be obtainable at normal merchant" % id)
	for id in Catalog.ordered_recipe_ids():
		var recipe := Catalog.recipe(id)
		for output in recipe.outputs.values():
			_check(ExpeditionInventory.ITEM_DEFINITIONS.has(output), "%s quality variant must be discoverable automatically by test room item catalog" % output)
		var price := int(ExpeditionSession.DEFAULT_MERCHANT_STOCK[str(Catalog.BASES[recipe.base].item_id)].price)
		for herb in recipe.ingredients:
			price += int(recipe.ingredients[herb]) * int(ExpeditionSession.DEFAULT_MERCHANT_STOCK[str(Catalog.HERBS[herb].item_id)].price)
		price += 2 * int(ExpeditionSession.DEFAULT_MERCHANT_STOCK.alchemy_empty_bottle.price)
		_check(price <= ExpeditionSession.STARTING_CROWNS, "%s must be affordable with the starting wallet" % id)


func _prepare_cold(system: System, correct_form := true, stirs := 2) -> void:
	system.select_recipe("pilgrim_tonic")
	system.pour_base("water")
	if correct_form:
		system.add_herb("dawnleaf", "mortar")
		_grind(system)
		system.pour_mortar()
	else:
		system.add_herb("dawnleaf")
	system.add_herb("bittermint")
	system.add_herb("bittermint")
	for index in stirs:
		system.stir()
	system.turn_hourglass()
	system.tick(8.0)


func _prepare_recipe(system: System, id: String, attach_still := true) -> void:
	system.select_recipe(id)
	var recipe := Catalog.recipe(id)
	system.pour_base(str(recipe.base))
	for milestone: Dictionary in recipe.milestones:
		_boil_until(system, float(milestone.boil_before))
		system.set_cauldron_lowered(false)
		if milestone.has("max_temp"):
			_cool_to(system, float(milestone.max_temp))
		if str(milestone.form) == "ground":
			system.add_herb(str(milestone.herb), "mortar")
			_grind(system)
			system.pour_mortar()
		else:
			system.add_herb(str(milestone.herb))
	for index in int(recipe.stirs):
		system.stir()
	_boil_until(system, float(recipe.boil_target))
	system.set_cauldron_lowered(false)
	if recipe.has("steep_seconds"):
		system.tick(float(recipe.steep_seconds))
	if recipe.has("finish_max_temp"):
		_cool_to(system, float(recipe.finish_max_temp))
	if str(recipe.finish) == "distill" and attach_still:
		system.start_distillation()


func _grind(system: System) -> void:
	for index in System.GRIND_STROKES:
		system.grind()


func _boil_until(system: System, target_turns: float) -> void:
	for attempt in 5000:
		if system.boil_turns + 0.00001 >= target_turns:
			return
		_manage_fire(system)
		system.tick(0.05)
	_check(false, "bounded heat simulation must reach %.1f actual boiling turns" % target_turns)


func _distill_until_ready(system: System) -> void:
	for attempt in 5000:
		if system.distill_progress >= 1.0:
			return
		_manage_fire(system)
		system.tick(0.05)
	_check(false, "heated still must finish within bounded physical simulation")


func _manage_fire(system: System) -> void:
	var point := float(system.snapshot().boiling_point)
	if system.temperature > point + 9.0:
		system.set_cauldron_lowered(false)
	else:
		system.set_cauldron_lowered(true)
	if system.heat < (point - 20.0) / 1.4:
		system.pump_bellows()


func _cool_to(system: System, target: float) -> void:
	system.set_cauldron_lowered(false)
	for attempt in 1000:
		if system.temperature <= target:
			return
		system.tick(0.05)
	_check(false, "raised cauldron must cool to requested temperature")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
