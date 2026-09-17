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
	_check(is_equal_approx(player.SWORD_WRIST_TURN_SECONDS, 0.14), context + ": the wrist turn must finish within the existing windup")
	player._update_viewmodel(0.0)
	var zero := _sample(player, tip, stowed)
	_check(_point_drift(start, zero) < 0.001 and _angle(start.pose, zero.pose) < 0.06, context + ": beginning at zero time must not move the visible blade or hands")
	var wrist_turn := variant == "right_diagonal"
	var metadata := REFERENCE.clip_metadata(variant)
	var prep := REFERENCE.sample(variant, float(metadata.timing.windup_seconds))
	var elapsed := 0.0
	var spent_count := 0
	var expected_charge := 0.0
	var expected_cost := 0.0
	var windup_drift := 0.0
	var windup_angle := 0.0
	var grip_drift := 0.0
	var grip_rise := 0.0
	var arm_length_error := 0.0
	var turn_endpoint_error := 0.0
	var laid_pose: Dictionary = {}
	var laid_hold_drift := 0.0
	var turn_checkpoint_seen := false
	var entry_drift := INF
	var entry_angle := INF
	var source_position_error := 0.0
	var source_angle_error := 0.0
	var rejoin_seen := false
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
		if wrist_turn and player.combat_state == DungeonPlayer.CombatState.WINDUP:
			var remaining := player.SWORD_WRIST_TURN_SECONDS - player.state_time
			if remaining > 0.0000001: delta = minf(delta, remaining)
		elif player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			for checkpoint: float in [0.10, 0.145, 0.30]:
				var remaining := checkpoint - player.state_time
				if remaining > 0.0000001: delta = minf(delta, remaining)
		var previous_phase := player.combat_state
		var previous_time := player.state_time
		var previous_stamina := player.stamina
		var previous := _sample(player, tip, stowed)
		player.advance_action_timers(delta)
		player.advance_combat_state(delta, false)
		player._update_viewmodel(delta)
		elapsed += delta
		var actual := _sample(player, tip, stowed)
		arm_length_error = maxf(arm_length_error, actual.arm_length_error)
		if player.stamina < previous_stamina - 0.000001: spent_count += 1
		if player.combat_state == DungeonPlayer.CombatState.WINDUP:
			windup_drift = maxf(windup_drift, _point_drift(start, actual))
			windup_angle = maxf(windup_angle, _angle(start.pose, actual.pose))
			grip_drift = maxf(grip_drift, (start.grip as Vector3).distance_to(actual.grip))
			grip_rise = maxf(grip_rise, (actual.grip as Vector3).y - (start.grip as Vector3).y)
			if wrist_turn and player.state_time >= player.SWORD_WRIST_TURN_SECONDS - 0.0000001:
				turn_checkpoint_seen = turn_checkpoint_seen or absf(player.state_time - player.SWORD_WRIST_TURN_SECONDS) < 0.000001
				turn_endpoint_error = maxf(turn_endpoint_error, _angle(actual.pose, prep))
				if laid_pose.is_empty(): laid_pose = actual
				laid_hold_drift = maxf(laid_hold_drift, _point_drift(laid_pose, actual))
			_check(is_equal_approx(player.stamina, player.MAX_STAMINA), context + ": waiting for release must not spend stamina")
		if previous_phase == DungeonPlayer.CombatState.WINDUP and player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			saw_active = true
			entry_drift = _point_drift(previous, actual)
			entry_angle = _angle(previous.pose, actual.pose)
			expected_charge = clampf(previous_time + delta - 0.24, 0.0, 1.0)
			expected_cost = player.get_melee_stamina_cost(expected_charge)
			_check(is_zero_approx(player.state_time), context + ": commit must enter ACTIVE at zero")
			_check(elapsed >= maxf(0.22, hold) and elapsed <= maxf(0.22, hold) + STEP + 0.000001, context + ": release must retain its existing minimum windup")
			_check(is_equal_approx(player.attack_charge, expected_charge), context + ": charge must retain time-minus-0.24 calculation")
		if (player.combat_state == DungeonPlayer.CombatState.ACTIVE and player.state_time >= 0.10 - 0.0000001) or player.combat_state == DungeonPlayer.CombatState.RECOVERY:
			var phase := "active" if player.combat_state == DungeonPlayer.CombatState.ACTIVE else "recovery"
			var expected := REFERENCE.retimed_attack(phase, player.state_time, player.attack_charge, variant, true)
			# Idle breathing is a pre-existing presentation offset; remove only
			# that known offset before comparing with the immutable authored pose.
			var unoffset: Transform3D = actual.pose
			unoffset.origin -= MOTION.locomotion(player._motion_clock, 0.0, 0.0, true).position
			source_position_error = maxf(source_position_error, unoffset.origin.distance_to(expected.origin))
			source_angle_error = maxf(source_angle_error, _angle(unoffset, expected))
			preserved_samples += 1
			rejoin_seen = rejoin_seen or (phase == "active" and absf(player.state_time - 0.10) < 0.000001)
			contact_seen = contact_seen or (phase == "active" and absf(player.state_time - 0.145) < 0.000001)
		player._resolve_active_attack()
		if saw_active and player.combat_state == DungeonPlayer.CombatState.READY:
			finished = true
			break
	if wrist_turn:
		_check(grip_drift < 0.001 and grip_rise < 0.001, context + ": laying the blade must keep its actual imported grip pinned without raising the hand")
		_check(turn_checkpoint_seen and not laid_pose.is_empty() and turn_endpoint_error < 0.06, context + ": the wrist turn must reach the existing preparation orientation at 140ms")
		if not laid_pose.is_empty():
			_check((laid_pose.tip as Vector3).y < (start.tip as Vector3).y - 0.001 and _angle(start.pose, laid_pose.pose) > 0.5, context + ": the actual blade must lower and rotate around the held grip")
		_check(laid_hold_drift < 0.001, context + ": a longer held input must keep the completed laid pose until release")
	else:
		_check(windup_drift < 0.001 and windup_angle < 0.06, context + ": reverse and overhead must retain their existing held preparation")
	_check(arm_length_error < 0.0001, context + ": actual arm segments must retain their fixed lengths")
	_check(entry_drift < 0.001 and entry_angle < 0.06, context + ": ACTIVE zero must continue the final windup blade and wrist without a snap")
	_check(rejoin_seen and contact_seen and preserved_samples > 10 and source_position_error < 0.00003 and source_angle_error < 0.06, context + ": the authored track must be restored at 100ms, including exact 145ms contact and all following active/recovery poses")
	_check(finished and spent_count == 1 and is_equal_approx(player.stamina, player.MAX_STAMINA - expected_cost), context + ": the complete real attack must return READY with exactly one existing stamina cost")
	print("DIRECT ENTRY ", context, " grip_mm=", grip_drift * 1000.0, " grip_rise_mm=", grip_rise * 1000.0, " windup_deg=", windup_angle, " entry_mm=", entry_drift * 1000.0, " arm_length_mm=", arm_length_error * 1000.0, " authored_mm=", source_position_error * 1000.0, " authored_deg=", source_angle_error, " charge=", expected_charge, " spends=", spent_count)


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
	return {"pose": player.weapon_pivot.transform, "points": points, "tip": actual_tip, "grip": actual_grip, "arm_length_error": length_error}


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
	print("SWORD DIRECT ENTRY %s: pinned-grip wrist turn, retained reverse/overhead holds, release/charge/cost clocks, unchanged authored rejoin and expedition preservation; target damage is covered by sword_attack_variants" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
