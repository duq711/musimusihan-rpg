extends SceneTree

const CREEP := preload("res://scripts/creep_enemy.gd")
const IDS: Array[String] = ["dagger_assassination", "dagger_assassination:front"]

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
	var original_cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	room.set_physics_process(false)
	# Deliberately advance the production player clock, while actual F2 input,
	# enemy AI and physics continue through the ordinary scene tree. The dagger
	# uses the same attack-entry/release API as LMB, without capturing a cursor.
	room.player.set_physics_process(false)
	_check(sandbox.active and room.inventory != original, "F2 owns a separate test inventory")
	_test_catalog()
	if CREEP.is_available():
		actual_checks = true
		await _test_rear_and_reward()
		await _test_front_comparison()
		await _test_pause_reselect_reset()
	else:
		_test_missing_asset()
	_check(original.slots == original_slots and original.equipment == original_equipment, "dagger equipment and kill rewards preserve the original inventory")
	room.suspend_stress_effects()
	room.queue_free()
	current_scene = null
	paused = false
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == before, "exit restores the exact original expedition and inventory identity")
	_check(Input.mouse_mode == original_cursor, "exit restores the prior cursor mode")
	for failure in failures:
		push_error("DAGGER ASSASSINATION TRIAL TEST FAIL: " + failure)
	print("DAGGER ASSASSINATION TRIAL TEST " + ("PASS" if failures.is_empty() else "FAIL") + ": " + ("real F2 rear/front fixtures, production attack API/contact (not OS mouse routing), single death/reward, live AI, pause/cancel, replay/reset, expedition restoration" if actual_checks else "catalog, missing-asset guidance and session restoration; real Creep trials SKIPPED"))
	quit(0 if failures.is_empty() else 1)


func _test_catalog() -> void:
	for index in IDS.size():
		var matching: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == IDS[index])
		_check(matching.size() == 1, "unique executable dagger F2 entry: " + IDS[index])
		if matching.size() != 1: continue
		var entry: Dictionary = matching[0]
		_check(entry.category == "기본" and entry.action == "dagger_assassination" and entry.payload == ("rear" if index == 0 else "front"), "correct rear/front dispatch: " + IDS[index])
		_check(entry.detail.contains("LMB") and entry.detail.contains("F2"), "catalog explains input and replay")


func _test_rear_and_reward() -> void:
	room.run_feature(IDS[0])
	var creep = _find_creep()
	_check(creep != null, "rear entry spawns the real Creep")
	if creep == null: return
	_check(not paused and not room.panel_open and room.enemy_ai_enabled and creep.is_physics_processing(), "rear fixture resumes actual enemy AI")
	_check(creep.health == 82.0 and creep.health == creep.max_health and creep.dismemberment.severed.is_empty(), "rear fixture uses a healthy intact enemy")
	_check(room.player.is_dagger_equipped() and room.inventory.equipment.get("offhand", "") == "", "fixture equips dagger and clears the shield")
	_check(creep.can_receive_dagger_assassination(room.player.global_position), "player starts within the live rear eligibility cone")
	var initial_position: Vector3 = creep.global_position
	await _frames(6)
	_check(creep.ai_state == DungeonEnemy.AIState.IDLE and Vector2(creep.global_position.x - initial_position.x, creep.global_position.z - initial_position.z).length() < .01, "live idle AI does not see a player behind it outside proximity range")
	# Stop AI only inside this assertion fixture after confirming its production
	# activation; the F2 entry itself never freezes or fakes enemy behavior.
	creep.set_physics_process(false)
	var contact: Dictionary = room.player._located_melee_contact(creep, room.player.get_melee_reach())
	_check(not contact.is_empty() and str(contact.get("region", "")) != "head", "prepared camera reaches posed body below the head")
	creep.defeated.connect(func(_actor: DungeonEnemy) -> void: defeats += 1)
	var prior_defeats := defeats
	var prior_loot: int = room.loot_count
	var prior_fragments: int = room.inventory.count_item("rune_fragment")
	await _attack_input_api(true)
	_check(room.player.combat_state == DungeonPlayer.CombatState.WINDUP and creep.health == 82.0, "LMB production entry API starts a stab without premature damage")
	await _attack_input_api(false)
	for step in 100: _tick(.01)
	_check(creep.health == 0.0 and creep.ai_state == DungeonEnemy.AIState.DEAD and defeats == prior_defeats + 1, "production attack contact performs exactly one rear assassination")
	_check(room.enemies_alive == 0 and room.loot_count == prior_loot + 1 and room.inventory.count_item("rune_fragment") == prior_fragments + 1, "assassination uses the real room kill and reward callback once")
	for step in 80: _tick(.01)
	_check(defeats == prior_defeats + 1 and room.loot_count == prior_loot + 1, "recovery cannot repeat death or rewards")


func _test_front_comparison() -> void:
	room.run_feature(IDS[1])
	var creep = _find_creep()
	_check(creep != null, "front comparison creates a fresh real Creep")
	if creep == null: return
	_check(creep.health == 82.0 and room.enemy_ai_enabled and creep.is_physics_processing(), "front comparison starts healthy with real AI enabled")
	_check(not creep.can_receive_dagger_assassination(room.player.global_position), "front comparison cannot receive rear assassination")
	await _frames(2)
	_check(creep.ai_state != DungeonEnemy.AIState.IDLE, "live front-facing enemy notices the player")
	creep.set_physics_process(false)
	var health: float = creep.health
	var prior_loot: int = room.loot_count
	await _attack_input_api(true)
	await _attack_input_api(false)
	for step in 100: _tick(.01)
	_check(creep.health > 0.0 and creep.health < health and health - creep.health <= 28.0, "same production attack from the front applies ordinary nonlethal body damage")
	_check(room.enemies_alive == 1 and room.loot_count == prior_loot, "front attack awards no assassination kill")


func _test_pause_reselect_reset() -> void:
	room.run_feature(IDS[0])
	var old_target = _find_creep()
	if old_target == null: return
	await _attack_input_api(true)
	_check(room.player.combat_state == DungeonPlayer.CombatState.WINDUP, "pause trial begins a real pending stab")
	await _press_f2()
	var enemy_clock: float = old_target.state_time
	var position: Vector3 = old_target.global_position
	var health: float = old_target.health
	_check(paused and room.panel_open and room.player.combat_state == DungeonPlayer.CombatState.READY, "F2 cancels ordinary windup and pauses the trial")
	for step in 40: room.player.advance_combat_state(.02)
	await _frames(5)
	_check(old_target.health == health and old_target.state_time == enemy_clock and old_target.global_position == position, "F2 freezes live AI and cannot resolve the cancelled contact")
	# Release in the paused menu cannot leave a latched click for resume.
	await _attack_input_api(false)
	await _press_f2()
	for step in 80: _tick(.01)
	_check(old_target.health == health and room.player.combat_state == DungeonPlayer.CombatState.READY, "resume does not revive the cancelled stab")
	room.player.stamina = 3.0
	room.run_feature(IDS[0])
	var fresh = _find_creep()
	_check(old_target.is_queued_for_deletion() and fresh != old_target and fresh.health == fresh.max_health, "reselection removes old target and prepares a healthy replacement")
	_check(room.player.stamina == room.player.MAX_STAMINA and room.player.health == room.player.MAX_HEALTH, "reselection heals and restores stamina")
	await _attack_input_api(true)
	room.reset_room()
	await _attack_input_api(false)
	await _frames(2)
	_check(paused and room.panel_open and _find_creep() == null and room.enemies_alive == 2 and room.loot_count == 0, "reset clears dagger encounter and restores default paused room")
	_check(room.player.combat_state == DungeonPlayer.CombatState.READY and not room.player.is_dagger_equipped(), "reset cannot leave a hidden pending dagger attack")


func _test_missing_asset() -> void:
	var equipment: Dictionary = room.inventory.equipment.duplicate(true)
	var position: Vector3 = room.player.position
	var health: float = room.player.health
	var count: int = room.enemies_alive
	for feature_id in IDS:
		room.run_feature(feature_id)
		_check(_find_creep() == null and room.enemies_alive == count and room.inventory.equipment == equipment, "missing asset leaves actors and equipment intact: " + feature_id)
		_check(room.player.position == position and room.player.health == health and paused and room.panel_open, "missing asset preserves player and paused menu")
		_check(room.status_label.text.contains("에셋") and room.status_label.text.contains("CREEP_ASSET.md"), "missing asset displays actionable installation guidance")


func _tick(delta: float) -> void:
	room.player.advance_action_timers(delta)
	room.player.advance_combat_state(delta, false)
	room.player._update_viewmodel(delta)
	room.player._resolve_active_attack()


func _attack_input_api(pressed: bool) -> void:
	# Headless DisplayServer cannot deliver captured-pointer LMB reliably.
	# Exercise its production action path, not an invented hit/kill; actual
	# OS mouse routing is explicitly outside this background test's scope.
	if not paused and not room.panel_open:
		if pressed:
			room.player._try_begin_attack()
		elif room.player.combat_state == DungeonPlayer.CombatState.WINDUP:
			room.player.attack_release_requested = true
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


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _find_creep():
	for actor in room.get_children():
		if actor is CREEP and not actor.is_queued_for_deletion(): return actor
	return null


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
