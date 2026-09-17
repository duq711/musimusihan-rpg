extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const MERCHANT_PATH := "res://merchant.tscn"
const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const SYSTEM := preload("res://scripts/alchemy_system.gd")
const TRIALS := {"distilling_brandy": "hearth_brandy", "distilling_absinthe": "moon_absinthe"}
const STRONG_COSTS := {"hearth_brandy": 14, "moon_absinthe": 21}
const STRONG_SALES := {"hearth_brandy": 120, "moon_absinthe": 168}
const NORMAL_COSTS := {"hearth_brandy": 12, "moon_absinthe": 19}
const NORMAL_SALES := {"hearth_brandy": 36, "moon_absinthe": 51}
var failures: Array[String] = []
var sandbox: Node
var room: Node3D
var bag: ExpeditionInventory
var original_signals: Array[int] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("alchemy_wine", 3)
	original.add_item("alchemy_moonwort", 4)
	original.add_item("liquor_hearth_brandy_normal", 1)
	ExpeditionSession.crowns = 487
	ExpeditionSession.hunger = 53.0
	ExpeditionSession.thirst = 27.0
	ExpeditionSession.stress = 38.0
	ExpeditionSession.apply_condition("bleeding", 75.0)
	ExpeditionSession.merchant_stock.alchemy_wine.quantity = 7
	ExpeditionSession.merchant_stock.alchemy_wine["delivery_record"] = {"order": {"remaining": 5}}
	var observer := func() -> void: original_signals.append(original.count_item("alchemy_wine"))
	original.changed.connect(observer)
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	bag = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "liquor trials must run in a paused, separately owned test expedition")
	_test_catalog()
	while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
		bag.add_item("rusted_sword", 1, false)
	room.run_feature("distilling_brandy")
	_check("교체" in room.status_label.text and bag.slots.size() <= ExpeditionInventory.MAX_SLOTS - 3, "a full trial bag must disclose replacements and reserve real result space")
	_check_supplies()
	if await _wait_for_scene(HIDEOUT_PATH):
		_check_trial_overlay("hearth_brandy")
		await _test_close_resume_and_cancel()
	for trial_id: String in TRIALS:
		if await _enter_trial(trial_id, str(TRIALS[trial_id])):
			var recipe_id := str(TRIALS[trial_id])
			var output_id := _brew_and_check(recipe_id)
			if not output_id.is_empty() and await _travel_to_merchant():
				_test_sale_and_buyback(output_id, recipe_id)
				_test_paid_reagent_purchase(recipe_id)
			await _return_to_room()
	_check(original.slots == original_slots and original.equipment == original_equipment and original_signals.is_empty(), "manufacture, paid purchases, sales and repeated scene visits must never mutate or signal the original bag")
	_check(sandbox.saved_session == snapshot, "test-session trading must preserve the saved wallet, material stock and nested merchant data")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		var previous_bag := bag
		room.reset_room()
		bag = room.inventory
		_check(bag != previous_bag and bag != original and sandbox.saved_session == snapshot, "reset must replace only the trial inventory while preserving the original expedition")
		_check(sandbox.pending_alchemy_trial.is_empty(), "reset must clear the one-shot distillery route")
		if await _enter_trial("alchemy_recipe:hearth_brandy", "hearth_brandy"):
			_brew_and_check("hearth_brandy")
			await _return_to_room()
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and original.changed.is_connected(observer), "leaving must restore the original inventory identity and existing signal connections")
	_check(ExpeditionSession.capture_snapshot() == snapshot and original.slots == original_slots and original.equipment == original_equipment, "leaving must restore original crowns, liquor/material stacks, equipment, stock, needs, stress and conditions exactly")
	ExpeditionSession.merchant_stock.alchemy_wine.delivery_record.order.remaining = 99
	_check(int(snapshot.merchant_stock.alchemy_wine.delivery_record.order.remaining) == 5, "restored merchant metadata must be deeply copied from the preserved snapshot")
	ExpeditionSession.restore_snapshot(snapshot)
	_check(sandbox.pending_alchemy_trial.is_empty(), "exiting must not leave a distilling request behind")
	original.changed.disconnect(observer)
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("DISTILLATION TEST ROOM PASS: manual production buttons, both real liquor recipes, required hot distillation, two bottles, merchant sale/buyback and paid supplies, full bag, close/resume, repeated F2, reset and deep original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_catalog() -> void:
	for trial_id: String in TRIALS:
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == trial_id)
		_check(matches.size() == 1 and matches[0].category == "장면" and matches[0].action == "distilling" and matches[0].payload == TRIALS[trial_id], "each distillery sale trial must execute its real recipe: " + trial_id)
		var recipe_id := str(TRIALS[trial_id])
		var recipes: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "alchemy_recipe:" + recipe_id)
		_check(recipes.size() == 1 and recipes[0].action == "distilling" and recipes[0].payload == recipe_id, "liquor recipes must also remain automatically registered from AlchemyCatalog: " + recipe_id)
		for item_id: String in CATALOG.recipe(recipe_id).outputs.values():
			var items: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "item:" + item_id)
			_check(items.size() == 1 and items[0].action == "item", "all liquor qualities must auto-register from the item catalog: " + item_id)
			var stocked := false
			for chest in room.loot_chests:
				for stack in chest.container.items:
					stocked = stocked or (str(stack.id) == item_id and int(stack.quantity) > 0)
			_check(stocked, "source-catalog supply chests must offer each actual liquor item: " + item_id)


func _check_supplies() -> void:
	for item_id: String in SYSTEM.trial_supplies():
		_check(bag.count_item(item_id) == int(SYSTEM.trial_supplies()[item_id]), "distilling entry must replenish exact source-catalog materials: " + item_id)


func _enter_trial(trial_id: String, recipe_id: String) -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "a distillery trial must start from the real test room")
		return false
	room = current_scene as Node3D
	room.run_feature(trial_id)
	_check_supplies()
	if not await _wait_for_scene(HIDEOUT_PATH):
		return false
	_check_trial_overlay(recipe_id)
	return true


func _check_trial_overlay(recipe_id: String) -> void:
	var overlay: CanvasLayer = current_scene.alchemy_overlay
	_check(is_instance_valid(overlay) and overlay.is_open() and overlay.inventory_model == bag and overlay.system._bag == bag, "distillery trial must open the actual alchemy workbench with the sandbox bag")
	_check(str(overlay.system.snapshot().recipe_id) == recipe_id and sandbox.pending_alchemy_trial.is_empty(), "hideout must consume the requested liquor recipe exactly once")
	_check(paused and not current_scene.world_root.visible and not current_scene.player.visible, "distilling must pause the real hideout and its duplicate world view")
	_check("판매" in overlay.recipe_text.text and "크라운" in overlay.recipe_text.text, "the live liquor recipe must explain real sale income and monetary costs")
	var before_selection := bag.slots.duplicate(true)
	(overlay.product_buttons.medicine as Button).pressed.emit()
	_check(overlay.recipe_picker.item_count == CATALOG.medicine_recipe_ids().size(), "medicine mode must preserve its original recipes separately from liquor")
	(overlay.product_buttons.liquor as Button).pressed.emit()
	_check(overlay.recipe_picker.item_count == CATALOG.liquor_recipe_ids().size(), "the real liquor mode button must expose the two production recipes")
	for index in overlay.recipe_picker.item_count:
		if str(overlay.recipe_picker.get_item_metadata(index)) == recipe_id:
			overlay.recipe_picker.select(index)
			overlay.recipe_picker.item_selected.emit(index)
	_check(str(overlay.system.snapshot().recipe_id) == recipe_id and bag.slots == before_selection, "choosing the real liquor recipe must select its instructions without consuming ingredients")
	_test_economy_quote(overlay, recipe_id)
	overlay.set_process(false)


func _test_economy_quote(overlay: CanvasLayer, recipe_id: String) -> void:
	var economy: Dictionary = overlay.recipe_economy(recipe_id)
	_check(economy.normal == {"quantity": 1, "cost": int(NORMAL_COSTS[recipe_id]), "revenue": int(NORMAL_SALES[recipe_id]), "profit": int(NORMAL_SALES[recipe_id]) - int(NORMAL_COSTS[recipe_id])}, "the recipe must quote exact normal bottle cost, merchant revenue and profit")
	_check(economy.strong == {"quantity": 2, "cost": int(STRONG_COSTS[recipe_id]), "revenue": int(STRONG_SALES[recipe_id]), "profit": int(STRONG_SALES[recipe_id]) - int(STRONG_COSTS[recipe_id])}, "the recipe must quote exact strong two-bottle cost, merchant revenue and profit")
	var base_item := str(CATALOG.BASES[str(CATALOG.recipe(recipe_id).base)].item_id)
	var original_price := int(ExpeditionSession.merchant_stock[base_item].price)
	ExpeditionSession.merchant_stock[base_item].price = original_price + 7
	var changed_quote: Dictionary = overlay.recipe_economy(recipe_id)
	for quality in ["normal", "strong"]:
		_check(int(changed_quote[quality].cost) == int(economy[quality].cost) + 7 and int(changed_quote[quality].profit) == int(economy[quality].profit) - 7, "economic quotes must derive from the actual session merchant prices")
	ExpeditionSession.merchant_stock[base_item].price = original_price
	overlay._refresh()


func _test_close_resume_and_cancel() -> void:
	var hideout: Node = current_scene
	var overlay: CanvasLayer = hideout.alchemy_overlay
	_click_base(overlay, "wine")
	_select_herb(overlay, "redroot")
	_click(overlay, "add_to_mortar")
	_click(overlay, "grind")
	_click(overlay, "turn_hourglass")
	var batch: Dictionary = overlay.system.snapshot()
	var spent_slots := bag.slots.duplicate(true)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	overlay._input(escape)
	overlay._process(3.0)
	await process_frame
	_check(not overlay.is_open() and not paused and overlay.system.snapshot() == batch and bag.slots == spent_slots, "Esc must close and freeze the real liquid, mortar and hourglass without changing the bag")
	hideout._open_alchemy()
	_check(overlay.is_open() and overlay.system.snapshot() == batch, "reopening the same workbench must resume the exact unfinished liquor batch")
	await _return_to_room()
	_check(bag.slots == spent_slots, "F2 cancellation must discard unfinished liquor without refunding spent ingredients")


func _brew_and_check(recipe_id: String) -> String:
	var overlay: CanvasLayer = current_scene.alchemy_overlay
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	var base_item := str(CATALOG.BASES[str(recipe.base)].item_id)
	var base_before := bag.count_item(base_item)
	var bottles_before := bag.count_item(SYSTEM.BOTTLE_ITEM)
	var crowns_before := ExpeditionSession.crowns
	var herbs_before: Dictionary = {}
	for herb_id: String in recipe.ingredients:
		var item_id := str(CATALOG.HERBS[herb_id].item_id)
		herbs_before[item_id] = bag.count_item(item_id)
	var output_id := str(recipe.outputs.strong)
	var output_before := bag.count_item(output_id)
	_brew(overlay, recipe_id)
	var result: Dictionary = overlay.system.snapshot().last_result
	_check(str(result.get("quality", "")) == "strong" and str(result.get("item_id", "")) == output_id and int(result.get("quantity", 0)) == 2, "following actual recipe controls must yield two strong sale bottles: " + recipe_id + " / " + str(result.get("mistakes", [])))
	_check(bag.count_item(output_id) == output_before + 2 and bag.count_item(base_item) == base_before - 1 and bag.count_item(SYSTEM.BOTTLE_ITEM) == bottles_before - 2, "production must commit its actual two bottles and consume one base plus two containers")
	for herb_id: String in recipe.ingredients:
		var item_id := str(CATALOG.HERBS[herb_id].item_id)
		_check(bag.count_item(item_id) == int(herbs_before[item_id]) - int(recipe.ingredients[herb_id]), "distilling must consume the exact herb recipe: " + item_id)
	_check(ExpeditionSession.crowns == crowns_before and bag.count_sellable_item(output_id) == bag.count_item(output_id), "distillation produces normal saleable inventory goods and awards no crowns until trade")
	_check("중개인 판매액" in overlay.journal_label.text and str(STRONG_SALES[recipe_id]) in overlay.journal_label.text and "거래" in overlay.journal_label.text, "the actual completion journal must show the total sale amount and route to merchant trading")
	var completed_slots := bag.slots.duplicate(true)
	var again: Dictionary = overlay.perform_action("bottle")
	_check(not bool(again.get("accepted", false)) and bag.slots == completed_slots and ExpeditionSession.crowns == crowns_before, "a completed batch cannot be bottled twice")
	return output_id if str(result.get("quality", "")) == "strong" else ""


func _brew(overlay: CanvasLayer, recipe_id: String) -> void:
	# Only real recipe/tool buttons and elapsed time are used. No grade, heat,
	# ingredient, progress, output or wallet state is fabricated by this test.
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	_click_base(overlay, str(recipe.base))
	_check(overlay.recipe_picker.disabled and (overlay.product_buttons.medicine as Button).disabled and (overlay.product_buttons.liquor as Button).disabled, "a started liquor batch must lock both recipe and product-mode selection")
	var locked_slots := bag.slots.duplicate(true)
	var switch_result: Dictionary = overlay.select_product_type("medicine")
	_check(not bool(switch_result.get("accepted", false)) and str(overlay.system.snapshot().recipe_id) == recipe_id and bag.slots == locked_slots, "blocked mode selection must not discard or replace a live liquor batch")
	var milestones: Array = recipe.milestones
	var index := 0
	while index < milestones.size():
		var step: Dictionary = milestones[index]
		_heat_to_turns(overlay, float(step.boil_before))
		_click(overlay, "raise_cauldron")
		if step.has("max_temp"):
			_cool_to(overlay, float(step.max_temp))
		_select_herb(overlay, str(step.herb))
		if step.form == "ground":
			var herb := str(step.herb)
			while index < milestones.size() and milestones[index].herb == herb and milestones[index].form == "ground":
				_click(overlay, "add_to_mortar")
				index += 1
			for stroke in range(3):
				_click(overlay, "grind")
			_click(overlay, "pour_mortar")
		else:
			_click(overlay, "add_whole")
			index += 1
	for stir in range(int(recipe.stirs)):
		_click(overlay, "stir")
	_heat_to_turns(overlay, float(recipe.boil_target))
	_click(overlay, "raise_cauldron")
	var before_distill := bag.slots.duplicate(true)
	var bypass: Dictionary = overlay.perform_action("bottle")
	_check(not bool(bypass.get("accepted", false)) and bag.slots == before_distill and str(overlay.system.snapshot().stage) == "brewing", "liquor must reject direct bottling before real distillation")
	_click(overlay, "start_distillation")
	overlay.system.tick(1.0)
	_check(float(overlay.system.snapshot().distill_progress) == 0.0, "an elevated cauldron must not collect spirits merely because time passes")
	var premature: Dictionary = overlay.perform_action("bottle")
	_check(not bool(premature.get("accepted", false)) and bag.slots == before_distill, "unfinished distillation must preserve bottles and award no sale goods")
	_click(overlay, "lower_cauldron")
	for tick_index in range(5000):
		if float(overlay.system.snapshot().distill_progress) >= 1.0:
			break
		_advance_heating(overlay)
	_check(float(overlay.system.snapshot().distill_progress) >= 1.0, "actual boiling must complete the requested distillation duration")
	_click(overlay, "bottle")


func _heat_to_turns(overlay: CanvasLayer, turns: float) -> void:
	if float(overlay.system.snapshot().boil_turns) >= turns:
		return
	_click(overlay, "lower_cauldron")
	for tick_index in range(10000):
		if float(overlay.system.snapshot().boil_turns) >= turns:
			return
		_advance_heating(overlay)
	_check(false, "actual fire controls did not reach the recipe boiling time")


func _advance_heating(overlay: CanvasLayer) -> void:
	var state: Dictionary = overlay.system.snapshot()
	var boiling_point := float(state.boiling_point)
	if bool(state.cauldron_lowered) and float(state.temperature) >= boiling_point + 10.0:
		_click(overlay, "raise_cauldron")
	elif not bool(state.cauldron_lowered) and float(state.temperature) <= boiling_point + 2.0:
		_click(overlay, "lower_cauldron")
	if float(state.heat) < (boiling_point - 20.0) / 1.4 + 3.0:
		_click(overlay, "pump_bellows")
	overlay.system.tick(0.05)


func _cool_to(overlay: CanvasLayer, temperature: float) -> void:
	for tick_index in range(5000):
		if float(overlay.system.snapshot().temperature) <= temperature:
			return
		overlay.system.tick(0.05)
	_check(false, "raised cauldron did not cool to the recipe temperature")


func _click(overlay: CanvasLayer, action: String) -> void:
	overlay._refresh()
	var button := overlay.action_buttons[action] as Button
	_check(not button.disabled, "real workbench button must be available: " + action)
	if not button.disabled:
		button.pressed.emit()


func _click_base(overlay: CanvasLayer, base_id: String) -> void:
	var button := overlay.base_buttons[base_id] as Button
	_check(not button.disabled, "real base bottle must be selectable: " + base_id)
	if not button.disabled:
		button.pressed.emit()


func _select_herb(overlay: CanvasLayer, herb_id: String) -> void:
	for index in overlay.herb_picker.item_count:
		if str(overlay.herb_picker.get_item_metadata(index)) == herb_id:
			overlay.herb_picker.select(index)
			overlay.herb_picker.item_selected.emit(index)
			return
	_check(false, "actual herb picker must expose the recipe ingredient: " + herb_id)


func _travel_to_merchant() -> bool:
	var hideout: Node = current_scene
	var old_overlay: CanvasLayer = hideout.alchemy_overlay
	old_overlay.close()
	hideout._travel_to_destination(MERCHANT_PATH)
	if not await _wait_for_scene(MERCHANT_PATH):
		return false
	_check(not is_instance_valid(old_overlay) and current_scene.inventory == bag and ExpeditionSession.get_inventory() == bag, "normal hideout travel must carry actual manufactured goods to the merchant and release the workbench")
	current_scene.trade_option_button.pressed.emit()
	_check(current_scene.trade_panel.visible, "the ordinary dialogue choice must open real merchant trading")
	return true


func _test_sale_and_buyback(item_id: String, recipe_id: String) -> void:
	var merchant: Control = current_scene
	var before_quantity := bag.count_item(item_id)
	var before_crowns := ExpeditionSession.crowns
	var before_stock := ExpeditionSession.get_stock_quantity(item_id)
	var sell_price := ExpeditionSession.get_sell_price(item_id)
	_check(sell_price * 2 == int(STRONG_SALES[recipe_id]), "two strong bottles must have the configured premium sale value")
	_check(merchant.bag_buttons.has(item_id), "actual manufactured liquor must appear in the merchant's sale list")
	if not merchant.bag_buttons.has(item_id):
		return
	(merchant.bag_buttons[item_id] as Button).pressed.emit()
	_check(not merchant.sell_button.disabled and str(sell_price) in merchant.sell_detail_label.text, "selecting manufactured liquor must show its real per-bottle sale price")
	for unit in range(before_quantity):
		merchant.sell_button.pressed.emit()
		_check(bag.count_item(item_id) == before_quantity - unit - 1 and ExpeditionSession.crowns == before_crowns + sell_price * (unit + 1), "each sale button press must remove and pay for exactly one actual bottle")
	_check(ExpeditionSession.get_stock_quantity(item_id) == before_stock + before_quantity and "판매했습니다" in merchant.trade_status_label.text, "merchant sale must update stock and visible confirmation")
	var after_sale := ExpeditionSession.capture_snapshot()
	merchant.sell_button.pressed.emit()
	_check(ExpeditionSession.capture_snapshot() == after_sale and bag.count_item(item_id) == 0, "repeated sale input after the final bottle must not duplicate crowns")
	(merchant.stock_buttons[item_id] as Button).pressed.emit()
	var buy_price := ExpeditionSession.get_buy_price(item_id)
	var crowns_before_buyback := ExpeditionSession.crowns
	merchant.buy_button.pressed.emit()
	_check(bag.count_item(item_id) == 1 and ExpeditionSession.crowns == crowns_before_buyback - buy_price, "buying back a sold bottle must consume the actual listed price")
	(merchant.bag_buttons[item_id] as Button).pressed.emit()
	merchant.sell_button.pressed.emit()
	_check(bag.count_item(item_id) == 0 and buy_price >= sell_price and ExpeditionSession.crowns == crowns_before_buyback - buy_price + sell_price, "buyback and immediate resale must not create free profit")


func _test_paid_reagent_purchase(recipe_id: String) -> void:
	var merchant: Control = current_scene
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	var costs := {str(CATALOG.BASES[str(recipe.base)].item_id): 1, SYSTEM.BOTTLE_ITEM: 2}
	for herb_id: String in recipe.ingredients:
		costs[str(CATALOG.HERBS[herb_id].item_id)] = int(recipe.ingredients[herb_id])
	var crowns_before := ExpeditionSession.crowns
	var paid := 0
	for item_id: String in costs:
		var quantity := int(costs[item_id])
		var before := bag.count_item(item_id)
		_check(merchant.stock_buttons.has(item_id), "repeatable liquor materials must appear in the merchant UI: " + item_id)
		if not merchant.stock_buttons.has(item_id):
			continue
		(merchant.stock_buttons[item_id] as Button).pressed.emit()
		for unit in range(quantity):
			var price := ExpeditionSession.get_buy_price(item_id)
			_check(not merchant.buy_button.disabled, "a distilling raw material must remain purchasable")
			merchant.buy_button.pressed.emit()
			paid += price
		_check(bag.count_item(item_id) == before + quantity and ExpeditionSession.get_stock_quantity(item_id) > 0, "paid materials must enter the real bag and remain available for the next batch: " + item_id)
	_check(paid == int(STRONG_COSTS[recipe_id]) and ExpeditionSession.crowns == crowns_before - paid, "buying every ingredient plus two empty bottles must cost the documented strong-batch price")


func _return_to_room() -> bool:
	var old_overlay: CanvasLayer
	var previous_player: DungeonPlayer
	var needs_before := ExpeditionSession.get_survival_snapshot()
	if current_scene.scene_file_path == HIDEOUT_PATH:
		old_overlay = current_scene.alchemy_overlay
		previous_player = current_scene.player
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	_check(paused, "F2 loading must pause the departing distillery or merchant scene")
	if is_instance_valid(previous_player):
		# Exercise the actual safe-zone tick during loading without relying on
		# the scheduler to place a physics frame before scene replacement.
		previous_player._physics_process(1.0 / 60.0)
		_check(ExpeditionSession.get_survival_snapshot() == needs_before, "the departing distiller must not change hunger, thirst, stress or conditions during F2 loading")
	if is_instance_valid(old_overlay):
		_check(not old_overlay.is_open() and str(old_overlay.system.snapshot().stage) == "empty", "F2 must immediately clear the real liquor batch before freeing its hideout")
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag and sandbox.pending_alchemy_trial.is_empty(), "F2 from either workbench or merchant must return to the paused test menu with the same isolated bag")
		_check(ExpeditionSession.get_survival_snapshot() == needs_before, "the complete F2 transition must preserve exact distilling-session needs and conditions")
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
	_check(false, "distillery scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
