extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const FEATURES := {"motion_sword_run": "run", "motion_sword_jump": "jump", "motion_sword_sequence": "sequence"}
const STEP := 1.0 / 60.0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	var weapon := original.get_equipment_instance("weapon")
	weapon["uid"] = "reference_motion_original"
	weapon["smithing"] = {"quality": 0.83, "grip": "balanced", "runes": ["ember"]}
	ExpeditionSession.crowns = 167
	ExpeditionSession.hunger = 57.0
	ExpeditionSession.thirst = 48.0
	ExpeditionSession.stress = 28.0
	ExpeditionSession.apply_condition("bleeding", 45.0)
	var before := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var original_data := original.equipment_data.duplicate(true)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and bag != original and paused and room.panel_open, "reference motion fixtures must begin in a paused isolated expedition")
	for feature_id: String in FEATURES:
		var family := str(FEATURES[feature_id])
		var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == feature_id)
		_check(entries.size() == 1 and entries[0].action == "reference_sword_motion" and entries[0].payload == family, "each movement trial needs one executable catalog entry: " + feature_id)
		for iteration in range(2):
			room.player.stamina = 1.0
			room.player.health = 31.0
			room.run_feature(feature_id)
			var player: DungeonPlayer = room.player
			player.set_physics_process(false)
			_check(not room.panel_open and not paused and room.inventory == bag, "fixture must resume the same real trial inventory: " + feature_id)
			_check(player.position.is_equal_approx(room.REFERENCE_MOTION_START) and player.velocity.is_zero_approx(), "repeat must restore the actual actor's starting position and velocity: " + feature_id)
			_check(player.health == player.MAX_HEALTH and player.stamina == player.MAX_STAMINA, "repeat must replenish real health and stamina: " + feature_id)
			_check(str(bag.equipment.weapon) == "rusted_sword" and str(bag.equipment.offhand) == "round_shield", "fixture must equip the production sword and shield: " + feature_id)
			_check(not player.safe_zone_mode and player.collision_layer != 0 and player.collision_mask != 0, "movement trial must keep combat and actual collision active: " + feature_id)
			_check(not room.enemy_ai_enabled and room.loot_chests.is_empty(), "motion lane must clear earlier encounters and props: " + feature_id)
			_check(room.get_node_or_null("ReferenceSwordMotionInstructions") != null, "fixture must provide live controls at the lane: " + feature_id)
			_check(player.sword_attack_mode == "cycle" and int(player.get_first_person_motion_snapshot().landing_count) == 0, "each new trial must reset cut selection and movement history: " + feature_id)
			await _drive_frames(player, 30)
			_check(player.is_on_floor(), "actual test-room floor must support the player's collider: " + feature_id)
			if family == "sequence":
				await _exercise_sequence(room)
			elif family == "jump":
				_check(not is_instance_valid(room.arm_motion_target) and room.enemies_alive == 0, "jump lane must remain free of attack targets")
				await _exercise_jump(player)
			else:
				_check(not is_instance_valid(room.arm_motion_target) and room.enemies_alive == 0, "run lane must remain free of attack targets")
				await _exercise_run(player)
			var f2 := InputEventKey.new()
			f2.keycode = KEY_F2
			f2.physical_keycode = KEY_F2
			f2.pressed = true
			room._unhandled_input(f2)
			_check(paused and room.panel_open and player.combat_state == DungeonPlayer.CombatState.READY, "F2 must cancel combat and open the paused test menu: " + feature_id)
			var frozen: Dictionary = player.get_first_person_motion_snapshot().duplicate(true)
			var frozen_position := player.position
			var frozen_stamina := player.stamina
			var frozen_hunger := ExpeditionSession.hunger
			player.advance_movement(0.4, Vector2(0.0, -1.0), true)
			player._update_viewmodel(0.4)
			var paused_jump: Dictionary = player.request_jump()
			await create_timer(0.025, true).timeout
			_check(not bool(paused_jump.get("accepted", false)) and player.get_first_person_motion_snapshot() == frozen, "menu must freeze movement phases and reject jump requests: " + feature_id)
			_check(player.position == frozen_position and player.stamina == frozen_stamina and ExpeditionSession.hunger == frozen_hunger, "menu must stop actual translation, costs and survival: " + feature_id)
			_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data and sandbox.saved_session == before, "real movement and attacks must preserve the original inventory and saved expedition: " + feature_id)
	room.reset_room()
	_check(room.inventory != bag and room.inventory != original and room.panel_open and paused, "reset must create a fresh isolated bag after motion trials")
	room.run_feature("motion_sword_sequence")
	_check(is_instance_valid(room.arm_motion_target) and room.player.stamina == room.player.MAX_STAMINA, "sequence must remain runnable with a fresh actual target after reset")
	room._show_test_panel()
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "leaving the motion trials must restore the exact original inventory and expedition")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "exit must preserve original items, equipment and smithing metadata")
	if sandbox.active:
		sandbox.finish()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD MOTION TEST ROOM %s: three playable fixtures, actual run/jump/landing/collision and target damage, repeated F2, reset and original expedition restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _drive_frames(player: DungeonPlayer, frames: int, movement := Vector2.ZERO, sprint := false) -> void:
	# Use the production input boundary and CharacterBody collision. No OS key
	# injection or direct assignment of animation phases is needed headlessly.
	for frame in range(frames):
		await physics_frame
		player.advance_movement(STEP, movement, sprint)
		player._update_viewmodel(STEP)


func _exercise_run(player: DungeonPlayer) -> void:
	var before_walk := player.position
	var walking_stamina := player.stamina
	var clock := player._movement_run_time
	await _drive_frames(player, 36, Vector2(0, -1), false)
	_check(player.position.distance_to(before_walk) > 1.0 and is_equal_approx(player.stamina, walking_stamina), "walking must move the actual collider without sprint stamina cost")
	_check(player._movement_run_time > clock and player._has_reference_locomotion(), "walking must advance the authored stride instead of freezing its first key")
	var pose := player.weapon_pivot.transform
	_check(pose.basis.y.dot(Vector3.UP) > .97, "walking must keep the reference's almost upright sword")
	await _drive_frames(player, 24)
	var start := player.position
	var stamina := player.stamina
	var landings := int(player.get_first_person_motion_snapshot().landing_count)
	await _drive_frames(player, 36, Vector2(0.0, -1.0), true)
	_check(start.z - player.position.z > 2.0 and player.is_on_floor(), "run trial must move the real grounded collider down the clear lane")
	_check(is_equal_approx(stamina - player.stamina, 17.0 * STEP * 36.0), "run trial must use the production sprint stamina rate exactly once")
	_check(player.velocity.z < -player.WALK_SPEED and str(player.get_first_person_motion_snapshot().movement_phase) == "grounded", "actual sprint velocity must feed grounded motion")
	await _drive_frames(player, 24)
	_check(Vector2(player.velocity.x, player.velocity.z).length() < 0.01, "releasing movement must stop through production deceleration")
	_check(int(player.get_first_person_motion_snapshot().landing_count) == landings, "flat-ground sprint and stopping must not invent landings")


func _exercise_jump(player: DungeonPlayer) -> void:
	var floor_y := player.position.y
	var stamina := player.stamina
	var landings := int(player.get_first_person_motion_snapshot().landing_count)
	var jump: Dictionary = player.request_jump()
	_check(bool(jump.get("accepted", false)) and is_equal_approx(stamina - player.stamina, 12.0), "Space-equivalent request must perform the real twelve-stamina jump")
	if not bool(jump.get("accepted", false)): return
	var phases: Dictionary = {str(player.get_first_person_motion_snapshot().movement_phase): true}
	var highest := floor_y
	var left_floor := false
	for frame in range(120):
		await _drive_frames(player, 1)
		phases[str(player.get_first_person_motion_snapshot().movement_phase)] = true
		highest = maxf(highest, player.position.y)
		left_floor = left_floor or not player.is_on_floor()
		if left_floor and player.is_on_floor(): break
	_check(left_floor and highest > floor_y + 0.45 and player.is_on_floor(), "jump trial must leave and land on the real collidable floor")
	_check(phases.has("takeoff") and phases.has("air") and phases.has("land") and int(player.get_first_person_motion_snapshot().landing_count) == landings + 1, "one real jump must pass through takeoff, air and exactly one landing")
	_check(absf(player.position.y - floor_y) < 0.05, "landing must return the actor to the existing floor height")
	await _drive_frames(player, 36)
	_check(str(player.get_first_person_motion_snapshot().movement_phase) == "grounded", "landing presentation must finish and return to grounded movement")


func _exercise_sequence(room: Node3D) -> void:
	var player: DungeonPlayer = room.player
	var target: DungeonEnemy = room.arm_motion_target
	var landings := int(player.get_first_person_motion_snapshot().landing_count)
	_check(is_instance_valid(target) and room.enemies_alive == 1, "sequence must create exactly one real combat target")
	if not is_instance_valid(target): return
	_check(target.position.is_equal_approx(room.REFERENCE_MOTION_TARGET) and not target.is_physics_processing(), "sequence target must start at the documented nine-metre stationary endpoint")
	await _drive_frames(player, 35, Vector2(0.0, -1.0), true)
	_check(player.position.z < room.REFERENCE_MOTION_START.z - 2.0, "sequence must actually sprint toward its target")
	var jump: Dictionary = player.request_jump()
	_check(bool(jump.get("accepted", false)), "sequence must allow a real jump from sprinting")
	var left_floor := false
	for frame in range(120):
		var approach := Vector2(0.0, -1.0) if player.position.z - target.position.z > 2.7 else Vector2.ZERO
		await _drive_frames(player, 1, approach, approach != Vector2.ZERO)
		left_floor = left_floor or not player.is_on_floor()
		if left_floor and player.is_on_floor() and Vector2(player.velocity.x, player.velocity.z).length() < 0.01: break
	_check(left_floor and player.is_on_floor() and int(player.get_first_person_motion_snapshot().landing_count) == landings + 1, "sequence must pass through real flight and one floor collision before its cut")
	_check(player.position.z - target.position.z < 2.8 and player.position.z > target.position.z, "movement must bring the actor within actual melee range without teleporting")
	var health := target.health
	var stamina := player.stamina
	var cost := player.get_melee_stamina_cost(0.0)
	var attack := player.begin_sword_attack()
	_check(bool(attack.get("accepted", false)), "sequence must start the real sword attack after running and landing")
	if not bool(attack.get("accepted", false)): return
	player.attack_release_requested = true
	for frame in range(180):
		player.advance_action_timers(STEP)
		player.advance_combat_state(STEP)
		player._update_viewmodel(STEP)
		player._resolve_active_attack()
		if player.combat_state == DungeonPlayer.CombatState.READY: break
	_check(target.health < health and is_equal_approx(stamina - player.stamina, cost), "sequence cut must damage the actual target and charge exactly one attack cost")
	_check(bool(player.begin_sword_attack().get("accepted", false)), "sequence must permit another real attack before F2 cancellation")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "reference sword trial scene transition timed out: " + path)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
