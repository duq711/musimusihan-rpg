extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const INVENTORY_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const REFERENCE := preload("res://scripts/reference_sword_motion.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
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
	for variant: String in ["right_diagonal", "left_reverse"]:
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
	_check(tip != null, context + ": actual imported blade tip must exist")
	if tip == null: return
	var start := _sample(player, tip, stowed)
	var accepted := player.begin_sword_attack(variant)
	_check(bool(accepted.accepted), context + ": real begin must accept the attack")
	if not bool(accepted.accepted): return
	_check(is_equal_approx(player.get_melee_hit_time(), 0.145) and is_equal_approx(player.get_melee_active_duration(), 0.30), context + ": both stances must retain the coordinated combat clock")
	var elapsed := 0.0
	var spent_count := 0
	var expected_charge := 0.0
	var expected_cost := 0.0
	var windup_drift := 0.0
	var windup_angle := 0.0
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
		if player.combat_state == DungeonPlayer.CombatState.ACTIVE:
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
	_check(windup_drift < 0.001 and windup_angle < 0.06, context + ": waiting must keep the actual blade and hands at the clicked pose without an extra raise")
	_check(entry_drift < 0.001 and entry_angle < 0.06, context + ": ACTIVE zero must continue the actual held pose")
	_check(rejoin_seen and contact_seen and preserved_samples > 10 and source_position_error < 0.00003 and source_angle_error < 0.06, context + ": the authored track must be restored at 100ms, including exact 145ms contact and all following active/recovery poses")
	_check(finished and spent_count == 1 and is_equal_approx(player.stamina, player.MAX_STAMINA - expected_cost), context + ": the complete real attack must return READY with exactly one existing stamina cost")
	print("DIRECT ENTRY ", context, " windup_mm=", windup_drift * 1000.0, " entry_mm=", entry_drift * 1000.0, " authored_mm=", source_position_error * 1000.0, " authored_deg=", source_angle_error, " charge=", expected_charge, " spends=", spent_count)


func _sample(player: DungeonPlayer, tip: Node3D, stowed: bool) -> Dictionary:
	var snapshot := player.get_first_person_motion_snapshot()
	var points: Array[Vector3] = [player.camera.to_local(tip.global_position), player.camera.to_local(player.weapon_arm.global_position)]
	var arm: Dictionary = snapshot.joint_landmarks.get("sword", {})
	for joint: String in ["shoulder", "elbow", "wrist"]:
		if arm.has(joint): points.append(player.camera.to_local(arm[joint]))
	if stowed: points.append(player.camera.to_local(player.sword_support_arm.global_position))
	return {"pose": player.weapon_pivot.transform, "points": points}


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
	print("SWORD DIRECT ENTRY %s: actual clicked pose, release/charge/cost clocks, unchanged contact/follow-through and expedition preservation; target damage is covered by sword_attack_variants" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
