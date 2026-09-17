extends Node3D
## Authored pools with rounded shores and a bounded GPU footstep ripple history.
const LAYOUT := preload("res://scripts/cave_layout.gd")
const WATER_SHADER := preload("res://assets/3d/abandoned_mine/mine_water.gdshader")
const MAX_RIPPLES := 24
const RIPPLE_LIFETIME := 4.2
const GRID_SPACING := 0.32
const FOOT_OFFSET := 0.89
var surfaces: Array[MeshInstance3D] = []
var pools: Array[Dictionary] = []
var player: CharacterBody3D
var total_ripples := 0
var last_event := ""
var last_pool := ""
var _geometry: Node3D
var _clock := 0.0
var _ripples := PackedVector4Array()
var _ring_cursor := 0
var _last_feet := Vector3.ZERO
var _has_contact_sample := false
var _previous_wet := false
var _previous_grounded := false
var _travel_since_step := 0.0
var _time_since_step := 0.0
var _step_side := 1.0


func build(geometry: Node3D) -> void:
	if not pools.is_empty():
		return
	_geometry = geometry
	_ripples.resize(MAX_RIPPLES)
	for index in MAX_RIPPLES:
		_ripples[index] = Vector4(0, 0, -100, 0)
	for source: Dictionary in LAYOUT.pools():
		var pool := source.duplicate(true)
		pool.shore = smooth_shore(source.polygon)
		pool.islands = []
		for island: Dictionary in LAYOUT.islands():
			if island.room_id == source.room_id:
				pool.islands.append(smooth_shore(island.polygon))
		var bounds := Rect2(pool.shore[0], Vector2.ZERO)
		for point: Vector2 in pool.shore:
			bounds = bounds.expand(point)
		pool.bounds = bounds.grow(0.4)
		pools.append(pool)
		var surface := MeshInstance3D.new()
		surface.name = "LivingWater_" + str(pool.id)
		surface.mesh = _build_surface(pool)
		surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = WATER_SHADER
		material.set_shader_parameter("ripple_events", _ripples)
		surface.material_override = material
		add_child(surface)
		surfaces.append(surface)
	_publish_shader_state()


static func smooth_shore(original: PackedVector2Array) -> PackedVector2Array:
	# Round the traced metre-long corners without moving the six authored pools.
	var shore := original.duplicate()
	for _iteration in 3:
		var rounded := PackedVector2Array()
		for index in shore.size():
			var first := shore[index]
			var second := shore[(index + 1) % shore.size()]
			rounded.append(first.lerp(second, 0.25))
			rounded.append(first.lerp(second, 0.75))
		shore = rounded
	return shore


func _build_surface(pool: Dictionary) -> ArrayMesh:
	var bounds: Rect2 = pool.bounds
	var columns := ceili(bounds.size.x / GRID_SPACING) + 1
	var rows := ceili(bounds.size.y / GRID_SPACING) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var shore_depth := PackedVector2Array()
	for z in rows:
		for x in columns:
			var point := bounds.position + Vector2(x * GRID_SPACING, z * GRID_SPACING)
			vertices.append(Vector3(point.x, float(pool.surface_y), point.y))
			normals.append(Vector3.UP)
			uv.append(point)
			var shore_distance := _shore_distance(pool, point)
			var bed: float = _geometry.floor_height(point)
			shore_depth.append(Vector2(shore_distance, maxf(0.0, float(pool.surface_y) - bed)))
	var indices := PackedInt32Array()
	for z in rows - 1:
		for x in columns - 1:
			var a := z * columns + x
			var b := a + 1
			var c := a + columns
			var d := c + 1
			if maxf(maxf(shore_depth[a].x, shore_depth[b].x), maxf(shore_depth[c].x, shore_depth[d].x)) < -0.18:
				continue
			# Godot's clockwise front faces must agree with the upward normals.
			# The two-sided shader distinguishes above-water and underside views.
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = shore_depth
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var nearest_squared := INF
	for index in polygon.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % polygon.size()])
		nearest_squared = minf(nearest_squared, point.distance_squared_to(closest))
	return sqrt(nearest_squared) * (1.0 if Geometry2D.is_point_in_polygon(point, polygon) else -1.0)


static func _shore_distance(pool: Dictionary, point: Vector2) -> float:
	var distance := _polygon_distance(point, pool.shore)
	for island: PackedVector2Array in pool.islands:
		distance = minf(distance, -_polygon_distance(point, island))
	return distance


func sample_surface(world_point: Vector3) -> Dictionary:
	var local := to_local(world_point)
	var point := Vector2(local.x, local.z)
	for pool: Dictionary in pools:
		if not (pool.bounds as Rect2).has_point(point):
			continue
		var shore_distance := _shore_distance(pool, point)
		if shore_distance <= 0.015:
			continue
		var bed: float = _geometry.floor_height(point)
		var depth := float(pool.surface_y) - bed
		if depth <= 0.012:
			continue
		return {"id": pool.id, "height": to_global(Vector3(point.x, float(pool.surface_y), point.y)).y, "depth": depth, "shore_distance": shore_distance}
	return {}


func bind_player(actor: CharacterBody3D) -> void:
	player = actor
	_has_contact_sample = false
	_previous_wet = false
	_previous_grounded = false
	_travel_since_step = 0.0


func _physics_process(delta: float) -> void:
	if is_instance_valid(player) and player.is_inside_tree():
		advance_contact(delta, player.global_position - Vector3.UP * FOOT_OFFSET, player.velocity, player.is_on_floor())
	else:
		advance_contact(delta, Vector3.ZERO, Vector3.ZERO, false, false)


func advance_contact(delta: float, feet: Vector3, velocity: Vector3, grounded: bool, actor_present := true) -> void:
	if get_tree() != null and get_tree().paused:
		return
	_clock += maxf(delta, 0.0)
	_time_since_step += maxf(delta, 0.0)
	var contact := sample_surface(feet) if actor_present else {}
	var wet := not contact.is_empty() and feet.y <= float(contact.height) + 0.055 and feet.y >= float(contact.height) - float(contact.depth) - 0.22
	var displacement := Vector2(feet.x - _last_feet.x, feet.z - _last_feet.z).length() if _has_contact_sample else 0.0
	var teleported := displacement > maxf(2.0, maxf(delta, 0.0) * 10.0)
	if wet:
		last_pool = str(contact.id)
		if not _previous_wet or (not _previous_grounded and grounded):
			_emit_ripple(feet, 1.0 if absf(velocity.y) < 1.0 else 1.45, "enter" if not _previous_wet else "land")
			_travel_since_step = 0.0
		elif not grounded and _previous_grounded and velocity.y > 0.5:
			_emit_ripple(feet, 0.72, "jump")
		elif grounded and not teleported:
			var speed := Vector2(velocity.x, velocity.z).length()
			_travel_since_step += displacement
			var stride := 0.84 if speed > 4.7 else 0.63
			if speed > 0.3 and _travel_since_step >= stride and _time_since_step >= 0.1:
				var side := Vector3(-velocity.z, 0, velocity.x).normalized() * (0.12 * _step_side)
				_emit_ripple(feet + side, 1.15 if speed > 4.7 else 0.72, "run" if speed > 4.7 else "walk")
				_step_side *= -1.0
				_travel_since_step = fmod(_travel_since_step, stride)
	else:
		_travel_since_step = 0.0
	_previous_wet = wet
	_previous_grounded = grounded
	_has_contact_sample = actor_present
	_last_feet = feet
	_publish_shader_state()


func _emit_ripple(point: Vector3, strength: float, event: String) -> void:
	_ripples[_ring_cursor] = Vector4(point.x, point.z, _clock, strength)
	_ring_cursor = (_ring_cursor + 1) % MAX_RIPPLES
	total_ripples += 1
	last_event = event
	_time_since_step = 0.0


func _publish_shader_state() -> void:
	for surface: MeshInstance3D in surfaces:
		var material := surface.material_override as ShaderMaterial
		material.set_shader_parameter("water_clock", _clock)
		material.set_shader_parameter("ripple_events", _ripples)


func get_state_snapshot() -> Dictionary:
	var active := 0
	for ripple: Vector4 in _ripples:
		if ripple.w > 0 and _clock - ripple.z < RIPPLE_LIFETIME:
			active += 1
	return {"pool_count": pools.size(), "ripple_count": active, "total_ripples": total_ripples, "clock": _clock, "last_event": last_event, "last_pool": last_pool, "capacity": MAX_RIPPLES}


func get_ripple_events() -> PackedVector4Array:
	return _ripples.duplicate()
