extends SceneTree
## Compare two real players with identical inputs and production assets. Only
## the comparison subclass omits the final grip-direction correction; it does
## not undo the tested output or replace the authored clips with a fixture.
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const INVENTORY_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const SUPPORT := preload("res://scripts/sword_shield_arm_visual.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const STEP := 1.0 / 60.0
const MODEL_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const SOURCE_PATHS := [
	"res://assets/animations/reference_sword_motion/motion_manifest.json",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/sword_shield/left_arm.glb",
	"res://assets/3d/player/sword_shield/right_arm.glb",
]
const OPTIONAL_BASELINE := "../asset-staging/sword_forehand_grip_direction_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
var failures: Array[String] = []


class WithoutGripDirection:
	extends DungeonPlayer

	func _apply_forehand_grip_direction(pivot: Transform3D, _phase: String) -> Transform3D:
		return pivot


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
	var baseline := ProjectSettings.globalize_path("res://").path_join(OPTIONAL_BASELINE).simplify_path()
	if FileAccess.file_exists(baseline):
		_check(FileAccess.get_sha256(baseline) == sources[SOURCE_PATHS[0]], "Changing the held direction must preserve the entire prior motion manifest byte for byte.")
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "Grip-direction fixtures must not replace an existing test-room session.")
	if sandbox.active:
		_finish()
		return
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	paused = false
	for stowed in [false, true]:
		var actual := _fixture(false)
		var comparison := _fixture(true)
		await physics_frame
		for fixture: Dictionary in [actual, comparison]:
			var player: DungeonPlayer = fixture.player
			if stowed:
				_check(bool(player.request_primary_weapon().accepted), "The two-hand fixture must use the real shield-stow request.")
				for frame in 72: _tick(player, STEP)
			_check(player._has_shield_equipped() == not stowed and player._sword_support_requested() == stowed, "Both comparison players must establish the requested real equipment stance.")
		for variant: String in ["right_diagonal", "left_reverse", "overhead"]:
			var holds: Array = [0.0, 0.45] if variant == "right_diagonal" else [0.0]
			for hold: float in holds: _test_pair(actual.player, comparison.player, variant, hold, stowed)
		_test_handoffs(actual, stowed)
		(actual.viewport as SubViewport).queue_free()
		(comparison.viewport as SubViewport).queue_free()
		await process_frame
	await _test_f2()
	sandbox.finish()
	paused = was_paused
	Input.mouse_mode = cursor
	AudioServer.set_bus_mute(0, muted)
	_check(_source_hashes() == sources, "Comparisons and interruption tests must not alter motion or original model bytes.")
	_check(ExpeditionSession.capture_snapshot() == saved and INVENTORY_PREVIEW.inventory_fingerprint(inventory) == contents and Input.mouse_mode == cursor and not sandbox.active, "All fixtures must restore the original expedition, inventory and cursor.")
	_finish()


func _fixture(without_direction: bool) -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	var player: DungeonPlayer = WithoutGripDirection.new() if without_direction else DungeonPlayer.new()
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


func _test_pair(actual: DungeonPlayer, baseline: DungeonPlayer, variant: String, hold: float, stowed: bool) -> void:
	var context := "%s/%s/hold=%.2f" % ["two_hand" if stowed else "shield", variant, hold]
	for player: DungeonPlayer in [actual, baseline]:
		_prepare(player)
		_check(bool(player.begin_sword_attack(variant).accepted), context + ": both real attacks must begin.")
		player._update_viewmodel(0.0)
	var elapsed := 0.0
	var grip_error := 0.0
	var plane_error := 0.0
	var previous_angle := 0.0
	var accumulated_angle := 0.0
	var spent := 0
	var saw_contact := false
	var saw_active := false
	var saw_ready := false
	var ready_residual := 0.0
	var completed := false
	for frame in 180:
		if elapsed >= hold - 0.0000001:
			actual.attack_release_requested = true
			baseline.attack_release_requested = true
		var delta := STEP
		if elapsed < hold - 0.0000001: delta = minf(delta, hold - elapsed)
		if actual.combat_state == DungeonPlayer.CombatState.ACTIVE:
			for checkpoint: float in [0.145, 0.30]:
				var remaining := checkpoint - actual.state_time
				if remaining > 0.0000001: delta = minf(delta, remaining)
		var previous_state := actual.combat_state
		var previous_pose := actual.weapon_pivot.transform
		var previous_stamina := actual.stamina
		_tick(actual, delta)
		_tick(baseline, delta)
		elapsed += delta
		if actual.stamina < previous_stamina - 0.000001: spent += 1
		_check(actual.combat_state == baseline.combat_state and is_equal_approx(actual.state_time, baseline.state_time) and is_equal_approx(actual.attack_charge, baseline.attack_charge) and is_equal_approx(actual.stamina, baseline.stamina), context + ": correction must preserve the full real combat clock, charge and stamina cost.")
		var pose := actual.weapon_pivot.transform
		var original := baseline.weapon_pivot.transform
		grip_error = maxf(grip_error, _actual_grip(actual).distance_to(_actual_grip(baseline)))
		plane_error = maxf(plane_error, pose.basis.z.distance_to(original.basis.z))
		_check_geometry(actual, stowed, context)
		if variant == "right_diagonal":
			var relative := original.basis.inverse() * pose.basis
			var current_angle := atan2(relative.x.y, relative.x.x)
			var advance := wrapf(current_angle - previous_angle, -PI, PI)
			_check(advance >= -0.003, context + ": actual correction must continue in the same rotational direction during recovery.")
			accumulated_angle += advance
			previous_angle = current_angle
		else:
			_check(_near_pose(pose, original), context + ": reverse and overhead must retain their complete visible source paths.")
		if actual.combat_state == DungeonPlayer.CombatState.WINDUP:
			_check(_near_pose(pose, original), context + ": WINDUP must retain the original held direction.")
		if previous_state == DungeonPlayer.CombatState.WINDUP and actual.combat_state == DungeonPlayer.CombatState.ACTIVE:
			saw_active = true
			_check(is_zero_approx(actual.state_time) and _near_pose(previous_pose, pose), context + ": ACTIVE zero must retain the actual held pose without an extra turn.")
		if actual.combat_state == DungeonPlayer.CombatState.ACTIVE and actual.state_time >= 0.145 - 0.0000001:
			if variant == "right_diagonal":
				_check(pose.basis.x.distance_to(-original.basis.x) < 0.00005 and pose.basis.y.distance_to(-original.basis.y) < 0.00005 and pose.basis.z.distance_to(original.basis.z) < 0.00005, context + ": contact through ACTIVE end must reverse width/length axes while retaining the actual blade plane.")
			if absf(actual.state_time - 0.145) < 0.000001:
				saw_contact = true
				if variant == "right_diagonal":
					_check(pose.basis.y.x > 0.0 and original.basis.y.x < 0.0, context + ": the actual contact blade must point right while its unchanged baseline points left.")
		if saw_active and actual.combat_state == DungeonPlayer.CombatState.READY:
			if not saw_ready:
				saw_ready = true
				# READY first captures the last displayed RECOVERY sample and
				# blends it to locomotion over the existing 100ms handoff. The
				# combat transition is not the end of that visible interpolation.
				var relative := original.basis.inverse() * pose.basis
				ready_residual = absf(atan2(relative.x.y, relative.x.x))
				var maximum_residual := deg_to_rad(0.06)
				var maximum_origin_error := 2.0 * ARM.GRIP_CENTER.length() * sin(maximum_residual * 0.5) + 0.00005
				_check(ready_residual <= maximum_residual and pose.origin.distance_to(original.origin) <= maximum_origin_error, context + ": first READY may retain only a sub-frame recovery rotation around the unchanged grip.")
			if actual.state_time >= 0.10 - 0.0000001:
				completed = true
				_check(not actual._reference_pose_handoff_active and not baseline._reference_pose_handoff_active and _near_pose(pose, original), context + ": after the existing READY handoff, recovery must finish at the exact original idle direction.")
				break
	_check(grip_error < 0.00005 and plane_error < 0.00005, context + ": the complete actual frame sequence must preserve the baseline grip trajectory and blade-plane normal.")
	_check(completed and saw_contact and spent == 1, context + ": the real attack must hit its existing 145ms contact, spend stamina once and finish READY.")
	if variant == "right_diagonal":
		_check(absf(accumulated_angle - TAU) < 0.005, context + ": actual preparation/attack/recovery must complete one continuous local turn and return to idle.")
	print("FOREHAND GRIP ", context, " grip_mm=", grip_error * 1000.0, " plane_error=", plane_error, " first_ready_residual_degrees=", rad_to_deg(ready_residual), " total_turn_degrees=", rad_to_deg(accumulated_angle))


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
			_check(_near_pose(pose, player.weapon_pivot.transform) and _arm_equal(arm, _actual_arm(player)), "Cancel/guard handoff at zero time must retain the actual corrected sword and wrist, without applying the turn twice.")
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
			_check(_near_pose(pose, player.weapon_pivot.transform) and _arm_equal(arm, _actual_arm(player)), "Clash recovery zero must preserve its already-corrected captured pose without a duplicate rotation.")
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
	_check(_near_pose(visible, player.weapon_pivot.transform), "Opening F2 must not rotate the visible corrected sword again.")
	var frozen := player.get_first_person_motion_snapshot()
	player.advance_combat_state(0.4)
	player._update_viewmodel(0.4)
	_check(player.get_first_person_motion_snapshot() == frozen and _near_pose(visible, player.weapon_pivot.transform), "F2 must freeze the visible sword, hands and motion clocks after cancellation.")
	room._unhandled_input(key)
	_check(not paused and not room.panel_open, "Closing F2 must resume the same test room.")
	player._update_viewmodel(0.0)
	var resumed := player.weapon_pivot.transform
	player._update_viewmodel(0.0)
	_check(_near_pose(resumed, player.weapon_pivot.transform), "Repeated READY updates after F2 must not accumulate the forehand correction.")
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
	_check((actual.elbow as Vector3).distance_to(actual.forearm_elbow) < 0.00005 and (actual.wrist as Vector3).distance_to(pose * ARM.REST_WRIST) < 0.00005, context + ": the fitted original sleeve must remain connected at elbow and actual corrected wrist.")
	var hand_grip := player.camera.to_local(player.weapon_arm.to_global(ARM.GRIP_CENTER))
	_check(hand_grip.distance_to(_actual_grip(player)) < 0.00002, context + ": the original right hand must stay attached to the actual sword grip.")
	if stowed:
		var support_grip := player.sword_support_arm.to_global(SUPPORT.GRIP_CENTER)
		_check(player.sword_support_arm.visible and support_grip.distance_to(player.weapon_pivot.to_global(player.SWORD_SUPPORT_GRIP)) < 0.00005, context + ": the actual left hand must retain its lower-handle contact after the direction change.")


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
	print("SWORD FOREHAND GRIP %s: paired actual players; unchanged grip/clocks/assets; reversed contact axes; fitted two-hand contacts; clash/cancel/F2 isolation; aesthetic quality not evaluated" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
