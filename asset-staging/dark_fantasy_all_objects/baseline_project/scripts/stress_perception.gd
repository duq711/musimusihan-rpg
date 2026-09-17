extends Node3D
class_name StressPerception

signal perception_triggered(kind: String)

const PROFILE := preload("res://scripts/stress_profile.gd")
const AUDIO := preload("res://scripts/stress_audio.gd")
const ENTRY_DELAY := 2.0
const GHOST_DURATION := 1.65
const WORLD_MASK := 2 | 4

var stress_value := 0.0
var active := false
var event_count := 0
var last_event := ""
var ghost: Node3D
var audio_player: AudioStreamPlayer3D
var vignette_layer: CanvasLayer
var vignette_rect: ColorRect
var player: DungeonPlayer
var rng := RandomNumberGenerator.new()

var _audio_due := ENTRY_DELAY
var _vision_due := ENTRY_DELAY
var _audio_remaining := 0.0
var _ghost_remaining := 0.0
var _ghost_material: StandardMaterial3D
var _event_gap := 0.0


func _init() -> void:
	rng.randomize()


func setup(player_ref: DungeonPlayer) -> void:
	if player != player_ref:
		clear_effects()
	player = player_ref


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "StressPerception"
	audio_player = AudioStreamPlayer3D.new()
	audio_player.name = "PerceivedSound"
	audio_player.volume_db = -20.0
	audio_player.max_db = -20.0
	audio_player.unit_size = 4.0
	audio_player.max_distance = 14.0
	audio_player.panning_strength = 0.9
	add_child(audio_player)
	vignette_layer = CanvasLayer.new()
	vignette_layer.name = "StressVignette"
	# Normal HUD is on layer 1, so the soft image-edge effect stays behind all
	# labels and buttons and never captures input.
	vignette_layer.layer = 0
	add_child(vignette_layer)
	vignette_rect = ColorRect.new()
	vignette_rect.name = "SoftEdges"
	vignette_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; uniform float intensity = 0.0; void fragment() { float edge = smoothstep(0.30, 0.77, distance(UV, vec2(0.5))); COLOR = vec4(0.025, 0.018, 0.035, edge * intensity); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	vignette_rect.material = material
	vignette_layer.add_child(vignette_rect)
	clear_effects()


func _exit_tree() -> void:
	clear_effects()


func _process(delta: float) -> void:
	advance(delta)


func update_stress(value: float) -> void:
	var previous := stress_value
	stress_value = clampf(value, 0.0, PROFILE.MAX_STRESS)
	if previous < PROFILE.AUDIO_THRESHOLD and stress_value >= PROFILE.AUDIO_THRESHOLD:
		_audio_due = ENTRY_DELAY
	if previous < PROFILE.VISION_THRESHOLD and stress_value >= PROFILE.VISION_THRESHOLD:
		_vision_due = ENTRY_DELAY
	if stress_value < PROFILE.AUDIO_THRESHOLD:
		_clear_audio()
	if stress_value < PROFILE.VISION_THRESHOLD:
		_clear_ghost()
	if not _can_perceive():
		clear_effects()
	else:
		_update_vignette()


func set_active(enabled: bool) -> void:
	if active != enabled:
		_audio_due = ENTRY_DELAY
		_vision_due = ENTRY_DELAY
		_event_gap = 0.0
	active = enabled
	if not _can_perceive():
		clear_effects()
	else:
		_update_vignette()


func clear_effects() -> void:
	_clear_audio()
	_clear_ghost()
	if is_instance_valid(vignette_layer):
		vignette_layer.hide()
	_audio_due = ENTRY_DELAY
	_vision_due = ENTRY_DELAY
	_event_gap = 0.0


func advance(delta: float) -> void:
	if not _can_perceive():
		clear_effects()
		return
	var elapsed := maxf(delta, 0.0)
	_update_vignette()
	_audio_remaining = maxf(0.0, _audio_remaining - elapsed)
	if _audio_remaining <= 0.0:
		_clear_audio()
	if is_instance_valid(ghost):
		_ghost_remaining = maxf(0.0, _ghost_remaining - elapsed)
		if _ghost_remaining <= 0.0 or not _ghost_has_clear_sight(ghost.global_position):
			_clear_ghost()
		else:
			var lived := GHOST_DURATION - _ghost_remaining
			var opacity := minf(lived / 0.20, _ghost_remaining / 0.55)
			_ghost_material.albedo_color.a = 0.62 * clampf(opacity, 0.0, 1.0)
	_event_gap = maxf(0.0, _event_gap - elapsed)
	if stress_value >= PROFILE.AUDIO_THRESHOLD:
		_audio_due -= elapsed
	if stress_value >= PROFILE.VISION_THRESHOLD:
		_vision_due -= elapsed
	if _event_gap > 0.0:
		return
	# Never catch up a backlog after a long frame with repeated sounds or
	# multiple apparitions. At most one event is produced per update.
	if stress_value >= PROFILE.AUDIO_THRESHOLD and _audio_due <= 0.0:
		trigger_event("whisper" if rng.randf() < 0.5 else "footsteps")
		_audio_due = PROFILE.audio_interval(stress_value)
		return
	if stress_value >= PROFILE.VISION_THRESHOLD and _vision_due <= 0.0:
		trigger_event("vision")
		_vision_due = PROFILE.vision_interval(stress_value)


func trigger_event(kind: String) -> bool:
	if not _can_perceive():
		clear_effects()
		return false
	if kind in ["whisper", "footsteps"]:
		if stress_value < PROFILE.AUDIO_THRESHOLD or _audio_remaining > 0.0:
			return false
		var stream := AUDIO.get_stream(kind)
		if stream == null:
			return false
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		audio_player.global_position = player.camera.global_position + player.head.global_basis.x * side * rng.randf_range(2.5, 4.0) + player.head.global_basis.z * rng.randf_range(0.5, 2.0)
		audio_player.stream = stream
		audio_player.play()
		_audio_remaining = stream.get_length()
		_audio_due = PROFILE.audio_interval(stress_value)
	elif kind == "vision":
		if stress_value < PROFILE.VISION_THRESHOLD or is_instance_valid(ghost):
			return false
		var placement := _find_ghost_placement()
		if not bool(placement.get("accepted", false)):
			return false
		_build_ghost(placement.position)
		_vision_due = PROFILE.vision_interval(stress_value)
	else:
		return false
	event_count += 1
	last_event = kind
	_event_gap = 0.75
	perception_triggered.emit(kind)
	return true


func _can_perceive() -> bool:
	return active and is_inside_tree() and not get_tree().paused and _has_input_capture() and is_instance_valid(player) and player.is_inside_tree() and not player.is_queued_for_deletion() and player.health > 0.0 and player.combat_state != DungeonPlayer.CombatState.DEAD and not player.camping and not player.safe_zone_mode and is_instance_valid(player.camera)


func _has_input_capture() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _update_vignette() -> void:
	if not is_instance_valid(vignette_layer):
		return
	var enabled := stress_value >= PROFILE.UNEASE_THRESHOLD and _can_perceive()
	vignette_layer.visible = enabled
	if enabled:
		var strength := lerpf(0.015, 0.16, clampf((stress_value - PROFILE.UNEASE_THRESHOLD) / (PROFILE.MAX_STRESS - PROFILE.UNEASE_THRESHOLD), 0.0, 1.0))
		(vignette_rect.material as ShaderMaterial).set_shader_parameter("intensity", strength)


func _find_ghost_placement() -> Dictionary:
	var forward := -player.head.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return {"accepted": false}
	forward = forward.normalized()
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := maxf(viewport_size.x / maxf(1.0, viewport_size.y), 0.5)
	var half_angle := atan(tan(deg_to_rad(player.camera.fov * 0.5)) * aspect)
	for _attempt in range(8):
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var angle := side * half_angle * rng.randf_range(0.76, 0.91)
		var direction := forward.rotated(Vector3.UP, angle)
		var at := player.global_position + direction * rng.randf_range(3.1, 4.8)
		var floor_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.8, at + Vector3.DOWN * 2.2, 2, [player.get_rid()])
		var hit := player.get_world_3d().direct_space_state.intersect_ray(floor_query)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
			continue
		var ground := hit.position as Vector3
		if absf(ground.y - (player.global_position.y - 0.9)) > 0.35 or not _ghost_has_clear_sight(ground):
			continue
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.6
		var space_query := PhysicsShapeQueryParameters3D.new()
		space_query.shape = shape
		space_query.transform = Transform3D(Basis.IDENTITY, ground + Vector3.UP * 0.84)
		space_query.collision_mask = WORLD_MASK
		space_query.exclude = [player.get_rid()]
		space_query.collide_with_areas = false
		if not player.get_world_3d().direct_space_state.intersect_shape(space_query, 8).is_empty():
			continue
		var chest := ground + Vector3.UP * 1.05
		if player.camera.is_position_behind(chest):
			continue
		var screen := player.camera.unproject_position(chest)
		if not Rect2(Vector2.ZERO, viewport_size).grow(-20.0).has_point(screen):
			continue
		return {"accepted": true, "position": ground}
	return {"accepted": false}


func _ghost_has_clear_sight(ground: Vector3) -> bool:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return false
	for height: float in [0.65, 1.45]:
		var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, ground + Vector3.UP * height, WORLD_MASK, [player.get_rid()])
		query.hit_from_inside = true
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false
	return true


func _build_ghost(at: Vector3) -> void:
	ghost = Node3D.new()
	ghost.name = "PeripheralAfterimage"
	ghost.set_meta("perception_only", true)
	add_child(ghost)
	if is_inside_tree():
		ghost.global_position = at
	else:
		ghost.position = at
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = Color(0.026, 0.022, 0.035, 0.0)
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	var body := CapsuleMesh.new()
	body.radius = 0.21
	body.height = 1.1
	body.radial_segments = 10
	body.rings = 4
	_add_ghost_mesh("ShroudedBody", body, Vector3(0.0, 0.75, 0.0), Vector3(1.1, 1.0, 0.8))
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.32
	head_mesh.radial_segments = 10
	head_mesh.rings = 5
	_add_ghost_mesh("HeadShape", head_mesh, Vector3(0.0, 1.43, 0.0), Vector3.ONE)
	for side in [-1, 1]:
		var limb := CapsuleMesh.new()
		limb.radius = 0.065
		limb.height = 0.72
		limb.radial_segments = 8
		limb.rings = 3
		_add_ghost_mesh("Arm%d" % side, limb, Vector3(side * 0.25, 0.76, 0.0), Vector3.ONE)
	_ghost_remaining = GHOST_DURATION


func _add_ghost_mesh(mesh_name: String, mesh: Mesh, at: Vector3, scale_value: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	instance.position = at
	instance.scale = scale_value
	instance.material_override = _ghost_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.add_child(instance)


func _clear_audio() -> void:
	_audio_remaining = 0.0
	if is_instance_valid(audio_player):
		audio_player.stop()
		audio_player.stream = null


func _clear_ghost() -> void:
	_ghost_remaining = 0.0
	if is_instance_valid(ghost):
		ghost.hide()
		ghost.queue_free()
	ghost = null
	_ghost_material = null
