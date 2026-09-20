extends SceneTree
## Actual production player geometry, portrait UI and first-person equipment.
## Only the audited macOS embedded bootstrap is accepted. It never creates a
## native window, captures the desktop, samples external gameplay input or emits
## audio. Synthetic portrait clicks stay inside an isolated SubViewport.

const PORTRAIT := preload("res://scripts/player_portrait.gd")
const APPEARANCE := preload("res://scripts/player_appearance.gd")
const CONTACT_PREVIEW := preload("res://tests/contact_visual_preview.gd")
const BODY_SIZE := Vector2i(1024, 1536)
const UI_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_appearance"

var output_path := ""
var captured_names: Array[String] = []
var local_gui_checks: Array[Dictionary] = []
var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Player captures require tests/run_embedded_preview.sh; ordinary native windows and dummy headless rendering are not accepted.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_QA_ITERATION").strip_edges()
	if iteration.is_empty():
		iteration = "final"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_QA_ITERATION must be a plain folder name.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	DirAccess.make_dir_recursive_absolute(output_path)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	await _capture_body()
	if not failed and OS.get_environment("PLAYER_QA_BODY_ONLY") != "1":
		await _capture_first_person()
		await _capture_inventory()
		await _capture_inventory_in_game()
	var state_preserved := Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot
	if not state_preserved:
		push_error("Player visual preview changed cursor mode or expedition state.")
		failed = true
	var manifest := {
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(),
		"model": APPEARANCE.MODEL_PATH,
		"model_sha256": FileAccess.get_sha256(APPEARANCE.MODEL_PATH),
		"portrait_script_sha256": FileAccess.get_sha256("res://scripts/player_portrait.gd"),
		"appearance_id": APPEARANCE.APPEARANCE_ID,
		"capture_kind": "Production model and UI rendered in isolated Godot SubViewports",
		"desktop_capture": false,
		"expedition_and_cursor_preserved": state_preserved,
		"local_gui_checks": local_gui_checks,
		"images": captured_names,
	}
	var manifest_file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if manifest_file:
		manifest_file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failed = true
	print("PLAYER APPEARANCE PREVIEW %s: %d actual-renderer captures, input and expedition preserved; %s" % ["FAIL" if failed else "PASS", captured_names.size(), output_path])
	quit(1 if failed else 0)


func _capture_body() -> void:
	var portrait := PORTRAIT.new()
	portrait.name = "ProductionPortraitCapture"
	root.add_child(portrait)
	portrait.viewport.size = BODY_SIZE
	portrait.viewport.transparent_bg = false
	portrait.viewport.use_taa = true
	for node in portrait.viewport.get_children():
		if node is WorldEnvironment:
			node.environment.background_color = Color("#181c1d")
	for shot in [
		{"name": "front", "angle": 0.0},
		{"name": "three_quarter", "angle": -32.0},
		{"name": "side", "angle": -90.0},
		{"name": "back", "angle": 180.0},
	]:
		portrait.set_view_angle(shot.angle)
		await _capture(portrait.viewport, "player_%s.png" % shot.name)
	portrait.set_view_angle(-12.0)
	portrait.camera.size = 0.72
	portrait.camera.position = Vector3(0.0, 1.50, -3.5)
	portrait.camera.look_at(Vector3(0.0, 1.50, 0.0))
	await _capture(portrait.viewport, "player_face_detail.png")
	# Optional close-up for wrist/cuff proportion reviews, using the actual mesh.
	if OS.get_environment("PLAYER_QA_WRIST_DETAIL") == "1":
		portrait.set_view_angle(0.0)
		portrait.camera.size = 0.40
		portrait.camera.position = Vector3(-0.29, 0.84, -3.5)
		portrait.camera.look_at(Vector3(-0.29, 0.84, 0.0))
		await _capture(portrait.viewport, "player_wrist_detail.png")
	if OS.get_environment("PLAYER_QA_ELBOW_DETAIL") == "1":
		portrait.set_view_angle(0.0)
		portrait.camera.size = 0.65
		portrait.camera.position = Vector3(-0.26, 1.15, -3.5)
		portrait.camera.look_at(Vector3(-0.26, 1.15, 0.0))
		await _capture(portrait.viewport, "player_elbow_detail.png")
	portrait.queue_free()
	await process_frame


func _capture_first_person() -> void:
	var viewport := _viewport(UI_SIZE)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#171a1b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.55, 0.62, 0.7)
	environment.environment.ambient_light_energy = 0.24
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	stage.add_child(environment)
	var floor_node := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(15.0, 15.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#2b2925")
	floor_material.roughness = 0.98
	floor_mesh.material = floor_material
	floor_node.mesh = floor_mesh
	stage.add_child(floor_node)
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.position = Vector3(0.0, 0.90, 0.0)
	player.head.rotation.x = deg_to_rad(-8.0)
	player._update_viewmodel(1.0)
	player.viewmodel_renderer.sync_view()
	await _capture(viewport, "player_first_person.png")
	viewport.queue_free()
	await process_frame


func _capture_inventory() -> void:
	# The production survival footer ensures an expedition exists. Let the
	# existing test-session owner provide it, then restore its prior snapshot.
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := _viewport(UI_SIZE)
	var background := ColorRect.new()
	background.color = Color("#20221f")
	background.size = Vector2(UI_SIZE)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(background)
	var overlay := _add_inventory_overlay(viewport)
	await _verify_portrait_gui(viewport, overlay, "inventory")
	await _capture(viewport, "player_inventory.png")
	viewport.queue_free()
	await process_frame
	sandbox.finish()


func _capture_inventory_in_game() -> void:
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	# These reviewed static helpers instantiate the actual mine, its production
	# environment, and the actual player with processing disabled before _ready.
	# The contact preview SceneTree and its window/interactive path never run.
	var viewport := CONTACT_PREVIEW.create_viewport()
	viewport.audio_listener_enable_3d = false
	root.add_child(viewport)
	var player := CONTACT_PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var configured := CONTACT_PREVIEW.configure_shot(player, {
		"name": "player_inventory_in_game",
		"position": Vector3(0.6, 1.75, 60.1),
		"target": Vector3(3.356, 0.65, 57.54),
		"equipment": true,
	})
	if not configured:
		push_error("Could not configure the actual cave/player camera.")
		failed = true
	else:
		await _capture(viewport, "player_in_game.png")
		var overlay := _add_inventory_overlay(viewport)
		await _verify_portrait_gui(viewport, overlay, "inventory_in_game")
		await _capture(viewport, "player_inventory_in_game.png")
	viewport.queue_free()
	await process_frame
	sandbox.finish()


func _add_inventory_overlay(viewport: SubViewport) -> InventoryOverlay:
	var isolated_inventory := ExpeditionInventory.new()
	isolated_inventory.seed_default_loadout()
	var overlay := InventoryOverlay.new()
	overlay.set_process_unhandled_input(false)
	viewport.add_child(overlay)
	var status := {"health": 100.0, "max_health": 100.0, "stamina": 100.0, "max_stamina": 100.0}
	overlay.open_inventory(isolated_inventory, func() -> Dictionary: return status)
	overlay.open_appearance_view()
	return overlay


func _verify_portrait_gui(viewport: SubViewport, overlay: InventoryOverlay, label: String) -> void:
	await process_frame
	var original_gui_disabled := viewport.gui_disable_input
	var original_mouse_mode := Input.mouse_mode
	# Only this unhosted viewport accepts the two explicit GUI clicks. Events
	# never enter Input.parse_input_event or any native cursor/focus API.
	viewport.gui_disable_input = false
	var portrait := overlay.player_portrait
	var right := portrait.get_node("ViewRight") as Button
	var reset := portrait.get_node("ViewReset") as Button
	await _click_viewport_button(viewport, right)
	var right_angle := float(portrait.call("get_view_angle"))
	await _click_viewport_button(viewport, reset)
	var reset_angle := float(portrait.call("get_view_angle"))
	viewport.gui_disable_input = original_gui_disabled
	var passed := is_equal_approx(right_angle, 30.0) and is_zero_approx(reset_angle) and Input.mouse_mode == original_mouse_mode
	local_gui_checks.append({
		"view": label,
		"right_click_degrees": right_angle,
		"reset_click_degrees": reset_angle,
		"cursor_mode_preserved": Input.mouse_mode == original_mouse_mode,
		"passed": passed,
	})
	if not passed:
		push_error("Actual inventory GUI routing failed for %s: right=%s reset=%s" % [label, right_angle, reset_angle])
		failed = true
	else:
		print("PLAYER LOCAL GUI PASS: %s actual right and reset hit targets; cursor mode preserved" % label)


func _click_viewport_button(viewport: SubViewport, button: Button) -> void:
	var center := button.get_global_rect().get_center()
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


func _viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture(viewport: SubViewport, file_name: String) -> void:
	for _frame in range(20):
		await process_frame
	RenderingServer.force_draw(false)
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		push_error("Actual renderer returned no image: " + file_name)
		failed = true
		return
	var save_result := rendered.save_png(output_path.path_join(file_name))
	if save_result != OK:
		push_error("Could not save actual player render: " + file_name)
		failed = true
		return
	captured_names.append(file_name)
	print("PLAYER CAPTURE: " + output_path.path_join(file_name))
