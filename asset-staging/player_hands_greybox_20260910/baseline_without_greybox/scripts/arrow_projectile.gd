extends Node3D
class_name ArrowProjectile

signal hit_target(target: Node, damage: float, headshot: bool)

const WORLD_LAYER := 2
const ENEMY_LAYER := 4
const HEADSHOT_HEIGHT := 0.5
const HEADSHOT_MULTIPLIER := 1.5
const MAX_FLIGHT_TIME := 8.0
const STICK_TIME := 4.0
const MAX_FLIGHT_STEP := 1.0 / 60.0

var damage := BowShotProfile.MIN_DAMAGE
var speed := 0.0
var gravity := BowShotProfile.SLACK_GRAVITY
var velocity := Vector3.DOWN * BowShotProfile.SLACK_DROP_SPEED
var charge := 0.0
var impacted := false
var lifetime := MAX_FLIGHT_TIME
var caster: Node

var _caster_origin := Vector3.ZERO
var _collision_exclusions: Array[RID] = []
var _visual: Node3D
var _stuck_target: WeakRef
var _stuck_transform := Transform3D.IDENTITY


func configure(caster_ref: Node, travel_direction: Vector3, draw_ratio: float) -> ArrowProjectile:
	caster = caster_ref
	charge = clampf(draw_ratio, 0.0, 1.0)
	damage = BowShotProfile.damage_for_draw(charge)
	speed = BowShotProfile.speed_for_draw(charge)
	gravity = BowShotProfile.gravity_for_draw(charge)
	var direction := travel_direction.normalized() if travel_direction.length_squared() > 0.0001 else Vector3.FORWARD
	# Untensioned arrows fall in world-down, even when aiming at the ceiling.
	# They retain real swept collision, sticking and ammunition consumption.
	velocity = Vector3.DOWN * BowShotProfile.SLACK_DROP_SPEED if BowShotProfile.is_slack_draw(charge) else direction * speed
	_collision_exclusions.clear()
	if is_instance_valid(caster):
		_collect_caster_colliders(caster)
		if caster is Node3D:
			_caster_origin = (caster as Node3D).global_position if caster.is_inside_tree() else (caster as Node3D).position
	_orient_to_velocity()
	return self


func _ready() -> void:
	name = "ArrowProjectile"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("arrow_projectile")
	_visual = ArcheryVisuals.create_arrow()
	add_child(_visual)
	_orient_to_velocity()


func _physics_process(delta: float) -> void:
	var active_time := minf(maxf(delta, 0.0), maxf(lifetime, 0.0))
	lifetime -= maxf(delta, 0.0)
	if impacted:
		_update_stuck_transform()
	else:
		# Each step sweeps the arrow point through the entire ballistic segment.
		# Substeps preserve the gravity arc during frame stalls, while ray queries
		# prevent even very thin walls from being skipped at maximum draw speed.
		while active_time > 0.000001 and not impacted:
			var step := minf(active_time, MAX_FLIGHT_STEP)
			var acceleration := Vector3.DOWN * gravity
			var next_position := global_position + velocity * step + acceleration * (0.5 * step * step)
			if not _sweep(global_position, next_position):
				global_position = next_position
				velocity += acceleration * step
				_orient_to_velocity()
			active_time -= step
	if lifetime <= 0.0:
		queue_free()


func check_spawn_path(from: Vector3) -> bool:
	# Sweep from the camera to the muzzle so spawning past a nearby wall cannot
	# bypass it. hit_from_inside also stops a shot when the camera is in a wall.
	if impacted:
		return true
	if not is_inside_tree():
		return false
	var to := global_position
	if from.distance_squared_to(to) < 0.000001:
		to = from + velocity.normalized() * 0.001
	return _sweep(from, to)


func _sweep(from: Vector3, to: Vector3) -> bool:
	if not is_inside_tree() or from.distance_squared_to(to) < 0.00000001:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER | ENEMY_LAYER, _collision_exclusions)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var target := hit.get("collider") as Node
	global_position = hit.get("position", from) as Vector3
	_resolve_impact(target)
	return true


func _resolve_impact(target: Node) -> void:
	if impacted:
		return
	impacted = true
	lifetime = STICK_TIME
	_orient_to_velocity()
	velocity = Vector3.ZERO
	if not is_instance_valid(target) or target == caster:
		return
	if target.has_method("receive_hit"):
		var headshot := target is Node3D and global_position.y >= (target as Node3D).global_position.y + HEADSHOT_HEIGHT
		var applied_damage := damage * (HEADSHOT_MULTIPLIER if headshot else 1.0)
		# Mark resolved before calling gameplay code or signals: listeners may
		# trigger another physics update, despawn the victim, or end the scene.
		target.call("receive_hit", applied_damage, _caster_origin, charge, headshot)
		hit_target.emit(target, applied_damage, headshot)
	if is_instance_valid(target) and target is Node3D and not target.is_queued_for_deletion():
		_stuck_target = weakref(target)
		_stuck_transform = (target as Node3D).global_transform.affine_inverse() * global_transform


func _update_stuck_transform() -> void:
	if _stuck_target == null:
		return
	var target := _stuck_target.get_ref() as Node3D
	if not is_instance_valid(target) or target.is_queued_for_deletion() or not target.is_inside_tree():
		_stuck_target = null
		queue_free()
		return
	global_transform = target.global_transform * _stuck_transform


func _collect_caster_colliders(node: Node) -> void:
	if node is CollisionObject3D:
		_collision_exclusions.append((node as CollisionObject3D).get_rid())
	for child in node.get_children():
		_collect_caster_colliders(child)


func _orient_to_velocity() -> void:
	if velocity.length_squared() < 0.000001:
		return
	var direction := velocity.normalized()
	var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var world_orientation := Basis.looking_at(direction, up)
	if is_inside_tree():
		global_basis = world_orientation
	else:
		basis = world_orientation
