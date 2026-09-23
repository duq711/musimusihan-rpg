extends Node
## Bounded spring motion for a tunic hem. Godot SoftBody3D separated the
## garment's UV seam vertices, so the source fabric visibly tore apart.

const MAX_SPEED := 7.0
const MAX_ACCELERATION := 26.0
const MAX_TURN_RATE := 5.0
const MAX_OFFSET := 0.07
const SPRING_STIFFNESS := 115.0
const SPRING_DAMPING := 18.0
const STRIDE_LENGTH := 1.25
const PINNED_BAND := 0.035

var _body: Node3D
var _hem: MeshInstance3D
var _wearer: CharacterBody3D
var _rest_arrays: Array
var _rest_vertices := PackedVector3Array()
var _surface: ArrayMesh
var _material: Material
var _top := 0.0
var _height := 1.0
var _configured := false
var _previous_position := Vector3.ZERO
var _previous_local_velocity := Vector3.ZERO
var _previous_yaw := 0.0
var _travelled_distance := 0.0
var _offset := Vector3.ZERO
var _spring_velocity := Vector3.ZERO
var _target := Vector3.ZERO
var _last_planar_speed := 0.0


func configure(body: Node3D, hem: MeshInstance3D) -> void:
	assert(body != null and hem != null and hem.mesh != null)
	_body = body
	_hem = hem
	if is_inside_tree():
		_prepare()


func _ready() -> void:
	_prepare()


func _prepare() -> void:
	set_physics_process(false)
	if _body == null or _hem == null or not _body.is_inside_tree() or not _hem.is_inside_tree():
		return
	if _hem.mesh.get_surface_count() != 1:
		push_error("Each player cloth hem needs one original garment surface.")
		return
	_rest_arrays = _hem.mesh.surface_get_arrays(0)
	_rest_vertices = (_rest_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	if _rest_vertices.size() < 12:
		push_error("Player cloth hem has too few vertices.")
		return
	_material = _hem.get_active_material(0)
	_top = -INF
	var bottom := INF
	for vertex in _rest_vertices:
		_top = maxf(_top, vertex.y)
		bottom = minf(bottom, vertex.y)
	_height = maxf(_top - bottom, 0.001)
	_surface = ArrayMesh.new()
	_hem.mesh = _surface # A separate deformation buffer per player or portrait.
	_update_surface()
	_wearer = _find_wearer(_body)
	_previous_position = _body.global_position
	_previous_yaw = _body.global_basis.get_euler().y
	_previous_local_velocity = _sample_local_velocity(1.0 / 60.0)
	_configured = true
	# A portrait is static and need not run a physics update loop.
	set_physics_process(_wearer != null)


func _physics_process(delta: float) -> void:
	if not _configured or delta <= 0.0 or not is_instance_valid(_body) or not is_instance_valid(_hem):
		return
	var local_velocity := _sample_local_velocity(delta)
	var planar := Vector3(local_velocity.x, 0.0, local_velocity.z).limit_length(MAX_SPEED)
	var previous_planar := Vector3(_previous_local_velocity.x, 0.0, _previous_local_velocity.z)
	var acceleration := ((planar - previous_planar) / delta).limit_length(MAX_ACCELERATION)
	var yaw := _body.global_basis.get_euler().y
	var turn_rate := clampf(angle_difference(_previous_yaw, yaw) / delta, -MAX_TURN_RATE, MAX_TURN_RATE)
	_previous_yaw = yaw
	_previous_position = _body.global_position
	_previous_local_velocity = local_velocity
	_last_planar_speed = planar.length()
	_travelled_distance += _last_planar_speed * delta
	# The spring responds to starts, stops, turns and a small travelling gait.
	var stride := _travelled_distance * TAU / STRIDE_LENGTH
	var gait := Vector3(sin(stride) * 0.007, 0.0, sin(stride * 1.5) * 0.005) * clampf(_last_planar_speed / 4.2, 0.0, 1.0)
	_target = (-acceleration * 0.0022 - planar * 0.005 + Vector3(-turn_rate * 0.008, 0.0, 0.0) + gait).limit_length(MAX_OFFSET)
	_spring_velocity += (_target - _offset) * SPRING_STIFFNESS * delta
	_spring_velocity *= exp(-SPRING_DAMPING * delta)
	_offset += _spring_velocity * delta
	_offset = _offset.limit_length(MAX_OFFSET)
	_update_surface()


func _update_surface() -> void:
	if _surface == null:
		return
	var arrays := _rest_arrays.duplicate(true)
	var vertices := _rest_vertices.duplicate()
	var gait_strength := clampf(_last_planar_speed / 4.2, 0.0, 1.0) * 0.004
	var phase := _travelled_distance * TAU / STRIDE_LENGTH
	for index in vertices.size():
		var rest := _rest_vertices[index]
		var weight := pow(clampf((_top - rest.y - PINNED_BAND) / maxf(_height - PINNED_BAND, 0.001), 0.0, 1.0), 1.35)
		var ripple := sin(phase - weight * 1.4 + rest.x * 7.0) * gait_strength * weight * weight
		vertices[index] = rest + _offset * weight + Vector3(0.0, _offset.length() * 0.08 * weight, ripple)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	_surface.clear_surfaces()
	_surface.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_surface.surface_set_material(0, _material)


func get_motion_state() -> Dictionary:
	return {
		"configured": _configured,
		"planar_speed": _last_planar_speed,
		"offset": _offset,
		"target": _target,
		"spring_velocity": _spring_velocity,
	}


func get_rest_vertices() -> PackedVector3Array:
	return _rest_vertices.duplicate()


func _sample_local_velocity(delta: float) -> Vector3:
	var world_velocity := (_body.global_position - _previous_position) / maxf(delta, 0.001)
	if is_instance_valid(_wearer):
		world_velocity = _wearer.velocity
	return _body.global_basis.orthonormalized().inverse() * world_velocity


func _find_wearer(start: Node) -> CharacterBody3D:
	var node := start
	while node != null:
		if node is CharacterBody3D:
			return node as CharacterBody3D
		node = node.get_parent()
	return null
