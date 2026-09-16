extends SceneTree
## Synthetic mouse and keyboard input stays in an isolated SubViewport.
const PREVIEW := preload("res://tests/health_panel_preview.gd")
const QUICK_ITEMS := ["linen_bandage", "healing_draught", "surgery_kit", "splint", "antidote", "purifying_salt", "nerve_tonic", "pilgrim_ration", "boiled_rainwater", "alchemy_red_mending_weak"]
const QUICK_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_hash := PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag)
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var root_gui_before := root.gui_disable_input
	var picking_before := root.physics_object_picking
	root.gui_disable_input = true
	root.physics_object_picking = false
	sandbox.begin()
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		await _exercise_pointer_flow(dimensions)
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and PREVIEW.HELPERS.PRESERVATION.inventory_fingerprint(original_bag) == original_hash and PREVIEW.HELPERS.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before and Input.mouse_mode == mouse_before, "Local input must preserve the original expedition, inventory, sandbox and OS cursor.")
	root.gui_disable_input = root_gui_before
	root.physics_object_picking = picking_before
	for failure in failures:
		push_error(failure)
	print("HEALTH PANEL INPUT TEST %s: combined left/right input, real inspect/equip/unequip, exact 0-to-1-to-17 treatment, ten hotkeys, quick-use meters and 1280/960 bounds" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _exercise_pointer_flow(dimensions: Vector2i) -> void:
	var viewport := PREVIEW.HELPERS.create_viewport(dimensions)
	root.add_child(viewport)
	var fixture := PREVIEW.create_fixture(viewport, {"action": "injured"})
	var overlay: InventoryOverlay = fixture.overlay
	var panel := overlay.health_panel
	var player: DungeonPlayer = fixture.player
	var bag: ExpeditionInventory = fixture.bag
	PREVIEW.HELPERS.stop_external_execution(overlay)
	# Only the production handler inside this unhosted viewport receives keys.
	overlay.set_process_input(true)
	overlay.open_inventory(bag, player.get_inventory_status_snapshot)
	for _frame in 3:
		await process_frame
	_check_combined_bounds(viewport, overlay)
	_check(not panel.treatment_popup.is_visible_in_tree(), "Direct inventory entry must show both panes with treatment initially closed at %s." % dimensions)
	var portrait_angle := float(overlay.player_portrait.call("get_view_angle"))
	await _exercise_equipment(viewport, overlay, player, bag)
	await _exercise_storage_equipment(viewport, overlay, bag)
	var equipment_before := bag.equipment.duplicate(true)
	await _click(viewport, panel.part_buttons.left_arm)
	_check(player.get_selected_treatment_part() == "left_arm" and panel.part_buttons.left_arm.get_meta("selected") and panel.treatment_popup.is_visible_in_tree(), "Actual body-card hit must select the anatomical part and open treatment beside the live loadout.")
	_check_popup(viewport, panel, player)
	await _click(viewport, panel.treatment_buttons.healing_draught)
	_check(player.get_body_health_snapshot().parts.left_arm.health == 0.0 and bag.count_item("healing_draught") == 3 and panel.treatment_popup.is_visible_in_tree(), "Normal treatment on a zero arm must fail without consumption and retain the popup.")
	await _click(viewport, panel.treatment_buttons.surgery_kit)
	_check(player.get_body_health_snapshot().parts.left_arm.health == 1.0 and bag.count_item("surgery_kit") == 2 and panel.treatment_popup.is_visible_in_tree(), "Actual surgery hit must consume one kit, restore exactly one and retain the popup.")
	_check_popup(viewport, panel, player)
	await _click(viewport, panel.treatment_buttons.healing_draught)
	_check(player.get_body_health_snapshot().parts.left_arm.health == 17.0 and bag.count_item("healing_draught") == 2, "Actual potion hit must heal the repaired cursed arm from one to seventeen.")
	_check_popup(viewport, panel, player)
	_check(bag.equipment == equipment_before and not overlay.item_detail_window.is_open(), "Left treatment hits must not change right equipment or open item details.")
	await _click(viewport, panel.popup_close_button)
	_check(not panel.treatment_popup.is_visible_in_tree() and player.get_selected_treatment_part() == "left_arm", "Closing treatment must retain the selected target.")
	var chest_point: Vector2 = panel.get_global_transform_with_canvas() * (panel.FIGURE_ORIGIN + panel.PART_CENTERS.thorax)
	await _point_click(viewport, chest_point)
	_check(player.get_selected_treatment_part() == "thorax", "Actual silhouette hit must select thorax at %s." % dimensions)
	_check_popup(viewport, panel, player)
	await _click(viewport, panel.automatic_button)
	_check(player.get_selected_treatment_part().is_empty(), "Actual automatic-target hit must clear explicit selection.")
	_check_popup(viewport, panel, player)
	await _click(viewport, panel.popup_close_button)
	_check(float(overlay.player_portrait.call("get_view_angle")) == portrait_angle, "Combined-pane hits must not rotate the unused production portrait.")
	var body_before := player.get_body_health_snapshot()
	var bag_before := bag.slots.duplicate(true)
	await _click(viewport, overlay.equipment_tab_button)
	_check_combined_bounds(viewport, overlay)
	_check(player.get_body_health_snapshot() == body_before and bag.slots == bag_before and not panel.treatment_popup.is_visible_in_tree(), "The shared tab must retain health and items while keeping both panes present.")
	await _exercise_quick_use(viewport, fixture)
	_check(root.gui_disable_input and viewport.gui_disable_input and not viewport.physics_object_picking, "Only local dispatch may temporarily enable viewport GUI input.")
	overlay.set_process_input(false)
	viewport.free()
	player.free()
	await process_frame


func _exercise_equipment(viewport: SubViewport, overlay: InventoryOverlay, player: DungeonPlayer, bag: ExpeditionInventory) -> void:
	var loadout := overlay.combined_loadout_panel
	if not str(bag.equipment.get("weapon", "")).is_empty():
		_check(bool(bag.unequip("weapon").get("accepted", false)), "Fixture must free its actual weapon slot.")
	var sword_index := PREVIEW.HELPERS.find_slot(bag, "rusted_sword")
	_check(sword_index >= 0, "Fixture must contain a packed sword.")
	if sword_index < 0:
		return
	var sword_count := bag.count_item("rusted_sword")
	await _click(viewport, overlay.health_panel.part_buttons.left_arm)
	var body_before := player.get_body_health_snapshot()
	await _point_click(viewport, loadout.inventory_buttons[sword_index].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	_check(overlay.item_detail_window.is_open() and overlay.selected_source == "inventory" and overlay.selected_index == sword_index and not overlay.health_panel.treatment_popup.is_visible_in_tree(), "Actual right bag right-click must open that item's detail and close left treatment.")
	_check(player.get_body_health_snapshot() == body_before and bag.count_item("rusted_sword") == sword_count, "Item inspection must preserve body state and quantities.")
	await _key(viewport, KEY_ESCAPE)
	_check(not overlay.item_detail_window.is_open() and not overlay.detail_root.is_visible_in_tree(), "Closing details must not reveal the legacy hover panel over the combined view.")
	await _double_click(viewport, loadout.inventory_buttons[sword_index])
	_check(overlay.item_detail_window.is_open() and overlay.item_detail_window.equip_button.is_visible_in_tree(), "Actual bag double-click must open the existing equippable detail.")
	await _click(viewport, overlay.item_detail_window.equip_button)
	_check(str(bag.equipment.weapon) == "rusted_sword" and bag.count_item("rusted_sword") == sword_count - 1 and str(loadout.equipment_buttons.weapon.get_meta("item_id")) == "rusted_sword", "Existing detail equip must update the actual weapon and combined equipment art.")
	await _key(viewport, KEY_ESCAPE)
	await _click(viewport, loadout.equipment_buttons.weapon)
	_check(overlay.selected_source == "equipment" and overlay.selected_equipment_slot == "weapon" and not overlay.health_panel.treatment_popup.is_visible_in_tree(), "Actual equipment hit must select that slot without activating left treatment.")
	await _double_click(viewport, loadout.equipment_buttons.weapon)
	_check(str(bag.equipment.weapon).is_empty() and bag.count_item("rusted_sword") == sword_count and str(loadout.equipment_buttons.weapon.get_meta("item_id")).is_empty(), "Actual equipment double-click must unequip once and return the sword.")
	_check(player.get_body_health_snapshot() == body_before and not overlay.item_detail_window.is_open(), "Right equipment transactions must preserve actual body state.")


func _exercise_storage_equipment(viewport: SubViewport, overlay: InventoryOverlay, bag: ExpeditionInventory) -> void:
	for slot: String in ["waist_pouch", "backpack"]:
		var replacement := "pilgrim_waist_pouch" if slot == "waist_pouch" else "wanderer_backpack"
		var previous := str(bag.equipment[slot])
		bag.set_equipment_tag(slot, "오래된 장비")
		bag.add_item(replacement, 1, true, {"item_tag": "새 여행 장비"})
		var unrelated: Array = bag.slots.filter(func(stack: Dictionary) -> bool: return str(stack.id) != replacement).duplicate(true)
		var index := PREVIEW.HELPERS.find_slot(bag, replacement)
		await _point_click(viewport, overlay.combined_loadout_panel.inventory_buttons[index].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		_check(overlay.item_detail_window.equip_button.is_visible_in_tree(), "Storage gear must offer the real equip action: " + slot)
		await _click(viewport, overlay.item_detail_window.equip_button)
		_check(str(bag.equipment[slot]) == replacement and bag.count_item(previous) == 1 and ExpeditionInventory.get_item_tag(bag.get_equipment_instance(slot)) == "새 여행 장비", "Storage swap must equip the tagged replacement and return old gear: " + slot)
		var remaining: Array = bag.slots.filter(func(stack: Dictionary) -> bool: return str(stack.id) != previous)
		_check(remaining == unrelated, "Storage exchange must retain every unrelated item, quantity and tag: " + slot)
		var loadout := overlay.combined_loadout_panel
		_check(str(loadout.equipment_buttons[slot].get_meta("item_id")) == replacement and loadout.storage_equipment_labels[slot].text == ExpeditionInventory.get_item_name(replacement), "Equipped storage icon and container heading must immediately show the replacement.")
		await _key(viewport, KEY_ESCAPE)
		await _point_click(viewport, loadout.equipment_buttons[slot].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
		_check(overlay.item_detail_window.is_open() and overlay.item_detail_window.equip_button.disabled, "The new equipped slot must support inspection and show equipped state.")
		await _key(viewport, KEY_ESCAPE)
		await _double_click(viewport, loadout.equipment_buttons[slot])
		_check(str(bag.equipment[slot]).is_empty() and bag.count_item(replacement) == 1 and loadout.storage_equipment_labels[slot].text == "장착하지 않음", "Double-click must unequip storage safely and refresh both views.")


func _exercise_quick_use(viewport: SubViewport, fixture: Dictionary) -> void:
	var overlay: InventoryOverlay = fixture.overlay
	var player: DungeonPlayer = fixture.player
	var bag: ExpeditionInventory = fixture.bag
	var loadout := overlay.combined_loadout_panel
	# A deterministic set of ten real effects, independent of demo-loadout order.
	for stack: Dictionary in bag.slots.duplicate(true):
		bag.remove_item(str(stack.id), int(stack.quantity))
	for item_id: String in QUICK_ITEMS:
		bag.add_item(item_id, 3)
	overlay.refresh_status_readout()
	_check(loadout.quick_use_item_ids == QUICK_ITEMS, "Ten quick keys must follow the actual consumable order.")
	_prepare_quick_effect(player, "linen_bandage")
	overlay.refresh_status_readout()
	var first_index := PREVIEW.HELPERS.find_slot(bag, "linen_bandage")
	await _point_click(viewport, loadout.inventory_buttons[first_index].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	var protected_state := player.get_body_health_snapshot()
	await _key(viewport, KEY_1)
	_check(overlay.item_detail_window.is_open() and bag.count_item("linen_bandage") == 3 and player.get_body_health_snapshot() == protected_state, "Open item details must suppress an otherwise useful background quick-use key.")
	await _key(viewport, KEY_ESCAPE)
	_prepare_quick_effect(player, "boiled_rainwater")
	overlay.refresh_status_readout()
	var water_index: int = loadout.quick_use_item_ids.find("boiled_rainwater")
	var water_before := bag.count_item("boiled_rainwater")
	await _click(viewport, loadout.quick_use_buttons[water_index])
	_check(bag.count_item("boiled_rainwater") == water_before - 1 and ExpeditionSession.thirst == 58.0, "Actual quick-use button must consume water and restore thirst.")
	_check_meters(overlay, player)
	for index in QUICK_KEYS.size():
		var item_id: String = QUICK_ITEMS[index]
		_prepare_quick_effect(player, item_id)
		overlay.refresh_status_readout()
		var before_count := bag.count_item(item_id)
		var before_health := player.health
		var responses_before: int = fixture.responses.size()
		await _key(viewport, QUICK_KEYS[index])
		_check(fixture.responses.size() == responses_before + 1 and bool(fixture.responses.back().get("accepted", false)) and bag.count_item(item_id) == before_count - 1, "Actual %s key must consume its mapped item exactly once: %s" % [str((index + 1) % 10), item_id])
		var definition := ExpeditionInventory.get_item_definition(item_id)
		match str(definition.get("effect", "")):
			"heal", "bandage":
				_check(player.health > before_health, "Quick treatment must restore actual living health: " + item_id)
			"surgery":
				_check(player.get_body_health_snapshot().parts.left_arm.health == 1.0, "Actual surgery hotkey must restore zero to exactly one.")
			"cure_condition":
				_check(not ExpeditionSession.has_condition(str(definition.condition)), "Quick cure must remove its actual condition: " + item_id)
			"restore_hunger":
				_check(ExpeditionSession.hunger == 52.0, "Quick ration must restore hunger by 32.")
			"restore_thirst":
				_check(ExpeditionSession.thirst == 58.0, "Quick water must restore thirst by 38.")
		_check_meters(overlay, player)
		_check(overlay.health_panel.snapshot == player.get_body_health_snapshot(), "Quick use must update the actual rendered body snapshot.")
		_check(loadout.quick_use_item_ids == QUICK_ITEMS, "Remaining stacks must retain their ten-key mapping.")


func _prepare_quick_effect(player: DungeonPlayer, item_id: String) -> void:
	ExpeditionSession.clear_conditions()
	player.reset_body_health()
	player.select_treatment_part("")
	ExpeditionSession.hunger = 20.0
	ExpeditionSession.thirst = 20.0
	var definition := ExpeditionInventory.get_item_definition(item_id)
	match str(definition.get("effect", "")):
		"heal", "bandage":
			player.apply_body_damage("right_arm", 40.0)
			player.select_treatment_part("right_arm")
			if str(definition.effect) == "bandage":
				player.apply_condition("bleeding", 90.0, "right_arm")
		"surgery":
			player.apply_body_damage("left_arm", 60.0)
			player.select_treatment_part("left_arm")
		"cure_condition":
			player.apply_condition(str(definition.condition), 90.0, "right_leg")
			player.select_treatment_part("right_leg")


func _check_meters(overlay: InventoryOverlay, player: DungeonPlayer) -> void:
	var expected := {"hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stamina": player.stamina, "stress": ExpeditionSession.stress}
	for id in expected:
		_check(is_equal_approx(float(overlay.health_chrome.survival_bars[id].value), float(expected[id])), "Meter must immediately match production after quick use: " + str(id))


func _check_combined_bounds(viewport: SubViewport, overlay: InventoryOverlay) -> void:
	var frame := Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(1)
	var loadout := overlay.combined_loadout_panel
	_check(overlay.health_tab_active and overlay.health_panel.is_visible_in_tree() and overlay.health_chrome.is_visible_in_tree() and loadout.is_visible_in_tree(), "Actual health, equipment and storage must remain visible together.")
	_check(overlay.health_tab_button == overlay.equipment_tab_button, "Both old entry points must use one combined navigation button.")
	_check(loadout.inventory_buttons.size() == 30 and loadout.equipment_buttons.size() == ExpeditionInventory.EQUIPMENT_ORDER.size() and loadout.quick_use_buttons.size() == 10, "Combined page must expose all real bag, equipment and quick slots.")
	for control in [overlay.health_panel, overlay.health_chrome, loadout]:
		_check(frame.encloses(control.get_global_rect()), "Combined panel must fit the viewport: " + str(control.name))
	var boundary: Vector2 = overlay.modal_root.get_global_transform_with_canvas() * Vector2(640, 0)
	for button in loadout.inventory_buttons + loadout.quick_use_buttons + loadout.equipment_buttons.values():
		_check(button.is_visible_in_tree() and frame.encloses(button.get_global_rect()) and button.get_global_rect().position.x >= boundary.x, "Actual loadout cell must fit the right pane: " + str(button.name))
	for meter in overlay.health_chrome.survival_bars.values():
		_check(meter.size.y <= 10.0 and meter.position.y + meter.size.y <= 692.0, "Survival fill must fit its thin footer track.")


func _check_popup(viewport: SubViewport, panel: Control, player: DungeonPlayer) -> void:
	var popup: Control = panel.treatment_popup
	_check(popup.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(1).encloses(popup.get_global_rect()), "Treatment popup must be visible and fully reachable.")
	_check(popup.position.x + popup.size.x <= 625.0, "Treatment must stay in the left pane and leave right equipment reachable.")
	var selected := player.get_selected_treatment_part()
	if selected.is_empty():
		_check(not panel.selected_health_label.is_visible_in_tree(), "Automatic target must hide the previous part's count.")
		return
	var part: Dictionary = player.get_body_health_snapshot().parts[selected]
	_check(panel.selected_health_label.is_visible_in_tree() and panel.selected_health_label.text == "%d/%d" % [ceili(float(part.health)), roundi(float(part.max_health))], "Popup must show actual selected health even when covering another left body card.")


func _click(viewport: SubViewport, control: Control) -> void:
	_check(control.is_visible_in_tree(), "Pointer target must be visible: " + str(control.name))
	await _point_click(viewport, control.get_global_rect().get_center())


func _double_click(viewport: SubViewport, control: Control) -> void:
	await _click(viewport, control)
	await _point_click(viewport, control.get_global_rect().get_center(), MOUSE_BUTTON_LEFT, true)


func _point_click(viewport: SubViewport, point: Vector2, button: int = MOUSE_BUTTON_LEFT, double_click: bool = false) -> void:
	_check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point), "Pointer target must fit the viewport: " + str(point))
	viewport.gui_disable_input = false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = button
		event.button_mask = (MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT) if pressed else 0
		event.double_click = double_click and pressed
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	viewport.gui_disable_input = true


func _key(viewport: SubViewport, keycode: int) -> void:
	viewport.gui_disable_input = false
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	viewport.gui_disable_input = true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
