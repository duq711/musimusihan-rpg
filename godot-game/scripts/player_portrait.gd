extends Control
## An isolated view of the same model as DungeonPlayer. No expedition or input
## state is owned here; buttons remain usable while the inventory pauses play.

const APPEARANCE := preload("res://scripts/player_appearance.gd")

var body: Node3D
var camera: Camera3D
var viewport: SubViewport
var left_button: Button
var right_button: Button
var reset_button: Button
var _view_angle := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.name = "CharacterViewport"
	viewport.size = Vector2i(472, 560)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	body = APPEARANCE.create_body()
	viewport.add_child(body)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.02, 0.023, 0.025, 0.0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.72, 0.72, 0.72)
	environment.environment.ambient_light_energy = 0.42
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	viewport.add_child(environment)
	_add_light(Vector3(-1.5, 2.6, -2.5), Color(0.95, 0.95, 0.94), 1.3)
	_add_light(Vector3(1.2, 1.8, -1.5), Color(0.98, 0.84, 0.68), 0.4)
	_add_light(Vector3(0.5, 2.2, 1.2), Color(0.68, 0.72, 0.75), 0.24)
	camera = Camera3D.new()
	camera.name = "CharacterCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	# Frame the visible shirt-to-trouser outfit, rather than the hidden head and boots.
	camera.size = 1.63
	camera.position = Vector3(0.0, 0.855, -3.5)
	camera.cull_mask = APPEARANCE.BODY_LAYER
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.855, 0.0))
	camera.current = true
	var display := TextureRect.new()
	display.name = "CharacterRender"
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.offset_bottom = -23.0
	left_button = _button("ViewLeft", "‹", 0.12, "왼쪽으로 돌리기")
	right_button = _button("ViewRight", "›", 0.73, "오른쪽으로 돌리기")
	reset_button = _button("ViewReset", "정면", 0.37, "정면으로 되돌리기")
	left_button.pressed.connect(func() -> void: set_view_angle(_view_angle - 30.0))
	right_button.pressed.connect(func() -> void: set_view_angle(_view_angle + 30.0))
	reset_button.pressed.connect(func() -> void: set_view_angle(0.0))
	visibility_changed.connect(_update_rendering)
	_update_rendering()


func set_view_angle(degrees: float) -> void:
	if not is_finite(degrees):
		return
	_view_angle = wrapf(degrees, -180.0, 180.0)
	if is_instance_valid(body):
		body.rotation.y = deg_to_rad(_view_angle)


func get_view_angle() -> float:
	return _view_angle


func _update_rendering() -> void:
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _button(node_name: String, text_value: String, anchor: float, tooltip: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	# Keep the controls above the inventory ring's foreground ornaments.
	button.z_index = 3
	# Opaque fills prevent the ring's lower diamond showing through the label.
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.055, 0.055, 0.048, 1.0) if state == "normal" else Color(0.12, 0.115, 0.09, 1.0)
		style.set_corner_radius_all(3)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_font_size_override("font_size", 12)
	button.custom_minimum_size = Vector2(40, 22)
	add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	button.anchor_left = anchor
	button.anchor_right = anchor
	button.offset_top = -22
	button.offset_bottom = 0
	button.offset_right = 40 if text_value != "정면" else 62
	return button


func _add_light(location: Vector3, color: Color, energy: float) -> void:
	var light := OmniLight3D.new()
	light.position = location
	light.light_color = color
	light.light_energy = energy
	light.light_specular = 0.12
	light.omni_range = 7.0
	light.layers = APPEARANCE.BODY_LAYER
	light.light_cull_mask = APPEARANCE.BODY_LAYER
	viewport.add_child(light)
