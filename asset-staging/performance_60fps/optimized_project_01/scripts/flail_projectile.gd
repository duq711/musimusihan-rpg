extends Node3D
class_name FlailProjectile

signal hit_target(target: Node, damage: float, headshot: bool)
signal returned()

const PROFILE := preload("res://scripts/flail_profile.gd")
const VISUALS := preload("res://scripts/flail_visuals.gd")
const WORLD_LAYER := 2
const ENEMY_LAYER := 4
const MAX_LIFETIME := 8.0
const CATCH_RADIUS := 0.16

var phase := "outbound"
var charge := 0.0
var damage := 28.0
var speed := 14.0
var max_distance := 6.0
var travelled := 0.0
var lifetime := MAX_LIFETIME
var caster: Node3D
var direction := Vector3.FORWARD

var _finished := false
var _hit_resolved := false
var _caster_origin := Vector3.ZERO
var _sweep_cast: ShapeCast3D
var _head: Node3D
var _chain: Node3D
var _caster_exclusion_rids: Array[RID] = []


func configure(caster_ref: Node3D, travel_direction: Vector3, draw_charge: float) -> FlailProjectile:
	caster = caster_ref
	charge = clampf(draw_charge, 0.0, 1.0)
	damage = PROFILE.throw_damage(charge)
	speed = PROFILE.throw_speed(charge)
	max_distance = PROFILE.throw_range(charge)
	direction = travel_direction.normalized() if travel_direction.length_squared() > 0.000001 else Vector3.FORWARD
	phase = "outbound"
	travelled = 0.0
	lifetime = MAX_LIFETIME
	_finished = false
	_hit_resolved = false
	if is_instance_valid(caster):
		_caster_origin = caster.global_position if caster.is_inside_tree() else caster.position
	_sync_caster_exclusions()
	return self


func _ready() -> void:
	name = "FlailProjectile"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("flail_projectile")
	_sweep_cast = ShapeCast3D.new()
	_sweep_cast.name = "HeadSweep"
	var shape := SphereShape3D.new()
	shape.radius = PROFILE.HEAD_RADIUS
	_sweep_cast.shape = shape
	_sweep_cast.enabled = false
	_sweep_cast.collision_mask = WORLD_LAYER | ENEMY_LAYER
	_sweep_cast.collide_with_areas = false
	_sweep_cast.collide_with_bodies = true
	_sweep_cast.max_results = 32
	add_child(_sweep_cast)
	_sync_caster_exclusions()
	_head = VISUALS.create_head()
	add_child(_head)
	_chain = VISUALS.create_chain()
	add_child(_chain)
	_refresh_chain()


func _physics_process(delta: float) -> void:
	if _finished or not is_inside_tree() or get_tree().paused:
		return
	if not is_instance_valid(caster) or not caster.is_inside_tree() or caster.is_queued_for_deletion():
		abort()
		return
	var elapsed := maxf(delta, 0.0)
	lifetime -= elapsed
	if lifetime <= 0.0:
		abort()
		return
	if phase == "outbound":
		var distance := minf(speed * elapsed, maxf(0.0, max_distance - travelled))
		var from := global_position
		var to := from + direction * distance
		if distance > 0.0 and _sweep(from, to):
			if _finished:
				return
			travelled += from.distance_to(global_position)
		else:
			global_position = to
			travelled += distance
			if travelled >= max_distance - 0.000001:
				phase = "returning"
	else:
		var anchor := _anchor_world()
		var remaining := global_position.distance_to(anchor)
		if remaining <= maxf(CATCH_RADIUS, PROFILE.RETURN_SPEED * elapsed):
			global_position = anchor
			_refresh_chain()
			_finished = true
			returned.emit()
			queue_free()
			return
		global_position = global_position.move_toward(anchor, PROFILE.RETURN_SPEED * elapsed)
	if is_instance_valid(_head):
		_head.rotate_object_local(Vector3.RIGHT, elapsed * 8.0)
	_refresh_chain()


func check_spawn_path(from: Vector3) -> bool:
	if _finished or phase != "outbound" or not is_inside_tree() or get_tree().paused:
		return false
	if not is_instance_valid(caster) or not caster.is_inside_tree():
		abort()
		return false
	var hit := _sweep(from, global_position)
	_refresh_chain()
	return hit


func abort() -> void:
	if _finished:
		return
	_finished = true
	visible = false
	set_physics_process(false)
	queue_free()


func _sweep(from: Vector3, to: Vector3) -> bool:
	if _sweep_cast == null or _hit_resolved or _finished:
		return false
	# Motion casts can miss a sphere already wholly enclosed by a wall. Probe
	# the real head volume at the start as well, especially the camera spawn.
	var overlap_query := PhysicsShapeQueryParameters3D.new()
	overlap_query.shape = _sweep_cast.shape
	overlap_query.transform = Transform3D(Basis.IDENTITY, from)
	overlap_query.collision_mask = WORLD_LAYER | ENEMY_LAYER
	overlap_query.collide_with_areas = false
	overlap_query.collide_with_bodies = true
	overlap_query.exclude = _caster_exclusion_rids
	var overlaps := get_world_3d().direct_space_state.intersect_shape(overlap_query, 32)
	if not overlaps.is_empty():
		var overlap_target: Node
		for hit in overlaps:
			var candidate := hit.get("collider") as Node
			if not is_instance_valid(candidate):
				continue
			overlap_target = candidate
			if not candidate.has_method("receive_hit"):
				break
		global_position = from
		_resolve_impact(overlap_target)
		return true
	_sweep_cast.global_position = from
	_sweep_cast.target_position = _sweep_cast.to_local(to)
	_sweep_cast.force_shapecast_update()
	if not _sweep_cast.is_colliding():
		_sweep_cast.position = Vector3.ZERO
		return false
	var motion := to - from
	var fraction := clampf(_sweep_cast.get_closest_collision_safe_fraction(), 0.0, 1.0)
	var target := _first_collider(from, motion)
	global_position = from + motion * fraction
	_sweep_cast.position = Vector3.ZERO
	_resolve_impact(target)
	return true


func _resolve_impact(target: Node) -> void:
	if _finished or _hit_resolved:
		return
	# Resolve the phase before calling gameplay code or signals. A callback can
	# process this object again, kill its target, or switch the scene safely.
	phase = "returning"
	_hit_resolved = true
	if is_instance_valid(target) and target.has_method("receive_hit"):
		target.call("receive_hit", damage, _caster_origin, charge, false)
		if not _finished and is_instance_valid(target):
			hit_target.emit(target, damage, false)


func _first_collider(from: Vector3, motion: Vector3) -> Node:
	var best: Node
	var best_progress := INF
	var best_is_wall := false
	for index in range(_sweep_cast.get_collision_count()):
		var object := _sweep_cast.get_collider(index)
		if not object is Node or not is_instance_valid(object):
			continue
		var candidate := object as Node
		if candidate == caster or (is_instance_valid(caster) and caster.is_ancestor_of(candidate)):
			continue
		var progress := 0.0
		if motion.length_squared() > 0.000001:
			progress = clampf((_sweep_cast.get_collision_point(index) - from).dot(motion) / motion.length_squared(), 0.0, 1.0)
		var is_wall := not candidate.has_method("receive_hit")
		if progress < best_progress - 0.0001 or (absf(progress - best_progress) <= 0.0001 and is_wall and not best_is_wall):
			best = candidate
			best_progress = progress
			best_is_wall = is_wall
	return best


func _sync_caster_exclusions() -> void:
	if not is_instance_valid(_sweep_cast):
		return
	_sweep_cast.clear_exceptions()
	_caster_exclusion_rids.clear()
	if is_instance_valid(caster):
		_exclude_caster_tree(caster)


func _exclude_caster_tree(node: Node) -> void:
	if node is CollisionObject3D:
		_sweep_cast.add_exception(node as CollisionObject3D)
		_caster_exclusion_rids.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_exclude_caster_tree(child)


func _anchor_world() -> Vector3:
	if not is_instance_valid(caster):
		return global_position
	if caster.has_method("get_flail_chain_anchor"):
		var anchor: Variant = caster.call("get_flail_chain_anchor")
		if anchor is Vector3 and (anchor as Vector3).is_finite():
			return anchor as Vector3
	return caster.global_position


func _refresh_chain() -> void:
	if is_instance_valid(_chain) and is_inside_tree() and is_instance_valid(caster):
		VISUALS.update_chain(_chain, _chain.to_local(_anchor_world()), _chain.to_local(global_position), 0.025)
