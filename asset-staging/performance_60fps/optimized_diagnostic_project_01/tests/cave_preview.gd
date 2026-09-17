extends SceneTree
## Geometry-only capture harness: never instantiates a game, player, or audio.
## Native macOS Godot shows/activates its main window before this script starts.
## Use a real renderer only after the user approves that window, or after a
## separately verified non-activating launcher becomes available. Headless is
## a dummy renderer here and must never be reported as visual verification.

const OUTPUT_DIR := "res://artifacts/visual_qa/abandoned_mine/godot"
const IMAGE_SIZE := Vector2i(1280, 720)
const SHOTS := [
	{"name": "grand_quarry", "position": Vector3(-10, 2, 2), "target": Vector3(1.2536, 3, -9.7544), "fov": 72.0},
	{"name": "bone_cavern", "position": Vector3(-40, 2, 29), "target": Vector3(-51.9, 1.1, 25.6), "fov": 72.0},
	{"name": "pillar_shrine", "position": Vector3(49.2033, 2, -41.6778), "target": Vector3(49.4123, 3, -55.4226), "fov": 70.0},
	{"name": "longlake", "position": Vector3(26.1164, 2, 36.0247), "target": Vector3(38.9657, 1.1, 28.3764), "fov": 72.0},
	{"name": "workshops", "position": Vector3(-1.6715, 2, 43.0080), "target": Vector3(1.4625, 1.8, 36.2464), "fov": 72.0},
]


func _init() -> void:
	call_deferred("_run")


static func create_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "CavePreviewViewport"
	viewport.size = IMAGE_SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport


static func populate_viewport(viewport: SubViewport) -> Camera3D:
	var stage := Node3D.new()
	stage.name = "CavePreviewStage"
	viewport.add_child(stage)
	var geometry: Node3D = load("res://scripts/cave_geometry.gd").new()
	geometry.name = "CaveGeometry"
	stage.add_child(geometry)
	geometry.build()
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = load("res://scripts/cave_dungeon.gd").make_environment()
	stage.add_child(world_environment)
	var camera := Camera3D.new()
	camera.name = "CavePreviewCamera"
	camera.near = 0.08
	camera.far = 160.0
	stage.add_child(camera)
	camera.current = true
	# Same two lights and cave-specific neutral-warm tint as the lit hand torch,
	# without constructing a player. The position is relative to the camera.
	var torch := SpotLight3D.new()
	torch.name = "PreviewCarriedTorchSpot"
	torch.position = Vector3(-0.35, -0.2, -0.55)
	torch.light_color = Color(1.0, 0.78, 0.55)
	torch.light_energy = 4.9
	torch.spot_range = 19.0
	torch.spot_angle = 60.0
	torch.shadow_enabled = true
	camera.add_child(torch)
	var fill := OmniLight3D.new()
	fill.name = "PreviewCarriedTorchFill"
	fill.position = torch.position
	fill.light_color = Color(1.0, 0.68, 0.40)
	fill.light_energy = 2.4
	fill.omni_range = 7.2
	fill.shadow_enabled = false
	camera.add_child(fill)
	return camera


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Cave PNG captures require a real renderer. Use cave_preview_test.gd for headless structural checks.")
		quit(1)
		return
	if OS.get_environment("CAVE_QA_WINDOW_APPROVED") != "1":
		push_error("The native render window requires explicit user approval before launching this preview; see tests/cave_preview.gd.")
		quit(1)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var viewport := create_viewport()
	root.add_child(viewport)
	var camera := populate_viewport(viewport)
	if camera == null:
		push_error("Could not build the cave preview stage.")
		quit(1)
		return
	var preview_display := TextureRect.new()
	preview_display.texture = viewport.get_texture()
	preview_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(preview_display)
	preview_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.title = "검은 물길 폐광 · 환경 검토 후 자동 종료"
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create cave preview output directory.")
		quit(1)
		return
	for shot in SHOTS:
		camera.global_position = shot.position
		camera.look_at(shot.target, Vector3.UP)
		camera.fov = shot.fov
		# Let particles, shadows, and temporal effects settle at each camera.
		for frame in range(60):
			await process_frame
		RenderingServer.force_draw(false)
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty():
			push_error("Cave preview renderer returned no image: %s" % shot.name)
			quit(1)
			return
		image.convert(Image.FORMAT_RGBA8)
		var file_name := "%s/cave_%s.png" % [output_path, shot.name]
		if image.save_png(file_name) != OK:
			push_error("Could not save cave preview: %s" % file_name)
			quit(1)
			return
		print("CAVE CAPTURE: %s" % file_name)
	print("CAVE PREVIEW PASS: five actual geometry captures, shared game environment, no game or player instantiation")
	quit(0)
