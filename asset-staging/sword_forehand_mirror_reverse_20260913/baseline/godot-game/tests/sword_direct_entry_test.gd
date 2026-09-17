extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const INVENTORY_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const REFERENCE := preload("res://scripts/reference_sword_motion.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const STEP := 1.0 / 120.0
const SOURCE_PATHS := [
	"res://assets/animations/reference_sword_motion/motion_manifest.json",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/sword_shield/left_arm.glb",
	"res://assets/3d/player/sword_shield/right_arm.glb",
]
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var inventory := before.get("inventory") as ExpeditionInventory
	var contents := INVENTORY_PREVIEW.inventory_fingerprint(inventory)
	var cursor := Input.mouse_mode
	var sources := _source_hashes()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "direct-entry test must not replace an existing sandbox")
	if sandbox.active:
		_finish()
		return
	sandbox.begin()
	for stowed in [false, true]:
		await _exercise_stance(stowed)
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == before and INVENTORY_PREVIEW.inventory_fingerprint(inventory) == contents and Input.mouse_mode == cursor and not sandbox.active, "direct-entry fixtures must restore the original expedition, inventory and cursor")
	_check(_source_hashes() == sources, "direct entry must preserve authored motion and original hand/sword assets")
	_finish()


func _exercise_stance(stowed: bool) -> void:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	await physics_frame
	_check(PREVIEW.configure_pose(fixture, "idle"), "direct-entry fixture must start with the production sword")
	player.set_torch_enabled(false)
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player.velocity = Vector3.ZERO
	player._motion_speed = 0.0
	player._update_viewmodel(0.3)
	if stowed:
		_check(bool(player.request_primary_weapon().accepted), "two-hand case must use the actual shield-stow request")
		for frame in 72:
			_tick(player, 1.0 / 60.0)
	_check(viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "direct-entry fixture must not sample hardware input")
	_check(player._has_shield_equipped() == not stowed and player._sword_support_requested() == stowed, "the requested real shield or two-hand stance must be established")
	for variant: String in ["right_diagonal", "left_reverse", "overhead"]:
		for hold: float in [0.0, 0.45]:
			_exercise_attack(player, variant, hold, stowed)
	player.cancel_sword_attack()
	viewport.queue_free()
	await process_frame


func _exercise_attack(player: DungeonPlayer, variant: String, hold: float, stowed: bool) -> void:
	var context := "%s %s hold=%.2f" % ["two_hand" if stowed else "shield", variant, hold]
	player.cancel_sword_attack()
	player.stamina = player.MAX_STAMINA
	player._motion_look_sway = Vector2.ZERO
	player._update_viewmodel(0.2)
	var tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
	var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
	_check(tip != null and grip != null, context + ": actual imported blade tip and grip must exist")
	if tip == null or grip == null: return
	var start := _sample(player, tip, stowed)
	var accepted := player.begin_sword_attack(variant)
	_check(bool(accepted.accepted), context + ": real begin must accept the attack")
	if not bool(accepted.accepted): return
	_check(is_equal_approx(player.get_melee_hit_time(), 0.145) and is_equal_approx(player.get_melee_active_duration(), 0.30), context + ": both stances must retain the coordinated combat clock")
	_check(player._sword_attack_coordinated and player._sword_direct_entry, context + ": both production stances must use the actual direct-entry path")
	var minimum_windup := 0.0 if variant == "right_diagonal" else 0.22
	_check(is_equal_approx(player._sword_minimum_windup_seconds(), minimum_windup), context + ": only coordinated forehand direct entry may release without a minimum wait")
	var entry_duration := player._sword_direct_entry_duration()
	_check(is_equal_approx(entry_duration, player.get_melee_hit_time() if variant == "right_diagonal" else 0.10), context + ": forehand entry must last to contact while reverse and overhead retain 100ms entry")
	player._update_viewmodel(0.0)
	var zero := _sample(player, tip, stowed)
	_check(_point_drift(start, zero) < 0.001 and _angle(start.pose, zero.pose) < 0.06, context + ": beginning at zero time must not move the visible blade or hands")
	var elapsed := 0.0
	var spent_count := 0
	var expected_charge := 0.0
	var expected_cost := 0.0
	var windup_drift := 0.0
	var windup_angle := 0.0
	var arm_length_error := 0.0
	var wrist_error := 0.0
	var entry_drift := INF
	var entry_angle := INF
	var source_position_error := 0.0
	var source_angle_error := 0.0
	var rejoin_seen := false
	var checkpoint_100ms_seen := false
	var contact_seen := false
	var preserved_samples := 0
	var saw_active := false
	var finished := false
	for frame in 420:
		if elapsed >= hold - 0.0000001:
			player.attack_release_requested = true
		var delta := STEP
		if elapsed < hold - 0.0000001:
			delta = minf(delta, hold - elapsed)
		if player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			for checkpoint: float in [0.10, 0.145, 0.30]:
				var remaining := checkpoint - player.state_time
				if remaining > 0.0000001: delta = minf(delta, remaining)
		var previous_phase := player.combat_state
		var previous_time := player.state_time
		var previous_stamina := player.stamina
		var released := player.attack_release_requested
		var previous := _sample(player, tip, stowed)
		player.advance_action_timers(delta)
		player.advance_combat_state(delta, false)
		player._update_viewmodel(delta)
		elapsed += delta
		var actual := _sample(player, tip, stowed)
		arm_length_error = maxf(arm_length_error, actual.arm_length_error)
		wrist_error = maxf(wrist_error, actual.wrist_error)
		if previous_phase == DungeonPlayer.CombatState.WINDUP:
			if not released:
				_check(player.combat_state == DungeonPlayer.CombatState.WINDUP, context + ": holding before the automatic-commit deadline must retain WINDUP")
			elif variant == "right_diagonal":
				_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and is_zero_approx(player.state_time), context + ": a forehand release must enter ACTIVE zero on the very next combat tick")
		if player.stamina < previous_stamina - 0.000001: spent_count += 1
		if player.combat_state == DungeonPlayer.CombatState.WINDUP:
			windup_drift = maxf(windup_drift, _point_drift(start, actual))
			windup_angle = maxf(windup_angle, _angle(start.pose, actual.pose))
			_check(is_equal_approx(player.stamina, player.MAX_STAMINA), context + ": waiting for release must not spend stamina")
		if previous_phase == DungeonPlayer.CombatState.WINDUP and player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			saw_active = true
			entry_drift = _point_drift(previous, actual)
			entry_angle = _angle(previous.pose, actual.pose)
			expected_charge = clampf(previous_time + delta - 0.24, 0.0, 1.0)
			expected_cost = player.get_melee_stamina_cost(expected_charge)
			_check(is_zero_approx(player.state_time), context + ": commit must enter ACTIVE at zero")
			_check(elapsed >= maxf(minimum_windup, hold) and elapsed <= maxf(minimum_windup, hold) + STEP + 0.000001, context + ": release must use immediate forehand entry or the other cuts' retained minimum windup")
			_check(is_equal_approx(player.attack_charge, expected_charge), context + ": charge must retain time-minus-0.24 calculation")
		if player.combat_state == DungeonPlayer.CombatState.ACTIVE and absf(player.state_time - 0.10) < 0.0000001:
			checkpoint_100ms_seen = true
			_check(variant != "right_diagonal" or player._uses_direct_sword_entry("active"), context + ": forehand must still be connecting at the 100ms checkpoint")
		if (player.combat_state == DungeonPlayer.CombatState.ACTIVE and player.state_time >= entry_duration - 0.0000001) or player.combat_state == DungeonPlayer.CombatState.RECOVERY:
			var phase := "active" if player.combat_state == DungeonPlayer.CombatState.ACTIVE else "recovery"
			var expected := REFERENCE.retimed_attack(phase, player.state_time, player.attack_charge, variant, true)
			# Idle breathing is a pre-existing presentation offset; remove only
			# that known offset before comparing with the immutable authored pose.
			var unoffset: Transform3D = actual.pose
			unoffset.origin -= MOTION.locomotion(player._motion_clock, 0.0, 0.0, true).position
			if variant == "right_diagonal":
				source_position_error = maxf(source_position_error, (unoffset * ARM.GRIP_CENTER).distance_to(expected * ARM.GRIP_CENTER))
				_check(unoffset.basis.z.distance_to(expected.basis.z) < 0.00002, context + ": forehand grip rotation must retain the original local-Z direction through contact and recovery")
				if phase == "active":
					# Independent contact contract: a proper half-turn reverses X/Y
					# and retains Z. Do not derive this expectation from apply().
					_check(unoffset.basis.x.distance_to(-expected.basis.x) < 0.00002 and unoffset.basis.y.distance_to(-expected.basis.y) < 0.00002, context + ": forehand contact must reverse the original width and length axes around the unchanged grip")
					var half_turned := Transform3D(Basis(-expected.basis.x, -expected.basis.y, expected.basis.z), Vector3.ZERO)
					source_angle_error = maxf(source_angle_error, _angle(unoffset, half_turned))
			else:
				source_position_error = maxf(source_position_error, unoffset.origin.distance_to(expected.origin))
				source_angle_error = maxf(source_angle_error, _angle(unoffset, expected))
			preserved_samples += 1
			rejoin_seen = rejoin_seen or (phase == "active" and absf(player.state_time - entry_duration) < 0.000001)
			contact_seen = contact_seen or (phase == "active" and absf(player.state_time - 0.145) < 0.000001)
			if phase == "active" and absf(player.state_time - 0.145) < 0.000001:
				_check(not player._uses_direct_sword_entry("active"), context + ": exact 145ms contact must have no remaining direct-entry blend")
		player._resolve_active_attack()
		if saw_active and player.combat_state == DungeonPlayer.CombatState.READY:
			finished = true
			break
	_check(windup_drift < 0.001 and windup_angle < 0.06, context + ": every cut must keep its captured blade, grip and arm pose throughout WINDUP without lifting or turning before release")
	_check(arm_length_error < 0.0001, context + ": actual arm segments must retain their fixed lengths")
	_check(wrist_error < 0.00003, context + ": the actual sleeve wrist must follow the final sword and original hand through its grip rotation")
	_check(entry_drift < 0.001 and entry_angle < 0.06, context + ": ACTIVE zero must continue the final windup blade and wrist without a snap")
	_check(checkpoint_100ms_seen and rejoin_seen and contact_seen and preserved_samples > 10 and source_position_error < 0.00003 and source_angle_error < 0.06, context + ": forehand must retain the authored grip path with opposite contact axes; reverse and overhead must retain the exact authored pose")
	_check(finished and spent_count == 1 and is_equal_approx(player.stamina, player.MAX_STAMINA - expected_cost), context + ": the complete real attack must return READY with exactly one existing stamina cost")
	print("DIRECT ENTRY ", context, " duration_ms=", entry_duration * 1000.0, " held_pose_mm=", windup_drift * 1000.0, " windup_deg=", windup_angle, " entry_mm=", entry_drift * 1000.0, " arm_length_mm=", arm_length_error * 1000.0, " authored_mm=", source_position_error * 1000.0, " authored_deg=", source_angle_error, " charge=", expected_charge, " spends=", spent_count)


func _sample(player: DungeonPlayer, tip: Node3D, stowed: bool) -> Dictionary:
	var snapshot := player.get_first_person_motion_snapshot()
	var actual_tip := player.camera.to_local(tip.global_position)
	var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
	var actual_grip := player.camera.to_local(grip.global_position)
	var points: Array[Vector3] = [actual_tip, actual_grip, player.camera.to_local(player.weapon_arm.global_position)]
	var arm: Dictionary = snapshot.joint_landmarks.get("sword", {})
	for joint: String in ["shoulder", "elbow", "wrist"]:
		if arm.has(joint): points.append(player.camera.to_local(arm[joint]))
	if stowed: points.append(player.camera.to_local(player.sword_support_arm.global_position))
	var upper := player.weapon_arm.get_node("RightArm_UpperArm_Surface") as Node3D
	var forearm := player.weapon_arm.get_node("RightArm_Forearm_Surface") as Node3D
	var upper_length := upper.to_global(ARM.REST_SHOULDER).distance_to(upper.to_global(ARM.REST_ELBOW))
	var forearm_length := forearm.to_global(ARM.REST_ELBOW).distance_to(forearm.to_global(ARM.REST_WRIST))
	var length_error := maxf(absf(upper_length - ARM.REST_UPPER_LENGTH), absf(forearm_length - ARM.REST_FOREARM_LENGTH))
	var actual_wrist := player.camera.to_local(forearm.to_global(ARM.REST_WRIST))
	var wrist_error := actual_wrist.distance_to(player.weapon_pivot.transform * ARM.REST_WRIST)
	return {"pose": player.weapon_pivot.transform, "points": points, "tip": actual_tip, "grip": actual_grip, "arm_length_error": length_error, "wrist_error": wrist_error}


func _point_drift(a: Dictionary, b: Dictionary) -> float:
	if a.points.size() != b.points.size(): return INF
	var maximum := (a.pose as Transform3D).origin.distance_to((b.pose as Transform3D).origin)
	for index in a.points.size(): maximum = maxf(maximum, (a.points[index] as Vector3).distance_to(b.points[index]))
	return maximum


func _angle(a: Transform3D, b: Transform3D) -> float:
	return rad_to_deg(a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()))


func _tick(player: DungeonPlayer, delta: float) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, false)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_PATHS: result[path] = FileAccess.get_sha256(path)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)


func _finish() -> void:
	for failure in failures: push_error(failure)
	print("SWORD DIRECT ENTRY %s: held WINDUP, forehand opposite contact axes at the original grip, unchanged reverse/overhead, actual wrist and arm lengths, release/charge/cost clocks and expedition preservation; target damage is covered by sword_attack_variants" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
