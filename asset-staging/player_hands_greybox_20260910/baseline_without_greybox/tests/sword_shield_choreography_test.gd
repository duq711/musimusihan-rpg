extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const MOTION := preload("res://scripts/first_person_motion.gd")
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const DT := 1.0 / 120.0
const STATIC_GRIP := preload("res://tests/sword_long_grip_test.gd")
const VARIANTS: Array[String] = ["right_diagonal", "left_reverse", "overhead"]
const PALM := Vector3(0, -0.019, -0.0825)

var failures: Array[String] = []
var metrics: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_phase_seams()
	_test_sweep_knot_velocity()
	var original := ExpeditionSession.capture_snapshot()
	var original_inventory := _inventory_fingerprint(original.inventory)
	var initial_cursor := Input.mouse_mode
	var initial_pause := paused
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var fixture := _fixture()
	await physics_frame
	var player := fixture.player as DungeonPlayer
	_test_actual_trajectories(player)
	_test_actual_clash_recovery(fixture)
	_test_guard_raise_and_reversal(player)
	var control_fixture := _fixture()
	_test_actual_impact_and_pause(player, control_fixture.player as DungeonPlayer)
	_report_anatomy_metrics()
	paused = initial_pause
	(fixture.viewport as SubViewport).queue_free()
	(control_fixture.viewport as SubViewport).queue_free()
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and _inventory_fingerprint(original.inventory) == original_inventory, "choreography checks must preserve the original expedition and inventory contents")
	_check(Input.mouse_mode == initial_cursor and paused == initial_pause, "choreography checks must preserve cursor and pause state")
	for failure in failures:
		push_error(failure)
	print("SWORD SHIELD CHOREOGRAPHY %s: continuous phase/knot velocity, three actual 120 Hz blade paths, modeled clash recovery without snapping, real wrist/limb/marker contacts, reversible shield raising, recoil and pause/aim isolation" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_phase_seams() -> void:
	for variant: String in VARIANTS:
		for charge: float in [0.0, 1.0]:
			var context := "%s charge %.0f" % [variant, charge]
			var duration := lerpf(0.47, 0.68, charge)
			var windup := MOTION.sword("windup", 0.22, charge, false, true, variant)
			var active_start := MOTION.sword("active", 0.0, charge, false, true, variant)
			var active_end := MOTION.sword("active", CHOREOGRAPHY.ACTIVE_SECONDS, charge, false, true, variant)
			var recovery_start := MOTION.sword("recovery", 0.0, charge, false, true, variant)
			var recovery_end := MOTION.sword("recovery", duration, charge, false, true, variant)
			var ready := MOTION.sword("ready", 0.0, charge, false, true, variant)
			_check(windup.is_equal_approx(active_start), context + " sword must preserve its complete transform at the windup/active boundary")
			_check(active_end.is_equal_approx(recovery_start), context + " sword must preserve its complete transform at the active/recovery boundary")
			_check(recovery_end.is_equal_approx(ready), context + " sword must return continuously to ready")
			for seam: Array in [["windup", 0.22, "active", 0.0], ["active", CHOREOGRAPHY.ACTIVE_SECONDS, "recovery", 0.0], ["recovery", duration, "ready", 0.0]]:
				var before := CHOREOGRAPHY.shield(0.0, 0.0, str(seam[0]), float(seam[1]), charge, variant)
				var after := CHOREOGRAPHY.shield(0.0, 0.0, str(seam[2]), float(seam[3]), charge, variant)
				_check(before.is_equal_approx(after), context + " supporting shield must also remain continuous across " + str(seam[0]))
				var roll_before := CHOREOGRAPHY.wrist_roll(str(seam[0]),float(seam[1]),charge,variant)
				var roll_after := CHOREOGRAPHY.wrist_roll(str(seam[2]),float(seam[3]),charge,variant)
				_check(is_equal_approx(roll_before,roll_after), context + " gripping wrist must remain continuous across " + str(seam[0]))


func _test_sweep_knot_velocity() -> void:
	_check(is_equal_approx(MOTION.SWORD_HIT_TIME, 0.055) and is_equal_approx(MOTION.SWORD_ACTIVE_END, 0.16), "paired choreography must leave the solo-sword presentation clocks intact")
	var step := 0.00001
	for variant: String in VARIANTS:
		for charge: float in [0.0, 1.0]:
			for time: float in [CHOREOGRAPHY.DEFLECTION_SECONDS, CHOREOGRAPHY.HIT_SECONDS]:
				var before := CHOREOGRAPHY.sword("active", time - step, charge, variant)
				var at := CHOREOGRAPHY.sword("active", time, charge, variant)
				var after := CHOREOGRAPHY.sword("active", time + step, charge, variant)
				var incoming := (at.origin - before.origin) / step
				var outgoing := (after.origin - at.origin) / step
				var angular_in := _angular_delta(before.basis, at.basis) / step
				var angular_out := _angular_delta(at.basis, after.basis) / step
				var context := "%s charge %.0f at %.6fs" % [variant, charge, time]
				_check(incoming.distance_to(outgoing) < 0.04 and angular_in.distance_to(angular_out) < 0.08, "The actual sweep must carry continuous linear/angular velocity through its contact knot: " + context)
				_check(incoming.length() + angular_in.length() > 0.1, "An unopposed swing must not stop at the intermediate deflection/body-contact knot: " + context)


func _angular_delta(first: Basis, second: Basis) -> Vector3:
	var rotation := first.get_rotation_quaternion().inverse() * second.get_rotation_quaternion()
	if rotation.w < 0.0: rotation = -rotation
	var vector := Vector3(rotation.x, rotation.y, rotation.z)
	return vector.normalized() * (2.0 * atan2(vector.length(), rotation.w)) if vector.length() > 0.00000001 else Vector3.ZERO


func _fixture() -> Dictionary:
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	fixture["viewport"] = viewport
	(fixture.chest as Node3D).position = Vector3(12, 0, 12)
	var player := fixture.player as DungeonPlayer
	player.position = Vector3(0, 1, 2)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._pitch = 0.0
	player.set_torch_enabled(false)
	_check(viewport.own_world_3d and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "actual player fixture must isolate its world and never sample hardware input")
	_reset_pose_clock(player)
	return fixture


func _reset_pose_clock(player: DungeonPlayer) -> void:
	player.cancel_sword_attack()
	player.set_sword_attack_mode("cycle")
	player.stamina = player.MAX_STAMINA
	player.health = player.MAX_HEALTH
	player.velocity = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player._camera_shake = 0.0
	player._motion_clock = 0.0
	player._motion_speed = 0.0
	player._motion_look_sway = Vector2.ZERO
	player._motion_previous_look = Vector2.ZERO
	player._motion_equip_elapsed = MOTION.EQUIP_DURATION
	player._update_viewmodel(0.0)


func _test_actual_trajectories(player: DungeonPlayer) -> void:
	var blade_tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
	_check(blade_tip != null, "trajectory must sample the actual imported BladeTip marker")
	if blade_tip == null:
		return
	for charge: float in [0.0, 1.0]:
		var trajectories: Dictionary = {}
		for variant: String in VARIANTS:
			_reset_pose_clock(player)
			player.set_sword_attack_mode(variant)
			var aim_before := player.head.global_transform
			var camera_basis_before := player.camera.global_basis
			var accepted := bool(player.begin_sword_attack().accepted)
			_check(accepted, "actual trajectory must begin " + variant)
			if not accepted:
				continue
			# Short attacks queue release immediately; charged attacks hold until
			# the existing automatic commit. Both use the real production clock.
			player.attack_release_requested = charge == 0.0
			var samples := PackedVector3Array()
			var seen_phases: Dictionary = {}
			var frame := 0
			while player.combat_state != DungeonPlayer.CombatState.READY and frame < 360:
				_tick(player, DT, false)
				var phase := str(player.get_first_person_motion_snapshot().phase)
				seen_phases[phase] = true
				_audit_actual_arms(player, "%s charge %.0f %s frame %d" % [variant, charge, phase, frame])
				if player.combat_state == DungeonPlayer.CombatState.ACTIVE:
					samples.append(player.camera.to_local(blade_tip.global_position))
				frame += 1
			_check(player.combat_state == DungeonPlayer.CombatState.READY and seen_phases.has("windup") and seen_phases.has("active") and seen_phases.has("recovery"), "actual 120 Hz sequence must traverse windup, active, recovery and ready: " + variant)
			_check(is_equal_approx(player.attack_charge, charge), "trajectory must actually reach the requested charge endpoint")
			_check(player.head.global_transform.is_equal_approx(aim_before) and player.camera.global_basis.is_equal_approx(camera_basis_before), "arm choreography must not steer the player's head or camera aim")
			_check(samples.size() >= floori(player.get_melee_active_duration() / DT) - 1, "each real paired active window must provide its full 120 Hz blade trajectory")
			trajectories[variant] = samples
		for first in VARIANTS.size():
			for second in range(first + 1, VARIANTS.size()):
				if not trajectories.has(VARIANTS[first]) or not trajectories.has(VARIANTS[second]):
					continue
				var a: PackedVector3Array = trajectories[VARIANTS[first]]
				var b: PackedVector3Array = trajectories[VARIANTS[second]]
				_check(a.size() == b.size(), "different attack styles must retain the same actual active duration")
				var squared_distance := 0.0
				for index in mini(a.size(), b.size()):
					squared_distance += a[index].distance_squared_to(b[index])
				var rms := sqrt(squared_distance / float(maxi(1, mini(a.size(), b.size()))))
				_check(rms > 0.08, "actual BladeTip paths must be meaningfully distinct for %s/%s charge %.0f; RMS separation %.4fm" % [VARIANTS[first], VARIANTS[second], charge, rms])


func _test_guard_raise_and_reversal(player: DungeonPlayer) -> void:
	_reset_pose_clock(player)
	_check(is_zero_approx(_raise_progress(player)), "actual guard must begin lowered")
	_audit_actual_arms(player, "held ready")
	_guard_steps(player, 12, true)
	_check(_raise_progress(player) > 0.0 and _raise_progress(player) < 1.0, "raising must expose intermediate progress rather than switch directly")
	var previous := player.shield_pivot.transform
	var sword_before := player.weapon_pivot.transform
	_tick(player, 0.000001, false)
	_check(_near_transform(player.shield_pivot.transform, previous) and _near_transform(player.weapon_pivot.transform, sword_before), "reversing a partly raised shield must preserve both hand-held poses at the reversal instant")
	_guard_steps(player, 6, false)
	previous = player.shield_pivot.transform
	sword_before = player.weapon_pivot.transform
	_tick(player, 0.000001, true)
	_check(_near_transform(player.shield_pivot.transform, previous) and _near_transform(player.weapon_pivot.transform, sword_before), "raising again during lowering must remain continuous")
	_guard_steps(player, 36, true)
	_check(is_equal_approx(_raise_progress(player), 1.0), "held guard must reach fully raised")
	_guard_steps(player, 40, false)
	_check(is_zero_approx(_raise_progress(player)), "released guard must return fully lowered")


func _test_actual_clash_recovery(fixture: Dictionary) -> void:
	var player := fixture.player as DungeonPlayer
	var enemy := DungeonEnemy.new()
	enemy.configure("검 충돌 회복 검증", 2000.0, 21.0, 0.0, Color(0.3, 0.3, 0.3))
	enemy.position = Vector3(12, 1, -12)
	(fixture.stage as Node3D).add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(player, null, fixture.stage)
	_check(enemy.sword_blade != null, "Clash recovery must use an actual armed enemy blade")
	if enemy.sword_blade == null:
		enemy.free()
		return
	var tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
	for variant: String in VARIANTS:
		for charge: float in [0.0, 1.0]:
			_reset_pose_clock(player)
			player.set_sword_attack_mode(variant)
			enemy._set_state(DungeonEnemy.AIState.IDLE)
			enemy.sword_blade.global_position = Vector3(12, 2, -12)
			var accepted := bool(player.begin_sword_attack().accepted)
			_check(accepted, "Real clash recovery fixture must begin " + variant)
			if not accepted: continue
			player.attack_release_requested = charge == 0.0
			# The combat state machine performs the normal release/auto-commit.
			# Only its windup sampling is abbreviated; no phase or charge is set.
			_tick(player, 0.2201 if charge == 0.0 else 1.2401, false)
			var clash_time := 0.05 if charge == 0.0 else 0.075
			while player.combat_state == DungeonPlayer.CombatState.ACTIVE and player.state_time < clash_time - 0.000001:
				_tick(player, minf(DT, clash_time - player.state_time), false)
			_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "Clash fixture must still be in its real active window")
			if player.combat_state != DungeonPlayer.CombatState.ACTIVE: continue
			enemy._set_state(DungeonEnemy.AIState.ACTIVE)
			# Contact placement is controlled here to isolate recovery at several
			# real cut phases. sword_clash_test separately verifies natural sweeps.
			var player_proxy := player.get_sword_clash_proxy()
			var enemy_proxy := enemy.get_sword_clash_proxy()
			enemy.sword_blade.global_position += (player_proxy.center as Vector3) - (enemy_proxy.center as Vector3)
			var before := _equipment_and_wrist_poses(player)
			var stamina := player.stamina
			var health := player.health
			var enemy_health := enemy.health
			var aim := player.head.global_transform
			var context := "%s charge %.0f clash %.3fs" % [variant, charge, clash_time]
			var clashed := player.try_sword_clash(enemy)
			_check(clashed and player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER, "Actual modeled contact must begin a real clash recovery: " + context)
			if not clashed: continue
			player._update_viewmodel(0.0)
			var after := _equipment_and_wrist_poses(player)
			for part: String in before:
				_check(_near_transform(before[part], after[part]), "Clash must preserve the exact contact-time " + part + " pose instead of snapping to the normal active-end pose: " + context)
			_check(not player.try_sword_clash(enemy), "A resolved clash cannot restart or charge the recovery again")
			var previous_weapon := player.weapon_pivot.transform
			var previous_shield := player.shield_pivot.transform
			var previous_tip := player.camera.to_local(tip.global_position)
			var frame := 0
			while player.combat_state == DungeonPlayer.CombatState.RECOVERY and frame < 100:
				_tick(player, DT, false)
				var weapon := player.weapon_pivot.transform
				var shield := player.shield_pivot.transform
				var tip_position := player.camera.to_local(tip.global_position)
				_check(weapon.origin.distance_to(previous_weapon.origin) < 0.04 and shield.origin.distance_to(previous_shield.origin) < 0.04 and tip_position.distance_to(previous_tip) < 0.12, "120Hz clash recovery must return the actual equipment continuously: " + context)
				_check(weapon.basis.get_rotation_quaternion().angle_to(previous_weapon.basis.get_rotation_quaternion()) < deg_to_rad(12) and shield.basis.get_rotation_quaternion().angle_to(previous_shield.basis.get_rotation_quaternion()) < deg_to_rad(12), "Clash recovery must not hide an angular snap between its endpoints: " + context)
				_audit_actual_arms(player, context + " recovery frame %d" % frame)
				if frame == 4:
					var frozen := _equipment_and_wrist_poses(player)
					var time_before := player.state_time
					paused = true
					_tick(player, 2.0, false)
					_check(player.state_time == time_before and _equipment_and_wrist_poses(player) == frozen, "Pausing an actual clash must freeze its saved recovery pose and clock")
					paused = false
				previous_weapon = weapon
				previous_shield = shield
				previous_tip = tip_position
				frame += 1
			_check(player.combat_state == DungeonPlayer.CombatState.READY, "Clash recovery must finish at READY within the normal charge-dependent recovery duration")
			_check(is_equal_approx(player.stamina, stamina) and is_equal_approx(player.health, health) and is_equal_approx(enemy.health, enemy_health), "Clash recovery must neither spend again nor leak its cancelled body hit")
			_check(player.head.global_transform.is_equal_approx(aim), "Real clash presentation must preserve the player's aim")
	enemy.free()
	_reset_pose_clock(player)


func _equipment_and_wrist_poses(player: DungeonPlayer) -> Dictionary:
	# Camera-local wrist frames remove the intentional translational camera
	# shake, while still inspecting the real fitted arm and equipment nodes.
	var inverse_camera := player.camera.global_transform.affine_inverse()
	return {"weapon": player.weapon_pivot.transform, "shield": player.shield_pivot.transform, "right_wrist": inverse_camera * player.weapon_arm.global_transform, "left_wrist": inverse_camera * player.shield_arm.global_transform}


func _guard_steps(player: DungeonPlayer, count: int, blocking: bool) -> void:
	for frame in count:
		var before := _raise_progress(player)
		_tick(player, DT, blocking)
		var after := _raise_progress(player)
		_check(after >= 0.0 and after <= 1.0 and (after >= before if blocking else after <= before), "actual shield raise/lower progress must be bounded and monotonic")
		_audit_actual_arms(player, "guard %s frame %d" % ["raising" if blocking else "lowering", frame])


func _test_actual_impact_and_pause(player: DungeonPlayer, control: DungeonPlayer) -> void:
	_reset_pose_clock(player)
	_reset_pose_clock(control)
	for _frame in 48:
		_tick(player, DT, true)
		_tick(control, DT, true)
	var aim_before := player.head.global_transform
	var camera_basis_before := player.camera.global_basis
	var result := player.receive_attack(18.0, player.global_position + Vector3(0, 0, -2))
	_check(bool(result.blocked) and not bool(result.parried), "recoil must originate from an actual ordinary blocked attack")
	_check(float(player.get_first_person_motion_snapshot().shield_impact_remaining) > 0.0, "real block must start the shield impact clock")
	var peak_backwards := 0.0
	for frame in 36:
		_tick(player, DT, true)
		_tick(control, DT, true)
		# A second actual fixture follows the same clock without a hit. It
		# removes ordinary breathing motion from the observed recoil measure.
		var displacement := player.shield_pivot.position - control.shield_pivot.position
		peak_backwards = maxf(peak_backwards, displacement.dot(Vector3.BACK))
		_audit_actual_arms(player, "actual shield impact frame %d" % frame)
		if frame == 4:
			var snapshot := player.get_first_person_motion_snapshot()
			var shield_before := player.shield_pivot.transform
			var sword_before := player.weapon_pivot.transform
			var time_before := player.state_time
			var wrist_before := player.weapon_arm.global_transform
			paused = true
			_tick(player, 2.0, true)
			var frozen := player.get_first_person_motion_snapshot()
			_check(frozen.motion_time == snapshot.motion_time and frozen.shield_raise_progress == snapshot.shield_raise_progress and frozen.shield_impact_remaining == snapshot.shield_impact_remaining and player.state_time == time_before, "pause must freeze the production guard, impact and combat clocks")
			_check(player.shield_pivot.transform == shield_before and player.weapon_pivot.transform == sword_before and player.weapon_arm.global_transform == wrist_before, "pause must freeze the actual equipment and anatomical wrist poses")
			paused = false
	_check(peak_backwards > 0.03, "real blocked recoil must visibly move the actual shield toward the defender")
	# At the same final timestamp, sample the zero remainder after the last
	# 120 Hz timer decrement; no extra simulation time or fake pose is added.
	player._update_viewmodel(0.0)
	control._update_viewmodel(0.0)
	_check(float(player.get_first_person_motion_snapshot().shield_impact_remaining) < 0.00001 and player.shield_pivot.transform.is_equal_approx(control.shield_pivot.transform), "actual shield recoil must return to its held guard after 0.30 seconds")
	_check(player.head.global_transform.is_equal_approx(aim_before) and player.camera.global_basis.is_equal_approx(camera_basis_before), "real shield impact and arm fitting must preserve head-owned aim")


func _audit_actual_arms(player: DungeonPlayer, context: String) -> void:
	var snapshot := player.get_first_person_motion_snapshot()
	var landmarks: Dictionary = snapshot.joint_landmarks
	var contacts: Dictionary = snapshot.hand_contacts
	failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
	failures.append_array(STATIC_GRIP.audit_sleeve_connections(player, context))
	var sword_marker := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
	_check(sword_marker != null and contacts.has("sword"), "authored sword grip must expose the actual canonical contact: " + context)
	if sword_marker != null and contacts.has("sword"):
		var contact: Dictionary = contacts.sword
		_check((contact.actual as Vector3).distance_to(sword_marker.global_position) < 0.0001 and (contact.target as Vector3).distance_to(sword_marker.global_position) < 0.0001, "authored hand and canonical sword contact must remain rigidly joined: " + context)
		var grip_screen := player.camera.unproject_position(sword_marker.global_position)
		var normalized := grip_screen / player.camera.get_viewport().get_visible_rect().size
		_check(not player.camera.is_position_behind(sword_marker.global_position) and normalized.x > 0.04 and normalized.x < 0.94 and normalized.y > 0.015 and normalized.y < 0.92, "Sword grip leaves the readable first-person frame: " + context + " " + str(normalized))
	for role: String in ["shield"]:
		if not landmarks.has(role) or not contacts.has(role):
			_check(false, "actual pose must expose " + role + " landmarks and contacts: " + context)
			continue
		var arm := player.weapon_arm if role == "sword" else player.shield_arm
		var marker := (player.sword_visual_root.find_child("HandGrip", true, false) if role == "sword" else player.shield_model.find_child("RearGrip", true, false)) as Node3D
		var forearm := arm.get("_forearm") as Node3D
		var upper := arm.get("_upper_arm") as Node3D
		if marker == null or forearm == null or upper == null:
			_check(false, "actual imported " + role + " grip and both arm meshes are required")
			continue
		var wrist := arm.global_position
		var elbow := forearm.to_global(Vector3(0, 0, 0.26))
		var shoulder := upper.to_global(Vector3(0, 0, 0.60))
		var limb: Dictionary = landmarks[role]
		var contact: Dictionary = contacts[role]
		var palm := arm.global_transform * PALM
		var contact_error := maxf(palm.distance_to(marker.global_position), maxf((contact.actual as Vector3).distance_to(marker.global_position), (contact.target as Vector3).distance_to(marker.global_position)))
		var joint_error := maxf((limb.wrist as Vector3).distance_to(wrist), maxf((limb.elbow as Vector3).distance_to(elbow), (limb.shoulder as Vector3).distance_to(shoulder)))
		joint_error = maxf(joint_error, maxf(forearm.to_global(Vector3.ZERO).distance_to(wrist), upper.to_global(Vector3(0, 0, 0.26)).distance_to(elbow)))
		if not metrics.has(role):
			metrics[role] = {"min_alignment": 1.0, "max_forearm": 0.0, "max_upper": 0.0, "max_contact": 0.0, "max_joint_error": 0.0}
		_record_extreme(role, "min_alignment", arm.global_basis.z.normalized().dot((elbow - wrist).normalized()), context, true)
		_record_extreme(role, "max_forearm", wrist.distance_to(elbow), context)
		_record_extreme(role, "max_upper", elbow.distance_to(shoulder), context)
		_record_extreme(role, "max_contact", contact_error, context)
		# A biomechanically valid path can still disappear below the first-person
		# frame. Keep the authored gripping hand readable through its recovery.
		if role == "sword":
			var grip_screen := player.camera.unproject_position(marker.global_position)
			var viewport_size := player.camera.get_viewport().get_visible_rect().size
			var normalized := grip_screen / viewport_size
			_check(not player.camera.is_position_behind(marker.global_position) and normalized.x > 0.04 and normalized.x < 0.94 and normalized.y > 0.015 and normalized.y < 0.92, "Sword grip leaves the readable first-person frame: " + context + " " + str(normalized))
		elif player.combat_state == DungeonPlayer.CombatState.READY:
			var grip_screen := player.camera.unproject_position(marker.global_position)
			var viewport_size := player.camera.get_viewport().get_visible_rect().size
			var normalized := grip_screen / viewport_size
			_check(not player.camera.is_position_behind(marker.global_position) and normalized.x > 0.04 and normalized.x < 0.94 and normalized.y > 0.015 and normalized.y < 0.92, "Shield grip leaves the readable carry/guard frame: " + context + " " + str(normalized))
		_record_extreme(role, "max_joint_error", joint_error, context)
	_check(contacts.size() == 2 and int(snapshot.visible_arm_count) == 2, "paired sword/shield choreography must expose exactly its two anatomical hand contacts")


func _record_extreme(role: String, key: String, value: float, context: String, minimum: bool = false) -> void:
	if not is_finite(value):
		_check(false, "non-finite actual arm geometry: " + role + " " + key + " " + context)
		return
	var is_extreme := value < float(metrics[role][key]) if minimum else value > float(metrics[role][key])
	if is_extreme:
		metrics[role][key] = value
		metrics[role][key + "_pose"] = context


func _report_anatomy_metrics() -> void:
	for role: String in ["shield"]:
		_check(metrics.has(role), "must inspect actual " + role + " anatomy")
		if not metrics.has(role):
			continue
		var result: Dictionary = metrics[role]
		print("CHOREOGRAPHY ACTUAL ANATOMY ", role, " ", JSON.stringify(result))
		for limit: Array in [["min_alignment", 0.5, true], ["max_forearm", 0.46, false], ["max_upper", 0.50, false], ["max_contact", 0.0001, false], ["max_joint_error", 0.0001, false]]:
			var key := str(limit[0])
			var value := float(result[key])
			var passed := value > float(limit[1]) if bool(limit[2]) else value <= float(limit[1])
			_check(passed, "%s %s physical limit %.4f failed at %.6f (%s)" % [role, key, float(limit[1]), value, str(result.get(key + "_pose", "no pose"))])


func _near_transform(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.00005 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.002


func _raise_progress(player: DungeonPlayer) -> float:
	return float(player.get_first_person_motion_snapshot().shield_raise_progress)


func _tick(player: DungeonPlayer, delta: float, block_requested: bool) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, block_requested)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null:
		return "no_inventory"
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text()


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message):
		failures.append(message)
