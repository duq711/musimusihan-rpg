extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(ExpeditionSession.journey_started, "a new journey must be marked active")
	_check(ExpeditionSession.crowns == ExpeditionSession.STARTING_CROWNS, "a new journey must receive the starting wallet")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == 8, "merchant stock must reset to its authored quantity")
	_check(inventory.count_item("linen_bandage") == 1, "the default loadout must remain intact")

	var starting_crowns := ExpeditionSession.crowns
	var starting_stock := ExpeditionSession.get_stock_quantity("linen_bandage")
	var starting_count := inventory.count_item("linen_bandage")
	var buy_observations: Array[Dictionary] = []
	var buy_observer := func() -> void:
		buy_observations.append(_snapshot(inventory, "linen_bandage"))
	inventory.changed.connect(buy_observer)
	var buy_result := ExpeditionSession.buy_item("linen_bandage")
	inventory.changed.disconnect(buy_observer)
	_check(bool(buy_result.get("accepted", false)), "an affordable in-stock item must be purchasable")
	_check(ExpeditionSession.crowns == starting_crowns - ExpeditionSession.get_buy_price("linen_bandage"), "a purchase must deduct the exact listed price")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == starting_stock - 1, "a purchase must reduce merchant stock")
	_check(inventory.count_item("linen_bandage") == starting_count + 1, "a purchase must enter the shared expedition bag")
	_check(buy_observations.size() == 1 and buy_observations[0] == _snapshot(inventory, "linen_bandage"), "purchase observers must receive exactly one fully committed wallet-stock-bag state")

	var before_sale_crowns := ExpeditionSession.crowns
	var sell_observations: Array[Dictionary] = []
	var sell_observer := func() -> void:
		sell_observations.append(_snapshot(inventory, "linen_bandage"))
	inventory.changed.connect(sell_observer)
	var sell_result := ExpeditionSession.sell_item("linen_bandage")
	inventory.changed.disconnect(sell_observer)
	_check(bool(sell_result.get("accepted", false)), "an owned bag item must be sellable")
	_check(ExpeditionSession.crowns == before_sale_crowns + ExpeditionSession.get_sell_price("linen_bandage"), "a sale must add the exact resale price")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == starting_stock, "a sale must return the item to merchant stock")
	_check(inventory.count_item("linen_bandage") == starting_count, "a sale must remove one item from the bag")
	_check(sell_observations.size() == 1 and sell_observations[0] == _snapshot(inventory, "linen_bandage"), "sale observers must receive exactly one fully committed wallet-stock-bag state")

	var loot_crowns := ExpeditionSession.crowns
	inventory.add_item("black_salt", 1)
	var loot_sale := ExpeditionSession.sell_item("black_salt")
	_check(bool(loot_sale.get("accepted", false)), "dungeon loot that was not in the initial catalog must still be sellable")
	_check(ExpeditionSession.merchant_stock.has("black_salt") and ExpeditionSession.get_stock_quantity("black_salt") == 1, "selling new loot must create a merchant stock entry")
	_check(ExpeditionSession.crowns == loot_crowns + ExpeditionSession.get_sell_price("black_salt"), "loot sales must pay the resale value")

	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	ExpeditionSession.crowns = 0
	_check_rejected_buy_is_atomic(inventory, "healing_draught", "not_enough_crowns")

	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	(ExpeditionSession.merchant_stock["healing_draught"] as Dictionary)["quantity"] = 0
	_check_rejected_buy_is_atomic(inventory, "healing_draught", "out_of_stock")

	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	inventory.slots.clear()
	_check(inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS) == 0, "capacity fixture must fill every bag slot")
	_check_rejected_buy_is_atomic(inventory, "grave_key", "inventory_full")

	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	var sell_snapshot := _snapshot(inventory, "black_salt")
	var missing_sale := ExpeditionSession.sell_item("black_salt")
	_check(not bool(missing_sale.get("accepted", false)) and str(missing_sale.get("reason", "")) == "not_owned", "an unowned item sale must be rejected")
	_check(_snapshot(inventory, "black_salt") == sell_snapshot, "a rejected sale must not mutate wallet, stock, or bag")
	var invalid_snapshot := _snapshot(inventory, "unknown_relic")
	var invalid_buy := ExpeditionSession.buy_item("unknown_relic")
	var invalid_sale := ExpeditionSession.sell_item("unknown_relic")
	_check(not bool(invalid_buy.get("accepted", false)) and not bool(invalid_sale.get("accepted", false)), "unknown items must be rejected by both transaction directions")
	_check(_snapshot(inventory, "unknown_relic") == invalid_snapshot, "invalid transactions must be atomic")

	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 1
	ExpeditionSession.crowns = 1
	ExpeditionSession.begin_new_journey()
	_check(ExpeditionSession.crowns == ExpeditionSession.STARTING_CROWNS and ExpeditionSession.get_stock_quantity("linen_bandage") == 8, "a new journey must deep-reset wallet and merchant stock")

	_test_archery_transactions()
	_test_flail_transactions()
	_test_camp_kit_transactions()
	_test_smithing_trade_protection()
	_finish()


func _test_archery_transactions() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(ExpeditionSession.get_stock_quantity("hunting_bow") == 1 and ExpeditionSession.get_stock_quantity("wooden_arrow") == 60, "merchant reset must supply one bow and sixty arrows")
	var crowns_before := ExpeditionSession.crowns
	var bought_bow := ExpeditionSession.buy_item("hunting_bow")
	_check(bool(bought_bow.get("accepted", false)) and inventory.count_item("hunting_bow") == 2, "a purchased bow must join the starter bow in the bag")
	_check(ExpeditionSession.crowns == crowns_before - 38 and ExpeditionSession.get_stock_quantity("hunting_bow") == 0, "bow purchase must commit the authored price and stock")
	_check_rejected_buy_is_atomic(inventory, "hunting_bow", "out_of_stock")
	var observations: Array[Dictionary] = []
	var observer := func() -> void:
		observations.append(_snapshot(inventory, "wooden_arrow"))
	inventory.changed.connect(observer)
	var bought_arrows := ExpeditionSession.buy_item("wooden_arrow", 31)
	inventory.changed.disconnect(observer)
	_check(bool(bought_arrows.get("accepted", false)) and int(bought_arrows.get("price", 0)) == 62, "arrow purchases must support exact multi-stack quantities at two crowns each")
	_check(inventory.count_item("wooden_arrow") == 43 and ExpeditionSession.get_stock_quantity("wooden_arrow") == 29, "purchased arrows must merge with starter ammunition without loss")
	_check(observations.size() == 1 and observations[0] == _snapshot(inventory, "wooden_arrow"), "arrow purchase observers must see one fully committed transaction")
	var arrows_before_sale := inventory.count_item("wooden_arrow")
	crowns_before = ExpeditionSession.crowns
	var sold_arrows := ExpeditionSession.sell_item("wooden_arrow", 30)
	_check(bool(sold_arrows.get("accepted", false)) and inventory.count_item("wooden_arrow") == arrows_before_sale - 30, "selling arrows must remove exactly the selected quantity across stacks")
	_check(ExpeditionSession.crowns == crowns_before + 30 * ExpeditionSession.get_sell_price("wooden_arrow") and ExpeditionSession.get_stock_quantity("wooden_arrow") == 59, "arrow sales must pay per-unit resale and return stock")
	var sale_snapshot := _snapshot(inventory, "wooden_arrow")
	var rejected_sale := ExpeditionSession.sell_item("wooden_arrow", 14)
	_check(not bool(rejected_sale.get("accepted", false)) and _snapshot(inventory, "wooden_arrow") == sale_snapshot, "selling more arrows than owned must preserve ammunition, wallet, and stock")

	# Selling a packed bow does not sell its ammunition or the currently equipped
	# bow. Equipment still has to be deliberately unequipped before resale.
	var bow_index := -1
	for index in inventory.slots.size():
		if str(inventory.slots[index].get("id", "")) == "hunting_bow":
			bow_index = index
			break
	_check(bool(inventory.equip_from_slot(bow_index).get("accepted", false)), "bought bows must use normal equipment swaps")
	var ammo_before := inventory.count_item("wooden_arrow")
	_check(bool(ExpeditionSession.sell_item("hunting_bow").get("accepted", false)), "the spare packed bow must be sellable")
	var equipped_snapshot := _snapshot(inventory, "hunting_bow")
	var equipped_sale := ExpeditionSession.sell_item("hunting_bow")
	_check(not bool(equipped_sale.get("accepted", false)) and _snapshot(inventory, "hunting_bow") == equipped_snapshot, "an equipped bow must not be removed by bag-only sales")
	_check(str(inventory.equipment.get("weapon", "")) == "hunting_bow" and inventory.count_item("wooden_arrow") == ammo_before, "bow resale must preserve equipped weapon and independent ammunition")
	_check(bool(inventory.unequip("weapon").get("accepted", false)) and bool(ExpeditionSession.sell_item("hunting_bow").get("accepted", false)), "an unequipped bow must become sellable through the same transaction")
	_check(inventory.count_item("wooden_arrow") == ammo_before, "selling the last bow must not discard its arrows")

	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	inventory.slots.clear()
	inventory.add_item("wooden_arrow", 29)
	inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS - 1)
	_check(bool(ExpeditionSession.buy_item("wooden_arrow").get("accepted", false)) and inventory.count_item("wooden_arrow") == 30, "a full bag must allow an arrow purchase that fits its existing stack")
	_check_rejected_buy_is_atomic(inventory, "wooden_arrow", "inventory_full")
	ExpeditionSession.begin_new_journey()
	_check(ExpeditionSession.get_stock_quantity("wooden_arrow") == 60 and ExpeditionSession.get_inventory().count_item("wooden_arrow") == 12, "new journey reset must restore stock and only starter ammunition")


func _test_flail_transactions() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(ExpeditionSession.get_stock_quantity("chain_flail") == 1 and ExpeditionSession.get_buy_price("chain_flail") == 64, "merchant must stock one flail at sixty-four crowns")
	var before := ExpeditionSession.crowns
	var observations: Array[Dictionary] = []
	var observer := func() -> void: observations.append(_snapshot(inventory, "chain_flail"))
	inventory.changed.connect(observer)
	var bought := ExpeditionSession.buy_item("chain_flail")
	inventory.changed.disconnect(observer)
	_check(bool(bought.get("accepted", false)) and inventory.count_item("chain_flail") == 2, "bought flail must join the starter flail")
	_check(ExpeditionSession.crowns == before - 64 and ExpeditionSession.get_stock_quantity("chain_flail") == 0, "flail purchase must atomically commit authored price and stock")
	_check(observations.size() == 1 and observations[0] == _snapshot(inventory, "chain_flail"), "flail purchase observers must see only the committed transaction")
	_check_rejected_buy_is_atomic(inventory, "chain_flail", "out_of_stock")
	var index := -1
	for slot in inventory.slots.size():
		if str(inventory.slots[slot].id) == "chain_flail":
			index = slot
			break
	_check(bool(inventory.equip_from_slot(index).get("accepted", false)), "purchased flail must equip normally")
	before = ExpeditionSession.crowns
	_check(bool(ExpeditionSession.sell_item("chain_flail").get("accepted", false)), "spare packed flail must be sellable")
	_check(ExpeditionSession.crowns == before + ExpeditionSession.get_sell_price("chain_flail") and ExpeditionSession.get_stock_quantity("chain_flail") == 1, "flail sale must pay the catalog resale price and replenish stock")
	var equipped_snapshot := _snapshot(inventory, "chain_flail")
	_check(not bool(ExpeditionSession.sell_item("chain_flail").get("accepted", false)) and _snapshot(inventory, "chain_flail") == equipped_snapshot, "bag-only sale must not remove the equipped flail")
	_check(str(inventory.equipment.weapon) == "chain_flail" and inventory.count_item("wooden_arrow") == 12, "flail transactions must preserve equipped weapon and starter ammunition")
	_check(bool(inventory.unequip("weapon").get("accepted", false)) and bool(ExpeditionSession.sell_item("chain_flail").get("accepted", false)), "unequipped flail must become sellable")
	ExpeditionSession.begin_new_journey()
	_check(ExpeditionSession.get_stock_quantity("chain_flail") == 1 and ExpeditionSession.get_inventory().count_item("chain_flail") == 1, "new journey must reset flail merchant stock and starter supply independently")
	ExpeditionSession.crowns = 63
	_check_rejected_buy_is_atomic(ExpeditionSession.get_inventory(), "chain_flail", "not_enough_crowns")
	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	inventory.slots.clear()
	inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	_check_rejected_buy_is_atomic(inventory, "chain_flail", "inventory_full")


func _test_camp_kit_transactions() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	_check(ExpeditionSession.get_stock_quantity("camp_kit") == 4 and ExpeditionSession.get_buy_price("camp_kit") == 18, "merchant must stock four camp kits at eighteen crowns")
	var crowns_before := ExpeditionSession.crowns
	var bought := ExpeditionSession.buy_item("camp_kit", 3)
	_check(bool(bought.get("accepted", false)) and inventory.count_item("camp_kit") == 4, "purchased camp kits must join the starter kit across stacks")
	_check(ExpeditionSession.crowns == crowns_before - 54 and ExpeditionSession.get_stock_quantity("camp_kit") == 1, "camp kit purchase must commit exact price and stock")
	crowns_before = ExpeditionSession.crowns
	_check(bool(ExpeditionSession.sell_item("camp_kit", 2).get("accepted", false)), "packed camp kits must be sellable through the standard transaction")
	_check(inventory.count_item("camp_kit") == 2 and ExpeditionSession.get_stock_quantity("camp_kit") == 3 and ExpeditionSession.crowns == crowns_before + 2 * ExpeditionSession.get_sell_price("camp_kit"), "kit resale must preserve quantity and pay per-unit value")
	var before := _snapshot(inventory, "camp_kit")
	_check(not bool(ExpeditionSession.sell_item("camp_kit", 3).get("accepted", false)) and before == _snapshot(inventory, "camp_kit"), "overselling kits must be atomic")
	ExpeditionSession.begin_new_journey()
	_check(ExpeditionSession.get_stock_quantity("camp_kit") == 4 and ExpeditionSession.get_inventory().count_item("camp_kit") == 1, "journey reset must separately restore kit merchant and starter stocks")
	ExpeditionSession.crowns = 17
	_check_rejected_buy_is_atomic(ExpeditionSession.get_inventory(), "camp_kit", "not_enough_crowns")
	ExpeditionSession.begin_new_journey()
	inventory = ExpeditionSession.get_inventory()
	inventory.slots.clear()
	inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	_check_rejected_buy_is_atomic(inventory, "camp_kit", "inventory_full")


func _check_rejected_buy_is_atomic(inventory: ExpeditionInventory, item_id: String, expected_reason: String) -> void:
	var before := _snapshot(inventory, item_id)
	var result := ExpeditionSession.buy_item(item_id)
	_check(not bool(result.get("accepted", false)) and str(result.get("reason", "")) == expected_reason, "purchase must reject with %s" % expected_reason)
	_check(_snapshot(inventory, item_id) == before, "a %s purchase failure must not mutate wallet, stock, or bag" % expected_reason)


func _snapshot(inventory: ExpeditionInventory, item_id: String) -> Dictionary:
	return {
		"crowns": ExpeditionSession.crowns,
		"stock": ExpeditionSession.get_stock_quantity(item_id),
		"count": inventory.count_item(item_id),
		"slots": inventory.slots.duplicate(true),
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("MERCHANT SESSION TEST PASS: reset, buy, sell, archery, chain flail, pricing, stock, capacity, and atomic failures")
		quit(0)
		return
	for failure in failures:
		push_error("MERCHANT SESSION TEST FAIL: %s" % failure)
	quit(1)


func _test_smithing_trade_protection() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var forge := preload("res://scripts/smithing_system.gd").new().setup(inventory)
	for id in forge.trial_supplies():
		inventory.add_item(str(id), int(forge.trial_supplies()[id]), false)
	inventory.add_item("rusted_sword", 2)
	var owned := forge.weapons()
	var upgraded_uid := str(owned[owned.size() - 1].uid)
	forge.select_weapon(upgraded_uid)
	forge.replace_grip("leather_grip")
	_check(inventory.count_sellable_item("rusted_sword") == 1, "simply viewing a plain sword must not protect its blank instance metadata from sale")
	var before := _snapshot(inventory, "rusted_sword")
	var rejected_bulk := ExpeditionSession.sell_item("rusted_sword", 2)
	_check(not rejected_bulk.accepted and rejected_bulk.reason == "protected_weapon" and _snapshot(inventory, "rusted_sword") == before, "bulk sale must atomically reject when its quantity would include an upgraded same-ID sword")
	var merchant := MerchantScreen.new()
	merchant.inventory = inventory
	merchant._build_fonts()
	merchant._build_interface()
	merchant._refresh_trade()
	merchant._select_bag_item("rusted_sword")
	_check(not merchant.sell_button.disabled and merchant.sell_detail_label.text.contains("판매 가능 1") and merchant.sell_detail_label.text.contains("보호 1"), "mixed same-ID merchant details must show the saleable and protected quantities separately")
	_check(merchant.sell_detail_label.text.contains("대장간") and (merchant.bag_buttons.rusted_sword as Button).text.contains("보호 1"), "merchant row and selected detail must visibly explain protected smithing weapons")
	merchant._sell_selected()
	_check(inventory.count_item("rusted_sword") == 1 and inventory.count_sellable_item("rusted_sword") == 0, "selling one mixed-ID weapon must choose only the ordinary sword")
	_check(ExpeditionSession.crowns == int(before.crowns) + ExpeditionSession.get_sell_price("rusted_sword") and ExpeditionSession.get_stock_quantity("rusted_sword") == int(before.stock) + 1, "sale of the plain instance must change wallet and stock by exactly one item")
	_check(forge.select_weapon(upgraded_uid).accepted and str(forge.snapshot().selected_weapon.smithing.grip) == "leather_grip", "aggregate sale must leave the exact upgraded instance and its properties intact")
	_check(merchant.sell_button.disabled and merchant.sell_detail_label.text.contains("판매 가능 0") and merchant.sell_detail_label.text.contains("보호 1"), "protected-only stock must remain inspectable with its sale action disabled")
	before = _snapshot(inventory, "rusted_sword")
	var protected_sale := ExpeditionSession.sell_item("rusted_sword")
	_check(not protected_sale.accepted and protected_sale.reason == "protected_weapon" and _snapshot(inventory, "rusted_sword") == before, "direct protected-only sale must preserve inventory, crowns and stock")
	inventory.add_item("rusted_sword")
	owned = forge.weapons()
	var drilled_uid := str(owned[owned.size() - 1].uid)
	forge.select_weapon(drilled_uid)
	forge.drill_socket()
	_check(inventory.count_sellable_item("rusted_sword") == 0, "partially drilled sword must already be protected because a part was consumed")
	before = _snapshot(inventory, "rusted_sword")
	_check(not ExpeditionSession.sell_item("rusted_sword", 2).accepted and _snapshot(inventory, "rusted_sword") == before, "completed upgrades and unfinished drilling must both survive aggregate selling attempts")
	forge.start("iron_longsword")
	for _pull in 6:
		forge.pump_bellows()
	forge.move_to_anvil()
	for face in 2:
		for section in 3:
			forge.hammer(section)
			forge.hammer(section)
		if face == 0:
			forge.flip_blade()
	forge.quench()
	forge.finish()
	before = _snapshot(inventory, "forged_longsword")
	_check(inventory.count_item("forged_longsword") == 1 and inventory.count_sellable_item("forged_longsword") == 0, "crafted weapon quality alone must protect the crafted instance")
	_check(not ExpeditionSession.sell_item("forged_longsword").accepted and _snapshot(inventory, "forged_longsword") == before, "quality-only crafted sword must never enter metadata-free aggregate buyback stock")
	merchant.free()
