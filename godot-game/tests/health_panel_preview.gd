extends SceneTree
## The production health tab and consumable callbacks run in an isolated
## SubViewport. A detached production player owns the real treatment state.

const HELPERS := preload("res://tests/item_detail_preview.gd")
const BODY := preload("res://scripts/body_health.gd")
const STATUS_CONTROLS := preload("res://scripts/test_room_status_controls.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/body_health"


func _init() -> void:
	call_deferred("_run")


static func shots() -> Array[Dictionary]:
	return [
		{"id": "01_full_health", "size": Vector2i(1280, 720), "action": "healthy"},
		{"id": "02_full_health_small", "size": Vector2i(960, 540), "action": "healthy"},
		{"id": "03_injured_arm_selected", "size": Vector2i(1280, 720), "action": "injured"},
		{"id": "04_surgery_restored_to_one", "size": Vector2i(1280, 720), "action": "surgery"},
		{"id": "05_treated_small_viewport", "size": Vector2i(960, 540), "action": "heal"},
		{"id": "06_treatment_popup_closed", "size": Vector2i(1280, 720), "action": "closed"},
		{"id": "07_equipment_selected", "size": Vector2i(1280, 720), "action": "equipment"},
		{"id": "08_test_room_body_controls", "size": Vector2i(1280, 720), "action": "controls"},
		{"id": "09_test_room_controls_small", "size": Vector2i(960, 540), "action": "controls"},
		{"id": "10_item_details_small", "size": Vector2i(960, 540), "action": "details"},
		{"id": "11_quick_use_applied", "size": Vector2i(1280, 720), "action": "quick_use"},
		{"id": "12_storage_equipment_swapped", "size": Vector2i(1280, 720), "action": "storage_swapped"},
		{"id": "13_backpack_details_small", "size": Vector2i(960, 540), "action": "storage_details"}
	]


static func create_fixture(viewport: SubViewport, shot: Dictionary) -> Dictionary:
	ExpeditionSession.clear_conditions()
	ExpeditionSession.hunger = 72.0
	ExpeditionSession.thirst = 64.0
	ExpeditionSession.stress = 24.0
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	bag.add_item("rusted_sword", 1, false)
	for item_id in ["linen_bandage", "healing_draught", "surgery_kit", "splint", "antidote", "purifying_salt", "nerve_tonic"]:
		bag.remove_item(item_id, bag.count_item(item_id), false)
		bag.add_item(item_id, 3, false)
	var player := DungeonPlayer.new()
	player.inventory_model = bag
	player.stamina = 83.0
	var overlay := InventoryOverlay.new()
	viewport.add_child(overlay)
	var responses: Array[Dictionary] = []
	overlay.treatment_part_selected.connect(player.select_treatment_part)
	overlay.consumable_requested.connect(func(item_id: String) -> void:
		var result := player.use_consumable(item_id, bag)
		responses.append(result.duplicate(true))
		overlay.set_status(str(result.get("message", "")))
	)
	if str(shot.action) not in ["healthy", "storage_swapped", "storage_details"]:
		player.apply_body_damage("left_arm", 60)
		player.apply_body_damage("left_leg", 30)
		player.apply_condition("fracture", 90, "left_leg")
		player.apply_condition("bleeding", 90, "left_arm")
		player.apply_condition("curse", 90)
		player.apply_condition("poison", 90)
		player.apply_condition("paralysis", 90)
	ExpeditionSession.stress = 24.0
	overlay.open_inventory(bag, player.get_inventory_status_snapshot)
	overlay.open_health_tab()
	if str(shot.action) not in ["healthy", "storage_swapped", "storage_details"]:
		overlay.health_panel.part_buttons.left_arm.pressed.emit()
	if str(shot.action) in ["surgery", "heal"]:
		overlay.health_panel.treatment_buttons.surgery_kit.pressed.emit()
	if str(shot.action) == "heal":
		overlay.health_panel.treatment_buttons.healing_draught.pressed.emit()
	if str(shot.action) in ["closed", "equipment", "details", "quick_use"]:
		overlay.health_panel.popup_close_button.pressed.emit()
	if str(shot.action) == "equipment":
		overlay.equipment_tab_button.pressed.emit()
		overlay.combined_loadout_panel.equipment_buttons.body.pressed.emit()
	if str(shot.action) == "details":
		overlay.open_item_details("inventory", HELPERS.find_slot(bag, "rusted_sword"))
	if str(shot.action) == "quick_use":
		var quick_index := overlay.combined_loadout_panel.quick_use_item_ids.find("boiled_rainwater")
		overlay.combined_loadout_panel.quick_use_buttons[quick_index].pressed.emit()
	if str(shot.action) in ["storage_swapped", "storage_details"]:
		for id in ["pilgrim_waist_pouch", "wanderer_backpack"]:
			bag.add_item(id)
			overlay.open_item_details("inventory", HELPERS.find_slot(bag, id))
			overlay.item_detail_window.equip_button.pressed.emit()
			overlay._dismiss_item_details()
		overlay.set_status("허리 파우치·배낭 교체 완료 · 기존 장비와 소지품은 가방에 유지됩니다")
		if str(shot.action) == "storage_details":
			overlay.open_item_details("equipment", -1, "backpack")
	HELPERS.stop_external_execution(overlay)
	var fixture := {"overlay": overlay, "player": player, "bag": bag, "responses": responses}
	if str(shot.action) == "controls":
		overlay.overlay_root.visible = false
		var background := ColorRect.new()
		background.color = Color(0.012, 0.020, 0.017)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport.add_child(background)
		var controls := STATUS_CONTROLS.new()
		controls.position = Vector2((float(viewport.size.x) - 790) * 0.5, 25 if viewport.size.y < 600 else 97)
		controls.size = Vector2(790, 435)
		viewport.add_child(controls)
		controls.body_part_selected.connect(func(part_id: String) -> void:
			player.select_treatment_part(part_id)
			controls.set_snapshot(_status_controls_snapshot(player))
		)
		controls.body_damage_requested.connect(func(part_id: String, amount: float) -> void:
			player.apply_body_damage(part_id, amount)
			controls.set_snapshot(_status_controls_snapshot(player))
		)
		controls.body_reset_requested.connect(func() -> void:
			player.reset_body_health()
			controls.set_snapshot(_status_controls_snapshot(player))
		)
		controls.set_snapshot(_status_controls_snapshot(player))
		for index in controls.body_part_selector.item_count:
			if str(controls.body_part_selector.get_item_metadata(index)) == "right_arm":
				controls.body_part_selector.select(index)
				controls.body_part_selector.item_selected.emit(index)
				break
		controls.body_damage_button.pressed.emit()
		HELPERS.stop_external_execution(controls)
		fixture["controls"] = controls
	return fixture


static func _status_controls_snapshot(player: DungeonPlayer) -> Dictionary:
	return {"health": player.health, "max_health": DungeonPlayer.MAX_HEALTH, "stamina": player.stamina, "max_stamina": DungeonPlayer.MAX_STAMINA, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress, "body": player.get_body_health_snapshot()}


static func inspect_fixture(viewport: SubViewport, fixture: Dictionary, shot: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var overlay: InventoryOverlay = fixture.overlay
	var player: DungeonPlayer = fixture.player
	var state := player.get_body_health_snapshot()
	var panel := overlay.health_panel
	if str(shot.action) == "controls":
		var controls: Control = fixture.controls
		if not Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(controls.get_global_rect()):
			failures.append("Production test-room status controls must fit the viewport.")
		if state.parts.right_arm.health != 50.0 or not controls.body_part_readout.text.contains("50 / 60"):
			failures.append("The actual status-card part selector and damage action must affect the production player.")
		if not HELPERS.execution_isolated(controls) or not HELPERS.execution_isolated(overlay):
			failures.append("Status controls capture must disable external input and processing.")
		return {"body_health": state, "part_readout": controls.body_part_readout.text, "controls_bounds": str(controls.get_global_rect()), "actual_damage_button_used": true, "failures": failures}
	if not overlay.health_tab_active or not panel.is_visible_in_tree() or not overlay.combined_loadout_panel.is_visible_in_tree() or overlay.inventory_root.is_visible_in_tree() or overlay.equipment_root.is_visible_in_tree():
		failures.append("Production inventory must show health and the real loadout together.")
	if str(shot.action) == "equipment" and (overlay.selected_equipment_slot != "body" or panel.treatment_popup.visible):
		failures.append("Selecting real equipment must retain the integrated body/loadout screen.")
	if str(shot.action) == "details" and (not overlay.item_detail_window.is_open() or panel.treatment_popup.visible):
		failures.append("Owned item inspection must open above the unified page and dismiss treatment.")
	if str(shot.action) == "quick_use" and (ExpeditionSession.thirst != 100.0 or fixture.bag.count_item("boiled_rainwater") != 0 or fixture.responses.size() != 1):
		failures.append("The real quick-use button must consume water and update the survival meter.")
	var loadout := overlay.combined_loadout_panel
	if loadout.inventory_buttons.size() != 30 or loadout.equipment_buttons.size() != ExpeditionInventory.EQUIPMENT_ORDER.size() or loadout.quick_use_buttons.size() != 10:
		failures.append("Combined loadout must expose the actual seven equipment slots, thirty storage cells and ten quick-use controls.")
	if str(shot.action) in ["storage_swapped", "storage_details"]:
		if fixture.bag.equipment.waist_pouch != "pilgrim_waist_pouch" or fixture.bag.equipment.backpack != "wanderer_backpack" or fixture.bag.count_item("leather_waist_pouch") != 1 or fixture.bag.count_item("expedition_backpack") != 1 or fixture.bag.count_item("healing_draught") != 3:
			failures.append("Storage preview must perform real equipment swaps and preserve prior containers and carried supplies.")
		if str(shot.action) == "storage_details" and not overlay.item_detail_window.is_open():
			failures.append("The equipped backpack must open its real detail window.")
	if panel.snapshot != state:
		failures.append("Rendered body values must equal the production player's current snapshot.")
	var frame := Rect2(Vector2.ZERO, Vector2(viewport.size)).grow(1)
	if not frame.encloses(panel.get_global_rect()) or not frame.encloses(overlay.health_chrome.get_global_rect()):
		failures.append("Full health composition and navigation must fit the actual viewport.")
	for part_id in panel.PART_ORDER:
		if not frame.encloses(panel.part_buttons[part_id].get_global_rect()):
			failures.append("Every body card must fit the viewport: " + part_id)
	if overlay.health_chrome.tab_buttons.size() != 6 or overlay.health_chrome.survival_bars.size() != 4:
		failures.append("The reference composition must contain five visible navigation tabs (one shared equipment/health entry) and four actual survival meters.")
	var survival_values := {"hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stamina": player.stamina, "stress": ExpeditionSession.stress}
	for key in survival_values:
		if not overlay.health_chrome.survival_bars.has(key) or not is_equal_approx(float(overlay.health_chrome.survival_bars[key].value), float(survival_values[key])):
			failures.append("Health footer must use the current real survival value: " + str(key))
		var meter: ProgressBar = overlay.health_chrome.survival_bars[key]
		if meter.size.y > 10.0 or meter.position.y + meter.size.y > 692.0:
			failures.append("Survival fill must stay within its ten-pixel track and lower frame: " + str(key))
	var popup_expected := str(shot.action) in ["injured", "surgery", "heal"]
	if panel.treatment_popup.is_visible_in_tree() != popup_expected:
		failures.append("Treatments must appear only while the selected-part popup is open.")
	if popup_expected and not frame.encloses(panel.treatment_popup.get_global_rect()):
		failures.append("The complete treatment popup must fit the actual viewport.")
	if popup_expected and not str(state.selected_part).is_empty():
		var selected: String = state.selected_part
		if panel.treatment_popup.get_global_rect().intersects(panel.part_bars[selected].get_global_rect()):
			failures.append("The treatment popup must not hide the selected part's real health bar.")
		var selected_part: Dictionary = state.parts[selected]
		if panel.selected_health_label.text != "%d/%d" % [ceili(float(selected_part.health)), roundi(float(selected_part.max_health))]:
			failures.append("The treatment popup must show the selected part's current health beside its title.")
	if not HELPERS.execution_isolated(overlay) or not viewport.gui_disable_input or viewport.physics_object_picking:
		failures.append("Preview must disable all external input and automatic world updates.")
	match str(shot.action):
		"healthy":
			if state.health != 440.0 or state.parts.head.health != 35.0:
				failures.append("Healthy fixture must preserve the production head35 and total440 rules.")
		"injured":
			if state.parts.left_arm.health != 0.0 or not panel.part_buttons.left_arm.get_meta("blacked") or not panel.part_buttons.left_arm.get_meta("selected"):
				failures.append("Injury fixture must show the actual selected blacked arm.")
		"surgery":
			if state.parts.left_arm.health != 1.0 or fixture.bag.count_item("surgery_kit") != 2 or fixture.responses.size() != 1 or not fixture.responses[0].get("accepted", false):
				failures.append("Surgery screenshot must follow real consumption and exact 0-to-1 restoration.")
		"heal":
			if state.parts.left_arm.health != 17.0 or fixture.bag.count_item("healing_draught") != 2 or fixture.responses.size() != 2 or not fixture.responses[1].get("accepted", false):
				failures.append("Healing screenshot must show real 0-to-1 surgery then 1-to-17 cursed potion treatment.")
		"closed":
			if str(state.selected_part) != "left_arm" or not panel.part_buttons.left_arm.get_meta("selected"):
				failures.append("Closing the treatment popup must retain the real selected body part.")
	return {"body_health": state, "total_label": panel.total_label.text, "target_label": panel.selected_label.text, "guidance": panel.guidance_label.text, "responses": fixture.responses, "treatment_buttons": panel.treatment_buttons.keys(), "popup_visible": panel.treatment_popup.is_visible_in_tree(), "survival_values": survival_values, "panel_bounds": str(panel.get_global_rect()), "bag_visible": overlay.combined_loadout_panel.is_visible_in_tree(), "failures": failures}


static func collect_hashes() -> Dictionary:
	var hashes := {}
	for path in ["res://scripts/health_panel.gd", "res://scripts/health_gothic_card.gd", "res://scripts/health_chrome.gd", "res://scripts/inventory_overlay.gd", "res://scripts/body_health.gd", "res://scripts/player.gd", "res://scripts/inventory_model.gd", "res://scripts/expedition_session.gd", "res://scripts/test_room.gd", "res://scripts/test_room_status_controls.gd", "res://tests/health_panel_preview.gd", "res://tests/item_detail_preview.gd", "res://tests/performance_preview.gd", "res://tests/hideout_ruin_preview.gd", "res://assets/ui/unified_character_inventory_v1.png", "res://scripts/combined_loadout_panel.gd", "res://assets/fonts/NotoSerifKR-Variable.ttf", "res://assets/fonts/NotoSansKR-Variable.ttf"]:
		hashes[path] = FileAccess.get_sha256(path)
	for path in ["res://assets/fonts/Cinzel-Variable.ttf", "res://assets/ui/health_armor_icons.svg", "res://assets/ui/leather_waist_pouch.svg", "res://assets/ui/expedition_backpack.svg"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Health captures require run_embedded_preview.sh health_panel_preview.gd.")
		quit(2)
		return
	var iteration := OS.get_environment("BODY_HEALTH_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Choose a new BODY_HEALTH_QA_ITERATION folder.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Preserve existing captures; choose a new iteration folder.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := HELPERS.PRESERVATION.inventory_fingerprint(original_bag)
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := HELPERS.PRESERVATION.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var hashes := collect_hashes()
	var failures: Array[String] = []
	for path in hashes:
		if str(hashes[path]).is_empty():
			failures.append("Missing source provenance: " + str(path))
	var captures: Array[Dictionary] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	for shot in shots():
		var viewport := HELPERS.create_viewport(shot.size)
		root.add_child(viewport)
		var fixture := create_fixture(viewport, shot)
		for frame in 12:
			await process_frame
		var report := inspect_fixture(viewport, fixture, shot)
		for failure in report.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var image_path := output.path_join(str(shot.id) + ".png")
		if pixels == null or pixels.is_empty() or pixels.save_png(image_path) != OK:
			failures.append("Could not save actual renderer output: " + str(shot.id))
		report["image"] = image_path.get_file()
		captures.append(report)
		viewport.free()
		fixture.player.free()
		await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == original and HELPERS.PRESERVATION.inventory_fingerprint(original_bag) == original_bag_hash and Input.mouse_mode == mouse_before and HELPERS.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before
	if not preserved:
		failures.append("Original expedition, inventory, sandbox or cursor changed.")
	if collect_hashes() != hashes:
		failures.append("Production sources changed during capture.")
	var manifest := {"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not save capture manifest.")
	for failure in failures:
		push_error(failure)
	print("HEALTH PANEL PREVIEW %s: %d actual health UI captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)
