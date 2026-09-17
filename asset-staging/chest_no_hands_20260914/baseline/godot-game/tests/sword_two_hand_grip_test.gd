extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const FIDELITY := preload("res://tests/sword_long_grip_test.gd")
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	await process_frame
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._update_viewmodel(0.4)
	_check(bool(player.request_primary_weapon().accepted), "actual shield stow must start the two-hand grip")
	player._update_viewmodel(1.1)
	_check(player._shield_stowed and not player.shield_pivot.visible and player._sword_support_progress() == 1.0 and player.sword_support_arm.visible, "actual stow must finish with the support hand on the lower hilt")
	_check(FileAccess.get_sha256(FIDELITY.SOURCE_PATH) == player.SWORD_LONG_GRIP.SOURCE_SHA256, "original sword and hand GLB bytes must remain untouched")
	var samples: Array[Dictionary] = []
	for variant: String in player.SWORD_ATTACK_VARIANTS:
		player.stamina = player.MAX_STAMINA
		_check(bool(player.begin_sword_attack(variant).accepted), "actual two-hand attack must start: " + variant)
		for frame in range(115):
			if frame == 27: player.attack_release_requested = true
			player.advance_combat_state(1.0 / 60.0, false)
			player._update_viewmodel(1.0 / 60.0)
			player._resolve_active_attack()
			_check_support_connection(player, "%s frame %d" % [variant, frame])
			if frame % 10 == 0 or frame in [27, 36, 45, 55]:
				samples.append(_contact_snapshot(player, variant, frame))
		_check(player.combat_state == DungeonPlayer.CombatState.READY and player._shield_stowed and player.sword_support_arm.visible, "each real attack must return to the completed two-hand carry state: " + variant)
	# Compare the actual imported hand with its original geometry. This does
	# not treat the source thumb's existing penetration as a solved contact.
	failures.append_array(FIDELITY.audit_source_fidelity(player))
	# Optional authoring evidence; standalone regression never depends on an
	# asset-staging directory or writes outside the configured report path.
	var output := OS.get_environment("SWORD_TWO_HAND_CONTACT_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		_check(file != null, "requested contact report must be writable")
		if file != null:
			file.store_string(JSON.stringify({"samples": samples, "scope": "support_connection_and_original_source_fidelity"}, "\t"))
			file.close()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "two-hand contact validation must preserve expedition and cursor")
	for failure in failures: push_error(failure)
	print("SWORD TWO HAND GRIP %s: %d support diagnostics, three real cuts, original source fidelity and unchanged expedition" % ["PASS" if failures.is_empty() else "FAIL", samples.size()])
	quit(0 if failures.is_empty() else 1)


func _check_support_connection(player: DungeonPlayer, context: String) -> void:
	var snapshot := player.get_first_person_motion_snapshot()
	var support: Dictionary = snapshot.hand_contacts.get("sword_support", {})
	var joint: Dictionary = snapshot.joint_landmarks.get("sword_support", {})
	_check(player._shield_stowed and not player.shield_pivot.visible and player.sword_support_arm.visible, "two-hand attacks must retain the stowed shield and visible support hand: " + context)
	_check(not support.is_empty() and float(support.get("error", INF)) < 0.00001 and float(support.get("grip_error", INF)) < 0.00001, "actual support hand must stay connected to the lower sword grip: " + context)
	_check(absf(float(joint.get("forearm_length", 0.0)) - 0.26) < 0.0001 and absf(float(joint.get("upper_length", 0.0)) - 0.34) < 0.0001, "support arm segments must retain their existing lengths through every cut: " + context)

func _contact_snapshot(player: DungeonPlayer, variant: String, frame: int) -> Dictionary:
	var arm: Node3D = player.sword_support_arm
	var grip: Dictionary = arm.call("get_combat_grip_snapshot")
	var local := player.weapon_pivot.global_transform.affine_inverse() * arm.global_transform
	var patches: Dictionary = {}
	for patch: String in grip.contact_patch_specs:
		patches[patch] = _vec(local * (arm.call("_digit_pad", patch) as Vector3))
	var errors: Dictionary = {}
	for digit: String in grip.contacts: errors[digit] = grip.contacts[digit].error
	return {"variant": variant, "frame": frame, "phase": player.combat_state, "time": player.state_time, "patches": patches, "solver_errors": errors, "tension": grip.tension, "wrist_in_weapon": _vec(local.origin), "orientation": [_vec(local.basis.x), _vec(local.basis.y), _vec(local.basis.z)]}

func _vec(value: Vector3) -> Array[float]: return [value.x, value.y, value.z]

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

