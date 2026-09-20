extends "res://tests/dagger_assassination_test.gd"
## Shared fixture construction only; all new checks drive the production rear
## reservation and its real mesh, skin, inventory and death/reward consumers.
const REAR := preload("res://scripts/rear_takedown_motion.gd")
const DISMEMBERMENT := preload("res://scripts/creep_dismemberment.gd")
const GAME := preload("res://scripts/game.gd")
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
	await _eligibility_and_profiles()
	await _ordered_execution("rusted_sword", false)
	await _ordered_execution("forged_longsword", true)
	await _ordered_execution("rusted_sword", false, 1.49)
	await _wrist_motion_sequence()
	await _cancellation_boundaries()
	await _blocked_approach()
	await _blocked_initial_approach()
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
	print("REAR TAKEDOWN TEST %s: unaware rear gates, actual skin/half-blade/leftward extraction, ordered long tick, intact head and one death/reward, cancellation and preserved session" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


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
	await physics_frame
	await physics_frame
	return actor


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
	_check(not actor.finish_rear_takedown(player), "direct premature finish cannot kill before lateral cutting contact")
	_check(not actor.finish_execution(player), "old execution finish cannot bypass the lateral-extraction clock")
	return true


func _ordered_execution(weapon: String, long_tick: bool, initial_distance := 1.15) -> void:
	var actor = await _new_rear_actor(weapon)
	if not is_equal_approx(initial_distance, 1.15):
		_prepare_player(actor, Vector3(0, 0, initial_distance))
		await physics_frame
		await physics_frame
	var hp: float = actor.health
	var before_rewards := bag.count_item("rune_fragment")
	var before_hits := landed.size()
	if not _start_rear(actor): return
	var entry_root: Transform3D = actor.global_transform
	var entry_player_position := player.global_position
	var before_lower := {}
	for bone_name: String in ["Torso", "Leg1.L", "Leg1.R", "Foot.L", "Foot.R"]:
		before_lower[bone_name] = actor.skeleton.get_bone_pose(actor.skeleton.find_bone(bone_name))
	var held_blade := {}
	var hold_camera_basis := Basis.IDENTITY
	var geometry := _real_blade()
	var actual_length: float = geometry.length
	_check(actual_length > .40 and absf(actual_length - player.get_execution_snapshot().blade_length_m) < .002, "execution must measure the actual equipped blade vertices in world metres")
	if long_tick:
		player.advance_execution(REAR.CUT_HIT + .01)
		player._update_viewmodel(0.0)
		_check(bool(player.get_execution_snapshot().stab_contact_committed), "long frame must resolve real stab contact before lateral cutting death")
		_check_execution_arm_reach("lateral_cut")
	else:
		for time: float in [REAR.PREPARE_END, REAR.STAB_HIT - .001, REAR.STAB_HIT, .82, REAR.HOLD_END, REAR.CUT_HIT - .001]:
			_advance_rear_to(time)
			_check(player.is_execution_active(), "valid staged rear execution remains active at %.3f" % time)
			_check(actor.health == hp and actor.dismemberment.severed.is_empty() and actor.dismemberment.detached.is_empty() and _defeats(actor) == 0 and landed.size() == before_hits, "stab, hold and initial lateral slice keep the target alive and head attached at %.3f" % time)
			_check(actor.ragdoll.phase == "living" and actor.ragdoll.parts.is_empty(), "no early physical death or held corpse during rear stab")
			_check(actor.global_transform.is_equal_approx(entry_root), "standing reaction must keep navigation root planted")
			for bone_name: String in before_lower:
				_check(actor.skeleton.get_bone_pose(actor.skeleton.find_bone(bone_name)).is_equal_approx(before_lower[bone_name]), "standing rear reaction must preserve lower body: " + bone_name)
			if time >= REAR.STAB_HIT and time <= REAR.HOLD_END:
				_check_half_blade_in_skin(actor, actual_length, time)
				if is_equal_approx(time, REAR.STAB_HIT): _check_execution_arm_reach("deep_stab")
				if is_equal_approx(time, REAR.HOLD_END):
					held_blade = _real_blade()
					hold_camera_basis = player.camera.global_basis
			if time <= REAR.HOLD_END:
				if is_equal_approx(initial_distance, 1.15):
					_check(player.global_position.distance_to(entry_player_position) < .001, "near player remains planted while the blade is buried")
				else:
					var stab_distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
					_check(absf(stab_distance - 1.15) < .015 and player.global_position.distance_to(entry_player_position) > .25, "far rear reservation uses actual collision-tested approach before the deep stab")
			_check(not actor.finish_rear_takedown(player), "premature finish remains refused throughout live sequence")
		var blade := _real_blade()
		var torso_hit: Dictionary = actor.query_located_hit(blade.heel, blade.tip, .045)
		_check(torso_hit.get("region", "") == "torso", "actual blade still crosses the torso during the lateral cutting contact")
		var left_shift := -((blade.heel as Vector3) - (held_blade.heel as Vector3)).dot(hold_camera_basis.x)
		_check(left_shift > .025, "actual blade heel starts moving left before the lethal slice")
		var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
		_check(absf(distance - REAR.STAB_DISTANCE) < .02, "lateral extraction retains the stabbing distance without the old neck-cut step")
		_check_execution_arm_reach("lateral_cut")
		report.append({"case": "precut_geometry", "actual_contact_region": torso_hit.get("region", ""), "blade_heel_left_shift_m": left_shift, "remaining_distance_m": distance})
		_advance_rear_to(REAR.CUT_HIT)
	actor.ragdoll.set_physics_process(false)
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and _defeats(actor) == 1, "lateral cutting contact causes exactly one death")
	_check(actor.dismemberment.severed.is_empty() and actor.dismemberment.detached.is_empty(), "lateral extraction must preserve the head and all body parts")
	_check(actor.ragdoll.phase == "simulating" and actor.ragdoll.parts.has("Head"), "whole body enters immediate physics with its attached head")
	_check(landed.size() == before_hits + 1 and bag.count_item("rune_fragment") == before_rewards + 1 and reward_game.loot_count == 1, "actual game reward receiver grants exactly one rune and one landed event")
	_check(not actor.finish_rear_takedown(player), "duplicate lateral finish cannot create another death or reward")
	if not long_tick:
		_advance_rear_to(REAR.WITHDRAW_END)
		var exited := _real_blade()
		var left_shift := -((exited.heel as Vector3) - (held_blade.heel as Vector3)).dot(hold_camera_basis.x)
		var state := player.get_execution_snapshot()
		var retreat := -((exited.tip as Vector3) - (held_blade.tip as Vector3)).dot(state.stab_direction)
		var tip_depth := ((exited.tip as Vector3) - (state.contact_point as Vector3)).dot(state.stab_direction)
		_check(left_shift > .18 and retreat > .20 and tip_depth < -.03, "actual blade exits the original back-entry plane by moving left and backward")
		_check(actor.dismemberment.severed.is_empty() and actor.ragdoll.parts.has("Head"), "head remains attached throughout the extraction follow-through")
		report.append({"case": "lateral_extraction_geometry", "heel_left_shift_m": left_shift, "tip_retreat_m": retreat, "tip_entry_plane_depth_m": tip_depth})
	player.cancel_execution()
	player.cancel_execution()
	player.advance_execution(REAR.DURATION)
	_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled and actor.dismemberment.detached.is_empty() and _defeats(actor) == 1 and bag.count_item("rune_fragment") == before_rewards + 1, "post-cut cancellation restores player and cannot duplicate death/reward")
	report.append({"case": weapon, "long_tick": long_tick, "initial_distance_m": initial_distance, "blade_length_m": actual_length, "head_bodies": actor.dismemberment.detached.size(), "attached_head_ragdoll": actor.ragdoll.parts.has("Head"), "defeats": _defeats(actor), "rune_rewards": bag.count_item("rune_fragment") - before_rewards})


func _check_half_blade_in_skin(actor, length: float, time: float) -> void:
	var state := player.get_execution_snapshot()
	var blade := _real_blade()
	var direction: Vector3 = state.stab_direction
	var anchor: Vector3 = state.contact_point
	var surfaces := _torso_surface_depths(actor, anchor, direction)
	# CreepPart_torso is an open skin partition (292 boundary edges); the five
	# separate CreepCap_body_* meshes close it only after severance. A triangle
	# segment query cannot require an exit through this visible partition.
	# Independently cross the actual blade segment with the posed skin instead.
	_check(not surfaces.is_empty(), "posed torso must provide actual entry surface evidence")
	if surfaces.is_empty(): return
	var crossings := _torso_segment_crossings(actor, blade.heel, blade.tip)
	_check(not crossings.is_empty(), "actual heel-to-tip blade segment must cross a visible posed torso triangle")
	if crossings.is_empty(): return
	var entry: Vector3 = crossings[0]
	for crossing in crossings:
		if crossing.distance_squared_to(anchor) < entry.distance_squared_to(anchor): entry = crossing
	var cast_entry: Vector3 = anchor + direction * surfaces[0]
	_check(entry.distance_to(cast_entry) < .025, "actual blade crossing must agree with the independently cast back skin entry")
	var depth: float = (blade.tip - entry).dot(direction)
	var heel_depth: float = (blade.heel - entry).dot(direction)
	var fraction := depth / length
	var off_axis: float = (blade.tip - anchor - direction * (blade.tip - anchor).dot(direction)).length()
	_check(fraction >= .50 and fraction <= .60 and off_axis < .02, "actual tip-to-posed-skin penetration must be about half the actual blade")
	_check(heel_depth < -.10, "actual blade heel must stay outside the entry while the tip passes into the torso")
	_check(absf(surfaces[0]) < .05, "recoil must preserve back skin contact within five centimetres")
	report.append({"case": "deep_skin", "time": time, "blade_length_m": length, "depth_fraction": fraction, "heel_depth_m": heel_depth, "off_axis_m": off_axis, "surface_depths_m": surfaces, "blade_skin_crossings": crossings.size(), "entry_cast_difference_m": entry.distance_to(cast_entry), "exit_required": false})


func _cancellation_boundaries() -> void:
	for mode: String in ["equipment", "player_death", "menu", "explicit", "target_detached", "new_wall"]:
		var actor = await _new_rear_actor()
		var rewards := bag.count_item("rune_fragment")
		if not _start_rear(actor): continue
		_advance_rear_to(.84)
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
		_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled, "cancelled rear execution releases player/render mode: " + mode)
		_check(actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "cancelled live target must be released and alerted: " + mode)
		_check(actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and actor.ragdoll.phase == "living" and _defeats(actor) == 0 and bag.count_item("rune_fragment") == rewards, "cancel before cut must not create delayed severance, dead hold or rewards: " + mode)
		_check(not actor.can_begin_rear_takedown(player), "cancelled target cannot immediately become unaware again: " + mode)


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
	report.append({"case": "execution_arm_reach", "phase": phase, "time": player.execution_elapsed, "shoulder_to_wrist_m": reach, "authored_shoulder_to_wrist_m": requested_reach, "shoulder_adjustment_m": adjustment, "grip_error_m": grip.error})
	if not wrist.is_empty(): report.append({"case": "actual_wrist_axis", "phase": phase, "measurement": wrist})


func _wrist_motion_sequence() -> void:
	var actor = await _new_rear_actor()
	if not _start_rear(actor): return
	var times: Array[float] = [0.0]
	for frame in range(1, int(ceil(REAR.DURATION / STEP)) + 1): times.append(minf(REAR.DURATION, frame * STEP))
	var boundaries: Array[float] = [REAR.PREPARE_END, REAR.STAB_HIT, REAR.HOLD_END, REAR.WITHDRAW_END, REAR.CUT_START, REAR.CUT_HIT, REAR.CUT_END, REAR.DURATION]
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
		var blade := _real_blade()
		var state := player.get_execution_snapshot()
		var depth: float = (blade.tip - state.contact_point).dot(state.stab_direction)
		var projection := measure_blade_projection(player.camera, blade.heel, blade.tip, state.contact_point, state.stab_direction)
		var weapon_basis := player.weapon_pivot.global_basis.orthonormalized()
		var strict_axis := (time >= REAR.PREPARE_END and time <= REAR.WITHDRAW_END and depth > 0.0) or (time >= REAR.STAB_HIT and time <= REAR.WITHDRAW_END) or absf(time - REAR.CUT_HIT) < .001
		if strict_axis:
			maximum_mismatch = maxf(maximum_mismatch, float(actual.axis_mismatch_degrees))
			_check(float(actual.axis_mismatch_degrees) <= 45.0, "actual hand/forearm axis mismatch exceeds 45 degrees at %.5fs" % time)
		if time >= REAR.PREPARE_END and time <= REAR.HOLD_END:
			if not embedded_seen:
				embedded_basis = weapon_basis
				embedded_seen = true
			var drift := basis_angle_degrees(embedded_basis, weapon_basis)
			maximum_fixed_rotation = maxf(maximum_fixed_rotation, drift)
			_check(drift <= .10, "thrust and embedded hold must preserve actual world blade rotation at %.5fs" % time)
		if time >= REAR.STAB_HIT and time <= REAR.CUT_HIT:
			_check(int(projection.in_frame_samples) >= 2 and float(projection.projected_span_px) > 1.0, "an exposed blade segment must project in front of the camera through the lethal lateral cut")
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
	report.append({"case": "full_wrist_continuity", "sample_count": samples.size(), "maximum_joint_step_m": maximum_step, "maximum_step_time": maximum_step_time, "maximum_hand_rotation_step_degrees": maximum_rotation, "maximum_embedded_axis_mismatch_degrees": maximum_mismatch, "maximum_fixed_blade_rotation_degrees": maximum_fixed_rotation, "projection_stages": projection_stages})


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
	return {"available": true, "wrist_world": wrist, "elbow_world": elbow, "shoulder_world": shoulder,
		"hand_basis_world": hand.basis.orthonormalized(), "neutral_hand_axis_world": hand_axis,
		"actual_forearm_axis_world": actual_forearm,
		"axis_mismatch_degrees": rad_to_deg(hand_axis.angle_to(actual_forearm)),
		"legacy_axis_mismatch_degrees": rad_to_deg(legacy_axis.angle_to(actual_forearm)),
		"measurement_scope": "Authored rig neutral axis versus posed forearm; not a clinical wrist angle."}


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
	_advance_rear_to(.84)
	# A low corner formerly blocked an unnecessary post-stab step toward the
	# neck. Lateral extraction must stay planted and finish without that step.
	wall = _add_box(Vector3(1.4, .65, .10), actor.global_position + Vector3(0, -.25, .65))
	var side_wall := _add_box(Vector3(.10, .65, 1.0), actor.global_position + Vector3(-.75, -.25, 1.10))
	await physics_frame
	await physics_frame
	_check(player._rear_takedown_has_clear_path(actor), "low-corner fixture isolates capsule obstruction from eye-line obstruction")
	var initial_position := player.global_position
	var elapsed := player.execution_elapsed
	while elapsed < REAR.CUT_HIT + .03 and player.is_execution_active():
		player.advance_execution(STEP)
		player._update_viewmodel(0.0)
		elapsed += STEP
		if actor.health <= 0.0: actor.ragdoll.set_physics_process(false)
	var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
	_check(player.global_position.distance_to(initial_position) < .005 and absf(distance - REAR.STAB_DISTANCE) < .02, "lateral finish must not move the capsule into a nearby low corner")
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and actor.ragdoll.parts.has("Head"), "planted lateral cut completes with an intact-head physical corpse")
	_check(actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and _defeats(actor) == 1 and landed.size() == hits + 1 and bag.count_item("rune_fragment") == rewards + 1, "low corner cannot revive old neck-cut movement or duplicate death/reward")
	report.append({"case": "planted_lateral_finish_by_corner", "remaining_distance_m": distance, "actual_step_m": player.global_position.distance_to(initial_position), "defeats": _defeats(actor)})
	side_wall.get_parent().remove_child(side_wall)
	side_wall.queue_free()


func _blocked_initial_approach() -> void:
	var actor = await _new_rear_actor()
	_prepare_player(actor, Vector3(0, 0, 1.49))
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
		while elapsed < REAR.STAB_HIT + STEP and player.is_execution_active():
			player.advance_combat_state(STEP)
			player._update_viewmodel(STEP)
			elapsed += STEP
			var blade := _real_blade()
			deepest_tip = maxf(deepest_tip, (blade.tip - anchor).dot(direction))
			contact_committed = contact_committed or bool(player.get_execution_snapshot().stab_contact_committed)
		_check(not player.is_execution_active() and elapsed < REAR.STAB_HIT, "blocked initial approach must cancel before the first deep stab event")
		_check(not contact_committed and deepest_tip < .03, "blocked initial approach must never commit a stab or display a deeply buried blade")
		_check(player.global_position.z >= wall.global_position.z + .05 + .36 - .015 and player.global_position.distance_to(initial_position) < .15, "far executor capsule must stop at the initial low corner")
		player.advance_execution(REAR.DURATION)
		_check(not player.viewmodel_renderer.world_contact_enabled and actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "early obstruction must release a living alerted enemy and normal player rendering")
		_check(actor.global_transform.is_equal_approx(original_root) and actor.dismemberment.detached.is_empty() and actor.dismemberment.severed.is_empty() and actor.ragdoll.phase == "living" and _defeats(actor) == 0 and landed.size() == hits and bag.count_item("rune_fragment") == rewards, "failed initial approach must not leave a held target, delayed cut, death or reward")
		report.append({"case": "blocked_initial_capsule_approach", "initial_distance_m": 1.49, "cancellation_time": elapsed, "actual_step_m": player.global_position.distance_to(initial_position), "deepest_tip_depth_m": deepest_tip, "stab_contact_committed": contact_committed})
	side_wall.get_parent().remove_child(side_wall)
	side_wall.queue_free()


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
