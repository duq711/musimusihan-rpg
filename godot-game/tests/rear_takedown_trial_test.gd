extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const MOTION := preload("res://scripts/rear_takedown_motion.gd")
const IDS: Array[String] = ["rear_takedown", "rear_takedown:alerted", "rear_takedown:front"]
const PAYLOADS: Array[String] = ["rear", "alerted", "front"]

var failures: Array[String] = []
var room: Node3D
var defeats := 0
var actual_checks := false
var default_encounters: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	original.equipment["weapon"] = "hunting_bow"
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 61.0
	var before := ExpeditionSession.capture_snapshot()
	var cursor_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	# Advance the public production action clock deliberately. F2 still routes
	# as a scene event; no OS pointer capture or hardware E input is tested.
	room.player.set_physics_process(false)
	default_encounters = _encounter_layout()
	_check(sandbox.active and room.inventory != original, "rear takedown trial owns an isolated inventory")
	_test_catalog()
	if CREEP.is_available():
		actual_checks = true
		await _test_complete_sequence()
		await _test_denials()
		await _test_pause_cancel_reselect_reset()
	else:
		_test_missing_asset()
	_check(original.slots == original_slots and original.equipment == original_equipment, "trial equipment and rewards preserve original inventory")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "exit restores exact expedition and inventory identity")
	_check(Input.mouse_mode == cursor_before, "exit restores original cursor mode")
	for failure in failures:
		push_error("REAR TAKEDOWN TRIAL TEST FAIL: " + failure)
	print("REAR TAKEDOWN TRIAL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + ("real F2 unaware/alerted/front fixtures, public E action API, contact blood/deep stab/twist reaction/straight pull-out/blade-clear ragdoll, attached-head death and single reward, pause/cancel/replay/reset, exact expedition restore; no OS hardware input" if actual_checks else "catalog, missing-asset guidance and session restore; actual Creep sequence SKIPPED"))
	quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	for index in IDS.size():
		var matches: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == IDS[index])
		_check(matches.size() == 1, "unique rear takedown entry: " + IDS[index])
		if matches.size() != 1: continue
		var entry: Dictionary = matches[0]
		_check(entry.category == "기본" and entry.action == "rear_takedown" and entry.payload == PAYLOADS[index], "real rear/alerted/front dispatch: " + IDS[index])
		_check(entry.detail.contains("E") and entry.detail.contains("F2"), "entry explains interaction and repeat controls")


func _test_complete_sequence() -> void:
	room.run_feature(IDS[0])
	var creep = _find_creep()
	_check(creep != null, "unaware trial creates a real Creep")
	if creep == null: return
	_check(room.inventory.equipment.get("weapon", "") == "rusted_sword" and not room.player.is_dagger_equipped(), "trial equips the supported actual sword")
	_check(creep.health == creep.max_health and creep.dismemberment.severed.is_empty() and creep.ai_state == DungeonEnemy.AIState.IDLE, "target starts healthy, intact and unaware")
	_check(room.enemy_ai_enabled and creep.is_physics_processing() and not paused, "fixture keeps production enemy AI running")
	await _frames(3)
	_check(creep.ai_state == DungeonEnemy.AIState.IDLE and room.player.get_rear_takedown_target() == creep, "unseen rear player can select the healthy target")
	creep.defeated.connect(func(_actor: DungeonEnemy) -> void: defeats += 1)
	var prior_defeats := defeats
	var prior_loot: int = room.loot_count
	var prior_fragments: int = room.inventory.count_item("rune_fragment")
	var initial_health: float = creep.health
	var accepted: Dictionary = room.player.begin_rear_takedown()
	_check(bool(accepted.get("accepted", false)), "public E action API accepts unaware rear sword target: " + str(accepted))
	if not bool(accepted.get("accepted", false)): return
	_check(room.player.is_execution_active() and room.player.get_execution_snapshot().get("profile", "") == "rear_sword", "accepted action owns the paired rear-sword clock")
	_advance_to(MOTION.STAB_CONTACT - .001)
	_check(int(creep.get_rear_takedown_blood_snapshot().burst_count) == 0 and not is_instance_valid(creep._rear_stab_blood), "public action emits no blood before real contact")
	_advance_to(MOTION.STAB_CONTACT + .001)
	var blood: Dictionary = creep.get_rear_takedown_blood_snapshot()
	_check(int(blood.burst_count) == 1 and is_instance_valid(creep._rear_stab_blood) and int(blood.effect.spawned_droplet_count) == 24, "real public contact creates exactly one actual 3D droplet burst")
	_check(not creep.commit_rear_stab_contact(room.player, blood.contact_point) and int(creep.get_rear_takedown_blood_snapshot().burst_count) == 1, "repeated public contact cannot emit a second burst")
	_advance_to(MOTION.STAB_HIT - .001)
	_check(creep.health == initial_health and not creep.dismemberment.severed.has("head"), "pre-stab reservation cannot prematurely kill or sever")
	_advance_to(MOTION.STAB_HIT + .001)
	_check(creep.health == 0.0 and creep.ai_state == DungeonEnemy.AIState.DEAD and creep.ragdoll.phase == "execution_hold" and creep.ragdoll.parts.is_empty() and creep.dismemberment.severed.is_empty(), "deep stab kills once and supports the intact corpse while the blade remains inside")
	_check(defeats == prior_defeats + 1 and room.enemies_alive == 0 and room.loot_count == prior_loot + 1 and room.inventory.count_item("rune_fragment") == prior_fragments + 1, "actual room callback awards exactly one death and reward at the deep stab")
	var deep_chest: Transform3D = creep.skeleton.get_bone_global_pose(creep.skeleton.find_bone("Chest"))
	_advance_to(MOTION.TWIST_END)
	var twisted_chest: Transform3D = creep.skeleton.get_bone_global_pose(creep.skeleton.find_bone("Chest"))
	var reaction: Dictionary = creep.get_rear_takedown_reaction_snapshot()
	_check(not deep_chest.is_equal_approx(twisted_chest) and float(reaction.get("twist_weight", 0.0)) > .99, "actual corpse chest reacts to the sword twist before straight extraction")
	_check(int(creep.get_rear_takedown_blood_snapshot().burst_count) == 1, "twist cannot repeat the stabbing blood event")
	var held_basis: Basis = room.player.weapon_pivot.global_basis.orthonormalized()
	_advance_to((MOTION.HOLD_END + MOTION.WITHDRAW_END) * .5)
	_check(creep.ragdoll.phase == "execution_hold" and creep.ragdoll.parts.is_empty(), "mid-withdrawal still holds the corpse while steel is embedded")
	_check(held_basis.is_equal_approx(room.player.weapon_pivot.global_basis.orthonormalized()), "public E action preserves blade roll during straight withdrawal")
	_advance_to(MOTION.WITHDRAW_END)
	var state: Dictionary = room.player.get_execution_snapshot()
	var tip: Vector3 = room.player.weapon_pivot.to_global(room.player._execution_blade_tip)
	var depth := (tip - (state.contact_point as Vector3)).dot(state.stab_direction)
	_check(depth <= -MOTION.WITHDRAW_CLEARANCE + .002 and creep.ragdoll.phase == "simulating" and creep.ragdoll.parts.has("Head"), "actual cleared blade releases the full attached-head corpse into physics")
	_check(defeats == prior_defeats + 1 and room.loot_count == prior_loot + 1, "release cannot duplicate the deep-stab death or reward")
	_advance_to(MOTION.DURATION + .05)
	room.player.advance_execution(3.0)
	await _frames(3)
	_check(not room.player.is_execution_active() and defeats == prior_defeats + 1 and room.loot_count == prior_loot + 1, "recovery finishes without duplicate death or reward")


func _test_denials() -> void:
	for feature_id in [IDS[1], IDS[2]]:
		room.run_feature(feature_id)
		var creep = _find_creep()
		_check(creep != null, "denial trial creates a healthy real enemy: " + feature_id)
		if creep == null: continue
		var health: float = creep.health
		var state: int = creep.ai_state
		var prior_loot: int = room.loot_count
		var accepted: Dictionary = room.player.begin_rear_takedown()
		_check(not bool(accepted.get("accepted", true)) and room.player.get_rear_takedown_target() == null, "public action denies alerted/front target: " + feature_id)
		_check(creep.ai_state == state and creep.ai_state != DungeonEnemy.AIState.EXECUTION and creep.is_physics_processing() and room.enemy_ai_enabled, "rejection cannot reserve or freeze enemy AI: " + feature_id)
		room.player.advance_execution(MOTION.DURATION + .1)
		_check(creep.health == health and creep.dismemberment.severed.is_empty() and room.loot_count == prior_loot, "denied action causes no damage, severing or reward: " + feature_id)
		await _frames(3)
		_check(creep.ai_state != DungeonEnemy.AIState.IDLE and creep.ai_state != DungeonEnemy.AIState.EXECUTION, "denied target continues real perception/combat: " + feature_id)


func _test_pause_cancel_reselect_reset() -> void:
	room.run_feature(IDS[0])
	var creep = _find_creep()
	if creep == null: return
	var result: Dictionary = room.player.begin_rear_takedown()
	_check(bool(result.get("accepted", false)), "pause trial begins the public paired action")
	if not bool(result.get("accepted", false)): return
	_advance_to(MOTION.STAB_HIT + .02)
	var elapsed: float = room.player.execution_elapsed
	var health: float = creep.health
	var weapon_pose: Transform3D = room.player.weapon_pivot.transform
	await _press_f2()
	var paused_blood: Dictionary = creep.get_rear_takedown_blood_snapshot()
	_check(int(paused_blood.burst_count) == 1 and not paused_blood.effect.is_empty(), "F2 pause fixture contains the real contact effect")
	room.player.advance_execution(5.0)
	await _frames(5)
	_check(paused and room.panel_open and room.player.is_execution_active() and room.player.execution_elapsed == elapsed, "F2 freezes the shared rear action instead of cancelling")
	_check(creep.health == health and not creep.dismemberment.severed.has("head") and room.player.weapon_pivot.transform.is_equal_approx(weapon_pose), "F2 retains the dead held target and blade pose")
	var still_blood: Dictionary = creep.get_rear_takedown_blood_snapshot()
	_check(still_blood == paused_blood, "F2 freezes blood age, world droplet positions and stains with the paired action")
	await _press_f2()
	await _frames(3)
	_check(float(creep.get_rear_takedown_blood_snapshot().effect.age) > float(paused_blood.effect.age), "closing F2 resumes the blood simulation")
	_advance_to((MOTION.HOLD_END + MOTION.WITHDRAW_END) * .5)
	var loot_before: int = room.loot_count
	room.player.cancel_execution()
	_check(not room.player.is_execution_active() and creep.ai_state == DungeonEnemy.AIState.DEAD and creep.health == 0.0 and creep.ragdoll.phase == "simulating" and creep.ragdoll.parts.has("Head"), "cancel releases a dead blade-held target into attached-head physics")
	room.player.advance_execution(5.0)
	_check(not creep.dismemberment.severed.has("head") and room.loot_count == loot_before, "cancelled dead hold cannot deliver duplicate death or rewards")
	var old_blood = creep._rear_stab_blood
	room.player.stamina = 3.0
	room.run_feature(IDS[0])
	var fresh = _find_creep()
	_check(creep.is_queued_for_deletion() and fresh != creep and fresh.health == fresh.max_health and fresh.dismemberment.severed.is_empty(), "reselection replaces the target with a healthy intact creature")
	_check(room.player.stamina == room.player.MAX_STAMINA and room.player.health == room.player.MAX_HEALTH, "reselection restores player health and stamina")
	_check(int(fresh.get_rear_takedown_blood_snapshot().burst_count) == 0 and not is_instance_valid(fresh._rear_stab_blood), "fresh target cannot inherit the previous wound event")
	await _frames(2)
	_check(not is_instance_valid(old_blood), "reselection deletes the previous target-owned blood effect")
	result = room.player.begin_rear_takedown()
	_check(bool(result.get("accepted", false)), "reset trial begins a second real reservation")
	if bool(result.get("accepted", false)): _advance_to(MOTION.STAB_HIT + .01)
	var reset_blood = fresh._rear_stab_blood
	var removed_target_id: int = fresh.get_instance_id()
	room.reset_room()
	await _frames(2)
	_check(not is_instance_valid(reset_blood), "F2 reset removes actual blood droplets and contact stains")
	# Default encounter archetypes may vary. Verify their baseline layout and
	# fresh ownership instead of incorrectly requiring no Creep instances.
	_check(paused and room.panel_open and not room.enemy_ai_enabled and _encounter_layout() == default_encounters and room.enemies_alive == default_encounters.size() and room.loot_count == 0, "reset clears rear targets and restores the paused default encounters")
	for actor in room.get_children():
		if actor is DungeonEnemy and not actor.is_queued_for_deletion():
			_check(actor.get_instance_id() != removed_target_id and actor.health == actor.max_health and not actor.is_physics_processing() and not is_instance_valid(actor.get("_execution_executor")), "reset default enemies are fresh, healthy, AI-paused and unreserved")
	_check(not room.player.is_execution_active(), "reset cannot leave stale execution ownership")
	room.player.advance_execution(5.0)
	_check(room.loot_count == 0, "reset cannot later award the removed target")


func _test_missing_asset() -> void:
	var equipment: Dictionary = room.inventory.equipment.duplicate(true)
	var position: Vector3 = room.player.position
	var count: int = room.enemies_alive
	for feature_id in IDS:
		room.run_feature(feature_id)
		_check(_find_creep() == null and room.enemies_alive == count and room.inventory.equipment == equipment and room.player.position == position, "missing model preserves equipment and original fixture: " + feature_id)
		_check(paused and room.panel_open and room.status_label.text.contains("CREEP_ASSET.md"), "missing model keeps menu open with installation guidance")


func _advance_to(seconds: float) -> void:
	var remaining: float = maxf(0.0, seconds - room.player.execution_elapsed)
	while remaining > .00001 and room.player.is_execution_active():
		var step := minf(.01, remaining)
		room.player._advance_execution_movement(step)
		room.player.advance_execution(step)
		room.player._update_viewmodel(0.0)
		remaining -= step


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _find_creep():
	for actor in room.get_children():
		if actor is CREEP and not actor.is_queued_for_deletion(): return actor
	return null


func _encounter_layout() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in room.get_children():
		if actor is DungeonEnemy and not actor.is_queued_for_deletion():
			result.append({"name": actor.display_name, "position": actor.position, "max_health": actor.max_health, "script": actor.get_script().resource_path})
	return result


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
