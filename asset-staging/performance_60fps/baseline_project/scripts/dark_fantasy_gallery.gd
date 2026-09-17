extends Control
## The in-game gallery and offline renderer share the same actual production
## factories, world, lighting and six cameras. No expedition or input ownership.

signal closed

const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const VIEWS: Array[String] = ["front", "back", "left", "right", "top", "bottom"]
const VIEW_LABELS: Array[String] = ["정면", "후면", "왼쪽", "오른쪽", "위", "아래"]
const DIRECTIONS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3.UP, Vector3.DOWN]
const CAPTURE_SIZE := Vector2i(512, 512)

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var light_rig: Node3D
var object_root: Node3D
var object_bounds := AABB()
var object_id := ""
var selected_view := "front"
var selector: OptionButton
var view_buttons: Array[Button] = []
var close_button: Button
var description: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_viewport()
	_build_controls()
	visibility_changed.connect(_update_rendering)
	var objects := CATALOG.entries()
	if not objects.is_empty():
		select_object(str(objects[0].id))
	_update_rendering()


func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.name = "ProductionObjectViewport"
	viewport.size = CAPTURE_SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.audio_listener_enable_2d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	stage = Node3D.new()
	stage.name = "ProductionObjectStage"
	viewport.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#171a1a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b0b9bd")
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	stage.add_child(environment_node)
	camera = Camera3D.new()
	camera.name = "SixDirectionCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = 0xFFFFF
	camera.current = true
	stage.add_child(camera)
	light_rig = Node3D.new()
	light_rig.name = "CameraRelativeLighting"
	stage.add_child(light_rig)
	_add_light(Vector3(-32, -35, 0), Color("#e4d7c2"), 1.15)
	_add_light(Vector3(20, 50, 0), Color("#aabcc5"), 0.48)
	_add_light(Vector3(-20, 155, 0), Color("#b2bcb4"), 0.32)


func _add_light(angles: Vector3, color: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angles
	light.light_color = color
	light.light_energy = energy
	light.light_cull_mask = 0xFFFFF
	light.shadow_enabled = true
	light_rig.add_child(light)


func _build_controls() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = Color("#101513")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "어둠의 오브젝트 도감"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	selector = OptionButton.new()
	selector.name = "ObjectSelector"
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.focus_mode = Control.FOCUS_NONE
	var objects := CATALOG.entries()
	for entry in objects:
		selector.add_item(str(entry.title))
	selector.item_selected.connect(func(index: int) -> void: select_object(str(objects[index].id)))
	column.add_child(selector)
	var display := TextureRect.new()
	display.name = "ProductionObjectRender"
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(display)
	description = Label.new()
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)
	var views := HBoxContainer.new()
	views.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(views)
	for index in VIEWS.size():
		var button := Button.new()
		button.name = "View_" + VIEWS[index]
		button.text = VIEW_LABELS[index]
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(72, 34)
		button.pressed.connect(set_view.bind(VIEWS[index]))
		views.add_child(button)
		view_buttons.append(button)
	close_button = Button.new()
	close_button.name = "CloseGallery"
	close_button.text = "시험 메뉴로 돌아가기 · F2 / Esc"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: closed.emit())
	column.add_child(close_button)


func select_object(id: String) -> bool:
	var entries := CATALOG.entries()
	var index := -1
	for candidate in entries.size():
		if str(entries[candidate].id) == id:
			index = candidate
			break
	if index < 0:
		return false
	var next_object := CATALOG.build_object(id)
	if not is_instance_valid(next_object):
		return false
	if is_instance_valid(object_root):
		stage.remove_child(object_root)
		object_root.free()
	object_root = next_object
	object_root.process_mode = Node.PROCESS_MODE_DISABLED
	stage.add_child(object_root)
	_disable_simulation(object_root)
	object_id = id
	object_bounds = mesh_bounds(object_root)
	selector.select(index)
	description.text = "%s · 실제 게임 3D 모델 · 정면 / 후면 / 좌 / 우 / 상 / 하" % str(entries[index].title)
	set_view("front")
	return object_bounds.size.length() > 0.001


func set_view(view_name: String) -> bool:
	var index := VIEWS.find(view_name)
	if index < 0 or not is_instance_valid(object_root):
		return false
	selected_view = view_name
	var radius := maxf(object_bounds.size.length() * 0.5, 0.1)
	var center := object_bounds.get_center()
	var direction := DIRECTIONS[index]
	camera.position = center + direction * (radius * 3.0 + 1.0)
	camera.near = 0.01
	camera.far = radius * 8.0 + 10.0
	var up := Vector3.FORWARD if index >= 4 else Vector3.UP
	camera.look_at(center, up)
	camera.size = maxf(maxf(object_bounds.size.x, object_bounds.size.y), object_bounds.size.z) * 1.2 + 0.01
	light_rig.transform = camera.transform
	for button_index in view_buttons.size():
		view_buttons[button_index].set_pressed_no_signal(button_index == index)
	return true


func _update_rendering() -> void:
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


static func _disable_simulation(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_ALWAYS if node is CPUParticles3D else Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		_disable_simulation(child)


static func mesh_bounds(object: Node3D) -> AABB:
	var collected: Array[AABB] = []
	_collect_bounds(object, object.global_transform.affine_inverse(), collected)
	var bounds := AABB()
	for index in collected.size():
		bounds = bounds.merge(collected[index]) if index > 0 else collected[index]
	return object.transform * bounds


static func _collect_bounds(node: Node, inverse: Transform3D, collected: Array[AABB]) -> void:
	if node is MeshInstance3D and node.mesh != null and node.visible:
		collected.append(inverse * node.global_transform * node.mesh.get_aabb())
	elif node is Sprite3D and node.texture != null and node.visible:
		collected.append(inverse * node.global_transform * node.get_aabb())
	elif node is CPUParticles3D and node.mesh != null and node.visible:
		# Bound the actual production emitter and its full lifetime trajectory.
		# Built-in particles are visual-only; all gameplay scripts remain absent.
		var extent: Vector3 = node.emission_box_extents if node.emission_shape == CPUParticles3D.EMISSION_SHAPE_BOX else Vector3.ONE * node.emission_sphere_radius
		var travel: Vector3 = node.direction.normalized() * node.initial_velocity_max * node.lifetime + node.gravity * 0.5 * node.lifetime * node.lifetime
		var particle_bounds := AABB(-extent, extent * 2.0).merge(AABB(travel - extent, extent * 2.0)).grow(node.mesh.get_aabb().size.length())
		collected.append(inverse * node.global_transform * particle_bounds)
	elif node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null and node.visible:
		var multimesh := node.multimesh as MultiMesh
		for index in multimesh.instance_count:
			collected.append(inverse * node.global_transform * multimesh.get_instance_transform(index) * multimesh.mesh.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, inverse, collected)


func _exit_tree() -> void:
	CATALOG.release_cached_templates()
