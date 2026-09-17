extends SceneTree

const SHOT_PROFILE := preload("res://scripts/bow_shot_profile.gd")
const SAMPLE_COUNT := 4096

var failures: Array[String] = []


class RejectingAmmoInventory:
	extends ExpeditionInventory

	func remove_item(item_id: String, quantity := 1, notify := true) -> bool:
		if item_id == "wooden_arrow":
			return false
		return super.remove_item(item_id, quantity, notify)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_test_charge_profile()
	_test_cone_sampling()
	_test_rng_contract()
	_test_player_shot_contract()
	_test_slack_launch_contract()
	_test_rejected_shots()
	_test_failed_ammo_transaction()
	_test_cancellation_paths()
	_test_recoil_and_true_aim()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("BOW ACCURACY TEST PASS: draw curve, unbiased cone sampling, all aim orientations, independent seeded randomness, real projectile direction, continuous draw cost, rejection/cancel safety and transient recoil")
		quit(0)
	else:
		for failure in failures:
			push_error("BOW ACCURACY TEST FAIL: " + failure)
		quit(1)


func _test_charge_profile() -> void:
	var previous_spread := INF
	var previous_recoil := INF
	for index in range(101):
		var charge := float(index) / 100.0
		var spread: float = SHOT_PROFILE.spread_degrees(charge)
		var recoil: float = SHOT_PROFILE.recoil_strength(charge)
		_check(is_equal_approx(spread, 12.0 * pow(1.0 - charge, 2.0)), "spread must follow the authored 12 × (1 − draw)² curve at %s" % charge)
		_check(spread <= previous_spread, "accuracy must improve monotonically with draw")
		if charge <= 0.1:
			_check(is_zero_approx(recoil), "slack drops must have no firing recoil")
		else:
			_check(is_equal_approx(recoil, lerpf(1.0, 0.25, charge)), "powered-shot recoil must retain the charge-scaled 1.0-to-0.25 curve")
			if charge > 0.11:
				_check(recoil <= previous_recoil, "powered-shot recoil must decrease monotonically with draw")
		previous_spread = spread
		previous_recoil = recoil
	_check(is_equal_approx(SHOT_PROFILE.spread_degrees(0.5), 3.0), "half draw must allow at most three degrees of deviation")
	_check(is_zero_approx(SHOT_PROFILE.spread_degrees(1.0)), "full draw must have no random deviation")
	_check(is_equal_approx(SHOT_PROFILE.spread_degrees(-2.0), 12.0) and is_zero_approx(SHOT_PROFILE.spread_degrees(2.0)), "out-of-range draw must clamp for accuracy")
	_check(is_zero_approx(SHOT_PROFILE.recoil_strength(-2.0)) and is_equal_approx(SHOT_PROFILE.recoil_strength(2.0), 0.25), "out-of-range draw must clamp for slack/full recoil")


func _test_cone_sampling() -> void:
	# Uniform solid angle means 1 − cos(theta), not theta itself, is uniform.
	# Fixed seeds make these distribution checks reproducible and non-flaky.
	var aims: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3.LEFT, Vector3(3.0, 4.0, -5.0), Vector3.ZERO]
	for aim_index in range(aims.size()):
		var raw_aim := aims[aim_index]
		var aim := raw_aim.normalized() if not raw_aim.is_zero_approx() else Vector3.FORWARD
		var reference := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var tangent := aim.cross(reference).normalized()
		var bitangent := aim.cross(tangent).normalized()
		for charge: float in [0.0, 0.5]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 70000 + aim_index
			var cap: float = deg_to_rad(SHOT_PROFILE.spread_degrees(charge))
			var cap_height := 1.0 - cos(cap)
			var normalized_radial_sum := 0.0
			var tangent_sum := Vector2.ZERO
			var quadrants := [0, 0, 0, 0]
			var annuli := [0, 0, 0, 0]
			var all_finite_and_unit := true
			var all_inside_cone := true
			for _sample in range(SAMPLE_COUNT):
				var direction: Vector3 = SHOT_PROFILE.sample_direction(raw_aim, charge, rng)
				all_finite_and_unit = all_finite_and_unit and direction.is_finite() and absf(direction.length() - 1.0) < 0.00001
				var dot := clampf(direction.dot(aim), -1.0, 1.0)
				all_inside_cone = all_inside_cone and dot >= cos(cap) - 0.000001
				var radial_fraction := (1.0 - dot) / cap_height
				normalized_radial_sum += radial_fraction
				var lateral := Vector2(direction.dot(tangent), direction.dot(bitangent))
				tangent_sum += lateral
				quadrants[(1 if lateral.x >= 0.0 else 0) + (2 if lateral.y >= 0.0 else 0)] += 1
				annuli[clampi(int(radial_fraction * 4.0), 0, 3)] += 1
			var label := "aim %s / draw %.1f" % [raw_aim, charge]
			_check(all_finite_and_unit, "every sampled direction must be finite and normalized: " + label)
			_check(all_inside_cone, "every shot must stay within its draw-dependent angular cone: " + label)
			_check(absf(normalized_radial_sum / SAMPLE_COUNT - 0.5) < 0.035, "samples must cover uniform solid angle rather than cluster at the center or rim: " + label)
			_check((tangent_sum / SAMPLE_COUNT).length() < sin(cap) * 0.035, "cone sampling must have no persistent horizontal or vertical bias: " + label)
			for index in range(4):
				_check(quadrants[index] > SAMPLE_COUNT * 0.19 and quadrants[index] < SAMPLE_COUNT * 0.31, "weak shots must reach every quadrant without directional bias: " + label)
				_check(annuli[index] > SAMPLE_COUNT * 0.19 and annuli[index] < SAMPLE_COUNT * 0.31, "equal-solid-angle annuli must receive comparable shot counts: " + label)
		var full_rng := RandomNumberGenerator.new()
		full_rng.seed = 500 + aim_index
		var full_state := full_rng.state
		_check((SHOT_PROFILE.sample_direction(raw_aim, 1.0, full_rng) as Vector3).is_equal_approx(aim), "full draw must preserve exact true aim for every orientation, including vertical/zero input")
		_check(full_rng.state == full_state, "full draw must not consume a random sample")


func _test_rng_contract() -> void:
	var first := RandomNumberGenerator.new()
	var second := RandomNumberGenerator.new()
	first.seed = 123456789
	second.seed = 123456789
	for index in range(100):
		var aim := Vector3(float(index % 3), 0.3, -1.0).normalized()
		var charge := float(index % 10) / 10.0
		var expected: Vector3 = SHOT_PROFILE.sample_direction(aim, charge, first)
		for _noise in range(7):
			randf()
		var actual: Vector3 = SHOT_PROFILE.sample_direction(aim, charge, second)
		_check(expected.is_equal_approx(actual), "identical private seeds must reproduce shots despite unrelated global random draws")
	seed(987654321)
	var expected_global := randi()
	seed(987654321)
	SHOT_PROFILE.sample_direction(Vector3.FORWARD, 0.0, first)
	_check(randi() == expected_global, "bow spread must not advance the global random stream")
	first.seed = 1122
	second.seed = 1122
	_check((SHOT_PROFILE.sample_direction(Vector3.FORWARD, -1.0, first) as Vector3).is_equal_approx(SHOT_PROFILE.sample_direction(Vector3.FORWARD, 0.0, second)), "clamped weak draw must preserve seeded sampling")
	var first_player := DungeonPlayer.new()
	var second_player := DungeonPlayer.new()
	_check(first_player.bow_shot_rng != second_player.bow_shot_rng, "each player must own a separate random generator")
	var second_state := second_player.bow_shot_rng.state
	first_player.bow_shot_rng.randf()
	_check(second_player.bow_shot_rng.state == second_state, "one player's randomness must never advance another player's stream")
	first_player.free()
	second_player.free()


func _fixture() -> Dictionary:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var world := Node3D.new()
	root.add_child(world)
	var player := DungeonPlayer.new()
	player.setup(world, null, inventory)
	world.add_child(player)
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_check(_equip(inventory, "hunting_bow"), "fixture must equip the actual starter bow")
	return {"world": world, "player": player, "inventory": inventory}


func _equip(inventory: ExpeditionInventory, item_id: String) -> bool:
	for index in range(inventory.slots.size()):
		if inventory.slots[index].id == item_id:
			return bool(inventory.equip_from_slot(index).get("accepted", false))
	return false


func _shoot(player: DungeonPlayer, charge: float, aim := Vector3.ZERO) -> Dictionary:
	player.bow_cooldown = 0.0
	player.stamina = 100.0
	_check(bool(player.begin_bow_draw().accepted), "accuracy test must draw through the real player API")
	player._update_combat(charge * DungeonPlayer.BOW_DRAW_DURATION)
	_check(is_equal_approx(player.get_bow_spread_degrees(), SHOT_PROFILE.spread_degrees(charge)), "player accuracy preview must share the real shot profile")
	return player.release_bow_shot(aim)


func _test_player_shot_contract() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var aim := Vector3(0.8, 0.3, -2.0).normalized()
	var deviations: Array[float] = []
	var recoil_values: Array[float] = []
	var emitted: Array[Vector2] = []
	player.arrow_fired.connect(func(charge: float, spent: float) -> void: emitted.append(Vector2(charge, spent)))
	for charge: float in [0.2, 0.5, 1.0]:
		player.bow_shot_rng.seed = 16491
		var rng_state := player.bow_shot_rng.state
		var count := player.get_arrow_count()
		var shot := _shoot(player, charge, aim)
		_check(bool(shot.get("accepted", false)), "weak, half and full draws must all release a real shot")
		if not bool(shot.get("accepted", false)):
			continue
		var arrow: ArrowProjectile = shot.projectile
		arrow.set_physics_process(false)
		var direction: Vector3 = shot.get("shot_direction", Vector3.ZERO)
		_check((shot.get("aim_direction", Vector3.ZERO) as Vector3).is_equal_approx(aim), "shot telemetry must preserve intended aim separately from spread")
		_check(direction.is_equal_approx(arrow.velocity.normalized()), "real projectile velocity must exactly use the returned randomized shot direction")
		_check(is_equal_approx(float(shot.get("spread_degrees", -1.0)), SHOT_PROFILE.spread_degrees(charge)), "reported spread must use charge before draw state is cleared")
		_check(is_equal_approx(float(shot.get("recoil_strength", -1.0)), SHOT_PROFILE.recoil_strength(charge)), "reported recoil must use the released charge")
		_check(is_equal_approx(player.bow_recoil_strength, SHOT_PROFILE.recoil_strength(charge)) and player._bow_recoil > 0.0, "successful shots must start the charge-scaled recoil")
		_check(player.get_arrow_count() == count - 1 and int(shot.arrows_spent) == 1, "accuracy must preserve the one-arrow-per-success transaction")
		var expected_cost := 22.0 * charge
		_check(is_equal_approx(player.stamina, 100.0 - expected_cost) and is_equal_approx(float(shot.stamina_spent), expected_cost), "accuracy must preserve the actual continuous draw cost without a release surcharge")
		_check(is_equal_approx(arrow.damage, lerpf(18.0, 46.0, charge)) and is_equal_approx(arrow.speed, 42.0 * clampf((charge - 0.1) / 0.9, 0.0, 1.0)), "powered accuracy must preserve charged damage and the new effective-tension launch speed")
		_check(not bool(shot.get("slack_drop", true)) and is_equal_approx(float(shot.get("launch_speed", -1.0)), arrow.speed), "powered shot telemetry must identify the real launch speed and non-slack flight")
		_check(is_equal_approx(player.bow_cooldown, DungeonPlayer.BOW_SHOT_COOLDOWN), "spread must preserve reload cooldown")
		deviations.append(aim.angle_to(direction))
		recoil_values.append(player.bow_recoil_strength)
		if is_equal_approx(charge, 1.0):
			_check(direction.is_equal_approx(aim) and player.bow_shot_rng.state == rng_state, "fully drawn live shots must follow true aim without randomness")
			var origin := arrow.global_position
			var initial_velocity := arrow.velocity
			arrow._physics_process(0.2)
			var expected := origin + initial_velocity * 0.2 + Vector3.DOWN * arrow.gravity * 0.02
			_check(arrow.global_position.distance_to(expected) < 0.001, "perfect launch accuracy must retain existing ballistic gravity after release")
		else:
			_check(player.bow_shot_rng.state != rng_state, "successful partial draws must advance their own random generator")
	if deviations.size() == 3:
		_check(deviations[0] > deviations[1] and deviations[1] > deviations[2] and deviations[2] < 0.00001, "replaying one sample at greater draw must narrow deviation all the way to exact aim")
		_check(recoil_values[0] > recoil_values[1] and recoil_values[1] > recoil_values[2], "live recoil strength must decrease with draw")
	_check(emitted.size() == 3, "each successful shot must still emit exactly one arrow-fired signal")
	if emitted.size() == 3:
		_check(emitted[0].is_equal_approx(Vector2(0.2, 4.4)) and emitted[1].is_equal_approx(Vector2(0.5, 11.0)) and emitted[2].is_equal_approx(Vector2(1.0, 22.0)), "arrow-fired signals must report released draw and cumulative draw stamina")
	fixture.world.free()


func _test_slack_launch_contract() -> void:
	for aim: Vector3 in [Vector3.FORWARD, Vector3.UP, Vector3.DOWN, Vector3.RIGHT, Vector3(0.4, 0.5, -0.3).normalized()]:
		for charge: float in [0.0, 0.05, 0.1]:
			var fixture := _fixture()
			var player: DungeonPlayer = fixture.player
			var state := player.bow_shot_rng.state
			var expected_origin := player.camera.global_position + aim * 0.18
			var shot := _shoot(player, charge, aim)
			_check(bool(shot.get("accepted", false)), "slack release must still create an actual arrow")
			if bool(shot.get("accepted", false)):
				var arrow := shot.projectile as ArrowProjectile
				arrow.set_physics_process(false)
				_check(arrow.velocity.is_equal_approx(Vector3.DOWN) and (shot.shot_direction as Vector3).is_equal_approx(Vector3.DOWN), "slack arrow must initially drop straight down regardless of aim")
				_check(bool(shot.get("slack_drop", false)) and is_zero_approx(float(shot.get("launch_speed", -1.0))), "slack telemetry must distinguish dropping from a powered forward shot")
				_check(arrow.global_position.is_equal_approx(expected_origin), "slack arrow must spawn just in front of the aimed camera, not below it or at a random muzzle offset")
				_check(player.bow_shot_rng.state == state, "slack release must not consume unused spread randomness")
				_check(is_zero_approx(player.bow_recoil_strength) and is_zero_approx(float(shot.recoil_strength)), "slack release must have no firing recoil")
				player._update_viewmodel(1.0)
				_check(player.camera.rotation.is_zero_approx(), "slack release must not kick the player's camera")
			fixture.world.free()


func _test_rejected_shots() -> void:
	for gate: String in ["not_drawing", "cooldown", "no_ammo", "safe_zone", "busy", "dead", "paused", "missing_camera", "weapon_changed"]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		player.bow_shot_rng.seed = 19965
		if gate != "not_drawing":
			_check(bool(player.begin_bow_draw().accepted), "failure fixture must begin drawing: " + gate)
			# Partial draw is deliberate: full draw does not consume random values
			# even on success, so it would hide accidental pre-validation sampling.
			player._update_combat(0.5)
		match gate:
			"cooldown": player.bow_cooldown = 1.0
			"no_ammo": fixture.inventory.remove_item("wooden_arrow", player.get_arrow_count())
			"safe_zone": player.configure_safe_zone(true)
			"busy": player.combat_state = DungeonPlayer.CombatState.RECOVERY
			"dead": player.combat_state = DungeonPlayer.CombatState.DEAD
			"paused": paused = true
			"missing_camera": player.camera = null
			"weapon_changed": _equip(fixture.inventory, "rusted_sword")
		var state := player.bow_shot_rng.state
		var count := player.get_arrow_count()
		var stamina_before := player.stamina
		var result := player.release_bow_shot(Vector3.FORWARD)
		_check(not bool(result.accepted), "invalid release must be rejected: " + gate)
		_check(player.bow_shot_rng.state == state, "rejected release must not advance spread RNG: " + gate)
		_check(player.get_arrow_count() == count and is_equal_approx(player.stamina, stamina_before), "rejected release must not consume ammo or stamina: " + gate)
		_check(_projectile_count(fixture.world) == 0 and is_zero_approx(player._bow_recoil), "rejected release must not create an arrow or recoil: " + gate)
		paused = false
		fixture.world.free()


func _test_failed_ammo_transaction() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var rejecting_inventory := RejectingAmmoInventory.new()
	rejecting_inventory.seed_default_loadout()
	_equip(rejecting_inventory, "hunting_bow")
	player.bind_inventory(rejecting_inventory)
	player.bow_shot_rng.seed = 89316
	player.begin_bow_draw()
	player._update_combat(0.5)
	var state := player.bow_shot_rng.state
	var count := player.get_arrow_count()
	var stamina_before := player.stamina
	var result := player.release_bow_shot()
	_check(not bool(result.accepted) and str(result.reason) == "no_ammo", "a failed final ammo removal must reject a shot even when initial ammo count was positive")
	_check(player.bow_shot_rng.state == state, "the final ammo transaction must succeed before spread sampling")
	_check(player.get_arrow_count() == count and is_equal_approx(player.stamina, stamina_before), "failed ammo transaction must preserve ammunition and add no further stamina charge or refund")
	_check(_projectile_count(fixture.world) == 0 and is_zero_approx(player._bow_recoil), "failed ammo transaction must free the unlaunched projectile without recoil")
	fixture.world.free()


func _test_cancellation_paths() -> void:
	for path: String in ["manual", "inventory", "focus", "safe_zone", "weapon_changed"]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		player.bow_shot_rng.seed = 9105
		var state := player.bow_shot_rng.state
		var count := player.get_arrow_count()
		player.begin_bow_draw()
		player._update_combat(0.5)
		var duplicate := player.begin_bow_draw()
		_check(not bool(duplicate.accepted) and player.bow_shot_rng.state == state, "duplicate draw must not reroll accuracy or consume randomness")
		match path:
			"manual": player.cancel_bow_draw()
			"inventory": player.prepare_for_inventory()
			"focus": player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"safe_zone": player.configure_safe_zone(true)
			"weapon_changed": _equip(fixture.inventory, "rusted_sword")
		_check(not player.bow_drawing and is_zero_approx(player.get_bow_draw_ratio()), "interruption must clear draw state: " + path)
		_check(player.bow_shot_rng.state == state and player.get_arrow_count() == count, "cancelling must preserve randomness and all arrows: " + path)
		_check(not bool(player.release_bow_shot().accepted) and _projectile_count(fixture.world) == 0, "release after cancellation must not create a shot: " + path)
		fixture.world.free()


func _test_recoil_and_true_aim() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	player.rotation.y = 0.6
	player._pitch = -0.21
	player.head.rotation.x = player._pitch
	var body_rotation := player.rotation
	var head_rotation := player.head.rotation
	var true_aim := -player.head.global_basis.z.normalized()
	player._update_viewmodel(1.0)
	var resting_position := player.weapon_pivot.position
	var weak := _shoot(player, 0.2)
	_check(bool(weak.accepted), "recoil fixture must fire the weak shot")
	player._update_viewmodel(1.0)
	var weak_position := player.weapon_pivot.position
	var weak_camera_rotation := player.camera.rotation.length()
	_check(weak_position.distance_to(resting_position) > 0.005, "weak release must produce visible weapon kick")
	_check(weak_camera_rotation > 0.0, "weak release must produce temporary camera recoil")
	_check(player.rotation.is_equal_approx(body_rotation) and player.head.rotation.is_equal_approx(head_rotation) and is_equal_approx(player._pitch, -0.21), "visual recoil must not permanently rotate player aim")
	# Fire before visual recovery, forcing only the reload gate open. Temporary
	# camera animation must never get baked into the next shot's real aim.
	var full := _shoot(player, 1.0)
	if bool(full.get("accepted", false)):
		_check((full.get("aim_direction", Vector3.ZERO) as Vector3).is_equal_approx(true_aim), "default input must use true head aim, not residual camera recoil")
		_check((full.get("shot_direction", Vector3.ZERO) as Vector3).is_equal_approx(true_aim), "a full draw during visual recovery must remain exactly on true aim")
	player._update_viewmodel(1.0)
	_check(player.weapon_pivot.position.distance_to(resting_position) < weak_position.distance_to(resting_position), "full draw must have visibly smaller weapon recoil than weak draw")
	_check(player.camera.rotation.length() < weak_camera_rotation, "full draw must have less camera recoil than weak draw")
	player._physics_process(0.3)
	_check(is_zero_approx(player._bow_recoil) and player.camera.rotation.is_zero_approx(), "camera recoil must recover completely after its short timer")
	_check(player.weapon_pivot.position.is_equal_approx(resting_position), "weapon recoil must recover to its resting pose")
	_check(player.rotation.is_equal_approx(body_rotation) and player.head.rotation.is_equal_approx(head_rotation) and is_equal_approx(player._pitch, -0.21), "recovery must leave true player aim unchanged")
	_shoot(player, 0.2)
	player._update_viewmodel(1.0)
	player.cancel_bow_draw()
	_check(is_zero_approx(player._bow_recoil) and is_zero_approx(player.bow_recoil_strength) and player.camera.rotation.is_zero_approx(), "explicit cancellation must immediately clear transient recoil")
	_shoot(player, 0.2)
	player._update_viewmodel(1.0)
	_equip(fixture.inventory, "rusted_sword")
	_check(is_zero_approx(player._bow_recoil) and is_zero_approx(player.bow_recoil_strength) and player.camera.rotation.is_zero_approx(), "equipment changes must clear all bow recoil")
	fixture.world.free()


func _projectile_count(world: Node) -> int:
	var count := 0
	for child in world.get_children():
		if child is ArrowProjectile:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
