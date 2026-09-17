extends SceneTree
## Real GUI routing inside an isolated viewport; never inject OS/global input.
const PREVIEW := preload("res://tests/item_detail_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var fingerprint := PREVIEW.PRESERVATION.inventory_fingerprint(original_bag)
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.PRESERVATION.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var original_root_gui_disabled := root.gui_disable_input
	var original_root_picking := root.physics_object_picking
	var original_muted := AudioServer.is_bus_mute(0)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	await _check_real_gui(Vector2i(1280, 720), "rusted_sword", true)
	await _check_real_gui(Vector2i(960, 540), "linen_bandage", false)
	sandbox.finish()
	var restored := ExpeditionSession.capture_snapshot()
	check(restored == original and restored.inventory == original_bag and PREVIEW.PRESERVATION.inventory_fingerprint(original_bag) == fingerprint, "Synthetic input must preserve the exact original expedition and inventory identity/content.")
	check(PREVIEW.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before and Input.mouse_mode == mouse_before, "Synthetic viewport input must preserve sandbox state and OS mouse mode.")
	root.gui_disable_input = original_root_gui_disabled
	root.physics_object_picking = original_root_picking
	AudioServer.set_bus_mute(0, original_muted)
	for failure in failures:
		push_error(failure)
	print("ITEM DETAIL INPUT TEST %s: actual viewport mouse routing, Korean typing, save/Enter/Esc, equip/discard, 1280 and 960 layouts, background isolation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _check_real_gui(image_size: Vector2i, item_id: String, equipment: bool) -> void:
	var viewport := PREVIEW.create_viewport(image_size)
	root.add_child(viewport)
	var bag := PREVIEW.create_inventory()
	var overlay := InventoryOverlay.new()
	viewport.add_child(overlay)
	overlay.open_inventory(bag)
	overlay.set_process(false)
	var dropped: Array[Dictionary] = []
	overlay.item_discarded.connect(func(stack: Dictionary) -> void: dropped.append(stack.duplicate(true)))
	var index := PREVIEW.find_slot(bag, item_id)
	check(overlay.open_item_details("inventory", index), "Production item details must open before GUI routing checks.")
	for frame in 3:
		await process_frame
	var detail := overlay.item_detail_window
	var portrait_angle := float(overlay.player_portrait.call("get_view_angle"))
	check(detail.z_index > overlay.detail_root.z_index and detail.z_index > overlay.player_portrait.z_index, "Detail panel must retain its production stacking priority above item hints and portrait.")
	var resolved_font := detail.title_label.get_theme_font("font")
	var base_font: Font = resolved_font.base_font if resolved_font is FontVariation else resolved_font
	check(base_font == detail.UI_FONT and base_font.has_char("가".unicode_at(0)), "Production detail labels must resolve the Korean UI font and retain Hangul glyphs.")
	check(Rect2(Vector2.ZERO, Vector2(image_size)).grow(1.0).encloses(detail.window_root.get_global_rect()), "Actual detail panel must fit the test viewport before clicking.")
	await _click(viewport, detail.tag_button)
	check(detail.tag_editor.visible, "Pointer hit on the actual name-tag button must open its editor at %s." % image_size)
	await _click(viewport, detail.tag_edit)
	check(viewport.gui_get_focus_owner() == detail.tag_edit, "Pointer hit must focus the actual name field without focusing the OS window.")
	var expected_tag := "보급 검" if equipment else "비상 붕대"
	await _type_text(viewport, expected_tag)
	check(detail.tag_edit.text == expected_tag, "Synthetic Korean text must route into the real editor at %s." % image_size)
	await _click(viewport, detail.tag_save_button)
	check(not detail.tag_editor.visible and detail.tag_label.text == expected_tag and ExpeditionInventory.get_item_tag(bag.slots[index].get("instance", {})) == expected_tag, "Actual Save hit target must commit the name and update the authoritative inventory.")
	await _click(viewport, detail.tag_button)
	await _click(viewport, detail.tag_edit)
	await _key(viewport, KEY_ENTER)
	check(not detail.tag_editor.visible and detail.is_open() and detail.tag_label.text == expected_tag, "Enter from the actual name field must commit through text_submitted and retain inspection.")
	await _click(viewport, detail.tag_button)
	await _key(viewport, KEY_ESCAPE)
	check(not detail.tag_editor.visible and detail.is_open(), "First real Esc event must cancel the subeditor while retaining inspection.")
	await _key(viewport, KEY_ESCAPE)
	check(not detail.is_open() and overlay.is_open(), "Second real Esc event must close inspection while retaining the inventory.")
	check(overlay.open_item_details("inventory", index), "The same item must reopen after actual keyboard dismissal.")
	await process_frame
	if equipment:
		await _click(viewport, detail.equip_button)
		check(bag.equipment.weapon == item_id and detail.equip_button.disabled and detail.equip_button.text == "장착 중", "Actual equipment button hit target must equip the named weapon and show equipped state.")
		check(ExpeditionInventory.get_item_tag(bag.get_equipment_instance("weapon")) == expected_tag, "Actual equip pointer flow must retain the name tag.")
	else:
		check(not detail.equip_button.visible, "Non-equipment detail must omit the equipment hit target.")
	var before_count := bag.count_item(item_id)
	await _click(viewport, detail.discard_button)
	check(detail.discard_editor.visible, "Actual discard pointer hit must open the quantity editor above inventory content.")
	if not equipment:
		detail.discard_quantity.value = 2
	await _click(viewport, detail.discard_confirm_button)
	var expected_quantity := 1 if equipment else 2
	check(dropped.size() == 1 and dropped[0].id == item_id and dropped[0].quantity == expected_quantity and ExpeditionInventory.get_item_tag(dropped[0].get("instance", {})) == expected_tag, "Actual discard confirmation hit target must emit the exact named item and selected quantity.")
	check((bag.equipment.weapon == "" if equipment else bag.count_item(item_id) == before_count - 2) and not detail.is_open(), "Actual discard must change owned inventory state and dismiss inspection.")
	check(float(overlay.player_portrait.call("get_view_angle")) == portrait_angle, "Details and editor pointer events must never reach the background portrait controls.")
	check(root.gui_disable_input and viewport.gui_disable_input and not viewport.physics_object_picking, "Only the local synthetic event dispatch may temporarily enable its viewport GUI input.")
	viewport.free()
	await process_frame


func _click(viewport: SubViewport, control: Control) -> void:
	check(control.is_visible_in_tree(), "Synthetic pointer target must be visible: " + str(control.name))
	var center := control.get_global_rect().get_center()
	check(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(center), "Synthetic pointer target must be inside viewport: " + str(control.name))
	viewport.gui_disable_input = false
	var motion := InputEventMouseMotion.new()
	motion.position = center
	motion.global_position = center
	viewport.push_input(motion, true)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = center
		click.global_position = center
		click.button_index = MOUSE_BUTTON_LEFT
		click.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		click.pressed = pressed
		viewport.push_input(click, true)
		await process_frame
	viewport.gui_disable_input = true


func _type_text(viewport: SubViewport, text: String) -> void:
	for index in text.length():
		await _key(viewport, text.unicode_at(index), text.unicode_at(index))


func _key(viewport: SubViewport, keycode: int, unicode: int = 0) -> void:
	viewport.gui_disable_input = false
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.unicode = unicode
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	viewport.gui_disable_input = true


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
