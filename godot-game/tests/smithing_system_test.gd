extends SceneTree

const Smithing := preload("res://scripts/smithing_system.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_pipeline_and_failures()
	_test_instance_upgrades_transfer_combat()
	_test_capacity_and_cancel()
	_test_normal_supply_source()
	if failures.is_empty():
		print("SMITHING SYSTEM TEST PASS: heat, both faces, rhythm, quenching, atomic costs, unique equipment, chest transfer, combat and supply source")
		quit(0)
	else:
		for failure in failures:
			push_error("SMITHING SYSTEM TEST FAIL: %s" % failure)
		quit(1)


func _fixture() -> ExpeditionInventory:
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	for id in Smithing.trial_supplies():
		bag.add_item(str(id), int(Smithing.trial_supplies()[id]), false)
	return bag


func _test_pipeline_and_failures() -> void:
	var bag := _fixture()
	var forge := Smithing.new().setup(bag)
	var before := bag.slots.duplicate(true)
	_check(not forge.start("missing").accepted and bag.slots == before, "unknown recipe must preserve materials")
	_check(forge.start("iron_longsword").accepted, "valid recipe must load actual iron and coal")
	_check(bag.count_item("iron_ingot") == 9 and bag.count_item("forge_charcoal") == 6, "start must charge recipe materials once")
	before = bag.slots.duplicate(true)
	_check(not forge.start("iron_longsword").accepted and bag.slots == before, "busy start must reject without a second material cost")
	_check(not forge.move_to_anvil().accepted and not forge.quench().accepted, "cold iron and unfinished blade must not skip forge steps")
	for _index in 6:
		forge.pump_bellows()
	_check(forge.temperature == 920.0 and forge.move_to_anvil().accepted, "six bellows pulls must reach working heat")
	_check(not forge.hammer(-1).accepted and not forge.hammer(3).accepted, "invalid blade region must be rejected")
	for region in 3:
		forge.hammer(region, 1.0)
		forge.hammer(region, 1.0)
	_check(not forge.shaping_complete() and not forge.quench().accepted, "all three sections on only one side must be insufficient")
	_check(not forge.hammer(0).accepted, "completed sections must not accept score farming hits")
	forge.flip_blade()
	forge.tick(50.0)
	var progress := forge.sections.duplicate(true)
	_check(not forge.hammer(0).accepted and forge.sections == progress, "cold strikes must preserve progress and require reheating")
	forge.return_to_fire()
	for _index in 4:
		forge.pump_bellows()
	forge.move_to_anvil()
	for region in 3:
		forge.hammer(region, 1.0)
		forge.hammer(region, 1.0)
	_check(forge.shaping_complete(), "both faces and all regions must reach finished shape")
	_check(forge.quench().accepted and forge.temperature == 20.0, "finished hot blade must quench into a cooled blade")
	var result := forge.finish()
	_check(result.accepted and bag.count_item("forged_longsword") == 1, "finish must put a real equippable weapon in inventory")
	_check(not forge.finish().accepted and bag.count_item("forged_longsword") == 1, "finish may not duplicate the weapon")
	_check(float(forge.snapshot().selected_weapon.smithing.quality) > 90.0, "accurate work must preserve high weapon quality")
	var copy := forge.snapshot()
	copy.selected_weapon.smithing.quality = -500
	_check(float(forge.snapshot().selected_weapon.smithing.quality) > 90.0, "UI snapshots must not mutate authoritative weapon quality")
	forge.start("iron_arming_sword")
	for _index in 8:
		forge.pump_bellows()
	_check(forge.quality < 100.0 and not forge.move_to_anvil().accepted, "overheating must lower quality and require cooling")
	forge.tick(60.0)
	_check(forge.move_to_anvil().accepted, "overheated stock must recover after cooling")
	var quality_before := forge.quality
	forge.hammer(0, 0.2)
	_check(forge.quality < quality_before and float(forge.sections[0][0]) < 0.5, "poor rhythm must lower quality and shaping speed")


func _test_instance_upgrades_transfer_combat() -> void:
	var bag := _fixture()
	var forge := Smithing.new().setup(bag)
	bag.add_item("rusted_sword")
	_check(forge.select_weapon("rusted_sword").accepted, "owned equipped weapon must be selectable")
	var uid := str(forge.snapshot().selected_weapon.uid)
	var before := bag.slots.duplicate(true)
	_check(not forge.insert_rune().accepted and bag.slots == before, "rune insertion before drilling must consume nothing")
	_check(forge.replace_grip("balanced_grip").accepted, "balanced grip must consume actual parts")
	before = bag.slots.duplicate(true)
	_check(not forge.replace_grip("balanced_grip").accepted and bag.slots == before, "identical grip must reject without extra cost")
	_check(forge.reinforce_blade("silver_edge").accepted, "silver edge must install on selected sword")
	var parts_before := bag.count_item("steel_fitting")
	_check(not forge.drill_socket(0.1).accepted and bag.count_item("steel_fitting") == parts_before, "misaligned drilling must not charge a part")
	forge.drill_socket()
	_check(bag.count_item("steel_fitting") == parts_before - 1 and not forge.insert_rune().accepted, "first drilling turn pays exactly once and leaves unfinished socket")
	forge.drill_socket()
	forge.drill_socket()
	_check(bag.count_item("steel_fitting") == parts_before - 1 and forge.insert_rune("rune_fragment").accepted, "three drilling turns must open a socket and accept a real rune")
	for _index in 3:
		forge.drill_socket()
	forge.insert_rune("ember_rune")
	before = bag.slots.duplicate(true)
	_check(not forge.drill_socket().accepted and not forge.insert_rune().accepted and bag.slots == before, "two-socket cap must reject without material loss")
	var player := DungeonPlayer.new()
	player.inventory_model = bag
	_check(is_equal_approx(player.get_melee_damage(0.0), 44.0) and is_equal_approx(player.get_melee_damage(1.0), 70.0), "silver and both runes must affect actual melee damage")
	_check(is_equal_approx(player.get_melee_stamina_cost(), 18.0 * 0.78), "balanced grip must affect actual attack stamina")
	player.health = 50.0
	player.apply_smithing_on_hit()
	_check(player.health == 52.0, "life rune must restore real player health on hit")
	player.attack_charge = 0.5
	player.stamina = 100.0
	player._set_combat_state(DungeonPlayer.CombatState.WINDUP)
	player._commit_attack()
	_check(is_equal_approx(player.stamina, 100.0 - 24.0 * 0.78), "committed attacks must actually subtract the modified grip cost")
	player.weapon_pivot = Node3D.new()
	player.add_child(player.weapon_pivot)
	var steel := StandardMaterial3D.new()
	player._build_sword_visual(steel, steel, steel)
	player.sword_blade.layers = 1 << 19
	player._sync_smithing_weapon_visual()
	var details := player.sword_visual_root.get_node("SmithingDetails")
	_check(details.has_node("RuneSocket0") and details.has_node("RuneSocket1") and details.has_node("BalancedPommelInlay"), "equipped weapon must visibly show both rune sockets and balanced grip fitting")
	_check((details.get_node("RuneGem0") as MeshInstance3D).layers == player.sword_blade.layers, "new rune geometry must render in the actual first person equipment layer")
	var first_rune := (details.get_node("RuneGem0") as MeshInstance3D).material_override as StandardMaterial3D
	_check(first_rune.emission_enabled and first_rune.emission.g > first_rune.emission.r, "life rune must use its distinct glowing teal gem")
	var stats := bag.equipped_smithing_stats()
	bag.equip_from_slot(_find_slot(bag, "rusted_sword"))
	_check(player.get_melee_damage() == 27.0 and player.get_melee_stamina_cost() == 18.0, "second identical base sword must not inherit upgraded instance effects")
	player._sync_smithing_weapon_visual()
	_check(not player.sword_visual_root.get_node("SmithingDetails").has_node("RuneGem0"), "swapping to another base sword must clear previous rune visual geometry")
	var upgraded_index := _find_uid(bag, uid)
	_check(upgraded_index >= 0, "equipping another sword must return the exact upgraded instance to the bag")
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	overlay.set_process(false)
	overlay.inventory_model = bag
	overlay.loot_container = LootContainer.new().configure("대장간 보관 시험", [])
	_check(overlay._move_inventory_to_container(upgraded_index, 1, false) == 1, "upgraded sword must transfer through actual inventory container action")
	_check(str(overlay.loot_container.items[0].instance.uid) == uid, "container deposit must preserve exact weapon instance")
	_check(overlay._move_container_to_inventory(0, 1, false) == 1, "stored upgraded sword must be retrievable")
	bag.equip_from_slot(_find_uid(bag, uid))
	_check(bag.equipped_smithing_stats() == stats, "retrieve and equip round trip must preserve every combat upgrade")
	overlay._show_context_details(overlay._item_context("equipment", -1, "weapon"))
	_check(overlay._detail_summary_label.text.contains("44.0") and overlay._detail_summary_label.text.contains("70.0"), "inventory inspection must show the selected instance's real modified damage")
	_check(overlay._detail_description_label.text.contains("균형") and overlay._detail_description_label.text.contains("은 상감") and overlay._detail_description_label.text.contains("2/2"), "inventory inspection must distinguish individual grip, blade and occupied rune sockets")
	_check(forge.select_weapon(uid).accepted, "unique selection must survive bag and container transfers")
	bag.unequip("weapon")
	_check(not bag.equipment_data.has("weapon"), "unequip must clear equipped payload after returning instance to bag")
	bag.equipment.weapon = "rusted_sword"
	_check(player.get_melee_damage() == 27.0, "a later legacy assignment must not inherit old smithing stats")
	overlay.free()
	player.free()


func _test_capacity_and_cancel() -> void:
	var empty := ExpeditionInventory.new()
	var unavailable := Smithing.new().setup(empty)
	_check(not unavailable.start().accepted and empty.slots.is_empty(), "missing materials must atomically reject new craft")
	var bag := _fixture()
	var forge := Smithing.new().setup(bag)
	forge.start()
	for _index in 6:
		forge.pump_bellows()
	forge.move_to_anvil()
	for face in 2:
		for region in 3:
			forge.hammer(region)
			forge.hammer(region)
		if face == 0:
			forge.flip_blade()
	forge.quench()
	bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS)
	var before := bag.slots.duplicate(true)
	_check(not forge.finish().accepted and forge.stage == "quenched" and bag.slots == before, "full inventory must retain completed work without overwriting items")
	bag.remove_item("rusted_sword", 1)
	_check(forge.finish().accepted and bag.count_item("forged_longsword") == 1, "freeing capacity must make held completion claimable once")
	bag.remove_item("rusted_sword", 1)
	var iron_before := bag.count_item("iron_ingot")
	forge.start("iron_arming_sword")
	forge.cancel()
	forge.cancel()
	_check(bag.count_item("iron_ingot") == iron_before - 2 and bag.count_item("forged_longsword") == 1, "cancelling consumes started materials and cannot duplicate refunds or destroy finished weapons")


func _test_normal_supply_source() -> void:
	for id in Smithing.trial_supplies():
		_check(ExpeditionInventory.ITEM_DEFINITIONS.has(id), "smithing material %s must belong to original item catalog" % id)
		_check(ExpeditionSession.DEFAULT_MERCHANT_STOCK.has(id), "smithing material %s must be purchasable in normal play" % id)
	_check(int(ExpeditionSession.DEFAULT_MERCHANT_STOCK.iron_ingot.price) * 3 + int(ExpeditionSession.DEFAULT_MERCHANT_STOCK.forge_charcoal.price) * 2 <= ExpeditionSession.STARTING_CROWNS, "first craft must be affordable from the normal starting wallet")


func _find_slot(bag: ExpeditionInventory, id: String) -> int:
	for index in bag.slots.size():
		if str(bag.slots[index].id) == id:
			return index
	return -1


func _find_uid(bag: ExpeditionInventory, uid: String) -> int:
	for index in bag.slots.size():
		var instance: Dictionary = bag.slots[index].get("instance", {})
		if str(instance.get("uid", "")) == uid:
			return index
	return -1


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
