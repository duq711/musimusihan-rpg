extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	var sword_data := {"item_tag": "귀환의 검", "smithing": {"blade_reinforcement": 1}}
	bag.add_item("rusted_sword", 1, true, sword_data)
	bag.add_item("patched_mail", 1, true, {"item_tag": "예비 갑옷"})
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame
	overlay.open_inventory(bag)
	var window = overlay.item_detail_window
	_check(not window.is_open(), "a fresh inventory must not open item details automatically")
	var drops: Array[Dictionary] = []
	overlay.item_discarded.connect(func(stack: Dictionary) -> void: drops.append(stack.duplicate(true)))
	var sword_index := _find_tag(bag, "귀환의 검")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	overlay.inventory_slot_buttons[sword_index].gui_input.emit(click)
	_check(window.is_open() and window.title_label.text == ExpeditionInventory.get_item_name("rusted_sword"), "right-click must open the actual selected item detail window")
	_check(window.item_art.texture != null and window.description_label.text == str(ExpeditionInventory.get_item_definition("rusted_sword").description), "the large art and description must come from the selected catalog item")
	_check(window.equip_button.visible and not window.equip_button.disabled and not window.tag_button.disabled and not window.discard_button.disabled, "owned weapons must expose only usable equip/tag/discard actions")
	_check(window.z_index > overlay.detail_root.z_index and not overlay.detail_root.visible, "the modal detail window must cover the compact hover tooltip")
	_check_no_search_actions(window)
	window.tag_button.pressed.emit()
	window.tag_edit.text = "지켜 낸 장검"
	window.tag_save_button.pressed.emit()
	_check(ExpeditionInventory.get_item_tag(bag.slots[sword_index].get("instance", {})) == "지켜 낸 장검" and window.tag_label.text == "지켜 낸 장검", "the tag editor must save the exact weapon and refresh its real nameplate")
	_check((bag.slots[sword_index].instance as Dictionary).smithing == sword_data.smithing, "editing a nameplate must preserve weapon modifications")
	window.equip_button.pressed.emit()
	_check(str(bag.equipment.weapon) == "rusted_sword" and ExpeditionInventory.get_item_tag(bag.get_equipment_instance("weapon")) == "지켜 낸 장검", "equip must move the tagged weapon into the real equipment model")
	_check(window.is_open() and window.equip_button.visible and window.equip_button.disabled and window.equip_button.text == "장착 중", "equipping must keep inspection on the equipped item without enabling duplicate equipment")
	window.tag_button.pressed.emit()
	window.tag_edit.text = "장착 중 이름표"
	window.tag_save_button.pressed.emit()
	_check(window.is_open() and window.tag_label.text == "장착 중 이름표" and ExpeditionInventory.get_item_tag(bag.get_equipment_instance("weapon")) == "장착 중 이름표", "equipped tags must stay attached and the inspector must retain the same equipment data")
	window.discard_button.pressed.emit()
	window.discard_confirm_button.pressed.emit()
	_check(str(bag.equipment.weapon).is_empty() and drops.size() == 1, "discarding equipped gear must remove exactly the equipped item and emit one world drop")
	_check(drops[0].source == "equipment" and drops[0].equipment_slot == "weapon" and drops[0].instance.item_tag == "장착 중 이름표" and drops[0].instance.smithing == sword_data.smithing, "world drops must carry equipment origin, exact nameplate and modifications")
	_check(not window.is_open() and overlay.is_open(), "discard must return to the same open inventory")

	var armor_index := _find_tag(bag, "예비 갑옷")
	overlay.open_item_details("inventory", armor_index)
	window.equip_button.pressed.emit()
	_check(str(bag.equipment.body) == "patched_mail" and ExpeditionInventory.get_item_tag(bag.get_equipment_instance("body")) == "예비 갑옷", "armor inspection must equip the selected exact body item")
	overlay.close()
	_check(not window.is_open() and overlay.is_open(), "closing an inspector must leave the inventory open")

	bag.add_item("linen_bandage", 4, true, {"item_tag": "비상용"})
	var bandage_index := _find_tag(bag, "비상용")
	var target_stack := bag.slots[bandage_index]
	overlay.open_item_details("inventory", bandage_index)
	_check(not window.equip_button.visible and window.description_label.text == str(ExpeditionInventory.get_item_definition("linen_bandage").description), "consumables must show their own explanation and omit equipment action")
	# Removal before the selected item shifts indices. The modal must keep the
	# actual selected dictionary, instead of tagging or dropping its neighbour.
	bag.remove_from_slot(0, 9999)
	_check(window.is_open(), "earlier-slot removal must preserve inspection of the same remaining stack")
	overlay._on_inventory_slot_hovered(0)
	_check(window.title_label.text == ExpeditionInventory.get_item_name("linen_bandage"), "hovering other slots must not replace an open detailed item")
	window.tag_button.pressed.emit()
	window.tag_edit.text = ""
	window.tag_save_button.pressed.emit()
	_check(not (target_stack.get("instance", {}) as Dictionary).has("item_tag") and window.tag_label.text.is_empty(), "saving an empty nameplate must remove it from only the inspected stack")
	window.discard_button.pressed.emit()
	window.discard_quantity.get_line_edit().text = "2"
	window.discard_confirm_button.pressed.emit()
	_check(int(target_stack.quantity) == 2 and drops.size() == 2 and int(drops[1].quantity) == 2 and int(drops[1].source_remaining) == 2, "typed discard quantity must apply to the same stack after index changes and retain the remainder")
	_check(drops[1].id == "linen_bandage", "pending discard must never act on a different item")
	var remaining_index := bag.slots.find(target_stack)
	overlay._on_inventory_slot_pressed(remaining_index)
	overlay.detail_button.pressed.emit()
	_check(window.is_open(), "the visible detail button must open the actual selected stack")
	window.tag_button.pressed.emit()
	window.tag_edit.text = "취소할 이름표"
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	overlay._input(escape)
	_check(window.is_open() and not window.tag_editor.visible and ExpeditionInventory.get_item_tag(target_stack.get("instance", {})).is_empty(), "Escape while editing must cancel without saving or closing inventory")
	overlay._input(escape)
	_check(not window.is_open() and overlay.is_open(), "the next Escape must close item details only")
	overlay.close()
	_check(not overlay.is_open(), "inventory close must still work after cancelling details")

	var chest := LootContainer.new().configure("시험 상자", [{"id": "rusted_sword", "quantity": 1}])
	overlay.open_container(bag, chest)
	_check(not overlay.open_item_details("container", 0), "unknown chest contents must not leak their description or artwork")
	chest.identify_all()
	_check(overlay.open_item_details("container", 0), "identified container items must be inspectable")
	_check(window.tag_button.disabled and window.discard_button.disabled and window.equip_button.disabled, "unowned container items must be read-only")
	var before := chest.items.duplicate(true)
	window.tag_requested.emit("불법 변경")
	window.discard_requested.emit(1)
	window.equip_requested.emit()
	_check(chest.items == before and drops.size() == 2, "read-only ownership must be enforced by action handlers, not just disabled visuals")
	overlay._dismiss_item_details()
	overlay.open_inventory(bag)
	remaining_index = bag.slots.find(target_stack)
	overlay.open_item_details("inventory", remaining_index)
	bag.remove_from_slot(remaining_index, 9999)
	_check(not window.is_open(), "removing the exact inspected stack must dismiss stale action targets")
	overlay.queue_free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("ITEM DETAILS TEST %s: actual inspection, exact-stack tags/equip/discard, ownership, typed quantity and modal cancellation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _find_tag(bag: ExpeditionInventory, tag: String) -> int:
	for index in bag.slots.size():
		if ExpeditionInventory.get_item_tag(bag.slots[index].get("instance", {})) == tag:
			return index
	return -1


func _check_no_search_actions(node: Node) -> void:
	if node is Button:
		_check(not (node as Button).text.contains("검색"), "item details must not include search actions")
	for child in node.get_children():
		_check_no_search_actions(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
