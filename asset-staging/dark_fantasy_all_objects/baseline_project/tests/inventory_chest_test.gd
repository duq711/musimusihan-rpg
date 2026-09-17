extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_equipment_to_bag_transactions()
	await _test_live_status_readout()
	await _test_concealed_container_search()
	await _test_container_mouse_transfer_controls()
	await _test_realtime_inventory_and_chest()
	_finish()


func _test_equipment_to_bag_transactions() -> void:
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame
	_check_reference_layout_structure(overlay)

	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	var hood_count_before := inventory.count_item("wanderer_hood")
	overlay.open_inventory(inventory)
	_check(not overlay.transfer_button.visible, "bag-only inventory must hide the central transfer action before equipment selection")
	overlay._on_equipment_slot_pressed("head")
	_check(overlay.transfer_button.visible and not overlay.transfer_button.disabled, "occupied equipment selection must show and enable the central bag transfer action")
	overlay.transfer_button.pressed.emit()
	_check(str(inventory.equipment.get("head", "missing")).is_empty(), "moving selected equipment to the bag must clear its equipment slot")
	_check(inventory.count_item("wanderer_hood") == hood_count_before + 1, "moving selected equipment must increase the exact bag item count")
	var hood_index := -1
	for index in inventory.slots.size():
		if str(inventory.slots[index].get("id", "")) == "wanderer_hood":
			hood_index = index
			break
	_check(hood_index >= 0, "unequipped head item must occupy one logical inventory slot")
	if hood_index >= 0:
		overlay._on_inventory_slot_pressed(hood_index)
		_check(overlay.selected_source == "inventory" and overlay.selected_index == hood_index, "continuous grid item selection must preserve the logical slot index")
		_check(not overlay.equip_button.disabled, "selected equipment item in the continuous grid must enable equip")
		overlay.equip_button.pressed.emit()
		_check(str(inventory.equipment.get("head", "")) == "wanderer_hood", "equipping from the continuous grid must restore the authored equipment slot")
		_check(inventory.count_item("wanderer_hood") == hood_count_before, "equipping must remove exactly one item from the bag")
		overlay._on_equipment_slot_pressed("head")
		_check(not overlay.unequip_button.disabled, "occupied equipment selection must preserve the dedicated unequip action")
		overlay.unequip_button.pressed.emit()
		_check(str(inventory.equipment.get("head", "missing")).is_empty(), "dedicated unequip must clear the selected equipment slot")
		_check(inventory.count_item("wanderer_hood") == hood_count_before + 1, "dedicated unequip must return exactly one item to the continuous grid bag")

	var full_inventory := ExpeditionInventory.new()
	full_inventory.seed_default_loadout()
	var free_slots := ExpeditionInventory.MAX_SLOTS - full_inventory.slots.size()
	_check(full_inventory.add_item("rusted_sword", free_slots) == 0, "equipment rollback setup must fill every remaining bag slot")
	_check(full_inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "equipment rollback setup must reach fixed bag capacity")
	var equipped_head_before := str(full_inventory.equipment.get("head", ""))
	var full_hood_count_before := full_inventory.count_item("wanderer_hood")
	overlay.open_inventory(full_inventory)
	overlay._on_equipment_slot_pressed("head")
	_check(not overlay.transfer_button.disabled, "full-bag equipment selection must still expose the central transfer attempt")
	overlay.transfer_button.pressed.emit()
	_check(str(full_inventory.equipment.get("head", "")) == equipped_head_before, "full bag must keep selected equipment in its original slot")
	_check(full_inventory.count_item("wanderer_hood") == full_hood_count_before, "failed equipment transfer must not duplicate the item into a full bag")
	_check(full_inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "failed equipment transfer must preserve full bag contents")

	overlay.close()
	overlay.queue_free()
	await process_frame


func _test_live_status_readout() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var runtime_status := {
		"health": 72.0,
		"max_health": 100.0,
		"stamina": 63.0,
		"max_stamina": 125.0,
	}
	var status_provider := func() -> Dictionary:
		return runtime_status
	ExpeditionSession.hunger = 64.0
	ExpeditionSession.thirst = 53.0

	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame
	overlay.open_inventory(inventory, status_provider)

	_check(overlay.status_footer != null, "inventory must expose its live status footer")
	_check(overlay.weight_value_label != null, "inventory status footer must expose the weight and slot readout")
	_check(overlay.weight_capacity_label != null, "inventory status footer must expose occupied and maximum bag slots")
	_check(overlay.stamina_bar != null and overlay.stamina_value_label != null, "inventory status footer must expose stamina current and maximum values")
	_check(overlay.hunger_bar != null and overlay.hunger_value_label != null, "inventory status footer must expose hunger current and maximum values")
	_check(overlay.thirst_bar != null and overlay.thirst_value_label != null, "inventory status footer must expose thirst current and maximum values")
	if (
		overlay.status_footer == null
		or overlay.weight_value_label == null
		or overlay.weight_capacity_label == null
		or overlay.stamina_bar == null
		or overlay.stamina_value_label == null
		or overlay.hunger_bar == null
		or overlay.hunger_value_label == null
		or overlay.thirst_bar == null
		or overlay.thirst_value_label == null
	):
		overlay.queue_free()
		await process_frame
		return

	_check(overlay.status_footer.name == "InventoryFooter", "live status footer must preserve the InventoryFooter node contract")
	_check(overlay.status_footer.visible and overlay.status_footer.is_visible_in_tree(), "live status footer must be visible while the inventory is open")
	_check(overlay.status_footer.position.is_equal_approx(Vector2(248, 665)), "bag-only status footer must align beneath the centered equipment and bag panes")
	_check(overlay.status_footer.size.is_equal_approx(Vector2(784, 44)), "bag-only status footer must span both centered panes")
	_check_status_readout(overlay, inventory, 63.0, 125.0, 64.0, 53.0, "initial inventory open")

	# Inventory pauses the SceneTree in realtime play. Explicit refresh must still
	# consume the latest provider/session/model values without closing and reopening.
	paused = true
	runtime_status["stamina"] = 21.0
	runtime_status["max_stamina"] = 90.0
	ExpeditionSession.hunger = 37.0
	ExpeditionSession.thirst = 28.0
	inventory.add_item("black_salt", 2)
	overlay.refresh_status_readout()
	_check(overlay.is_open(), "refreshing live status must leave the inventory open")
	_check_status_readout(overlay, inventory, 21.0, 90.0, 37.0, 28.0, "open inventory refresh")
	paused = false

	var container := LootContainer.new().configure("상태 푸터 배치", [{"id": "linen_bandage", "quantity": 1}])
	overlay.open_container(inventory, container, status_provider)
	_check(overlay.status_footer.visible and overlay.status_footer.is_visible_in_tree(), "live status footer must remain visible in container mode")
	_check(overlay.status_footer.position.is_equal_approx(Vector2(16, 665)), "container status footer must align beneath the left equipment and bag panes")
	_check(overlay.status_footer.size.is_equal_approx(Vector2(784, 44)), "container status footer must keep the same two-pane span")
	_check_status_readout(overlay, inventory, 21.0, 90.0, 37.0, 28.0, "container open")

	overlay.open_inventory(inventory, status_provider)
	_check(overlay.status_footer.position.is_equal_approx(Vector2(248, 665)), "returning to bag-only mode must restore the centered footer position")
	_check(overlay.status_footer.size.is_equal_approx(Vector2(784, 44)), "returning to bag-only mode must preserve footer size")
	overlay.close()
	overlay.queue_free()
	await process_frame


func _check_status_readout(
	overlay: InventoryOverlay,
	inventory: ExpeditionInventory,
	expected_stamina: float,
	expected_max_stamina: float,
	expected_hunger: float,
	expected_thirst: float,
	context: String
) -> void:
	var weight_text := _compact_readout(overlay.weight_value_label.text)
	var capacity_text := _compact_readout(overlay.weight_capacity_label.text)
	var stamina_text := _compact_readout(overlay.stamina_value_label.text)
	var hunger_text := _compact_readout(overlay.hunger_value_label.text)
	var thirst_text := _compact_readout(overlay.thirst_value_label.text)
	_check(weight_text.contains("%.1fKG" % inventory.total_weight()), "%s must show current carried weight" % context)
	_check(capacity_text.contains("%d/%d" % [inventory.slots.size(), ExpeditionInventory.MAX_SLOTS]), "%s must show occupied and maximum bag slots" % context)
	_check(stamina_text.contains("%d/%d" % [roundi(expected_stamina), roundi(expected_max_stamina)]), "%s must show current and maximum stamina" % context)
	_check(hunger_text.contains("%d/%d" % [roundi(expected_hunger), roundi(ExpeditionSession.MAX_NEED)]), "%s must show current and maximum hunger" % context)
	_check(thirst_text.contains("%d/%d" % [roundi(expected_thirst), roundi(ExpeditionSession.MAX_NEED)]), "%s must show current and maximum thirst" % context)
	_check(is_equal_approx(overlay.stamina_bar.value, expected_stamina), "%s stamina bar must use the live current value" % context)
	_check(is_equal_approx(overlay.stamina_bar.max_value, expected_max_stamina), "%s stamina bar must use the provider maximum" % context)
	_check(is_equal_approx(overlay.hunger_bar.value, expected_hunger), "%s hunger bar must use session hunger" % context)
	_check(is_equal_approx(overlay.hunger_bar.max_value, ExpeditionSession.MAX_NEED), "%s hunger bar must use the survival maximum" % context)
	_check(is_equal_approx(overlay.thirst_bar.value, expected_thirst), "%s thirst bar must use session thirst" % context)
	_check(is_equal_approx(overlay.thirst_bar.max_value, ExpeditionSession.MAX_NEED), "%s thirst bar must use the survival maximum" % context)


func _compact_readout(text_value: String) -> String:
	return text_value.replace(" ", "").replace("\n", "").to_upper()


func _test_concealed_container_search() -> void:
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame

	var inventory := ExpeditionInventory.new()
	var container := LootContainer.new().configure("미식별 수색", [
		{"id": "linen_bandage", "quantity": 2},
		{"id": "silver_chalice", "quantity": 1},
		{"id": "black_salt", "quantity": 3}
	])
	container.identify_interval = 1.0
	var total_units_before := container.item_count()
	overlay.open_container(inventory, container)

	_check(overlay.process_mode == Node.PROCESS_MODE_ALWAYS, "container search overlay must process while realtime gameplay is paused")
	_check(container.search_started, "opening a container overlay must begin persistent rummaging")
	_check(container.identified_stack_count() == 0 and container.unidentified_stack_count() == 3, "new authored chest stacks must all begin unidentified")
	for index in range(container.items.size()):
		var button := overlay.container_slot_buttons[index]
		var authored_stack := container.items[index]
		var authored_id := str(authored_stack.get("id", ""))
		var authored_name := ExpeditionInventory.get_item_name(authored_id)
		var authored_quantity := int(authored_stack.get("quantity", 0))
		var marker := button.get_node_or_null("UnknownMarker") as Label
		_check(button.visible and button.text == "?", "unidentified stack %d must render as a question mark" % index)
		_check(bool(button.get_meta("concealed", false)), "unidentified stack %d must expose concealed metadata" % index)
		_check(str(button.get_meta("item_id", "leaked")) == "", "unidentified stack %d must not expose its item id through button metadata" % index)
		_check(int(button.get_meta("quantity", -1)) == 0, "unidentified stack %d must not expose its quantity through button metadata" % index)
		_check(marker != null and marker.visible and marker.text == "?", "unidentified stack %d must show the dedicated question-mark marker" % index)
		_check(not button.tooltip_text.contains(authored_id), "unidentified stack %d tooltip must not leak its item id" % index)
		_check(not button.tooltip_text.contains(authored_name), "unidentified stack %d tooltip must not leak its item name" % index)
		_check(not button.tooltip_text.contains(str(authored_quantity)), "unidentified stack %d tooltip must not leak its quantity" % index)
		_check(button.size.is_equal_approx(InventoryOverlay.STORAGE_CELL_SIZE), "unidentified stack %d must use a neutral 1x1 visual footprint" % index)

	# Every transfer path must reject concealed items without changing ownership.
	overlay._on_container_slot_pressed(0)
	_check(overlay.selected_source.is_empty() and overlay.transfer_button.disabled, "selecting a concealed stack must not enable the transfer action")
	_emit_container_mouse_input(overlay, 0, true, false)
	_emit_container_mouse_input(overlay, 0, false, true)
	_check(not overlay.quantity_dialog_root.visible, "concealed double/Ctrl-click must not expose the quantity dialog")
	overlay.selected_source = "container"
	overlay.selected_index = 0
	overlay._transfer_selected()
	_check(overlay.take_all_button.disabled, "take-all must remain disabled while any stack is unidentified")
	overlay._take_all_from_container()
	_check(inventory.slots.is_empty(), "double-click, Ctrl-click, transfer, and take-all must not move concealed loot")
	_check(container.item_count() == total_units_before, "blocked concealed transfers must preserve every source unit")

	# Search progress is deterministic and reveals at most one stack per update.
	var before_interval := container.advance_search(0.99)
	_check(before_interval.is_empty() and container.identified_stack_count() == 0, "search must reveal nothing before the identification interval")
	var first_reveal := container.advance_search(0.02)
	_check(not first_reveal.is_empty() and container.identified_stack_count() == 1, "crossing the interval through advance_search must reveal exactly one stack")
	overlay._process(5.0)
	_check(container.identified_stack_count() == 2 and container.unidentified_stack_count() == 1, "one overlay process call must reveal at most one additional stack even with a long delta")
	var identified_before_close := container.identified_stack_count()
	overlay.close()
	overlay.open_container(inventory, container)
	_check(container.identified_stack_count() == identified_before_close and container.unidentified_stack_count() == 1, "closing and reopening a chest must preserve partial identification progress")
	_check(not bool(overlay.container_slot_buttons[0].get_meta("concealed", true)), "reopening must keep the first revealed stack identified")
	_check(not bool(overlay.container_slot_buttons[1].get_meta("concealed", true)), "reopening must keep the second revealed stack identified")
	_check(bool(overlay.container_slot_buttons[2].get_meta("concealed", false)), "reopening must keep the remaining stack concealed")

	# The realtime inventory pauses the SceneTree, so ALWAYS processing must still
	# allow one-by-one discovery to finish without resuming the dungeon.
	container.identify_interval = 0.01
	paused = true
	await process_frame
	_check(paused and container.identified_stack_count() == 3, "paused realtime overlays must continue revealing loot through ALWAYS processing")
	paused = false

	overlay.close()
	overlay.queue_free()
	await process_frame


func _test_container_mouse_transfer_controls() -> void:
	var overlay := InventoryOverlay.new()
	root.add_child(overlay)
	await process_frame
	var close_state := {"count": 0}
	overlay.closed.connect(func() -> void: close_state["count"] = int(close_state["count"]) + 1)

	# A one-unit stack moves immediately on a real double-click input event.
	var single_inventory := ExpeditionInventory.new()
	var single_container := LootContainer.new().configure("단일 전송", [{"id": "reliquary", "quantity": 1}])
	overlay.open_container(single_inventory, single_container)
	single_container.identify_all()
	_emit_container_mouse_input(overlay, 0, true, false)
	_check(single_inventory.count_item("reliquary") == 1, "double-clicking a one-unit chest stack must move it immediately")
	_check(single_container.is_empty(), "one-unit double-click transfer must empty the source stack")
	_check(not overlay.quantity_dialog_root.visible, "one-unit double-click transfer must not open the quantity dialog")

	# Multi-unit double-click opens the picker; confirmation moves only the
	# authored quantity and preserves the remainder in the same container.
	var split_inventory := ExpeditionInventory.new()
	var split_container := LootContainer.new().configure("수량 전송", [{"id": "healing_draught", "quantity": 4}])
	overlay.open_container(split_inventory, split_container)
	split_container.identify_all()
	_emit_container_mouse_input(overlay, 0, true, false)
	_check(overlay.quantity_dialog_root.visible, "double-clicking a multi-unit chest stack must open the quantity dialog")
	_check(is_equal_approx(overlay.quantity_spinbox.min_value, 1.0), "quantity dialog minimum must be one")
	_check(is_equal_approx(overlay.quantity_spinbox.max_value, 4.0), "quantity dialog maximum must match the selected stack")
	overlay.quantity_spinbox.value = 2.0
	_check(is_equal_approx(overlay.quantity_spinbox.value, 2.0), "quantity dialog must retain the selected transfer quantity")
	overlay.quantity_confirm_button.pressed.emit()
	_check(not overlay.quantity_dialog_root.visible, "confirming a quantity transfer must close the quantity dialog")
	_check(split_inventory.count_item("healing_draught") == 2, "quantity confirmation must move exactly the selected units")
	_check(split_container.item_count() == 2, "quantity confirmation must preserve the unselected source remainder")
	_check(split_inventory.count_item("healing_draught") + split_container.item_count() == 4, "quantity confirmation must conserve total item ownership")

	# Cancellation is a pure UI operation and must not mutate either model.
	_emit_container_mouse_input(overlay, 0, true, false)
	_check(overlay.quantity_dialog_root.visible, "remaining multi-unit stack must reopen the quantity dialog")
	var split_inventory_before_cancel := split_inventory.count_item("healing_draught")
	var split_container_before_cancel := split_container.item_count()
	overlay.quantity_spinbox.value = 1.0
	overlay.quantity_cancel_button.pressed.emit()
	_check(not overlay.quantity_dialog_root.visible, "quantity cancel must close the dialog")
	_check(split_inventory.count_item("healing_draught") == split_inventory_before_cancel, "quantity cancel must not change the inventory")
	_check(split_container.item_count() == split_container_before_cancel, "quantity cancel must not change the container")

	# Ctrl + a normal single click bypasses the picker and requests the whole
	# source stack through the same GUI input signal used at runtime.
	var ctrl_inventory := ExpeditionInventory.new()
	var ctrl_container := LootContainer.new().configure("전체 전송", [{"id": "linen_bandage", "quantity": 4}])
	overlay.open_container(ctrl_inventory, ctrl_container)
	ctrl_container.identify_all()
	_emit_container_mouse_input(overlay, 0, false, true)
	_check(ctrl_inventory.count_item("linen_bandage") == 4, "Ctrl-click must move the entire selected chest stack")
	_check(ctrl_container.is_empty(), "Ctrl-click whole-stack transfer must empty the source stack")
	_check(not overlay.quantity_dialog_root.visible, "Ctrl-click whole-stack transfer must bypass the quantity dialog")

	# Whole-stack requests are capacity-aware: move what fits, leave the rest,
	# and never lose or duplicate units.
	var limited_inventory := ExpeditionInventory.new()
	limited_inventory.add_item("healing_draught", 4)
	limited_inventory.add_item("rusted_sword", ExpeditionInventory.MAX_SLOTS - limited_inventory.slots.size())
	_check(limited_inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "partial-transfer setup must fill every logical inventory slot")
	var limited_container := LootContainer.new().configure("부분 전송", [{"id": "healing_draught", "quantity": 4}])
	var limited_total_before := limited_inventory.count_item("healing_draught") + limited_container.item_count()
	overlay.open_container(limited_inventory, limited_container)
	limited_container.identify_all()
	_emit_container_mouse_input(overlay, 0, false, true)
	_check(limited_inventory.count_item("healing_draught") == 5, "capacity-limited Ctrl-click must fill the one available stack unit")
	_check(limited_container.item_count() == 3, "capacity-limited Ctrl-click must preserve the source remainder")
	_check(limited_inventory.count_item("healing_draught") + limited_container.item_count() == limited_total_before, "capacity-limited transfer must conserve total item ownership")
	_check(not overlay.quantity_dialog_root.visible, "capacity-limited Ctrl-click must not open the quantity dialog")

	# Closing while the nested picker is active dismisses only that picker. The
	# second close owns the overlay lifecycle and emits the public closed signal.
	var close_inventory := ExpeditionInventory.new()
	var close_container := LootContainer.new().configure("닫기 전송", [{"id": "black_salt", "quantity": 3}])
	overlay.open_container(close_inventory, close_container)
	close_container.identify_all()
	_emit_container_mouse_input(overlay, 0, true, false)
	_check(overlay.quantity_dialog_root.visible, "close lifecycle setup must open the quantity dialog")
	overlay.close()
	_check(not overlay.quantity_dialog_root.visible, "first close with quantity dialog open must dismiss only the dialog")
	_check(overlay.is_open(), "dismissing the quantity dialog must keep the inventory overlay open")
	_check(int(close_state["count"]) == 0, "dismissing the quantity dialog must not emit the overlay closed signal")
	_check(close_inventory.count_item("black_salt") == 0 and close_container.item_count() == 3, "dismissing the quantity dialog must not transfer items")
	overlay.close()
	_check(not overlay.is_open(), "second close must close the inventory overlay")
	_check(int(close_state["count"]) == 1, "closing the inventory overlay must emit closed exactly once")

	overlay.queue_free()
	await process_frame


func _test_realtime_inventory_and_chest() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_check(packed != null, "realtime scene must load for inventory integration")
	if packed == null:
		return
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await physics_frame
	await physics_frame

	_check(game.inventory != null, "realtime game must own shared inventory model")
	_check(game.inventory_overlay != null and not game.inventory_overlay.is_open(), "realtime inventory overlay must start hidden")
	_check(game.inventory_overlay.equipment_slot_buttons.size() == ExpeditionInventory.EQUIPMENT_ORDER.size(), "shared overlay must expose every authored equipment slot")
	_check(game.inventory_overlay.inventory_slot_buttons.size() == ExpeditionInventory.MAX_SLOTS, "shared overlay must expose every logical bag slot")
	_check(game.inventory_overlay.container_slot_buttons.size() == InventoryOverlay.CONTAINER_SLOT_COUNT, "shared overlay must expose every logical container stack button")
	_check(game.loot_chests.size() == 2, "realtime dungeon must spawn two deterministic loot chests")
	if game.loot_chests.is_empty():
		game.queue_free()
		await process_frame
		return

	var chest: DungeonLootChest = game.loot_chests[0]
	var chest_units_before: int = chest.container.item_count()
	var bandages_before: int = game.inventory.count_item("linen_bandage")
	var ray_from := chest.global_position + Vector3(0.0, 1.2, 2.4)
	var ray_to := chest.global_position + Vector3(0.0, 1.2, -0.6)
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 16)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var ray_result: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	var interaction_owner: Variant = null
	if not ray_result.is_empty():
		var collider := ray_result.get("collider") as CollisionObject3D
		if collider != null and collider.has_meta("interaction_owner"):
			interaction_owner = collider.get_meta("interaction_owner")
	_check(interaction_owner == chest, "realtime interaction ray must resolve the chest metadata owner")
	if interaction_owner is DungeonLootChest:
		(interaction_owner as DungeonLootChest).interact(game.player)

	_check(chest.state == DungeonLootChest.ChestState.OPENING and not chest.opened, "initial realtime interaction must begin opening without immediately opening the chest")
	_check(not chest.container.ever_opened, "realtime chest must not persist opened state before the timed interaction completes")
	_check(game.player.is_timed_interacting() and game.player.timed_interaction_owner == chest, "realtime player must own the active chest interaction")
	_check(is_equal_approx(game.player.get_timed_interaction_progress(), 0.0), "new realtime timed interaction must start at zero progress")
	_check(game.hud.interaction_panel != null and game.hud.interaction_panel.visible, "realtime timed interaction must show its HUD progress panel")
	_check(game.hud.interaction_progress != null and game.hud.interaction_progress.visible, "realtime timed interaction must show its progress bar")
	_check(game.game_mode == game.GameMode.RUNNING and not game.inventory_overlay.is_open(), "realtime container overlay must stay closed while the chest is still opening")
	_check(not paused, "realtime dungeon must remain unpaused during chest opening")

	game.player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.5)
	_check(not chest.opened and not game.inventory_overlay.is_open(), "partial realtime opening progress must not open the chest")
	_check(game.player.get_timed_interaction_progress() > 0.0 and game.player.get_timed_interaction_progress() < 1.0, "partial realtime opening must expose intermediate progress")
	game.player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION)
	_check(chest.opened and chest.container.ever_opened, "completing realtime chest interaction must persist its opened state")
	_check(not game.player.is_timed_interacting(), "completed realtime chest opening must clear player interaction state")
	_check(game.game_mode == game.GameMode.INVENTORY, "completed realtime chest interaction must enter inventory mode")
	_check(game.inventory_overlay.is_open(), "completed realtime chest interaction must show shared overlay")
	_check(paused, "realtime inventory must pause dungeon simulation after opening completes")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "realtime inventory must release the mouse")

	chest.container.identify_all()
	game.inventory_overlay._on_container_slot_pressed(0)
	_check(game.inventory_overlay.selected_source == "container" and game.inventory_overlay.selected_index == 0, "chest selection must preserve the logical container slot index")
	game.inventory_overlay.transfer_button.pressed.emit()
	_check(game.inventory.count_item("linen_bandage") == bandages_before + 2, "realtime transfer must move the exact selected chest stack")
	_check(chest.container.item_count() == chest_units_before - 2, "realtime transfer must remove the same units from chest")
	var units_after_transfer: int = chest.container.item_count()
	game.inventory_overlay.close()
	_check(not paused and game.game_mode == game.GameMode.RUNNING, "closing realtime inventory must resume the dungeon")
	if DisplayServer.get_name() != "headless":
		_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "closing realtime inventory must restore captured mouse")

	chest.interact(game.player)
	_check(not game.player.is_timed_interacting(), "reopening an opened realtime chest must bypass timed interaction")
	_check(game.inventory_overlay.is_open() and paused, "reopening an opened realtime chest must immediately restore its paused container overlay")
	_check(chest.container.item_count() == units_after_transfer, "reopening realtime chest must not regenerate loot")
	game.inventory_overlay.close()
	game.queue_free()
	await process_frame


func _emit_container_mouse_input(overlay: InventoryOverlay, index: int, double_click: bool, ctrl_pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.double_click = double_click
	event.ctrl_pressed = ctrl_pressed
	overlay.container_slot_buttons[index].gui_input.emit(event)


func _check_reference_layout_structure(overlay: InventoryOverlay) -> void:
	_check_preserved_navigation_tabs(overlay)
	_check(not overlay.detail_root.visible, "the reference-style item detail popup must start hidden")

	var grid := overlay.inventory_grid_root
	_check(grid != null and grid.name == "InventoryGridRoot", "shared overlay must expose the named continuous InventoryGridRoot")
	if grid == null:
		return
	_check(bool(grid.get_meta("continuous_grid", false)), "InventoryGridRoot must declare the continuous-grid contract")
	_check(InventoryOverlay.BAG_VISUAL_COLUMNS == 10 and int(grid.get_meta("visual_columns", 0)) == 10, "reference-style bag background must expose ten visual columns")
	_check(InventoryOverlay.BAG_VISUAL_ROWS == 5 and int(grid.get_meta("visual_rows", 0)) == 5, "reference-style bag background must expose five visual rows")
	_check(overlay.inventory_slot_buttons.size() == ExpeditionInventory.MAX_SLOTS, "continuous inventory grid must retain every logical inventory button independently of its visual background")
	var bag_background_count := 0
	for child in grid.get_children():
		if str(child.name).begins_with("BagGridCell_"):
			bag_background_count += 1
	_check(bag_background_count == 50, "reference-style bag must contain exactly fifty 10 by 5 background cells")
	for cell_index in range(50):
		_check(grid.get_node_or_null("BagGridCell_%02d" % cell_index) != null, "continuous inventory grid must expose background cell %02d" % cell_index)
	var forbidden_sections: Array[String] = ["전술 조끼", "주머니", "배낭"]
	for descendant in grid.find_children("*", "", true, false):
		for section_name in forbidden_sections:
			_check(not str(descendant.name).contains(section_name), "continuous inventory grid must not retain a %s compartment node" % section_name)
			if descendant is Label:
				_check(not (descendant as Label).text.contains(section_name), "continuous inventory grid must not retain a %s compartment label" % section_name)

	var container_grid := overlay.container_grid_root
	_check(container_grid != null and container_grid.name == "ContainerGridRoot", "shared overlay must expose the named ContainerGridRoot")
	if container_grid == null:
		return
	_check(InventoryOverlay.STORAGE_VISUAL_COLUMNS == 10, "reference-style container background must expose ten visual columns")
	_check(InventoryOverlay.STORAGE_VISUAL_ROWS == 4, "reference-style container background must expose four visual rows")
	var container_background_count := 0
	for child in container_grid.get_children():
		if str(child.name).begins_with("ContainerGridCell_"):
			container_background_count += 1
	_check(container_background_count == 40, "reference-style container must contain exactly forty 10 by 4 background cells")
	for cell_index in range(40):
		_check(container_grid.get_node_or_null("ContainerGridCell_%02d" % cell_index) != null, "container grid must expose background cell %02d" % cell_index)


func _check_preserved_navigation_tabs(overlay: InventoryOverlay) -> void:
	var navigation_bar := overlay.modal_root.get_node_or_null("InventoryNavigationBar") as Control
	_check(navigation_bar != null, "inventory overlay must preserve its navigation bar")
	if navigation_bar == null:
		return
	var preserved_tabs: Array[Dictionary] = [
		{"node": "SkillTab", "text": "스킬", "position": Vector2(230, 3)},
		{"node": "MapTab", "text": "지도", "position": Vector2(284, 3)},
		{"node": "MissionTab", "text": "임무", "position": Vector2(338, 3)}
	]
	for expected in preserved_tabs:
		var tab_name := str(expected.get("node", ""))
		var tab := navigation_bar.get_node_or_null(tab_name) as Control
		_check(tab != null, "inventory navigation must preserve %s" % tab_name)
		if tab == null:
			continue
		var expected_position: Vector2 = expected.get("position", Vector2.ZERO)
		_check(tab.position.is_equal_approx(expected_position), "%s must keep its preserved navigation position" % tab_name)
		_check(tab.size.is_equal_approx(Vector2(56, 33)), "%s must keep its preserved navigation size" % tab_name)
		var tab_label := tab.get_child(0) as Label if tab.get_child_count() > 0 else null
		_check(tab_label != null and tab_label.text == str(expected.get("text", "")), "%s must preserve its Korean label" % tab_name)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("INVENTORY CHEST TEST PASS: deliberate interaction, concealed search, mouse transfers, quantity modal, reopen, and sync")
		quit(0)
		return
	for failure in failures:
		push_error("INVENTORY CHEST TEST FAIL: %s" % failure)
	quit(1)
