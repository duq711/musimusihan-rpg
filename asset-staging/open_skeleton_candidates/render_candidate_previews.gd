extends SceneTree

const SIZE := Vector2i(720, 720)

var viewport: SubViewport
var stage: Node3D
var holder: Node3D
var camera: Camera3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var model_path := OS.get_environment("CANDIDATE_MODEL")
	var output_name := OS.get_environment("CANDIDATE_NAME")
	if model_path.is_empty() or output_name.is_empty():
		push_error("Set CANDIDATE_MODEL and CANDIDATE_NAME")
		quit(1)
		return
	_build_stage()
	var model: Node3D
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(model_path)):
		model = _load_obj_directory(model_path)
	else:
		var packed := load(model_path) as PackedScene
		if packed == null:
			push_error("Could not load %s" % model_path)
			quit(1)
			return
		model = packed.instantiate() as Node3D
	holder.add_child(model)
	_override_bone_material(model)
	await process_frame
	var bounds := _scene_bounds(model)
	if bounds.size.z > bounds.size.y and bounds.size.z > bounds.size.x:
		holder.rotation_degrees.x = -90.0
	elif bounds.size.x > bounds.size.y and bounds.size.x > bounds.size.z:
		holder.rotation_degrees.z = 90.0
	await process_frame
	bounds = _scene_bounds(model)
	var height := maxf(bounds.size.y, 0.001)
	holder.scale = Vector3.ONE * (1.85 / height)
	await process_frame
	bounds = _scene_bounds(model)
	holder.position = Vector3(-bounds.get_center().x, -bounds.position.y, -bounds.get_center().z)
	await process_frame
	bounds = _scene_bounds(model)
	var images: Array[Image] = []
	for view in [
		{"name": "front", "direction": Vector3(0, 0.035, -1)},
		{"name": "three_quarter", "direction": Vector3(0.68, 0.05, -1)},
		{"name": "side", "direction": Vector3(1, 0.04, 0)},
	]:
		_frame(bounds, view.direction)
		images.append(await _capture("%s_%s.png" % [output_name, view.name]))
	var contact := Image.create(SIZE.x * images.size(), SIZE.y, false, Image.FORMAT_RGBA8)
	contact.fill(Color("#070908"))
	for index in range(images.size()):
		contact.blit_rect(images[index], Rect2i(Vector2i.ZERO, SIZE), Vector2i(index * SIZE.x, 0))
	var contact_path := ProjectSettings.globalize_path("res://previews/%s_contact.png" % output_name)
	contact.save_png(contact_path)
	print("Rendered %s; meshes=%d; bounds=%s" % [contact_path, _mesh_count(model), bounds])
	quit(0)


func _build_stage() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://previews"))
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.msaa_3d = Viewport.MSAA_8X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	holder = Node3D.new()
	stage.add_child(holder)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0b0e0e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b4b8b0")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 24, 0)
	key.light_color = Color("#ffd4a0")
	key.light_energy = 1.15
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 2.8, -3.1)
	fill.light_color = Color("#73a9ad")
	fill.light_energy = 2.3
	fill.omni_range = 8.0
	stage.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(2.6, 2.5, 2.7)
	rim.light_color = Color("#b8733c")
	rim.light_energy = 1.9
	rim.omni_range = 8.0
	stage.add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(7, 7)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#161a18")
	floor_material.roughness = 0.92
	floor.material = floor_material
	floor_mesh.mesh = floor
	floor_mesh.position.y = -0.005
	stage.add_child(floor_mesh)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 31.0
	camera.near = 0.025
	camera.far = 30.0
	stage.add_child(camera)


func _capture(file_name: String) -> Image:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(ProjectSettings.globalize_path("res://previews/%s" % file_name))
	return image


func _scene_bounds(root: Node) -> AABB:
	var found := false
	var combined := AABB()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			var bounds := mesh_node.global_transform * mesh_node.get_aabb()
			combined = bounds if not found else combined.merge(bounds)
			found = true
		for child in node.get_children():
			pending.append(child)
	return combined if found else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _frame(bounds: AABB, direction: Vector3) -> void:
	var center := bounds.get_center()
	var max_extent := maxf(bounds.size.y, bounds.size.x * 1.04)
	var distance := maxf(3.0, max_extent * 1.86)
	camera.position = center + direction.normalized() * distance
	camera.look_at(center + Vector3(0, bounds.size.y * 0.015, 0), Vector3.UP)


func _mesh_count(root: Node) -> int:
	var count := 0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			count += 1
		for child in node.get_children():
			pending.append(child)
	return count


func _override_bone_material(root: Node) -> void:
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color("#74664f")
	bone.roughness = 0.82
	bone.metallic = 0.0
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			(node as MeshInstance3D).material_override = bone
		for child in node.get_children():
			pending.append(child)


func _load_obj_directory(resource_directory: String) -> Node3D:
	var root := Node3D.new()
	root.name = "OBJDirectory"
	for file_name in DirAccess.get_files_at(resource_directory):
		if not file_name.ends_with(".obj"):
			continue
		var mesh := load("%s/%s" % [resource_directory, file_name]) as Mesh
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.name = file_name.get_basename()
		instance.mesh = mesh
		root.add_child(instance)
	return root
