extends SceneTree
## Production inventory and item inspection only, in an isolated SubViewport.
## No world, native window, external input or desktop image is created.

const PERFORMANCE := preload("res://tests/performance_preview.gd")
const PRESERVATION := preload("res://tests/hideout_ruin_preview.gd")
const APPEARANCE := preload("res://scripts/player_appearance.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/item_details"
const SAVED_TAG := "먼 길의 비상 붕대"


func _init() -> void:
	call_deferred("_run")


static func shots() -> Array[Dictionary]:
	return [
		{"id": "01_weapon_details", "item_id": "rusted_sword", "size": Vector2i(1280, 720), "action": "inspect"},
		{"id": "02_armor_details", "item_id": "patched_mail", "size": Vector2i(1280, 720), "action": "inspect"},
		{"id": "03_bandage_name_saved", "item_id": "linen_bandage", "size": Vector2i(1280, 720), "action": "save_tag"},
		{"id": "04_bandage_discard_quantity", "item_id": "linen_bandage", "size": Vector2i(1280, 720), "action": "discard_editor"},
		{"id": "05_material_small_window", "item_id": "iron_ingot", "size": Vector2i(960, 540), "action": "inspect"},
	]


static func create_viewport(image_size: Vector2i) -> SubViewport:
	var viewport := PERFORMANCE.create_viewport(image_size)
	viewport.name = "IsolatedProductionItemDetails"
	return viewport


static func create_inventory() -> ExpeditionInventory:
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	bag.add_item("rusted_sword", 1, false)
	bag.add_item("patched_mail", 1, false)
	bag.add_item("linen_bandage", 3, false)
	bag.add_item("iron_ingot", 4, false)
	return bag


static func create_overlay(viewport: SubViewport, bag: ExpeditionInventory) -> InventoryOverlay:
	var overlay := InventoryOverlay.new()
	viewport.add_child(overlay)
	overlay.open_inventory(bag)
	stop_external_execution(overlay)
	return overlay


static func stop_external_execution(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_shortcut_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	if node is Viewport:
		node.gui_disable_input = true
		node.physics_object_picking = false
		node.audio_listener_enable_2d = false
		node.audio_listener_enable_3d = false
	for child in node.get_children():
		stop_external_execution(child)


static func execution_isolated(node: Node) -> bool:
	if node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_shortcut_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input():
		return false
	if node is Viewport and (not node.gui_disable_input or node.physics_object_picking or node.audio_listener_enable_2d or node.audio_listener_enable_3d):
		return false
	for child in node.get_children():
		if not execution_isolated(child):
			return false
	return true


static func configure_shot(overlay: InventoryOverlay, shot: Dictionary) -> Dictionary:
	var bag := overlay.inventory_model
	var index := find_slot(bag, str(shot.item_id))
	var result := {"opened": overlay.open_item_details("inventory", index), "action": str(shot.action), "action_verified": true, "model_index": index}
	if not result.opened:
		result.action_verified = false
		return result
	var detail := overlay.item_detail_window
	match str(shot.action):
		"save_tag":
			# Exercise the actual editor signals and inventory callback. The
			# harness never supplies a fabricated label or presentation payload.
			detail.tag_button.pressed.emit()
			detail.tag_edit.text = SAVED_TAG
			detail.tag_save_button.pressed.emit()
			result.action_verified = ExpeditionInventory.get_item_tag(bag.slots[index].get("instance", {})) == SAVED_TAG and detail.tag_label.text == SAVED_TAG and not detail.tag_editor.visible
		"discard_editor":
			detail.discard_button.pressed.emit()
			detail.discard_quantity.value = 2
			result.action_verified = detail.discard_editor.visible and detail.discard_quantity.value == 2 and detail.discard_quantity.max_value == bag.slots[index].quantity
	return result


static func inspect_shot(viewport: SubViewport, overlay: InventoryOverlay, shot: Dictionary, action: Dictionary) -> Dictionary:
	var detail := overlay.item_detail_window
	var definition := ExpeditionInventory.get_item_definition(str(shot.item_id))
	var equip_expected := not str(definition.get("equip_slot", "")).is_empty()
	var failures: Array[String] = []
	if not bool(action.get("opened", false)) or not detail.is_open():
		failures.append("Actual inventory item inspection did not open.")
	if not bool(action.get("action_verified", false)):
		failures.append("Real editor signals failed to perform the intended action.")
	if detail.title_label.text != str(definition.get("name", "")) or detail.description_label.text != str(definition.get("description", "")):
		failures.append("Item name or description differs from the source catalog.")
	if detail.item_art.texture == null:
		failures.append("Actual inventory artwork is missing.")
	if detail.equip_button.is_visible_in_tree() != equip_expected or (equip_expected and detail.equip_button.disabled):
		failures.append("Equip action visibility does not match the selected item category.")
	if not detail.tag_button.is_visible_in_tree() or detail.tag_button.disabled or not detail.discard_button.is_visible_in_tree() or detail.discard_button.disabled:
		failures.append("Owned item must expose usable name-tag and discard actions.")
	var button_labels: Array[String] = []
	for node in detail.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.contains("검색") or button.text.contains("보험"):
			failures.append("Reference-only search or insurance action appeared in the production detail window.")
		if button.is_visible_in_tree():
			button_labels.append(button.text)
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var panel_rect := detail.window_root.get_global_rect()
	if not bounds.grow(1.0).encloses(panel_rect):
		failures.append("Responsive detail window extends outside the capture viewport.")
	var portrait := overlay.player_portrait
	var body := portrait.get("body") as Node3D
	var portrait_retained := is_instance_valid(body) and str(body.get_meta("model_path", "")) == APPEARANCE.MODEL_PATH and portrait.is_visible_in_tree()
	if not portrait_retained:
		failures.append("The original production character portrait was replaced or hidden.")
	if not execution_isolated(overlay) or not viewport.gui_disable_input or viewport.physics_object_picking or viewport.audio_listener_enable_2d or viewport.audio_listener_enable_3d:
		failures.append("Preview still accepts external input, gameplay updates or audio.")
	return {"item_id": str(shot.item_id), "title": detail.title_label.text, "visible_buttons": button_labels, "equip_visible": detail.equip_button.is_visible_in_tree(), "equip_expected": equip_expected, "tag_text": detail.tag_label.text, "discard_editor_visible": detail.discard_editor.visible, "discard_quantity": detail.discard_quantity.value, "description_from_catalog": detail.description_label.text == str(definition.get("description", "")), "panel_rect": str(panel_rect), "production_portrait_retained": portrait_retained, "action": action, "harness_changes_presentation": false, "failures": failures}


static func find_slot(bag: ExpeditionInventory, item_id: String) -> int:
	for index in bag.slots.size():
		if str(bag.slots[index].get("id", "")) == item_id:
			return index
	return -1


static func collect_source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["res://project.godot", "res://scripts/inventory_overlay.gd", "res://scripts/item_detail_window.gd", "res://scripts/inventory_model.gd", "res://scripts/loot_container.gd", "res://scripts/player_portrait.gd", "res://scripts/player_appearance.gd", "res://scripts/expedition_session.gd", "res://scripts/test_room_sandbox.gd", "res://assets/fonts/NotoSansKR-Variable.ttf", "res://assets/ui/inventory_item_atlas.png", APPEARANCE.MODEL_PATH, "res://tests/item_detail_preview.gd", "res://tests/performance_preview.gd", "res://tests/hideout_ruin_preview.gd", "res://tests/run_embedded_preview.sh"]:
		hashes[path] = FileAccess.get_sha256(path)
	for shot in shots():
		var path := str(ExpeditionInventory.get_item_definition(str(shot.item_id)).get("icon_path", ""))
		if not path.is_empty():
			hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Item detail captures require the audited run_embedded_preview.sh item_detail_preview.gd renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("ITEM_DETAIL_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Choose a new safe ITEM_DETAIL_QA_ITERATION folder name.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Existing item-detail evidence is preserved; choose a new iteration.")
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Item detail preview requires a fresh isolated process.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := PRESERVATION.inventory_fingerprint(original_bag)
	var sandbox_before := PRESERVATION.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var paused_before := paused
	var hashes := collect_source_hashes()
	var failures: Array[String] = []
	var captures: Array[Dictionary] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	for shot in shots():
		var viewport := create_viewport(shot.size)
		root.add_child(viewport)
		var overlay := create_overlay(viewport, create_inventory())
		var action := configure_shot(overlay, shot)
		for frame in 24:
			await process_frame
		var state := inspect_shot(viewport, overlay, shot, action)
		for failure in state.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var image_path := output.path_join(str(shot.id) + ".png")
		var saved := pixels != null and not pixels.is_empty() and pixels.save_png(image_path) == OK
		if not saved:
			failures.append("Real renderer failed to save " + str(shot.id))
		state["image"] = {"file": image_path.get_file(), "size": [viewport.size.x, viewport.size.y], "sha256": FileAccess.get_sha256(image_path) if saved else ""}
		captures.append(state)
		viewport.free()
		await process_frame
	sandbox.finish()
	paused = paused_before
	var restored := ExpeditionSession.capture_snapshot()
	var preserved: bool = restored == original and restored.inventory == original_bag and PRESERVATION.inventory_fingerprint(original_bag) == original_bag_hash and Input.mouse_mode == mouse_before
	var sandbox_preserved := PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before
	var sources_unchanged := collect_source_hashes() == hashes
	if not preserved or not sandbox_preserved:
		failures.append("Original expedition, inventory identity/content, sandbox or cursor changed.")
	if not sources_unchanged:
		failures.append("Source files changed during capture; use a new iteration after all edits settle.")
	for path in hashes:
		if str(hashes[path]).is_empty():
			failures.append("Source hash missing: " + str(path))
	var manifest := {"capture_kind": "Unretouched production InventoryOverlay and ItemDetailWindow, using independent real inventory fixtures", "display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "gameplay_world_created": false, "production_portrait_world_retained": true, "source_sha256": hashes, "source_files_unchanged": sources_unchanged, "expedition_inventory_and_cursor_preserved": preserved, "sandbox_preserved": sandbox_preserved, "captures": captures, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write item detail capture manifest.")
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	for failure in failures:
		push_error(failure)
	print("ITEM DETAIL PREVIEW %s: %d actual inventory/detail captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)
