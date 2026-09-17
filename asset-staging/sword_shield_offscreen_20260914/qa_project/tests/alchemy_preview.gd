extends SceneTree
## Audited offscreen production UI capture: embedded renderer, isolated bag,
## viewport-local synthetic clicks only; no desktop capture, OS cursor or sound.
const OVERLAY := preload("res://scripts/alchemy_overlay.gd")
const SYSTEM := preload("res://scripts/alchemy_system.gd")
const LOCATION := preload("res://tests/dark_fantasy_scene_preview.gd")
const SOURCES := ["res://scripts/alchemy_overlay.gd", "res://scripts/alchemy_visual.gd", "res://scripts/alchemy_catalog.gd", "res://scripts/alchemy_system.gd", "res://scripts/alchemy_audio.gd", "res://scripts/inventory_model.gd", "res://scripts/player_arm_visual.gd", "res://assets/3d/player/gravebound_player.glb", "res://scripts/dark_fantasy_materials.gd", "res://scripts/hideout.gd", "res://tests/dark_fantasy_scene_preview.gd", "res://tests/alchemy_preview.gd"]
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var canvas: SubViewport
var ui: CanvasLayer
var output_path := ""
var local_button_check := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited embedded alchemy_preview.gd runner.")
		quit(2)
		return
	var iteration := OS.get_environment("ALCHEMY_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	output_path = ProjectSettings.globalize_path("res://artifacts/visual_qa/alchemy/" + iteration)
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Use a new capture iteration directory.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_path)
	var original := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	var hashes := {}
	for source in SOURCES: hashes[source] = FileAccess.get_sha256(source)
	AudioServer.set_bus_mute(0, true)
	root.gui_disable_input = true
	root.physics_object_picking = false
	canvas = SubViewport.new()
	canvas.size = Vector2i(1280, 720)
	canvas.own_world_3d = true
	canvas.physics_object_picking = false
	canvas.audio_listener_enable_2d = false
	canvas.audio_listener_enable_3d = false
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	ui = OVERLAY.new()
	canvas.add_child(ui)
	ui.set_process_input(false)
	var bag := ExpeditionInventory.new()
	for id: String in SYSTEM.trial_supplies(): bag.add_item(id, int(SYSTEM.trial_supplies()[id]))
	ui.open_for_inventory(bag)
	ui.set_process(false)
	await _capture("01_workbench")
	# A real native Godot button click, delivered solely inside this SubViewport.
	var button: Button = ui.base_buttons.water
	var point := button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame
	local_button_check = ui.system.snapshot().base_id == "water"
	if not local_button_check: failures.append("Real water button did not pour actual bag water.")
	await _capture("02_pouring_water", "pour_water", 0.45)
	_act("add_to_mortar", "dawnleaf")
	_act("add_to_mortar", "dawnleaf")
	_act("grind")
	ui.set_view("mortar")
	await _capture("03_mortar_grinding", "grind", 0.60)
	_act("discard")
	_act("select_recipe", "moon_distillate")
	_act("pour_base", "spirits")
	_act("add_to_mortar", "moonwort")
	_act("add_to_mortar", "moonwort")
	for stroke in 3: _act("grind")
	_act("pour_mortar")
	ui.set_view("cauldron")
	await _capture("04_ground_herb_pour", "add_mortar", 0.60)
	_act("add_whole", "ironbloom")
	_act("stir")
	_act("lower_cauldron")
	_act("turn_hourglass")
	_heat_until(1.0)
	await _capture("05_boiling_bellows", "pump_bellows", 0.28)
	_act("raise_cauldron")
	_act("start_distillation")
	_act("lower_cauldron")
	var attempts := 0
	while float(ui.system.snapshot().distill_progress) < 0.52 and attempts < 1600:
		_heat_step()
		attempts += 1
	ui.set_view("distill")
	await _capture("06_distillation")
	while float(ui.system.snapshot().distill_progress) < 1.0 and attempts < 2400:
		_heat_step()
		attempts += 1
	_act("bottle")
	await _capture("07_finished_result", "bottle", 0.55)
	_act("discard")
	_act("select_recipe", "pilgrim_tonic")
	_act("pour_base", "wine")
	_act("bottle")
	await _capture("08_failure_explanation")
	ui._toggle_book()
	await _capture("09_expanded_recipe")
	canvas.size = Vector2i(960, 540)
	ui._layout()
	await _capture("10_small_window")
	ui.cancel_work()
	canvas.queue_free()
	await process_frame
	await _capture_hideout()
	var preserved := ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_before
	if not preserved: failures.append("Original expedition or cursor changed.")
	for source in SOURCES:
		if FileAccess.get_sha256(source) != hashes[source]: failures.append("Source changed during capture: " + source)
	var manifest := {"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(), "actual_production_ui": true, "local_button_check": local_button_check, "desktop_capture": false, "hardware_input": false, "expedition_and_cursor_preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	for failure in failures: push_error(failure)
	print("ALCHEMY PREVIEW %s: %d production captures; local button input and state preservation; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output_path])
	quit(0 if failures.is_empty() else 1)

func _act(action: String, payload: Variant = null) -> void:
	var result: Dictionary = ui.perform_action(action, payload)
	if not result.get("accepted", false): failures.append(action + ": " + str(result.get("message", "")))

func _heat_step() -> void:
	var state: Dictionary = ui.system.snapshot()
	var boiling_point := float(state.boiling_point)
	if float(state.temperature) > boiling_point + 9.0 and bool(state.cauldron_lowered):
		ui.system.set_cauldron_lowered(false)
	elif float(state.temperature) < boiling_point + 2.0 and not bool(state.cauldron_lowered):
		ui.system.set_cauldron_lowered(true)
	if float(state.heat) < (boiling_point - 20.0) / 1.4 + 8.0: ui.system.pump_bellows()
	ui.system.tick(0.05)

func _heat_until(turns: float) -> void:
	var attempts := 0
	while float(ui.system.snapshot().boil_turns) < turns and attempts < 2400:
		_heat_step()
		attempts += 1
	if attempts >= 2400: failures.append("Boiling never reached requested turns.")

func _capture(id: String, animation := "", time := 0.0) -> void:
	ui._refresh()
	for frame in 8: await process_frame
	ui.visual.set_process(false)
	if not animation.is_empty():
		ui.visual.animate_action(animation)
		ui.visual._process(time)
	for frame in 3: await process_frame
	RenderingServer.force_draw(false)
	var pixels := canvas.get_texture().get_image()
	if pixels == null or pixels.is_empty() or pixels.save_png(output_path.path_join(id + ".png")) != OK:
		failures.append("Missing rendered pixels: " + id)
	var state: Dictionary = ui.system.snapshot()
	captures.append({"id": id, "image": id + ".png", "size": str(canvas.size), "stage": state.stage, "base_id": state.base_id, "temperature": state.temperature, "boil_turns": state.boil_turns, "distill_progress": state.distill_progress, "result": state.last_result})
	ui.visual.set_process(true)

func _capture_hideout() -> void:
	var viewport: SubViewport = LOCATION.create_viewport("hideout")
	root.add_child(viewport)
	LOCATION.populate_viewport(viewport)
	var shot := {"id": "11_hideout_alchemy_bench", "scene": "hideout", "position": Vector3(11.1, 1.7, -4.7), "target": Vector3(11.1, 1.17, -2.8)}
	if not LOCATION.configure_shot(viewport, shot): failures.append("Could not configure production hideout bench view.")
	for frame in 20: await process_frame
	RenderingServer.force_draw(false)
	var pixels := viewport.get_texture().get_image()
	if pixels == null or pixels.is_empty() or pixels.save_png(output_path.path_join("11_hideout_alchemy_bench.png")) != OK:
		failures.append("Missing actual hideout alchemy bench pixels.")
	captures.append({"id": "11_hideout_alchemy_bench", "image": "11_hideout_alchemy_bench.png", "production_hideout_geometry": true, "camera": str(shot.position)})
	viewport.queue_free()
	await process_frame
