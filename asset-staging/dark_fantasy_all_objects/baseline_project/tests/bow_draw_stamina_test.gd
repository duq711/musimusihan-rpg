extends SceneTree

const SHOT_PROFILE := preload("res://scripts/bow_shot_profile.gd")

var failures: Array[String] = []


class DamageTarget:
	extends StaticBody3D

	var health := 500.0
	var hits := 0
	var last_damage := 0.0
	var last_charge := 0.0
	var was_headshot := false

	func receive_hit(amount: float, _attacker: Vector3, charge: float, headshot: bool) -> void:
		health -= amount
		hits += 1
		last_damage = amount
		last_charge = charge
		was_headshot = headshot


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_test_damage_profile_and_real_impacts()
	_test_live_draw_damage_and_hold()
	_test_frame_rate_independence()
	_test_low_stamina_and_exhaustion()
	_test_depletion_keeps_failure_gates()
	_test_cancel_and_interruptions()
	_test_pause_freezes_draw_and_recovery()
	_test_recovery_delay()
	_test_failed_release_preserves_spent_stamina()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("BOW DRAW STAMINA TEST PASS: capped live damage, actual impacts, 22/s continuous hold cost, frame-rate-independent exhaustion auto-release, no release surcharge, guarded failure/cancellation, pause and delayed recovery")
		quit(0)
	else:
		for failure in failures:
			push_error("BOW DRAW STAMINA TEST FAIL: " + failure)
		quit(1)


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


func _test_damage_profile_and_real_impacts() -> void:
	_check(is_equal_approx(SHOT_PROFILE.MIN_DAMAGE, 18.0) and is_equal_approx(SHOT_PROFILE.MAX_DAMAGE, 46.0), "the shared profile must define the existing 18-to-46 damage range")
	var world := Node3D.new()
	root.add_child(world)
	var previous := 0.0
	for index in range(101):
		var ratio := float(index) / 100.0
		var actual: float = SHOT_PROFILE.damage_for_draw(ratio)
		_check(is_equal_approx(actual, 18.0 + 28.0 * ratio) and actual >= previous and actual <= 46.0, "damage must increase continuously to, but never above, the full-draw maximum")
		previous = actual
	for ratio: float in [-2.0, 0.0, 0.5, 1.0, 2.0]:
		var expected := lerpf(18.0, 46.0, clampf(ratio, 0.0, 1.0))
		var target := DamageTarget.new()
		world.add_child(target)
		var arrow := ArrowProjectile.new().configure(null, Vector3.FORWARD, ratio)
		world.add_child(arrow)
		arrow.set_physics_process(false)
		# Direct impact isolates the damage contract from the separately tested
		# random spread distribution and ballistic collision sweep.
		arrow.global_position = target.global_position
		arrow._resolve_impact(target)
		arrow._resolve_impact(target)
		_check(is_equal_approx(SHOT_PROFILE.damage_for_draw(ratio), expected) and is_equal_approx(arrow.damage, expected), "shared and projectile damage must clamp identically for draw %s" % ratio)
		_check(target.hits == 1 and is_equal_approx(target.health, 500.0 - expected) and is_equal_approx(target.last_damage, expected), "a torso impact must remove exactly the configured charged damage once for draw %s" % ratio)
		_check(not target.was_headshot and is_equal_approx(target.last_charge, clampf(ratio, 0.0, 1.0)), "impact must pass the clamped real charge without a hidden headshot multiplier")
		arrow.free()
		target.free()
	world.free()


func _test_live_draw_damage_and_hold() -> void:
	for seconds: float in [0.0, 0.5, 1.0, 2.0]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		var signals: Array[Vector2] = []
		player.arrow_fired.connect(func(ratio: float, spent: float) -> void: signals.append(Vector2(ratio, spent)))
		var count := player.get_arrow_count()
		var state := player.bow_shot_rng.state
		_check(bool(player.begin_bow_draw().accepted), "positive stamina must start the real draw")
		_check(is_equal_approx(player.stamina, 100.0) and is_zero_approx(player.bow_draw_stamina_spent), "beginning a draw must not charge stamina up front")
		player._update_combat(seconds)
		var ratio := minf(seconds, 1.0)
		var spent := 22.0 * seconds
		var damage := lerpf(18.0, 46.0, ratio)
		_check(player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), ratio), "draw must reach full power after one second and remain held for %s seconds" % seconds)
		_check(is_equal_approx(player.stamina, 100.0 - spent) and is_equal_approx(player.bow_draw_stamina_spent, spent), "holding must continuously spend 22 stamina per second even after maximum draw")
		_check(player.get_arrow_count() == count and _projectile_count(fixture.world) == 0 and player.bow_shot_rng.state == state, "holding alone must not consume arrows, sample spread or auto-fire")
		var shot := player.release_bow_shot(Vector3.FORWARD)
		_check(bool(shot.get("accepted", false)), "release after a valid hold must succeed")
		if bool(shot.get("accepted", false)):
			var arrow := shot.projectile as ArrowProjectile
			arrow.set_physics_process(false)
			_check(is_equal_approx(arrow.damage, damage) and is_equal_approx(float(shot.get("base_damage", -1.0)), damage), "released projectile and telemetry must use the exact current charge damage")
			var target := DamageTarget.new()
			fixture.world.add_child(target)
			arrow.global_position = target.global_position
			arrow._resolve_impact(target)
			_check(target.hits == 1 and is_equal_approx(target.health, 500.0 - damage) and not target.was_headshot, "the actual player-fired arrow must apply the exact draw-scaled torso damage")
			_check(is_equal_approx(player.stamina, 100.0 - spent) and is_zero_approx(float(shot.get("release_stamina_spent", -1.0))), "release must not charge stamina a second time")
			_check(is_equal_approx(float(shot.get("stamina_spent", -1.0)), spent) and is_equal_approx(float(shot.get("draw_stamina_spent", -1.0)), spent), "successful telemetry must report cumulative actual draw spending")
			_check(player.get_arrow_count() == count - 1 and _projectile_count(fixture.world) == 1, "only a successful release may consume one arrow")
		_check(signals.size() == 1, "successful release must emit exactly one shot signal")
		if signals.size() == 1:
			_check(signals[0].is_equal_approx(Vector2(ratio, spent)), "shot signal must contain released power and actual total draw cost")
		_check(not player.bow_drawing and is_zero_approx(player.bow_draw_stamina_spent), "release must clear the per-draw accumulator")
		fixture.world.free()


func _test_frame_rate_independence() -> void:
	for fps: int in [30, 60, 144]:
		for seconds: float in [0.5, 2.0]:
			var fixture := _fixture()
			var player: DungeonPlayer = fixture.player
			player.begin_bow_draw()
			var frames := roundi(seconds * fps)
			for _frame in range(frames):
				player._physics_process(1.0 / fps)
			_check(absf(player.stamina - (100.0 - seconds * 22.0)) < 0.0001, "real player physics must drain the same stamina at %s FPS for %s seconds" % [fps, seconds])
			_check(absf(player.bow_draw_stamina_spent - seconds * 22.0) < 0.0001 and absf(player.get_bow_draw_ratio() - minf(seconds, 1.0)) < 0.0001, "draw power and accumulated cost must be frame-rate independent")
			var before := player.stamina
			var draw_before := player.get_bow_draw_ratio()
			player._update_combat(-1.0)
			_check(is_equal_approx(player.stamina, before) and is_equal_approx(player.get_bow_draw_ratio(), draw_before), "negative elapsed time must neither charge stamina nor reverse draw progress")
			fixture.world.free()


func _test_low_stamina_and_exhaustion() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	player.stamina = 1.0
	_check(bool(player.begin_bow_draw().accepted), "less than the old minimum cost must still allow drawing")
	player._update_combat(0.01)
	var quick := player.release_bow_shot()
	_check(bool(quick.get("accepted", false)) and is_equal_approx(player.stamina, 0.78), "low-stamina quick release must use only elapsed holding cost")
	fixture.world.free()
	for budget: float in [1.0, 5.0, 22.0, 100.0]:
		for fps: int in [0, 30, 60, 144]:
			fixture = _fixture()
			player = fixture.player
			player.stamina = budget
			var count := player.get_arrow_count()
			var state := player.bow_shot_rng.state
			var emitted: Array[Vector2] = []
			player.arrow_fired.connect(func(ratio: float, spent: float) -> void: emitted.append(Vector2(ratio, spent)))
			_check(bool(player.begin_bow_draw().accepted), "any positive stamina must allow a draw before exhaustion")
			if fps == 0:
				player._update_combat(100.0)
			else:
				for _frame in range(ceilf(budget / 22.0 * fps) + 2):
					if not player.bow_drawing:
						break
					player._physics_process(1.0 / fps)
			var expected_ratio := minf(budget / 22.0, 1.0)
			var arrows := _projectiles(fixture.world)
			_check(is_zero_approx(player.stamina) and not player.bow_drawing and is_zero_approx(player.get_bow_draw_ratio()), "exhaustion must clamp stamina to zero and release the held bow automatically")
			_check(player.get_arrow_count() == count - 1 and arrows.size() == 1 and emitted.size() == 1, "exhaustion must spend exactly one arrow and emit exactly one shot at %s FPS with %s stamina" % [fps, budget])
			if arrows.size() == 1:
				var arrow := arrows[0]
				arrow.set_physics_process(false)
				_check(is_equal_approx(arrow.charge, expected_ratio) and is_equal_approx(arrow.damage, 18.0 + 28.0 * expected_ratio), "automatic release must use only time affordable before depletion, not the remainder of a large frame")
				if expected_ratio <= 0.1:
					_check(arrow.velocity.is_equal_approx(Vector3.DOWN) and player.bow_shot_rng.state == state, "an exhausted slack draw must drop without unused spread samples")
				elif expected_ratio < 1.0:
					_check(player.bow_shot_rng.state != state, "an exhausted powered partial draw must use the real random spread path")
				else:
					_check(player.bow_shot_rng.state == state and is_equal_approx(arrow.damage, 46.0), "full-draw exhaustion must keep exact aim and maximum damage")
			if emitted.size() == 1:
				_check(emitted[0].is_equal_approx(Vector2(expected_ratio, budget)), "automatic shot signal must report actual affordable charge and all spent stamina")
			_check(not bool(player.release_bow_shot().accepted) and not bool(player.begin_bow_draw().accepted), "mouse release must not duplicate an automatic shot and zero stamina must reject a new draw")
			player._update_combat(100.0)
			_check(player.get_arrow_count() == count - 1 and _projectile_count(fixture.world) == 1 and emitted.size() == 1, "later held-input updates must never repeat an exhaustion shot")
			_check(is_zero_approx(player.stamina) and is_zero_approx(player.bow_draw_stamina_spent), "auto-release must stop draining and clear its per-draw accumulator")
			fixture.world.free()
	fixture = _fixture()
	player = fixture.player
	player.begin_bow_draw()
	player._update_combat(0.5)
	player.stamina = 0.0
	var released := player.release_bow_shot()
	_check(bool(released.get("accepted", false)) and is_equal_approx(released.projectile.charge, 0.5), "release must allow an already-held bow at zero stamina instead of applying the begin-draw gate again")
	fixture.world.free()


func _test_depletion_keeps_failure_gates() -> void:
	for gate: String in ["ammo", "camera", "busy", "dead", "paused", "equipment", "safe_zone", "cooldown"]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		player.stamina = 11.0
		player.begin_bow_draw()
		player._update_combat(0.25)
		var state := player.bow_shot_rng.state
		match gate:
			"ammo": fixture.inventory.remove_item("wooden_arrow", player.get_arrow_count())
			"camera": player.camera = null
			"busy": player.combat_state = DungeonPlayer.CombatState.RECOVERY
			"dead": player.combat_state = DungeonPlayer.CombatState.DEAD
			"paused": paused = true
			"equipment": _equip(fixture.inventory, "rusted_sword")
			"safe_zone": player.configure_safe_zone(true)
			"cooldown": player.bow_cooldown = 1.0
		var count := player.get_arrow_count()
		player._update_combat(100.0)
		_check(player.get_arrow_count() == count and player.bow_shot_rng.state == state and _projectile_count(fixture.world) == 0, "exhaustion must not bypass another release safety gate: " + gate)
		paused = false
		fixture.world.free()


func _test_cancel_and_interruptions() -> void:
	for path: String in ["manual", "inventory", "focus", "damage", "safe_zone", "equipment"]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		var count := player.get_arrow_count()
		var state := player.bow_shot_rng.state
		player.begin_bow_draw()
		player._update_combat(0.5)
		match path:
			"manual": player.cancel_bow_draw()
			"inventory": player.prepare_for_inventory()
			"focus": player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
			"damage": player.receive_environment_damage(1.0, "bow stamina test")
			"safe_zone": player.configure_safe_zone(true)
			"equipment": _equip(fixture.inventory, "rusted_sword")
		_check(not player.bow_drawing and is_zero_approx(player.bow_draw_stamina_spent), "interruption must clear draw and spending accumulator: " + path)
		player._update_combat(0.5)
		_check(is_equal_approx(player.stamina, 89.0), "interruption must not refund spent stamina or keep draining it: " + path)
		_check(player.get_arrow_count() == count and player.bow_shot_rng.state == state and _projectile_count(fixture.world) == 0, "interruption must leave ammunition and spread RNG untouched: " + path)
		fixture.world.free()


func _test_pause_freezes_draw_and_recovery() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	player.begin_bow_draw()
	player._update_combat(0.5)
	var delay_before := player.stamina_regen_delay
	paused = true
	player._update_combat(2.0)
	player._physics_process(2.0)
	_check(player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), 0.5), "paused direct updates must not advance a held bow")
	_check(is_equal_approx(player.stamina, 89.0) and is_equal_approx(player.bow_draw_stamina_spent, 11.0) and is_equal_approx(player.stamina_regen_delay, delay_before), "pause must freeze stamina spending and recovery delay")
	player.cancel_bow_draw()
	player.stamina_regen_delay = 0.0
	player._physics_process(2.0)
	_check(is_equal_approx(player.stamina, 89.0), "a paused cancelled bow must not allow stamina recovery")
	paused = false
	_check(bool(player.begin_bow_draw().accepted), "drawing must become available again after unpausing")
	player._update_combat(0.25)
	_check(is_equal_approx(player.stamina, 83.5) and is_equal_approx(player.bow_draw_stamina_spent, 5.5), "unpausing must resume elapsed-time spending from a fresh draw accumulator")
	fixture.world.free()


func _test_recovery_delay() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	player.begin_bow_draw()
	player._physics_process(0.5)
	_check(is_equal_approx(player.stamina, 89.0) and player.stamina_regen_delay > 0.0, "held-bow spending must arm the normal regeneration delay")
	player.stamina_regen_delay = 0.0
	player._update_stamina(0.5)
	_check(is_equal_approx(player.stamina, 89.0), "stamina must not regenerate while the bow is held even if a delay expires")
	player._physics_process(0.5)
	_check(is_equal_approx(player.stamina, 78.0) and player.stamina_regen_delay > 0.0, "a continued full draw must refresh its recovery delay")
	player.cancel_bow_draw()
	player._physics_process(0.3)
	_check(is_equal_approx(player.stamina, 78.0), "cancel must not grant immediate stamina regeneration")
	player._physics_process(0.4)
	_check(is_equal_approx(player.stamina, 78.0), "regeneration must remain delayed until the recovery timer expires")
	player._physics_process(0.1)
	_check(player.stamina > 78.0 and player.stamina <= DungeonPlayer.MAX_STAMINA, "normal stamina regeneration must resume after the delay")
	fixture.world.free()


func _test_failed_release_preserves_spent_stamina() -> void:
	for gate: String in ["ammo", "camera"]:
		var fixture := _fixture()
		var player: DungeonPlayer = fixture.player
		player.begin_bow_draw()
		player._update_combat(0.5)
		match gate:
			"ammo": fixture.inventory.remove_item("wooden_arrow", player.get_arrow_count())
			"camera": player.camera = null
		var before := player.stamina
		var count := player.get_arrow_count()
		var state := player.bow_shot_rng.state
		var shot := player.release_bow_shot()
		_check(not bool(shot.get("accepted", false)) and not player.bow_drawing, "failed release must cancel the active draw: " + gate)
		_check(is_equal_approx(player.stamina, before) and player.get_arrow_count() == count and player.bow_shot_rng.state == state and _projectile_count(fixture.world) == 0, "failed release must not add charges, refund holding cost or mutate ammunition/RNG: " + gate)
		fixture.world.free()


func _projectile_count(world: Node) -> int:
	return _projectiles(world).size()


func _projectiles(world: Node) -> Array[ArrowProjectile]:
	var arrows: Array[ArrowProjectile] = []
	for child in world.get_children():
		if child is ArrowProjectile:
			arrows.append(child)
	return arrows


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
