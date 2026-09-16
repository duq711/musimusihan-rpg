extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for slot: String in ["waist_pouch", "backpack"]:
		var replacement := "pilgrim_waist_pouch" if slot == "waist_pouch" else "wanderer_backpack"
		var bag := ExpeditionInventory.new()
		bag.seed_default_loadout()
		var previous := str(bag.equipment[slot])
		bag.set_equipment_tag(slot, "기존 이름표")
		bag.add_item(replacement, 1, true, {"item_tag": "교체 이름표", "custom_marker": 42})
		bag.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS - bag.slots.size())
		_check(bag.slots.size() == 30, "Swap fixture must fill all thirty slots.")
		var unrelated := _without(bag, [previous, replacement])
		var weight := bag.total_weight()
		var change_count := [0]
		bag.changed.connect(func() -> void: change_count[0] += 1)
		var result := bag.equip_from_slot(_find(bag, replacement))
		_check(result.get("accepted", false) and str(bag.equipment[slot]) == replacement, "A full inventory must allow an atomic same-slot storage swap: " + slot)
		_check(change_count[0] == 1 and bag.slots.size() == 30 and bag.count_item(previous) == 1 and bag.count_item(replacement) == 0, "Swap must emit once, return old equipment and conserve ownership.")
		_check(_without(bag, [previous, replacement]) == unrelated and is_equal_approx(bag.total_weight(), weight), "All carried contents and total weight must be conserved by exchange.")
		_check(ExpeditionInventory.get_item_tag(bag.get_equipment_instance(slot)) == "교체 이름표" and bag.get_equipment_instance(slot).custom_marker == 42, "Replacement instance data must remain equipped.")
		_check(ExpeditionInventory.get_item_tag(bag.slots[_find(bag, previous)].get("instance", {})) == "기존 이름표", "Returned storage must retain its own name tag.")
		var before_slots := bag.slots.duplicate(true)
		var before_equipment := bag.equipment.duplicate(true)
		_check(bag.unequip(slot).get("reason", "") == "full" and bag.slots == before_slots and bag.equipment == before_equipment and change_count[0] == 1, "Full-bag removal must reject without mutation or signal.")
		var discarded := bag.discard_equipment(slot)
		_check(str(discarded.id) == replacement and int(discarded.quantity) == 1 and discarded.instance.custom_marker == 42 and _without(bag, [previous, replacement]) == unrelated, "Discard must return only the actual equipped container; all carried contents remain safe.")
		_check(bag.equip_from_slot(_find(bag, previous)).get("accepted", false) and bag.unequip(slot).get("accepted", false), "Empty storage slots must support equip and safe removal when space exists.")
		var legacy := ExpeditionInventory.new()
		legacy.equipment = {"head": "wanderer_hood", "body": "patched_mail", "weapon": "rusted_sword", "offhand": "round_shield", "utility": "field_torch"}
		legacy.add_item(replacement)
		_check(legacy.equip_from_slot(0).get("accepted", false) and str(legacy.equipment[slot]) == replacement and legacy.equipment.weapon == "rusted_sword", "Old five-key inventory must accept a newly introduced storage slot without overwriting other gear.")
	var original := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var trial := ExpeditionSession.get_inventory()
	trial.set_equipment_tag("backpack", "별도 원정")
	var saved := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.restore_snapshot(saved)
	_check(ExpeditionSession.get_inventory() == trial and ExpeditionInventory.get_item_tag(trial.get_equipment_instance("backpack")) == "별도 원정", "Session round-trip must preserve storage gear and instance data.")
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original, "Trial must restore the original expedition exactly.")
	for failure in failures:
		push_error(failure)
	print("STORAGE EQUIPMENT TEST %s: full-bag atomic exchange, tagged instance ownership, safe rejection/removal/discard, legacy equipment and session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _find(bag: ExpeditionInventory, id: String) -> int:
	for index in bag.slots.size():
		if str(bag.slots[index].id) == id:
			return index
	return -1


func _without(bag: ExpeditionInventory, ids: Array) -> Array:
	return bag.slots.filter(func(stack: Dictionary) -> bool: return str(stack.id) not in ids).duplicate(true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
