extends SceneTree

# Four-view turntable QA for the runtime-articulated enemy GLBs.

const PREVIEW_SIZE := Vector2i(512, 512)
const PREVIEW_DIR := "res://previews/enemies"
const ASSETS := ["sanctuary_warden_3d", "ossuary_keeper_3d"]
const VIEWS := [
	{"name": "front", "direction": Vector3(0, 0.06, -1)},
	{"name": "three_quarter", "direction": Vector3(0.72, 0.10, -1)},
	{"name": "side", "direction": Vector3(1, 0.06, 0)},
	{"name": "back", "direction": Vector3(0, 0.06, 1)},
]

var viewport: SubViewport
var stage: Node3D
var asset_holder: Node3D
var camera: Camera3D
var floor_mesh: MeshInstance3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	_build_world()
	var images: Array[Image] = []

	for asset_name in ASSETS:
		for child in asset_holder.get_children():
			child.free()
		var packed := load("res://out/%s.glb" % asset_name) as PackedScene
		if packed == null:
			push_error("Cannot load preview asset %s" % asset_name)
			quit(1)
			return
		var asset := packed.instantiate() as Node3D
		asset_holder.add_child(asset)
		await process_frame
		var bounds := _scene_bounds(asset)
		floor_mesh.position.y = bounds.position.y - 0.018

		for view_definition in VIEWS:
			_frame_asset(bounds, view_definition.direction)
			viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			await process_frame
			await process_frame
			RenderingServer.force_draw(false)
			var image := viewport.get_texture().get_image()
			image.convert(Image.FORMAT_RGBA8)
			var output_path := "%s/%s_%s.png" % [PREVIEW_DIR, asset_name, view_definition.name]
			var save_error := image.save_png(ProjectSettings.globalize_path(output_path))
			if save_error != OK:
				push_error("Cannot write %s: %s" % [output_path, error_string(save_error)])
				quit(1)
				return
			images.append(image)

	var contact := Image.create(PREVIEW_SIZE.x * VIEWS.size(), PREVIEW_SIZE.y * ASSETS.size(), false, Image.FORMAT_RGBA8)
	contact.fill(Color("#07090a"))
	for index in range(images.size()):
		var destination := Vector2i((index % VIEWS.size()) * PREVIEW_SIZE.x, (index / VIEWS.size()) * PREVIEW_SIZE.y)
		contact.blit_rect(images[index], Rect2i(Vector2i.ZERO, PREVIEW_SIZE), destination)
	var contact_path := "%s/enemy_contact_sheet.png" % PREVIEW_DIR
	var contact_error := contact.save_png(ProjectSettings.globalize_path(contact_path))
	if contact_error != OK:
		push_error("Cannot write contact sheet: %s" % error_string(contact_error))
		quit(1)
		return
	print("Rendered %d enemy turntable views to %s" % [images.size(), ProjectSettings.globalize_path(contact_path)])
	quit(0)


func _build_world() -> void:
	viewport = SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	stage = Node3D.new()
	viewport.add_child(stage)
	asset_holder = Node3D.new()
	stage.add_child(asset_holder)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#080c0e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#70858c")
	environment.ambient_light_energy = 0.55
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 28, 0)
	key.light_color = Color("#ffd0a0")
	key.light_energy = 2.05
	key.shadow_enabled = true
	stage.add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.8, 3.0, -3.0)
	fill.light_color = Color("#4d9baa")
	fill.light_energy = 4.2
	fill.omni_range = 9.0
	stage.add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(2.7, 2.8, 2.8)
	rim.light_color = Color("#b54120")
	rim.light_energy = 3.5
	rim.omni_range = 9.0
	stage.add_child(rim)

	floor_mesh = MeshInstance3D.new()
	var floor := PlaneMesh.new()
	floor.size = Vector2(8, 8)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#111514")
	floor_material.metallic = 0.08
	floor_material.roughness = 0.72
	floor.material = floor_material
	floor_mesh.mesh = floor
	stage.add_child(floor_mesh)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 34.0
	camera.near = 0.025
	camera.far = 30.0
	stage.add_child(camera)


func _scene_bounds(root: Node) -> AABB:
	var found := false
	var combined := AABB()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var mesh_node := node as MeshInstance3D
			var world_aabb := mesh_node.global_transform * mesh_node.get_aabb()
			combined = world_aabb if not found else combined.merge(world_aabb)
			found = true
		for child in node.get_children():
			pending.append(child)
	return combined if found else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _frame_asset(bounds: AABB, direction: Vector3) -> void:
	var center := bounds.get_center()
	center.y = bounds.position.y + bounds.size.y * 0.49
	var normalized_direction := direction.normalized()
	var distance := maxf(3.2, bounds.size.y * 1.75)
	camera.position = center + normalized_direction * distance
	camera.look_at(center + Vector3(0, bounds.size.y * 0.01, 0), Vector3.UP)
