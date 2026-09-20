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
	await _cancellation_boundaries()
	await _blocked_approach()
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
	print("REAR TAKEDOWN TEST %s: unaware rear gates, actual skin/half-blade/neck contact, ordered long tick, one severance/death/reward, cancellation and preserved session" % ("PASS" if failures.is_empty() else "FAIL"))
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
	_check(not ordinary.can_begin_rear_takedown(player), "unsupported enemy without authored detachable neck must fail explicitly")


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
	_check(not actor.finish_rear_takedown(player), "direct premature finish cannot sever a head before cut contact")
	_check(not actor.finish_execution(player), "old execution finish cannot bypass the new neck-cut clock")
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
	var geometry := _real_blade()
	var actual_length: float = geometry.length
	_check(actual_length > .40 and absf(actual_length - player.get_execution_snapshot().blade_length_m) < .002, "execution must measure the actual equipped blade vertices in world metres")
	if long_tick:
		player.advance_execution(REAR.CUT_HIT + .01)
		player._update_viewmodel(0.0)
		_check(bool(player.get_execution_snapshot().stab_contact_committed), "long frame must resolve real stab contact before the neck-cut event")
		_check_execution_arm_reach("cut")
	else:
		for time: float in [REAR.PREPARE_END, REAR.STAB_HIT - .001, REAR.STAB_HIT, .82, REAR.HOLD_END, REAR.WITHDRAW_END, REAR.CUT_HIT - .001]:
			_advance_rear_to(time)
			_check(player.is_execution_active(), "valid staged rear execution remains active at %.3f" % time)
			_check(actor.health == hp and actor.dismemberment.severed.is_empty() and actor.dismemberment.detached.is_empty() and _defeats(actor) == 0 and landed.size() == before_hits, "stab, hold and extraction must keep the target alive and head attached at %.3f" % time)
			_check(actor.ragdoll.phase == "living" and actor.ragdoll.parts.is_empty(), "no early physical death or held corpse during rear stab")
			_check(actor.global_transform.is_equal_approx(entry_root), "standing reaction must keep navigation root planted")
			for bone_name: String in before_lower:
				_check(actor.skeleton.get_bone_pose(actor.skeleton.find_bone(bone_name)).is_equal_approx(before_lower[bone_name]), "standing rear reaction must preserve lower body: " + bone_name)
			if time >= REAR.STAB_HIT and time <= REAR.HOLD_END:
				_check_half_blade_in_skin(actor, actual_length, time)
				if is_equal_approx(time, REAR.STAB_HIT): _check_execution_arm_reach("deep_stab")
			if time <= REAR.HOLD_END:
				if is_equal_approx(initial_distance, 1.15):
					_check(player.global_position.distance_to(entry_player_position) < .001, "near player must not start the short neck-cut step while the blade is buried")
				else:
					var stab_distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
					_check(absf(stab_distance - 1.15) < .015 and player.global_position.distance_to(entry_player_position) > .25, "far rear reservation must use actual collision-tested approach before the deep stab")
			if is_equal_approx(time, REAR.WITHDRAW_END):
				var state := player.get_execution_snapshot()
				var blade := _real_blade()
				_check((blade.tip - state.contact_point).dot(state.stab_direction) < -.15, "actual blade tip must exit the back before wide neck slash")
			if time < REAR.CUT_HIT:
				_check(not actor.finish_rear_takedown(player), "premature finish remains refused throughout live sequence")
		var neck := _actual_neck_center(actor)
		var blade := _real_blade()
		var closest := Geometry3D.get_closest_point_to_segment(neck, blade.heel, blade.tip)
		var fraction: float = (closest - blade.heel).length() / actual_length
		_check(neck.distance_to(closest) < .055 and fraction > .75 and fraction < .98, "actual forward cutting edge, clear of the tip and hilt, must approach the posed neck cap before death")
		var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
		_check(distance >= .78 and distance <= .88 and player.global_position.distance_to(entry_player_position) > .20, "actual collision-tested player step must bring the neck within arm reach without moving the target")
		_check_execution_arm_reach("cut")
		report.append({"case": "precut_geometry", "neck_edge_distance_m": neck.distance_to(closest), "blade_fraction_from_heel": fraction})
		_advance_rear_to(REAR.CUT_HIT)
	actor.ragdoll.set_physics_process(false)
	_check(actor.health == 0.0 and actor.ai_state == DungeonEnemy.AIState.DEAD and _defeats(actor) == 1, "neck-cut contact causes exactly one death")
	_check(actor.dismemberment.severed == ["head"] and actor.dismemberment.detached.size() == 1, "one finishing slash must detach exactly the real head")
	_check(actor.ragdoll.phase == "simulating" and not actor.ragdoll.parts.has("Head"), "decapitated body must enter immediate physics without a duplicate physical head")
	_check(landed.size() == before_hits + 1 and bag.count_item("rune_fragment") == before_rewards + 1 and reward_game.loot_count == 1, "actual game reward receiver must grant exactly one rune and one landed event")
	var count: int = actor.dismemberment.detached.size()
	_check(not actor.finish_rear_takedown(player), "duplicate neck finish cannot create another head or reward")
	player.cancel_execution()
	player.cancel_execution()
	player.advance_execution(REAR.DURATION)
	_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled and actor.dismemberment.detached.size() == count and _defeats(actor) == 1 and bag.count_item("rune_fragment") == before_rewards + 1, "post-cut cancellation restores player and cannot duplicate death/reward")
	report.append({"case": weapon, "long_tick": long_tick, "initial_distance_m": initial_distance, "blade_length_m": actual_length, "head_bodies": count, "defeats": _defeats(actor), "rune_rewards": bag.count_item("rune_fragment") - before_rewards})


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
	report.append({"case": "execution_arm_reach", "phase": phase, "time": player.execution_elapsed, "shoulder_to_wrist_m": reach, "authored_shoulder_to_wrist_m": requested_reach, "shoulder_adjustment_m": adjustment, "grip_error_m": grip.error})


func _blocked_approach() -> void:
	var actor = await _new_rear_actor()
	var original_root: Transform3D = actor.global_transform
	var rewards := bag.count_item("rune_fragment")
	var hits := landed.size()
	if not _start_rear(actor): return
	_advance_rear_to(.84)
	# A low L-shaped corner leaves the eye-to-torso rays clear but blocks the
	# real character capsule. It must not be bypassed by pose-only arm reach.
	wall = _add_box(Vector3(1.4, .65, .10), actor.global_position + Vector3(0, -.25, .65))
	var side_wall := _add_box(Vector3(.10, .65, 1.0), actor.global_position + Vector3(-.75, -.25, 1.10))
	await physics_frame
	await physics_frame
	_check(player._rear_takedown_has_clear_path(actor), "low-corner fixture must isolate capsule obstruction from eye-line obstruction")
	var initial_position := player.global_position
	var elapsed := player.execution_elapsed
	while elapsed < REAR.CUT_HIT + .03 and player.is_execution_active():
		player.advance_execution(STEP)
		player._update_viewmodel(0.0)
		elapsed += STEP
	var distance := Vector2(player.global_position.x - actor.global_position.x, player.global_position.z - actor.global_position.z).length()
	_check(player.global_position.z >= wall.global_position.z + .05 + .36 - .015, "actual capsule must stop before the closed corner instead of moving through it")
	_check(distance > .95 and player.global_position.distance_to(initial_position) < .20, "physical obstruction must prevent the short execution approach")
	_check(not player.is_execution_active() and not player.viewmodel_renderer.world_contact_enabled, "unreachable neck cut must cancel and restore normal player rendering")
	_check(actor.health == actor.max_health and actor.ai_state == DungeonEnemy.AIState.STAGGER and not is_instance_valid(actor._execution_executor), "blocked approach must release a living, alerted target")
	_check(actor.global_transform.is_equal_approx(original_root) and actor.dismemberment.detached.is_empty() and _defeats(actor) == 0 and landed.size() == hits and bag.count_item("rune_fragment") == rewards, "blocked approach cannot move the victim, detach the head or grant a death/reward")
	report.append({"case": "blocked_capsule_approach", "remaining_distance_m": distance, "actual_step_m": player.global_position.distance_to(initial_position), "cancelled": not player.is_execution_active()})
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


func _actual_neck_center(actor) -> Vector3:
	var weighted := Vector3.ZERO
	var total := 0.0
	for cap: MeshInstance3D in actor.dismemberment.body_caps.head:
		var faces: PackedVector3Array = actor.dismemberment._bake_world_mesh(cap, Vector3.ZERO).get_faces()
		for index in range(0, faces.size(), 3):
			var area := (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index]).length() * .5
			weighted += (faces[index] + faces[index + 1] + faces[index + 2]) * area / 3.0
			total += area
	_check(total > 0.0, "real authored neck cap must contain posed triangles")
	return weighted / maxf(total, .0000001)


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
