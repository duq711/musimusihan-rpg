extends SceneTree
## Compare two real players with identical inputs and production assets. Only
## the comparison subclass omits the final grip-direction correction; it does
## not undo the tested output or replace the authored clips with a fixture.
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const INVENTORY_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const SUPPORT := preload("res://scripts/sword_shield_arm_visual.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const REFERENCE := preload("res://scripts/reference_sword_motion.gd")
const STEP := 1.0 / 60.0
const MODEL_SHA256 := "2b94cc385f837fe253552cd654cb1f665246f61cdee5227814d63049da9f22fb"
const SOURCE_PATHS := [
	"res://assets/animations/reference_sword_motion/motion_manifest.json",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/sword_shield/left_arm.glb",
	"res://assets/3d/player/sword_shield/right_arm.glb",
]
const OPTIONAL_BASELINE := "../asset-staging/sword_forehand_immediate_cut_20260913/baseline/godot-game/assets/animations/reference_sword_motion/motion_manifest.json"
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
	var held := actual.weapon_pivot.transform
	var held_shield := actual.shield_pivot.transform
	# The expected endpoint comes independently from the source contact key,
	# not from the correction helper or an inverse of its displayed result.
	var metadata := REFERENCE.clip_metadata(variant)
	var authored_contact := REFERENCE.sample(variant, float(metadata.timing.windup_seconds) + float(metadata.timing.hit_seconds))
	var contact_basis := Basis(-authored_contact.basis.x, -authored_contact.basis.y, authored_contact.basis.z)
	var shortest_entry_angle := _basis_distance(held.basis, contact_basis)
	var elapsed := 0.0
	var grip_error := 0.0
	var plane_error := 0.0
	var entry_path_angle := 0.0
	var entry_grips: Array[Vector3] = []
	var entry_grips_without_breathing: Array[Vector3] = []
	var entry_grip_line_errors := Vector2.ZERO
	var previous_entry_progress := 0.0
	var tail_previous_angle := PI
	var recovery_turn := 0.0
	var spent := 0
	var saw_contact := false
	var saw_active := false
	var saw_first_active_motion := false
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
		var previous_time := actual.state_time
		var previous_pose := actual.weapon_pivot.transform
		var previous_shield := actual.shield_pivot.transform
		var previous_grip := _actual_grip(actual)
		var previous_stamina := actual.stamina
		_tick(actual, delta)
		_tick(baseline, delta)
		elapsed += delta
		if actual.stamina < previous_stamina - 0.000001: spent += 1
		_check(actual.combat_state == baseline.combat_state and is_equal_approx(actual.state_time, baseline.state_time) and is_equal_approx(actual.attack_charge, baseline.attack_charge) and is_equal_approx(actual.stamina, baseline.stamina), context + ": correction must preserve the full real combat clock, charge and stamina cost.")
		var pose := actual.weapon_pivot.transform
		var original := baseline.weapon_pivot.transform
		var forehand_entry := variant == "right_diagonal" and actual.combat_state == DungeonPlayer.CombatState.ACTIVE and actual.state_time < 0.145 - 0.0000001
		if not forehand_entry:
			grip_error = maxf(grip_error, _actual_grip(actual).distance_to(_actual_grip(baseline)))
		_check(_near_pose(actual.shield_pivot.transform, baseline.shield_pivot.transform), context + ": changing sword direction must not alter the paired shield path.")
		_check_geometry(actual, stowed, context)
		if variant == "right_diagonal":
			# The previous full-ACTIVE local-Z spin is superseded: entry now
			# takes one shortest path from the held basis to fixed contact.
			# Its intermediate blade plane therefore need not equal raw source.
			if actual.combat_state == DungeonPlayer.CombatState.ACTIVE and actual.state_time <= 0.145 + 0.0000001:
				entry_grips.append(_actual_grip(actual))
				var from_start := _basis_distance(held.basis, pose.basis)
				var to_contact := _basis_distance(pose.basis, contact_basis)
				# Only breathing is active in this stationary fixture. Infer the
				# blend amount from the independently verified displayed rotation,
				# not the production entry helper or its progress calculation.
				_check(is_zero_approx(actual._motion_speed) and actual._motion_look_sway.is_zero_approx() and actual._motion_equip_elapsed >= MOTION.EQUIP_DURATION, context + ": breathing separation requires a stationary, fully equipped fixture without look sway.")
				var entry_weight := from_start / shortest_entry_angle
				var breathing: Vector3 = MOTION.locomotion(actual._motion_clock, 0.0, 0.0, true).position
				entry_grips_without_breathing.append(_actual_grip(actual) - breathing * entry_weight)
				_check(absf(from_start + to_contact - shortest_entry_angle) < 0.0001, context + ": every entry frame must remain on the single shortest rotation to independently sampled contact.")
				_check(from_start >= previous_entry_progress - 0.00002 and from_start <= shortest_entry_angle + 0.00002, context + ": entry must not turn back or overshoot the fixed contact direction.")
				entry_path_angle += _basis_distance(previous_pose.basis, pose.basis)
				previous_entry_progress = from_start
				if previous_state == DungeonPlayer.CombatState.ACTIVE and is_zero_approx(previous_time) and actual.state_time > 0.0:
					saw_first_active_motion = true
					_check(_basis_distance(previous_pose.basis, pose.basis) > 0.00001 and previous_grip.distance_to(_actual_grip(actual)) > 0.00001, context + ": the first positive ACTIVE tick must move the grip and blade into the cut without another held preparation.")
			if saw_contact:
				var relative := original.basis.inverse() * pose.basis
				var current_angle := atan2(relative.x.y, relative.x.x)
				var advance := wrapf(current_angle - tail_previous_angle, -PI, PI)
				_check(advance >= -0.003, context + ": after contact the retained recovery correction must continue in its existing rotational direction.")
				recovery_turn += advance
				tail_previous_angle = current_angle
				plane_error = maxf(plane_error, pose.basis.z.distance_to(original.basis.z))
		else:
			_check(_near_pose(pose, original), context + ": reverse and overhead must retain their complete visible source paths.")
			plane_error = maxf(plane_error, pose.basis.z.distance_to(original.basis.z))
		if actual.combat_state == DungeonPlayer.CombatState.WINDUP:
			_check(_near_pose(pose, original), context + ": WINDUP must retain the original held direction.")
			if variant == "right_diagonal":
				_check(_near_pose(pose, held) and _near_pose(actual.shield_pivot.transform, held_shield), context + ": forehand charge must hold the actual sword and shield without a separate preparation.")
		if elapsed < hold - 0.0000001:
			_check(actual.combat_state == DungeonPlayer.CombatState.WINDUP and is_equal_approx(actual.stamina, actual.MAX_STAMINA), context + ": held input must retain its charge clock without committing or spending early.")
		if previous_state == DungeonPlayer.CombatState.WINDUP and actual.combat_state == DungeonPlayer.CombatState.ACTIVE:
			saw_active = true
			_check(is_zero_approx(actual.state_time) and _near_pose(previous_pose, pose), context + ": ACTIVE zero must retain the actual held pose without an extra turn.")
			var minimum_windup := 0.0 if variant == "right_diagonal" else 0.22
			_check(elapsed >= maxf(minimum_windup, hold) and elapsed <= maxf(minimum_windup, hold) + STEP + 0.000001, context + ": release must commit the forehand on the next combat tick while other cuts retain their existing minimum windup.")
			var expected_charge := clampf(previous_time + delta - 0.24, 0.0, 1.0)
			_check(is_equal_approx(actual.attack_charge, expected_charge) and is_equal_approx(previous_stamina - actual.stamina, actual.get_melee_stamina_cost(expected_charge)), context + ": commit must keep the existing charge formula and single stamina cost.")
			if variant == "right_diagonal":
				_check(_near_pose(previous_shield, actual.shield_pivot.transform), context + ": immediate ACTIVE zero must preserve the captured shield pose instead of skipping its preparation curve.")
		if actual.combat_state == DungeonPlayer.CombatState.ACTIVE and actual.state_time >= 0.145 - 0.0000001:
			if variant == "right_diagonal":
				_check(pose.basis.x.distance_to(-original.basis.x) < 0.00005 and pose.basis.y.distance_to(-original.basis.y) < 0.00005 and pose.basis.z.distance_to(original.basis.z) < 0.00005, context + ": contact through ACTIVE end must reverse width/length axes while retaining the actual blade plane.")
			if absf(actual.state_time - 0.145) < 0.000001:
				saw_contact = true
				if variant == "right_diagonal":
					_check(pose.basis.y.x > 0.0 and original.basis.y.x < 0.0, context + ": the actual contact blade must point right while its unchanged baseline points left.")
					_check(_basis_distance(pose.basis, contact_basis) < 0.00002 and absf(entry_path_angle - shortest_entry_angle) < 0.0001, context + ": contact must finish the single shortest entry rotation without an extra flip.")
					# The former paired-baseline entry grip briefly retreated before
					# cutting. That path is intentionally superseded only before
					# contact. Retain the comparison player's actual endpoint and
					# raw monotonic checks, separating only its known breathing when
					# checking the underlying straight approach segment.
					var contact_breathing: Vector3 = MOTION.locomotion(actual._motion_clock, 0.0, 0.0, true).position
					var contact_without_breathing := _actual_grip(baseline) - contact_breathing
					_check(contact_without_breathing.distance_to(authored_contact * ARM.GRIP_CENTER) < 0.00005, context + ": removing only the fixture breathing must recover the independent authored contact grip.")
					entry_grip_line_errors = _check_entry_grips(entry_grips, entry_grips_without_breathing, held * ARM.GRIP_CENTER, _actual_grip(baseline), contact_without_breathing, context)
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
	_check(grip_error < 0.00005, context + ": contact, recovery and held poses must preserve the baseline grip trajectory; reverse and overhead retain it throughout.")
	_check(plane_error < 0.00005, context + ": contact and recovery must retain the baseline blade-plane normal; other cuts retain it throughout.")
	_check(completed and saw_contact and spent == 1, context + ": the real attack must hit its existing 145ms contact, spend stamina once and finish READY.")
	if variant == "right_diagonal":
		_check(saw_first_active_motion and absf(recovery_turn - PI) < 0.005, context + ": a directly moving entry must retain the existing additional half-turn recovery and finish at idle.")
	print("FOREHAND GRIP ", context, " preserved_grip_mm=", grip_error * 1000.0, " raw_line_error_mm=", entry_grip_line_errors.x * 1000.0, " breathing_removed_line_error_mm=", entry_grip_line_errors.y * 1000.0, " post_contact_plane_error=", plane_error, " first_ready_residual_degrees=", rad_to_deg(ready_residual), " entry_shortest_degrees=", rad_to_deg(shortest_entry_angle), " actual_entry_degrees=", rad_to_deg(entry_path_angle), " recovery_turn_degrees=", rad_to_deg(recovery_turn))


func _check_entry_grips(samples: Array[Vector3], without_breathing: Array[Vector3], held: Vector3, contact: Vector3, contact_without_breathing: Vector3, context: String) -> Vector2:
	var path := contact - held
	var straight_path := contact_without_breathing - held
	_check(samples.size() > 2 and samples.size() == without_breathing.size() and path.length() > 0.0001 and straight_path.length() > 0.0001, context + ": the actual immediate entry must contain a moving grip approach to contact.")
	if samples.is_empty() or samples.size() != without_breathing.size() or minf(path.length_squared(), straight_path.length_squared()) <= 0.00000001: return Vector2(INF, INF)
	var previous_progress := 0.0
	var previous_straight_progress := 0.0
	var maximum_line_errors := Vector2.ZERO
	for index in samples.size():
		var grip := samples[index]
		var progress := (grip - held).dot(path) / path.length_squared()
		maximum_line_errors.x = maxf(maximum_line_errors.x, grip.distance_to(held + path * progress))
		_check(progress >= previous_progress - 0.00001 and progress >= -0.00001 and progress <= 1.00001, context + ": entry grip must approach its real source-contact endpoint monotonically without retreat or overshoot.")
		previous_progress = progress
		var straight_grip := without_breathing[index]
		var straight_progress := (straight_grip - held).dot(straight_path) / straight_path.length_squared()
		maximum_line_errors.y = maxf(maximum_line_errors.y, straight_grip.distance_to(held + straight_path * straight_progress))
		_check(straight_progress >= previous_straight_progress - 0.00001 and straight_progress >= -0.00001 and straight_progress <= 1.00001, context + ": the underlying grip approach must also remain monotonic after separating known breathing.")
		previous_straight_progress = straight_progress
	_check(samples[0].distance_to(held) < 0.00005 and samples[-1].distance_to(contact) < 0.00005, context + ": the actual entry must preserve its captured held grip and rejoin the exact baseline contact grip.")
	_check(maximum_line_errors.y < 0.00005 and without_breathing[0].distance_to(held) < 0.00005 and without_breathing[-1].distance_to(contact_without_breathing) < 0.00005, context + ": separating only known breathing must expose a direct held-to-contact grip segment within the original geometric tolerance.")
	return maximum_line_errors


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


func _basis_distance(a: Basis, b: Basis) -> float:
	# atan2 keeps tiny frame-to-frame rotations measurable; acos(dot) loses
	# precision near an identical orientation in the engine's float basis.
	var relative := (a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()).normalized()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))


func _source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in SOURCE_PATHS: hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)


func _finish() -> void:
	for failure in failures: push_error(failure)
	print("SWORD FOREHAND GRIP %s: paired actual players; immediate release, direct grip approach and one shortest contact entry; preserved post-contact grip/charge/assets; reversed contact axes; fitted two-hand contacts; clash/cancel/F2 isolation; aesthetic quality not evaluated" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
