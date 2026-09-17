extends Area3D
class_name MagicProjectile

signal hit_target(spell_id: String, target: Node, damage: float)

const WORLD_LAYER := 2
const ENEMY_LAYER := 4

var spell_id := ""
var element := ""
var damage := 0.0
var speed := 12.0
var radius := 0.14
var knockback := 0.3
var direction := Vector3.FORWARD
var caster: Node
var lifetime := 5.0
var _resolved := false
var _spell_color := Color.WHITE
var _sweep_cast: ShapeCast3D
var _visual_root: Node3D


func configure(id: String, definition: Dictionary, caster_ref: Node, travel_direction: Vector3) -> MagicProjectile:
	spell_id = id
	element = str(definition.get("element", "arcane"))
	damage = maxf(0.0, float(definition.get("damage", 0.0)))
	speed = maxf(0.1, float(definition.get("speed", 12.0)))
	radius = maxf(0.05, float(definition.get("radius", 0.14)))
	knockback = clampf(float(definition.get("knockback", 0.3)), 0.0, 1.0)
	_spell_color = definition.get("color", Color.WHITE) as Color
	caster = caster_ref
	direction = travel_direction.normalized() if travel_direction.length_squared() > 0.0001 else Vector3.FORWARD
	name = "%sProjectile" % spell_id.to_pascal_case()
	_sync_caster_exception()
	_orient_visual_to_direction()
	return self


func _ready() -> void:
	add_to_group("magic_projectile")
	collision_layer = 0
	collision_mask = WORLD_LAYER | ENEMY_LAYER
	monitoring = false
	monitorable = false
	_build_collision()
	_build_visual()


func _physics_process(delta: float) -> void:
	if _resolved:
		return
	lifetime -= delta
	if lifetime <= 0.0:
		_resolved = true
		queue_free()
		return
	var from := global_position
	var motion := direction * speed * delta
	var to := from + motion
	_sweep_cast.target_position = _sweep_cast.to_local(to)
	_sweep_cast.force_shapecast_update()
	if not _sweep_cast.is_colliding():
		global_position = to
		_spin_visual(delta)
		return

	# ShapeCast3D sweeps the projectile's real SphereShape3D, preventing fast or
	# off-centre shots from tunnelling through thin walls and enemy silhouettes.
	var safe_fraction := clampf(_sweep_cast.get_closest_collision_safe_fraction(), 0.0, 1.0)
	global_position = from + motion * safe_fraction
	var target := _first_sweep_collider(from, motion)
	if target != null and target.has_method("receive_hit"):
		resolve_hit(target)
	else:
		_resolved = true
		queue_free()


func resolve_hit(target: Node) -> bool:
	if _resolved or target == null or not is_instance_valid(target) or not target.has_method("receive_hit"):
		return false
	_resolved = true
	var attacker_position := global_position - direction
	if is_instance_valid(caster) and caster is Node3D:
		attacker_position = (caster as Node3D).global_position
	target.call("receive_hit", damage, attacker_position, knockback, false)
	hit_target.emit(spell_id, target, damage)
	queue_free()
	return true


func _build_collision() -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = "ProjectileCollision"
	var shape := SphereShape3D.new()
	shape.radius = radius
	shape_node.shape = shape
	add_child(shape_node)

	_sweep_cast = ShapeCast3D.new()
	_sweep_cast.name = "ProjectileSweep"
	_sweep_cast.shape = shape
	_sweep_cast.enabled = false
	_sweep_cast.exclude_parent = true
	_sweep_cast.collision_mask = WORLD_LAYER | ENEMY_LAYER
	_sweep_cast.collide_with_areas = false
	_sweep_cast.collide_with_bodies = true
	_sweep_cast.max_results = 16
	add_child(_sweep_cast)
	_sync_caster_exception()


func _build_visual() -> void:
	# Collision keeps the authored gameplay radius; the mesh is deliberately
	# slimmer so a close projectile does not cover the crosshair or its target.
	var visual_radius := radius * 0.76
	_visual_root = Node3D.new()
	_visual_root.name = "DirectionVisuals"
	add_child(_visual_root)

	preload("res://scripts/dark_fantasy_effect_visual.gd").populate_projectile(_visual_root, element, visual_radius)

	_orient_visual_to_direction()


func _first_sweep_collider(from: Vector3, motion: Vector3) -> Node:
	var best_target: Node
	var best_progress := INF
	var best_is_blocker := false
	var motion_length_squared := motion.length_squared()
	for index in _sweep_cast.get_collision_count():
		var candidate_object := _sweep_cast.get_collider(index)
		if not candidate_object is Node:
			continue
		var candidate := candidate_object as Node
		if not is_instance_valid(candidate) or candidate == caster:
			continue
		var progress := 0.0
		if motion_length_squared > 0.000001:
			var contact_offset := _sweep_cast.get_collision_point(index) - from
			progress = clampf(contact_offset.dot(motion) / motion_length_squared, 0.0, 1.0)
		var is_blocker := not candidate.has_method("receive_hit")
		if progress < best_progress - 0.0001 or (
			absf(progress - best_progress) <= 0.0001 and is_blocker and not best_is_blocker
		):
			best_target = candidate
			best_progress = progress
			best_is_blocker = is_blocker
	return best_target


func _sync_caster_exception() -> void:
	if _sweep_cast == null or not is_instance_valid(_sweep_cast):
		return
	_sweep_cast.clear_exceptions()
	if caster is CollisionObject3D and is_instance_valid(caster):
		_sweep_cast.add_exception(caster as CollisionObject3D)


func _orient_visual_to_direction() -> void:
	if _visual_root == null or not is_instance_valid(_visual_root):
		return
	var world_basis := global_basis if is_inside_tree() else basis
	var local_direction := (world_basis.inverse() * direction).normalized()
	var local_up := Vector3.UP
	if absf(local_direction.dot(local_up)) > 0.98:
		local_up = Vector3.RIGHT
	_visual_root.basis = Basis.looking_at(local_direction, local_up)


func _spin_visual(delta: float) -> void:
	if _visual_root != null and is_instance_valid(_visual_root):
		_visual_root.rotate_object_local(Vector3.FORWARD, delta * (8.0 if element == "ice" else 3.5))


func _projectile_material(color_value: Color, emissive: bool, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = 0.25 if emissive else 0.96
	material.metallic = 0.0
	if color_value.a < 0.99:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if emissive:
		material.emission_enabled = true
		material.emission = Color(color_value.r, color_value.g, color_value.b)
		material.emission_energy_multiplier = energy
	return material
