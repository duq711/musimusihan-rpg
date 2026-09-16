extends SceneTree

const BODY := preload("res://scripts/body_health.gd")
const DETAILS_PREVIEW := preload("res://tests/item_detail_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var bag := ExpeditionInventory.new()
	for item_id in ["linen_bandage", "healing_draught", "surgery_kit", "splint", "antidote", "purifying_salt", "nerve_tonic"]:
		bag.add_item(item_id, 3, false)
	bag.add_item("rusted_sword", 1, false)
	var state := BODY.create_state()
	var conditions := {"fracture": 40.0, "bleeding": 20.0, "curse": 50.0, "paralysis": 15.0, "poison": 30.0}
	state.condition_parts = {"fracture": ["left_leg"], "bleeding": ["left_arm"]}
	BODY.damage(state, "left_arm", 60)
	BODY.damage(state, "left_leg", 30)
	var provider := func() -> Dictionary: return {"health": BODY.total_health(state), "max_health": 440.0, "body_health": BODY.snapshot(state, conditions)}
	var viewport := DETAILS_PREVIEW.create_viewport(Vector2i(1280, 720))
	root.add_child(viewport)
	var overlay := InventoryOverlay.new()
	viewport.add_child(overlay)
	overlay.open_inventory(bag, provider)
	overlay.treatment_part_selected.connect(func(part_id: String) -> void: state.selected_part = part_id)
	var consumables: Array[String] = []
	overlay.consumable_requested.connect(func(item_id: String) -> void: consumables.append(item_id))
	await process_frame
	var panel := overlay.health_panel
	var loadout := overlay.combined_loadout_panel
	_check(overlay.health_tab_active and panel.is_visible_in_tree() and loadout.is_visible_in_tree() and overlay.health_chrome.is_visible_in_tree(), "Opening inventory must immediately show actual health, equipment, bag and survival meters together.")
	_check(loadout.inventory_buttons.size() == 30 and loadout.equipment_buttons.size() == ExpeditionInventory.EQUIPMENT_ORDER.size() and loadout.quick_use_buttons.size() == 10 and loadout.quick_use_item_ids.size() == 10, "Combined loadout must expose thirty real bag cells, seven equipment slots and ten quick-use slots.")
	_check_loadout_binding(loadout, bag)
	_check(not panel.treatment_popup.is_visible_in_tree(), "Opening health must leave the figure unobstructed until a body part is selected.")
	_check(overlay.health_chrome.KEYS == ["overview", "equipment", "skills", "map", "quests"] and overlay.health_tab_button == overlay.equipment_tab_button and overlay.equipment_tab_button.text == "장비·건강상태", "Equipment and health must share one physical navigation tab while preserving the reference's other sections.")
	for meter in overlay.health_chrome.survival_bars.values():
		_check(meter.size.y <= 10.0 and meter.position.y + meter.size.y <= 692.0, "Survival fills must remain inside their authored ten-pixel tracks and lower frame.")
	_check(panel.part_buttons.size() == 7 and panel.total_label.text == "350 / 440", "Health panel must show all seven actual part values and total.")
	_check(panel.selected_label.get_theme_font("font") == panel.theme.default_font and panel.theme.default_font is FontVariation and panel.theme.default_font.base_font.resource_path == "res://assets/fonts/NotoSerifKR-Variable.ttf", "Health labels must use the authored readable Korean serif font.")
	for part_id in panel.PART_ORDER:
		_check(panel.part_bars[part_id].size.y >= 10.0, "Reference health cards must show substantial readable health bars: " + part_id)
		_check(panel.part_bars[part_id].value == panel.snapshot.parts[part_id].health and panel.part_bars[part_id].max_value == panel.snapshot.parts[part_id].max_health, "Rendered health fill must match the real selected part values: " + part_id)
		_check(not panel.part_bars[part_id].get_global_rect().intersects(panel.part_value_labels[part_id].get_global_rect()), "Health bars must not cover their numerical readouts: " + part_id)
	_check(panel.part_buttons.left_arm.get_meta("blacked") and panel.part_condition_labels.left_arm.text.contains("일반 치료 불가"), "Zero-health arm must expose its blacked state and normal-healing restriction.")
	for expected in ["골절", "출혈", "저주", "마비", "독"]:
		_check(panel.conditions_label.text.contains(expected), "Health panel must name the actual condition: " + expected)
	_check(panel.part_condition_labels.left_leg.text.contains("골절"), "A local fracture must appear on its own body-part card.")
	panel.part_buttons.left_arm.pressed.emit()
	_check(state.selected_part == "left_arm" and panel.part_buttons.left_arm.get_meta("selected"), "Selecting a part must emit through inventory and refresh the actual selected outline.")
	_check(panel.treatment_popup.is_visible_in_tree() and panel.treatment_buttons.surgery_kit.is_visible_in_tree(), "Selecting a part must reveal the actual owned treatments in the popup.")
	_check(panel.treatment_popup.position.x + panel.treatment_popup.size.x <= 625.0 and not panel.treatment_popup.get_global_rect().intersects(loadout.inventory_buttons[0].get_global_rect()), "Treatment popup must stay in the left health area and leave the actual right bag reachable.")
	_check(panel.selected_health_label.is_visible_in_tree() and panel.selected_health_label.text == "0/60", "Treatment popup must repeat the selected part's exact health in its title area.")
	_check(panel.guidance_label.text.contains("1까지 복구"), "Destroyed-part selection must explain surgery/high-level restoration before healing.")
	_check(panel.treatment_buttons.size() == 7, "The panel must list actual owned treatment definitions.")
	panel.treatment_buttons.surgery_kit.pressed.emit()
	_check(consumables == ["surgery_kit"], "Treatment button must request the actual inventory consumable, not mutate a fake health value.")
	_check(panel.treatment_popup.is_visible_in_tree(), "Treatment must keep its popup open for subsequent healing.")
	panel.automatic_button.pressed.emit()
	_check(state.selected_part.is_empty() and panel.selected_label.text.contains("자동"), "Automatic target button must clear explicit treatment selection.")
	_check(not panel.selected_health_label.is_visible_in_tree(), "Automatic target must not display a stale selected-part health value.")
	panel.popup_close_button.pressed.emit()
	_check(not panel.treatment_popup.is_visible_in_tree(), "The popup close action must restore the unobstructed body view.")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = panel.FIGURE_ORIGIN + panel.PART_CENTERS.thorax
	panel._gui_input(event)
	_check(state.selected_part == "thorax", "Clicking the actual silhouette must select that body part.")
	bag.remove_item("surgery_kit", 3)
	_check(not panel.treatment_buttons.has("surgery_kit"), "Exhausted treatment stacks must disappear after real bag changes.")
	_check("surgery_kit" not in loadout.quick_use_item_ids, "Quick-use slots must remove exhausted real consumables.")
	_check_loadout_binding(loadout, bag)
	var before_body := state.duplicate(true)
	overlay.equipment_tab_button.pressed.emit()
	_check(overlay.health_tab_active and panel.is_visible_in_tree() and loadout.is_visible_in_tree() and overlay.health_chrome.is_visible_in_tree() and not panel.treatment_popup.is_visible_in_tree(), "The equipment entry point must retain the combined view and close only transient treatment presentation.")
	_check(state == before_body, "Reopening the combined tab must not change health, selected target or conditions.")
	overlay.open_health_tab()
	viewport.size = Vector2i(960, 540)
	await process_frame
	await process_frame
	var frame := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(frame.grow(1).encloses(panel.get_global_rect()) and frame.grow(1).encloses(overlay.health_chrome.get_global_rect()) and frame.grow(1).encloses(loadout.get_global_rect()) and loadout.is_visible_in_tree(), "Small viewport must fit the complete simultaneous health and real loadout composition.")
	for button in loadout.inventory_buttons + loadout.quick_use_buttons:
		_check(frame.grow(1).encloses(button.get_global_rect()), "Every actual storage and quick-use cell must fit 960x540: " + str(button.name))
	for button in loadout.equipment_buttons.values():
		_check(frame.grow(1).encloses(button.get_global_rect()), "Every actual equipment slot must fit 960x540: " + str(button.name))
	panel.part_buttons.left_arm.pressed.emit()
	await process_frame
	_check(frame.grow(1).encloses(panel.treatment_popup.get_global_rect()), "Treatment popup must remain fully reachable at 960x540.")
	overlay.open_equipment_tab()
	_check(overlay.modal_root.scale == Vector2.ONE * 0.75 and panel.is_visible_in_tree() and loadout.is_visible_in_tree(), "Both inventory entry points must keep the same combined scale at 960x540.")
	viewport.free()
	await process_frame
	var hud := DungeonHUD.new()
	root.add_child(hud)
	await process_frame
	hud.update_magic(SpellCatalog.SPELL_ORDER, "restorative_light", true)
	hud.update_conditions(conditions)
	_check(hud.magic_slots_label.text.contains("[6]") and hud.magic_slots_label.get_minimum_size().x <= 576, "All six actual spells must fit the existing HUD selector width.")
	_check(hud.control_legend_label.text.contains("1~6") and hud.condition_label.text.contains("마비") and hud.condition_label.text.contains("독"), "HUD must advertise six spell keys and both new global conditions.")
	_check(hud.health_bar.max_value == 440 and hud.health_label.text.contains("440 / 440"), "HUD's initial health label and meter must agree with the production total.")
	hud.free()
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and ExpeditionSession.capture_snapshot().inventory == original_bag and Input.mouse_mode == mouse_before, "UI tests must preserve original expedition, inventory identity and cursor.")
	for failure in failures:
		push_error(failure)
	print("HEALTH PANEL TEST %s: simultaneous actual health/loadout, 30 bag cells, seven equipped slots, ten quick slots, treatment signals, conditions, silhouette input, shared navigation and responsive bounds" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check_loadout_binding(loadout: Control, bag: ExpeditionInventory) -> void:
	for index in loadout.inventory_buttons.size():
		var item_id := str(bag.slots[index].id) if index < bag.slots.size() else ""
		_check(str(loadout.inventory_buttons[index].get_meta("item_id")) == item_id, "Combined cell must follow the actual bag slot after a transaction: %d" % index)
	for slot in loadout.equipment_buttons:
		_check(str(loadout.equipment_buttons[slot].get_meta("item_id")) == str(bag.equipment.get(slot, "")), "Combined equipment must follow the actual equipped item: " + str(slot))
	for index in loadout.quick_use_item_ids.size():
		var item_id := str(loadout.quick_use_item_ids[index])
		_check(item_id.is_empty() or (bag.count_item(item_id) > 0 and str(ExpeditionInventory.get_item_definition(item_id).get("category", "")) == "consumable"), "Quick use may reference only actual owned consumables: %d" % index)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
