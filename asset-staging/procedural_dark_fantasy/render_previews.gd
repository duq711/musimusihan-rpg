extends SceneTree

# Optional visual QA helper. It renders each imported GLB with the same neutral
# three-point lighting and writes thumbnails plus a contact sheet to previews/.

const PREVIEW_SIZE := Vector2i(512, 512)
const PREVIEW_DIR := "res://previews"

var viewport: SubViewport
var stage: Node3D
var asset_holder: Node3D
var camera: Camera3D
var floor_mesh: MeshInstance3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	_build_preview_world()
	var names := [
		"rusted_longsword", "weathered_round_shield", "iron_cage_torch", "reliquary_chest",
		"blood_rune_trap", "sanctum_portal_arch", "dungeon_floor_4m", "dungeon_wall_4m",
		"dungeon_archway_4m", "dungeon_pillar_3m", "dungeon_stairs_4m"
	]
	var images: Array[Image] = []
	for asset_name in names:
		for old_child in asset_holder.get_children():
			old_child.free()
		var packed := load("res://out/%s.glb" % asset_name) as PackedScene
		if packed == null:
			push_error("Cannot preview %s" % asset_name)
			quit(1)
			return
		var asset := packed.instantiate()
		asset_holder.add_child(asset)
		await process_frame
		var bounds := _scene_bounds(asset)
		_frame_asset(bounds)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await process_frame
		await process_frame
		RenderingServer.force_draw(false)
		var image := viewport.get_texture().get_image()
		image.convert(Image.FORMAT_RGBA8)
		image.save_png(ProjectSettings.globalize_path("%s/%s.png" % [PREVIEW_DIR, asset_name]))
		images.append(image)

	var contact := Image.create(PREVIEW_SIZE.x * 4, PREVIEW_SIZE.y * 3, false, Image.FORMAT_RGBA8)
	contact.fill(Color("#090b0c"))
	for index in range(images.size()):
		contact.blit_rect(images[index], Rect2i(Vector2i.ZERO, PREVIEW_SIZE), Vector2i((index % 4) * PREVIEW_SIZE.x, (index / 4) * PREVIEW_SIZE.y))
	contact.save_png(ProjectSettings.globalize_path("%s/contact_sheet.png" % PREVIEW_DIR))
	print("Rendered %d previews to %s" % [images.size(), ProjectSettings.globalize_path(PREVIEW_DIR)])
	quit(0)


func _build_preview_world() -> void:
	viewport = SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)

	stage = Node3D.new()
	viewport.add_child(stage)
	asset_holder = Node3D.new()
	stage.add_child(asset_holder)

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#0b1012")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#63727a")
	environment.ambient_light_energy = 0.42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_color = Color("#ffd0a3")
	key.light_energy = 1.85
	key.shadow_enabled = true
	stage.add_child(key)

	var fill := OmniLight3D.new()
	fill.position = Vector3(-3.5, 3.8, 3.2)
	fill.light_color = Color("#68a8bd")
	fill.light_energy = 5.0
	fill.omni_range = 12.0
	stage.add_child(fill)

	var rim := OmniLight3D.new()
	rim.position = Vector3(3.0, 4.0, -3.2)
	rim.light_color = Color("#c9411e")
	rim.light_energy = 3.2
	rim.omni_range = 10.0
	stage.add_child(rim)

	floor_mesh = MeshInstance3D.new()
	var floor_shape := PlaneMesh.new()
	floor_shape.size = Vector2(12, 12)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#111514")
	floor_material.roughness = 0.96
	floor_shape.material = floor_material
	floor_mesh.mesh = floor_shape
	stage.add_child(floor_mesh)

	camera = Camera3D.new()
	camera.current = true
	camera.fov = 39.0
	camera.near = 0.025
	camera.far = 100.0
	stage.add_child(camera)


func _scene_bounds(root: Node) -> AABB:
	var found := false
	var combined := AABB()
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D and node.visible and node.name.find("Collision") == -1:
			var mesh_node := node as MeshInstance3D
			var transformed := mesh_node.global_transform * mesh_node.get_aabb()
			combined = transformed if not found else combined.merge(transformed)
			found = true
		for child in node.get_children():
			pending.append(child)
	return combined if found else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


func _frame_asset(bounds: AABB) -> void:
	var center := bounds.get_center()
	var longest := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var distance := maxf(1.5, longest * 2.25)
	var lateral := distance * (0.42 if bounds.size.y > bounds.size.x * 1.25 else 0.62)
	camera.position = center + Vector3(lateral, distance * 0.28, distance)
	camera.look_at(center + Vector3(0, bounds.size.y * 0.02, 0), Vector3.UP)
	floor_mesh.position.y = bounds.position.y - 0.025

