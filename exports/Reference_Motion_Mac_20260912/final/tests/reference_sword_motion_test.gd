extends SceneTree

const REFERENCE := preload("res://scripts/reference_sword_motion.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const PREVIEW := preload("res://tests/reference_sword_motion_preview.gd")
const SOURCE := "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
const STEP := 1.0 / 60.0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(REFERENCE.is_available(), "Actual authored motion must load; fallback curves are not a completed delivery: " + REFERENCE.get_load_error())
	_check(REFERENCE.full_delivery_available(), "The complete motion delivery requires all eight actual authored clips")
	_check(REFERENCE.right_arm_available(), "Completed delivery requires v2 authored shoulder/elbow/wrist samples for all eight clips")
	_check(FileAccess.get_sha256(SOURCE) == REFERENCE.SOURCE_SHA256, "Reference motions must preserve the original static glove and sword asset")
	if REFERENCE.is_available():
		_test_clips_and_combat_clocks()
		await _test_actual_player_uses_delivery()
		await _test_authored_handoffs_and_clashes()
	for failure in failures:
		push_error(failure)
	print("REFERENCE SWORD MOTION %s: Mac/legacy motion delivery and production playback checks, physical run/air handoffs, guard ownership and composed solo/paired clash recovery" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_clips_and_combat_clocks() -> void:
	for clip: String in ["idle", "walk", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"]:
		_check(REFERENCE.has_track(clip) and REFERENCE.has_track(clip, "shield"), "Both hands must have a delivered trajectory: " + clip)
		_check(REFERENCE.has_right_arm(clip), "The actual authored right arm must accompany each delivered trajectory: " + clip)
		if not REFERENCE.has_track(clip):
			continue
		var metadata := REFERENCE.clip_metadata(clip)
		var duration: float = metadata.duration_seconds
		for frame in range(121):
			var pose := REFERENCE.sample(clip, duration * float(frame) / 120.0)
			_check(pose.is_finite() and absf(pose.basis.determinant() - 1.0) < 0.001, "Delivered pose must be a finite rigid transform: " + clip)
	var ready := CHOREOGRAPHY.ready()
	_check(not REFERENCE.sample("run", 0.25).is_equal_approx(ready), "Run must use a distinct authored trajectory")
	_check(not REFERENCE.sample("takeoff", 0.1).is_equal_approx(REFERENCE.sample("air", 0.1)), "Takeoff and airborne posture must remain separate actions")
	for variant: String in REFERENCE.ATTACK_CLIPS:
		var metadata := REFERENCE.clip_metadata(variant)
		var timing: Dictionary = metadata.timing
		var contact := REFERENCE.sample(variant, float(timing.windup_seconds) + float(timing.hit_seconds))
		for paired in [false, true]:
			var hit := 0.145 if paired else DungeonPlayer.ATTACK_HIT_TIME
			var end := 0.30 if paired else 0.16
			_check(MOTION.sword("active", hit, 0.0, false, paired, variant).is_equal_approx(contact), "Real sword clock must reach the authored contact pose: " + variant)
			for charge in [0.0, 1.0]:
				_check(MOTION.sword("windup", 0.22, charge, false, paired, variant).is_equal_approx(MOTION.sword("active", 0.0, charge, false, paired, variant)), "Windup must enter the delivered active clip continuously: " + variant)
				_check(MOTION.sword("active", end, charge, false, paired, variant).is_equal_approx(MOTION.sword("recovery", 0.0, charge, false, paired, variant)), "Delivered cut must enter recovery continuously: " + variant)
				_check(MOTION.sword("recovery", lerpf(0.47, 0.68, charge), charge, false, paired, variant).is_equal_approx(ready), "Every delivered cut must return to the same neutral grip: " + variant)


func _test_actual_player_uses_delivery() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	PREVIEW.ARM_PREVIEW.configure_pose(fixture, "idle")
	player.set_torch_enabled(false)
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._motion_look_sway = Vector2.ZERO
	player.velocity = Vector3.ZERO
	player._motion_speed = 0.0
	await physics_frame
	_check(bool(player.get_first_person_motion_snapshot().reference_motion_available), "The production player must report the actual delivery, not a preview substitute")
	for variant: String in REFERENCE.ATTACK_CLIPS:
		player.cancel_sword_attack()
		player.combat_state = DungeonPlayer.CombatState.ACTIVE
		player.sword_attack_variant = variant
		player.attack_charge = 0.0
		player.state_time = player.get_melee_hit_time()
		player._shield_impact = 0.0
		player._motion_clock = 0.0
		player._update_viewmodel(0.0)
		var expected := MOTION.sword("active", player.state_time, 0.0, false, player._has_shield_equipped(), variant)
		_check(player.weapon_pivot.transform.is_equal_approx(expected), "Actual visible sword must occupy the delivered contact pose: " + variant)
		var contact: Dictionary = player.get_first_person_motion_snapshot().hand_contacts.sword
		_check(float(contact.error) < 0.00001, "Original glove must remain attached to the actual moving sword: " + variant)
		var timing: Dictionary = REFERENCE.clip_metadata(variant).timing
		var arm := REFERENCE.sample_right_arm(variant, float(timing.windup_seconds) + float(timing.hit_seconds))
		if not arm.is_empty():
			var actual_arm: Dictionary = player.get_first_person_motion_snapshot().joint_landmarks.sword
			_check(bool(actual_arm.authored_arm_active) and bool(actual_arm.exact_authored_sample), "Actual hit must retain the evaluated Windows joint key: " + variant)
			for joint: String in ["shoulder", "elbow", "wrist"]:
				_check(player.camera.to_local(actual_arm[joint]).distance_to(arm[joint]) < 0.001, "Rendered arm must use the same authored contact joint: " + variant + "/" + joint)
	viewport.queue_free()
	await process_frame
	ExpeditionSession.restore_snapshot(snapshot)


func _test_authored_handoffs_and_clashes() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_inventory := _inventory_fingerprint(original.inventory)
	var original_cursor := Input.mouse_mode
	var original_pause := paused
	var original_ticks := Engine.physics_ticks_per_second
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "Authored handoff tests must not replace an existing sandbox")
	if sandbox.active:
		return
	Engine.physics_ticks_per_second = 60
	sandbox.begin()
	for paired in [false, true]:
		for motion: String in ["run", "air"]:
			await _test_moving_attack_handoff(paired, motion)
	await _test_guard_lowering_ownership()
	for paired in [false, true]:
		await _test_composed_clash_recovery(paired)
	paused = original_pause
	Engine.physics_ticks_per_second = original_ticks
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and _inventory_fingerprint(original.inventory) == original_inventory, "Actual authored handoffs and clashes must restore the original expedition and inventory contents")
	_check(Input.mouse_mode == original_cursor and paused == original_pause, "Authored handoff tests must preserve cursor and pause state")


func _new_motion_fixture(paired: bool) -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	fixture["viewport"] = viewport
	_check(PREVIEW.ARM_PREVIEW.configure_pose(fixture, "idle"), "Real player must prepare its normal sword equipment")
	var player := fixture.player as DungeonPlayer
	var bag := fixture.inventory as ExpeditionInventory
	if not paired:
		_check(bool(bag.unequip("offhand").accepted), "Solo fixture must unequip its shield through the real inventory transaction")
	player.cancel_sword_attack()
	player.set_torch_enabled(false)
	player.position = Vector3(0, 0.90, 2.4)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._pitch = 0.0
	player.velocity = Vector3.ZERO
	player._motion_clock = 0.0
	player._motion_speed = 0.0
	player._motion_look_sway = Vector2.ZERO
	player._motion_previous_look = Vector2.ZERO
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player.reset_reference_movement_motion(true)
	player._update_viewmodel(0.0)
	_check(viewport.own_world_3d and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "Motion fixture must use an isolated collision world with automatic hardware input disabled")
	return fixture


func _physics_frames(player: DungeonPlayer, count: int, movement := Vector2.ZERO, sprint := false, guard := false) -> void:
	for frame in range(count):
		await physics_frame
		player.advance_action_timers(STEP)
		player.advance_combat_state(STEP, guard)
		player.advance_movement(STEP, movement, sprint)
		player._update_viewmodel(STEP)
		player._resolve_active_attack()


func _action_tick(player: DungeonPlayer, delta: float, guard: bool = false) -> void:
	# Presentation/combat sampling after the physical setup intentionally keeps
	# target placement fixed. It still uses the real attack state and resolver.
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, guard)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _test_moving_attack_handoff(paired: bool, motion: String) -> void:
	var fixture := _new_motion_fixture(paired)
	var player := fixture.player as DungeonPlayer
	var context := "%s %s" % ["paired" if paired else "solo", motion]
	await _physics_frames(player, 24)
	await _physics_frames(player, 36, Vector2(0, -1), true)
	_check(player.is_on_floor() and player.velocity.z < -player.WALK_SPEED, "Handoff must start from an actual colliding ground sprint: " + context)
	if motion == "air":
		var jump := player.request_jump()
		_check(bool(jump.accepted), "Air handoff must originate from an accepted real jump: " + context)
		for frame in range(60):
			await _physics_frames(player, 1, Vector2(0, -1), true)
			if str(player.get_first_person_motion_snapshot().movement_phase) == "air":
				break
		_check(not player.is_on_floor() and str(player.get_first_person_motion_snapshot().movement_phase) == "air", "Air attack setup must observe actual flight, not an assigned phase: " + context)
	var before := _actual_poses(player, paired)
	_check(not (before.weapon as Transform3D).is_equal_approx(CHOREOGRAPHY.ready()), "Moving handoff fixture must expose a visible non-neutral pose: " + context)
	var accepted := player.begin_sword_attack()
	_check(bool(accepted.accepted), "Actual moving sword attack must be accepted: " + context)
	if bool(accepted.accepted):
		player._update_viewmodel(0.0)
		_check_poses_equal(before, _actual_poses(player, paired), "WINDUP at zero time must retain the previous rendered pose: " + context)
		_action_tick(player, 0.11)
		_check(player.combat_state == DungeonPlayer.CombatState.WINDUP and not player._reference_pose_handoff_active, "Moving-pose correction must finish within windup, before any ACTIVE hit: " + context)
		player.attack_release_requested = true
		_action_tick(player, 0.1101)
		_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and not player._reference_pose_handoff_active, "Release must enter ACTIVE through the real state machine with no residual handoff: " + context)
		var target := _new_enemy(fixture, "실제 모션 타격 대상")
		target.global_position = player.camera.global_position + Vector3(0, -0.2, -1.7)
		await physics_frame
		_check(not player._query_melee_hits().is_empty(), "Real contact target must intersect the production melee query: " + context)
		var health := target.health
		# Isolate the exact gameplay contact timestamp after the moving handoff.
		# Only additive view offsets are neutralized; no clip or combat phase is
		# injected, and the actual Windows trajectory remains authoritative.
		player.velocity = Vector3.ZERO
		player._motion_speed = 0.0
		player._motion_look_sway = Vector2.ZERO
		player._motion_clock = 0.0
		var hit := player.get_melee_hit_time()
		player.advance_combat_state(hit - 0.0001)
		player._update_viewmodel(0.0)
		player._resolve_active_attack()
		_check(is_equal_approx(target.health, health), "A completed handoff must not deliver damage before the real hit timestamp: " + context)
		player.advance_combat_state(0.0001)
		player._update_viewmodel(0.0)
		var expected := MOTION.sword("active", hit, player.attack_charge, false, paired, player.sword_attack_variant)
		_check(_near_transform(player.weapon_pivot.transform, expected), "At the real hit timestamp the visible weapon must match the unshifted delivered contact pose: " + context)
		player._resolve_active_attack()
		var hit_health := target.health
		_check(hit_health < health, "The real attack must damage its actual target at contact: " + context)
		player._resolve_active_attack()
		_check(is_equal_approx(target.health, hit_health), "Repeated contact resolution must not apply a second hit: " + context)
	(fixture.viewport as SubViewport).queue_free()
	await process_frame


func _test_guard_lowering_ownership() -> void:
	var fixture := _new_motion_fixture(true)
	var player := fixture.player as DungeonPlayer
	await _physics_frames(player, 24)
	await _physics_frames(player, 36, Vector2(0, -1), true)
	var before := _actual_poses(player, true)
	player.advance_combat_state(STEP, true)
	player._update_viewmodel(0.0)
	_check_poses_equal(before, _actual_poses(player, true), "Raising guard at zero time must retain the actual preceding run pose")
	_action_tick(player, 0.30, true)
	_check(is_equal_approx(player._shield_raise_progress, 1.0), "The held real guard must finish raising before its lowering trial")
	var partial_samples := 0
	for frame in range(24):
		_action_tick(player, STEP, false)
		var progress := float(player.get_first_person_motion_snapshot().shield_raise_progress)
		if progress <= 0.0:
			break
		partial_samples += 1
		_check(not player.blocking and not player._reference_locomotion_valid, "Released guard must retain authored movement exclusion while its actual lowering progress is positive")
		var expected := CHOREOGRAPHY.shield(progress, 0.0, "ready", player.state_time, 0.0, player.sword_attack_variant)
		var local_velocity := player.global_basis.inverse() * player.velocity
		var movement := MOTION.locomotion(player._motion_clock, player._motion_speed, local_velocity.x, false)
		expected.origin += movement.position * 0.65 + player._shield_corner_offset()
		_check(_near_transform(player.shield_pivot.transform, expected), "The actual lowering shield must follow its production guard curve instead of an absolute run clip")
	_check(partial_samples > 8 and is_zero_approx(player._shield_raise_progress), "Guard lowering must expose intermediate progress and reach zero after release")
	_check(player._reference_locomotion_valid, "Authored locomotion must resume once actual guard lowering reaches zero")
	(fixture.viewport as SubViewport).queue_free()
	await process_frame


func _test_composed_clash_recovery(paired: bool) -> void:
	var fixture := _new_motion_fixture(paired)
	var player := fixture.player as DungeonPlayer
	var context := "paired" if paired else "solo"
	await _physics_frames(player, 24)
	await _physics_frames(player, 36, Vector2(0, -1), true)
	if paired:
		_action_tick(player, 0.25, true)
		var impact := player.receive_attack(12.0, player.global_position + Vector3(0, 0, -2))
		_check(bool(impact.blocked) and not bool(impact.parried), "Paired overlay fixture must originate its recoil from a real ordinary blocked attack")
		player.advance_combat_state(0.0001, false)
	# A real look change adds view sway on top of the existing moving stride.
	player.rotation.y += 0.25
	var accepted := player.begin_sword_attack()
	_check(bool(accepted.accepted), "Composed clash must start a real sword attack: " + context)
	if not bool(accepted.accepted):
		(fixture.viewport as SubViewport).queue_free()
		await process_frame
		return
	player.attack_release_requested = true
	_action_tick(player, 0.2201)
	_action_tick(player, 0.04)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "Composed clash must occur inside the actual active swing: " + context)
	var pure := MOTION.sword("active", player.state_time, player.attack_charge, false, paired, player.sword_attack_variant)
	_check(player.weapon_pivot.position.distance_to(pure.origin) > 0.005 and player._motion_look_sway.length() > 0.0001, "Clash fixture must contain nonzero movement and look overlays, not only a raw clip sample: " + context)
	var enemy := _new_enemy(fixture, "합성 자세 검격 대상")
	enemy.position = Vector3(12, 1, -12)
	enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	var enemy_proxy := enemy.get_sword_clash_proxy()
	var player_proxy := player.get_sword_clash_proxy()
	# Deliberately position the real enemy blade at this actual sampled blade.
	# This isolates recovery; sword_clash_test covers natural opposing sweeps.
	enemy.sword_blade.global_position += (player_proxy.center as Vector3) - (enemy_proxy.center as Vector3)
	var before := _actual_poses(player, paired)
	var stamina := player.stamina
	var health := player.health
	var enemy_health := enemy.health
	var aim := player.head.global_basis
	var clashed := player.try_sword_clash(enemy)
	_check(clashed and player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER, "Actual blade overlap must cancel both real attacks into their recovery states: " + context)
	if clashed:
		player._update_viewmodel(0.0)
		_check_poses_equal(before, _actual_poses(player, paired), "Composed clash recovery t=0 must equal actual contact without duplicated overlays: " + context)
		var saved_weapon := player._sword_clash_weapon_pose
		var saved_shield := player._sword_clash_shield_pose
		var frozen := player.get_first_person_motion_snapshot()
		var frozen_poses := _actual_poses(player, paired)
		paused = true
		_action_tick(player, 0.4)
		_check(player.get_first_person_motion_snapshot() == frozen, "Pause must freeze authored clash clocks and lifecycle: " + context)
		_check_poses_equal(frozen_poses, _actual_poses(player, paired), "Pause must freeze actual composed clash poses: " + context)
		paused = false
		for frame in range(80):
			_action_tick(player, 1.0 / 120.0)
			_check(player._sword_clash_weapon_pose == saved_weapon and player._sword_clash_shield_pose == saved_shield, "Recovery must never overwrite its saved actual contact poses: " + context)
			if player.combat_state == DungeonPlayer.CombatState.READY:
				break
		_check(player.combat_state == DungeonPlayer.CombatState.READY and not player._sword_clash_recovering, "Actual composed clash must finish within the existing recovery duration: " + context)
		_check(is_equal_approx(player.stamina, stamina) and is_equal_approx(player.health, health) and is_equal_approx(enemy.health, enemy_health), "Clash recovery must not add damage or spend resources again: " + context)
		_check(player.head.global_basis.is_equal_approx(aim), "Composed clash must preserve gameplay aim: " + context)
		await _physics_frames(player, 60)
		var idle := REFERENCE.sample("idle", player._motion_clock)
		_check(_near_transform(player.weapon_pivot.transform, idle), "After actual stopping, completed clash must return to the current authored idle frame: " + context)
	(fixture.viewport as SubViewport).queue_free()
	await process_frame


func _new_enemy(fixture: Dictionary, title: String) -> DungeonEnemy:
	var enemy := DungeonEnemy.new()
	enemy.configure(title, 2000.0, 12.0, 0.0, Color(0.3, 0.3, 0.3))
	enemy.position = Vector3(20, 1, -20)
	(fixture.stage as Node3D).add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(fixture.player as DungeonPlayer, null, fixture.stage)
	_check(enemy.sword_blade != null, "Actual enemy fixture must own rendered blade geometry")
	return enemy


func _actual_poses(player: DungeonPlayer, paired: bool) -> Dictionary:
	var camera_inverse := player.camera.global_transform.affine_inverse()
	var poses := {"weapon": player.weapon_pivot.transform, "right_wrist": camera_inverse * player.weapon_arm.global_transform}
	var joints: Dictionary = player.get_first_person_motion_snapshot().joint_landmarks.get("sword", {})
	for joint: String in ["shoulder", "elbow", "wrist"]:
		if joints.has(joint): poses["right_" + joint + "_joint"] = Transform3D(Basis.IDENTITY, camera_inverse * (joints[joint] as Vector3))
	if paired:
		poses["shield"] = player.shield_pivot.transform
		poses["left_wrist"] = camera_inverse * player.shield_arm.global_transform
	return poses


func _check_poses_equal(before: Dictionary, after: Dictionary, context: String) -> void:
	for part: String in before:
		_check(after.has(part) and _near_transform(before[part], after[part]), context + " / " + part)


func _near_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.00005 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.002


func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text() if inventory != null else "none"


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
