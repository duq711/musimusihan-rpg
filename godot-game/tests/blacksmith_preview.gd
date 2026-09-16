extends SceneTree
## Audited isolated production UI capture: no native window, cursor change,
## game scene entry, hardware input sampling or audible sound.
const OVERLAY := preload("res://scripts/blacksmith_overlay.gd")
const EQUIPMENT_CAPTURE := preload("res://tests/blacksmith_equipment_capture.gd")
const SYSTEM := preload("res://scripts/smithing_system.gd")
const SOURCES := ["res://scripts/blacksmith_overlay.gd", "res://scripts/blacksmith_visual.gd", "res://scripts/smithing_system.gd", "res://scripts/player_arm_visual.gd", "res://assets/3d/player/gravebound_player.glb", "res://scripts/dark_fantasy_materials.gd", "res://assets/ai/blacksmith/smithing_target_sheet.png", "res://scripts/player.gd", "res://scripts/inventory_model.gd", "res://tests/blacksmith_equipment_capture.gd"]
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var output_path := ""
var canvas: SubViewport
var smith: CanvasLayer

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited run_embedded_preview.sh blacksmith_preview.gd path.")
		quit(2)
		return
	var iteration := OS.get_environment("BLACKSMITH_QA_ITERATION").strip_edges()
	if iteration.is_empty(): iteration = "iteration_01"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	output_path = ProjectSettings.globalize_path("res://artifacts/visual_qa/blacksmith/" + iteration)
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Capture folders must be new: " + output_path)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_path)
	var mouse_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var hashes := {}
	for source in SOURCES: hashes[source] = FileAccess.get_sha256(source)
	AudioServer.set_bus_mute(0, true)
	root.gui_disable_input = true
	root.physics_object_picking = false
	canvas = SubViewport.new()
	canvas.name = "IsolatedBlacksmithGameplayUI"
	canvas.size = Vector2i(1280, 720)
	canvas.own_world_3d = true
	canvas.audio_listener_enable_3d = false
	canvas.audio_listener_enable_2d = false
	canvas.physics_object_picking = false
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	smith = OVERLAY.new()
	smith.set_process_input(false)
	canvas.add_child(smith)
	var bag := ExpeditionInventory.new()
	bag.seed_default_loadout()
	for item_id: String in SYSTEM.trial_supplies():
		bag.add_item(item_id, int(SYSTEM.trial_supplies()[item_id]))
	smith.open_for_inventory(bag)
	smith.set_process(false)
	smith.set_process_input(false)
	await _capture("01_workshop")
	# A real button click stays inside this isolated GUI viewport.
	var button: Button = smith.action_buttons.start
	var pos := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame
	if smith.system.stage != "fire": failures.append("Local production recipe button click did not start forging.")
	for stroke in 6: _act("pump_bellows")
	await _capture("02_fire_bellows")
	_act("move_to_anvil")
	_act("hammer", {"section": 0, "accuracy": 1.0})
	await _capture("03_anvil_strike", "hammer")
	for face in 2:
		for section in 3:
			while float(smith.system.sections[face][section]) < 1.0:
				if smith.system.temperature < 745:
					_act("return_to_fire")
					_act("pump_bellows")
					_act("move_to_anvil")
				_act("hammer", {"section": section, "accuracy": 1.0})
		if face == 0: _act("flip_blade")
	if smith.system.temperature < 700:
		_act("return_to_fire")
		_act("pump_bellows")
	_act("quench")
	await _capture("04_quench", "quench")
	_act("finish")
	smith.show_station("grip")
	_act("replace_grip", "balanced_grip")
	await _capture("05_grip")
	smith.show_station("blade")
	_act("reinforce_blade", "silver_edge")
	await _capture("06_blade")
	smith.show_station("rune")
	for cut in 3: _act("drill_socket", 1.0)
	await _capture("07_drill_socket", "drill_socket")
	_act("insert_rune", "rune_fragment")
	await _capture("08_rune_insert", "insert_rune")
	await _capture_equipped(bag)
	var preserved := Input.mouse_mode == mouse_before and ExpeditionSession.capture_snapshot() == session_before
	if not preserved: failures.append("Preview changed original expedition or cursor.")
	for source in SOURCES:
		if FileAccess.get_sha256(source) != hashes[source]: failures.append("Source changed during capture: " + source)
	var manifest := {"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "actual_production_ui": true, "desktop_capture": false, "hardware_input": false, "local_recipe_button_test": smith.system.stage == "finished", "expedition_and_cursor_preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	smith.close()
	canvas.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("BLACKSMITH PREVIEW %s: %d production workstation captures; cursor and expedition preserved; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)

func _act(action: String, payload: Variant = null) -> void:
	var result: Dictionary = smith.perform_action(action, payload)
	if not bool(result.get("accepted", false)):
		failures.append(action + ": " + str(result.get("message", "")))

func _capture(id: String, animation := "") -> void:
	for frame in 12: await process_frame
	if not animation.is_empty():
		smith.visual.animate_action(animation)
		smith.visual._process(0.28 if animation != "quench" else 0.60)
		smith.visual.set_process(false)
	for frame in 4: await process_frame
	RenderingServer.force_draw(false)
	var rendered := canvas.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		failures.append("No real renderer pixels for " + id)
		return
	if rendered.save_png(output_path.path_join(id + ".png")) != OK:
		failures.append("Failed saving " + id)
	var state: Dictionary = smith.system.snapshot()
	captures.append({"id": id, "image": id + ".png", "stage": state.stage, "temperature": state.temperature, "selected_weapon": state.selected_weapon, "camera": str(smith.camera.transform)})
	smith.visual.set_process(true)


func _capture_equipped(bag: ExpeditionInventory) -> void:
	var selected: Dictionary = smith.system.snapshot().selected_weapon
	var equipped := false
	for index in bag.slots.size():
		var instance: Dictionary = bag.slots[index].get("instance", {})
		if str(instance.get("uid", "")) == str(selected.get("uid", "")):
			equipped = bool(bag.equip_from_slot(index).accepted)
			break
	if not equipped:
		failures.append("Could not equip the actual forged/upgraded sword for external view.")
		return
	smith.close()
	canvas.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var equipped_view := EQUIPMENT_CAPTURE.create_viewport(bag)
	root.add_child(equipped_view)
	await physics_frame
	await physics_frame
	for frame in 20: await process_frame
	var inspection: Dictionary = EQUIPMENT_CAPTURE.inspect(equipped_view)
	if not bool(inspection.get("passed", false)):
		failures.append("Actual equipped sword visual did not match its installed rune metadata.")
	RenderingServer.force_draw(false)
	var pixels := equipped_view.get_texture().get_image()
	if pixels == null or pixels.is_empty() or pixels.save_png(output_path.path_join("09_equipped_sword.png")) != OK:
		failures.append("Could not capture the actual equipped sword.")
	inspection["id"] = "09_equipped_sword"
	inspection["image"] = "09_equipped_sword.png"
	captures.append(inspection)
	equipped_view.queue_free()
	await process_frame
