extends SceneTree
## Asset-only companion to player_appearance_preview.gd. Uses the actual
## production portrait and model without loading unrelated gameplay fixtures.
const PORTRAIT := preload("res://scripts/player_portrait.gd")
const APPEARANCE := preload("res://scripts/player_appearance.gd")
const BODY_SIZE := Vector2i(1024, 1536)
var output_path := ""
var captured_names: Array[String] = []
var failed := false
func _init() -> void: call_deferred("_run")
func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Anatomy captures require the audited embedded renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_QA_ITERATION must name the review folder.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path("res://artifacts/visual_qa/player_appearance/" + iteration)
	DirAccess.make_dir_recursive_absolute(output_path)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var mouse_mode := Input.mouse_mode
	await _capture_body()
	failed = failed or Input.mouse_mode != mouse_mode
	var manifest := {
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(),
		"model": APPEARANCE.MODEL_PATH,
		"model_sha256": FileAccess.get_sha256(APPEARANCE.MODEL_PATH),
		"portrait_script_sha256": FileAccess.get_sha256("res://scripts/player_portrait.gd"),
		"capture_kind": "Actual production portrait and model; isolated asset review",
		"desktop_capture": false,
		"cursor_preserved": Input.mouse_mode == mouse_mode,
		"images": captured_names,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: failed = true
	print("PLAYER ANATOMY PREVIEW %s: %d actual-renderer captures" % ["FAIL" if failed else "PASS", captured_names.size()])
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
	if OS.get_environment("PLAYER_QA_MULTIVIEW") == "1":
		await _capture_calibrated_views(portrait)
	portrait.set_view_angle(-12.0)
	portrait.camera.size = 0.72
	portrait.camera.position = Vector3(0.0, 1.50, -3.5)
	portrait.camera.look_at(Vector3(0.0, 1.50, 0.0))
	await _capture(portrait.viewport, "player_face_detail.png")
	await _capture_shoulder_form(portrait)
	portrait.queue_free()
	await process_frame


func _capture_calibrated_views(portrait) -> void:
	# Match the supplied 1086x1448 reference frame: anatomical skull y36,
	# sole y1401, centreline x533.5. Hair above the skull is excluded from scale.
	var old_size: Vector2i = portrait.viewport.size
	var old_transform: Transform3D = portrait.camera.transform
	var old_camera_size: float = portrait.camera.size
	var overrides: Dictionary = {}
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color(.62, .66, .70)
	clay.roughness = .9
	for mesh: MeshInstance3D in portrait.body.find_children("*", "MeshInstance3D", true, false):
		overrides[mesh] = mesh.material_override
	var scale := 1.712215677 / 1365.0
	var height := scale * 1448.0
	var center_z := .0076724137 - 47.0 * scale + height * .5
	portrait.viewport.size = Vector2i(1086, 1448)
	portrait.viewport.transparent_bg = true
	portrait.camera.size = height
	portrait.camera.position = Vector3(-9.5 * scale, center_z, -3.5)
	portrait.camera.look_at(Vector3(-9.5 * scale, center_z, 0.0))
	for shot in [{"name":"front", "angle":0.0}, {"name":"back", "angle":180.0}, {"name":"right", "angle":90.0}, {"name":"left", "angle":-90.0}]:
		portrait.set_view_angle(shot.angle)
		await _capture(portrait.viewport, "calibrated_%s.png" % shot.name)
		for mesh in overrides: mesh.material_override = clay
		await _capture(portrait.viewport, "calibrated_%s_clay.png" % shot.name)
		for mesh in overrides: mesh.material_override = overrides[mesh]
	portrait.viewport.transparent_bg = false
	portrait.viewport.size = old_size
	portrait.camera.transform = old_transform
	portrait.camera.size = old_camera_size


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
