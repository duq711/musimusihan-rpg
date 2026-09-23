extends SceneTree
## Windowless, real-renderer review of the source outfit on the playable player.
## The unrigged garment stays intact while movement changes the player's pose.

const APPEARANCE := preload("res://scripts/player_appearance.gd")
const SIZE := Vector2i(960, 1200)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_cloth"

var _failed := false
var _output := ""
var _captures: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Player cloth preview requires the approved embedded renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_CLOTH_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_CLOTH_QA_ITERATION must be a new plain folder name.")
		quit(2)
		return
	_output = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(_output):
		push_error("Player cloth review never overwrites an existing capture folder: " + _output)
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_output)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor := Input.mouse_mode
	var expedition := ExpeditionSession.capture_snapshot()
	var viewport := _make_viewport()
	var stage := Node3D.new()
	viewport.add_child(stage)
	_add_stage(stage)
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.position = Vector3(0.0, 0.90, 0.0)
	player.camera.visible = false
	player.camera.current = false
	var camera := Camera3D.new()
	camera.name = "ExternalClothReviewCamera"
	camera.fov = 39.0
	camera.cull_mask |= APPEARANCE.BODY_LAYER
	stage.add_child(camera)
	camera.current = true
	var shirt := player.player_body.find_child("Medival_ShirtUpper", true, false) as MeshInstance3D
	if shirt == null:
		push_error("The production player has no original Medival shirt.")
		_failed = true
	else:
		for _frame in range(4):
			await physics_frame
		await _capture(viewport, camera, player, shirt, "rest_front", Vector3(0.0, 0.0, -3.4))
		await _advance(player, 18, Vector2(0.0, -1.0), false)
		await _capture(viewport, camera, player, shirt, "walk_front", Vector3(0.0, 0.0, -3.4))
		await _capture(viewport, camera, player, shirt, "walk_side", Vector3(3.4, 0.0, 0.0))
		await _advance(player, 24, Vector2(0.0, -1.0), true)
		await _capture(viewport, camera, player, shirt, "sprint_front", Vector3(0.0, 0.0, -3.4))
		await _advance(player, 5, Vector2.ZERO, false)
		await _capture(viewport, camera, player, shirt, "stop_front", Vector3(0.0, 0.0, -3.4))
		await _advance(player, 55, Vector2.ZERO, false)
		await _capture(viewport, camera, player, shirt, "settled_front", Vector3(0.0, 0.0, -3.4))
		await _capture(viewport, camera, player, shirt, "settled_back", Vector3(0.0, 0.0, 3.4))
	viewport.queue_free()
	await process_frame
	var preserved := cursor == Input.mouse_mode and expedition == ExpeditionSession.capture_snapshot()
	_failed = _failed or not preserved
	var manifest := {
		"display_driver": DisplayServer.get_name(),
		"rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"capture_kind": "Actual DungeonPlayer and intact source outfit mesh in an isolated SubViewport",
		"model_sha256": FileAccess.get_sha256(APPEARANCE.MODEL_PATH),
		"outfit_sha256": FileAccess.get_sha256(APPEARANCE.OUTFIT_PATH),
		"cursor_and_expedition_preserved": preserved,
		"frames": _captures,
	}
	var file := FileAccess.open(_output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		_failed = true
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("PLAYER CLOTH PREVIEW %s: %d actual-renderer frames; %s" % ["FAIL" if _failed else "PASS", _captures.size(), _output])
	quit(1 if _failed else 0)


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _add_stage(stage: Node3D) -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("#24282a")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color(0.65, 0.70, 0.75)
	world.environment.ambient_light_energy = 0.55
	stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -30.0, 0.0)
	key.light_energy = 2.1
	stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	fill.light_energy = 0.55
	stage.add_child(fill)
	var floor := StaticBody3D.new()
	floor.collision_layer = DungeonPlayer.WORLD_LAYER
	floor.collision_mask = 0
	floor.position.y = -0.10
	stage.add_child(floor)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.20, 60.0)
	shape.shape = box
	floor.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60.0, 60.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#35342e")
	ground.material_override = ground_material
	stage.add_child(ground)


func _advance(player: DungeonPlayer, frames: int, input: Vector2, sprint: bool) -> void:
	for _frame in range(frames):
		player.advance_movement(1.0 / 60.0, input, sprint)
		await physics_frame


func _capture(viewport: SubViewport, camera: Camera3D, player: DungeonPlayer, shirt: MeshInstance3D, label: String, offset: Vector3) -> void:
	camera.global_position = player.global_position + offset
	camera.look_at(player.global_position, Vector3.UP)
	for _frame in range(3):
		await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("No actual image for " + label)
		_failed = true
		return
	var filename := label + ".png"
	if image.save_png(_output.path_join(filename)) != OK:
		push_error("Could not save " + filename)
		_failed = true
		return
	_captures.append({"file": filename, "player_position": player.global_position, "velocity": player.velocity, "shirt_bounds": shirt.mesh.get_aabb()})
