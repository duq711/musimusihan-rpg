extends SceneTree
const ROOM_PATH := "res://test_room.tscn"
const STATIC_GRIP := preload("res://tests/sword_long_grip_test.gd")
const FAMILIES := ["sword", "shield", "bow", "flail", "staff", "torch", "chest", "shield_cut_right", "shield_cut_left", "shield_cut_overhead", "shield_raise", "shield_impact"]
const CUT_MODES := {"shield_cut_right": "right_diagonal", "shield_cut_left": "left_reverse", "shield_cut_overhead": "overhead"}
const ACTION_STEP := 1.0 / 120.0
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	var original_weapon := original.get_equipment_instance("weapon")
	original_weapon["uid"] = "motion_original_weapon"
	original_weapon["smithing"] = {"quality": 0.83, "grip": "balanced", "reinforcement": "silver", "sockets": 1, "runes": ["ember"], "drill_progress": 0.25}
	ExpeditionSession.crowns = 127
	ExpeditionSession.hunger = 53
	ExpeditionSession.thirst = 47
	ExpeditionSession.stress = 29
	var before := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var original_data := original.equipment_data.duplicate(true)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and bag != original and room.panel_open and paused, "motion trials must begin in the paused isolated test room")
	for family: String in FAMILIES:
		var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "motion_" + family)
		_check(entries.size() == 1 and entries[0].action == "first_person_motion" and entries[0].payload == family, "motion family must have one executable catalog entry: " + family)
		for iteration in range(2):
			if family == "torch" and iteration == 1:
				# A full bag and two occupied hands must not hide the named trial.
				room._equip_weapon("hunting_bow")
				bag.equipment["offhand"] = "round_shield"
				bag.equipment["utility"] = ""
				bag.equipment_data.erase("utility")
				var carried_bow := bag.get_equipment_instance("weapon")
				carried_bow["uid"] = "torch_trial_carried_bow"
				for index in range(ExpeditionInventory.MAX_SLOTS):
					bag.add_item("rusted_sword", 1, false)
				_check(bag.slots.size() == ExpeditionInventory.MAX_SLOTS, "torch repeat must exercise a full trial bag")
			room.run_feature("motion_" + family)
			var player: DungeonPlayer = room.player
			player.set_physics_process(false)
			await physics_frame
			await physics_frame
			_check(not paused and not room.panel_open and player.health == 100 and player.stamina == 100, "motion trial must resume real play with restored actor: " + family)
			_check(not player.safe_zone_mode, "motion trial must never leave a safe-zone flag on the combat room")
			_check(player.sword_attack_mode == str(CUT_MODES.get(family, "cycle")), "motion fixture must select its real fixed cut or restore the ordinary cycle: " + family)
			if family == "torch" and iteration == 1:
				var returned_bows := bag.slots.filter(func(stack: Dictionary) -> bool: return str(stack.get("instance", {}).get("uid", "")) == "torch_trial_carried_bow")
				_check(returned_bows.size() == 1, "torch preparation must preserve the normally unequipped weapon instance even with a full bag")
			await _exercise(room, family)
			var f2 := InputEventKey.new()
			f2.keycode = KEY_F2
			f2.physical_keycode = KEY_F2
			f2.pressed = true
			room._unhandled_input(f2)
			_check(paused and room.panel_open and not player.is_timed_interacting() and not player.bow_drawing and not player._is_flail_busy(), "F2 must cancel in-progress hand/weapon actions and restore the paused menu: " + family)
			_check(player.combat_state == DungeonPlayer.CombatState.READY and not player.blocking, "F2 must cancel the current sword attack and release guard before the next trial: " + family)
			_check(not player.attack_release_requested and is_zero_approx(player._shield_impact), "F2 must clear pending sword release and shield impact: " + family)
			_check(player.get_next_sword_attack_variant() == str(CUT_MODES.get(family, "right_diagonal")), "F2 must reset the cycle while retaining a focused trial's selected cut: " + family)
			var frozen_motion := player.get_first_person_motion_snapshot().duplicate(true)
			_advance_sword_shield(player, 0.4, true)
			_check(player.get_first_person_motion_snapshot() == frozen_motion, "paused motion menu must freeze real attack, guard and hand transforms: " + family)
			var hunger := ExpeditionSession.hunger
			await create_timer(0.025, true).timeout
			_check(is_equal_approx(hunger, ExpeditionSession.hunger), "motion menu must pause survival")
			_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data and sandbox.saved_session == before, "motion actions must remain isolated from the original equipped item IDs, weapon instances and expedition")
	room.reset_room()
	_check(room.inventory != bag and room.inventory != original and room.panel_open and paused, "motion trial reset must create a fresh isolated bag")
	room.run_feature("motion_bow")
	_check(room.inventory.count_item("wooden_arrow") == 30, "motion fixture must remain executable after reset")
	_check(room.player.sword_attack_mode == "cycle", "reset followed by an ordinary fixture must not retain a fixed sword cut")
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "motion trial exit must restore original inventory identity and every expedition value")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "motion trial exit must preserve original arrows, equipped item IDs and weapon metadata")
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("FIRST PERSON MOTION TEST ROOM %s: seven motion families plus five sword/shield trials, real cuts/guard/enemy impact, repeated F2, reset and complete original session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _exercise(room: Node3D, family: String) -> void:
	var player: DungeonPlayer = room.player
	match family:
		"sword":
			failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
			failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
			var target: DungeonEnemy = room.arm_motion_target
			var health := target.health
			player._try_begin_attack()
			player._commit_attack()
			player.state_time = player.get_melee_hit_time() + 0.01
			player._resolve_active_attack()
			_check(target.health < health and player.stamina < 100, "sword motion trial must retain actual hit and stamina costs")
		"shield":
			_check(room.enemy_ai_enabled and str(room.inventory.equipment.offhand) == "round_shield", "shield fixture must provide actual attacking enemies and the shield")
			player.blocking = true
			player.block_time = 0.1
			player._update_viewmodel(0.02)
			failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
			failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
			_check_continuous_guard_arm(player.shield_arm, "actual shield hand")
			var result := player.receive_attack(18, player.global_position - player.global_basis.z * 2)
			_check(bool(result.get("blocked", false)) and player._shield_impact > 0, "shield motion must use the production impact response")
		"shield_cut_right", "shield_cut_left", "shield_cut_overhead":
			_exercise_shield_cut(room, family)
		"shield_raise":
			_exercise_shield_raise(room)
		"shield_impact":
			_exercise_shield_impact(room)
		"bow":
			var arrows: int = room.inventory.count_item("wooden_arrow")
			_check(player.begin_bow_draw().accepted, "bow trial must begin actual string draw")
			player._advance_bow_draw(0.5)
			var result := player.release_bow_shot()
			_check(result.accepted and is_instance_valid(result.projectile) and room.inventory.count_item("wooden_arrow") == arrows - 1, "bow release must spawn the actual arrow and consume one")
			player.bow_cooldown = 0
			player.begin_bow_draw()
		"flail":
			_check(player.begin_flail_spin().accepted, "flail trial must begin the production spin")
			player._update_flail(0.7)
			var result := player.release_flail_throw()
			_check(result.accepted and is_instance_valid(player.flail_projectile) and player.stamina < 100, "flail trial must create the actual paid throwing action")
		"staff":
			var result := player.cast_spell("fire_bolt")
			_check(result.accepted and is_instance_valid(result.projectile) and player._cast_recoil > 0, "staff trial must cast the actual learned fire spell")
		"torch":
			_check(str(room.inventory.equipment.weapon).is_empty() and str(room.inventory.equipment.offhand).is_empty() and str(room.inventory.equipment.utility) == "field_torch", "torch fixture must prepare an actual handheld torch without inventory setup")
			player.set_torch_enabled(false)
			_check(not player.torch.visible, "torch motion trial must use the real carried light")
			player.set_torch_enabled(true)
			player.velocity = Vector3(0, 0, -player.SPRINT_SPEED)
			player._update_viewmodel(0.1)
			_check(player.torch.visible, "actual torch must remain lit when sampling sprint motion")
			if player.has_method("get_first_person_motion_snapshot"):
				var motion: Dictionary = player.call("get_first_person_motion_snapshot")
				_check(str(motion.left_hand_role) == "torch" and int(motion.visible_arm_count) > 0 and int(motion.visible_arm_count) <= 2, "torch trial must visibly assign its left hand to the torch with at most two arms")
		"chest":
			var chest: DungeonLootChest = room.loot_chests[0]
			chest.interact(player)
			player.advance_timed_interaction(chest.OPEN_DURATION * 0.55)
			_check(player.is_timed_interacting() and player.chest_equipment_stowed, "chest motion trial must drive real hands and timed chest interaction")
	player._update_viewmodel(0.02)
	await process_frame


func _advance_sword_shield(player: DungeonPlayer, delta: float, block_requested: bool = false) -> void:
	# Advance the same clocks and resolver as gameplay without changing OS input.
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, block_requested)
	player._update_viewmodel(delta)
	player._resolve_active_attack()


func _exercise_shield_cut(room: Node3D, family: String) -> void:
	var player: DungeonPlayer = room.player
	var target: DungeonEnemy = room.arm_motion_target
	var expected := str(CUT_MODES[family])
	_check(not room.enemy_ai_enabled and is_instance_valid(target), "focused cut must prepare a real stationary target: " + family)
	_check(str(room.inventory.equipment.weapon) == "rusted_sword" and str(room.inventory.equipment.offhand) == "round_shield", "focused cut must equip the actual sword and shield: " + family)
	if not is_instance_valid(target): return
	var flat_distance := Vector2(target.global_position.x - player.global_position.x, target.global_position.z - player.global_position.z).length()
	_check(is_equal_approx(flat_distance, 2.0), "focused cut target must begin at the documented two-metre distance: " + family)
	var health := target.health
	var stamina := player.stamina
	var cost := player.get_melee_stamina_cost(0.0)
	var result := player.begin_sword_attack()
	_check(bool(result.get("accepted", false)) and player.sword_attack_variant == expected, "LMB-equivalent attack must use the fixture mode without a test-only variant override: " + family)
	if not bool(result.get("accepted", false)): return
	player.attack_release_requested = true
	var phases: Dictionary = {DungeonPlayer.CombatState.WINDUP: true}
	var locked_variant := true
	for frame in range(240):
		_advance_sword_shield(player, ACTION_STEP)
		phases[player.combat_state] = true
		locked_variant = locked_variant and player.sword_attack_variant == expected
		if player.combat_state == DungeonPlayer.CombatState.READY: break
	_check(locked_variant and phases.has(DungeonPlayer.CombatState.ACTIVE) and phases.has(DungeonPlayer.CombatState.RECOVERY) and phases.has(DungeonPlayer.CombatState.READY), "selected cut must stay locked through real windup, hit, recovery and ready: " + family)
	_check(target.health < health and is_equal_approx(stamina - player.stamina, cost), "focused cut must hit the real target and spend exactly one light-attack cost: " + family)
	_check(player.get_next_sword_attack_variant() == expected, "fixed cut must remain selected for its next attack: " + family)
	# Leave an actual second preparation pending so the following F2 check
	# proves cancellation, rather than merely observing an already idle actor.
	_check(bool(player.begin_sword_attack().get("accepted", false)), "fixed cut must support a second attack before F2 cancellation: " + family)


func _exercise_shield_raise(room: Node3D) -> void:
	var player: DungeonPlayer = room.player
	_check(not room.enemy_ai_enabled and str(room.inventory.equipment.offhand) == "round_shield", "raise trial must provide a real shield and a stationary opponent")
	for frame in range(90): _advance_sword_shield(player, ACTION_STEP)
	var lowered := player.shield_pivot.transform
	var left_grip := player.camera.to_local(player.shield_model.find_child("RearGrip", true, false).global_position)
	var right_grip := player.camera.to_local(player.sword_visual_root.find_child("HandGrip", true, false).global_position)
	_check(right_grip.distance_to(Vector3(-left_grip.x, left_grip.y, left_grip.z)) < 0.002, "lowered hands must match height, depth and mirrored lateral spacing")
	_check(lowered.origin.x < -0.50 and lowered.origin.y < -0.60, "resting shield must sit at the lower-left screen edge")
	var carry := player._shield_corner_offset()
	_check(carry.x < -0.15 and carry.y < -0.30, "actual shield trial must use the corner carry framing")
	var health := player.health
	var stamina := player.stamina
	for frame in range(90): _advance_sword_shield(player, ACTION_STEP, true)
	var raised := player.shield_pivot.transform
	_check(absf(raised.origin.x) < 0.06 and raised.origin.y < -0.48 and raised.origin.y > -0.63 and raised.basis.z.dot(Vector3.BACK) > 0.95, "raised shield must cover the lower center with its broad face, not stand sideways")
	_check(player._shield_corner_offset().is_zero_approx(), "fully raised guard must retain its original protective pose")
	# The reference intentionally crops the supporting hand below the frame.
	# Check the real modeled rim, not the grip's on-screen visibility.
	var rim := player.camera.unproject_position(player.shield_model.to_global(Vector3(0, 0.427, 0))) / player.camera.get_viewport().get_visible_rect().size
	_check(rim.x > 0.45 and rim.x < 0.55 and rim.y > 0.65 and rim.y < 0.82, "guard rim must sit in the lower quarter, leaving central vision open")
	var guard_right := player.camera.to_local(player.sword_visual_root.find_child("HandGrip", true, false).global_position)
	var guard_tip := player.camera.to_local(player.sword_visual_root.find_child("BladeTip", true, false).global_position)
	_check(guard_right.y < -0.60 and guard_tip.y < guard_right.y, "guard must lower both the right hand and sword blade")
	_check(player.blocking and player.block_time > 0.2 and not raised.is_equal_approx(lowered), "holding the real block request must raise the live shield into guard")
	_check(player.health == health and player.stamina == stamina, "raising against the stationary opponent must not simulate a hit or spend attack resources")
	failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
	failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
	_check_continuous_guard_arm(player.shield_arm, "raised guard shield hand")
	for frame in range(90): _advance_sword_shield(player, ACTION_STEP)
	_check(not player.blocking and player.shield_pivot.position.distance_to(lowered.origin) < raised.origin.distance_to(lowered.origin) * 0.2, "releasing the real block request must lower the shield toward its initial position")
	_advance_sword_shield(player, ACTION_STEP, true)
	_check(player.blocking, "raise trial must allow a repeated guard before F2 cancellation")


func _exercise_shield_impact(room: Node3D) -> void:
	var player: DungeonPlayer = room.player
	var attacker: DungeonEnemy = null
	for child in room.get_children():
		if child is DungeonEnemy:
			attacker = child
			break
	_check(room.enemy_ai_enabled and is_instance_valid(attacker) and str(room.inventory.equipment.offhand) == "round_shield", "impact trial must provide the actual attacking opponent and equipped shield")
	if not is_instance_valid(attacker): return
	_check(attacker.is_physics_processing() and attacker.target == player, "impact fixture must initially enable the production enemy AI against this player")
	# Stop its scheduler only while deterministically resolving this one attack;
	# its actual range, facing, line-of-sight and damage resolver remain in use.
	attacker.set_physics_process(false)
	attacker.global_position = player.global_position - player.global_basis.z * 1.5
	attacker.rotation.y = player.rotation.y + PI
	for frame in range(90): _advance_sword_shield(player, ACTION_STEP, true)
	var health := player.health
	var stamina := player.stamina
	var guarded := player.shield_pivot.transform
	attacker._set_state(DungeonEnemy.AIState.ACTIVE)
	attacker.state_time = DungeonEnemy.ATTACK_HIT_TIME
	attacker._resolve_active_attack()
	_check(attacker.attack_has_resolved and attacker.attack_has_connected, "impact trial must connect the real enemy attack through range, facing and line-of-sight")
	_check(is_equal_approx(health, player.health) and is_equal_approx(stamina - player.stamina, attacker.attack_damage * 1.18), "actual sustained guard must prevent health damage and apply one real stamina cost")
	_check(attacker.ai_state != DungeonEnemy.AIState.STAGGER, "ordinary shield impact must not award the just-guard enemy stun")
	_check(player.blocking and player._shield_impact > 0.0, "the enemy's actual hit must trigger the production shield impact response")
	player._update_viewmodel(0.02)
	_check(not player.shield_pivot.transform.is_equal_approx(guarded), "the live equipped shield must move in response to the resolved enemy impact")


func _check_continuous_guard_arm(arm: Node3D, context: String) -> void:
	_check(is_instance_valid(arm), context + " must be created by the executable shield trial")
	if not is_instance_valid(arm): return
	_check(bool(arm.get_meta("continuous_skin", false)), context + " must select the continuous skin rig")
	var skeleton := arm.get("skeleton") as Skeleton3D
	_check(skeleton != null and skeleton.get_bone_count() == 16, context + " must own the actual sixteen-bone hand skeleton")
	if skeleton == null: return
	var curled_bones: Array[int] = []
	for bone_name: String in ["index0", "middle1", "thumb1"]:
		var bone := skeleton.find_bone(bone_name)
		_check(bone >= 0, context + " must expose its real gripping joint: " + bone_name)
		if bone < 0: continue
		var rotation := skeleton.get_bone_pose_rotation(bone)
		_check(rotation.is_finite() and not rotation.is_equal_approx(Quaternion.IDENTITY), context + " must rotate the real finger bone while gripping: " + bone_name)
		curled_bones.append(bone)
	var skinned_mesh_count := 0
	var weighted_vertices := 0
	var weighted_bones := {}
	for part: MeshInstance3D in arm.find_children("*", "MeshInstance3D", true, false):
		if part.skin == null or part.mesh == null: continue
		skinned_mesh_count += 1
		_check(part.is_visible_in_tree(), context + " must render its weighted hand mesh during guard")
		_check(part.get_node_or_null(part.skeleton) == skeleton, context + " skin mesh must be bound to the same skeleton whose fingers are gripping")
		var bind_count := part.skin.get_bind_count()
		_check(bind_count > 0, context + " must have real skin bindings rather than only a continuous_skin label")
		for surface in range(part.mesh.get_surface_count()):
			var arrays := part.mesh.surface_get_arrays(surface)
			if not (arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array and arrays[Mesh.ARRAY_BONES] is PackedInt32Array and arrays[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array):
				_check(false, context + " rendered skin surface must provide vertices, bone indices and weights")
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var complete := not vertices.is_empty() and bones.size() == weights.size() and bones.size() in [vertices.size() * 4, vertices.size() * 8]
			_check(complete, context + " skin surface must supply a complete set of bone influences for each vertex")
			if not complete: continue
			var influences := 4 if bones.size() == vertices.size() * 4 else 8
			var valid_surface := true
			for vertex in range(vertices.size()):
				var total := 0.0
				for influence in range(influences):
					var index := vertex * influences + influence
					var weight := weights[index]
					if not is_finite(weight) or weight < 0.0 or weight > 1.001:
						valid_surface = false
						continue
					total += weight
					if weight <= 0.00001: continue
					var binding := bones[index]
					if binding < 0 or binding >= bind_count:
						valid_surface = false
						continue
					var actual_bone := part.skin.get_bind_bone(binding)
					if actual_bone < 0: actual_bone = skeleton.find_bone(str(part.skin.get_bind_name(binding)))
					if actual_bone < 0 or actual_bone >= skeleton.get_bone_count(): valid_surface = false
					else: weighted_bones[actual_bone] = true
				if absf(total - 1.0) > 0.002: valid_surface = false
			_check(valid_surface, context + " vertices must have finite normalized weights bound to real bones")
			weighted_vertices += vertices.size()
	_check(skinned_mesh_count > 0 and weighted_vertices >= 3 and weighted_bones.size() >= 4, context + " must contain actual skin geometry influenced by palm and finger bones")
	for bone in curled_bones:
		_check(weighted_bones.has(bone), context + " gripping rotations must deform the rendered hand, not an unused decorative skeleton")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "motion trial scene transition timed out: " + path)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
