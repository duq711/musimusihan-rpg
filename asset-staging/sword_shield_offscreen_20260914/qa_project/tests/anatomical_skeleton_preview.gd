extends SceneTree

const OUTPUT_DIR := "res://artifacts/visual_qa"
const IMAGE_SIZE := Vector2i(720, 720)

var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var enemy: DungeonEnemy


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_stage()
	enemy = DungeonEnemy.new()
	enemy.configure("굶주린 성소지기", 1.0, 1.0, 1.0, Color.WHITE)
	enemy.position.y = 0.90
	stage.add_child(enemy)
	enemy.set_physics_process(false)
	enemy._update_weapon_pose(1.0)
	enemy._update_visual_pose(1.0)
	await process_frame
	var bounds := _scene_bounds(enemy.model_root)
	var names: Array[String] = ["front", "three_quarter", "side", "back"]
	var directions: Array[Vector3] = [
		Vector3(0.0, 0.025, -1.0),
		Vector3(-0.66, 0.035, -1.0),
		Vector3(-1.0, 0.025, 0.0),
		Vector3(0.0, 0.025, 1.0),
	]
	var images: Array[Image] = []
	for index in range(names.size()):
		_frame(bounds, directions[index])
		images.append(await _capture("anatomical_skeleton_%s.png" % names[index]))

	enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	enemy._update_weapon_pose(1.0)
	enemy._update_visual_pose(1.0)
	await process_frame
	bounds = _scene_bounds(enemy.model_root)
	_frame(bounds, Vector3(0.0, 0.025, -1.0))
	images.append(await _capture("anatomical_skeleton_reference_pose.png"))

	var contact := Image.create(IMAGE_SIZE.x * images.size(), IMAGE_SIZE.y, false, Image.FORMAT_RGBA8)
	contact.fill(Color("#080a09"))
	for index in range(images.size()):
		contact.blit_rect(images[index], Rect2i(Vector2i.ZERO, IMAGE_SIZE), Vector2i(index * IMAGE_SIZE.x, 0))
	var output_path := ProjectSettings.globalize_path("%s/anatomical_skeleton_turnaround.png" % OUTPUT_DIR)
	var error := contact.save_png(output_path)
	if error != OK:
		push_error("Could not save anatomical contact sheet: %s" % error_string(error))
		quit(1)
		return
	print("ANATOMICAL SKELETON PREVIEW PASS: %s" % output_path)
	quit(0)


func _build_stage() -> void:
	viewport = SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#080b0a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#89948d")
	environment.ambient_light_energy = 0.42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -28.0, 0.0)
	key.light_color = Color("#e3c08e")
	key.light_energy = 1.15
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(2.2, 2.5, -2.8)
	fill.light_color = Color("#8aa9a0")
	fill.light_energy = 1.35
	fill.omni_range = 7.0
	stage.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.3, 2.4, 2.2)
	rim.light_color = Color("#9b653e")
	rim.light_energy = 1.1
	rim.omni_range = 7.0
	stage.add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(6.0, 6.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#181814")
	floor_material.roughness = 0.94
	floor.material = floor_material
	floor_mesh.mesh = floor
	stage.add_child(floor_mesh)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 32.0
	camera.near = 0.025
	camera.far = 30.0
	stage.add_child(camera)


func _capture(file_name: String) -> Image:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var captured := viewport.get_texture().get_image()
	captured.convert(Image.FORMAT_RGBA8)
	var path := ProjectSettings.globalize_path("%s/%s" % [OUTPUT_DIR, file_name])
	var error := captured.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
	return captured


func _scene_bounds(scene_root: Node) -> AABB:
	var found := false
	var combined := AABB()
	var pending: Array[Node] = [scene_root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).visible:
			var mesh_node := node as MeshInstance3D
			var world_bounds := mesh_node.global_transform * mesh_node.get_aabb()
			combined = world_bounds if not found else combined.merge(world_bounds)
			found = true
		for child in node.get_children():
			pending.append(child)
	return combined if found else AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


func _frame(bounds: AABB, direction: Vector3) -> void:
	var center := bounds.get_center()
	var extent := maxf(bounds.size.y, bounds.size.x * 1.05)
	var distance := maxf(3.25, extent * 2.08)
	camera.position = center + direction.normalized() * distance
	camera.look_at(center + Vector3(0.0, bounds.size.y * 0.015, 0.0), Vector3.UP)
