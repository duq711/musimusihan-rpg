extends SceneTree

var failures: Array[String] = []


class RegionTarget:
	extends StaticBody3D
	var region_offset := Vector3(1.15, 0.0, 0.0)
	var removed := false
	var located_hits := 0
	var generic_hits := 0
	var last_position := Vector3.INF
	var last_attacker := Vector3.INF
	var last_headshot := false
	var attachment: Node3D

	func _ready() -> void:
		collision_layer = 4
		collision_mask = 0
		add_to_group("enemy")
		var collider := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.30
		collider.shape = sphere
		add_child(collider)

	func query_located_hit(from: Vector3, to: Vector3, radius: float = 0.0) -> Dictionary:
		if removed:
			return {}
		var center := global_position + region_offset
		var motion := to - from
		var offset := from - center
		var a := motion.length_squared()
		var b := 2.0 * offset.dot(motion)
		var c := offset.length_squared() - pow(0.12 + radius, 2)
		var discriminant := b * b - 4.0 * a * c
		if a < 0.000001 or discriminant < 0.0:
			return {}
		var t := maxf(0.0, (-b - sqrt(discriminant)) / (2.0 * a))
		var contact := center + center.direction_to(from + motion * t) * 0.12
		return {"position": contact, "region": "arm_l", "fraction": t} if t <= 1.0 else {}

	func get_aim_point() -> Vector3:
		return global_position

	func get_located_hit_attachment(hit_position: Vector3) -> Node3D:
		attachment = Node3D.new()
		add_child(attachment)
		attachment.global_position = hit_position
		return attachment

	func receive_hit(_amount: float, _attacker: Vector3, _charge: float, _headshot: bool) -> void:
		generic_hits += 1

	func receive_located_hit(_amount: float, attacker: Vector3, _charge: float, headshot: bool, hit_position: Vector3) -> void:
		located_hits += 1
		last_position = hit_position
		last_attacker = attacker
		last_headshot = headshot


class MinimalPlayer:
	extends DungeonPlayer

	func _ready() -> void:
		camera = Camera3D.new()
		add_child(camera)
		head = Node3D.new()
		add_child(head)
		set_physics_process(false)

	func get_melee_damage(_charge: float = 0.0) -> float:
		return 20.0

	func apply_smithing_on_hit() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var mouse_mode := Input.mouse_mode
	await _test_melee()
	for kind in ["arrow", "flail", "magic"]:
		await _test_projectile(kind, false, false)
		await _test_projectile(kind, true, false)
		await _test_projectile(kind, false, true)
		if kind != "arrow":
			await _test_projectile(kind, false, true, true)
	_check(Input.mouse_mode == mouse_mode, "verification must preserve the cursor")
	if failures.is_empty():
		print("LOCATED HIT PATH TEST PASS: real melee and arrow/flail/magic contact routing, off-capsule limbs, removed-region misses, wall blocking, single hits and cursor preservation")
		quit(0)
	else:
		for failure in failures:
			push_error("LOCATED HIT PATH TEST FAIL: " + failure)
		quit(1)


func _test_melee() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := RegionTarget.new()
	world.add_child(target)
	target.position = Vector3(0.0, 0.0, -1.7)
	var player := MinimalPlayer.new()
	world.add_child(player)
	player.position.x = 1.15
	await physics_frame
	await process_frame
	player._perform_melee_hit()
	_check(target.located_hits == 1 and target.generic_hits == 0, "sword must deliver a real pointed region outside the navigation capsule")
	_check(absf(target.last_position.x - 1.15) < 0.001 and target.last_position.z < -1.3 and not target.last_headshot, "sword must preserve anatomical contact rather than attacker/aim-center coordinates")
	player.attack_hit_ids.clear()
	target.removed = true
	# Aim through the still-present broad capsule: missing anatomy must not be hit.
	player.position.x = 0.0
	player._perform_melee_hit()
	_check(target.located_hits == 1 and target.generic_hits == 0, "a removed region must not fall back to generic sphere damage")
	world.free()


func _test_projectile(kind: String, removed: bool, wall: bool, near_wall: bool = false) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := RegionTarget.new()
	world.add_child(target)
	target.position = Vector3(0.0, 0.0, -2.0)
	target.removed = removed
	if near_wall:
		target.region_offset.x = 1.30
	if removed:
		target.region_offset = Vector3.ZERO
	var origin := Vector3(0.0 if removed else 1.15, 0.0, 0.0)
	var caster := Node3D.new()
	world.add_child(caster)
	caster.position = origin + Vector3.BACK
	if wall:
		var blocker := StaticBody3D.new()
		blocker.collision_layer = 2
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3, 3, 0.02 if near_wall else 0.05)
		collision.shape = box
		blocker.add_child(collision)
		world.add_child(blocker)
		blocker.position.z = -1.915 if near_wall else -1.0
	var shot: Node3D
	match kind:
		"arrow": shot = ArrowProjectile.new().configure(caster, Vector3.FORWARD, 1.0)
		"flail": shot = FlailProjectile.new().configure(caster, Vector3.FORWARD, 1.0)
		"magic": shot = MagicProjectile.new().configure("fire_bolt", {"damage": 20, "speed": 20, "radius": 0.14}, caster, Vector3.FORWARD)
	world.add_child(shot)
	shot.set_physics_process(false)
	shot.global_position = origin
	await physics_frame
	await process_frame
	if kind == "arrow":
		shot.call("_sweep", origin, origin + Vector3.FORWARD * 4.0)
	elif kind == "flail":
		shot.call("_sweep", origin, origin + Vector3.FORWARD * 4.0)
	else:
		shot.call("_physics_process", 0.2)
	var context := "%s removed=%s wall=%s near=%s" % [kind, removed, wall, near_wall]
	if removed or wall:
		_check(target.located_hits == 0 and target.generic_hits == 0, context + ": absent anatomy and intervening walls must block damage")
	else:
		_check(target.located_hits == 1 and target.generic_hits == 0, context + ": actual sweep must route one precise hit outside the capsule")
		_check(target.last_position.is_finite() and absf(target.last_position.x - origin.x) < 0.001 and target.last_position.z < -1.5, context + ": exact contact must reach receive_located_hit")
		_check(target.last_attacker.is_equal_approx(caster.global_position), context + ": attacker origin and contact point must remain distinct")
		if kind == "arrow":
			_check(is_instance_valid(target.attachment), "a lodged anatomical arrow must request its bone/part anchor")
			if is_instance_valid(target.attachment):
				var before := shot.global_position
				# Mimic the anchor leaving the live actor with its physical part.
				target.attachment.reparent(world)
				target.attachment.global_position += Vector3.UP * 0.3
				shot.call("_update_stuck_transform")
				_check(shot.global_position.is_equal_approx(before + Vector3.UP * 0.3), "a lodged arrow must follow its reparented severed-region anchor")
	world.free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
