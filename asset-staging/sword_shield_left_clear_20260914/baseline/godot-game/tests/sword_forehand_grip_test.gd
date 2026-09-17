extends SceneTree
## Drive real clicks against production clips, then compare forehand ACTIVE
## geometry with an independently calculated camera-X mirror of reverse.
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const INVENTORY_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const SUPPORT := preload("res://scripts/sword_shield_arm_visual.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const REFERENCE := preload("res://scripts/reference_sword_motion.gd")
const STEP := 1.0 / 60.0
const ENTRY_BOUNDARY_EPSILON := 0.000001
const MODEL_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const SOURCE_PATHS := [
	"res://assets/animations/reference_sword_motion/motion_manifest.json",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/sword_shield/left_arm.glb",
	"res://assets/3d/player/sword_shield/right_arm.glb",
]
const OPTIONAL_BASELINE := "../asset-staging/sword_shield_hold_reverse_finish_20260914/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var saved := ExpeditionSession.capture_snapshot()
	var inventory := saved.get("inventory") as ExpeditionInventory
	var contents := INVENTORY_PREVIEW.inventory_fingerprint(inventory)
	var cursor := Input.mouse_mode
	var was_paused := paused
	var muted := AudioServer.is_bus_mute(0)
	var sources := _source_hashes()
	_check(sources[SOURCE_PATHS[1]] == MODEL_SHA256, "The exact original sword/glove GLB must be retained.")
	_check_source_preservation()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "Grip-direction fixtures must not replace an existing test-room session.")
	if sandbox.active:
		_finish()
		return
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	paused = false
	for stowed in [false, true]:
		var actual := _fixture()
		await physics_frame
		var player: DungeonPlayer = actual.player
		if stowed:
			_check(bool(player.request_primary_weapon().accepted), "The two-hand fixture must use the real shield-stow request.")
			for frame in 72: _tick(player, STEP)
		_check(player._has_shield_equipped() == not stowed and player._sword_support_requested() == stowed, "The real player must establish the requested equipment stance.")
		for variant: String in ["right_diagonal", "left_reverse", "overhead"]:
			var holds: Array = [0.0, 0.45]
			for hold: float in holds: _test_attack(player, variant, hold, stowed)
		_test_handoffs(actual, stowed)
		(actual.viewport as SubViewport).queue_free()
		await process_frame
	await _test_f2()
	sandbox.finish()
	paused = was_paused
	Input.mouse_mode = cursor
	AudioServer.set_bus_mute(0, muted)
	_check(_source_hashes() == sources, "Actual attacks and interruption tests must not alter motion or original model bytes.")
	_check(ExpeditionSession.capture_snapshot() == saved and INVENTORY_PREVIEW.inventory_fingerprint(inventory) == contents and Input.mouse_mode == cursor and not sandbox.active, "All fixtures must restore the original expedition, inventory and cursor.")
	_finish()


func _fixture() -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.bind_inventory(inventory)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	var chest := DungeonLootChest.new().configure("파지 방향 시험 상자", [{"id": "linen_bandage", "quantity": 1}])
	stage.add_child(chest)
	var fixture := {"viewport": viewport, "stage": stage, "inventory": inventory, "player": player, "chest": chest}
	_check(PREVIEW.configure_pose(fixture, "idle"), "Production equipment setup must load the real sword and hands.")
	player.set_torch_enabled(false)
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player._pitch = 0.0
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	_check(viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "The actual-player fixture must not sample hardware input.")
	_prepare(player)
	return fixture


func _prepare(player: DungeonPlayer) -> void:
	player.cancel_sword_attack()
	player.reset_reference_movement_motion()
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player.velocity = Vector3.ZERO
	player._motion_speed = 0.0
	player._motion_clock = 0.0
	player._motion_look_sway = Vector2.ZERO
	player._motion_previous_look = Vector2(player.rotation.y, player._pitch)
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._camera_shake = 0.0
	player._update_viewmodel(0.2)
	player._motion_clock = 0.0
	player._update_viewmodel(0.0)


func _test_attack(player: DungeonPlayer, variant: String, hold: float, stowed: bool) -> void:
	var context := "%s/%s/hold=%.2f" % ["two_hand" if stowed else "shield", variant, hold]
	_prepare(player)
	var held := player.weapon_pivot.transform
	var held_shield := player.shield_pivot.transform
	var attack := player.begin_sword_attack(variant)
	_check(bool(attack.accepted), context + ": the actual production attack must begin.")
	if not bool(attack.accepted): return
	var minimum := 0.0 if variant == "right_diagonal" else 0.22
	_check(player._sword_attack_coordinated and player._sword_direct_entry and is_equal_approx(player._sword_minimum_windup_seconds(), minimum), context + ": forehand must release immediately while the other cuts retain .22s.")
	_check(is_equal_approx(player._sword_direct_entry_duration(), 0.10) and is_equal_approx(player.get_melee_hit_time(), 0.145) and is_equal_approx(player.get_melee_active_duration(), 0.30), context + ": all cuts must share 100ms entry and the unchanged contact/active clocks.")
	player._update_viewmodel(0.0)
	_check(_near_pose(player.weapon_pivot.transform, held), context + ": begin at zero must preserve the actual held sword.")
	var elapsed := 0.0
	var spent := 0
	var expected_cost := 0.0
	var saw_contact := false
	var saw_rejoin := false
	var before_entry_boundary_seen := false
	var after_entry_boundary_seen := false
	var before_entry_pose := Transform3D.IDENTITY
	var saw_active := false
	var completed := false
	var mirror_samples := 0
	var maximum_grip_error := 0.0
	var maximum_axis_error := 0.0
	for frame in 180:
		if elapsed >= hold - 0.0000001: player.attack_release_requested = true
		var delta := STEP
		if elapsed < hold - 0.0000001: delta = minf(delta, hold - elapsed)
		if player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			for checkpoint: float in [0.10 - ENTRY_BOUNDARY_EPSILON, 0.10, 0.10 + ENTRY_BOUNDARY_EPSILON, 0.145, 0.30]:
				var remaining := checkpoint - player.state_time
				if remaining > 0.0000001: delta = minf(delta, remaining)
		var previous_state := player.combat_state
		var previous_time := player.state_time
		var previous_pose := player.weapon_pivot.transform
		var previous_shield := player.shield_pivot.transform
		var previous_stamina := player.stamina
		var released := player.attack_release_requested
		_tick(player, delta)
		elapsed += delta
		var pose := player.weapon_pivot.transform
		if player.stamina < previous_stamina - 0.000001: spent += 1
		_check_geometry(player, stowed, context)
		if not stowed and player.combat_state in [DungeonPlayer.CombatState.WINDUP, DungeonPlayer.CombatState.ACTIVE, DungeonPlayer.CombatState.RECOVERY]:
			_check(player.shield_pivot.is_visible_in_tree() and _near_pose(player.shield_pivot.transform, held_shield), context + ": every charge/strike/recovery frame must keep the shield at its captured carried pose.")
			_check(not player.blocking and is_zero_approx(player.block_time), context + ": retaining the carried shield must not silently enable damage blocking or just guard.")
		if previous_state == DungeonPlayer.CombatState.WINDUP and released and variant == "right_diagonal":
			_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and is_zero_approx(player.state_time), context + ": forehand release must commit on the very next combat tick.")
		if player.combat_state == DungeonPlayer.CombatState.WINDUP:
			_check(_near_pose(pose, held), context + ": held input must keep the captured sword pose.")
			_check(is_equal_approx(player.stamina, player.MAX_STAMINA) and is_equal_approx(player.attack_charge, clampf(player.state_time - 0.24, 0.0, 1.0)), context + ": waiting must preserve charge math and spend nothing.")
			if variant == "right_diagonal":
				_check(_near_pose(player.shield_pivot.transform, held_shield), context + ": forehand charge must retain the captured shield.")
		if elapsed < hold - 0.0000001:
			_check(player.combat_state == DungeonPlayer.CombatState.WINDUP, context + ": held input must not commit before release.")
		if previous_state == DungeonPlayer.CombatState.WINDUP and player.combat_state == DungeonPlayer.CombatState.ACTIVE:
			saw_active = true
			_check(is_zero_approx(player.state_time) and _near_pose(previous_pose, pose), context + ": ACTIVE zero must retain the actual held pose.")
			_check(elapsed >= maxf(minimum, hold) and elapsed <= maxf(minimum, hold) + STEP + 0.000001, context + ": release must respect the independent variant-specific minimum.")
			var expected_charge := clampf(previous_time + delta - 0.24, 0.0, 1.0)
			expected_cost = player.get_melee_stamina_cost(expected_charge)
			_check(is_equal_approx(player.attack_charge, expected_charge) and is_equal_approx(previous_stamina - player.stamina, expected_cost), context + ": commit must preserve charge and the single existing cost.")
			if variant == "right_diagonal":
				_check(_near_pose(previous_shield, player.shield_pivot.transform), context + ": immediate ACTIVE zero must retain the captured shield without a jump.")
		var phase := str(DungeonPlayer.CombatState.keys()[player.combat_state]).to_lower()
		if phase == "active":
			# Nominal .10 can be 0.099999999... after repeated ticks. Verify
			# strict ownership on both sides without overwriting state_time.
			if absf(player.state_time - (0.10 - ENTRY_BOUNDARY_EPSILON)) < 0.0000001:
				before_entry_boundary_seen = true
				before_entry_pose = pose
				_check(player._uses_direct_sword_entry(phase), context + ": the sample just before 100ms must retain direct entry.")
			if absf(player.state_time - (0.10 + ENTRY_BOUNDARY_EPSILON)) < 0.0000001:
				after_entry_boundary_seen = true
				_check(not player._uses_direct_sword_entry(phase), context + ": the sample just after 100ms must use the authored pose.")
				_check(before_entry_boundary_seen and pose.origin.distance_to(before_entry_pose.origin) < 0.0001 and pose.basis.get_rotation_quaternion().angle_to(before_entry_pose.basis.get_rotation_quaternion()) < 0.001, context + ": actual ticks must cross the shared entry boundary without a sword-pose jump.")
		if (phase == "active" and player.state_time >= 0.10 - 0.0000001) or phase == "recovery":
			var authored := REFERENCE.retimed_attack(phase, player.state_time, player.attack_charge, variant, true)
			# Remove only the known idle breathing offset in this stationary,
			# fully equipped fixture. The real combat and arm paths keep running.
			var breathing: Vector3 = MOTION.locomotion(player._motion_clock, 0.0, 0.0, true).position
			var unoffset := pose
			unoffset.origin -= breathing
			_check(_near_pose(unoffset, authored), context + ": from 100ms through recovery the displayed sword must use its raw authored pose.")
			if phase == "active":
				saw_rejoin = saw_rejoin or absf(player.state_time - 0.10) < 0.000001
				saw_contact = saw_contact or absf(player.state_time - 0.145) < 0.000001
				if variant == "right_diagonal" and player.state_time <= 0.145 + 0.0000001:
					# Proper X reflection: world mirror M has det -1, and local
					# X sign reversal supplies the second -1 without mirroring
					# the original right-hand mesh or changing its scale.
					var reverse := REFERENCE.retimed_attack("active", player.state_time, player.attack_charge, "left_reverse", true)
					var mirrored_basis := Basis(-_mirror_x(reverse.basis.x), _mirror_x(reverse.basis.y), _mirror_x(reverse.basis.z))
					var mirrored_grip := _mirror_x(reverse * ARM.GRIP_CENTER)
					maximum_grip_error = maxf(maximum_grip_error, (_actual_grip(player) - breathing).distance_to(mirrored_grip))
					maximum_axis_error = maxf(maximum_axis_error, maxf(unoffset.basis.x.distance_to(mirrored_basis.x), maxf(unoffset.basis.y.distance_to(mirrored_basis.y), unoffset.basis.z.distance_to(mirrored_basis.z))))
					_check(absf(unoffset.basis.determinant() - 1.0) < 0.00001, context + ": the reflected source must remain a proper rotation with no negative scale.")
					mirror_samples += 1
		if saw_active and phase == "ready" and player.state_time > 0.10 + ENTRY_BOUNDARY_EPSILON:
			var idle := REFERENCE.sample("idle", player._motion_clock)
			# The authored locomotion track suppresses generic breathing in
			# READY; after the handoff, speed zero uses authored idle alone.
			_check(not player._reference_pose_handoff_active and _near_pose(pose, idle), context + ": completed recovery and READY handoff must return to the original idle pose.")
			if not stowed:
				_check(_near_pose(player.shield_pivot.transform, REFERENCE.sample("idle", player._motion_clock, "shield")), context + ": the shield must resume normal idle after the attack finishes.")
			completed = true
			break
	_check(completed and saw_contact and saw_rejoin and spent == 1 and is_equal_approx(player.stamina, player.MAX_STAMINA - expected_cost), context + ": the real click must join at 100ms, reach 145ms contact, spend once and finish READY.")
	_check(before_entry_boundary_seen and after_entry_boundary_seen, context + ": the real ticks must sample both sides of the 100ms entry boundary.")
	if variant == "right_diagonal":
		_check(mirror_samples > 3 and maximum_grip_error < 0.00005 and maximum_axis_error < 0.00005, context + ": post-entry samples through contact must match the same-phase reverse grip and basis under proper camera-X reflection.")
	print("FOREHAND MIRROR ", context, " active_samples=", mirror_samples, " grip_mm=", maximum_grip_error * 1000.0, " axis_error=", maximum_axis_error, " spends=", spent)


func _mirror_x(point: Vector3) -> Vector3:
	return Vector3(-point.x, point.y, point.z)


func _check_source_preservation() -> void:
	_check(REFERENCE.clip_metadata("right_diagonal").timing == REFERENCE.clip_metadata("left_reverse").timing, "Forehand and reverse must use identical source timing for same-phase reflection.")
	var baseline := ProjectSettings.globalize_path("res://").path_join(OPTIONAL_BASELINE).simplify_path()
	if not FileAccess.file_exists(baseline): return
	var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline))
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATHS[0]))
	_check(previous is Dictionary and current is Dictionary, "The optional immutable baseline and current manifest must decode.")
	if not previous is Dictionary or not current is Dictionary: return
	var before_clips: Dictionary = previous.get("clips", {})
	var after_clips: Dictionary = current.get("clips", {})
	_check(before_clips.size() == after_clips.size() and after_clips.has("right_diagonal"), "Changing forehand must retain the complete original clip set.")
	for clip: String in before_clips:
		if clip == "left_reverse": continue
		_check(after_clips.has(clip) and after_clips[clip] == before_clips[clip], "Only the reverse finish may change; preserve the other clips exactly: " + clip)
	_check(current.get("source") == previous.get("source") and current.get("coordinate_system") == previous.get("coordinate_system"), "The new clip must preserve original model provenance and coordinate semantics.")


func _advance_to_active(player: DungeonPlayer, elapsed: float) -> void:
	_prepare(player)
	_check(bool(player.begin_sword_attack("right_diagonal").accepted), "Interruption must begin a real forehand attack.")
	player.attack_release_requested = true
	for frame in 90:
		if player.combat_state == DungeonPlayer.CombatState.ACTIVE: break
		_tick(player, STEP)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "Interruption fixture must reach ACTIVE through the real combat clock.")
	while player.combat_state == DungeonPlayer.CombatState.ACTIVE and player.state_time < elapsed - 0.0000001:
		_tick(player, minf(STEP, elapsed - player.state_time))


func _test_handoffs(fixture: Dictionary, stowed: bool) -> void:
	var player: DungeonPlayer = fixture.player
	for elapsed: float in [0.075, 0.145]:
		for guard in [false, true]:
			_advance_to_active(player, elapsed)
			var pose := player.weapon_pivot.transform
			var arm := _actual_arm(player)
			player.cancel_sword_attack()
			player.blocking = guard
			player._update_viewmodel(0.0)
			_check(_near_pose(pose, player.weapon_pivot.transform) and _arm_equal(arm, _actual_arm(player)), "Cancel/guard handoff at zero time must retain the actual authored sword and wrist.")
			_check_geometry(player, stowed, "cancel/guard handoff")
		_advance_to_active(player, elapsed)
		var enemy := DungeonEnemy.new()
		enemy.configure("파지 방향 실제 검격", 2000, 12, 0, Color.GRAY)
		enemy.position = Vector3(12, 1, -12)
		(fixture.stage as Node3D).add_child(enemy)
		enemy.set_physics_process(false)
		enemy.setup(player, null, fixture.stage)
		enemy._set_state(DungeonEnemy.AIState.ACTIVE)
		var enemy_proxy := enemy.get_sword_clash_proxy()
		var player_proxy := player.get_sword_clash_proxy()
		enemy.sword_blade.global_position += (player_proxy.center as Vector3) - (enemy_proxy.center as Vector3)
		var pose := player.weapon_pivot.transform
		var arm := _actual_arm(player)
		var clashed := player.try_sword_clash(enemy)
		_check(clashed and player._sword_clash_recovering, "Actual overlapping blade geometry must begin the captured clash recovery.")
		if clashed:
			player._update_viewmodel(0.0)
			_check(_near_pose(pose, player.weapon_pivot.transform) and _arm_equal(arm, _actual_arm(player)), "Clash recovery zero must preserve the actual captured sword and arm pose.")
			_check_geometry(player, stowed, "clash handoff")
		enemy.queue_free()


func _test_f2() -> void:
	var room := (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	room.set_process(false)
	room.set_physics_process(false)
	room.run_feature("motion_sword_run")
	var player: DungeonPlayer = room.player
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.set_torch_enabled(false)
	_advance_to_active(player, 0.145)
	var visible := player.weapon_pivot.transform
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.physical_keycode = KEY_F2
	key.pressed = true
	room._unhandled_input(key)
	_check(paused and room.panel_open and player.combat_state == DungeonPlayer.CombatState.READY, "Real F2 must keep its existing attack-cancellation and pause contract.")
	_check(_near_pose(visible, player.weapon_pivot.transform), "Opening F2 must preserve the visible authored sword pose.")
	var frozen := player.get_first_person_motion_snapshot()
	player.advance_combat_state(0.4)
	player._update_viewmodel(0.4)
	_check(player.get_first_person_motion_snapshot() == frozen and _near_pose(visible, player.weapon_pivot.transform), "F2 must freeze the visible sword, hands and motion clocks after cancellation.")
	room._unhandled_input(key)
	_check(not paused and not room.panel_open, "Closing F2 must resume the same test room.")
	player._update_viewmodel(0.0)
	var resumed := player.weapon_pivot.transform
	player._update_viewmodel(0.0)
	_check(_near_pose(resumed, player.weapon_pivot.transform), "Repeated zero-time READY updates after F2 must preserve the same resumed pose.")
	_check_geometry(player, player._sword_support_requested(), "F2 resume")
	room.queue_free()
	await process_frame


func _tick(player: DungeonPlayer, delta: float) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, false)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _actual_grip(player: DungeonPlayer) -> Vector3:
	var marker := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
	return player.camera.to_local(marker.global_position)


func _actual_arm(player: DungeonPlayer) -> Dictionary:
	var upper := player.weapon_arm.get_node("RightArm_UpperArm_Surface") as Node3D
	var forearm := player.weapon_arm.get_node("RightArm_Forearm_Surface") as Node3D
	return {"shoulder": player.camera.to_local(upper.to_global(ARM.REST_SHOULDER)), "elbow": player.camera.to_local(upper.to_global(ARM.REST_ELBOW)), "wrist": player.camera.to_local(forearm.to_global(ARM.REST_WRIST)), "forearm_elbow": player.camera.to_local(forearm.to_global(ARM.REST_ELBOW))}


func _check_geometry(player: DungeonPlayer, stowed: bool, context: String) -> void:
	var pose := player.weapon_pivot.transform
	_check(pose.origin.is_finite() and pose.basis.is_finite() and absf(pose.basis.determinant() - 1.0) < 0.00001, context + ": the actual sword must remain a finite proper rotation.")
	var actual := _actual_arm(player)
	_check(absf((actual.shoulder as Vector3).distance_to(actual.elbow) - ARM.REST_UPPER_LENGTH) < 0.00005 and absf((actual.elbow as Vector3).distance_to(actual.wrist) - ARM.REST_FOREARM_LENGTH) < 0.00005, context + ": actual sleeve segments must retain their original lengths.")
	_check((actual.elbow as Vector3).distance_to(actual.forearm_elbow) < 0.00005 and (actual.wrist as Vector3).distance_to(pose * ARM.REST_WRIST) < 0.00005, context + ": the fitted original sleeve must remain connected at elbow and actual authored wrist.")
	var hand_grip := player.camera.to_local(player.weapon_arm.to_global(ARM.GRIP_CENTER))
	_check(hand_grip.distance_to(_actual_grip(player)) < 0.00002, context + ": the original right hand must stay attached to the actual sword grip.")
	if stowed:
		var support_grip := player.sword_support_arm.to_global(SUPPORT.GRIP_CENTER)
		_check(player.sword_support_arm.visible and support_grip.distance_to(player.weapon_pivot.to_global(player.SWORD_SUPPORT_GRIP)) < 0.00005, context + ": the actual left hand must retain its lower-handle contact throughout the authored cut.")


func _arm_equal(a: Dictionary, b: Dictionary) -> bool:
	for joint: String in ["shoulder", "elbow", "wrist"]:
		if (a[joint] as Vector3).distance_to(b[joint]) >= 0.00005: return false
	return true


func _near_pose(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.00005 and a.basis.is_equal_approx(b.basis)


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in SOURCE_PATHS: hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)


func _finish() -> void:
	for failure in failures: push_error(failure)
	print("SWORD FOREHAND GRIP %s: real clicks and held charge; shared 100ms entry; same-phase reverse camera-X reflection; original clips/assets and fitted two-hand contacts; clash/cancel/F2 isolation; aesthetic quality not evaluated" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
