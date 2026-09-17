extends SceneTree

var failures: Array[String] = []
var room: Node3D
var player: DungeonPlayer
var attacker: DungeonEnemy
var sandbox: Node
var original: ExpeditionInventory
var original_snapshot: Dictionary
var original_slots: Array
var original_equipment: Dictionary
var original_data: Dictionary


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	original = ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	var weapon := original.get_equipment_instance("weapon")
	weapon["uid"] = "shield_guard_original_weapon"
	weapon["smithing"] = {"quality": 0.83, "runes": ["ember"], "grip": "balanced"}
	ExpeditionSession.crowns = 137
	ExpeditionSession.hunger = 57.0
	ExpeditionSession.thirst = 39.0
	ExpeditionSession.set_stress(42.0)
	ExpeditionSession.apply_condition("curse", 73.0)
	original_snapshot = ExpeditionSession.capture_snapshot()
	original_slots = original.slots.duplicate(true)
	original_equipment = original.equipment.duplicate(true)
	original_data = original.equipment_data.duplicate(true)
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	room.set_process(false)
	_check(sandbox.active and room.inventory != original and room.panel_open and paused, "shield trial must begin in a paused, isolated expedition")
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "shield")
	_check(entries.size() == 1 and entries[0].action == "armed" and entries[0].payload == "shield_guard", "shield catalog entry must connect the actual dedicated combat fixture")
	await _open_shield_trial()
	if is_instance_valid(attacker):
		_test_continuous_guard()
		_test_stamina_exhaustion()
		_test_just_guard_and_stun()
		_test_direction_release_and_environment()
		_test_equipment_boundaries()
		await _test_pause_and_repeat()
		await _test_reset_and_exit()
	else:
		sandbox.finish()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("SHIELD GUARD TEST %s: full damage blocking with positive stamina, immediate exhaustion release and recovery, timed attacker stun, real attack and equipment boundaries, ailments/stress, F2/repeat/reset and original expedition restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _open_shield_trial() -> void:
	room.run_feature("shield")
	player = room.player
	player.set_physics_process(false)
	attacker = null
	var enemy_count := 0
	for child in room.get_children():
		if child is DungeonEnemy and not child.is_queued_for_deletion():
			enemy_count += 1
			attacker = child as DungeonEnemy
			_check(attacker.is_physics_processing() and attacker.target == player, "shield fixture must enable the production enemy AI against the actual player")
			attacker.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not paused and not room.panel_open and room.enemy_ai_enabled and enemy_count == 1, "shield selection must resume a repeatable duel with one actual attacker")
	_check(str(room.inventory.equipment.weapon) == "rusted_sword" and str(room.inventory.equipment.offhand) == "round_shield", "shield selection must equip the actual sword and shield")
	_check(player.health == player.MAX_HEALTH and player.stamina == player.MAX_STAMINA and not player.blocking, "shield selection must restore health, stamina and released guard")
	_check(not player.safe_zone_mode and player.torch_enabled, "shield selection must remain real dungeon combat with its torch enabled")
	_check(get_nodes_in_group("trap").filter(func(node: Node) -> bool: return not node.is_queued_for_deletion()).is_empty(), "focused shield fixture must remove environment traps from the duel")
	_check_original_untouched()


func _prepare_guard(held_seconds: float, starting_stamina := 100.0, expected_blocking: bool = true) -> void:
	player.cancel_sword_attack()
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	player.health = player.MAX_HEALTH
	player.stamina = starting_stamina
	player.velocity = Vector3.ZERO
	player.advance_combat_state(held_seconds, true)
	_check(player.blocking == expected_blocking, "a requested guard must require positive stamina (starting %.4f, expected blocking %s)" % [starting_stamina, expected_blocking])


func _enemy_hit(amount := 20.0, condition := "bleeding") -> void:
	attacker.global_position = player.global_position - player.global_basis.z * 1.5
	attacker.rotation.y = player.rotation.y + PI
	attacker.velocity = Vector3.ZERO
	attacker.target = player
	attacker.attack_damage = amount
	attacker.inflicted_condition = condition
	attacker._set_state(DungeonEnemy.AIState.ACTIVE)
	attacker.state_time = DungeonEnemy.ATTACK_HIT_TIME
	attacker._resolve_active_attack()


func _test_continuous_guard() -> void:
	ExpeditionSession.active_conditions.clear()
	ExpeditionSession.set_stress(31.0)
	_prepare_guard(0.4)
	var health := player.health
	_enemy_hit()
	_check(attacker.attack_has_resolved and attacker.attack_has_connected, "ordinary guard must connect the real enemy hit through its range, facing and line of sight")
	_close(player.health, health, "ordinary shield guard must completely block health damage")
	_close(player.stamina, 100.0 - 20.0 * 1.18, "ordinary shield guard must spend its existing impact stamina cost once")
	_check(attacker.ai_state != DungeonEnemy.AIState.STAGGER and player._shield_impact > 0.0, "ordinary guard must produce shield recoil without stunning the attacker")
	var stamina := player.stamina
	attacker._resolve_active_attack()
	_close(player.stamina, stamina, "the same resolved swing must not consume shield stamina twice")
	player.advance_combat_state(30.0, true)
	for amount: float in [20.0, 20.0]:
		stamina = player.stamina
		_enemy_hit(amount)
		_close(player.health, health, "consecutive sustained blocks must prevent health damage while stamina remains")
		_close(player.stamina, stamina - amount * 1.18, "each ordinary shield impact must spend its existing stamina cost")
		_check(player.blocking and player.combat_state == DungeonPlayer.CombatState.READY, "a held shield must remain ready while impact costs leave positive stamina")
		_check(attacker.ai_state != DungeonEnemy.AIState.STAGGER, "holding beyond the timing window must never regain the attacker stun")
		player.advance_combat_state(2.0, true)
	_check(ExpeditionSession.active_conditions.is_empty(), "all fully blocked attacks must prevent authored bleeding")
	_close(ExpeditionSession.stress, 31.0, "fully blocked damage must not add stress")


func _test_stamina_exhaustion() -> void:
	for starting_stamina: float in [0.001, 1.0, 20.0 * 1.18]:
		ExpeditionSession.active_conditions.clear()
		ExpeditionSession.set_stress(17.0)
		_prepare_guard(0.4, starting_stamina)
		player._update_viewmodel(1.0)
		var raised_progress: float = player.get_first_person_motion_snapshot().shield_raise_progress
		_check(raised_progress > 0.99, "exhaustion test must begin with the actual viewmodel shield fully raised")
		_enemy_hit(20.0, "fracture")
		_close(player.health, player.MAX_HEALTH, "the hit that exhausts any positive stamina must still be fully blocked")
		_close(player.stamina, 0.0, "insufficient and exact impact stamina must be consumed without becoming negative")
		_check(not player.blocking and is_zero_approx(player.block_time), "the exhausting hit must immediately release guard and clear its just-guard timer")
		_check(player.combat_state == DungeonPlayer.CombatState.READY and attacker.ai_state != DungeonEnemy.AIState.STAGGER, "exhaustion must not add guard-break damage, a guard-break lockout or ordinary-hit enemy stun")
		_check(not ExpeditionSession.has_condition("fracture"), "the fully blocked exhausting hit must not inflict its authored injury")
		_close(ExpeditionSession.stress, 17.0, "the fully blocked exhausting hit must not add damage stress")
		player._update_viewmodel(0.05)
		_check(float(player.get_first_person_motion_snapshot().shield_raise_progress) < raised_progress, "actual shield viewmodel must begin lowering immediately after impact exhaustion")
		player._update_viewmodel(1.0)
		_close(float(player.get_first_person_motion_snapshot().shield_raise_progress), 0.0, "the exhausted shield viewmodel must finish lowering")
		player.advance_combat_state(0.3, true)
		_check(not player.blocking and is_zero_approx(player.block_time), "continued RMB request must not raise a shield again at zero stamina")
		_enemy_hit(10.0, "fracture")
		_close(player.health, player.MAX_HEALTH - 10.0, "the next actual attack after exhaustion must deal normal unguarded health damage")
		_check(ExpeditionSession.has_condition("fracture") and ExpeditionSession.stress > 17.0, "an unguarded follow-up attack must restore injury and damage-stress consequences")
	for held_seconds: float in [0.1, 0.4]:
		_prepare_guard(held_seconds, 0.0, false)
		player._update_viewmodel(1.0)
		_close(float(player.get_first_person_motion_snapshot().shield_raise_progress), 0.0, "a shield requested at zero stamina must stay visually lowered")
		_enemy_hit(10.0)
		_close(player.health, player.MAX_HEALTH - 10.0, "zero starting stamina must reject both ordinary and just-guard protection")
		_close(player.stamina, 0.0, "zero starting stamina must not obtain the just-guard refund")
		_check(not player.blocking and attacker.ai_state != DungeonEnemy.AIState.STAGGER, "zero-stamina guard input must not stun the attacking enemy")
		_prepare_guard(held_seconds, 20.0)
		player.stamina = 0.0
		# Direct state edits can happen between combat updates. The damage entry
		# point must reject and clear a guard that no longer has stamina.
		var stale_result := player.receive_attack(10.0, player.global_position - player.global_basis.z * 1.5)
		_check(not bool(stale_result.get("blocked", false)) and not bool(stale_result.get("parried", false)), "receive_attack must reject stale guard after external stamina reaches zero")
		_check(not player.blocking and is_zero_approx(player.block_time), "receive_attack must clear stale blocking and timing immediately at zero stamina")
		_close(player.health, player.MAX_HEALTH - 10.0, "externally exhausted guard must allow the current attack's full damage")
		_close(player.stamina, 0.0, "stale timed guard must not refund stamina after external exhaustion")
	_prepare_guard(0.4, 20.0)
	player._update_viewmodel(1.0)
	player.stamina = 0.0
	player.advance_combat_state(0.05, true)
	_check(not player.blocking and is_zero_approx(player.block_time), "combat updates must also release a held shield after external stamina exhaustion")
	player._update_viewmodel(0.05)
	_check(float(player.get_first_person_motion_snapshot().shield_raise_progress) < 1.0, "external exhaustion must lower the actual shield on its next viewmodel update")
	player.stamina_regen_delay = 0.0
	player._update_stamina(0.1)
	_check(player.stamina > 0.0, "a lowered exhausted shield must permit the existing stamina regeneration")
	player.advance_combat_state(0.1, true)
	_check(player.blocking and player.block_time <= DungeonPlayer.JUST_GUARD_WINDOW, "a requested shield must become available again once real stamina has recovered")
	_enemy_hit()
	_close(player.health, player.MAX_HEALTH, "recovered stamina must restore the shield's actual full-damage protection")
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "raising the shield after recovery must support a fresh just-guard stun")


func _test_just_guard_and_stun() -> void:
	_close(DungeonPlayer.JUST_GUARD_WINDOW, 0.20, "just guard must keep its inclusive 0.20-second timing window")
	_close(DungeonEnemy.JUST_GUARD_STUN_SECONDS, 1.15, "shield just guard must expose the authored 1.15-second attacker stun")
	_prepare_guard(0.001)
	_enemy_hit()
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER and is_equal_approx(player.health, player.MAX_HEALTH), "shield must protect from its very first requested frame before the visual raise finishes")
	_prepare_guard(DungeonPlayer.JUST_GUARD_WINDOW, 55.0)
	var enemy_health := attacker.health
	_enemy_hit()
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "an attack at the inclusive just-guard boundary must stun the actual attacker")
	_close(player.health, player.MAX_HEALTH, "just guard must prevent all health damage")
	_close(player.stamina, 63.0, "just guard must retain its eight-stamina refund")
	_close(attacker.health, enemy_health, "shield stun must not create retaliation health damage")
	_check(attacker.velocity.dot(player.global_position.direction_to(attacker.global_position)) > 0.0, "just guard must retain the actual attacker's knockback response")
	attacker._resolve_active_attack()
	_close(player.stamina, 63.0, "a stunned attack must not resolve again or refund stamina twice")
	attacker._physics_process(0.73)
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "shield stun must still prevent AI attacks beyond ordinary 0.72-second stagger")
	attacker._physics_process(0.41)
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "shield stun must persist until its full authored duration")
	attacker._physics_process(0.02)
	_check(attacker.ai_state == DungeonEnemy.AIState.CHASE, "the real enemy AI must resume when its shield stun expires")
	_prepare_guard(0.201, 55.0)
	_enemy_hit()
	_check(attacker.ai_state != DungeonEnemy.AIState.STAGGER, "an attack just outside the timing window must only receive ordinary guard")
	_close(player.health, player.MAX_HEALTH, "missing just-guard timing must still completely protect shield health")
	_close(player.stamina, 55.0 - 23.6, "an attack beyond the just-guard boundary must consume ordinary block stamina")
	_prepare_guard(0.1, 0.001)
	_enemy_hit()
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "a correctly timed shield raised with positive stamina must still stun")
	_close(player.stamina, 8.001, "positive-stamina just guard must retain its eight-stamina refund")
	attacker._physics_process(0.1)
	attacker.receive_hit(1.0, player.global_position, 0.0, false)
	attacker._physics_process(0.8)
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "a follow-up hit must not shorten remaining shield stun to ordinary hit stagger")
	attacker._physics_process(0.26)
	_check(attacker.ai_state == DungeonEnemy.AIState.CHASE, "follow-up damage must still allow the retained shield stun to expire")
	attacker._set_state(DungeonEnemy.AIState.ACTIVE)
	_check(attacker.receive_sword_clash(player.global_position), "the same armed enemy must retain its real sword-clash response")
	attacker._physics_process(0.71)
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "ordinary sword clash must retain its original stagger duration")
	attacker._physics_process(0.02)
	_check(attacker.ai_state == DungeonEnemy.AIState.CHASE, "ordinary sword clash must recover after 0.72 seconds rather than use shield stun duration")


func _test_direction_release_and_environment() -> void:
	for angle: float in [54.0, 56.0, 90.0, 180.0]:
		_prepare_guard(0.4)
		var direction := (-player.global_basis.z).rotated(Vector3.UP, deg_to_rad(angle))
		var result := player.receive_attack(10.0, player.global_position + direction * 1.5)
		var covered: bool = float(angle) < 55.0
		_check(bool(result.get("blocked", false)) == covered, "shield must preserve the existing frontal angle limit: " + str(angle))
		_close(player.health, player.MAX_HEALTH if covered else player.MAX_HEALTH - 10.0, "shield direction must determine whether the actual hit removes health")
	_prepare_guard(0.4)
	player.advance_combat_state(0.01, false)
	_check(not player.blocking and is_zero_approx(player.block_time), "releasing guard must immediately end protection and reset timing")
	_enemy_hit(10.0, "fracture")
	_close(player.health, player.MAX_HEALTH - 10.0, "a hit after releasing the shield must deal normal health damage")
	_check(ExpeditionSession.has_condition("fracture"), "an unguarded hit must retain its authored injury")
	player.advance_combat_state(0.1, true)
	_enemy_hit()
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "releasing and raising the shield again must create a new just-guard window")
	_prepare_guard(0.4)
	ExpeditionSession.set_stress(0.0)
	player.receive_environment_damage(10.0, "shield regression trap", "curse")
	_close(player.health, player.MAX_HEALTH - 10.0, "held shield must preserve environmental damage bypass")
	_check(ExpeditionSession.has_condition("curse") and ExpeditionSession.stress > 0.0, "environmental hits must still apply injury and damage stress")


func _test_equipment_boundaries() -> void:
	_prepare_guard(0.4)
	player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
	_check(player.request_primary_weapon().accepted, "primary 1 must pack the actual held shield")
	player.advance_combat_state(0.4, true)
	var packed_result := player.receive_attack(20.0, player.global_position - player.global_basis.z * 1.5)
	_check(room.inventory.equipment.offhand == "round_shield" and not bool(packed_result.get("shield_guard", false)) and is_equal_approx(float(packed_result.get("damage", 0.0)), 4.0), "a packed shield must stay in inventory but cannot provide full shield protection against a real hit")
	player.reset_shield_carry()
	_prepare_guard(0.4)
	var bag: ExpeditionInventory = room.inventory
	_check(bool(bag.unequip("offhand").get("accepted", false)), "equipment boundary must remove the actual shield through the inventory API")
	player.advance_combat_state(0.4, true)
	var result := player.receive_attack(20.0, player.global_position - player.global_basis.z * 1.5)
	_check(bool(result.get("blocked", false)) and is_equal_approx(float(result.get("damage", 0.0)), 4.0), "removing the shield must retain the original weapon block rather than leave full shield protection")
	_close(player.health, player.MAX_HEALTH - 4.0, "shieldless weapon block must preserve its historical chip damage")
	_prepare_guard(0.4, 1.0)
	result = player.receive_attack(20.0, player.global_position - player.global_basis.z * 1.5)
	_check(player.combat_state == DungeonPlayer.CombatState.GUARD_BREAK and is_equal_approx(float(result.get("damage", 0.0)), 11.0), "shieldless weapon guard must retain its original exhaustion break and health damage")
	_prepare_guard(0.1, 40.0)
	_enemy_hit()
	_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "shieldless timed weapon guard must retain its existing attacker stagger")
	attacker._physics_process(0.73)
	_check(attacker.ai_state == DungeonEnemy.AIState.CHASE, "shieldless timed weapon guard must not inherit the longer shield-specific stun")
	player.cancel_sword_attack()
	player.stamina = 0.0
	player.advance_combat_state(0.4, true)
	_check(not player.blocking, "shieldless weapon guard must continue to require positive stamina")
	_check(_equip_from_bag("round_shield"), "inventory must re-equip the same shield for further combat tests")
	_prepare_guard(0.4, 0.0, false)
	_enemy_hit(10.0)
	_close(player.health, player.MAX_HEALTH - 10.0, "re-equipping a shield must not bypass the zero-stamina guard restriction")
	_prepare_guard(0.4, 1.0)
	_enemy_hit()
	_close(player.health, player.MAX_HEALTH, "re-equipped shield with positive stamina must fully block the exhausting hit")
	_check(not player.blocking, "re-equipped shield must lower after the impact consumes its remaining stamina")
	for weapon_id: String in ["hunting_bow", "chain_flail"]:
		_check(_equip_from_bag(weapon_id), "equipment test must use the actual inventory API: " + weapon_id)
		player.health = player.MAX_HEALTH
		player.stamina = player.MAX_STAMINA
		player.advance_combat_state(0.4, true)
		_check(not player.blocking, "two-handed weapon RMB behavior must not become shield guard: " + weapon_id)
		_enemy_hit(10.0)
		_close(player.health, player.MAX_HEALTH - 10.0, "carried offhand shield must not block while using incompatible weapon: " + weapon_id)
	_check(_equip_from_bag("rusted_sword"), "inventory must restore melee equipment after ranged/flail regression")


func _equip_from_bag(item_id: String) -> bool:
	var bag: ExpeditionInventory = room.inventory
	for index in range(bag.slots.size()):
		if str(bag.slots[index].get("id", "")) == item_id:
			return bool(bag.equip_from_slot(index).get("accepted", false))
	return false


func _test_pause_and_repeat() -> void:
	_prepare_guard(0.1)
	_enemy_hit()
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.physical_keycode = KEY_F2
	f2.pressed = true
	room._unhandled_input(f2)
	_check(room.panel_open and paused and not player.blocking and is_zero_approx(player.block_time), "F2 must cancel the live guard and return to the paused test menu")
	var state_time := attacker.state_time
	var block_time := player.block_time
	var hunger := ExpeditionSession.hunger
	attacker.set_physics_process(true)
	player.advance_combat_state(2.0, true)
	room._process(2.0)
	await create_timer(0.03, true).timeout
	_close(attacker.state_time, state_time, "paused F2 menu must freeze the actual enemy stun clock")
	_close(player.block_time, block_time, "paused F2 menu must not advance or reopen guard timing")
	_close(ExpeditionSession.hunger, hunger, "paused F2 menu must freeze survival")
	attacker.set_physics_process(false)
	_check_original_untouched()
	_check(bool((room.inventory as ExpeditionInventory).unequip("offhand").get("accepted", false)), "repeat fixture must begin with its shield actually unequipped")
	_check(_equip_from_bag("hunting_bow"), "repeat fixture must replace a previously equipped bow")
	for index in range(ExpeditionInventory.MAX_SLOTS):
		(room.inventory as ExpeditionInventory).add_item("rusted_sword", 1, false)
	_check((room.inventory as ExpeditionInventory).slots.size() == ExpeditionInventory.MAX_SLOTS, "repeat fixture must exercise a full sandbox inventory")
	await _open_shield_trial()
	if not is_instance_valid(attacker): return
	_prepare_guard(3.0, 0.0, false)
	_enemy_hit(10.0)
	_close(player.health, player.MAX_HEALTH - 10.0, "reselected fixture must retain the real zero-stamina guard restriction")
	_prepare_guard(3.0, 1.0)
	_enemy_hit()
	_close(player.health, player.MAX_HEALTH, "reselected fixture must fully block while its last positive stamina is consumed")
	_check(not player.blocking and is_zero_approx(player.block_time), "reselected fixture must release the shield as soon as the blocking hit exhausts stamina")
	_check_original_untouched()


func _test_reset_and_exit() -> void:
	var previous_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != previous_bag and room.inventory != original and paused and room.panel_open, "reset must create a new test bag while keeping the original expedition isolated")
	await _open_shield_trial()
	if is_instance_valid(attacker):
		_prepare_guard(0.1)
		_enemy_hit()
		_check(attacker.ai_state == DungeonEnemy.AIState.STAGGER, "reset shield fixture must still execute the real timed stun")
	_check_original_untouched()
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original, "leaving shield trials must restore the exact original inventory object")
	_check(ExpeditionSession.capture_snapshot() == original_snapshot, "leaving shield trials must restore every original expedition value and condition")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "shield trial combat, equipment replacement and reset must preserve original stacks and nested weapon metadata")


func _check_original_untouched() -> void:
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_data, "shield testing must not mutate the saved expedition inventory")
	_check(sandbox.saved_session == original_snapshot, "shield testing must retain the reusable original expedition snapshot")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "shield trial scene transition timed out: " + path)


func _close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) < 0.002, "%s (actual %.4f, expected %.4f)" % [message, actual, expected])


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
