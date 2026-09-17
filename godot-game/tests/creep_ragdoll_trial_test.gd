extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const TRIALS := {
	"creep_ragdoll": "front",
	"creep_ragdoll:side": "side",
	"creep_ragdoll:wall": "wall",
}

var failures: Array[String] = []
var room: Node3D
var defeat_count := 0
var pause_on_defeat := false
var phase_on_defeat := ""
var clip_on_defeat := ""
var asset_checks_executed := false


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
	ExpeditionSession.set_stress(37.5)
	var before := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	# Freeze only unrelated player/survival updates. The fixture's timer,
	# enemy, ragdoll controller, rigid bodies and pause handling remain real.
	room.set_process(false)
	room.set_physics_process(false)
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original, "ragdoll trial uses a separate expedition and inventory")
	_test_catalog()
	if CREEP.is_available():
		asset_checks_executed = true
		for feature_id: String in TRIALS:
			await _test_trial(feature_id, str(TRIALS[feature_id]))
		await _test_replay_and_cancellation()
	else:
		_test_missing_asset()
	_check(original.slots == original_slots and original.equipment == original_equipment, "ragdoll rewards, loadouts and resets leave the original bag and equipment untouched")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "exiting restores the exact original expedition and inventory identity")
	for failure in failures:
		push_error("CREEP RAGDOLL TRIAL TEST FAIL: " + failure)
	var coverage := "three real fatal-hit timers, reaction and physics pause/resume, single rewards, repeat/reset, isolation and restoration" if asset_checks_executed else "catalog, missing-asset guidance, preserved encounters and session restoration; rig/physics checks SKIPPED"
	print("CREEP RAGDOLL TRIAL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + coverage)
	quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	for feature_id: String in TRIALS:
		var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == feature_id)
		_check(matching.size() == 1, "one catalog entry for " + feature_id)
		if matching.size() == 1:
			var entry: Dictionary = matching[0]
			_check(entry.category == "기본" and entry.action == "creep_ragdoll" and entry.payload == TRIALS[feature_id], "catalog dispatches the real scenario: " + feature_id)


func _test_missing_asset() -> void:
	print("CREEP RAGDOLL ASSET CHECKS SKIPPED: licensed model is absent; validating public-clone behavior.")
	var initial_actors: Array = _room_enemies()
	for feature_id: String in TRIALS:
		room.run_feature(feature_id)
		_check(room.panel_open and paused and room.enemies_alive == 2, "missing asset preserves the paused encounters: " + feature_id)
		_check(_room_enemies() == initial_actors and _find_creep() == null and room.creep_ragdoll_timer == null, "missing asset creates neither Creep nor a pending fatal hit: " + feature_id)
		_check(room.status_label.text.contains("설치"), "missing asset gives installation guidance: " + feature_id)


func _test_trial(feature_id: String, scenario: String) -> void:
	room._show_test_panel()
	room.run_feature(feature_id)
	var creep = _find_creep()
	_check(creep != null, "scenario spawns the actual Creep: " + feature_id)
	if creep == null:
		return
	_check(not paused and not room.panel_open and room.enemies_alive == 1, "scenario resumes one live encounter: " + feature_id)
	_check(creep.health == creep.max_health and room.player.health == room.player.MAX_HEALTH, "scenario prepares a healthy target and player: " + feature_id)
	_check(creep.target == room.player and creep.game == room and creep.hud == room.hud, "scenario retains production combat and rewards: " + feature_id)
	_check(creep.ragdoll.phase == "living" and not creep.is_physics_processing(), "target waits alive without AI attacks before its timed fatal hit: " + feature_id)
	var timer: Timer = room.creep_ragdoll_timer
	_check(is_instance_valid(timer) and not timer.is_stopped() and is_equal_approx(timer.wait_time, 1.0) and timer.process_mode == Node.PROCESS_MODE_PAUSABLE, "scenario schedules the real pausable one-second timer: " + feature_id)
	if not is_instance_valid(timer):
		return
	var impact: Vector3 = room.creep_ragdoll_attacker_position.direction_to(creep.global_position)
	var expected := Vector3.RIGHT if scenario == "side" else Vector3.FORWARD
	_check(impact.is_equal_approx(expected), "scenario selects its advertised impact direction: " + feature_id)
	if scenario == "wall":
		var wall := room.get_node("NorthWall") as Node3D
		_check(absf(creep.position.z - wall.position.z) < 2.0 and room.player.position.z > creep.position.z + 3.0, "wall trial uses the actual north wall with a clear observation position")
	else:
		_check(creep.position.is_equal_approx(Vector3(0, 1, -3)), "floor trial starts in the open combat area: " + feature_id)
	var loot_before: int = room.loot_count
	var fragments_before: int = room.inventory.count_item("rune_fragment")
	var defeats_before := defeat_count
	phase_on_defeat = ""
	clip_on_defeat = ""
	pause_on_defeat = true
	creep.defeated.connect(_on_creep_defeated)
	if scenario == "front":
		# Exercise the actual F2 input path, holding longer than the full timer.
		await _press_f2()
		var time_left := timer.time_left
		await _advance_frames(72)
		_check(paused and room.panel_open and is_equal_approx(timer.time_left, time_left) and creep.ragdoll.phase == "living" and creep.health == creep.max_health, "F2 freezes the full pending-fatal-hit countdown without an early death")
		await _press_f2()
	var died := await _wait_for_death(creep)
	_check(died, "real timer delivers fatal damage: " + feature_id)
	pause_on_defeat = false
	if not died:
		room._show_test_panel()
		return
	_check(phase_on_defeat == "reaction" and clip_on_defeat == "hit", "fatal hit starts a reaction before physical simulation: " + feature_id)
	_check(room.creep_ragdoll_timer == null and room.creep_ragdoll_target == null, "completed fatal hit releases its fixture timer and target reference: " + feature_id)
	_check(creep.collision_layer == 0 and creep.collision_mask == 0 and room.enemies_alive == 0, "fatal hit disables the living body and clears the encounter: " + feature_id)
	_check(defeat_count == defeats_before + 1 and room.loot_count == loot_before + 1 and room.inventory.count_item("rune_fragment") == fragments_before + 1, "normal defeat awards exactly one real reward: " + feature_id)
	creep.receive_hit(1000.0, creep.global_position + Vector3.LEFT, 1.0, false)
	_check(defeat_count == defeats_before + 1 and room.loot_count == loot_before + 1 and room.inventory.count_item("rune_fragment") == fragments_before + 1, "corpse hits cannot duplicate the defeat or reward: " + feature_id)
	var reaction: Dictionary = creep.ragdoll.snapshot()
	await _advance_frames(16)
	var still_reacting: Dictionary = creep.ragdoll.snapshot()
	_check(paused and reaction.phase == "reaction" and still_reacting.phase == "reaction" and is_equal_approx(still_reacting.reaction_time, reaction.reaction_time), "F2 pause freezes the death reaction clock: " + feature_id)
	# Disabled enemy AI must not stop the independent reaction/physics owner.
	creep.set_physics_process(false)
	room._hide_test_panel()
	var simulating := await _wait_for_simulation(creep)
	_check(simulating, "resuming advances the separate ragdoll controller with enemy AI disabled: " + feature_id)
	if not simulating:
		room._show_test_panel()
		return
	var active: Dictionary = creep.ragdoll.snapshot()
	_check(active.bodies > 0 and active.joints == active.bodies - 1 and creep.animation_clip == "ragdoll", "trial enters actual connected body simulation: " + feature_id)
	_check((active.impact_velocity as Vector3).normalized().is_equal_approx(expected), "normal hit direction reaches the ragdoll: " + feature_id)
	await _press_f2()
	var frozen: Dictionary = creep.ragdoll.snapshot()
	await _advance_frames(16)
	var after_pause: Dictionary = creep.ragdoll.snapshot()
	_check(paused and is_equal_approx(after_pause.simulation_time, frozen.simulation_time) and _same_positions(frozen.positions, after_pause.positions), "F2 freezes all body positions and the physics clock: " + feature_id)
	await _press_f2()
	await _advance_frames(12)
	var resumed: Dictionary = creep.ragdoll.snapshot()
	_check(not paused and resumed.simulation_time > after_pause.simulation_time and not _same_positions(after_pause.positions, resumed.positions), "resuming advances both real body motion and its clock: " + feature_id)
	room._show_test_panel()


func _test_replay_and_cancellation() -> void:
	var old_corpse = _find_creep()
	room.player.apply_body_damage("left_arm", 24.0)
	room.run_feature("creep_ragdoll:wall")
	var fresh = _find_creep()
	_check(fresh != null and fresh != old_corpse and (not is_instance_valid(old_corpse) or old_corpse.is_queued_for_deletion()), "reselecting the wall scenario removes its prior corpse and respawns")
	_check(room.player.health == room.player.MAX_HEALTH and fresh != null and fresh.health == fresh.max_health, "reselection heals the player and restores the target")
	var cancelled_timer: Timer = room.creep_ragdoll_timer
	if fresh == null or not is_instance_valid(cancelled_timer):
		_check(false, "reselection supplies both the live actor and cancellable timer")
		return
	room.run_feature("creep_ragdoll:wall")
	_check(fresh.is_queued_for_deletion() and cancelled_timer.is_stopped() and cancelled_timer.is_queued_for_deletion(), "reselection before death cancels the old actor and timer")
	var pending = _find_creep()
	var loot_before: int = room.loot_count
	room.run_feature("torch")
	_check(room.creep_ragdoll_timer == null and room.creep_ragdoll_target == null, "changing to another feature cancels the scheduled fatal hit")
	await _advance_frames(72)
	_check(is_instance_valid(pending) and pending.health == pending.max_health and room.enemies_alive == 1 and room.loot_count == loot_before, "cancelled timer cannot later kill the retained target or grant loot")
	room.run_feature("creep_ragdoll")
	var reset_target = _find_creep()
	var reset_timer: Timer = room.creep_ragdoll_timer
	if reset_target == null or not is_instance_valid(reset_timer):
		_check(false, "reset trial supplies both the live actor and cancellable timer")
		return
	room.reset_room()
	_check(reset_target.is_queued_for_deletion() and reset_timer.is_stopped() and reset_timer.is_queued_for_deletion(), "reset cancels pending death and removes the old Creep")
	_check(room.panel_open and paused and room.enemies_alive == 2 and room.creep_ragdoll_timer == null and _find_creep() == null, "reset restores the paused default encounters without a ragdoll timer")
	room._hide_test_panel()
	await _advance_frames(72)
	_check(room.enemies_alive == 2 and room.loot_count == 0 and _find_creep() == null, "resuming after reset cannot trigger a stale death or reward")
	room._show_test_panel()


func _on_creep_defeated(creep) -> void:
	defeat_count += 1
	phase_on_defeat = str(creep.ragdoll.phase)
	clip_on_defeat = str(creep.animation_clip)
	if pause_on_defeat:
		room._show_test_panel()


func _wait_for_death(creep) -> bool:
	for frame in 100:
		if creep.ai_state == DungeonEnemy.AIState.DEAD:
			return true
		await _advance_frames(1)
	return creep.ai_state == DungeonEnemy.AIState.DEAD


func _wait_for_simulation(creep) -> bool:
	for frame in 40:
		if creep.ragdoll.phase == "simulating":
			return true
		await _advance_frames(1)
	return creep.ragdoll.phase == "simulating"


func _advance_frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


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


func _same_positions(before: Dictionary, after: Dictionary) -> bool:
	if before.size() != after.size() or before.is_empty():
		return false
	for key in before:
		if not after.has(key) or not (before[key] as Vector3).is_equal_approx(after[key]):
			return false
	return true


func _room_enemies() -> Array:
	return room.get_children().filter(func(actor: Node) -> bool: return actor is DungeonEnemy and not actor.is_queued_for_deletion())


func _find_creep():
	for actor in _room_enemies():
		if actor is CREEP:
			return actor
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
