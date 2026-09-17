extends SceneTree

var failures: Array[String] = []


class CombatPlayer extends DungeonPlayer:
	func _ready() -> void:
		# Keep production combat and collision code, without loading a game map,
		# viewmodel, audio, or external input/cursor handlers into the fixture.
		collision_layer = PLAYER_LAYER
		collision_mask = WORLD_LAYER
		head = Node3D.new()
		add_child(head)
		camera = Camera3D.new()
		head.add_child(camera)
		set_physics_process(false)
		set_process_unhandled_input(false)


class DamageTarget extends StaticBody3D:
	var hits := 0
	var last_damage := 0.0
	func receive_hit(amount: float, _attacker: Vector3, _force: float, _critical: bool) -> void:
		hits += 1
		last_damage = amount


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_mouse := Input.mouse_mode
	for injury in ["healthy", "blackout", "fracture", "both"]:
		await _test_weapons(injury)
	_test_healable_capacity()
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == original_mouse, "Weapon fixtures must preserve the original expedition and OS mouse mode.")
	for failure in failures:
		push_error(failure)
	print("BODY HEALTH WEAPON CORE TEST %s: actual bow/flail hits and stamina, weapon swaps, arm blackout/fracture combinations, paid draw timing/exhaustion, magic costs, recovery, and usable healing capacity" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _fixture(injury: String) -> Dictionary:
	ExpeditionSession.begin_new_journey()
	var world := Node3D.new()
	root.add_child(world)
	var player := CombatPlayer.new()
	player.setup(world, null, ExpeditionSession.get_inventory())
	world.add_child(player)
	if injury in ["blackout", "both"]:
		player.apply_body_damage("left_arm", 60.0)
	if injury in ["fracture", "both"]:
		player.apply_condition("fracture", 120.0, "right_arm")
	return {"world": world, "player": player}


func _equip(player: DungeonPlayer, id: String) -> void:
	var bag := player.inventory_model
	if str(bag.equipment.weapon) == id:
		return
	if bag.count_item(id) == 0:
		bag.add_item(id, 1)
	for index in bag.slots.size():
		if str(bag.slots[index].id) == id:
			_check(bool(bag.equip_from_slot(index).get("accepted", false)), "Actual inventory must equip %s." % id)
			return
	_check(false, "Weapon fixture could not find %s." % id)


func _target(world: Node3D, distance: float) -> DamageTarget:
	var target := DamageTarget.new()
	target.collision_layer = DungeonPlayer.ENEMY_LAYER
	target.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 0.4)
	shape.shape = box
	target.add_child(shape)
	world.add_child(target)
	target.position.z = -distance
	return target


func _test_weapons(injury: String) -> void:
	var fixture := _fixture(injury)
	var player: DungeonPlayer = fixture.player
	var world: Node3D = fixture.world
	var multiplier := 1.0 if injury == "healthy" else 0.64 if injury == "both" else 0.8
	var cost_multiplier := 1.0 / multiplier
	_check(is_equal_approx(player.get_body_attack_multiplier(), multiplier) and is_equal_approx(player.get_body_attack_stamina_multiplier(), cost_multiplier), "%s: physical damage and exertion must reflect each impaired arm exactly once." % injury)
	_check(is_equal_approx(player.get_melee_damage(), 27.0 * multiplier) and is_equal_approx(player.get_melee_stamina_cost(), 18.0 * cost_multiplier), "%s: sword must use the same arm rules as other weapons." % injury)

	_equip(player, "hunting_bow")
	player.stamina = 100.0
	var arrows := player.get_arrow_count()
	_check(player.begin_bow_draw().accepted, "%s: actual bow draw must start." % injury)
	player._advance_bow_draw(0.5)
	_check(is_equal_approx(player.get_bow_draw_ratio(), 0.5) and is_equal_approx(player.stamina, 100.0 - 11.0 * cost_multiplier), "%s: injured exertion must increase bow cost without accelerating draw time." % injury)
	_check(is_equal_approx(player.get_bow_damage(), 32.0 * multiplier), "%s: displayed bow damage must include arm injury." % injury)
	var shot := player.release_bow_shot(Vector3.FORWARD)
	_check(shot.accepted and is_equal_approx(shot.projectile.damage, 32.0 * multiplier) and is_equal_approx(shot.base_damage, shot.projectile.damage) and is_equal_approx(shot.stamina_spent, 11.0 * cost_multiplier) and shot.release_stamina_spent == 0.0 and player.get_arrow_count() == arrows - 1, "%s: releasing must create the adjusted arrow and spend no duplicate stamina." % injury)
	shot.projectile.free()
	player.bow_cooldown = 0.0
	player.stamina = 100.0
	var target := _target(world, 4.0)
	await physics_frame
	await process_frame
	player.begin_bow_draw()
	player._advance_bow_draw(1.0)
	shot = player.release_bow_shot(Vector3.FORWARD)
	shot.projectile.set_physics_process(false)
	shot.projectile._physics_process(0.3)
	_check(target.hits == 1 and is_equal_approx(target.last_damage, 46.0 * multiplier) and is_equal_approx(shot.launch_speed, 42.0), "%s: actual swept full-draw arrow must deal injured damage with unchanged healthy trajectory/speed." % injury)
	shot.projectile.free()
	target.free()
	player.bow_cooldown = 0.0
	player.stamina = 5.5 * cost_multiplier
	arrows = player.get_arrow_count()
	player.begin_bow_draw()
	player._advance_bow_draw(1.0)
	var exhausted_arrow: ArrowProjectile
	for child in world.get_children():
		if child is ArrowProjectile:
			exhausted_arrow = child
	_check(is_instance_valid(exhausted_arrow) and is_equal_approx(exhausted_arrow.charge, 0.25) and is_equal_approx(exhausted_arrow.damage, 25.0 * multiplier) and player.stamina == 0.0 and player.get_arrow_count() == arrows - 1 and not player.bow_drawing, "%s: exhaustion must release exactly the fraction of draw paid at the injured rate." % injury)
	if is_instance_valid(exhausted_arrow):
		exhausted_arrow.free()

	_equip(player, "chain_flail")
	if injury != "healthy":
		player.stamina = 18.0
		_check(not player.begin_flail_melee().accepted and player.stamina == 18.0 and player.flail_state == "ready", "%s: switching to flail must not bypass the higher melee stamina requirement." % injury)
	player.stamina = 100.0
	target = _target(world, 1.55)
	await physics_frame
	await process_frame
	var melee := player.begin_flail_melee()
	player._update_flail(0.21)
	player._update_flail(0.1)
	_check(melee.accepted and is_equal_approx(melee.stamina_spent, 18.0 * cost_multiplier) and is_equal_approx(player.stamina, 100.0 - 18.0 * cost_multiplier) and target.hits == 1 and is_equal_approx(target.last_damage, 32.0 * multiplier), "%s: actual flail melee must apply adjusted cost and one adjusted collision hit." % injury)
	player.cancel_flail_action()
	target.free()
	if injury != "healthy":
		player.stamina = 24.0
		_check(not player.begin_flail_spin().accepted and player.stamina == 24.0 and player.flail_state == "ready", "%s: insufficient adjusted flail spin cost must reject without action or charge." % injury)
	player.stamina = 100.0
	target = _target(world, 4.0)
	await physics_frame
	await process_frame
	var spin := player.begin_flail_spin()
	player._update_flail(1.2)
	var thrown := player.release_flail_throw(Vector3.FORWARD)
	thrown.projectile.set_physics_process(false)
	thrown.projectile._physics_process(0.3)
	_check(spin.accepted and is_equal_approx(spin.stamina_spent, 24.0 * cost_multiplier) and is_equal_approx(player.stamina, 100.0 - 24.0 * cost_multiplier) and thrown.stamina_spent == 0.0 and is_equal_approx(thrown.damage, 60.0 * multiplier) and target.hits == 1 and is_equal_approx(target.last_damage, thrown.damage) and is_equal_approx(thrown.range, 14.0), "%s: actual charged flail throw must retain range and pay adjusted spin cost once while dealing injured impact damage." % injury)
	player.cancel_flail_action()
	target.free()

	_equip(player, "weathered_staff")
	ExpeditionSession.learn_spell("fire_bolt")
	ExpeditionSession.learn_spell("healing_light")
	if injury != "healthy":
		player.stamina = 22.0
		_check(not player.cast_spell("fire_bolt", Vector3.FORWARD).accepted and player.stamina == 22.0 and player.spell_cooldown == 0.0, "%s: switching to staff must not bypass injured spell exertion." % injury)
	player.stamina = 100.0
	var magic := player.cast_spell("fire_bolt", Vector3.FORWARD)
	_check(magic.accepted and is_equal_approx(magic.stamina_spent, 22.0 * cost_multiplier) and is_equal_approx(player.stamina, 100.0 - 22.0 * cost_multiplier) and is_equal_approx(magic.projectile.damage, 30.0), "%s: actual attack spell must increase exertion while retaining its elemental damage." % injury)
	magic.projectile.free()
	player.spell_cooldown = 0.0
	player.stamina = 100.0
	player.apply_body_damage("left_leg", 40.0)
	player.select_treatment_part("left_leg")
	magic = player.cast_spell("healing_light")
	_check(magic.accepted and magic.health_restored == 32.0 and is_equal_approx(magic.stamina_spent, 28.0 * cost_multiplier) and is_equal_approx(player.stamina, 100.0 - 28.0 * cost_multiplier), "%s: actual healing magic must apply the same exertion penalty without reducing normal healing power." % injury)
	if injury in ["blackout", "both"]:
		_check(player.restore_body_part("left_arm") == 1.0, "%s: surgery must restore the disabled arm before ordinary recovery." % injury)
	if injury in ["fracture", "both"]:
		player.select_treatment_part("right_arm")
		player.inventory_model.add_item("splint", 1)
		_check(player.use_consumable("splint", player.inventory_model).accepted, "%s: actual splint must cure the remaining arm fracture." % injury)
	_check(player.get_body_attack_multiplier() == 1.0 and player.get_body_attack_stamina_multiplier() == 1.0, "%s: removing the arm impairment must restore healthy weapon multipliers." % injury)
	world.free()


func _test_healable_capacity() -> void:
	ExpeditionSession.begin_new_journey()
	var player := DungeonPlayer.new()
	player.bind_inventory(ExpeditionSession.get_inventory())
	player.apply_body_damage("left_arm", 60.0)
	_check(player.health < player.get_max_health() and player.get_healable_health_capacity() == 0.0 and player.get_healable_health_capacity("left_arm") == 0.0 and player.restore_health(440.0) == 0.0, "Blackout-only damage must report no usable ordinary healing capacity to rest/cooking checks.")
	player.apply_body_damage("right_leg", 20.0)
	_check(player.get_healable_health_capacity() == 20.0 and player.get_healable_health_capacity("right_leg") == 20.0 and player.get_healable_health_capacity("left_arm") == 0.0, "Healing capacity must sum only damaged living parts and respect an explicit part.")
	player.apply_body_damage("head", 35.0)
	_check(player.get_healable_health_capacity() == 0.0, "A dead body must never advertise ordinary healing capacity.")
	player.free()


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
