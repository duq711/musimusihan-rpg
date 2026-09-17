extends SceneTree

const SYSTEM := preload("res://scripts/alchemy_system.gd")
const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const EXPECTED := {
	"hearth_brandy": {"normal_cost": 12, "strong_cost": 14, "normal_sale": 36, "strong_sale": 120},
	"moon_absinthe": {"normal_cost": 19, "strong_cost": 21, "normal_sale": 51, "strong_sale": 168},
}
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	_test_catalog()
	_test_paid_crafting_and_resale()
	_test_continuous_supplies()
	_test_repeated_profit()
	_test_rejected_transactions()
	_test_merchant_interface()
	_test_snapshot_preservation()
	ExpeditionSession.restore_snapshot(original)
	if failures.is_empty():
		print("DISTILLATION ECONOMY TEST PASS: actual paid distillation, normal/strong profits, repeated sourcing, sale and buyback, atomic failures, merchant UI and restored session")
		quit(0)
	else:
		for failure in failures:
			push_error("DISTILLATION ECONOMY TEST FAIL: %s" % failure)
		quit(1)


func _test_catalog() -> void:
	_check(CATALOG.medicine_recipe_ids().size() == 5 and CATALOG.liquor_recipe_ids().size() == 2 and CATALOG.ordered_recipe_ids().size() == 7, "new liquor recipes must preserve all five medicines and share the canonical recipe listing")
	_check(CATALOG.ordered_recipe_ids().size() == CATALOG.RECIPES.size(), "every original recipe must be included in automatic test room registration")
	for recipe_id in CATALOG.liquor_recipe_ids():
		var recipe := CATALOG.recipe(recipe_id)
		_check(str(recipe.product_type) == "liquor" and str(recipe.finish) == "distill", "%s must declare a real distilled trade good" % recipe_id)
		for quality in ["weak", "normal", "strong"]:
			var output := str(recipe.outputs[quality])
			var definition := ExpeditionInventory.get_item_definition(output)
			_check(str(definition.get("category", "")) == "treasure" and str(definition.get("product_type", "")) == "liquor" and not definition.has("effect"), "%s must be a sale item rather than an accidental recovery consumable" % output)
			_check(str(definition.get("name", "")).begins_with(CATALOG.quality_label(recipe_id, quality)), "%s must expose the correct product quality name" % output)
			_check(FileAccess.file_exists(str(definition.get("icon_path", ""))), "%s must have an authored bottle icon" % output)
			_check(ExpeditionSession.get_sell_price(output) < int(definition.value), "%s buyback must cost more than its resale income" % output)
	_check(CATALOG.quality_label("red_mending", "strong") == "진한" and CATALOG.quality_label("hearth_brandy", "strong") == "특급", "medicine and liquor quality vocabulary must remain distinct")


func _test_paid_crafting_and_resale() -> void:
	for recipe_id in CATALOG.liquor_recipe_ids():
		for quality in ["normal", "strong"]:
			ExpeditionSession.begin_new_journey()
			var bag := ExpeditionSession.get_inventory()
			bag.slots.clear()
			var starting_crowns := ExpeditionSession.crowns
			var bottle_count := 2 if quality == "strong" else 1
			var cost := _purchase_recipe(recipe_id, bottle_count)
			_check(cost == int(EXPECTED[recipe_id][quality + "_cost"]) and ExpeditionSession.crowns == starting_crowns - cost, "%s %s must charge the authored cost including every empty bottle" % [recipe_id, quality])
			var system := SYSTEM.new().setup(bag)
			_prepare(system, recipe_id, quality == "normal")
			var before_bottling := _state()
			_check(not system.bottle().accepted and _state() == before_bottling, "unfinished liquor distillation must never mint sale goods or consume bottles")
			_finish_distillation(system)
			var result := system.bottle()
			_check(bool(result.get("accepted", false)) and str(result.get("quality", "")) == quality and int(result.get("quantity", 0)) == bottle_count, "%s must yield the actual requested %s quality through heat, herbs and stirring: %s" % [recipe_id, quality, result])
			var output := str(CATALOG.recipe(recipe_id).outputs[quality])
			_check(bag.count_item(output) == bottle_count and bag.count_item("alchemy_empty_bottle") == 0, "successful distillation must consume exactly the purchased empty bottles")
			var player := DungeonPlayer.new()
			var before_use := bag.slots.duplicate(true)
			_check(not bool(player.use_consumable(output, bag).get("accepted", false)) and bag.slots == before_use, "the inventory use action must preserve sale-only liquor")
			player.free()
			var observations: Array[Dictionary] = []
			var observer := func() -> void: observations.append(_state())
			bag.changed.connect(observer)
			var sold := ExpeditionSession.sell_item(output, bottle_count)
			bag.changed.disconnect(observer)
			var income := int(EXPECTED[recipe_id][quality + "_sale"])
			_check(bool(sold.get("accepted", false)) and int(sold.get("price", 0)) == income and ExpeditionSession.crowns == starting_crowns - cost + income, "%s %s must make positive real wallet profit after paying all materials" % [recipe_id, quality])
			_check(income > cost and bag.slots.is_empty(), "paid liquor manufacture and sale must leave profit and no duplicated ingredients")
			_check(observations.size() == 1 and observations[0] == _state(), "sale observers must see one fully committed bag, wallet and merchant stock")
			var after_sale := _state()
			_check(not ExpeditionSession.sell_item(output).accepted and _state() == after_sale, "selling the same completed bottle twice must reject atomically")
			var buyback_start := ExpeditionSession.crowns
			var bought_back := ExpeditionSession.buy_item(output)
			_check(bool(bought_back.get("accepted", false)) and int(bought_back.get("price", 0)) == int(ExpeditionInventory.get_item_definition(output).value), "the merchant must price actual liquor buyback at full catalog value")
			_check(ExpeditionSession.sell_item(output).accepted and ExpeditionSession.crowns < buyback_start, "buying and immediately reselling liquor must lose money, never create arbitrage")


func _test_continuous_supplies() -> void:
	ExpeditionSession.begin_new_journey()
	var required: Dictionary = {}
	for recipe_id in CATALOG.liquor_recipe_ids():
		required.merge(_resources(recipe_id, 2), true)
	var unlimited_ids: Array[String] = []
	for item_id in ExpeditionSession.DEFAULT_MERCHANT_STOCK:
		if ExpeditionSession.is_stock_unlimited(str(item_id)):
			unlimited_ids.append(str(item_id))
	_check(unlimited_ids.size() == required.size(), "only the exact liquor inputs and bottles may receive unlimited supply")
	for item_id in required:
		ExpeditionSession.begin_new_journey()
		var bag := ExpeditionSession.get_inventory()
		bag.slots.clear()
		ExpeditionSession.crowns = 10000
		_check(ExpeditionSession.is_stock_unlimited(str(item_id)), "%s must remain obtainable for repeatable earnings" % item_id)
		var count := int(ExpeditionSession.DEFAULT_MERCHANT_STOCK[item_id].quantity) + 1
		var stock_before := ExpeditionSession.merchant_stock.duplicate(true)
		var wallet_before := ExpeditionSession.crowns
		var observations: Array[Dictionary] = []
		var observer := func() -> void: observations.append(_state())
		bag.changed.connect(observer)
		var result := ExpeditionSession.buy_item(str(item_id), count)
		bag.changed.disconnect(observer)
		_check(bool(result.get("accepted", false)) and bag.count_item(str(item_id)) == count, "%s must support purchases beyond the old finite batch stock" % item_id)
		_check(ExpeditionSession.crowns == wallet_before - count * ExpeditionSession.get_buy_price(str(item_id)) and ExpeditionSession.merchant_stock == stock_before, "continuous supply must still charge every unit without changing any finite stock")
		_check(observations.size() == 1 and observations[0] == _state(), "unlimited purchases must notify only after committing wallet and inventory")
		_check(ExpeditionSession.get_sell_price(str(item_id)) < ExpeditionSession.get_buy_price(str(item_id)), "continuous raw materials must not allow buy/sell arbitrage")
		_check(ExpeditionSession.sell_item(str(item_id), count).accepted and ExpeditionSession.crowns < wallet_before and ExpeditionSession.merchant_stock == stock_before, "reselling unlimited raw materials must lose money and preserve stock metadata")
		(ExpeditionSession.merchant_stock[item_id] as Dictionary)["quantity"] = 0
		_check(ExpeditionSession.buy_item(str(item_id)).accepted, "unlimited supply must not depend on the finite quantity counter")
	var finite_before := ExpeditionSession.get_stock_quantity("linen_bandage")
	_check(not ExpeditionSession.is_stock_unlimited("linen_bandage") and ExpeditionSession.buy_item("linen_bandage").accepted and ExpeditionSession.get_stock_quantity("linen_bandage") == finite_before - 1, "ordinary finite merchant inventory must continue to decrease normally")
	_check(not ExpeditionSession.is_stock_unlimited("unknown_item"), "unknown items must never gain continuous supply")


func _test_repeated_profit() -> void:
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	bag.slots.clear()
	var starting_stock := ExpeditionSession.merchant_stock.duplicate(true)
	var starting_crowns := ExpeditionSession.crowns
	for batch in 40:
		var cost := _purchase_recipe("hearth_brandy", 2)
		var system := SYSTEM.new().setup(bag)
		_prepare(system, "hearth_brandy")
		_finish_distillation(system)
		var bottled := system.bottle()
		var sold := ExpeditionSession.sell_item("liquor_hearth_brandy_strong", 2)
		_check(cost == 14 and str(bottled.get("quality", "")) == "strong" and bool(sold.get("accepted", false)) and bag.slots.is_empty(), "paid batch %d must remain executable after repeated manufacture and sale" % batch)
	_check(ExpeditionSession.crowns == starting_crowns + 40 * (120 - 14), "forty real batches must earn exactly the manufactured margin beyond every initial input stock limit")
	for item_id in starting_stock:
		_check(ExpeditionSession.merchant_stock[item_id] == starting_stock[item_id], "repeated liquor production must never reset or drain unrelated finite merchant inventory")
	_check(ExpeditionSession.get_stock_quantity("liquor_hearth_brandy_strong") == 80, "only actual sold output bottles may accumulate in finite buyback stock")


func _test_rejected_transactions() -> void:
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	ExpeditionSession.crowns = 0
	_reject_buy("alchemy_wine", 1, "not_enough_crowns")
	ExpeditionSession.crowns = 10000
	for quantity in [0, -1]:
		_reject_buy("alchemy_empty_bottle", quantity, "invalid_item")
		var before := _state()
		_check(not ExpeditionSession.sell_item("alchemy_empty_bottle", quantity).accepted and _state() == before, "nonpositive liquor supply sales must preserve the complete transaction state")
	bag.slots.clear()
	bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	_reject_buy("alchemy_wine", 1, "inventory_full")
	bag.slots.clear()
	bag.add_item("alchemy_wine", 11)
	bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS - 1)
	_reject_buy("alchemy_wine", 2, "inventory_full")
	_check(ExpeditionSession.buy_item("alchemy_wine").accepted and bag.count_item("alchemy_wine") == 12 and bag.slots.size() == ExpeditionInventory.MAX_SLOTS, "a full bag may still buy unlimited input when exactly one unit fits its existing stack")
	_reject_buy("alchemy_wine", 1, "inventory_full")
	(ExpeditionSession.merchant_stock["alchemy_water"] as Dictionary)["quantity"] = 0
	_reject_buy("alchemy_water", 1, "out_of_stock")
	_reject_buy("unknown_liquor", 1, "invalid_item")


func _test_merchant_interface() -> void:
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	bag.slots.clear()
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["quantity"] = 0
	var merchant := MerchantScreen.new()
	merchant.inventory = bag
	merchant._build_fonts()
	merchant._build_interface()
	merchant._refresh_trade()
	merchant._select_stock_item("alchemy_wine")
	_check((merchant.stock_buttons.alchemy_wine as Button).text.contains("상시 공급") and not (merchant.stock_buttons.alchemy_wine as Button).disabled, "merchant stock must visibly identify continuously supplied wine even with a zero quantity counter")
	_check(not merchant.buy_button.disabled and merchant.buy_detail_label.text.contains("상시 공급"), "merchant selection must allow and explain unlimited purchases")
	var wallet_before := ExpeditionSession.crowns
	merchant._buy_selected()
	_check(bag.count_item("alchemy_wine") == 1 and ExpeditionSession.crowns == wallet_before - 5, "the actual merchant buy action must pay for and deliver wine")
	merchant._show_work()
	_check(merchant.dialogue_line_label.text.contains("증류기") and merchant.dialogue_line_label.text.contains("36") and merchant.dialogue_line_label.text.contains("51"), "merchant work guidance must explain the distillation income route")
	bag.add_item("liquor_moon_absinthe_strong")
	merchant._refresh_trade()
	merchant._select_bag_item("liquor_moon_absinthe_strong")
	_check(not merchant.sell_button.disabled and merchant.sell_detail_label.text.contains("84 크라운"), "merchant must expose the actual premium liquor resale price")
	wallet_before = ExpeditionSession.crowns
	merchant._sell_selected()
	_check(bag.count_item("liquor_moon_absinthe_strong") == 0 and ExpeditionSession.crowns == wallet_before + 84, "merchant sell action must exchange a real premium bottle for the displayed crowns")
	merchant.free()


func _test_snapshot_preservation() -> void:
	ExpeditionSession.begin_new_journey()
	var original_bag := ExpeditionSession.get_inventory()
	original_bag.add_item("liquor_hearth_brandy_normal", 3)
	ExpeditionSession.crowns = 437
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["price"] = 9
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["unlimited"] = false
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["quantity"] = 7
	var preserved_slots := original_bag.slots.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	_check(ExpeditionSession.get_inventory() != original_bag and ExpeditionSession.is_stock_unlimited("alchemy_wine"), "a separate trial journey must own its input supply flags and inventory")
	ExpeditionSession.buy_item("alchemy_wine", 3)
	ExpeditionSession.get_inventory().add_item("liquor_hearth_brandy_normal")
	ExpeditionSession.sell_item("liquor_hearth_brandy_normal")
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["price"] = 100
	_check(int(snapshot.merchant_stock.alchemy_wine.price) == 9 and not bool(snapshot.merchant_stock.alchemy_wine.unlimited), "trial supply edits must not mutate preserved stock metadata")
	ExpeditionSession.restore_snapshot(snapshot)
	_check(ExpeditionSession.get_inventory() == original_bag and original_bag.slots == preserved_slots and ExpeditionSession.crowns == 437, "returning from a trial must restore the exact original liquor bag reference and wallet")
	_check(ExpeditionSession.merchant_stock == snapshot.merchant_stock and not ExpeditionSession.is_stock_unlimited("alchemy_wine") and ExpeditionSession.get_stock_quantity("alchemy_wine") == 7 and ExpeditionSession.get_buy_price("alchemy_wine") == 9, "restoration must preserve nested finite overrides, supply flags, prices and quantities")
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["unlimited"] = true
	_check(not bool(snapshot.merchant_stock.alchemy_wine.unlimited), "restored stock metadata must not alias the saved snapshot")


func _resources(recipe_id: String, bottles: int) -> Dictionary:
	var recipe := CATALOG.recipe(recipe_id)
	var resources := {str(CATALOG.BASES[recipe.base].item_id): 1, "alchemy_empty_bottle": bottles}
	for herb in recipe.ingredients:
		resources[str(CATALOG.HERBS[herb].item_id)] = int(recipe.ingredients[herb])
	return resources


func _purchase_recipe(recipe_id: String, bottles: int) -> int:
	var cost := 0
	var resources := _resources(recipe_id, bottles)
	for item_id in resources:
		var quantity := int(resources[item_id])
		var price := ExpeditionSession.get_buy_price(str(item_id)) * quantity
		var result := ExpeditionSession.buy_item(str(item_id), quantity)
		_check(bool(result.get("accepted", false)) and int(result.get("price", 0)) == price, "%s must buy its real input %s at the current merchant price" % [recipe_id, item_id])
		cost += price
	return cost


func _prepare(system: SYSTEM, recipe_id: String, skip_stir := false) -> void:
	var recipe := CATALOG.recipe(recipe_id)
	_check(system.select_recipe(recipe_id).accepted and system.pour_base(str(recipe.base)).accepted, "liquor crafting must consume its selected real base")
	for milestone: Dictionary in recipe.milestones:
		if str(milestone.form) == "ground":
			system.add_herb(str(milestone.herb), "mortar")
			for stroke in SYSTEM.GRIND_STROKES:
				system.grind()
			system.pour_mortar()
		else:
			system.add_herb(str(milestone.herb))
	for stir in int(recipe.stirs) - (1 if skip_stir else 0):
		system.stir()
	for attempt in 5000:
		if system.boil_turns + 0.00001 >= float(recipe.boil_target):
			break
		_manage_fire(system)
		system.tick(0.05)
	_check(system.boil_turns + 0.00001 >= float(recipe.boil_target), "physical heat must reach the selected liquor's boiling milestone")
	system.set_cauldron_lowered(false)
	_check(system.start_distillation().accepted, "the selected liquor must connect to the working still")


func _finish_distillation(system: SYSTEM) -> void:
	for attempt in 5000:
		if system.distill_progress >= 1.0:
			return
		_manage_fire(system)
		system.tick(0.05)
	_check(false, "physical heat must finish liquor distillation in a bounded simulation")


func _manage_fire(system: SYSTEM) -> void:
	var point := float(system.snapshot().boiling_point)
	system.set_cauldron_lowered(system.temperature <= point + 9.0)
	if system.heat < (point - 20.0) / 1.4:
		system.pump_bellows()


func _reject_buy(item_id: String, quantity: int, reason: String) -> void:
	var before := _state()
	var result := ExpeditionSession.buy_item(item_id, quantity)
	_check(not bool(result.get("accepted", false)) and str(result.get("reason", "")) == reason, "%s purchase must reject with %s" % [item_id, reason])
	_check(_state() == before, "rejected %s must preserve wallet, all stock metadata and every bag slot" % reason)


func _state() -> Dictionary:
	return {"crowns": ExpeditionSession.crowns, "stock": ExpeditionSession.merchant_stock.duplicate(true), "slots": ExpeditionSession.get_inventory().slots.duplicate(true)}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
