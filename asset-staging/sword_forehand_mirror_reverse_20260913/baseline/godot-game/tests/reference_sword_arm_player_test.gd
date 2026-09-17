extends SceneTree
## Integration against explicitly analytical in-memory clips, never a Windows
## delivery. The original production cache is restored before this test exits.

const DATA := preload("res://scripts/reference_sword_motion.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const IK := preload("res://scripts/reference_sword_arm.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const PREVIEW := preload("res://tests/reference_sword_motion_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original_cache := {"loaded": DATA._loaded, "clips": DATA._clips, "error": DATA._load_error, "arm_available": DATA._right_arm_available}
	var original_session := ExpeditionSession.capture_snapshot()
	var original_inventory := _inventory_digest()
	var original_cursor := Input.mouse_mode
	var original_pause := paused
	var original_mute := AudioServer.is_bus_mute(0)
	var sources := _source_hashes()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "Analytical arm integration must not replace an active sandbox.")
	if sandbox.active:
		quit(1)
		return
	var clips := _analytical_clips()
	var clip_count := DATA.RIGHT_ARM_REQUIRED_CLIPS.size() + 1
	_check(clips.size() == clip_count and clips.has("walk"), "All eight required analytical clips and the Mac walk context must decode before cache substitution.")
	if clips.size() != clip_count or not clips.has("walk"):
		quit(1)
		return
	# Only this short-lived test process sees this fixture; no manifest, source
	# file, provenance record, or delivered-output claim is created.
	DATA._clips = clips
	DATA._loaded = true
	DATA._load_error = ""
	DATA._right_arm_available = true
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	paused = false
	var fixture := _fixture()
	var player := fixture.player as DungeonPlayer
	var original_meshes := _mesh_ids(player)
	_test_exact_key_meshes(player)
	_test_authored_elbow_at_rest_shoulder(player)
	for fps in [30, 60, 120]:
		_test_combat_sampling(player, fps)
	_test_zero_time_handoffs(player)
	_test_guard_seed_adjustment(player)
	_test_partial_stow_cancel(fixture)
	_test_clash(fixture)
	_test_reset(player)
	_check(_mesh_ids(player) == original_meshes, "Arm playback must retain every original mesh resource.")
	(fixture.viewport as SubViewport).queue_free()
	await process_frame
	await _test_actual_f2()
	sandbox.finish()
	paused = original_pause
	Input.mouse_mode = original_cursor
	AudioServer.set_bus_mute(0, original_mute)
	DATA._clips = original_cache.clips
	DATA._loaded = original_cache.loaded
	DATA._load_error = original_cache.error
	DATA._right_arm_available = original_cache.arm_available
	_check(DATA._clips == original_cache.clips and DATA._loaded == original_cache.loaded and DATA._load_error == original_cache.error and DATA._right_arm_available == original_cache.arm_available, "Original production cache and availability must be restored.")
	_check(_source_hashes() == sources, "Analytical integration must never write a source or production manifest.")
	_check(ExpeditionSession.capture_snapshot() == original_session and _inventory_digest() == original_inventory and Input.mouse_mode == original_cursor and paused == original_pause, "All fixtures must preserve the original expedition, inventory, pause and cursor.")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD ARM PLAYER %s: analytical fixture only; actual_delivery_evaluated=false; actual meshes, 30/60/120Hz clocks, handoffs, blade clash, F2 and reset" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _fixture() -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	fixture["viewport"] = viewport
	_check(PREVIEW.ARM_PREVIEW.configure_pose(fixture, "idle"), "Actual fixture must equip its real static-grip sword and shield.")
	var player := fixture.player as DungeonPlayer
	player.set_torch_enabled(false)
	player.position = Vector3(0, 0.9, 2.4)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player._pitch = 0.0
	_check(player.weapon_arm.get_meta("imported_static_grip", false) and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "Use original imported arm with automatic OS input/physics disabled.")
	_neutralize(player)
	return fixture


func _neutralize(player: DungeonPlayer) -> void:
	player.cancel_sword_attack()
	player.reset_reference_movement_motion()
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player.velocity = Vector3.ZERO
	player._motion_speed = 0.0
	player._motion_clock = 0.0
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._motion_look_sway = Vector2.ZERO
	player._motion_previous_look = Vector2(player.rotation.y, player._pitch)
	player._camera_shake = 0.0
	player._update_viewmodel(0.12)
	player._motion_clock = 0.0
	player._update_viewmodel(0.0)


func _test_exact_key_meshes(player: DungeonPlayer) -> void:
	for clip: String in DATA.RIGHT_ARM_REQUIRED_CLIPS:
		for time in [0.0, 0.5, 1.0]:
			var sampled := DATA.sample_right_arm(clip, time)
			player.weapon_pivot.transform = sampled.raw_sword
			player._reference_arm_target = sampled
			player._update_character_arms()
			var actual := _actual_arm(player)
			for joint: String in ["shoulder", "elbow", "wrist"]:
				_check((actual[joint] as Vector3).distance_to(sampled[joint]) < 0.00002, "Original mesh joint must reproduce an exact analytical source key: %s/%s/%s" % [clip, str(time), joint])
			_check(bool(player._joint_landmarks.sword.exact_authored_sample), "Exact source keys must remain marked exact.")
			_check_geometry(player, "exact " + clip)
	# An interior time must be reconstructed to source lengths even when the
	# independent linear joint inputs contract under analytical rotation.
	var between := DATA.sample_right_arm("overhead", 0.25)
	_check(not bool(between.exact_sample), "Interior fixture time must exercise runtime reconstruction.")
	player.weapon_pivot.transform = between.raw_sword
	player._reference_arm_target = between
	player._update_character_arms()
	_check_geometry(player, "interpolated analytical key")


func _test_combat_sampling(player: DungeonPlayer, fps: int) -> void:
	for variant: String in DATA.ATTACK_CLIPS:
		_neutralize(player)
		var entry_pose := player.weapon_pivot.transform
		var entry_arm := _actual_arm(player)
		var accepted := player.begin_sword_attack(variant)
		_check(bool(accepted.get("accepted", false)), "Actual equipped attack must begin for clock sampling.")
		if not bool(accepted.get("accepted", false)): continue
		var entry_duration := player._sword_direct_entry_duration()
		_check(is_equal_approx(entry_duration, player.get_melee_hit_time() if variant == "right_diagonal" else 0.10), "Only forehand may extend its direct entry to the actual contact time.")
		_check(player._uses_direct_sword_entry("windup") and _near_pose(player._sword_entry_pose, entry_pose), "Actual start must capture the visible sword before the active swing.")
		_check_arm_equal(player._sword_entry_arm, entry_arm, "actual attack captured starting arm")
		player._update_viewmodel(0.0)
		_check(_near_pose(player.weapon_pivot.transform, entry_pose), "Attack start at zero time must preserve the visible sword.")
		_check_arm_equal(_actual_arm(player), entry_arm, "attack zero-time held arm")
		var metadata := DATA.clip_metadata(variant)
		player.attack_release_requested = true
		var seen_active := false
		var seen_active_start := false
		for frame in range(fps * 2):
			var delta := 1.0 / float(fps)
			player.advance_combat_state(delta)
			# Neutralize only the additive look/breathing clock for comparison;
			# the actual combat clock, charge and state transitions keep running.
			player._motion_clock = -delta
			player._update_viewmodel(delta)
			_check_geometry(player, "%dHz %s" % [fps, variant])
			var phase := str(DungeonPlayer.CombatState.keys()[player.combat_state]).to_lower()
			if phase == "active": seen_active = true
			if phase == "windup":
				_check(player._uses_direct_sword_entry(phase), "WINDUP must retain the actual captured entry at %dHz/%s." % [fps, variant])
				_check(_near_pose(player.weapon_pivot.transform, entry_pose), "Every cut must retain the held sword without a preparatory lift or turn at %dHz/%s." % [fps, variant])
				_check_arm_equal(_actual_arm(player), entry_arm, "held WINDUP arm %dHz/%s" % [fps, variant])
			elif phase == "active" and player.state_time < entry_duration:
				_check(player._uses_direct_sword_entry(phase), "The variant's initial ACTIVE entry interval must connect the held pose to the authored swing.")
				if is_zero_approx(player.state_time):
					seen_active_start = true
					_check(_near_pose(player.weapon_pivot.transform, entry_pose), "ACTIVE t=0 must continue the held sword without a jump: %dHz/%s" % [fps, variant])
					_check_arm_equal(_actual_arm(player), entry_arm, "ACTIVE zero-time arm %dHz/%s" % [fps, variant])
			elif phase in ["active", "recovery"] and not player._reference_pose_handoff_active:
				_check(not player._uses_direct_sword_entry(phase), "After the variant's entry endpoint, no direct-entry blend may remain.")
				var time := DATA.authored_attack_time(metadata.timing, phase, player.state_time, player.attack_charge, true)
				var sample := DATA.sample_right_arm(variant, time)
				if variant == "right_diagonal":
					_check_forehand_pose(player.weapon_pivot.transform, sample.raw_sword, phase == "active", "forehand %dHz/%s" % [fps, phase])
				else:
					_check(_near_pose(player.weapon_pivot.transform, sample.raw_sword), "Player weapon and authored arm must sample the shared combat time at %dHz." % fps)
			player._resolve_active_attack()
			if player.combat_state == DungeonPlayer.CombatState.READY: break
		_check(seen_active and seen_active_start and player.combat_state == DungeonPlayer.CombatState.READY, "Actual attack must preserve ACTIVE entry, traverse the original swing and finish at every sampled rate.")
	# Test exact entry/contact boundaries through each full composed player path.
	for variant: String in DATA.ATTACK_CLIPS:
		_neutralize(player)
		_check(bool(player.begin_sword_attack(variant).get("accepted", false)), "Exact contact sampling must initialize the real attack-entry and coordinated timing state.")
		var entry_duration := player._sword_direct_entry_duration()
		player.combat_state = DungeonPlayer.CombatState.ACTIVE
		# 100ms remains a measured checkpoint for every cut. Sample both sides
		# with frozen overlay time to distinguish a pose jump from normal motion.
		var previous_pose := Transform3D.IDENTITY
		var previous_wrist := Vector3.ZERO
		for offset: float in [-0.000001, 0.0, 0.000001]:
			player.state_time = 0.10 + offset
			player._update_viewmodel(0.0)
			var actual_pose := player.weapon_pivot.transform
			var actual_arm := _actual_arm(player)
			var actual_wrist: Vector3 = actual_arm.wrist
			if offset >= 0.0:
				_check(actual_pose.origin.distance_to(previous_pose.origin) < 0.0001 and actual_pose.basis.get_rotation_quaternion().angle_to(previous_pose.basis.get_rotation_quaternion()) < 0.001 and actual_wrist.distance_to(previous_wrist) < 0.0001, "Sword and actual wrist must remain continuous across 100ms: " + variant)
			if offset == 0.0:
				_check(player._uses_direct_sword_entry("active") == (variant == "right_diagonal"), "At exactly 100ms only forehand must still be in direct entry: " + variant)
			_check_geometry(player, "100ms connection checkpoint " + variant)
			previous_pose = actual_pose
			previous_wrist = actual_wrist
		player.state_time = entry_duration
		player._update_viewmodel(0.0)
		var boundary_metadata := DATA.clip_metadata(variant)
		var boundary_time := DATA.authored_attack_time(boundary_metadata.timing, "active", player.state_time, player.attack_charge, true)
		var boundary_sample := DATA.sample_right_arm(variant, boundary_time)
		_check(not player._uses_direct_sword_entry("active"), "The exact variant entry endpoint must finish the direct-entry blend: " + variant)
		if variant == "right_diagonal":
			_check_forehand_pose(player.weapon_pivot.transform, boundary_sample.raw_sword, true, "forehand entry endpoint")
		else:
			_check(_near_pose(player.weapon_pivot.transform, boundary_sample.raw_sword), "The exact variant entry endpoint must restore the original blade pose: " + variant)
		_check_geometry(player, "exact authored entry endpoint " + variant)
		player.state_time = player.get_melee_hit_time()
		player._update_viewmodel(0.0)
		var contact_time := float(boundary_metadata.timing.windup_seconds) + float(boundary_metadata.timing.hit_seconds)
		var expected := DATA.sample_right_arm(variant, contact_time)
		_check(is_equal_approx(player.state_time, 0.145) and not player._uses_direct_sword_entry("active"), "Exactly 145ms must reach the authored contact without the entry override: " + variant)
		if variant == "right_diagonal":
			_check_forehand_pose(player.weapon_pivot.transform, expected.raw_sword, true, "forehand exact contact")
			_check(not bool(player._joint_landmarks.sword.exact_authored_sample), "The turned forehand wrist must be fitted by IK instead of retaining a stale exact-arm flag.")
			var target: Dictionary = player._reference_arm_target
			_check(not bool(target.get("fitted_pose", false)) and not bool(target.get("exact_sample", false)), "Forehand correction must invalidate old arm fits before solving the new wrist.")
			_check((target.shoulder as Vector3).distance_to(expected.shoulder) < 0.00002 and (target.elbow as Vector3).distance_to(expected.elbow) < 0.00002, "Forehand correction must retain the original shoulder and elbow hints.")
			_check(_near_pose(target.raw_sword, player.weapon_pivot.transform), "Forehand arm input must identify the corrected actual sword pose.")
			_check_geometry(player, "forehand exact contact after wrist IK")
			player.combat_state = DungeonPlayer.CombatState.RECOVERY
			player.state_time = lerpf(0.47, 0.68, player.attack_charge)
			player._update_viewmodel(0.0)
			var recovery_time := DATA.authored_attack_time(boundary_metadata.timing, "recovery", player.state_time, player.attack_charge, true)
			_check(_near_pose(player.weapon_pivot.transform, DATA.sample(variant, recovery_time)), "Forehand must return to the original orientation exactly at the recovery endpoint.")
			_check_geometry(player, "forehand recovery endpoint")
		else:
			_check(bool(player._joint_landmarks.sword.exact_authored_sample), "Shared real hit timestamp must preserve the exact authored key: " + variant)
			_check_arm_equal(_actual_arm(player), expected, "exact retimed contact " + variant)


func _check_forehand_pose(actual: Transform3D, original: Transform3D, half_turn: bool, context: String) -> void:
	_check((actual * ARM.GRIP_CENTER).distance_to(original * ARM.GRIP_CENTER) < 0.00002, context + ": turning the model must preserve the authored grip position.")
	_check(actual.basis.z.distance_to(original.basis.z) < 0.00002, context + ": the original local-Z axis must remain unchanged.")
	if half_turn:
		_check(actual.basis.x.distance_to(-original.basis.x) < 0.00002 and actual.basis.y.distance_to(-original.basis.y) < 0.00002, context + ": contact must independently reverse original X/Y axes without reversing Z.")


func _test_authored_elbow_at_rest_shoulder(player: DungeonPlayer) -> void:
	# This analytical source key is inside the v2 +/-1% length contract.
	# The legacy rest-shoulder exception used to erase its 20 mm elbow offset,
	# while the player's cache incorrectly continued reporting that offset.
	var source := ARM.SOURCE_READY
	var expected := {"shoulder": source * ARM.REST_SHOULDER,
		"elbow": source * (ARM.REST_ELBOW + Vector3.UP * 0.02),
		"wrist": source * ARM.REST_WRIST}
	var q := source.basis.get_rotation_quaternion()
	var sword: Array = []
	var shield: Array = []
	var joints: Array = []
	for time in [0.0, 1.0]:
		sword.append({"time_seconds": time, "position": _array(source.origin), "rotation_xyzw": [q.x, q.y, q.z, q.w]})
		shield.append({"time_seconds": time, "position": [-0.35, -0.2, -0.6], "rotation_xyzw": [0, 0, 0, 1]})
		joints.append({"time_seconds": time, "shoulder": _array(expected.shoulder), "elbow": _array(expected.elbow), "wrist": _array(expected.wrist)})
	var raw := {"kind": "locomotion", "duration_seconds": 1.0, "loop": false,
		"tracks": {"sword": sword, "shield": shield}, "right_arm": joints}
	var clip := DATA._decode_clip("idle", raw, 2)
	_check(not clip.is_empty(), "A 20 mm elbow offset at the source rest shoulder must satisfy the agreed v2 length/wrist contract.")
	if clip.is_empty(): return
	var saved_idle: Dictionary = DATA._clips.idle
	DATA._clips["idle"] = clip
	_neutralize(player)
	var sampled := DATA.sample_right_arm("idle", 0.0)
	_check(bool(sampled.exact_sample), "Rest-shoulder regression must use an exact validated source key.")
	var actual := _actual_arm(player)
	_check_arm_equal(actual, expected, "authored elbow at exact source rest shoulder / actual surfaces")
	_check_arm_equal(player._reference_arm_rendered, actual, "authored elbow at exact source rest shoulder / rendered cache")
	_check((actual.elbow as Vector3).distance_to(source * ARM.REST_ELBOW) > 0.0199, "The authored 20 mm bend must survive instead of snapping to the legacy straight elbow.")
	_check((actual.elbow as Vector3).distance_to(actual.forearm_elbow) < 0.00002, "Both original sleeve surfaces must preserve the same authored elbow.")
	var landmarks: Dictionary = player._joint_landmarks.sword
	for joint: String in ["shoulder", "elbow", "wrist"]:
		_check((actual[joint] as Vector3).distance_to(player.camera.to_local(landmarks[joint])) < 0.00002, "Recorded landmarks must match the source-rest regression's actual mesh: " + joint)
	var upper := (actual.shoulder as Vector3).distance_to(actual.elbow)
	var forearm := (actual.elbow as Vector3).distance_to(actual.wrist)
	_check(absf(upper - IK.UPPER_LENGTH) <= IK.UPPER_LENGTH * 0.01 and absf(forearm - IK.FOREARM_LENGTH) <= IK.FOREARM_LENGTH * 0.01, "Exact authored tolerance must not be silently replaced with canonical-length IK.")
	_check(bool(landmarks.exact_authored_sample) and float(player._hand_contacts.sword.error) < 0.00001, "The exact accepted key must retain its authored flag and original sword/glove contact.")
	DATA._clips["idle"] = saved_idle


func _test_zero_time_handoffs(player: DungeonPlayer) -> void:
	for source: String in ["run", "air", "land", "attack"]:
		_neutralize(player)
		player._movement_ground_known = true
		player._movement_grounded = source in ["run", "land", "attack"]
		player._movement_phase = source if source in ["air", "land"] else "grounded"
		player._movement_phase_time = 0.5
		player._movement_landing_strength = 0.65
		player._movement_run_time = 0.5
		if source == "run":
			player._motion_speed = player.SPRINT_SPEED
			player.velocity = Vector3(0, 0, -player.SPRINT_SPEED)
		if source == "attack":
			_check(bool(player.begin_sword_attack("overhead").get("accepted", false)), "Attack-to-guard fixture must capture the real entry state before contact sampling.")
			player.combat_state = DungeonPlayer.CombatState.ACTIVE
			player.state_time = player.get_melee_hit_time()
		player._motion_clock = -0.12
		player._update_viewmodel(0.12)
		var before := _actual_arm(player)
		var sword := player.weapon_pivot.transform
		player.cancel_sword_attack()
		_check(bool(player.begin_sword_attack("right_diagonal").get("accepted", false)), "Basic direct entry must accept an actual prior pose: " + source)
		player._update_viewmodel(0.0)
		_check(_near_pose(sword, player.weapon_pivot.transform), "Basic direct entry at zero time must retain the previous actual sword: " + source)
		_check_arm_equal(_actual_arm(player), before, "basic direct entry t=0 from " + source)
		_check_geometry(player, "basic direct entry zero-time handoff from " + source)
		player.cancel_sword_attack()
		player.blocking = true
		player._update_viewmodel(0.0)
		_check(player._reference_pose_handoff_active and _near_pose(sword, player.weapon_pivot.transform), "Guard t=0 must retain the previous actual sword: " + source)
		_check_arm_equal(_actual_arm(player), before, "guard t=0 from " + source)
		_check_geometry(player, "guard handoff from " + source)
		player._update_viewmodel(0.11)
		_check(not player._reference_pose_handoff_active, "Guard handoff must end after the existing 100ms interval.")
		_check_geometry(player, "guard settled from " + source)


func _test_clash(fixture: Dictionary) -> void:
	var player := fixture.player as DungeonPlayer
	_neutralize(player)
	_check(bool(player.begin_sword_attack("overhead").get("accepted", false)), "Clash fixture must start the real attack before sampling its direct entry.")
	player.combat_state = DungeonPlayer.CombatState.ACTIVE
	player.state_time = 0.1
	player._motion_speed = player.WALK_SPEED
	player.velocity = Vector3(0, 0, -player.WALK_SPEED)
	player._motion_look_sway = Vector2(0.015, -0.01)
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION * 0.7
	player._update_viewmodel(0.0)
	var enemy := DungeonEnemy.new()
	enemy.configure("분석용 실제 검 충돌", 2000, 12, 0, Color.GRAY)
	enemy.position = Vector3(12, 1, -12)
	(fixture.stage as Node3D).add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(player, null, fixture.stage)
	enemy._set_state(DungeonEnemy.AIState.ACTIVE)
	var attacker_proxy := enemy.get_sword_clash_proxy()
	var player_proxy := player.get_sword_clash_proxy()
	enemy.sword_blade.global_position += (player_proxy.center as Vector3) - (attacker_proxy.center as Vector3)
	var before := _actual_arm(player)
	var pivot := player.weapon_pivot.transform
	var clashed := player.try_sword_clash(enemy)
	_check(clashed and player.combat_state == DungeonPlayer.CombatState.RECOVERY, "Actual overlapping blade proxies must trigger clash recovery.")
	if clashed:
		_check_arm_equal(player._reference_arm_clash_from, before, "actual clash capture")
		player._update_viewmodel(0.0)
		_check(_near_pose(pivot, player.weapon_pivot.transform), "Clash t=0 must retain the actual composed blade.")
		_check_arm_equal(_actual_arm(player), before, "actual clash t=0")
		_check_geometry(player, "actual clash t=0")
	enemy.queue_free()


func _test_guard_seed_adjustment(player: DungeonPlayer) -> void:
	_neutralize(player)
	player.blocking = true
	player._motion_clock = -0.30
	player._update_viewmodel(0.30)
	var requested := ARM.SOURCE_READY * ARM.REST_SHOULDER
	var actual := _actual_arm(player)
	var adjustment := (actual.shoulder as Vector3).distance_to(requested)
	var landmarks: Dictionary = player._joint_landmarks.sword
	_check(adjustment > 0.0001, "Real guard seed must exercise a measurable initial reach correction.")
	_check(absf(float(landmarks.shoulder_adjustment_m) - adjustment) < 0.00002, "Final fitting must retain the guard seed's correction instead of replacing it with its second solve's zero.")
	_check((player._reference_arm_target.requested_shoulder as Vector3).distance_to(requested) < 0.00002, "Guard seed must retain the original requested shoulder.")
	# Compare the independently composed rigid delta against the carried
	# requested shoulder after look/equip offsets.
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION * 0.7
	player._motion_look_sway = Vector2(0.012, -0.009)
	player._update_viewmodel(0.0)
	var raw_guard := CHOREOGRAPHY.guard_sword(player._shield_raise_progress)
	var delta_pose := player.weapon_pivot.transform * raw_guard.affine_inverse()
	var composed_request := delta_pose * requested
	actual = _actual_arm(player)
	landmarks = player._joint_landmarks.sword
	_check((player._reference_arm_rendered.requested_shoulder as Vector3).distance_to(composed_request) < 0.00002, "Requested shoulder must follow the same actual look/equip transform as the arm.")
	_check(absf(float(landmarks.shoulder_adjustment_m) - (actual.shoulder as Vector3).distance_to(composed_request)) < 0.00002, "Snapshot must report total actual displacement from the composed request.")
	_check_geometry(player, "guard seed correction with overlays")


func _test_partial_stow_cancel(fixture: Dictionary) -> void:
	var player := fixture.player as DungeonPlayer
	var chest := fixture.chest as DungeonLootChest
	for destination: String in ["guard", "locomotion"]:
		_neutralize(player)
		if destination == "guard":
			player._movement_ground_known = true
			player._movement_grounded = false
			player._movement_phase = "air"
			player._movement_phase_time = 0.25
			player._motion_clock = -0.12
			player._update_viewmodel(0.12)
		else:
			player.blocking = true
			player._motion_clock = -0.30
			player._update_viewmodel(0.30)
		var before := _actual_arm(player)
		var before_pivot := player.weapon_pivot.transform
		var before_cache: Dictionary = player._reference_arm_rendered.duplicate(true)
		var started := player.begin_timed_interaction(chest, 2.0, "분석용 실제 상자 부분 수납")
		_check(started and player.chest_equipment_stowed, "Actual chest interaction must start equipment stowing.")
		if not started: continue
		player.advance_timed_interaction(player.timed_interaction_duration * 0.08)
		_check(player._chest_stow_amount > 0.0 and player._chest_stow_amount < 1.0, "Regression must interrupt partial stowing before equipment is fully tucked.")
		player._update_viewmodel(0.04)
		_check(player._reference_arm_rendered == before_cache, "Hidden stowed fitting must never replace the saved visible arm pose.")
		player.cancel_timed_interaction()
		_check(not player.chest_equipment_stowed and not player.is_timed_interacting(), "Actual cancellation must finish the partial chest interaction.")
		_check(_near_pose(player.weapon_pivot.transform, before_pivot), "Cancellation must immediately restore the actual sword.")
		_check_arm_equal(_actual_arm(player), before, "partial stow cancel immediate arm / " + destination)
		_check_arm_equal(player._reference_arm_rendered, _actual_arm(player), "partial stow cancel restored cache / " + destination)
		_check_geometry(player, "partial stow cancel " + destination)
		# The regular cancel API also releases guard; the next delta=0 update
		# must capture the restored visible chain when entering either owner.
		player.cancel_sword_attack()
		player.blocking = destination == "guard"
		player._update_viewmodel(0.0)
		_check(player._reference_pose_handoff_active, "Resuming after stow cancellation must exercise the next real ownership handoff.")
		_check(_near_pose(player.weapon_pivot.transform, before_pivot), "Post-cancel handoff t=0 must retain the restored sword: " + destination)
		_check_arm_equal(_actual_arm(player), before, "post-cancel handoff t=0 / " + destination)
		_check_geometry(player, "post-cancel handoff " + destination)


func _test_reset(player: DungeonPlayer) -> void:
	player.reset_reference_movement_motion(true)
	_check(player._reference_arm_target.is_empty() and player._reference_arm_rendered.is_empty() and player._reference_arm_locomotion_from.is_empty() and player._reference_arm_handoff_from.is_empty() and player._reference_arm_clash_from.is_empty() and player._reference_arm_previous_bend == Vector3.ZERO, "Movement reset must clear every authored-arm target, capture and direction cache.")


func _test_actual_f2() -> void:
	var room := (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	room.set_process(false)
	room.set_physics_process(false)
	room.run_feature("motion_sword_run")
	var player: DungeonPlayer = room.player
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._update_viewmodel(0.12)
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.physical_keycode = KEY_F2
	key.pressed = true
	room._unhandled_input(key)
	_check(paused and room.panel_open, "Direct test-room F2 handling must open the real paused menu.")
	var captured := player.get_first_person_motion_snapshot()
	var arm := _actual_arm(player)
	var private_state := [player._reference_arm_target.duplicate(true), player._reference_arm_rendered.duplicate(true), player._reference_arm_previous_bend, player._reference_pose_handoff_elapsed]
	player.advance_combat_state(0.4)
	player._update_viewmodel(0.4)
	_check(player.get_first_person_motion_snapshot() == captured, "F2 must freeze actual motion clocks and landmarks.")
	_check_arm_equal(_actual_arm(player), arm, "F2 paused original mesh")
	_check(private_state == [player._reference_arm_target, player._reference_arm_rendered, player._reference_arm_previous_bend, player._reference_pose_handoff_elapsed], "F2 must also freeze private arm interpolation history.")
	room._unhandled_input(key)
	_check(not paused and not room.panel_open, "F2 must resume the same test room.")
	_test_reset(player)
	room.queue_free()
	await process_frame


func _actual_arm(player: DungeonPlayer) -> Dictionary:
	var upper := player.weapon_arm.get_node("RightArm_UpperArm_Surface") as Node3D
	var forearm := player.weapon_arm.get_node("RightArm_Forearm_Surface") as Node3D
	return {"shoulder": player.camera.to_local(upper.to_global(ARM.REST_SHOULDER)), "elbow": player.camera.to_local(upper.to_global(ARM.REST_ELBOW)), "wrist": player.camera.to_local(forearm.to_global(ARM.REST_WRIST)), "forearm_elbow": player.camera.to_local(forearm.to_global(ARM.REST_ELBOW))}


func _check_geometry(player: DungeonPlayer, context: String) -> void:
	var actual := _actual_arm(player)
	var upper := (actual.shoulder as Vector3).distance_to(actual.elbow)
	var forearm := (actual.elbow as Vector3).distance_to(actual.wrist)
	_check(absf(upper - IK.UPPER_LENGTH) < 0.00002 and absf(forearm - IK.FOREARM_LENGTH) < 0.00002, "Actual sleeve segment lengths must remain fixed: " + context)
	_check((actual.elbow as Vector3).distance_to(actual.forearm_elbow) < 0.00002, "Actual upper/forearm meshes must share the same elbow: " + context)
	_check((actual.wrist as Vector3).distance_to(player.weapon_pivot.transform * ARM.REST_WRIST) < 0.00002, "Actual sleeve wrist must remain on the final sword/glove: " + context)
	_check(float(player._hand_contacts.sword.error) < 0.00001, "Actual glove contact must remain attached: " + context)
	var recorded: Dictionary = player._joint_landmarks.sword
	for joint: String in ["shoulder", "elbow", "wrist"]:
		_check((actual[joint] as Vector3).is_finite() and (actual[joint] as Vector3).distance_to(player.camera.to_local(recorded[joint])) < 0.00002, "Recorded landmarks must describe the actual transformed mesh: " + context + "/" + joint)


func _check_arm_equal(actual: Dictionary, expected: Dictionary, context: String) -> void:
	for joint: String in ["shoulder", "elbow", "wrist"]:
		var error := (actual[joint] as Vector3).distance_to(expected[joint])
		_check(error < 0.00002, context + "/" + joint + " (error %.9f m)" % error)


func _near_pose(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.00002 and a.basis.is_equal_approx(b.basis)


func _analytical_clips() -> Dictionary:
	var clips := {}
	for name: String in DATA.RIGHT_ARM_REQUIRED_CLIPS:
		var sword: Array = []
		var shield: Array = []
		var joints: Array = []
		var elbow_local := ARM.REST_WRIST + Vector3(0.7, -0.2, 0.5).normalized() * IK.FOREARM_LENGTH
		var shoulder_local := elbow_local + Vector3(0.4, 0.2, 0.8).normalized() * IK.UPPER_LENGTH
		for index in range(3):
			var angle := 0.65 if index == 1 and name != "idle" else 0.0
			var pose := ARM.SOURCE_READY * Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
			var q := pose.basis.get_rotation_quaternion()
			var time := float(index) * 0.5
			sword.append({"time_seconds": time, "position": _array(pose.origin), "rotation_xyzw": [q.x, q.y, q.z, q.w]})
			shield.append({"time_seconds": time, "position": [-0.35, -0.2, -0.6], "rotation_xyzw": [0, 0, 0, 1]})
			joints.append({"time_seconds": time, "shoulder": _array(pose * shoulder_local), "elbow": _array(pose * elbow_local), "wrist": _array(pose * ARM.REST_WRIST)})
		var raw := {"kind": "attack" if name in DATA.ATTACK_CLIPS else "locomotion", "duration_seconds": 1.0, "loop": name in ["run", "air"], "tracks": {"sword": sword, "shield": shield}, "right_arm": joints}
		if name in DATA.ATTACK_CLIPS:
			raw["timing"] = {"windup_seconds": 0.25, "active_seconds": 0.5, "hit_seconds": 0.25, "recovery_seconds": 0.25}
		var decoded := DATA._decode_clip(name, raw, 2)
		if not decoded.is_empty(): clips[name] = decoded
	# Current Mac locomotion includes walk and owns its authored carry framing.
	# Reuse the validated analytical run track for that input; omitting walk
	# selects the legacy shield-aligned carry offset instead of this key's pose.
	if clips.has("run"):
		clips["walk"] = clips["run"].duplicate(true)
	return clips


func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _mesh_ids(player: DungeonPlayer) -> Array[int]:
	var ids: Array[int] = []
	for part in player.weapon_arm.find_children("*", "MeshInstance3D", true, false):
		ids.append((part as MeshInstance3D).mesh.get_instance_id())
	return ids


func _inventory_digest() -> String:
	var bag := ExpeditionSession.capture_snapshot().inventory as ExpeditionInventory
	if bag == null: return "none"
	return JSON.stringify({"slots": bag.slots, "equipment": bag.equipment, "equipment_data": bag.equipment_data}).sha256_text()


func _source_hashes() -> Dictionary:
	var result := {}
	for path: String in [DATA.MANIFEST_PATH, "res://scripts/player.gd", "res://scripts/reference_sword_motion.gd", "res://scripts/reference_sword_arm.gd", "res://scripts/sword_long_grip_visual.gd", "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return result


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
