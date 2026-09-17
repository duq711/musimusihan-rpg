extends Node
## A separate depth buffer for carried equipment. The original meshes stay in
## the gameplay world, so sword contacts, muzzle anchors, poses and lights keep
## their real transforms. Only their camera visibility changes.

const EQUIPMENT_LAYER := 1 << 19
const RESOLUTION_BUDGET := preload("res://scripts/render_resolution_budget.gd")

var source_camera: Camera3D
var viewport: SubViewport
var camera: Camera3D
var overlay: CanvasLayer
var display: TextureRect
var equipment_lights: Array[Light3D] = []
var _source_lights: Array[Light3D] = []
var _carried_roots: Array[Node3D] = []
var _source_viewport: Viewport
var _source_environment: Environment
var _original_cull_mask := 0
var _original_scaling_mode := Viewport.SCALING_3D_MODE_BILINEAR
var _original_scaling_scale := 1.0


func setup(camera_ref: Camera3D, carried_roots: Array) -> void:
	source_camera = camera_ref
	_source_viewport = source_camera.get_viewport()
	_original_scaling_mode = _source_viewport.scaling_3d_mode
	_original_scaling_scale = _source_viewport.scaling_3d_scale
	_original_cull_mask = source_camera.cull_mask
	_carried_roots.assign(carried_roots)
	source_camera.cull_mask &= ~EQUIPMENT_LAYER
	for carried in carried_roots:
		_assign_equipment_layer(carried)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100

	viewport = SubViewport.new()
	viewport.name = "EquipmentViewport"
	viewport.transparent_bg = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.world_3d = source_camera.get_world_3d()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)

	camera = Camera3D.new()
	camera.name = "EquipmentCamera"
	camera.cull_mask = EQUIPMENT_LAYER
	viewport.add_child(camera)
	camera.current = true
	_create_equipment_lights()

	overlay = CanvasLayer.new()
	overlay.name = "EquipmentOverlay"
	# The world is beneath layer 0; the normal HUD is on layer 1 and inventory,
	# camp and test-room menus are higher. No UI input belongs to this layer.
	overlay.layer = 0
	overlay.custom_viewport = _source_viewport
	add_child(overlay)
	display = TextureRect.new()
	display.name = "EquipmentImage"
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.focus_mode = Control.FOCUS_NONE
	overlay.add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sync_view()


func _process(_delta: float) -> void:
	sync_view()


func sync_view() -> void:
	if not is_instance_valid(source_camera) or not source_camera.is_inside_tree():
		return
	var carried_visible := false
	for carried in _carried_roots:
		if is_instance_valid(carried) and carried.is_visible_in_tree():
			carried_visible = true
			break
	var active := carried_visible and _source_viewport.get_camera_3d() == source_camera and source_camera.is_visible_in_tree()
	overlay.visible = active
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	# Match the source viewport's internal render dimensions, including stretch
	# scaling and nested off-screen previews, rather than the native window size.
	var view_size := RESOLUTION_BUDGET.render_size_for(_source_viewport)
	var budget_scale := minf(_original_scaling_scale, RESOLUTION_BUDGET.scale_for(view_size))
	if not is_equal_approx(_source_viewport.scaling_3d_scale, budget_scale):
		_source_viewport.scaling_3d_scale = budget_scale
	# FSR2 reconstructs only the world image. Text/HUD retain native pixels,
	# and transparent carried equipment keeps its separate, non-temporal pass.
	var scaling_mode := Viewport.SCALING_3D_MODE_FSR2 if budget_scale < _original_scaling_scale else _original_scaling_mode
	if _source_viewport.scaling_3d_mode != scaling_mode:
		_source_viewport.scaling_3d_mode = scaling_mode
	var equipment_size := RESOLUTION_BUDGET.equipment_size_for(view_size)
	if viewport.size != equipment_size:
		viewport.size = equipment_size
	viewport.msaa_3d = _source_viewport.msaa_3d
	viewport.screen_space_aa = _source_viewport.screen_space_aa
	# TAA smears translucent flame edges against a transparent background.
	viewport.use_taa = false
	camera.global_transform = source_camera.global_transform
	camera.projection = source_camera.projection
	camera.fov = source_camera.fov
	camera.size = source_camera.size
	camera.keep_aspect = source_camera.keep_aspect
	camera.frustum_offset = source_camera.frustum_offset
	camera.h_offset = source_camera.h_offset
	camera.v_offset = source_camera.v_offset
	camera.near = minf(source_camera.near, 0.025)
	camera.far = source_camera.far
	_sync_environment()
	_sync_lights()


func _create_equipment_lights() -> void:
	# Camera culling applies to Light3D.layers too, not only to meshes. World
	# lights remain on layer 1 and therefore cannot illuminate this camera's
	# layer-20 image. Mirror the carried torch/staff lights into this pass only;
	# copying their light_cull_mask alone would leave black silhouettes.
	for source: Light3D in source_camera.find_children("*", "Light3D", true, false):
		var light := source.duplicate(0) as Light3D
		light.name = "Equipment" + source.name
		light.layers = EQUIPMENT_LAYER
		light.light_cull_mask = EQUIPMENT_LAYER
		light.shadow_enabled = false
		light.light_bake_mode = Light3D.BAKE_DISABLED
		light.light_indirect_energy = 0.0
		light.light_volumetric_fog_energy = 0.0
		camera.add_child(light)
		_source_lights.append(source)
		equipment_lights.append(light)


func _sync_lights() -> void:
	for index in equipment_lights.size():
		var source := _source_lights[index]
		var light := equipment_lights[index]
		if not is_instance_valid(source):
			light.visible = false
			continue
		light.global_transform = source.global_transform
		light.visible = source.is_visible_in_tree()
		light.light_color = source.light_color
		light.light_energy = source.light_energy
		light.light_specular = source.light_specular
		if light is OmniLight3D:
			(light as OmniLight3D).omni_range = (source as OmniLight3D).omni_range
			(light as OmniLight3D).omni_attenuation = (source as OmniLight3D).omni_attenuation
		elif light is SpotLight3D:
			(light as SpotLight3D).spot_range = (source as SpotLight3D).spot_range
			(light as SpotLight3D).spot_angle = (source as SpotLight3D).spot_angle
			(light as SpotLight3D).spot_attenuation = (source as SpotLight3D).spot_attenuation
			(light as SpotLight3D).spot_angle_attenuation = (source as SpotLight3D).spot_angle_attenuation


func _sync_environment() -> void:
	var environment := source_camera.environment
	if environment == null:
		environment = source_camera.get_world_3d().environment
	if environment == _source_environment and camera.environment != null:
		return
	_source_environment = environment
	var equipment_environment := environment.duplicate() as Environment if environment != null else Environment.new()
	# Keep the world's exposure, ambient lighting and reflections, but exclude
	# sky, distant fog and screen-space effects that belong to the world image.
	equipment_environment.background_mode = Environment.BG_CLEAR_COLOR
	equipment_environment.fog_enabled = false
	equipment_environment.volumetric_fog_enabled = false
	equipment_environment.ssao_enabled = false
	equipment_environment.ssil_enabled = false
	equipment_environment.ssr_enabled = false
	# Flames already contain their authored soft glow geometry. Avoid a second
	# full-screen bloom chain over the mostly transparent equipment image.
	equipment_environment.glow_enabled = false
	camera.environment = equipment_environment


func _assign_equipment_layer(node: Node) -> void:
	if node is VisualInstance3D and not node is Light3D:
		(node as VisualInstance3D).layers = EQUIPMENT_LAYER
	for child in node.get_children():
		_assign_equipment_layer(child)


func _exit_tree() -> void:
	if is_instance_valid(source_camera):
		source_camera.cull_mask = _original_cull_mask
	if is_instance_valid(_source_viewport):
		_source_viewport.scaling_3d_mode = _original_scaling_mode
		_source_viewport.scaling_3d_scale = _original_scaling_scale
