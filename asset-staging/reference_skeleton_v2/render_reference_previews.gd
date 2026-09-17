extends SceneTree

const MODEL := "res://out/reference_skeleton_3d.glb"
const PREVIEW_DIR := "res://previews"
const SIZE := Vector2i(720, 720)
const VIEWS := [
	{"name": "front", "direction": Vector3(0, 0.035, -1)},
	{"name": "three_quarter", "direction": Vector3(0.68, 0.05, -1)},
	{"name": "side", "direction": Vector3(1, 0.04, 0)},
	{"name": "back", "direction": Vector3(0, 0.04, 1)},
]

var viewport: SubViewport
var stage: Node3D
var holder: Node3D
var camera: Camera3D
var floor_mesh: MeshInstance3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PREVIEW_DIR))
	_build_stage()
	var packed := load(MODEL) as PackedScene
	if packed == null:
		push_error("Could not load %s" % MODEL)
		quit(1)
		return
	var skeleton := packed.instantiate() as Node3D
	holder.add_child(skeleton)
	await process_frame
	var images: Array[Image] = []
	var bounds := _scene_bounds(skeleton)
	for view in VIEWS:
		_frame(bounds, view.direction)
		images.append(await _capture("reference_skeleton_v2_%s.png" % view.name))

	_apply_reference_pose(skeleton)
	await process_frame
	var pose_bounds := _scene_bounds(skeleton)
	_frame(pose_bounds, Vector3(0.52, 0.04, -1))
	images.append(await _capture("reference_skeleton_v2_reference_pose.png"))

	var contact := Image.create(SIZE.x * images.size(), SIZE.y, false, Image.FORMAT_RGBA8)
	contact.fill(Color("#070908"))
	for index in range(images.size()):
		contact.blit_rect(images[index], Rect2i(Vector2i.ZERO, SIZE), Vector2i(index * SIZE.x, 0))
	var contact_path := ProjectSettings.globalize_path("%s/reference_skeleton_v2_contact_sheet.png" % PREVIEW_DIR)
	var error := contact.save_png(contact_path)
	if error != OK:
		push_error("Could not save contact sheet: %s" % error_string(error))
		quit(1)
		return
	print("Rendered front, 3/4, side, back, and reference-pose previews: %s" % contact_path)
	quit(0)


func _build_stage() -> void:
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
	environment.ambient_light_color = Color("#a7b1ad")
	environment.ambient_light_energy = 0.48
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 24, 0)
	key.light_color = Color("#ffd6a1")
	key.light_energy = 1.35
	key.shadow_enabled = true
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-2.5, 2.8, -3.1)
	fill.light_color = Color("#72a9ae")
	fill.light_energy = 2.1
	fill.omni_range = 8.0
	stage.add_child(fill)
	var rim := OmniLight3D.new()
	rim.position = Vector3(2.6, 2.5, 2.7)
	rim.light_color = Color("#b8733c")
	rim.light_energy = 1.8
	rim.omni_range = 8.0
	stage.add_child(rim)

	floor_mesh = MeshInstance3D.new()
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
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var path := ProjectSettings.globalize_path("%s/%s" % [PREVIEW_DIR, file_name])
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save %s: %s" % [path, error_string(error)])
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
	center.y = bounds.position.y + bounds.size.y * 0.50
	var max_extent := maxf(bounds.size.y, bounds.size.x * 1.04)
	var distance := maxf(3.0, max_extent * 1.86)
	camera.position = center + direction.normalized() * distance
	camera.look_at(center + Vector3(0, bounds.size.y * 0.015, 0), Vector3.UP)


func _apply_reference_pose(skeleton: Node3D) -> void:
	# Mirrors the expressive raised-arm, bent-leg silhouette of the supplied image
	# without baking that source image or its watermark into the model.
	var arm_l := skeleton.get_node("VisualRoot/TorsoPivot/ArmLPivot") as Node3D
	var arm_r := skeleton.get_node("VisualRoot/TorsoPivot/ArmRPivot") as Node3D
	var elbow_l := skeleton.get_node("VisualRoot/TorsoPivot/ArmLPivot/ElbowLPivot") as Node3D
	var elbow_r := skeleton.get_node("VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot") as Node3D
	var wrist_l := skeleton.get_node("VisualRoot/TorsoPivot/ArmLPivot/ElbowLPivot/WristLPivot") as Node3D
	var wrist_r := skeleton.get_node("VisualRoot/TorsoPivot/ArmRPivot/ElbowRPivot/WristRPivot") as Node3D
	var leg_l := skeleton.get_node("VisualRoot/LegLPivot") as Node3D
	var leg_r := skeleton.get_node("VisualRoot/LegRPivot") as Node3D
	var knee_l := skeleton.get_node("VisualRoot/LegLPivot/KneeLPivot") as Node3D
	var knee_r := skeleton.get_node("VisualRoot/LegRPivot/KneeRPivot") as Node3D
	arm_l.rotation_degrees = Vector3(-18, -12, -104)
	elbow_l.rotation_degrees = Vector3(-18, -18, -64)
	wrist_l.rotation_degrees = Vector3(8, -8, -18)
	arm_r.rotation_degrees = Vector3(6, 8, 108)
	elbow_r.rotation_degrees = Vector3(-10, 10, 13)
	wrist_r.rotation_degrees = Vector3(-6, 8, 16)
	leg_l.rotation_degrees = Vector3(-14, -8, -35)
	knee_l.rotation_degrees = Vector3(-10, 4, 28)
	leg_r.rotation_degrees = Vector3(9, 8, 28)
	knee_r.rotation_degrees = Vector3(-22, -6, -30)
