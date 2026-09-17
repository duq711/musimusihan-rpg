extends SceneTree

const SHOT_PROFILE := preload("res://scripts/bow_shot_profile.gd")

var failures: Array[String] = []


class ArrowTarget:
	extends StaticBody3D

	var hit_count := 0
	var last_damage := 0.0
	var last_charge := 0.0
	var last_headshot := false
	var last_attacker := Vector3.ZERO


	func receive_hit(amount: float, attacker: Vector3, draw_charge: float, headshot: bool) -> void:
		hit_count += 1
		last_damage = amount
		last_charge = draw_charge
		last_headshot = headshot
		last_attacker = attacker


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_visual_contract()
	_test_charge_contract()
	await _test_slack_drop_floor_and_powered_flight()
	await _test_wall_and_first_hit()
	await _test_headshots_and_sticking()
	await _test_spawn_blocking_and_caster_exclusion()
	await _test_gravity_and_expiry()
	await _test_pause_isolation()
	if failures.is_empty():
		print("ARROW PROJECTILE TESTS PASSED")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_visual_contract() -> void:
	var bow := ArcheryVisuals.create_bow()
	var arrow := bow.get_node("NockedArrow") as Node3D
	_check(arrow.get_node_or_null("WoodenShaft") != null and arrow.get_node_or_null("IronArrowhead") != null, "nocked arrow must contain a wooden shaft and metal point")
	_check(arrow.get_node_or_null("Fletching2") != null, "arrow must have three recognizable fletchings")
	var rest_position := arrow.position
	ArcheryVisuals.set_bow_draw(bow, 1.0)
	_check(is_equal_approx(arrow.position.z - rest_position.z, 0.28), "full bow draw must pull its actual nocked arrow back by 28 cm")
	var string := bow.get_node("String_1") as Node3D
	var string_bottom := string.position - string.basis.y * 0.5
	_check(string_bottom.distance_to(arrow.position + Vector3(0, 0, 0.80)) < 0.001, "bowstring center and arrow nock must stay connected at full draw")
	arrow.visible = false
	ArcheryVisuals.set_bow_draw(bow, 0.0)
	_check(not arrow.visible, "draw animation must preserve the caller-controlled nocked arrow visibility")
	bow.free()


func _test_charge_contract() -> void:
	var low := ArrowProjectile.new().configure(null, Vector3.ZERO, -1.0)
	_check(is_equal_approx(low.charge, 0.0) and is_equal_approx(low.damage, 18.0) and is_zero_approx(low.speed), "minimum charge must retain 18 damage but have no forward launch speed")
	_check(low.velocity.is_equal_approx(Vector3.DOWN) and is_equal_approx(low.gravity, 9.8) and low.basis.is_finite(), "slack release must drop at one metre per second with earth-like gravity and a finite orientation")
	low.free()
	var high := ArrowProjectile.new().configure(null, Vector3.UP, 2.0)
	_check(is_equal_approx(high.charge, 1.0) and is_equal_approx(high.damage, 46.0) and is_equal_approx(high.speed, 42.0), "maximum charge must clamp to 46 damage and 42 m/s")
	_check(high.basis.is_finite(), "vertical arrows must retain a finite visual orientation")
	_check(is_equal_approx(high.gravity, 5.0), "full draw must retain the original authored ballistic gravity")
	high.free()
	var zero_aim := ArrowProjectile.new().configure(null, Vector3.ZERO, 1.0)
	_check(zero_aim.velocity.is_equal_approx(Vector3.FORWARD * 42.0), "powered zero aim input must default to forward without invalid transforms")
	zero_aim.free()
	var previous_speed := 0.0
	var previous_gravity := INF
	for ratio: float in [-1.0, 0.0, 0.05, 0.1, 0.1001, 0.25, 0.5, 0.75, 1.0, 2.0]:
		var tension := clampf((ratio - 0.1) / 0.9, 0.0, 1.0)
		var speed: float = SHOT_PROFILE.speed_for_draw(ratio)
		var gravity: float = SHOT_PROFILE.gravity_for_draw(ratio)
		_check(is_equal_approx(speed, 42.0 * tension) and speed >= previous_speed, "effective bow tension must smoothly increase forward launch speed after the first tenth of draw")
		_check(is_equal_approx(gravity, lerpf(9.8, 5.0, tension)) and gravity <= previous_gravity, "weak powered shots must drop more strongly than a full draw")
		_check(SHOT_PROFILE.is_slack_draw(ratio) == (ratio <= 0.1), "the first tenth of draw must be classified as slack, including the boundary")
		previous_speed = speed
		previous_gravity = gravity


func _test_slack_drop_floor_and_powered_flight() -> void:
	for aim: Vector3 in [Vector3.FORWARD, Vector3.UP, Vector3.DOWN, Vector3.RIGHT]:
		for ratio: float in [0.0, 0.05, 0.1]:
			var world := _world()
			var floor_body := _body(Vector3(0.0, -0.05, 0.0), Vector3(8.0, 0.1, 8.0), 2)
			world.add_child(floor_body)
			var rear := _target(Vector3(0.0, 1.2, -2.0))
			world.add_child(rear)
			var arrow := ArrowProjectile.new().configure(null, aim, ratio)
			world.add_child(arrow)
			arrow.set_physics_process(false)
			arrow.global_position = Vector3(0.0, 1.2, 0.0)
			await physics_frame
			await process_frame
			arrow._physics_process(0.2)
			_check(absf(arrow.global_position.y - 0.804) < 0.002 and absf(arrow.velocity.y + 2.96) < 0.002, "slack arrow must visibly fall immediately along the physical downward ballistic arc")
			_check(absf(arrow.global_position.x) < 0.00001 and absf(arrow.global_position.z) < 0.00001, "slack arrow must not gain forward or sideways motion even when aimed upward or sideways")
			arrow._physics_process(0.8)
			_check(arrow.impacted and absf(arrow.global_position.y) < 0.002 and arrow.velocity.is_zero_approx(), "slack drop must hit and stick to the real collision floor during a large frame")
			_check(rear.hit_count == 0, "an immediate slack release must not reach a distant aimed enemy")
			world.free()
	var world := _world()
	var previous_distance := 0.0
	for ratio: float in [0.1001, 0.25, 0.5, 0.75, 1.0]:
		var arrow := ArrowProjectile.new().configure(null, Vector3.FORWARD, ratio)
		world.add_child(arrow)
		arrow.set_physics_process(false)
		arrow.global_position = Vector3(0.0, 10.0, 0.0)
		var start := arrow.global_position
		arrow._physics_process(0.2)
		var distance := -arrow.global_position.z
		_check(distance > previous_distance and absf(distance - SHOT_PROFILE.speed_for_draw(ratio) * 0.2) < 0.001, "real powered flight must travel farther as the bow is drawn further")
		_check(absf(arrow.global_position.y - (start.y - SHOT_PROFILE.gravity_for_draw(ratio) * 0.02)) < 0.001, "powered flight must use its charge-scaled gravity")
		previous_distance = distance
		arrow.free()
	world.free()


func _test_wall_and_first_hit() -> void:
	var world := _world()
	var wall := _body(Vector3(0, 0, -2), Vector3(3, 3, 0.01), 2)
	world.add_child(wall)
	var rear := _target(Vector3(0, 0, -3))
	world.add_child(rear)
	var arrow := _arrow(world, Vector3.ZERO)
	var emitted: Array = []
	arrow.hit_target.connect(func(_target_node: Node, amount: float, _headshot: bool) -> void: emitted.append(amount))
	await physics_frame
	await process_frame
	arrow._physics_process(0.25)
	_check(arrow.impacted and arrow.global_position.z >= -2.006, "42 m/s arrows must stop at a 1 cm wall even during a 250 ms frame")
	_check(rear.hit_count == 0 and emitted.is_empty(), "walls must block enemies behind them without emitting a damage signal")
	arrow._physics_process(0.25)
	_check(rear.hit_count == 0, "a lodged arrow must never resume damage behind a wall")
	world.free()

	world = _world()
	var front := _target(Vector3(0, 0, -2))
	rear = _target(Vector3(0, 0, -3))
	world.add_child(front)
	world.add_child(rear)
	arrow = _arrow(world, Vector3.ZERO)
	emitted.clear()
	arrow.hit_target.connect(func(_target_node: Node, amount: float, _headshot: bool) -> void: emitted.append(amount))
	await physics_frame
	await process_frame
	arrow._physics_process(0.25)
	arrow._physics_process(0.5)
	_check(front.hit_count == 1 and rear.hit_count == 0 and emitted.size() == 1, "one arrow must damage and signal exactly once, only on the nearest target")
	_check(is_equal_approx(front.last_damage, 46.0) and not front.last_headshot, "torso hits must apply unmultiplied charged damage")
	world.free()


func _test_headshots_and_sticking() -> void:
	var world := _world()
	var target := _target(Vector3(0, 0, -2))
	world.add_child(target)
	var caster := Node3D.new()
	caster.position = Vector3(0.2, 0, 1)
	world.add_child(caster)
	var arrow := _arrow(world, Vector3(0, 0.7, 0), caster)
	await physics_frame
	await process_frame
	arrow._physics_process(0.1)
	_check(target.hit_count == 1 and target.last_headshot, "arrow contacts above the target's head threshold must count as headshots")
	_check(is_equal_approx(target.last_damage, 69.0), "fully charged headshots must apply the 1.5 damage multiplier")
	_check(is_equal_approx(target.last_charge, 1.0) and target.last_attacker.is_equal_approx(caster.global_position), "arrow impacts must pass real charge and caster origin to the combat code")
	var impact_position := arrow.global_position
	target.position.x += 0.5
	arrow._physics_process(0.1)
	_check(arrow.global_position.is_equal_approx(impact_position + Vector3(0.5, 0, 0)), "lodged arrows must track moving targets")
	target.free()
	arrow._physics_process(0.1)
	_check(arrow.is_queued_for_deletion(), "an arrow attached to a freed target must expire without stale transform access")
	world.free()


func _test_spawn_blocking_and_caster_exclusion() -> void:
	var world := _world()
	var wall := _body(Vector3(0, 0, -0.1), Vector3(3, 3, 0.01), 2)
	world.add_child(wall)
	var arrow := _arrow(world, Vector3(0, 0, -0.18))
	await physics_frame
	await process_frame
	_check(arrow.check_spawn_path(Vector3.ZERO), "camera-to-muzzle sweep must detect a wall behind the spawn point")
	_check(arrow.global_position.z > -0.11, "spawn-path impact must stick to the camera-facing wall surface")
	world.free()

	world = _world()
	wall = _body(Vector3.ZERO, Vector3(1, 1, 1), 2)
	world.add_child(wall)
	arrow = _arrow(world, Vector3(0, 0, -0.18))
	await physics_frame
	await process_frame
	_check(arrow.check_spawn_path(Vector3.ZERO), "a camera starting inside world collision must not shoot through it")
	world.free()

	world = _world()
	var caster := _body(Vector3.ZERO, Vector3(1, 1, 1), 4)
	world.add_child(caster)
	var target := _target(Vector3(0, 0, -2))
	world.add_child(target)
	arrow = _arrow(world, Vector3(0, 0, -0.18), caster)
	await physics_frame
	await process_frame
	_check(not arrow.check_spawn_path(Vector3.ZERO), "caster collision must be excluded even if it uses a queried collision layer")
	arrow._physics_process(0.1)
	_check(target.hit_count == 1, "excluding the caster must still allow forward target damage")
	world.free()


func _test_gravity_and_expiry() -> void:
	var world := _world()
	var arrow := _arrow(world, Vector3.ZERO)
	arrow.gravity = 5.0
	arrow._physics_process(0.5)
	_check(absf(arrow.global_position.y + 0.625) < 0.002 and absf(arrow.velocity.y + 2.5) < 0.002, "arrow flight must follow its authored ballistic gravity arc")
	_check(absf(arrow.global_position.z + 21.0) < 0.002, "ballistic integration must preserve charged forward speed")
	arrow._physics_process(ArrowProjectile.MAX_FLIGHT_TIME)
	_check(arrow.is_queued_for_deletion(), "missed arrows must expire after bounded flight time")
	world.free()

	world = _world()
	world.add_child(_body(Vector3(0, 0, -1), Vector3(3, 3, 0.02), 2))
	arrow = _arrow(world, Vector3.ZERO)
	await physics_frame
	await process_frame
	arrow._physics_process(0.1)
	_check(arrow.impacted and not arrow.is_queued_for_deletion(), "a wall impact must leave a briefly visible lodged arrow")
	arrow._physics_process(ArrowProjectile.STICK_TIME + 0.1)
	_check(arrow.is_queued_for_deletion(), "lodged arrows must expire without accumulating indefinitely")
	world.free()


func _test_pause_isolation() -> void:
	var world := _world()
	world.process_mode = Node.PROCESS_MODE_ALWAYS
	var arrow := _arrow(world, Vector3.ZERO)
	arrow.set_physics_process(true)
	_check(arrow.process_mode == Node.PROCESS_MODE_PAUSABLE, "arrows must opt into pause even under an always-processing game controller")
	var before_position := arrow.global_position
	var before_lifetime := arrow.lifetime
	paused = true
	for _frame in range(3):
		await physics_frame
		await process_frame
	_check(arrow.global_position.is_equal_approx(before_position) and is_equal_approx(arrow.lifetime, before_lifetime), "opening a paused test menu must freeze arrow flight and expiry")
	paused = false
	await physics_frame
	await process_frame
	_check(arrow.global_position.z < before_position.z, "closing the paused menu must resume arrow flight")
	world.free()


func _world() -> Node3D:
	var world := Node3D.new()
	root.add_child(world)
	return world


func _arrow(world: Node3D, position_value: Vector3, caster: Node = null) -> ArrowProjectile:
	var arrow := ArrowProjectile.new().configure(caster, Vector3.FORWARD, 1.0)
	world.add_child(arrow)
	arrow.global_position = position_value
	arrow.gravity = 0.0
	arrow.set_physics_process(false)
	return arrow


func _body(position_value: Vector3, size_value: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_value
	body.collision_layer = layer
	body.collision_mask = 0
	_add_shape(body, size_value)
	return body


func _target(position_value: Vector3) -> ArrowTarget:
	var target := ArrowTarget.new()
	target.position = position_value
	target.collision_layer = 4
	target.collision_mask = 0
	_add_shape(target, Vector3(0.8, 1.8, 0.2))
	return target


func _add_shape(body: StaticBody3D, size_value: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size_value
	collision.shape = box
	body.add_child(collision)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
