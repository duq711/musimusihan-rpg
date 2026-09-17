extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_tag_edits_and_signal_contract()
	_test_stack_identity_and_capacity()
	_test_container_round_trip_and_full_destination()
	_test_equipment_tags_upgrades_and_discard()
	if failures.is_empty():
		print("ITEM METADATA TEST PASS: sanitized names, exact change signals, distinct stacks, chest round trips, equipment and upgrade preservation, discard and full-bag invariance")
		quit(0)
	else:
		for failure in failures:
			push_error("ITEM METADATA TEST FAIL: %s" % failure)
		quit(1)


func _test_tag_edits_and_signal_contract() -> void:
	var bag := ExpeditionInventory.new()
	bag.add_item("iron_ingot", 3, false)
	bag.add_item("healing_draught", 2, false)
	var signals := {"count": 0}
	bag.changed.connect(func() -> void: signals.count += 1)
	_check(not bag.set_slot_tag(-1, "invalid") and not bag.set_slot_tag(2, "invalid"), "out-of-range bag name edits must reject")
	_check(not bag.set_equipment_tag("missing", "invalid") and not bag.set_equipment_tag("weapon", "invalid"), "invalid and empty equipment slots must reject name edits")
	_check(bag.set_slot_tag(0, " \t대장간\n재료\r " + String.chr(0x7f) + String.chr(0x85) + String.chr(0x2028)) and _tag(bag.slots[0]) == "대장간재료", "name tags must remove controls and line breaks, then trim whitespace")
	_check(signals.count == 1, "one accepted name change must emit once")
	_check(bag.set_slot_tag(0, "대장간재료\n") and signals.count == 1, "equivalent sanitized name edits must not emit")
	_check(bag.set_slot_tag(0, "수".repeat(40)) and _tag(bag.slots[0]) == "수".repeat(ExpeditionInventory.MAX_ITEM_TAG_LENGTH), "24-character name limit must count Unicode characters")
	_check(bag.set_slot_tag(1, "비상약") and _tag(bag.slots[1]) == "비상약", "consumable stacks must support their own name tag")
	_check(bag.slots[0].id == "iron_ingot" and bag.slots[0].quantity == 3 and bag.slots[1].quantity == 2, "names must preserve original IDs and stack quantities")
	_check(bag.set_slot_tag(0, " \n\t ") and not bag.slots[0].has("instance"), "removing a sole name tag must remove the empty instance payload")
	var before_signals := int(signals.count)
	var before := _snapshot(bag)
	_check(bag.set_slot_tag(0, "") and signals.count == before_signals and _snapshot(bag) == before, "already-empty tags must leave inventory and signals unchanged")
	var instance := _worked_weapon()
	bag.add_item("rusted_sword", 1, false, instance)
	_check(bag.set_slot_tag(2, "바뀐 이름") and bag.slots[2].instance.smithing == instance.smithing, "renaming must preserve all nested smithing metadata")
	_check(instance.item_tag == "첫 검", "rename must not mutate a caller-owned instance Dictionary")
	_check(bag.set_slot_tag(2, "") and not bag.slots[2].instance.has("item_tag") and bag.slots[2].instance.uid == "worked-sword-1", "tag removal must preserve instance identity and other payload")


func _test_stack_identity_and_capacity() -> void:
	var bag := ExpeditionInventory.new()
	var first := {"item_tag": "식사 재료", "origin": {"batch": 1}}
	var second := {"item_tag": "식사 재료", "origin": {"batch": 2}}
	bag.add_item("raw_meat", 2, false, first)
	bag.add_item("raw_meat", 1, false, second)
	bag.add_item("raw_meat", 1, false)
	bag.add_item("raw_meat", 1, false, {"item_tag": "보관용"})
	_check(bag.slots.size() == 4, "equal IDs with different tags or nested payload must occupy separate stacks")
	bag.add_item("raw_meat", 3, false, first.duplicate(true))
	_check(bag.slots.size() == 4 and bag.slots[0].quantity == 5, "equal complete metadata must still stack normally")
	first.origin.batch = 99
	_check(bag.slots[0].instance.origin.batch == 1, "add_item must deeply copy incoming metadata")
	bag.add_item("iron_ingot", 15, false, {"item_tag": "광산", "origin": {"batch": 3}})
	_check(bag.slots[4].quantity == 12 and bag.slots[5].quantity == 3 and _tag(bag.slots[5]) == "광산", "splitting an incoming quantity across stacks must preserve every name")
	bag.slots[4].instance.origin.batch = 7
	_check(bag.slots[5].instance.origin.batch == 3, "split stacks must not share nested mutable instance payload")
	var full_bag := ExpeditionInventory.new()
	full_bag.add_item("raw_meat", 1, false, {"item_tag": "기존"})
	for _index in ExpeditionInventory.MAX_SLOTS - 1:
		full_bag.add_item("grave_key", 3, false)
	_check(full_bag.slots.size() == ExpeditionInventory.MAX_SLOTS, "full capacity fixture must fill actual inventory slots")
	_check(full_bag.can_add("raw_meat", 5, {"item_tag": "기존"}), "capacity checks must accept remaining room for matching metadata")
	_check(not full_bag.can_add("raw_meat", 1) and not full_bag.can_add("raw_meat", 1, {"item_tag": "다름"}), "full inventory must not count a differently named stack as free room")
	var signals := {"count": 0}
	full_bag.changed.connect(func() -> void: signals.count += 1)
	var before := _snapshot(full_bag)
	_check(full_bag.add_item("raw_meat", 1, true, {"item_tag": "다름"}) == 1 and _snapshot(full_bag) == before and signals.count == 0, "rejected named stack addition must preserve the full bag and emit nothing")


func _test_container_round_trip_and_full_destination() -> void:
	var bag := ExpeditionInventory.new()
	var instance := {"item_tag": "야영 재료", "origin": {"batch": 12}}
	bag.add_item("raw_meat", 4, false, instance)
	bag.add_item("raw_meat", 1, false, {"item_tag": "따로 보관"})
	var chest := LootContainer.new().configure("이름표 시험", [])
	chest.store_item("raw_meat", 1, false)
	var overlay := InventoryOverlay.new()
	overlay.inventory_model = bag
	overlay.loot_container = chest
	_check(overlay._move_inventory_to_container(0, 2, false) == 2, "actual inventory deposit must move a partial named stack")
	_check(chest.items.size() == 2 and chest.items[1].instance == instance and _tag(bag.slots[0]) == "야영 재료", "container deposit must separate names and preserve the source remainder")
	_check(overlay._move_container_to_inventory(1, 1, false) == 1 and bag.slots[0].quantity == 3, "actual withdrawal must merge only into the matching named stack")
	_check(chest.items[1].quantity == 1 and chest.items[1].instance == instance, "partial withdrawal must preserve the container remainder metadata")
	var copied := chest.take_from_slot(1, 1, false)
	copied.instance.origin.batch = 99
	_check(bag.slots[0].instance.origin.batch == 12, "container and inventory instance payload must not share nested data")
	var authored := LootContainer.new().configure("보존 시험", [{"id": "iron_ingot", "quantity": 15, "instance": instance}], "", 3)
	_check(authored.items.size() == 2 and authored.items[0].instance == instance and authored.items[1].instance == instance and authored.has_unidentified_items(), "authored multi-stack loot must preserve instance data without revealing search state")
	chest = LootContainer.new().configure("가득 찬 보관함", [], "", 1)
	chest.store_item("raw_meat", 1, false, true, {"item_tag": "다른 재료"})
	overlay.loot_container = chest
	var before_bag := _snapshot(bag)
	var before_chest := chest.items.duplicate(true)
	_check(overlay._move_inventory_to_container(0, 3, false) == 0 and _snapshot(bag) == before_bag and chest.items == before_chest, "full differently named container must reject deposit without reordering or mutating either source")
	var full_bag := ExpeditionInventory.new()
	full_bag.add_item("raw_meat", 1, false, {"item_tag": "기존"})
	for _index in ExpeditionInventory.MAX_SLOTS - 1:
		full_bag.add_item("grave_key", 3, false)
	overlay.inventory_model = full_bag
	before_bag = _snapshot(full_bag)
	before_chest = chest.items.duplicate(true)
	_check(overlay._move_container_to_inventory(0, 1, false) == 0 and _snapshot(full_bag) == before_bag and chest.items == before_chest, "full differently named bag must reject withdrawal without mutating either source")
	overlay.free()


func _test_equipment_tags_upgrades_and_discard() -> void:
	var bag := ExpeditionInventory.new()
	var instance := _worked_weapon()
	bag.add_item("rusted_sword", 1, false, instance)
	_check(bag.equip_from_slot(0).accepted and bag.equipment.weapon == "rusted_sword", "a named weapon must equip with its original ID")
	_check(bag.get_equipment_instance("weapon") == instance, "equip must preserve name, unique ID and every upgrade")
	var stats := bag.equipped_smithing_stats()
	var signals := {"count": 0}
	bag.changed.connect(func() -> void: signals.count += 1)
	_check(bag.set_equipment_tag("weapon", " 오래된 친구 ") and bag.get_equipment_instance("weapon").item_tag == "오래된 친구" and signals.count == 1, "equipped name edits must trim and emit exactly once")
	_check(bag.set_equipment_tag("weapon", "오래된 친구") and signals.count == 1 and bag.equipped_smithing_stats() == stats, "equipped idempotent edits must preserve combat stats and emit nothing")
	_check(bag.unequip("weapon").accepted and _tag(bag.slots[0]) == "오래된 친구" and bag.slots[0].instance.smithing == instance.smithing, "unequip must return the exact named and upgraded item")
	bag.equip_from_slot(0)
	bag.add_item("rusted_sword", 1, false, {"item_tag": "예비 검"})
	bag.equip_from_slot(0)
	_check(ExpeditionInventory.get_item_tag(bag.get_equipment_instance("weapon")) == "예비 검" and _tag(bag.slots[0]) == "오래된 친구", "swapping identical equipment IDs must keep each name and instance separate")
	bag.equip_from_slot(0)
	_check(bag.equipped_smithing_stats() == stats, "swapping back must restore the original weapon upgrades")
	_check(bag.set_equipment_tag("weapon", "") and not bag.get_equipment_instance("weapon").has("item_tag") and bag.equipped_smithing_stats() == stats, "removing an equipped name must preserve upgrade metadata")
	bag.set_equipment_tag("weapon", "버릴 검")
	while bag.slots.size() < ExpeditionInventory.MAX_SLOTS:
		bag.add_item("grave_key", 3, false)
	var before := _snapshot(bag)
	var before_signals := int(signals.count)
	_check(not bag.unequip("weapon").accepted and _snapshot(bag) == before and signals.count == before_signals, "unequip with a full bag must reject with exact state and signal invariance")
	var original_instance := bag.get_equipment_instance("weapon")
	var discarded := bag.discard_equipment("weapon")
	_check(discarded.id == "rusted_sword" and discarded.quantity == 1 and discarded.instance.item_tag == "버릴 검" and discarded.instance.smithing == instance.smithing, "direct equipment discard must return the original ID, one item and full metadata")
	_check(bag.equipment.weapon == "" and not bag.equipment_data.has("weapon") and bag.slots == before.slots and signals.count == before_signals + 1, "direct discard must work with full bag, empty equipment data and emit once")
	discarded.instance.smithing.quality = 0.0
	_check(original_instance.smithing.quality == 96.0, "discard result must be a deep copy of the removed equipment instance")
	before_signals = int(signals.count)
	_check(bag.discard_equipment("weapon").is_empty() and bag.discard_equipment("missing").is_empty() and signals.count == before_signals, "empty and invalid equipment discard must be a silent no-op")
	bag.equipment.body = "patched_mail"
	before = _snapshot(bag)
	_check(not bag.unequip("body").accepted and _snapshot(bag) == before, "failed legacy equipment unequip must not initialize or mutate instance metadata")


func _worked_weapon() -> Dictionary:
	return {"item_id": "rusted_sword", "uid": "worked-sword-1", "item_tag": "첫 검", "smithing": {"quality": 96.0, "grip": "balanced_grip", "reinforcement": "silver_edge", "sockets": 2, "drill_progress": 0.0, "runes": ["rune_fragment", "ember_rune"]}}


func _tag(stack: Dictionary) -> String:
	return ExpeditionInventory.get_item_tag(stack.get("instance", {}))


func _snapshot(bag: ExpeditionInventory) -> Dictionary:
	return {"slots": bag.slots.duplicate(true), "equipment": bag.equipment.duplicate(true), "equipment_data": bag.equipment_data.duplicate(true)}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
