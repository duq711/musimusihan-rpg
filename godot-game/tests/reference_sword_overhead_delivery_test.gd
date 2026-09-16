extends SceneTree
## Actual installed iteration07 delivery only. Never injects synthetic samples
## into the production cache. An absent delivery is an explicit failure.

const DATA := preload("res://scripts/reference_sword_motion.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const SLEEVE := preload("res://scripts/reference_continuous_sleeve.gd")
const CATALOG := preload("res://scripts/test_room_catalog.gd")
const SOURCE := "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
const STEP := 1.0 / 60.0
const ABSENT := ["idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse"]
var failures: Array[String] = []
var actual_motion_checked := false
var actual_sleeve_checked := false
var arm_visual_report: Dictionary = {"checked": false, "native_sleeve_applied": false}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var entries := CATALOG.entries().filter(func(entry: Dictionary) -> bool: return entry.id == "motion_shield_cut_overhead")
	_check(entries.size() == 1 and entries[0].action == "first_person_motion" and entries[0].payload == "shield_cut_overhead", "Overhead delivery must use the existing executable fixed-cut test-room entry.")
	_check(not bool(DATA._decode_partial_manifest({}).ok), "An empty partial delivery must be rejected.")
	var hashes := _asset_hashes()
	_check(hashes[SOURCE] == DATA.SOURCE_SHA256, "The original static sword and glove must remain byte-identical.")
	var installed := FileAccess.file_exists(DATA.PARTIAL_MANIFEST_PATH)
	_check(installed, "Actual iteration07 overhead delivery is unconfirmed: production overhead_manifest.json is absent.")
	if installed:
		var scope := DATA.get_delivery_scope()
		var partial: bool = DATA.is_available() and scope.kind == "partial" and scope.clips == ["overhead"]
		_check(partial, "Installed delivery must load as exactly one partial overhead: " + DATA.get_load_error())
		if partial:
			actual_motion_checked = true
			_test_actual_scope()
			await _test_actual_test_room()
	_check(_asset_hashes() == hashes, "Actual delivery tests must not modify any received or original asset.")
	for failure in failures: push_error(failure)
	print("%s %s: %s" % [_report_name(), ("PASS" if failures.is_empty() else "FAIL"), JSON.stringify({"actual_motion_checked": actual_motion_checked, "actual_sleeve_checked": actual_sleeve_checked, "native_sleeve_required": _requires_native_sleeve(), "arm_visual": arm_visual_report, "full_eight_clip_delivery": false, "visual_match_verified": false})])
	quit(0 if failures.is_empty() else 1)


func _report_name() -> String:
	return "REFERENCE SWORD OVERHEAD DELIVERY"


func _requires_native_sleeve() -> bool:
	# This delivery gate remains strict. The separate runtime test overrides
	# only the declared scope, while reusing all actual gameplay assertions.
	return true


func _test_actual_scope() -> void:
	_check(not DATA.full_delivery_available() and DATA.right_arm_available(), "A real single overhead with arm data must not report all eight clips complete.")
	_check(DATA.has_track("overhead", "sword") and DATA.has_track("overhead", "shield") and DATA.has_right_arm("overhead"), "Actual overhead requires both equipment tracks and authored shoulder/elbow/wrist.")
	for clip: String in ABSENT:
		_check(not DATA.has_clip(clip) and not DATA.has_right_arm(clip), "Undelivered motion must remain unavailable: " + clip)
	var metadata := DATA.clip_metadata("overhead")
	_check(is_equal_approx(float(metadata.duration_seconds), 1.55), "The received source clip must retain its original 1.55-second duration.")
	var contact_time := DATA.authored_attack_time(metadata.timing, "active", 0.145, 0.0, true)
	var arm := DATA.sample_right_arm("overhead", contact_time)
	_check(bool(arm.get("exact_sample", false)), "The actual contact must address an explicit authored arm key.")
	_check(not DATA.sample("overhead", 0.0).is_equal_approx(DATA.sample("overhead", contact_time)), "Actual overhead must contain a moving sword trajectory.")
	if _requires_native_sleeve():
		_check(FileAccess.file_exists(SLEEVE.SOURCE_PATH) and FileAccess.get_sha256(SLEEVE.SOURCE_PATH) == SLEEVE.SOURCE_SHA256, "The actual continuous sleeve GLB must be received and match its Windows SHA-256.")


func _test_actual_test_room() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag := _inventory_fingerprint(original.inventory)
	var original_cursor := Input.mouse_mode
	var original_pause := paused
	var original_ticks := Engine.physics_ticks_per_second
	var audio_bus := AudioServer.get_bus_index("Master")
	var original_mute := AudioServer.is_bus_mute(audio_bus)
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "Actual delivery test must not replace an existing sandbox.")
	if sandbox.active: return
	AudioServer.set_bus_mute(audio_bus, true)
	Engine.physics_ticks_per_second = 60
	var room := (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	room.set_process_unhandled_input(false)
	_disable_player_input(room.player)
	_check(sandbox.active and room.inventory != original.inventory and room.panel_open and paused, "Actual test-room entry must isolate and pause its own expedition.")
	await _test_undelivered_movement(room)
	for feature: String in ["motion_shield_cut_right", "motion_shield_cut_left"]:
		await _test_undelivered_cut(room, feature)
	var bag: ExpeditionInventory = room.inventory
	for iteration in range(2):
		room.player.stamina = 1.0
		room.player.health = 31.0
		room.run_feature("motion_shield_cut_overhead")
		_disable_player_input(room.player)
		var player: DungeonPlayer = room.player
		_check(room.inventory == bag and not paused and not room.panel_open, "Repeated fixed overhead must resume the same isolated test bag.")
		_check(player.stamina == player.MAX_STAMINA and player.health == player.MAX_HEALTH, "Reselecting overhead must recover real health and stamina.")
		_check(str(bag.equipment.weapon) == "rusted_sword" and str(bag.equipment.offhand) == "round_shield" and player.sword_attack_mode == "overhead", "Existing fixture must equip the real sword/shield and fix the actual attack variant.")
		await _drive_frames(player, 24)
		_check(player.is_on_floor() and is_instance_valid(room.arm_motion_target) and not room.enemy_ai_enabled, "The overhead fixture must retain an actual floor and stationary damageable target.")
		await _exercise_overhead(room)
		await _test_f2_freeze(room)
		_check(ExpeditionSession.capture_snapshot() != original and sandbox.saved_session == original and _inventory_fingerprint(original.inventory) == original_bag, "Actual attacks and F2 must preserve the saved original expedition and inventory contents.")
	room.reset_room()
	_check(room.inventory != bag and room.panel_open and paused, "Reset after actual delivery trials must create another isolated bag.")
	room.run_feature("motion_shield_cut_overhead")
	_disable_player_input(room.player)
	_check(room.player.sword_attack_mode == "overhead" and is_instance_valid(room.arm_motion_target), "Actual overhead trial must remain playable after reset.")
	room._show_test_panel()
	room.leave_room()
	await _wait_for_menu()
	_check(not sandbox.active and ExpeditionSession.capture_snapshot() == original and _inventory_fingerprint(original.inventory) == original_bag, "Leaving the actual overhead fixture must restore the original inventory reference and expedition values.")
	if sandbox.active: sandbox.finish()
	paused = original_pause
	Engine.physics_ticks_per_second = original_ticks
	Input.mouse_mode = original_cursor
	AudioServer.set_bus_mute(audio_bus, original_mute)
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame


func _test_undelivered_movement(room: Node3D) -> void:
	room.run_feature("motion_sword_run")
	var player: DungeonPlayer = room.player
	_disable_player_input(player)
	await _drive_frames(player, 24)
	await _drive_frames(player, 36, Vector2(0, -1), true)
	_check(player.is_on_floor() and player.velocity.z < -player.WALK_SPEED, "Undelivered run must still execute real sprinting and floor collision.")
	_check_fallback_movement(player, "run")
	await _drive_frames(player, 24)
	var landings := int(player.get_first_person_motion_snapshot().landing_count)
	var jump := player.request_jump()
	_check(bool(jump.get("accepted", false)), "Undelivered jump must retain the actual jump request and stamina gate.")
	if not bool(jump.get("accepted", false)): return
	var air_seen := false
	for frame in range(120):
		await _drive_frames(player, 1)
		if not player.is_on_floor():
			air_seen = true
			_check_fallback_movement(player, "air")
		if air_seen and player.is_on_floor(): break
	_check(air_seen and player.is_on_floor() and int(player.get_first_person_motion_snapshot().landing_count) == landings + 1, "Undelivered jump must still land exactly once on the actual floor.")
	_check_fallback_movement(player, "land")


func _check_fallback_movement(player: DungeonPlayer, context: String) -> void:
	_check(not player._has_reference_locomotion() and not player._reference_locomotion_valid, "No absent movement sample may be substituted or labeled authored: " + context)
	var expected := CHOREOGRAPHY.ready()
	var local_velocity := player.global_basis.inverse() * player.velocity
	var speed := 0.0 if not player.is_on_floor() else player._motion_speed
	var movement := MOTION.locomotion(player._motion_clock, speed, local_velocity.x, false)
	expected.origin += movement.position + Vector3(player._motion_look_sway.x, player._motion_look_sway.y, 0)
	expected.basis = expected.basis * Basis.from_euler(movement.rotation)
	_check(_near_transform(player.weapon_pivot.transform, expected), "Actual sword must retain the existing procedural movement pose: " + context)


func _test_undelivered_cut(room: Node3D, feature: String) -> void:
	room.run_feature(feature)
	var player: DungeonPlayer = room.player
	_disable_player_input(player)
	await _drive_frames(player, 24)
	_neutralize_offsets(player)
	var attack := player.begin_sword_attack()
	_check(bool(attack.get("accepted", false)) and not DATA.has_track(player.sword_attack_variant), "Existing other-cut fixture must begin an actual undelivered variant: " + feature)
	if not bool(attack.get("accepted", false)): return
	player.attack_release_requested = true
	_combat_tick(player, 0.22001)
	_combat_tick(player, player.get_melee_hit_time())
	var expected := MOTION.sword("active", player.state_time, player.attack_charge, false, true, player.sword_attack_variant)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE and _near_transform(player.weapon_pivot.transform, expected), "Undelivered other cuts must retain their real fallback curve without missing-clip errors: " + feature)
	player.cancel_sword_attack()


func _exercise_overhead(room: Node3D) -> void:
	var player: DungeonPlayer = room.player
	var target := room.arm_motion_target as DungeonEnemy
	if not is_instance_valid(target): return
	_neutralize_offsets(player)
	_check(not player._query_melee_hits().is_empty(), "The existing 2m overhead target must intersect the real melee query.")
	var health := target.health
	var stamina := player.stamina
	var attack := player.begin_sword_attack()
	_check(bool(attack.get("accepted", false)) and player.sword_attack_variant == "overhead", "Fixed overhead must start through the actual player attack request.")
	if not bool(attack.get("accepted", false)): return
	player.attack_release_requested = true
	_combat_tick(player, 0.22001)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "Actual release must pass WINDUP and enter ACTIVE.")
	var cost := player.get_melee_stamina_cost(player.attack_charge)
	var hit := player.get_melee_hit_time()
	_check(is_equal_approx(hit, 0.145), "Authored source timing must preserve the existing paired gameplay contact at 145ms.")
	_combat_tick(player, hit - 0.0001)
	player._resolve_active_attack()
	_check(is_equal_approx(target.health, health), "Actual overhead must not damage the target before its gameplay hit time.")
	_combat_tick(player, 0.0001)
	var metadata := DATA.clip_metadata("overhead")
	var source_time := DATA.authored_attack_time(metadata.timing, "active", player.state_time, player.attack_charge, true)
	var expected := DATA.sample("overhead", source_time)
	_check(_near_transform(player.weapon_pivot.transform, expected), "The rendered sword at real contact must occupy the actual Windows trajectory.")
	_check(_near_transform(player.shield_pivot.transform, DATA.sample("overhead", source_time, "shield")), "The rendered shield must share the actual overhead contact clock.")
	var authored := DATA.sample_right_arm("overhead", source_time)
	var snapshot := player.get_first_person_motion_snapshot()
	var joints: Dictionary = snapshot.joint_landmarks.sword
	_check(bool(authored.get("exact_sample", false)) and bool(joints.get("exact_authored_sample", false)), "Real overhead contact must retain an exact authored joint key.")
	for joint: String in ["shoulder", "elbow", "wrist"]:
		_check(player.camera.to_local(joints[joint]).distance_to(authored[joint]) < 0.001, "Actual fitted arm must preserve the received contact joint within 1mm: " + joint)
	_check(float(snapshot.hand_contacts.sword.error) < 0.00001, "The original glove must remain attached to the moving sword.")
	_test_native_sleeve(player, authored)
	player._resolve_active_attack()
	var hit_health := target.health
	_check(hit_health < health and is_equal_approx(stamina - player.stamina, cost), "Actual overhead must damage its target and charge one production stamina cost.")
	player._resolve_active_attack()
	_check(is_equal_approx(target.health, hit_health), "Repeated contact resolution must not hit the same target twice.")
	_combat_tick(player, 0.30 - player.state_time)
	player._resolve_active_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "Actual active resolver must finish the overhead at the existing 300ms boundary.")
	for frame in range(90):
		_combat_tick(player, STEP)
		if player.combat_state == DungeonPlayer.CombatState.READY: break
	_check(player.combat_state == DungeonPlayer.CombatState.READY, "The actual overhead must complete recovery through the combat state machine.")
	# The received source endpoint differs from legacy READY. Preserve the
	# production 100ms handoff before checking the final fallback idle pose.
	_combat_tick(player, 0.11)
	_check(not player._reference_pose_handoff_active and _near_transform(player.weapon_pivot.transform, CHOREOGRAPHY.ready()), "Recovery must finish its handoff into the existing undelivered idle pose.")
	_check(bool(player.begin_sword_attack().get("accepted", false)), "Another actual overhead must be available for F2 cancellation.")


func _test_native_sleeve(player: DungeonPlayer, authored: Dictionary) -> void:
	var arm := player.weapon_arm as Node3D
	var visual: Dictionary = arm.call("get_snapshot")
	var status: Dictionary = visual.get("continuous_sleeve", {})
	arm_visual_report = {"checked": true, "animation_driver": str(visual.get("animation_driver", "")), "native_sleeve_applied": bool(status.get("ok", false)), "native_error": str(status.get("error", ""))}
	if not bool(status.get("ok", false)):
		_check(not _requires_native_sleeve(), "Actual continuous sleeve must load successfully: " + str(status.get("error", "missing native adapter")))
		_check(str(visual.get("animation_driver", "")) == "rigid_segment_fit" and not bool(visual.get("skeleton", true)), "Without the received native sleeve, runtime must explicitly report its existing rigid segment arm.")
		_test_existing_arm_surfaces(player, authored)
		return
	actual_sleeve_checked = true
	_check(str(status.source_sha256) == SLEEVE.SOURCE_SHA256 and int(status.bone_count) == 7 and int(status.mesh_count) == 3 and int(status.updates) > 0, "Native sleeve must expose the verified actual 7-bone / 3-surface asset with real pose updates.")
	_check(str(status.clock_owner) == "production_player" and int(status.runtime_animation_players) == 0, "Native sleeve must use the production player clock without another animation clock.")
	var adapter := arm.get_node_or_null("ReferenceContinuousSleeve")
	_check(adapter != null and adapter.has_method("bone_point_to_global"), "Native sleeve must expose its actual skin-bone landmarks.")
	if adapter == null or not adapter.has_method("bone_point_to_global"): return
	for item: Array in [["shoulder", "SleeveUpper", ARM.REST_SHOULDER], ["elbow", "SleeveForearm", ARM.REST_ELBOW], ["wrist", "SleeveHand", ARM.REST_WRIST]]:
		var actual: Vector3 = adapter.call("bone_point_to_global", item[1], item[2])
		_check(actual.is_finite() and player.camera.to_local(actual).distance_to(authored[item[0]]) < 0.001, "Actual native skin bone must reach the received contact joint within 1mm: " + str(item[0]))
	for part: MeshInstance3D in adapter.arm_meshes:
		_check(part.is_visible_in_tree() and part.skin != null and part.get_node_or_null(part.skeleton) == adapter.skeleton, "Each visible received sleeve surface must remain bound to the actual runtime skeleton.")


func _test_existing_arm_surfaces(player: DungeonPlayer, authored: Dictionary) -> void:
	var upper := player.weapon_arm.get_node_or_null("RightArm_UpperArm_Surface") as MeshInstance3D
	var forearm := player.weapon_arm.get_node_or_null("RightArm_Forearm_Surface") as MeshInstance3D
	_check(upper != null and forearm != null and upper.is_visible_in_tree() and forearm.is_visible_in_tree(), "Runtime without the native sleeve must retain the real visible original arm surfaces.")
	if upper == null or forearm == null: return
	var points := {"shoulder": player.camera.to_local(upper.to_global(ARM.REST_SHOULDER)), "elbow": player.camera.to_local(upper.to_global(ARM.REST_ELBOW)), "wrist": player.camera.to_local(forearm.to_global(ARM.REST_WRIST))}
	for joint: String in ["shoulder", "elbow", "wrist"]:
		_check((points[joint] as Vector3).distance_to(authored[joint]) < 0.001, "Existing actual surface must reproduce the received contact joint within 1mm: " + joint)
	_check(player.camera.to_local(forearm.to_global(ARM.REST_ELBOW)).distance_to(points.elbow) < 0.001, "Existing forearm and upper arm must meet at the actual authored elbow.")
	_check(absf((points.shoulder as Vector3).distance_to(points.elbow) / ARM.REST_UPPER_LENGTH - 1.0) <= 0.01 and absf((points.elbow as Vector3).distance_to(points.wrist) / ARM.REST_FOREARM_LENGTH - 1.0) <= 0.01, "Actual existing surfaces must retain the delivered arm lengths within the 1 percent contract.")


func _test_f2_freeze(room: Node3D) -> void:
	var player: DungeonPlayer = room.player
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.physical_keycode = KEY_F2
	f2.pressed = true
	room._unhandled_input(f2)
	_check(paused and room.panel_open and player.combat_state == DungeonPlayer.CombatState.READY, "F2 must cancel the actual overhead and pause its existing test menu.")
	var frozen := player.get_first_person_motion_snapshot().duplicate(true)
	var sleeve: Dictionary = player.weapon_arm.call("get_snapshot").get("continuous_sleeve", {}).duplicate(true)
	var stamina := player.stamina
	var position := player.position
	var hunger := ExpeditionSession.hunger
	player.advance_combat_state(0.4)
	player.advance_movement(0.4, Vector2(0, -1), true)
	player._update_viewmodel(0.4)
	player._resolve_active_attack()
	await create_timer(0.025, true).timeout
	_check(player.get_first_person_motion_snapshot() == frozen and player.weapon_arm.call("get_snapshot").get("continuous_sleeve", {}) == sleeve, "F2 must freeze both production motion and native sleeve updates.")
	_check(player.stamina == stamina and player.position == position and ExpeditionSession.hunger == hunger, "F2 must freeze real movement, stamina and survival.")


func _disable_player_input(player: DungeonPlayer) -> void:
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_torch_enabled(false)
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION


func _drive_frames(player: DungeonPlayer, count: int, movement := Vector2.ZERO, sprint := false) -> void:
	for frame in range(count):
		await physics_frame
		player.advance_movement(STEP, movement, sprint)
		player._update_viewmodel(STEP)


func _neutralize_offsets(player: DungeonPlayer) -> void:
	player.velocity = Vector3.ZERO
	player._motion_speed = 0.0
	player._motion_look_sway = Vector2.ZERO
	player._motion_clock = 0.0
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._shield_impact = 0.0
	player._update_viewmodel(0.0)


func _combat_tick(player: DungeonPlayer, delta: float) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta)
	# Neutralize breathing only, leaving real combat/source clocks untouched.
	player._motion_clock = -delta
	player._update_viewmodel(delta)


func _wait_for_menu() -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://main_menu.tscn" and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "Actual overhead test-room exit timed out before original expedition restoration.")


func _asset_hashes() -> Dictionary:
	var result := {}
	for path: String in [SOURCE, SLEEVE.SOURCE_PATH, DATA.MANIFEST_PATH, DATA.PARTIAL_MANIFEST_PATH]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result


func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null: return "none"
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data})


func _near_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.00001 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.001


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
