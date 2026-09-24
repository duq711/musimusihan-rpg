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
	var licensed := APPEARANCE.has_licensed_character()
	var model_path: String = APPEARANCE.LICENSED_MODEL_PATH if licensed else APPEARANCE.MODEL_PATH
	var manifest := {
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(),
		"model": model_path,
		"model_sha256": FileAccess.get_sha256(model_path),
		"outfit_source_sha256": FileAccess.get_sha256(APPEARANCE.OUTFIT_PATH),
		"licensed_character": licensed,
		"portrait_script_sha256": FileAccess.get_sha256("res://scripts/player_portrait.gd"),
		"appearance_id": APPEARANCE.LICENSED_APPEARANCE_ID if licensed else APPEARANCE.APPEARANCE_ID,
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
	portrait.fit_body_to_frame()
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
	portrait.camera.size = 0.84
	portrait.camera.position = Vector3(0.0, 1.15, -3.5)
	portrait.camera.look_at(Vector3(0.0, 1.15, 0.0))
	await _capture(portrait.viewport, "player_outfit_detail.png")
	if OS.get_environment("PLAYER_QA_FACE_DETAIL") == "1":
		await _capture_face_detail(portrait)
	if OS.get_environment("PLAYER_QA_UPPER_BODY_DETAIL") == "1":
		await _capture_upper_body_detail(portrait)
	if OS.get_environment("PLAYER_QA_SHOULDER_FORM") == "1":
		await _capture_shoulder_form(portrait)
	if OS.get_environment("PLAYER_QA_TROUSERS_DETAIL") == "1":
		await _capture_trousers_detail(portrait)
	if OS.get_environment("PLAYER_QA_HAND_DETAIL") == "1":
		await _capture_hand_detail(portrait)
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
		if OS.get_environment("PLAYER_QA_ARM_STRUCTURE") == "1":
			var clay := StandardMaterial3D.new()
			clay.albedo_color = Color(0.56, 0.59, 0.61)
			clay.roughness = 0.9
			for mesh: MeshInstance3D in portrait.viewport.find_children("*", "MeshInstance3D", true, false):
				if str(mesh.name).begins_with("Gravebound_FP_"):
					mesh.material_override = clay
			await _capture(portrait.viewport, "player_arm_structure_front.png")
			portrait.set_view_angle(-90.0)
			portrait.camera.position = Vector3(0.0, 1.15, -3.5)
			portrait.camera.look_at(Vector3(0.0, 1.15, 0.0))
			await _capture(portrait.viewport, "player_arm_structure_side.png")
	portrait.queue_free()
	await process_frame


func _capture_shoulder_form(portrait) -> void:
	# Matching textured/clay views expose chest-to-arm and underarm volume while
	# retaining the whole production body and the portrait's existing lighting.
	var previous_angle := float(portrait.get_view_angle())
	var previous_transform: Transform3D = portrait.camera.transform
	var previous_size := float(portrait.camera.size)
	var previous_viewport_size: Vector2i = portrait.viewport.size
	var previous_overrides: Dictionary = {}
	for mesh: MeshInstance3D in portrait.body.find_children("*", "MeshInstance3D", true, false):
		previous_overrides[mesh] = mesh.material_override
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.56, 0.59, 0.61)
	clay.roughness = 0.9
	portrait.set_view_angle(0.0)
	# A square frame keeps both upper arms inside the 0.82 m orthographic width.
	portrait.viewport.size = Vector2i(1024, 1024)
	portrait.camera.size = 0.82
	var center := Vector3(0.0, 1.33, 0.0)
	for shot in [
		{"name": "front", "position": Vector3(0.0, 1.33, -1.5)},
		{"name": "oblique", "position": Vector3(-0.90, 1.38, -1.20)},
		{"name": "side", "position": Vector3(-1.5, 1.33, 0.0)},
		{"name": "rear", "position": Vector3(0.0, 1.33, 1.5)},
	]:
		portrait.camera.position = shot.position
		portrait.camera.look_at(center, Vector3.UP)
		await _capture(portrait.viewport, "player_shoulder_form_%s.png" % shot.name)
		for mesh in previous_overrides:
			mesh.material_override = clay
		await _capture(portrait.viewport, "player_shoulder_form_%s_clay.png" % shot.name)
		for mesh in previous_overrides:
			mesh.material_override = previous_overrides[mesh]
	portrait.set_view_angle(previous_angle)
	portrait.camera.transform = previous_transform
	portrait.camera.size = previous_size
	portrait.viewport.size = previous_viewport_size


func _capture_trousers_detail(portrait) -> void:
	# Keep the production outfit visible so the open coat removal can be checked
	# at the waist, both thighs and the underside of the joined trouser crotch.
	var previous_angle := float(portrait.get_view_angle())
	var previous_transform: Transform3D = portrait.camera.transform
	var previous_size := float(portrait.camera.size)
	portrait.set_view_angle(0.0)
	portrait.camera.size = 0.86
	var center := Vector3(0.0, 0.84, 0.0)
	for shot in [
		{"name": "front", "position": Vector3(0.0, 0.84, -1.4)},
		{"name": "rear", "position": Vector3(0.0, 0.84, 1.4)},
		{"name": "low", "position": Vector3(0.30, 0.26, -1.2)},
	]:
		portrait.camera.position = shot.position
		portrait.camera.look_at(center, Vector3.UP)
		await _capture(portrait.viewport, "player_trousers_%s.png" % shot.name)
	portrait.set_view_angle(previous_angle)
	portrait.camera.transform = previous_transform
	portrait.camera.size = previous_size


func _capture_face_detail(portrait) -> void:
	var previous_angle := float(portrait.get_view_angle())
	var previous_transform: Transform3D = portrait.camera.transform
	var previous_size := float(portrait.camera.size)
	portrait.set_view_angle(0.0)
	portrait.camera.size = 0.43
	var center := Vector3(0.0, 1.61, 0.0)
	for shot in [
		{"name": "front", "position": Vector3(0.0, 1.62, -1.0), "up": Vector3.UP},
		{"name": "left", "position": Vector3(-0.55, 1.65, -0.85), "up": Vector3.UP},
		{"name": "right", "position": Vector3(0.55, 1.65, -0.85), "up": Vector3.UP},
		{"name": "rear", "position": Vector3(0.0, 1.68, 1.0), "up": Vector3.UP},
		{"name": "crown", "position": Vector3(0.0, 2.50, 0.0), "up": Vector3.BACK},
	]:
		portrait.camera.position = shot.position
		portrait.camera.look_at(center, shot.up)
		await _capture(portrait.viewport, "player_face_%s_close.png" % shot.name)
	portrait.set_view_angle(previous_angle)
	portrait.camera.transform = previous_transform
	portrait.camera.size = previous_size


func _capture_upper_body_detail(portrait) -> void:
	# Inspect the preserved production head and its exposed scalp, including a
	# texture-free view to distinguish surface geometry from material artifacts.
	var previous_angle := float(portrait.get_view_angle())
	var previous_camera_transform: Transform3D = portrait.camera.transform
	var previous_camera_size := float(portrait.camera.size)
	portrait.set_view_angle(0.0)
	var center := Vector3(0.0, 1.66, 0.0)
	portrait.camera.size = 0.60
	for shot in [
		{"name": "top", "position": Vector3(0.0, 3.0, 0.0), "up": Vector3.BACK},
		{"name": "high", "position": Vector3(0.48, 2.28, -0.70), "up": Vector3.UP},
		{"name": "rear", "position": Vector3(0.0, 1.84, 0.90), "up": Vector3.UP},
	]:
		portrait.camera.position = shot.position
		portrait.camera.look_at(center, shot.up)
		await _capture(portrait.viewport, "player_head_%s.png" % shot.name)
	var head := portrait.body.find_child("Gravebound_AnatomicalHead", true, false) as MeshInstance3D
	if head == null or head.mesh == null:
		push_error("Production anatomical head is missing from the portrait model.")
		failed = true
	else:
		var previous_override := head.material_override
		var previous_visibility: Dictionary = {}
		for mesh: MeshInstance3D in portrait.body.find_children("*", "MeshInstance3D", true, false):
			previous_visibility[mesh] = mesh.visible
			mesh.visible = mesh == head
		var clay := StandardMaterial3D.new()
		clay.albedo_color = Color(0.56, 0.59, 0.61)
		clay.roughness = 0.9
		head.material_override = clay
		portrait.camera.position = Vector3(0.0, 3.0, 0.0)
		portrait.camera.look_at(center, Vector3.BACK)
		await _capture(portrait.viewport, "player_head_top_clay.png")
		head.material_override = previous_override
		for mesh in previous_visibility:
			mesh.visible = previous_visibility[mesh]
	await _capture_upper_shoulders(portrait)
	portrait.set_view_angle(previous_angle)
	portrait.camera.transform = previous_camera_transform
	portrait.camera.size = previous_camera_size


func _capture_upper_shoulders(portrait) -> void:
	# Keep the whole production body visible: these high rear-side views expose
	# the relationship between the head, neck cowl, mantle and shoulders.
	var center := Vector3(0.0, 1.42, 0.0)
	portrait.camera.size = 0.68
	for shot in [
		{"name": "left", "position": Vector3(-0.65, 2.08, 0.35)},
		{"name": "right", "position": Vector3(0.65, 2.08, 0.35)},
	]:
		portrait.camera.position = shot.position
		portrait.camera.look_at(center, Vector3.UP)
		await _capture(portrait.viewport, "player_upper_shoulder_%s.png" % shot.name)
	var previous_overrides: Dictionary = {}
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.56, 0.59, 0.61)
	clay.roughness = 0.9
	for mesh: MeshInstance3D in portrait.body.find_children("*", "MeshInstance3D", true, false):
		previous_overrides[mesh] = mesh.material_override
		mesh.material_override = clay
	# Repeat the right-side view with matching framing and no texture shading.
	await _capture(portrait.viewport, "player_upper_shoulder_right_clay.png")
	for mesh in previous_overrides:
		mesh.material_override = previous_overrides[mesh]


func _capture_hand_detail(portrait) -> void:
	# Isolate the actual static production hand so the torso cannot hide its palm.
	# Reuse the portrait's material resources, world-space light locations and
	# environment; only the optional final clay view overrides its duplicate.
	var previous_angle := float(portrait.get_view_angle())
	portrait.set_view_angle(0.0)
	var source := portrait.body.find_child("Gravebound_FP_L_Hand", true, false) as MeshInstance3D
	if source == null or source.mesh == null:
		push_error("Production left hand is missing from the portrait model.")
		failed = true
		portrait.set_view_angle(previous_angle)
		return
	var viewport := _viewport(Vector2i(1024, 1024))
	viewport.transparent_bg = false
	for node in portrait.viewport.get_children():
		if node is WorldEnvironment or node is Light3D:
			viewport.add_child(node.duplicate(0))
	var hand := source.duplicate(0) as MeshInstance3D
	viewport.add_child(hand)
	hand.global_transform = source.global_transform
	var corners: Array[Vector3] = []
	var bounds := source.get_aabb()
	for index in range(8):
		corners.append(source.global_transform * bounds.get_endpoint(index))
	var center := source.global_transform * bounds.get_center()
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = portrait.camera.cull_mask
	viewport.add_child(camera)
	camera.current = true
	# Inward-facing hands are deeper than they are wide from the front. Keep
	# palm/dorsal labels correct for both that pose and the earlier broad pose.
	var inward := Vector3(-1.0 if center.x > 0.0 else 1.0, 0.0, 0.0)
	var inward_pose := bounds.size.z > bounds.size.x
	var palm_direction := inward if inward_pose else Vector3.BACK
	var side_direction := Vector3.FORWARD if inward_pose else inward
	for shot in [
		{"name": "dorsal", "direction": -palm_direction},
		{"name": "palm", "direction": palm_direction},
		{"name": "side", "direction": side_direction},
	]:
		_fit_hand_camera(camera, center, corners, shot.direction)
		await _capture(viewport, "player_hand_%s.png" % shot.name)
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(0.56, 0.59, 0.61)
	clay.roughness = 0.9
	hand.material_override = clay
	_fit_hand_camera(camera, center, corners, palm_direction)
	await _capture(viewport, "player_hand_palm_clay.png")
	viewport.queue_free()
	portrait.set_view_angle(previous_angle)
	await process_frame


func _fit_hand_camera(camera: Camera3D, center: Vector3, corners: Array[Vector3], direction: Vector3) -> void:
	camera.global_position = center + direction.normalized() * 1.0
	camera.look_at(center, Vector3.UP)
	var half_width := 0.0
	var half_height := 0.0
	for corner in corners:
		var local_corner := camera.global_transform.affine_inverse() * corner
		half_width = maxf(half_width, absf(local_corner.x))
		half_height = maxf(half_height, absf(local_corner.y))
	var viewport_size := camera.get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / viewport_size.y
	camera.size = maxf(half_height, half_width / aspect) * 2.0 * 1.18


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
