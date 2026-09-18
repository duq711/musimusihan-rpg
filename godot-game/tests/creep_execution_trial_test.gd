extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const MOTION := preload("res://scripts/creep_execution_motion.gd")
const IDS: Array[String] = ["creep_execution", "creep_execution:both_legs"]

var failures: Array[String] = []
var room: Node3D
var defeats := 0
var actual_checks := false


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
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	# Advance the same player attack clock deliberately, while real timers,
	# enemy physics, F2 and skeletal modifiers run on normal frames.
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original, "execution fixture owns a separate test expedition")
	_test_catalog()
	if CREEP.is_available():
		actual_checks = true
		for feature_id in IDS:
			await _test_trial(feature_id)
		await _test_cancel_reset()
	else:
		for feature_id in IDS:
			room.run_feature(feature_id)
			_check(_find_creep() == null and room.creep_execution_timer == null and not room.creep_execution_ready, "missing model does not invent an execution target: " + feature_id)
			_check(room.status_label.text.contains("에셋"), "missing model reports actionable guidance")
	_check(original.slots == original_slots and original.equipment == original_equipment, "test loadout, cuts and execution rewards leave original inventory untouched")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "exit restores exact original expedition and inventory identity")
	for failure in failures:
		push_error("CREEP EXECUTION TRIAL TEST FAIL: " + failure)
	print("CREEP EXECUTION TRIAL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + ("real localized leg loss, grounded recovery, sword/shield and stowed shield, timed stab single kill/reward, F2 pause/resume, cancel/reset, exact session restore" if actual_checks else "catalog and session restore; asset-dependent execution SKIPPED"))
	quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	for index in IDS.size():
		var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == IDS[index])
		_check(matching.size() == 1, "unique F2 execution entry: " + IDS[index])
		if matching.size() != 1:
			continue
		var entry: Dictionary = matching[0]
		_check(entry.category == "기본" and entry.action == "creep_execution" and entry.payload == ("left_leg" if index == 0 else "both_legs"), "F2 entry dispatches actual execution preparation: " + IDS[index])
		_check(entry.detail.contains("랙돌") and entry.detail.contains("회복") and entry.detail.contains("0.4"), "catalog describes real fall gate and hold-release input")


func _test_trial(feature_id: String) -> void:
	room.run_feature(feature_id)
	var creep = _find_creep()
	_check(creep != null and room.creep_execution_target == creep and not room.creep_execution_ready, "entry starts with the intact live production Creep: " + feature_id)
	if creep == null:
		return
	creep.defeated.connect(func(_actor: DungeonEnemy) -> void: defeats += 1)
	var before_defeats := defeats
	var before_loot: int = room.loot_count
	var before_fragments: int = room.inventory.count_item("rune_fragment")
	_check(creep.dismemberment.severed.is_empty() and creep.health == creep.max_health, "fixture does not directly sever or kill")
	var preparation: Timer = room.creep_execution_timer
	var cuts: Timer = room.creep_dismemberment_timer
	await _press_f2()
	var pending := cuts.time_left
	await _frames(60)
	_check(paused and preparation.time_left > 0.0 and cuts.time_left == pending and creep.health == creep.max_health and not room.creep_execution_ready, "F2 freezes preparation and real localized-hit countdown")
	await _press_f2()
	var ready := false
	for frame in 1500:
		await _frames(1)
		if room.creep_execution_ready:
			ready = true
			break
		if creep.is_knocked_down():
			_check(not creep.is_execution_vulnerable() and creep.ai_state != DungeonEnemy.AIState.EXECUTION, "physical falling/recovering creature cannot be executed")
	_check(ready, "actual localized hits, physical landing and recovery finish before execution setup: " + feature_id)
	if not ready:
		return
	# Freeze only AI travel to make the exact player timing assertions stable.
	# The trial itself enables production crawling, bites and user input.
	creep.set_physics_process(false)
	_check(creep.is_crawling() and not creep.is_knocked_down() and creep.is_execution_vulnerable(), "grounded living crawler becomes eligible without low-health stagger")
	_check(creep.health > creep.max_health * 0.3 and creep.ai_state != DungeonEnemy.AIState.STAGGER, "fixture does not fake generic low-health/stagger execution eligibility")
	_check(creep.dismemberment.severed.size() == (2 if feature_id.ends_with("both_legs") else 1), "fixture uses exactly the requested real leg cuts")
	_check(room.creep_execution_timer == null and room.creep_dismemberment_timer == null and room.enemy_ai_enabled, "setup timers release while production AI remains enabled")
	_check(room.player.get_execution_target() == creep, "ready camera and distance select the low crawler")
	if feature_id.ends_with("both_legs"):
		var stow: Dictionary = room.player.request_primary_weapon()
		_check(stow.get("accepted", false), "normal primary-weapon input starts shield stowing")
		room.player._update_viewmodel(room.player.SHIELD_STOW_DURATION + room.player.SWORD_SUPPORT_DURATION + 0.1)
		_check(room.player._shield_stowed and room.player.get_execution_target() == creep, "crawler remains targetable after stowing the shield")
	var health: float = creep.health
	_check(_charge_release(), "real charged sword release starts crawler stab: " + feature_id)
	if not room.player.is_execution_active():
		return
	room.player.advance_execution(0.35)
	room.player._update_viewmodel(0.0)
	var held: Dictionary = room.player.get_execution_snapshot().duplicate(true)
	var held_weapon: Transform3D = room.player.weapon_pivot.transform
	await _press_f2()
	room.player.advance_execution(5.0)
	await _frames(15)
	_check(paused and room.player.get_execution_snapshot() == held and room.player.weapon_pivot.transform == held_weapon and creep.health == health, "F2 preserves the paired stab pose and clock without dealing contact damage")
	await _press_f2()
	room.player.advance_execution(MOTION.HIT_SECONDS - 0.35 - 0.001)
	_check(creep.health == health and defeats == before_defeats, "no lethal damage before authored blade contact")
	room.player.advance_execution(0.002)
	_check(creep.health == 0.0 and creep.ai_state == DungeonEnemy.AIState.DEAD and defeats == before_defeats + 1, "blade contact performs one actual Creep death")
	_check(room.enemies_alive == 0 and room.loot_count == before_loot + 1 and room.inventory.count_item("rune_fragment") == before_fragments + 1, "execution uses the ordinary single kill/reward path")
	room.player.advance_execution(3.0)
	await _frames(5)
	_check(not room.player.is_execution_active() and defeats == before_defeats + 1 and creep.ragdoll.phase != "idle", "withdrawal releases combat and retains actual death ragdoll without another kill")


func _test_cancel_reset() -> void:
	room.run_feature("creep_execution")
	var old_target = _find_creep()
	var old_timer: Timer = room.creep_execution_timer
	room.run_feature("creep_execution:both_legs")
	_check(old_target.is_queued_for_deletion() and old_timer.is_queued_for_deletion(), "reselection removes old actor and preparation timer")
	await _frames(1)
	var fresh = _find_creep()
	var fresh_hp: float = fresh.health
	room.run_feature("torch")
	_check(room.creep_execution_timer == null and room.creep_execution_target == null and not room.creep_execution_ready, "changing feature cancels pending execution setup")
	await _frames(70)
	_check(is_instance_valid(fresh) and fresh.health == fresh_hp and fresh.dismemberment.severed.is_empty(), "cancelled timers cannot cut or reframe a retained target later")
	room.run_feature("creep_execution")
	room.reset_room()
	await _frames(1)
	_check(paused and room.panel_open and room.creep_execution_timer == null and not room.creep_execution_ready and _find_creep() == null and room.enemies_alive == 2, "reset restores default paused encounters and clears all setup ownership")
	room._hide_test_panel()
	await _frames(70)
	_check(_find_creep() == null and room.enemies_alive == 2 and room.loot_count == 0, "no stale execution or reward appears after reset")


func _charge_release() -> bool:
	var started: Dictionary = room.player.begin_sword_attack()
	if not started.get("accepted", false):
		return false
	room.player.advance_combat_state(0.42)
	room.player.attack_release_requested = true
	room.player.advance_combat_state(0.01)
	return room.player.is_execution_active()


func _frames(count: int) -> void:
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


func _find_creep():
	for actor in room.get_children():
		if actor is CREEP and not actor.is_queued_for_deletion():
			return actor
	return null


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
