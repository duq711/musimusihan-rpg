extends SceneTree

const PROJECTILE := preload("res://scripts/flail_projectile.gd")
const VISUALS := preload("res://scripts/flail_visuals.gd")
const PROFILE := preload("res://scripts/flail_profile.gd")

var failures: Array[String] = []


class FlailTarget:
	extends StaticBody3D
	var hits := 0
	var health := 500.0
	var last_damage := 0.0
	var last_charge := 0.0
	var headshot := false
	func receive_hit(amount: float, _attacker: Vector3, force: float, critical: bool) -> void:
		hits += 1
		health -= amount
		last_damage = amount
		last_charge = force
		headshot = critical


class FlailCaster:
	extends CharacterBody3D
	var anchor_offset := Vector3(0.25, 0.2, 0.0)
	func get_flail_chain_anchor() -> Vector3:
		return global_position + anchor_offset


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_visual_contract()
	_test_charge_contract()
	await _test_wall_and_first_hit()
	await _test_radius_contact_and_return_safety()
	await _test_spawn_path_and_caster_exclusions()
	_test_range_and_moving_return()
	await _test_pause_and_cleanup()
	if failures.is_empty():
		print("FLAIL PROJECTILE TEST PASS: spiked head and linked chain, charged range/damage/speed, swept sphere collision, wall/spawn blocking, one-hit outbound, harmless moving-anchor return, caster exclusions, pause and bounded cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error("FLAIL PROJECTILE TEST FAIL: " + failure)
		quit(1)


func _test_visual_contract() -> void:
	var flail := VISUALS.create_flail()
	_check(flail.get_node("ChainAnchor") is Marker3D and (flail.get_node("ChainAnchor") as Node3D).position.is_equal_approx(Vector3(0.0, 0.28, 0.0)), "flail must expose the exact handle chain anchor")
	_check(flail.get_node_or_null("LeatherHandle") != null and flail.get_node("Head/IronBall") is MeshInstance3D, "flail must have a leather handle and an actual iron ball")
	_check(flail.get_node("Head").get_child_count() >= 15, "the iron ball must carry visible spikes on its cardinal and diagonal faces")
	var chain := flail.get_node("Chain") as Node3D
	var links := chain.get_node("Links") as MultiMeshInstance3D
	_check(links.multimesh.mesh is TorusMesh and links.multimesh.visible_instance_count > 5, "the chain must consist of actual instanced ring meshes, not a painted line")
	for head_position: Vector3 in [Vector3(0.15, -0.16, -0.62), Vector3(0.2, 0.78, -0.45), Vector3(0.2, -0.18, -0.45)]:
		VISUALS.set_head_position(flail, head_position)
		_check((flail.get_node("Head") as Node3D).position.is_equal_approx(head_position), "head animation must set the true local iron-ball position")
		_check((chain.get_node("Start") as Node3D).position.is_equal_approx(Vector3(0.0, 0.28, 0.0)) and (chain.get_node("End") as Node3D).position.is_equal_approx(head_position), "animated chain endpoints must remain connected to the handle and iron ball")
		var count := links.multimesh.visible_instance_count
		# The headless dummy renderer does not store MultiMesh transforms. The
		# rendered run verifies the actual GPU instance endpoint data as well.
		if DisplayServer.get_name() != "headless":
			_check(links.multimesh.get_instance_transform(0).origin.is_equal_approx(Vector3(0.0, 0.28, 0.0)) and links.multimesh.get_instance_transform(count - 1).origin.is_equal_approx(head_position), "the visible first and last chain rings must agree with the attachment markers")
		for index in range(count):
			_check(links.multimesh.get_instance_transform(index).is_finite(), "animated chain ring transforms must remain finite")
	VISUALS.set_head_visible(flail, false)
	_check(not (flail.get_node("Head") as Node3D).visible and not chain.visible and (flail.get_node("LeatherHandle") as Node3D).visible, "throwing must hide held head/chain but keep the handle")
	VISUALS.set_head_visible(flail, true)
	_check((flail.get_node("Head") as Node3D).visible and chain.visible, "returning must restore held head and chain")
	VISUALS.update_chain(chain, Vector3.ZERO, Vector3.ZERO)
	_check(links.multimesh.visible_instance_count == 0, "zero-length chain must be safe and hide collapsed links")
	VISUALS.update_chain(chain, Vector3.ZERO, Vector3.UP * 14.0)
	_check(links.multimesh.visible_instance_count <= VISUALS.MAX_CHAIN_LINKS and links.multimesh.get_instance_transform(0).is_finite(), "full-range vertical chain must remain finite and bounded")
	flail.free()


func _test_charge_contract() -> void:
	for charge: float in [-1.0, 0.0, 0.5, 1.0, 2.0]:
		var shot := PROJECTILE.new().configure(null, Vector3.ZERO, charge)
		var clamped := clampf(charge, 0.0, 1.0)
		_check(is_equal_approx(shot.damage, lerpf(28.0, 60.0, clamped)) and is_equal_approx(shot.speed, lerpf(14.0, 26.0, clamped)) and is_equal_approx(shot.max_distance, lerpf(6.0, 14.0, clamped)), "flail damage, speed and maximum range must use clamped profile charge")
		_check(shot.direction.is_equal_approx(Vector3.FORWARD) and shot.phase == "outbound" and is_zero_approx(shot.travelled), "a fresh zero-aim throw must safely default to forward outbound motion")
		shot.free()


func _test_wall_and_first_hit() -> void:
	var fixture := _fixture()
	var world: Node3D = fixture.world
	world.add_child(_body(Vector3(0, 0, -2), Vector3(3, 3, 0.01), 2))
	var rear := _target(Vector3(0, 0, -3))
	world.add_child(rear)
	var shot := _shot(fixture, 1.0)
	var hits: Array[Node] = []
	shot.hit_target.connect(func(target: Node, _amount: float, _critical: bool) -> void: hits.append(target))
	await physics_frame
	await process_frame
	shot._physics_process(0.5)
	_check(shot.phase == "returning" and shot.global_position.z > -1.81, "26 m/s flail sphere must stop in front of a 1 cm wall during a 500 ms frame")
	_check(rear.hits == 0 and hits.is_empty(), "wall collision must block an enemy behind it without a damage signal")
	world.free()
	fixture = _fixture()
	world = fixture.world
	var front := _target(Vector3(0, 0, -2))
	rear = _target(Vector3(0, 0, -3))
	world.add_child(front)
	world.add_child(rear)
	shot = _shot(fixture, 1.0)
	hits.clear()
	shot.hit_target.connect(func(target: Node, _amount: float, _critical: bool) -> void: hits.append(target))
	await physics_frame
	await process_frame
	shot._physics_process(0.5)
	_check(front.hits == 1 and rear.hits == 0 and hits.size() == 1 and shot.phase == "returning", "only the first enemy may be hit before the flail immediately starts returning")
	_check(is_equal_approx(front.last_damage, 60.0) and is_equal_approx(front.health, 440.0) and not front.headshot and is_equal_approx(front.last_charge, 1.0), "full thrown flail must apply one actual 60-damage non-headshot hit")
	shot._physics_process(0.01)
	_check(front.hits == 1 and rear.hits == 0 and hits.size() == 1, "returning updates must not repeat an impact")
	world.free()


func _test_radius_contact_and_return_safety() -> void:
	var fixture := _fixture()
	var target := _target(Vector3(0.18, 0.0, -2.0), Vector3(0.04, 0.4, 0.04))
	fixture.world.add_child(target)
	var shot := _shot(fixture, 0.5)
	await physics_frame
	await process_frame
	shot._physics_process(0.2)
	_check(target.hits == 1 and is_equal_approx(target.last_damage, 44.0), "0.2-radius sphere must hit a target outside a center-line ray and apply charge-scaled damage")
	fixture.world.free()
	fixture = _fixture()
	shot = _shot(fixture, 0.0)
	shot._physics_process(1.0)
	_check(shot.phase == "returning", "maximum range must transition an unimpeded throw to return")
	target = _target(Vector3(0.0, 0.0, -3.0))
	fixture.world.add_child(target)
	await physics_frame
	await process_frame
	shot._physics_process(0.15)
	_check(target.hits == 0, "the returning head must pass enemies without dealing damage")
	fixture.world.free()


func _test_spawn_path_and_caster_exclusions() -> void:
	var fixture := _fixture()
	fixture.world.add_child(_body(Vector3(0, 0, -0.3), Vector3(3, 3, 0.01), 2))
	var shot := _shot(fixture, 1.0, Vector3(0, 0, -0.45))
	await physics_frame
	await process_frame
	_check(shot.check_spawn_path(Vector3.ZERO) and shot.phase == "returning" and shot.global_position.z > -0.11, "camera-to-spawn sphere sweep must prevent spawning through a close wall")
	fixture.world.free()
	fixture = _fixture()
	fixture.world.add_child(_body(Vector3.ZERO, Vector3(1, 1, 1), 2))
	shot = _shot(fixture, 1.0, Vector3(0, 0, -0.45))
	await physics_frame
	await process_frame
	_check(shot.check_spawn_path(Vector3.ZERO) and shot.phase == "returning", "a head whose camera starts inside world collision must not bypass the wall")
	fixture.world.free()
	fixture = _fixture()
	var caster: FlailCaster = fixture.caster
	caster.collision_layer = 2
	_add_shape(caster, Vector3(2.0, 2.0, 2.0))
	var child_collider := _body(Vector3(0.0, 0.0, -0.6), Vector3.ONE, 2)
	caster.add_child(child_collider)
	shot = _shot(fixture, 1.0, Vector3(0.0, 0.0, -0.45))
	await physics_frame
	await process_frame
	_check(not shot.check_spawn_path(Vector3.ZERO), "spawn sweep must exclude caster and its nested colliders")
	shot._physics_process(0.1)
	_check(shot.phase == "outbound" and shot.global_position.z < -3.0, "outbound sphere sweep must remain free of caster self-collision")
	fixture.world.free()


func _test_range_and_moving_return() -> void:
	for charge: float in [0.0, 0.5, 1.0]:
		var fixture := _fixture()
		var shot := _shot(fixture, charge)
		var signals: Array[bool] = []
		shot.returned.connect(func() -> void: signals.append(true))
		shot._physics_process(2.0)
		_check(shot.phase == "returning" and is_equal_approx(shot.travelled, PROFILE.throw_range(charge)) and is_equal_approx(-shot.global_position.z, PROFILE.throw_range(charge)), "a large outbound frame must stop exactly at the charged maximum range")
		var caster: FlailCaster = fixture.caster
		caster.global_position = Vector3(1.0, 0.5, 0.0)
		var anchor := caster.get_flail_chain_anchor()
		var before := shot.global_position
		shot._physics_process(0.05)
		_check(shot.global_position.is_equal_approx(before.move_toward(anchor, PROFILE.RETURN_SPEED * 0.05)), "returning head must seek the current hand position at the authored return speed")
		var chain := shot.get_node("Chain") as Node3D
		_check((chain.get_node("Start") as Node3D).global_position.is_equal_approx(anchor) and (chain.get_node("End") as Node3D).global_position.is_equal_approx(shot.global_position), "thrown chain must stay connected to the moving caster and head")
		shot._physics_process(1.0)
		_check(shot.is_queued_for_deletion() and signals.size() == 1 and shot.global_position.is_equal_approx(anchor), "reaching the hand must emit returned exactly once then safely free the projectile")
		shot._physics_process(1.0)
		_check(signals.size() == 1, "completion callbacks must never repeat")
		fixture.world.free()


func _test_pause_and_cleanup() -> void:
	var fixture := _fixture()
	var shot := _shot(fixture, 1.0)
	shot.set_physics_process(true)
	var before := shot.global_position
	var life := shot.lifetime
	paused = true
	shot._physics_process(1.0)
	for _frame in range(3):
		await physics_frame
		await process_frame
	_check(shot.global_position.is_equal_approx(before) and is_equal_approx(shot.lifetime, life), "both direct and scheduled paused updates must freeze flight and lifetime")
	paused = false
	shot.set_physics_process(false)
	shot._physics_process(0.1)
	_check(shot.global_position.z < before.z, "unpausing must resume flail flight")
	fixture.world.free()
	for cleanup: String in ["abort", "expired", "missing_caster"]:
		fixture = _fixture()
		shot = _shot(fixture, 1.0)
		var signals: Array[bool] = []
		shot.returned.connect(func() -> void: signals.append(true))
		match cleanup:
			"abort": shot.abort()
			"expired": shot.lifetime = 0.01
			"missing_caster": fixture.caster.free()
		shot._physics_process(0.1)
		_check(shot.is_queued_for_deletion() and signals.is_empty(), "cleanup must free safely without a misleading successful-return signal: " + cleanup)
		_check(not shot.check_spawn_path(Vector3.ZERO), "cleaned-up flails must not create any subsequent impact")
		fixture.world.free()


func _fixture() -> Dictionary:
	var world := Node3D.new()
	root.add_child(world)
	var caster := FlailCaster.new()
	world.add_child(caster)
	return {"world": world, "caster": caster}


func _shot(fixture: Dictionary, charge: float, origin := Vector3.ZERO) -> FlailProjectile:
	var shot := PROJECTILE.new().configure(fixture.caster, Vector3.FORWARD, charge)
	fixture.world.add_child(shot)
	shot.global_position = origin
	shot.set_physics_process(false)
	return shot


func _target(position_value: Vector3, size := Vector3(0.8, 1.8, 0.2)) -> FlailTarget:
	var target := FlailTarget.new()
	target.position = position_value
	target.collision_layer = 4
	target.collision_mask = 0
	_add_shape(target, size)
	return target


func _body(position_value: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_value
	body.collision_layer = layer
	body.collision_mask = 0
	_add_shape(body, size)
	return body


func _add_shape(body: CollisionObject3D, size: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
