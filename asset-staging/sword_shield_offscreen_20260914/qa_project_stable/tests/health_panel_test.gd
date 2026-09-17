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
	_check(not overlay.health_tab_active and not overlay.health_panel.visible, "Inventory must start in its preserved equipment view.")
	overlay.health_tab_button.pressed.emit()
	await process_frame
	var panel := overlay.health_panel
	_check(overlay.health_tab_active and panel.is_visible_in_tree() and overlay.inventory_root.is_visible_in_tree(), "Health tab must display the real panel and retain the bag.")
	_check(panel.part_buttons.size() == 7 and panel.total_label.text == "350 / 440", "Health panel must show all seven actual part values and total.")
	_check(panel.part_buttons.left_arm.get_meta("blacked") and panel.part_condition_labels.left_arm.text.contains("일반 치료 불가"), "Zero-health arm must expose its blacked state and normal-healing restriction.")
	for expected in ["골절", "출혈", "저주", "마비", "독"]:
		_check(panel.conditions_label.text.contains(expected), "Health panel must name the actual condition: " + expected)
	_check(panel.part_condition_labels.left_leg.text.contains("골절"), "A local fracture must appear on its own body-part card.")
	panel.part_buttons.left_arm.pressed.emit()
	_check(state.selected_part == "left_arm" and panel.part_buttons.left_arm.get_meta("selected"), "Selecting a part must emit through inventory and refresh the actual selected outline.")
	_check(panel.guidance_label.text.contains("1까지 복구"), "Destroyed-part selection must explain surgery/high-level restoration before healing.")
	_check(panel.treatment_buttons.size() == 7, "The panel must list actual owned treatment definitions.")
	panel.treatment_buttons.surgery_kit.pressed.emit()
	_check(consumables == ["surgery_kit"], "Treatment button must request the actual inventory consumable, not mutate a fake health value.")
	panel.automatic_button.pressed.emit()
	_check(state.selected_part.is_empty() and panel.selected_label.text.contains("자동"), "Automatic target button must clear explicit treatment selection.")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = panel.FIGURE_ORIGIN + panel.PART_CENTERS.thorax
	panel.gui_input.emit(event)
	_check(state.selected_part == "thorax", "Clicking the actual silhouette must select that body part.")
	bag.remove_item("surgery_kit", 3)
	_check(not panel.treatment_buttons.has("surgery_kit"), "Exhausted treatment stacks must disappear after real bag changes.")
	var before_body := state.duplicate(true)
	overlay.equipment_tab_button.pressed.emit()
	_check(not panel.visible and overlay.equipment_root.is_visible_in_tree() and overlay.inventory_root.position == Vector2(640, 47), "Equipment tab must restore the original bag-only layout.")
	_check(state == before_body, "Switching tabs must not change health, selected target or conditions.")
	overlay.open_health_tab()
	viewport.size = Vector2i(960, 540)
	await process_frame
	await process_frame
	var frame := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(frame.encloses(overlay.health_panel.get_global_rect()) and frame.encloses(overlay.inventory_root.get_global_rect()), "Small viewport must retain both full health and bag panels within bounds.")
	overlay.open_equipment_tab()
	_check(overlay.modal_root.scale == Vector2.ONE, "Leaving health view must restore the established inventory scale.")
	viewport.free()
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and ExpeditionSession.get_inventory() == original_bag and Input.mouse_mode == mouse_before, "UI tests must preserve original expedition, inventory identity and cursor.")
	for failure in failures:
		push_error(failure)
	print("HEALTH PANEL TEST %s: seven actual parts, targeted treatment signals, local/global conditions, silhouette input, tab restoration and responsive bounds" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
