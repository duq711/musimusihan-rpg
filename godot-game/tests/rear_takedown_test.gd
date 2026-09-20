extends "res://tests/dagger_assassination_test.gd"
## Shared fixture construction only; all new checks drive the production rear
## reservation and its real mesh, skin, inventory and death/reward consumers.
const REAR := preload("res://scripts/rear_takedown_motion.gd")
const DISMEMBERMENT := preload("res://scripts/creep_dismemberment.gd")
const GAME := preload("res://scripts/game.gd")
const ARM_PREVIEW := preload("res://tests/player_arm_preview.gd")
var reward_game
var reward_hud: DungeonHUD


func _run() -> void:
	if not CREEP.is_available() or not ResourceLoader.exists(DISMEMBERMENT.MODEL_PATH):
		print("REAR TAKEDOWN TEST PASS: licensed split Creep absent; physical execution checks SKIPPED")
		quit(); return
	var original := ExpeditionSession.capture_snapshot()
	var original_items := _inventory_fingerprint(original.inventory)
	var cursor := Input.mouse_mode
	var initial_pause := paused
	var model_hash := FileAccess.get_sha256(DISMEMBERMENT.MODEL_PATH)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	paused = false
	_build_fixture()
	reward_hud = DungeonHUD.new()
	viewport.add_child(reward_hud)
	# Keep the actual game's reward receiver without building its entire map.
	reward_game = GAME.new()
	reward_game.inventory = bag
	reward_game.hud = reward_hud
	reward_game.portal_material = StandardMaterial3D.new()
	_thrust_grip_adapter_regression()
	await _fresh_idle_preparation_regression()
	await _eligibility_and_profiles()
	await _ordered_execution("rusted_sword", false)
	await _ordered_execution("forged_longsword", true)
	await _ordered_execution("rusted_sword", false, .86)
	await _ordered_execution("rusted_sword", false, 1.49)
	await _wrist_motion_sequence()
	await _ordinary_attack_grip_restoration()
	await _cancellation_boundaries()
	await _blocked_approach()
	await _blocked_initial_approach()
	await _blocked_preparation_retreat()
	await _clear_targets()
	reward_game.free()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	paused = initial_pause
	_check(original == ExpeditionSession.capture_snapshot() and original_items == _inventory_fingerprint(original.inventory), "rear trial must restore the original expedition, inventory identity and instances")
	_check(cursor == Input.mouse_mode and paused == initial_pause, "rear trial must preserve desktop cursor and pause state")
	_check(model_hash == FileAccess.get_sha256(DISMEMBERMENT.MODEL_PATH), "rear execution must preserve the licensed split model bytes")
	for failure in failures: push_error("REAR TAKEDOWN: " + failure)
	print("REAR TAKEDOWN REPORT: ", JSON.stringify(report))
	print("REAR TAKEDOWN TEST %s: unaware rear gates, actual back/front skin/full-blade/straight extraction and blade-clear ragdoll, ordered long tick, intact head and one death/reward, cancellation and preserved session" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _thrust_grip_adapter_regression() -> void:
	# Check the actual supplied rig under its adapter, not merely the two
	# helper functions against one another. Changing grip cannot stretch the
	# hand, move its palm anchor, or leave a residual pose on ordinary attacks.
	var grip = player.SWORD_LONG_GRIP.new()
	stage.add_child(grip)
	grip.setup()
	var adapter: Node3D = grip.get_node("SuppliedRightArm")
	var rig := adapter.find_child("Skeleton3D", true, false) as Skeleton3D
	var wrist_index := rig.find_bone("wrist")
	var default_frame := adapter.transform
	var default_bones: Array[Transform3D] = []
	for index in rig.get_bone_count(): default_bones.append(rig.get_bone_pose(index))
	var maximum_palm_error := 0.0
	var maximum_wrist_error := 0.0
	for amount: float in [-1.0, 0.0, .25, .5, .75, 1.0, 2.0, 0.0]:
		grip.set_thrust_grip(amount)
		var clamped := clampf(amount, 0.0, 1.0)
		var palm: Vector3 = grip.to_local(adapter.to_global(adapter.GRIP_CENTER))
		var wrist := grip.to_local(rig.to_global(rig.get_bone_global_pose(wrist_index).origin))
		var expected_palm: Vector3 = grip.GRIP_CENTER + grip.THRUST_CONTACT_OFFSET * clamped
		var palm_error: float = palm.distance_to(expected_palm)
		var wrist_error: float = wrist.distance_to(grip.wrist_local(clamped))
		maximum_palm_error = maxf(maximum_palm_error, palm_error)
		maximum_wrist_error = maxf(maximum_wrist_error, wrist_error)
		_check(palm_error < .0001 and wrist_error < .0001, "thrust grip keeps the planned palm offset and reports the true skinned wrist at blend %.2f" % amount)
		_check(adapter.basis.get_scale().is_equal_approx(Vector3.ONE) and adapter.basis.determinant() > .9999, "thrust grip is a rigid rotation without hand stretch or reflection")
		for index in rig.get_bone_count():
			var pose := rig.get_bone_pose(index)
			_check(pose.origin.is_equal_approx(default_bones[index].origin) and pose.basis.get_scale().is_equal_approx(default_bones[index].basis.get_scale()), "diagonal finger wrapping preserves bone lengths and scale")
	_check(adapter.transform.is_equal_approx(default_frame) and is_zero_approx(grip.thrust_grip_amount), "returning grip amount to zero restores the exact normal hand frame")
	for index in rig.get_bone_count():
		_check(rig.get_bone_pose(index).is_equal_approx(default_bones[index]), "returning grip amount to zero restores every original finger bone rotation")
	grip.set_thrust_grip(NAN)
	_check(adapter.transform.is_equal_approx(default_frame), "nonfinite grip input cannot contaminate the actual rig")
	report.append({"case": "thrust_grip_adapter", "maximum_actual_palm_anchor_error_m": maximum_palm_error, "maximum_actual_wrist_api_error_m": maximum_wrist_error, "ordinary_frame_restored": adapter.transform.is_equal_approx(default_frame), "contact_scope": "Anchor and bone consistency; skin contact checked in GPU closeups."})
	grip.queue_free()


func _check_restored_grip(subject: DungeonPlayer, context: String) -> void:
	var adapter := subject.weapon_arm.get_node_or_null("SuppliedRightArm") as Node3D
	_check(adapter != null, context + ": supplied right hand is retained")
	if adapter == null: return
	_check(is_zero_approx(float(subject.weapon_arm.get("thrust_grip_amount"))), context + ": no rear-thrust grip blend leaks into ordinary combat")
	_check(adapter.transform.is_equal_approx(subject.SWORD_LONG_GRIP.grip_frame(0.0)), context + ": original non-thrust hand frame is restored exactly")


func _ordinary_attack_grip_restoration() -> void:
	await _clear_targets()
	_check(_equip("rusted_sword"), "normal-attack restoration equips the real sword")
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
	player._update_viewmodel(0.0)
	_check_restored_grip(player, "after completed rear execution")
	var result := player.begin_sword_attack()
	_check(bool(result.accepted), "ordinary attack remains available after the rear sequence")
	player.attack_release_requested = true
	var active_seen := false
	var ready_seen := false
	for frame in 80:
		player.advance_combat_state(STEP)
		player._update_viewmodel(STEP)
		active_seen = active_seen or player.combat_state == DungeonPlayer.CombatState.ACTIVE
		player._resolve_active_attack()
		ready_seen = ready_seen or (active_seen and player.combat_state == DungeonPlayer.CombatState.READY)
		_check_restored_grip(player, "ordinary attack tick %d" % frame)
	_check(active_seen and ready_seen, "ordinary attack advances through active swing and recovery with the original grip")
	player.cancel_sword_attack()
	player._update_viewmodel(0.0)
	_check_restored_grip(player, "after ordinary attack cancellation")
	report.append({"case": "ordinary_attack_grip_restoration", "accepted": result.get("accepted", false), "samples": 80, "active_seen": active_seen, "ready_seen": ready_seen, "rear_grip_must_remain_zero": true})


class FreshPreparationDriver extends Node:
	var subject: DungeonPlayer
	var actor
	var capture: Callable
	var tick := 0
	var before_begin := {}
	var begin_result := {}
	var samples: Array[Dictionary] = []

	func _physics_process(delta: float) -> void:
		tick += 1
		if tick == 36:
			before_begin = capture.call()
			begin_result = subject.begin_rear_takedown()
		subject.advance_combat_state(delta)
		subject._update_viewmodel(delta)
		subject._resolve_active_attack()
		actor._resolve_active_attack()
		if tick >= 36:
			var sample: Dictionary = capture.call()
			sample["tick"] = tick
			samples.append(sample)
		if tick >= 35 + int(ceil(REAR.PREPARE_END * 60.0)) + 1:
			set_physics_process(false)


func _fresh_idle_preparation_regression() -> void:
	# Use the same fresh player/rig/inventory fixture and initialization as the
	# actual GPU preview. Reusing the earlier test's arm pose at delta=0 hid a
	# bad preparation path that appeared after a real 0.6-second idle entry.
	var fresh_viewport := ARM_PREVIEW.create_viewport()
	fresh_viewport.size = Vector2i(960, 540)
	fresh_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(fresh_viewport)
	var fixture := ARM_PREVIEW.populate_viewport(fresh_viewport)
	var fresh_world: Node3D = fixture.stage
	var subject: DungeonPlayer = fixture.player
	fixture.chest.position = Vector3(20, 0, 20)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position.y = -.1
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, .2, 20)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	fresh_world.add_child(floor_body)
	subject.position = Vector3(0, .9, 1.15)
	_check(ARM_PREVIEW._equip_weapon(subject.inventory_model, "rusted_sword"), "fresh preparation equips the preview's actual sword")
	subject.inventory_model.equipment.offhand = ""
	subject.inventory_model.changed.emit()
	subject.configure_safe_zone(false)
	subject.set_torch_enabled(false)
	subject._torch_draw_elapsed = 0.0
	subject._sword_draw_elapsed = subject.SWORD_DRAW_DURATION
	subject._motion_equip_elapsed = subject.MOTION.EQUIP_DURATION
	subject.velocity = Vector3.ZERO
	subject.stamina = subject.MAX_STAMINA
	subject.health = subject.MAX_HEALTH
	for settle in 2:
		await physics_frame
		await process_frame
	var actor = CREEP.new()
	actor.configure("새 대기 자세 검수 크리프", 118, 8, 2.2, Color.WHITE)
	actor.position = Vector3(0, .9, 0)
	fresh_world.add_child(actor)
	actor.target = null
	actor.set_process_input(false)
	actor.set_process_unhandled_input(false)
	var driver := FreshPreparationDriver.new()
	driver.subject = subject
	driver.actor = actor
	driver.capture = func() -> Dictionary: return _capture_fresh_preparation(subject)
	driver.process_physics_priority = 100
	fresh_world.add_child(driver)
	driver.set_physics_process(false)
	# The GPU harness warms 10 + 4 process frames at fixed 30fps/60Hz.
	# Await their physics ticks explicitly under this uncapped headless loop.
	for warm in 20: await physics_frame
	var contacts: Dictionary = actor.get_rear_takedown_contacts()
	_check(not contacts.is_empty(), "fresh preparation finds real posed back skin")
	if contacts.is_empty():
		fresh_viewport.queue_free()
		await process_frame
		return
	var aim: Vector3 = (contacts.back as Vector3) - subject.camera.global_position
	subject.rotation.y = atan2(-aim.x, -aim.z)
	subject._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	subject.head.rotation.x = subject._pitch
	subject._update_viewmodel(1.0)
	subject.camera.make_current()
	subject.viewmodel_renderer.sync_view()
	for warm in 8: await physics_frame
	actor.target = subject
	driver.set_physics_process(true)
	while driver.is_physics_processing():
		await physics_frame
		await process_frame
	_check(bool(driver.begin_result.get("accepted", false)), "fresh settled idle accepts the production rear action at tick 36")
	_check(driver.samples.size() >= int(ceil(REAR.PREPARE_END * 60.0)), "fresh preparation retains every 60Hz sample through its boundary")
	var previous: Dictionary = driver.before_begin
	_check(bool(previous.get("actual", {}).get("available", false)), "fresh preparation retains the actual idle rig immediately before begin")
	var maximum_step := 0.0
	var maximum_rotation := 0.0
	var maximum_shoulder := 0.0
	for sample: Dictionary in driver.samples:
		_check(bool(sample.actual.get("available", false)), "fresh preparation reads actual rendered rig bones")
		if not bool(sample.actual.get("available", false)) or not bool(previous.get("actual", {}).get("available", false)): continue
		var delta := actual_joint_step(previous.actual, sample.actual)
		var rotation := basis_angle_degrees(previous.actual.hand_basis_world, sample.actual.hand_basis_world)
		maximum_step = maxf(maximum_step, delta)
		maximum_rotation = maxf(maximum_rotation, rotation)
		maximum_shoulder = maxf(maximum_shoulder, float(sample.shoulder_adjustment_m))
		_check(delta < .12 and rotation < 45.0, "fresh idle-to-preparation real joints cannot snap at %.5fs (%.4fm / %.2fdeg)" % [sample.elapsed, delta, rotation])
		_check(float(sample.shoulder_adjustment_m) <= .045 and float(sample.shoulder_camera_z_m) >= .015, "fresh preparation preserves the interpolated shoulder anchor and keeps it behind the camera at %.5fs" % sample.elapsed)
		_check(absf(float(sample.upper_length_m) - .34) <= .004 and absf(float(sample.forearm_length_m) - .26) <= .004, "fresh preparation preserves the fitted 34/26cm upper/forearm lengths")
		previous = sample
	report.append({"case": "fresh_idle_preparation", "initialization": "same fresh ARM_PREVIEW fixture; completed draw/equip; actual back-skin aim; 35 idle physics ticks before begin at tick36", "before_begin": driver.before_begin, "begin_result": driver.begin_result, "sample_count": driver.samples.size(), "maximum_joint_step_m": maximum_step, "maximum_hand_rotation_degrees": maximum_rotation, "maximum_shoulder_adjustment_m": maximum_shoulder, "samples": driver.samples})
	subject.cancel_execution()
	subject._update_viewmodel(0.0)
	_check_restored_grip(subject, "fresh preparation cancellation")
	_check(actor.health == actor.max_health and actor.dismemberment.severed.is_empty(), "preparation-only regression does not commit a stab or kill")
	fresh_viewport.queue_free()
	await process_frame


func _capture_fresh_preparation(subject: DungeonPlayer) -> Dictionary:
	var actual := measure_wrist_geometry(subject)
	if not bool(actual.get("available", false)): return {"actual": actual, "elapsed": subject.execution_elapsed}
	var requested: Vector3 = subject.SWORD_LONG_GRIP.SOURCE_READY * subject.SWORD_LONG_GRIP.REST_SHOULDER
	if subject.is_execution_active() and not subject._rear_arm_entry.is_empty():
		requested = (subject._rear_arm_entry.shoulder as Vector3).lerp(requested, smoothstep(0, REAR.PREPARE_END, subject.execution_elapsed))
	var shoulder_camera := subject.camera.to_local(actual.shoulder_world)
	var fitted: Dictionary = subject.get_first_person_motion_snapshot().joint_landmarks.get("sword", {})
	return {"actual": actual, "elapsed": subject.execution_elapsed, "weapon_transform": subject.weapon_pivot.global_transform,
		"requested_shoulder_camera": requested, "actual_shoulder_camera": shoulder_camera,
		"shoulder_adjustment_m": shoulder_camera.distance_to(requested), "shoulder_camera_z_m": shoulder_camera.z,
		"upper_length_m": (fitted.shoulder as Vector3).distance_to(fitted.elbow),
		"forearm_length_m": (fitted.elbow as Vector3).distance_to(fitted.wrist)}


func _new_rear_actor(weapon := "rusted_sword"):
	await _clear_targets()
	player.reset_body_health()
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	_check(_equip(weapon), "rear fixture must equip its actual inventory item: " + weapon)
	var actor = _spawn(true)
	reward_game.enemies_alive = 1
	reward_game.loot_count = 0
	actor.defeated.connect(reward_game._on_enemy_defeated)
	_prepare_player(actor, Vector3(0, 0, 1.15))
	_settle_rear_idle(actor)
	await physics_frame
	await physics_frame
	return actor


func _settle_rear_idle(actor) -> void:
	# The inherited dagger fixture updates once with delta=0 after cancelling
	# the previous action. Let the real 100ms pose handoff finish, as it does
	# in a fresh gameplay idle, instead of carrying a prior extraction pose.
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
	player.velocity = Vector3.ZERO
	var contacts: Dictionary = actor.get_rear_takedown_contacts()
	if not contacts.is_empty():
		var aim: Vector3 = (contacts.back as Vector3) - player.camera.global_position
		player.rotation.y = atan2(-aim.x, -aim.z)
		player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
		player.head.rotation.x = player._pitch
	for tick in 36:
		player.advance_combat_state(STEP)
		player._update_viewmodel(STEP)
		player._resolve_active_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.READY and not player.is_execution_active(), "rear fixture settles through the real idle coordinator without starting an attack")
	_check_restored_grip(player, "settled rear fixture idle")


func _eligibility_and_profiles() -> void:
	var actor = await _new_rear_actor()
	_check(actor.can_begin_rear_takedown(player) and player.get_rear_takedown_target() == actor, "real upright unaware rear target must be selectable")
	for yaw: float in [0.0, 1.23, PI]:
		actor.rotation.y = yaw
		for degrees: float in [-56.0, -54.0, 0.0, 54.0, 56.0, 180.0]:
			var offset := Vector3(sin(deg_to_rad(degrees)), 0, cos(deg_to_rad(degrees))) * 1.15
			_prepare_player(actor, actor.global_basis * offset)
			_check(actor.can_begin_rear_takedown(player) == (absf(degrees) < 55.0), "rear cone must follow actual enemy yaw: %.2f / %.1f" % [yaw, degrees])
	actor.rotation = Vector3.ZERO
	for distance: float in [.849, .851, 1.499, 1.501]:
		_prepare_player(actor, Vector3(0, 0, distance))
		_check(actor.can_begin_rear_takedown(player) == (distance > .85 and distance < 1.50), "rear horizontal range boundary %.3f" % distance)
	for height: float in [-.801, -.799, .799, .801]:
		_prepare_player(actor, Vector3(0, height, 1.15))
		_check(actor.can_begin_rear_takedown(player) == (absf(height) < .8), "rear height boundary %.3f" % height)
	_prepare_player(actor, Vector3(0, 0, 1.15))
	var other_world := SubViewport.new()
	other_world.own_world_3d = true
	root.add_child(other_world)
	var foreign_executor := Node3D.new()
	other_world.add_child(foreign_executor)
	foreign_executor.global_position = player.global_position
	_check(not actor.can_begin_rear_takedown(foreign_executor) and not actor.begin_rear_takedown(foreign_executor), "a colocated executor in another World3D cannot reserve the target")
	other_world.queue_free()
	actor._set_state(DungeonEnemy.AIState.CHASE)
	_check(not actor.can_begin_rear_takedown(player) and not bool(player.begin_rear_takedown().accepted), "already-alerted rear target must reject execution")
	_check(not is_instance_valid(actor._execution_executor), "failed alerted reservation must not leave a held enemy")
	actor._set_state(DungeonEnemy.AIState.IDLE)
	_check(player.get_rear_takedown_target() == actor, "turn-before-begin fixture initially selects real unaware target")
	actor.rotation.y = PI
	_check(not bool(player.begin_rear_takedown().accepted) and not is_instance_valid(actor._execution_executor), "turning around after selection must invalidate the actual reservation")
	actor.rotation = Vector3.ZERO
	wall = _add_box(Vector3(2, 3, .15), actor.global_position + Vector3(0, .5, .57))
	await physics_frame
	_check(not actor.can_begin_rear_takedown(player) and not bool(player.begin_rear_takedown().accepted), "a physical world wall blocks both enemy and player rear reservation")
	wall.get_parent().remove_child(wall)
	wall.queue_free()
	wall = null
	await physics_frame
	for weapon: String in ["rusted_sword", "forged_longsword", "forged_arming_sword", "iron_dagger", "hunting_bow"]:
		_check(_equip(weapon), "profile check equips actual item: " + weapon)
		var supported := weapon in ["rusted_sword", "forged_longsword", "forged_arming_sword"]
		_check((player.get_rear_takedown_profile() == "rear_sword") == supported, "weapon-specific rear profile: " + weapon)
		if not supported:
			_check(not bool(player.begin_rear_takedown().accepted) and not is_instance_valid(actor._execution_executor), "unsupported weapon cannot reserve or reuse sword finisher: " + weapon)
	_check(_equip("rusted_sword"), "restore sword for failed-stamina gate")
	player.stamina = 0.0
	_check(not bool(player.begin_rear_takedown().accepted) and not is_instance_valid(actor._execution_executor), "insufficient stamina must not reserve the target")
	player.stamina = player.MAX_STAMINA
	var ordinary = _spawn(false)
	ordinary.position.x = 5.0
	_prepare_player(ordinary, Vector3(0, 0, 1.15))
	_check(not ordinary.can_begin_rear_takedown(player), "unsupported enemy without authored rear-takedown support must fail explicitly")


func _start_rear(actor) -> bool:
	var entry: Transform3D = actor.global_transform
	var bones: Array[Transform3D] = []
	for bone in actor.skeleton.get_bone_count(): bones.append(actor.skeleton.get_bone_pose(bone))
	var stamina := player.stamina
	var outcome := player.begin_rear_takedown()
	_check(bool(outcome.accepted), "actual sword rear execution must begin: " + str(outcome))
	if not bool(outcome.accepted): return false
	_check(actor.global_transform.is_equal_approx(entry), "reservation cannot turn or teleport the unaware actor")
	for bone in bones.size():
		_check(actor.skeleton.get_bone_pose(bone).is_equal_approx(bones[bone]), "reservation must preserve actual source bone pose: " + actor.skeleton.get_bone_name(bone))
	_check(actor.ai_state == DungeonEnemy.AIState.EXECUTION and actor._execution_executor == player and player.viewmodel_renderer.world_contact_enabled, "player and enemy must share one real reservation with world-depth rendering")
	_check(is_equal_approx(stamina - player.stamina, REAR.STAMINA_COST * player.get_body_attack_stamina_multiplier()), "reservation spends one real execution stamina cost")
	_check(not actor.finish_rear_takedown(player), "direct premature finish cannot kill before deep-stab contact")
	_check(not actor.finish_execution(player), "old execution finish cannot bypass the deep-stab clock")
	return true


func _ordered_execution(weapon: String, long_tick: bool, initial_distance := 1.15) -> void:
	var actor = await _new_rear_actor(weapon)
	if not is_equal_approx(initial_distance, 1.15):
		_prepare_player(actor, Vector3(0, 0, initial_distance))
		_settle_rear_idle(actor)
		await physics_frame
		await physics_frame
	var hp: float = actor.health
	var before_rewards := bag.count_item("rune_fragment")
	var before_hits := landed.size()
	if not _start_rear(actor): return
	var entry_root: Transform3D = actor.global_transform
	var initial_chest_basis: Basis = actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("Chest")).basis.orthonormalized()
	var before_lower := {}
	for bone_name: String in ["Torso", "Leg1.L", "Leg1.R", "Foot.L", "Foot.R"]:
		before_lower[bone_name] = actor.skeleton.get_bone_pose(actor.skeleton.find_bone(bone_name))
	var geometry := _real_blade()
	var actual_length: float = geometry.length
	_check(actual_length > .40 and absf(actual_length - player.get_execution_snapshot().blade_length_m) < .002, "execution measures actual equipped blade vertices in world metres")
	if long_tick:
		player.advance_execution(REAR.WITHDRAW_END + .01)
		player._update_viewmodel(0.0)
		_check(bool(player.get_execution_snapshot().stab_contact_committed), "long frame resolves real stab contact before death and straight extraction")
	else:
		for time: float in [REAR.PREPARE_END, REAR.STAB_CONTACT - .001, REAR.STAB_CONTACT, REAR.STAB_CONTACT + STEP, REAR.STAB_CONTACT + .08, REAR.STAB_HIT - .001]:
			_advance_rear_to(time)
			_check(player.is_execution_active(), "valid rear execution remains active at %.3f" % time)
			_check(actor.health == hp and actor.dismemberment.severed.is_empty() and actor.dismemberment.detached.is_empty() and _defeats(actor) == 0 and landed.size() == before_hits, "no death or reward before the deep stab at %.3f" % time)
			_check(actor.ragdoll.phase == "living" and actor.ragdoll.parts.is_empty(), "pre-stab reaction cannot create a corpse")
			_check(actor.global_transform.is_equal_approx(entry_root), "standing reaction keeps navigation root planted")
			for bone_name: String in before_lower:
				_check(actor.skeleton.get_bone_pose(actor.skeleton.find_bone(bone_name)).is_equal_approx(before_lower[bone_name]), "standing rear reaction preserves lower body: " + bone_name)
			if time >= REAR.STAB_CONTACT - .001: _check_skin_contact_reaction(actor, time, initial_chest_basis)
			if is_equal_approx(time, REAR.PREPARE_END):
				var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
				_check(absf(distance - REAR.STAB_DISTANCE) < .02, "preparation reaches chamber distance before the thrust")
			_check(not actor.finish_rear_takedown(player), "premature finish cannot bypass the deep-stab clock")
		_advance_rear_to(REAR.STAB_HIT)
		_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and actor.ragdoll.phase == "execution_hold" and actor.ragdoll.parts.is_empty(), "deep actual stab kills once but holds the intact final recoil pose while steel remains inside")
		_check_skin_contact_reaction(actor, REAR.STAB_HIT, initial_chest_basis)
		_check_through_blade_in_skin(actor, actual_length, REAR.STAB_HIT)
		_check_execution_arm_reach("deep_stab")
		var held_pose: Array[Transform3D] = []
		for bone in actor.skeleton.get_bone_count(): held_pose.append(actor.skeleton.get_bone_pose(bone))
		var held := _real_blade()
		var held_basis := player.weapon_pivot.global_basis.orthonormalized()
		var state := player.get_execution_snapshot()
		var previous_depth := float((held.tip - state.contact_point).dot(state.stab_direction))
		for time: float in [REAR.HOLD_END, (REAR.HOLD_END + REAR.WITHDRAW_END) * .5, REAR.WITHDRAW_END - .03]:
			_advance_rear_to(time)
			var blade := _real_blade()
			var depth := float((blade.tip - state.contact_point).dot(state.stab_direction))
			var shift: Vector3 = blade.tip - held.tip
			var lateral := (shift - (state.stab_direction as Vector3) * shift.dot(state.stab_direction)).length()
			_check(actor.ragdoll.phase == "execution_hold" and actor.ragdoll.parts.is_empty(), "body stays held until actual tip clears the wound by the required margin")
			for bone in held_pose.size(): _check(actor.skeleton.get_bone_pose(bone).is_equal_approx(held_pose[bone]), "held death preserves final penetration recoil without twist or side movement")
			_check(basis_angle_degrees(held_basis, player.weapon_pivot.global_basis.orthonormalized()) <= .10 and lateral < .002, "straight extraction cannot roll the blade or sweep it sideways")
			_check(depth <= previous_depth + .0001, "extraction tip moves monotonically backward on the original thrust axis")
			previous_depth = depth
			if is_equal_approx(time, REAR.HOLD_END):
				_check_through_blade_in_skin(actor, actual_length, time)
				var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
				_check(absf(distance - REAR.CONTACT_DISTANCE) < .02, "deep grip keeps the collision-tested stance distance")
		_advance_rear_to(REAR.WITHDRAW_END)
		var exited := _real_blade()
		var tip_depth := float((exited.tip - state.contact_point).dot(state.stab_direction))
		var shift: Vector3 = exited.tip - held.tip
		var lateral := (shift - (state.stab_direction as Vector3) * shift.dot(state.stab_direction)).length()
		_check(tip_depth <= -REAR.WITHDRAW_CLEARANCE + .001 and lateral < .002 and basis_angle_degrees(held_basis, player.weapon_pivot.global_basis.orthonormalized()) <= .10, "actual steel clears the wound by the required margin on the same straight axis and fixed roll")
		var returned_distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
		_check(absf(returned_distance - REAR.STAB_DISTANCE) < .02, "body reverses its lunge during straight extraction without stretching the arm")
		report.append({"case": "straight_extraction_geometry", "lateral_tip_shift_m": lateral, "tip_retreat_m": -shift.dot(state.stab_direction), "tip_entry_plane_depth_m": tip_depth, "returned_stance_distance_m": returned_distance})
	actor.ragdoll.set_physics_process(false)
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and _defeats(actor) == 1, "deep stab causes exactly one death")
	_check(actor.dismemberment.severed.is_empty() and actor.dismemberment.detached.is_empty(), "straight pull-out preserves the head and all limbs")
	_check(actor.ragdoll.phase == "simulating" and actor.ragdoll.parts.has("Head") and not bool(actor.ragdoll.snapshot().execution_held), "cleared blade releases the entire attached-head corpse into physics")
	var body_ids := {}
	for key in actor.ragdoll.parts: body_ids[key] = actor.ragdoll.parts[key].body.get_instance_id()
	_check(not actor.release_execution_ragdoll(player), "repeated release cannot restart the same corpse")
	for key in body_ids: _check(actor.ragdoll.parts[key].body.get_instance_id() == body_ids[key], "duplicate release preserves existing physical bodies")
	_check(landed.size() == before_hits + 1 and bag.count_item("rune_fragment") == before_rewards + 1 and reward_game.loot_count == 1, "actual game receiver grants exactly one rune and one landed event")
	_check(not actor.finish_rear_takedown(player), "duplicate finish cannot grant another death or reward")
	player.cancel_execution()
	player.cancel_execution()
	player.advance_execution(REAR.DURATION)
	player._update_viewmodel(0.0)
	_check_restored_grip(player, "post-withdrawal cancellation")
	_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled and _defeats(actor) == 1 and bag.count_item("rune_fragment") == before_rewards + 1, "post-withdrawal cancellation restores player without duplicate death or reward")
	report.append({"case": weapon, "long_tick": long_tick, "initial_distance_m": initial_distance, "blade_length_m": actual_length, "attached_head_ragdoll": actor.ragdoll.parts.has("Head"), "defeats": _defeats(actor), "rune_rewards": bag.count_item("rune_fragment") - before_rewards})


func _check_through_blade_in_skin(actor, length: float, time: float) -> void:
	var state := player.get_execution_snapshot()
	var blade := _real_blade()
	var skin := measure_skin_passage(actor, blade.heel, blade.tip, state.contact_point, state.stab_direction)
	_check(bool(skin.get("found", false)), "actual posed skin must provide both entry and opposite-side exit evidence at %.3f" % time)
	if not bool(skin.get("found", false)):
		report.append({"case": "missing_through_skin", "time": time, "measurement": skin})
		return
	_check(skin.entry_mesh == "CreepPart_torso" and skin.exit_mesh == "CreepPart_torso", "actual stab enters and exits torso skin; passing through an open neck seam into head skin is invalid")
	_check(float(skin.inserted_fraction) >= .89 and float(skin.inserted_fraction) <= .99, "actual tip must reach almost the full blade length beyond posed back skin")
	_check(float(skin.heel_depth_m) < -.008, "blade heel and guard stay outside actual back skin")
	_check(float(skin.exit_protrusion_m) > .03, "real blade tip must protrude at least three centimetres beyond the actual opposite skin")
	_check(float(skin.body_thickness_m) > .05 and float(skin.off_axis_m) < .02, "entry and exit must span real body thickness on the stab axis")
	_check(float(skin.entry_anchor_error_m) < .05, "reaction preserves actual back-entry skin within five centimetres")
	report.append({"case": "through_skin", "time": time, "blade_length_m": length, "measurement": skin})


func _check_skin_contact_reaction(actor, time: float, initial_chest_basis: Basis) -> void:
	var state := player.get_execution_snapshot()
	var blade := _real_blade()
	var skin := measure_skin_passage(actor, blade.heel, blade.tip, state.contact_point, state.stab_direction)
	var reaction: Dictionary = actor.get_rear_takedown_reaction_snapshot()
	_check(bool(skin.get("found", false)) and skin.get("entry_mesh", "") == "CreepPart_torso", "contact clock is checked against actual posed torso skin, never a capsule")
	if not bool(skin.get("found", false)): return
	var depth := float(skin.depth_m)
	var recoil := float(reaction.get("recoil_weight", -1.0))
	var chest_basis: Basis = actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("Chest")).basis.orthonormalized()
	var chest_change := basis_angle_degrees(initial_chest_basis, chest_basis)
	if time < REAR.STAB_CONTACT:
		_check(depth < 0.0 and is_zero_approx(recoil) and chest_change < .01, "victim cannot recoil before the real sword tip reaches back skin")
	elif is_equal_approx(time, REAR.STAB_CONTACT):
		_check(absf(depth) < .003 and is_zero_approx(recoil), "first-contact key places the actual tip on torso skin before starting recoil")
	else:
		_check(depth > .0 and recoil > .0 and chest_change > .01, "after physical skin contact the victim must already react while the sword is advancing")
	if time >= REAR.STAB_HIT - .001:
		_check(recoil > .95 and float(reaction.get("contact_weight", -1.0)) > .99 and float(reaction.get("penetration_weight", -1.0)) > .95 and chest_change > 5.0, "deepest thrust already includes substantial actual chest recoil instead of starting it afterward")
	report.append({"case": "physical_skin_contact_and_recoil", "time": time, "actual_skin_depth_m": depth, "actual_chest_rotation_degrees": chest_change, "reaction": reaction, "entry_skin_world": skin.entry_world, "entry_mesh": skin.entry_mesh})


static func measure_skin_passage(actor, heel: Vector3, tip: Vector3, anchor: Vector3, direction: Vector3) -> Dictionary:
	# Intersect only actual visible body skin: no collision capsule, AABB, caps,
	# inferred thickness or fabricated closing face can prove a far-side exit.
	var hits: Array[Dictionary] = []
	var from := anchor - direction * .3
	var to := anchor + direction * 1.4
	for part: MeshInstance3D in actor.visual_meshes:
		if not str(part.name).begins_with("CreepPart_") or not part.is_visible_in_tree(): continue
		var baked = actor.dismemberment._bake_world_mesh(part, Vector3.ZERO)
		var faces: PackedVector3Array = baked.get_faces()
		for index in range(0, faces.size(), 3):
			# Test both triangle windings so a back-face API convention cannot
			# silently omit the skin on the opposite side of an open partition.
			for reverse in 2:
				var hit = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1 + reverse], faces[index + 2 - reverse])
				if not hit is Vector3: continue
				var duplicate := false
				for existing: Dictionary in hits:
					if (existing.position as Vector3).distance_to(hit) < .0001: duplicate = true
				if not duplicate: hits.append({"position": hit, "depth_m": (hit - anchor).dot(direction), "mesh": str(part.name)})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.depth_m) < float(b.depth_m))
	var entry_index := -1
	var error := INF
	for index in hits.size():
		if (hits[index].position as Vector3).distance_to(anchor) < error:
			error = (hits[index].position as Vector3).distance_to(anchor)
			entry_index = index
	var exit_index := -1
	if entry_index >= 0:
		for index in range(entry_index + 1, hits.size()):
			if float(hits[index].depth_m) - float(hits[entry_index].depth_m) > .05:
				# The farthest skin crossing is the true outer exit. The first
				# forward hit might merely enter another body partition.
				exit_index = index
	var result := {"found": entry_index >= 0 and exit_index >= 0, "crossings": hits, "geometry_scope": "visible posed CreepPart skin triangles only; farthest forward crossing is exit; no caps or collision proxies"}
	if not bool(result.found): return result
	var entry: Vector3 = hits[entry_index].position
	var exit: Vector3 = hits[exit_index].position
	var blade_length := heel.distance_to(tip)
	var depth := (tip - entry).dot(direction)
	result.merge({"entry_world": entry, "exit_world": exit, "entry_mesh": hits[entry_index].mesh, "exit_mesh": hits[exit_index].mesh,
		"entry_anchor_error_m": entry.distance_to(anchor), "depth_m": depth, "inserted_fraction": depth / maxf(blade_length, .000001),
		"heel_depth_m": (heel - entry).dot(direction), "body_thickness_m": (exit - entry).dot(direction), "exit_protrusion_m": (tip - exit).dot(direction),
		"off_axis_m": (tip - anchor - direction * (tip - anchor).dot(direction)).length()})
	return result


static func measure_visible_skin_segment(actor, from: Vector3, to: Vector3) -> Dictionary:
	# After cancellation the sword has a different axis. Intersect its actual
	# finite blade segment with the displayed posed skin instead of projecting
	# the idle-returning tip onto the obsolete thrust axis.
	var hits: Array[Dictionary] = []
	var blade_length := from.distance_to(to)
	for part: MeshInstance3D in actor.visual_meshes:
		if not str(part.name).begins_with("CreepPart_") or not part.is_visible_in_tree(): continue
		var baked = actor.dismemberment._bake_world_mesh(part, Vector3.ZERO)
		var faces: PackedVector3Array = baked.get_faces()
		for index in range(0, faces.size(), 3):
			for reverse in 2:
				var hit = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1 + reverse], faces[index + 2 - reverse])
				if not hit is Vector3: continue
				var duplicate := false
				for existing: Dictionary in hits:
					if (existing.position as Vector3).distance_to(hit) < .0001: duplicate = true
				if not duplicate: hits.append({"position": hit, "mesh": str(part.name), "fraction": from.distance_to(hit) / maxf(blade_length, .000001)})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.fraction) < float(b.fraction))
	return {"intersects": not hits.is_empty(), "crossings": hits, "heel_world": from, "tip_world": to, "measurement_scope": "Actual finite rendered blade centerline against visible posed skin triangles, both windings. No old-axis projection or anatomical capsule. Does not certify full blade-volume clearance."}


func _cancellation_boundaries() -> void:
	for mode: String in ["equipment", "player_death", "menu", "explicit", "target_detached", "new_wall"]:
		var actor = await _new_rear_actor()
		var rewards := bag.count_item("rune_fragment")
		if not _start_rear(actor): continue
		_advance_rear_to(REAR.STAB_HIT - .04)
		match mode:
			"equipment": _check(_equip("iron_dagger"), "mid-execution equipment swap uses actual inventory")
			"player_death":
				player.health = 0.0
				player.sync_body_health_from_session()
			"menu": player.prepare_for_inventory()
			"explicit": player.cancel_execution()
			"target_detached":
				stage.remove_child(actor)
				player.advance_execution(.01)
				stage.add_child(actor)
			"new_wall":
				wall = _add_box(Vector3(2, 3, .12), actor.global_position + Vector3(0, .5, .58))
				await physics_frame
				await physics_frame
		player.advance_execution(REAR.DURATION)
		player._update_viewmodel(0.0)
		_check_restored_grip(player, "cancel " + mode)
		_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled, "cancelled rear execution releases player/render mode: " + mode)
		_check(actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "cancelled live target must be released and alerted: " + mode)
		_check(actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and actor.ragdoll.phase == "living" and _defeats(actor) == 0 and bag.count_item("rune_fragment") == rewards, "cancel before stab must not create delayed severance, dead hold or rewards: " + mode)
		_check(not actor.can_begin_rear_takedown(player), "cancelled target cannot immediately become unaware again: " + mode)

	for mode: String in ["explicit", "menu", "equipment", "player_death"]:
		var actor = await _new_rear_actor()
		var rewards := bag.count_item("rune_fragment")
		var hits := landed.size()
		if not _start_rear(actor): continue
		_advance_rear_to(REAR.STAB_HIT + .04)
		_check(actor.health == 0.0 and actor.ragdoll.phase == "execution_hold", "post-stab cancellation fixture owns a dead blade-held target: " + mode)
		match mode:
			"explicit": player.cancel_execution()
			"menu": player.prepare_for_inventory()
			"equipment": _check(_equip("iron_dagger"), "held-corpse cancellation uses real inventory equipment swap")
			"player_death":
				player.health = 0.0
				player.sync_body_health_from_session()
		player.advance_execution(REAR.DURATION)
		player._update_viewmodel(0.0)
		_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled, "post-stab cancellation releases player: " + mode)
		_check(actor.ragdoll.phase == "simulating" and actor.ragdoll.parts.has("Head") and not bool(actor.ragdoll.snapshot().execution_held), "cancelled execution cannot leave a corpse suspended on its sword: " + mode)
		_check(actor.dismemberment.severed.is_empty() and _defeats(actor) == 1 and landed.size() == hits + 1 and bag.count_item("rune_fragment") == rewards + 1, "held-corpse cancellation preserves one death and one reward: " + mode)
		_check_restored_grip(player, "held corpse cancel " + mode)


func _check_execution_arm_reach(phase: String) -> void:
	var motion := player.get_first_person_motion_snapshot()
	var arm: Dictionary = motion.joint_landmarks.get("sword", {})
	var grip: Dictionary = motion.hand_contacts.get("sword", {})
	_check(not arm.is_empty() and not grip.is_empty(), "execution must expose actual fitted arm joints and sword-hand contact: " + phase)
	if arm.is_empty() or grip.is_empty(): return
	var reach: float = (arm.wrist as Vector3).distance_to(arm.shoulder)
	var adjustment := float(arm.get("shoulder_adjustment_m", INF))
	var authored_shoulder: Vector3 = player.camera.to_global(player.SWORD_LONG_GRIP.SOURCE_READY * player.SWORD_LONG_GRIP.REST_SHOULDER)
	var requested_reach: float = (arm.wrist as Vector3).distance_to(authored_shoulder)
	_check(reach <= .601 and requested_reach <= .641 and adjustment <= .041, "execution must stay within fixed arm length and four-centimetre shoulder correction: " + phase)
	_check(absf(float(arm.upper_length) - .34) < .004 and absf(float(arm.forearm_length) - .26) < .004, "execution cannot lengthen the rendered upper arm or forearm: " + phase)
	_check(float(grip.get("error", INF)) < .01, "execution must preserve the actual sword-hand grip: " + phase)
	var wrist := measure_wrist_geometry(player)
	_check(bool(wrist.get("available", false)), "actual supplied hand and forearm bones must be measurable: " + phase)
	if bool(wrist.get("available", false)):
		_check(float(wrist.axis_mismatch_degrees) <= 45.0, "authored hand axis must align with the actual posed forearm within 45 degrees: " + phase)
		if phase == "deep_stab":
			_check(float(wrist.blade_forearm_angle_degrees) <= 25.0, "middle-guard deep thrust keeps the real blade within 25 degrees of forearm extension")
			_check(float(wrist.elbow_extension_angle_degrees) >= 120.0, "deep thrust extends the actual elbow to at least 120 degrees instead of leaving the hand near the chest")
			_check(float(wrist.axis_mismatch_degrees) <= 20.0, "middle-guard deep thrust keeps the actual hand/forearm neutral-axis mismatch within 20 degrees")
			_check(float(wrist.elbow_behind_wrist_along_blade_m) > .15, "deep thrust is supported by the real elbow at least 15cm behind the wrist along the blade")
	report.append({"case": "execution_arm_reach", "phase": phase, "time": player.execution_elapsed, "shoulder_to_wrist_m": reach, "authored_shoulder_to_wrist_m": requested_reach, "shoulder_adjustment_m": adjustment, "grip_error_m": grip.error})
	if not wrist.is_empty(): report.append({"case": "actual_wrist_axis", "phase": phase, "measurement": wrist})


func _wrist_motion_sequence() -> void:
	var actor = await _new_rear_actor()
	if not _start_rear(actor): return
	var times: Array[float] = [0.0]
	for frame in range(1, int(ceil(REAR.DURATION / STEP)) + 1): times.append(minf(REAR.DURATION, frame * STEP))
	var boundaries: Array[float] = [REAR.PREPARE_END, REAR.STAB_CONTACT, REAR.STAB_HIT, REAR.HOLD_END, REAR.WITHDRAW_END, REAR.RECOVER_START, REAR.DURATION]
	for boundary in boundaries:
		times.append(boundary - .0001)
		times.append(boundary)
		if boundary < REAR.DURATION: times.append(boundary + .0001)
	times.sort()
	var samples: Array[Dictionary] = []
	var elapsed := 0.0
	var embedded_basis := Basis.IDENTITY
	var embedded_seen := false
	var maximum_mismatch := 0.0
	var maximum_fixed_rotation := 0.0
	var maximum_lateral_shift := 0.0
	var previous_withdrawal_depth := INF
	var minimum_thrust_forearm_clearance := INF
	var minimum_preparation_forearm_clearance := INF
	for time in times:
		if not samples.is_empty() and time <= elapsed + .0000001: continue
		var delta := time - elapsed
		player.advance_combat_state(delta)
		player._update_viewmodel(delta)
		if actor.health <= 0.0: actor.ragdoll.set_physics_process(false)
		elapsed = time
		var actual := measure_wrist_geometry(player)
		_check(bool(actual.get("available", false)), "60Hz wrist check reads the actual supplied skeleton")
		if not bool(actual.get("available", false)): continue
		if player.is_execution_active():
			_check(absf(float(actual.thrust_grip_amount) - REAR.grip_blend(time)) < .0001, "actual hand uses the rear-only diagonal grip blend at %.5fs" % time)
			_check(float(actual.actual_wrist_fit_error_m) < .001 and float(actual.actual_neutral_api_error_degrees) < .1, "rear IK helpers must match the actual rendered wrist and neutral axis at %.5fs" % time)
			_check(float(actual.planned_grip_offset_error_m) < .001, "diagonal grip follows the planned hand-to-handle contact offset")
		if time >= REAR.PREPARE_END and time <= REAR.HOLD_END:
			minimum_thrust_forearm_clearance = minf(minimum_thrust_forearm_clearance, float(actual.camera_forearm_centerline_clearance_m))
			_check(float(actual.camera_forearm_centerline_clearance_m) >= .14, "middle-guard thrust keeps the real forearm centerline at least 14cm from the camera at %.5fs" % time)
		elif time < REAR.PREPARE_END:
			minimum_preparation_forearm_clearance = minf(minimum_preparation_forearm_clearance, float(actual.camera_forearm_centerline_clearance_m))
		var blade := _real_blade()
		var state := player.get_execution_snapshot()
		var depth: float = (blade.tip - state.contact_point).dot(state.stab_direction)
		var projection := measure_blade_projection(player.camera, blade.heel, blade.tip, state.contact_point, state.stab_direction)
		var weapon_basis := player.weapon_pivot.global_basis.orthonormalized()
		var strict_axis := (time >= REAR.PREPARE_END and time <= REAR.WITHDRAW_END and depth > 0.0) or (time >= REAR.STAB_HIT and time <= REAR.WITHDRAW_END)
		if strict_axis:
			maximum_mismatch = maxf(maximum_mismatch, float(actual.axis_mismatch_degrees))
			_check(float(actual.axis_mismatch_degrees) <= 45.0, "actual hand/forearm axis mismatch exceeds 45 degrees at %.5fs" % time)
		if time >= REAR.PREPARE_END and time <= REAR.WITHDRAW_END:
			if not embedded_seen:
				embedded_basis = weapon_basis
				embedded_seen = true
			var drift := basis_angle_degrees(embedded_basis, weapon_basis)
			maximum_fixed_rotation = maxf(maximum_fixed_rotation, drift)
			_check(drift <= .10, "thrust, hold and straight pull-out must preserve actual world blade rotation at %.5fs" % time)
		if time >= REAR.PREPARE_END and time <= REAR.WITHDRAW_END:
			var offset: Vector3 = blade.tip - state.contact_point
			var lateral := (offset - (state.stab_direction as Vector3) * depth).length()
			maximum_lateral_shift = maxf(maximum_lateral_shift, lateral)
			_check(lateral < .002, "thrust and withdrawal stay on the original axis without a sideways slice")
		if time >= REAR.HOLD_END and time <= REAR.WITHDRAW_END:
			_check(depth <= previous_withdrawal_depth + .0001, "straight withdrawal depth is monotonic at every actual frame")
			previous_withdrawal_depth = depth
		if time >= REAR.STAB_HIT and time <= REAR.HOLD_END:
			_check(int(projection.in_frame_samples) >= 2 and float(projection.projected_span_px) > 1.0, "exposed steel remains visible during the deepest stab and hold")
		samples.append({"time": time, "delta": delta, "actual": actual, "weapon_basis": weapon_basis, "projection": projection, "depth_m": depth})
	var maximum_step := 0.0
	var maximum_rotation := 0.0
	var maximum_step_time := 0.0
	for index in range(1, samples.size()):
		var previous: Dictionary = samples[index - 1]
		var current: Dictionary = samples[index]
		var step := actual_joint_step(previous.actual, current.actual)
		var rotation := basis_angle_degrees(previous.actual.hand_basis_world, current.actual.hand_basis_world)
		if step > maximum_step:
			maximum_step = step
			maximum_step_time = current.time
		maximum_rotation = maxf(maximum_rotation, rotation)
		# These are discontinuity guards, not a universal animation speed limit:
		# bound the fitted joints to 12cm and the hand to 45 degrees per tick.
		_check(step < .12 and rotation < 45.0, "actual bone continuity must not snap at %.5fs (%.4fm / %.2fdeg)" % [current.time, step, rotation])
		if float(current.delta) <= .00011:
			_check(step < .004 and rotation < .75, "real joint pose must join continuously across a phase boundary at %.5fs" % current.time)
	var projection_stages: Array[Dictionary] = []
	for sample in samples:
		for boundary in boundaries:
			if absf(float(sample.time) - boundary) < .000001:
				projection_stages.append({"time": sample.time, "projection": sample.projection, "axis_mismatch_degrees": sample.actual.axis_mismatch_degrees})
	_check(samples.size() >= int(ceil(REAR.DURATION / STEP)) and embedded_seen, "full 60Hz execution and explicit phase-boundary samples must be retained")
	report.append({"case": "full_wrist_continuity", "sample_count": samples.size(), "preparation_samples": samples.filter(func(sample): return float(sample.time) <= REAR.PREPARE_END), "maximum_joint_step_m": maximum_step, "maximum_step_time": maximum_step_time, "maximum_hand_rotation_step_degrees": maximum_rotation, "maximum_embedded_axis_mismatch_degrees": maximum_mismatch, "maximum_fixed_blade_rotation_degrees": maximum_fixed_rotation, "maximum_lateral_tip_shift_m": maximum_lateral_shift, "minimum_thrust_forearm_camera_clearance_m": minimum_thrust_forearm_clearance, "minimum_preparation_forearm_camera_clearance_m": minimum_preparation_forearm_clearance, "forearm_clearance_scope": "Actual elbow-to-wrist centerline distance to camera; 14cm floor from preparation-end through deep-stab hold. Preparation is reported separately. Proxy only, not an exact skin/sleeve collision proof.", "projection_stages": projection_stages})


static func measure_wrist_geometry(subject: DungeonPlayer) -> Dictionary:
	# Inspect actual hand/deform bones. Never substitute the animation solver's
	# requested elbow or its reported angle for the rendered rig's result.
	var adapter := subject.weapon_arm.get_node_or_null("SuppliedRightArm")
	if adapter == null: return {"available": false}
	var rig := adapter.find_child("Skeleton3D", true, false) as Skeleton3D
	if rig == null: return {"available": false}
	var wrist_index := rig.find_bone("wrist")
	var elbow_index := rig.find_bone("elbow")
	var shoulder_index := rig.find_bone("upper")
	if mini(wrist_index, mini(elbow_index, shoulder_index)) < 0: return {"available": false}
	var rest_wrist := rig.get_bone_global_rest(wrist_index)
	var neutral := rig.get_bone_global_rest(elbow_index).origin - rest_wrist.origin
	var wrist_pose := rig.get_bone_global_pose(wrist_index)
	var hand: Transform3D = rig.global_transform * wrist_pose
	var wrist := hand.origin
	var elbow := rig.to_global(rig.get_bone_global_pose(elbow_index).origin)
	var shoulder := rig.to_global(rig.get_bone_global_pose(shoulder_index).origin)
	var hand_axis := (rig.global_basis * wrist_pose.basis * rest_wrist.basis.inverse() * neutral).normalized()
	var actual_forearm := (elbow - wrist).normalized()
	var legacy_axis := (subject.weapon_arm.global_basis * (subject.SWORD_LONG_GRIP.REST_ELBOW - subject.SWORD_LONG_GRIP.REST_WRIST)).normalized()
	var blade_axis := subject.weapon_pivot.global_basis.y.normalized()
	var handle_center: Vector3 = subject.weapon_pivot.to_global(subject.SWORD_LONG_GRIP.GRIP_CENTER)
	var anatomical_grip_center: Vector3 = adapter.to_global(adapter.GRIP_CENTER)
	var wrist_camera := subject.camera.to_local(wrist)
	var elbow_camera := subject.camera.to_local(elbow)
	var segment := wrist_camera - elbow_camera
	var nearest_fraction := clampf(-elbow_camera.dot(segment) / maxf(segment.length_squared(), .00000001), 0.0, 1.0)
	var nearest_forearm_point := elbow_camera + segment * nearest_fraction
	var digit_landmarks := {}
	for digit: String in ["index", "middle", "ring", "little", "thumb"]:
		var points: Array[Dictionary] = []
		for joint in 3:
			var bone := rig.find_bone(digit + str(joint))
			if bone < 0: continue
			var point := rig.to_global(rig.get_bone_global_pose(bone).origin)
			var axial := (point - handle_center).dot(blade_axis)
			points.append({"joint": joint, "world": point, "handle_axis_distance_m": (point - handle_center - blade_axis * axial).length(), "handle_axis_offset_m": axial})
		digit_landmarks[digit] = points
	var grip_amount := float(subject.weapon_arm.get("thrust_grip_amount"))
	var expected_palm: Vector3 = subject.weapon_pivot.to_global(subject.SWORD_LONG_GRIP.GRIP_CENTER + subject.SWORD_LONG_GRIP.THRUST_CONTACT_OFFSET * grip_amount)
	var expected_wrist: Vector3 = subject.weapon_arm.to_global(subject.SWORD_LONG_GRIP.wrist_local(grip_amount))
	var expected_neutral: Vector3 = (subject.weapon_arm.global_basis * subject.SWORD_LONG_GRIP.neutral_axis_local(grip_amount)).normalized()
	return {"available": true, "wrist_world": wrist, "elbow_world": elbow, "shoulder_world": shoulder,
		"hand_basis_world": hand.basis.orthonormalized(), "neutral_hand_axis_world": hand_axis,
		"actual_forearm_axis_world": actual_forearm,
		"axis_mismatch_degrees": rad_to_deg(hand_axis.angle_to(actual_forearm)),
		"legacy_axis_mismatch_degrees": rad_to_deg(legacy_axis.angle_to(actual_forearm)),
		"blade_forearm_angle_degrees": rad_to_deg(blade_axis.angle_to(-actual_forearm)),
		"elbow_extension_angle_degrees": rad_to_deg((shoulder - elbow).angle_to(wrist - elbow)),
		"elbow_extension_measurement_scope": "Actual shoulder-elbow-wrist interior angle; 180 degrees is fully straight. Not a clinical joint-limit diagnosis.",
		"blade_hand_neutral_angle_degrees": rad_to_deg(blade_axis.angle_to(-hand_axis)),
		"elbow_behind_wrist_along_blade_m": (wrist - elbow).dot(blade_axis),
		"elbow_right_of_wrist_camera_m": elbow_camera.x - wrist_camera.x,
		"elbow_above_wrist_camera_m": elbow_camera.y - wrist_camera.y,
		"camera_forearm_centerline_clearance_m": nearest_forearm_point.length(),
		"camera_forearm_nearest_point": nearest_forearm_point,
		"camera_forearm_nearest_fraction": nearest_fraction,
		"camera_forearm_clearance_scope": "Origin-to-segment distance in camera space using actual rendered elbow and wrist bones. Centerline proxy only; not an exact skin/sleeve intersection proof.",
		"handle_center_world": handle_center, "anatomical_grip_center_world": anatomical_grip_center,
		"grip_anchor_error_m": handle_center.distance_to(anatomical_grip_center),
		"expected_palm_anchor_world": expected_palm,
		"planned_grip_offset_m": subject.SWORD_LONG_GRIP.THRUST_CONTACT_OFFSET.length() * grip_amount,
		"planned_grip_offset_error_m": anatomical_grip_center.distance_to(expected_palm),
		"thrust_grip_amount": grip_amount,
		"actual_wrist_fit_error_m": wrist.distance_to(expected_wrist),
		"actual_neutral_api_error_degrees": rad_to_deg(hand_axis.angle_to(expected_neutral)),
		"digit_bone_landmarks": digit_landmarks,
		"grip_measurement_scope": "The palm anchor and digit bone distances are geometry diagnostics, not a skin/handle contact or penetration proof. Inspect the same-pose grip-side GPU closeup.",
		"measurement_scope": "Actual posed wrist/elbow versus blade thrust axis, plus authored neutral hand axis versus forearm; not a clinical wrist angle."}


static func actual_joint_step(a: Dictionary, b: Dictionary) -> float:
	var maximum := 0.0
	for joint: String in ["wrist_world", "elbow_world", "shoulder_world"]:
		maximum = maxf(maximum, (a[joint] as Vector3).distance_to(b[joint]))
	return maximum


static func basis_angle_degrees(a: Basis, b: Basis) -> float:
	if a.is_equal_approx(b): return 0.0
	return rad_to_deg(a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion()))


static func measure_blade_projection(camera: Camera3D, heel: Vector3, tip: Vector3, entry: Vector3, axis: Vector3) -> Dictionary:
	# Visible-in-frustum geometry only. Skin, hand and sleeve occlusion still
	# requires the actual GPU images; do not call this a rendered visibility test.
	var depth := maxf(0.0, (tip - entry).dot(axis))
	var exposed_end := tip - axis * depth
	var rect := camera.get_viewport().get_visible_rect()
	var points: Array[Vector2] = []
	for index in 25:
		var point := heel.lerp(exposed_end, float(index) / 24.0)
		if camera.to_local(point).z >= -camera.near: continue
		var projected := camera.unproject_position(point)
		if rect.has_point(projected): points.append(projected)
	var span := 0.0
	for a in points:
		for b in points: span = maxf(span, a.distance_to(b))
	return {"in_frame_samples": points.size(), "projected_span_px": span, "projected_span_viewport_fraction": span / maxf(rect.size.x, 1.0), "exposed_length_m": heel.distance_to(exposed_end), "occlusion_verified": false}


func _blocked_approach() -> void:
	var actor = await _new_rear_actor()
	var rewards := bag.count_item("rune_fragment")
	var hits := landed.size()
	if not _start_rear(actor): return
	_advance_rear_to(REAR.STAB_HIT + .04)
	# A low front corner must not provoke the removed forward neck-cut step.
	# Straight extraction reverses the lunge away from this corner.
	wall = _add_box(Vector3(1.4, .65, .10), actor.global_position + Vector3(0, -.25, .25))
	var side_wall := _add_box(Vector3(.10, .65, 1.0), actor.global_position + Vector3(-.75, -.25, 1.10))
	await physics_frame
	await physics_frame
	_check(player._rear_takedown_has_clear_path(actor), "low-corner fixture isolates capsule obstruction from eye-line obstruction")
	var initial_position := player.global_position
	var elapsed := player.execution_elapsed
	while elapsed < REAR.WITHDRAW_END + .03 and player.is_execution_active():
		player.advance_execution(STEP)
		player._update_viewmodel(0.0)
		elapsed += STEP
		if actor.health <= 0.0: actor.ragdoll.set_physics_process(false)
	var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
	_check(player.global_position.z >= initial_position.z and absf(distance - REAR.STAB_DISTANCE) < .02, "straight extraction reverses the lunge away from a nearby low front corner")
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and actor.ragdoll.parts.has("Head"), "straight withdrawal completes with an intact-head physical corpse")
	_check(actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and _defeats(actor) == 1 and landed.size() == hits + 1 and bag.count_item("rune_fragment") == rewards + 1, "low corner cannot revive old neck-cut movement or duplicate death/reward")
	report.append({"case": "straight_withdrawal_by_front_corner", "remaining_distance_m": distance, "actual_step_m": player.global_position.distance_to(initial_position), "defeats": _defeats(actor)})
	side_wall.get_parent().remove_child(side_wall)
	side_wall.queue_free()


func _blocked_initial_approach() -> void:
	var actor = await _new_rear_actor()
	_prepare_player(actor, Vector3(0, 0, 1.49))
	var unsettled_blade := _real_blade()
	var unsettle_geometry := {"weapon_world": player.weapon_pivot.global_transform, "skin_segment": measure_visible_skin_segment(actor, unsettled_blade.heel, unsettled_blade.tip)}
	_settle_rear_idle(actor)
	var idle_blade := _real_blade()
	var idle_geometry := {"weapon_world": player.weapon_pivot.global_transform, "skin_segment": measure_visible_skin_segment(actor, idle_blade.heel, idle_blade.tip), "settle_ticks": 36, "aim": "actual back skin as in fresh GPU fixture"}
	_check(not bool(idle_geometry.skin_segment.intersects), "settled real idle blade must be clear of the actual target skin before a blocked-approach attempt")
	var original_root: Transform3D = actor.global_transform
	var rewards := bag.count_item("rune_fragment")
	var hits := landed.size()
	# The far fixture needs an initial step before thrusting. This low corner
	# blocks that first step while preserving all eye/back reservation rays.
	wall = _add_box(Vector3(1.4, .65, .10), actor.global_position + Vector3(0, -.25, 1.02))
	var side_wall := _add_box(Vector3(.10, .65, 1.0), actor.global_position + Vector3(-.75, -.25, 1.45))
	await physics_frame
	await physics_frame
	_check(actor.can_begin_rear_takedown(player) and player._rear_takedown_has_clear_path(actor), "far low-corner fixture must permit rear reservation and isolate the blocked initial body step")
	if _start_rear(actor):
		var initial_position := player.global_position
		var state := player.get_execution_snapshot()
		var anchor: Vector3 = state.contact_point
		var direction: Vector3 = state.stab_direction
		var elapsed := 0.0
		var deepest_tip := -INF
		var contact_committed := false
		var obstruction_samples: Array[Dictionary] = []
		var cancellation_geometry := {}
		var preparation_skin_samples := 0
		while elapsed < REAR.STAB_HIT + STEP and player.is_execution_active():
			player.advance_combat_state(STEP)
			player._update_viewmodel(STEP)
			elapsed += STEP
			var blade := _real_blade()
			var actual_axis: Vector3 = (blade.tip - blade.heel).normalized()
			var projected_depth: float = (blade.tip - anchor).dot(direction)
			var lateral: float = ((blade.tip as Vector3) - anchor - direction * projected_depth).length()
			var sample := {"requested_elapsed": elapsed, "execution_elapsed": player.execution_elapsed, "active": player.is_execution_active(), "weapon_world": player.weapon_pivot.global_transform, "tip_world": blade.tip, "heel_world": blade.heel, "axis_world": actual_axis, "old_thrust_axis_tip_depth_m": projected_depth, "old_thrust_axis_lateral_error_m": lateral, "actual_axis_vs_old_thrust_dot": actual_axis.dot(direction)}
			if player.is_execution_active():
				if player.execution_elapsed >= REAR.PREPARE_END:
					deepest_tip = maxf(deepest_tip, projected_depth)
					sample["geometry_phase"] = "axial_thrust"
				else:
					# Preparation rotates the sword beside the torso. Its tip can
					# project beyond the future wound plane while remaining far
					# to one side; inspect the actual finite segment every frame.
					var skin_segment := measure_visible_skin_segment(actor, blade.heel, blade.tip)
					sample["geometry_phase"] = "preparation_rotation"
					sample["actual_skin_segment"] = skin_segment
					preparation_skin_samples += 1
					_check(not bool(skin_segment.intersects), "blocked-approach preparation's actual rotating blade segment must not cross posed skin at %.5fs" % player.execution_elapsed)
			else:
				cancellation_geometry = sample.duplicate(true)
				cancellation_geometry["actual_skin_segment"] = measure_visible_skin_segment(actor, blade.heel, blade.tip)
			obstruction_samples.append(sample)
			contact_committed = contact_committed or bool(player.get_execution_snapshot().stab_contact_committed)
		_check(not player.is_execution_active() and elapsed < REAR.STAB_HIT, "blocked initial approach must cancel before the first deep stab event")
		_check(not contact_committed and deepest_tip < .03, "blocked initial approach must never commit a stab or exceed 3cm depth during its actual axial thrust")
		_check(not cancellation_geometry.is_empty(), "initial obstruction retains the actual post-cancellation sword pose")
		if not cancellation_geometry.is_empty():
			_check(not bool(cancellation_geometry.actual_skin_segment.intersects), "after initial obstruction the idle-returning actual blade segment must not cross visible posed skin")
		_check(player.global_position.z >= wall.global_position.z + .05 + .36 - .015 and player.global_position.distance_to(initial_position) < .15, "far executor capsule must stop at the initial low corner")
		player.advance_execution(REAR.DURATION)
		_check(not player.viewmodel_renderer.world_contact_enabled and actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "early obstruction must release a living alerted enemy and normal player rendering")
		_check(actor.global_transform.is_equal_approx(original_root) and actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and actor.ragdoll.phase == "living" and _defeats(actor) == 0 and landed.size() == hits and bag.count_item("rune_fragment") == rewards, "failed initial approach must not leave a held target, delayed cut, death or reward")
		report.append({"case": "blocked_initial_capsule_approach", "initial_distance_m": 1.49, "cancellation_time": elapsed, "actual_step_m": player.global_position.distance_to(initial_position), "deepest_axial_thrust_tip_depth_m": deepest_tip if is_finite(deepest_tip) else null, "preparation_actual_skin_samples": preparation_skin_samples, "stab_contact_committed": contact_committed, "unsettled_inherited_fixture": unsettle_geometry, "settled_idle_geometry": idle_geometry, "samples": obstruction_samples, "cancellation_geometry": cancellation_geometry, "geometry_scope": "The 3cm penetration limit applies from preparation-end onward to the active axial thrust. Every prior preparation rotation and the post-cancellation returning pose independently test their current finite blade segment against actual visible posed skin triangles."})
	side_wall.get_parent().remove_child(side_wall)
	side_wall.queue_free()


func _blocked_preparation_retreat() -> void:
	for long_tick: bool in [false, true]:
		await _blocked_preparation_retreat_variant(long_tick)


func _blocked_preparation_retreat_variant(long_tick: bool) -> void:
	var actor = await _new_rear_actor()
	var initial_position := player.global_position
	var original_root: Transform3D = actor.global_transform
	var rewards := bag.count_item("rune_fragment")
	var hits := landed.size()
	# At the ordinary 1.15m start the middle guard now needs .25m of room
	# behind the player. Leave .07m of real capsule clearance, then obstruct
	# the rest without blocking any eye-to-back reservation ray.
	wall = _add_box(Vector3(1.4, .65, .10), actor.global_position + Vector3(0, -.25, 1.63))
	await physics_frame
	await physics_frame
	_check(actor.can_begin_rear_takedown(player) and player._rear_takedown_has_clear_path(actor), "rear-wall fixture permits reservation and isolates the new preparation retreat")
	if _start_rear(actor):
		var elapsed := 0.0
		var contact_committed := false
		var delta: float = REAR.STAB_HIT + .01 if long_tick else STEP
		while elapsed < REAR.PREPARE_END + STEP and player.is_execution_active():
			# One delayed update deliberately crosses the retreat, thrust and
			# lethal-cut boundaries. It must sweep the retreat first, not reduce
			# the reversing path to a net forward movement through the target.
			player.advance_combat_state(delta)
			player._update_viewmodel(delta)
			elapsed += delta
			contact_committed = contact_committed or bool(player.get_execution_snapshot().stab_contact_committed)
		_check(not player.is_execution_active(), "blocked preparation retreat cancels even when one tick crosses the lethal-cut boundary: long_tick=%s" % long_tick)
		if not long_tick: _check(elapsed < REAR.PREPARE_END, "60Hz blocked preparation retreat cancels before the forward thrust begins")
		_check(not contact_committed, "blocked preparation retreat must never commit stabbing contact")
		_check(player.global_position.z <= wall.global_position.z - .05 - .36 + .015 and player.global_position.distance_to(initial_position) < .12, "rearward capsule sweep stops before the wall instead of teleporting through it")
		player.advance_execution(REAR.DURATION)
		player._update_viewmodel(0.0)
		_check_restored_grip(player, "blocked preparation retreat")
		_check(not player.viewmodel_renderer.world_contact_enabled and actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "blocked retreat releases a living alerted enemy and restores normal rendering")
		_check(actor.global_transform.is_equal_approx(original_root) and actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and actor.ragdoll.phase == "living" and _defeats(actor) == 0 and landed.size() == hits and bag.count_item("rune_fragment") == rewards, "blocked retreat cannot move the target, kill, or grant a reward")
		report.append({"case": "blocked_middle_guard_retreat", "long_tick": long_tick, "requested_delta_seconds": delta, "initial_distance_m": 1.15, "requested_preparation_distance_m": REAR.STAB_DISTANCE, "requested_clock_at_cancellation": elapsed, "cancellation_before_stab": not contact_committed and actor.health == actor.max_health, "actual_retreat_m": player.global_position.distance_to(initial_position), "stab_contact_committed": contact_committed})


func _advance_rear_to(time: float) -> void:
	player.advance_execution(maxf(0.0, time - player.execution_elapsed))
	player._update_viewmodel(0.0)


func _real_blade() -> Dictionary:
	# Independent measurement of rendered mesh vertices, not the motion's
	# penetration constant or the player's cached endpoint/length dictionary.
	var blade: MeshInstance3D = player.sword_blade
	var axis := blade.global_basis.y.normalized()
	var minimum := INF
	var maximum := -INF
	var tip := Vector3.ZERO
	for surface in blade.mesh.get_surface_count():
		var vertices: PackedVector3Array = blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			var point := blade.to_global(vertex)
			var distance := point.dot(axis)
			minimum = minf(minimum, distance)
			if distance > maximum:
				maximum = distance
				tip = point
	return {"tip": tip, "heel": tip - axis * (maximum - minimum), "length": maximum - minimum}


func _torso_surface_depths(actor, anchor: Vector3, direction: Vector3) -> Array[float]:
	var depths: Array[float] = []
	for point in _torso_segment_crossings(actor, anchor - direction * .2, anchor + direction * 1.2):
		depths.append((point - anchor).dot(direction))
	depths.sort()
	return depths


func _torso_segment_crossings(actor, start: Vector3, end: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for part: MeshInstance3D in actor.visual_meshes:
		if part.name != "CreepPart_torso" or not part.is_visible_in_tree(): continue
		var faces: PackedVector3Array = actor.dismemberment._bake_world_mesh(part, Vector3.ZERO).get_faces()
		for index in range(0, faces.size(), 3):
			var point = Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index + 1], faces[index + 2])
			if point is Vector3:
				var duplicate := false
				for existing in points: duplicate = duplicate or existing.distance_to(point) < .0001
				if not duplicate: points.append(point)
	return points
