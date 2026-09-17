extends SceneTree
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const FRAME_SECONDS := 1.0 / 60.0
const ATTACK_FRAMES := 115
const RELEASE_PROFILES := [
	{"name": "quick_click", "frame": 0},
	{"name": "hold_0_45s", "frame": 27},
]
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _check(ok: bool, message: String) -> void:
	if not ok and not failures.has(message): failures.append(message)


func _capture(stowed: bool, release_frame: int, profile: String) -> Array[Dictionary]:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var p: DungeonPlayer = fixture.player
	var bag: ExpeditionInventory = fixture.inventory
	var equipment := bag.equipment.duplicate(true)
	var equipment_data := bag.equipment_data.duplicate(true)
	p.set_physics_process(false)
	p.set_process_unhandled_input(false)
	await process_frame
	p._sword_draw_elapsed = p.SWORD_DRAW_DURATION
	p._update_viewmodel(0.4)
	if stowed:
		_check(bool(p.request_primary_weapon().accepted), profile + ": stow must start")
		p._update_viewmodel(1.1)
	_check(p.set_sword_attack_mode("cycle"), profile + ": the actual three-cut cycle must be selectable")
	p._motion_clock = 0.0
	p._update_viewmodel(0.2)
	var records: Array[Dictionary] = []
	for variant: String in p.SWORD_ATTACK_VARIANTS:
		var context := "%s %s %s" % [profile, "two_hands" if stowed else "shield", variant]
		p.stamina = p.MAX_STAMINA
		_check(p.get_next_sword_attack_variant() == variant, context + ": both stances must use the same three-cut cycle")
		var result := p.begin_sword_attack()
		_check(bool(result.accepted) and str(result.get("variant", "")) == variant, context + ": actual attack variant must match the cycle")
		_check(is_equal_approx(p.get_melee_hit_time(), 0.145) and is_equal_approx(p.get_melee_active_duration(), 0.30), context + ": shared motion must retain its real hit and active clocks")
		# Sample attack time zero as well as every subsequent frame. A quick
		# release reaches the normal combat clock before its first advance;
		# the held profile reaches the same release flag after 27/60 seconds.
		p._update_viewmodel(0.0)
		records.append(_sample(p, variant, -1))
		_check_stance(p, stowed, context)
		var active_seen := false
		var recovery_seen := false
		var release_sent := false
		for frame in ATTACK_FRAMES:
			if frame == release_frame:
				p.attack_release_requested = true
				release_sent = true
			p.advance_combat_state(FRAME_SECONDS, false)
			p._update_viewmodel(FRAME_SECONDS)
			p._resolve_active_attack()
			active_seen = active_seen or p.combat_state == p.CombatState.ACTIVE
			recovery_seen = recovery_seen or p.combat_state == p.CombatState.RECOVERY
			_check_stance(p, stowed, context)
			records.append(_sample(p, variant, frame))
		_check(release_sent and active_seen and recovery_seen and p.combat_state == p.CombatState.READY, context + ": the requested release must traverse active and recovery and finish in READY")
	_check(p.get_next_sword_attack_variant() == p.SWORD_ATTACK_VARIANTS[0], profile + ": cycle must wrap")
	if stowed:
		p.advance_combat_state(0.1, true)
		p._update_viewmodel(0.1)
		_check(p.blocking and not p._has_shield_equipped(), profile + ": two-handed guard remains a weapon guard")
	_check(bag.equipment == equipment and bag.equipment_data == equipment_data, profile + ": stance and attacks must preserve equipped items")
	viewport.queue_free()
	await process_frame
	return records


func _check_stance(p: DungeonPlayer, stowed: bool, context: String) -> void:
	var snapshot := p.get_first_person_motion_snapshot()
	if stowed:
		var support: Dictionary = snapshot.hand_contacts.get("sword_support", {})
		_check(float(support.get("grip_error", 1.0)) < 0.00001 and p.sword_support_arm.visible and p._left_hand_role() == "sword_support", context + ": left support hand must follow every cut")
		_check(not p.shield_pivot.visible and not p.shield_arm.visible and not p._has_shield_equipped(), context + ": animation sharing must not restore shield or shield defense")
	else:
		var shield_contact: Dictionary = snapshot.hand_contacts.get("shield", {})
		_check(float(shield_contact.get("error", 1.0)) < 0.00001 and p.shield_pivot.visible and p.shield_arm.visible and p._has_shield_equipped(), context + ": shield stance must retain its actual shield and hand contact")
		_check(not p.sword_support_arm.visible and p._left_hand_role() == "shield", context + ": shield stance must not switch the left hand to sword support")


func _sample(p: DungeonPlayer, variant: String, frame: int) -> Dictionary:
	return {
		"variant": variant,
		"frame": frame,
		"pose": p.weapon_pivot.transform,
		"blade_pose": p.camera.global_transform.affine_inverse() * p.sword_blade.global_transform,
		"phase": p.combat_state,
		"phase_time": p.state_time,
		"charge": p.attack_charge,
		"stamina": p.stamina,
	}


func _compare(shield: Array[Dictionary], two_hands: Array[Dictionary], profile: String) -> Dictionary:
	var position_error := 0.0
	var angle_error := 0.0
	var expected_samples := DungeonPlayer.SWORD_ATTACK_VARIANTS.size() * (ATTACK_FRAMES + 1)
	_check(shield.size() == expected_samples and two_hands.size() == expected_samples, profile + ": both stances must capture all three attacks from time zero through completion")
	for i in mini(shield.size(), two_hands.size()):
		var a: Dictionary = shield[i]
		var b: Dictionary = two_hands[i]
		_check(a.variant == b.variant and a.frame == b.frame, profile + ": every comparison must use the same cut and input-relative frame")
		for key: String in ["pose", "blade_pose"]:
			var a_pose: Transform3D = a[key]
			var b_pose: Transform3D = b[key]
			position_error = maxf(position_error, a_pose.origin.distance_to(b_pose.origin))
			angle_error = maxf(angle_error, a_pose.basis.get_rotation_quaternion().angle_to(b_pose.basis.get_rotation_quaternion()))
		_check(a.phase == b.phase and is_equal_approx(float(a.phase_time), float(b.phase_time)) and is_equal_approx(float(a.charge), float(b.charge)), profile + ": combat phase, time and charge must match at every frame")
		_check(is_equal_approx(float(a.stamina), float(b.stamina)), profile + ": actual attack stamina must match at every frame")
	_check(position_error < 0.0001 and angle_error < 0.001, profile + ": actual sword and blade trajectories must match across stances at every frame")
	return {"profile": profile, "samples_per_stance": shield.size(), "max_position_m": position_error, "max_angle_rad": angle_error}


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var results: Array[Dictionary] = []
	for profile: Dictionary in RELEASE_PROFILES:
		var shield := await _capture(false, int(profile.frame), str(profile.name))
		_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, str(profile.name) + ": shield fixture must preserve expedition and cursor")
		var two_hands := await _capture(true, int(profile.frame), str(profile.name))
		results.append(_compare(shield, two_hands, str(profile.name)))
		_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, str(profile.name) + ": two-hand fixture must preserve expedition and cursor")
	for message in failures: push_error(message)
	print("UNIFIED SWORD MOTION %s %s" % ["PASS" if failures.is_empty() else "FAIL", JSON.stringify(results)])
	quit(0 if failures.is_empty() else 1)
