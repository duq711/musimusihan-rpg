extends SceneTree

const PREVIEW := preload("res://tests/player_arm_preview.gd")
const CHOREOGRAPHY := preload("res://scripts/sword_shield_choreography.gd")
const VARIANTS: Array[String] = ["right_diagonal", "left_reverse", "overhead"]

var failures: Array[String] = []
var landed_hits: Array[Dictionary] = []
var player: DungeonPlayer
var enemy: DungeonEnemy
var bag: ExpeditionInventory


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_inventory := _inventory_fingerprint(original.inventory)
	var initial_cursor := Input.mouse_mode
	var initial_pause := paused
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	player = fixture.player as DungeonPlayer
	bag = fixture.inventory as ExpeditionInventory
	# This fixture owns its world and never samples movement or mouse input.
	# The arm preview's hidden chest still has a real collider: move it aside.
	(fixture.chest as Node3D).position = Vector3(12, 0, 12)
	player.position = Vector3(0, 1, 2)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player._pitch = 0.0
	player.set_torch_enabled(false)
	player.attack_landed.connect(_on_attack_landed)
	enemy = DungeonEnemy.new()
	enemy.configure("검 공격 변형 검증 대상", 2000.0, 21.0, 0.0, Color(0.3, 0.3, 0.3))
	enemy.set_physics_process(false)
	(fixture.stage as Node3D).add_child(enemy)
	enemy.set_physics_process(false)
	enemy.setup(player, null, fixture.stage)
	# The real capsule intersects the unchanged forward melee query. The aim
	# point is deliberately off the headshot axis, so body damage is exact.
	enemy.global_position = player.camera.global_position + Vector3(0, -0.2, -1.7)
	await physics_frame
	await physics_frame
	_check(viewport.own_world_3d and viewport.gui_disable_input and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "fixture must isolate physics and hardware input")
	_check(bag != original.inventory and bag.equipment.weapon == "rusted_sword" and bag.equipment.offhand == "round_shield", "fixture must own an actual sword/shield inventory")
	_check(not player._query_melee_hits().is_empty(), "actual enemy capsule must be inside the production melee query")
	_check(is_equal_approx(DungeonPlayer.ATTACK_HIT_TIME, 0.055) and is_equal_approx(DungeonEnemy.ATTACK_HIT_TIME, 0.09), "the new paired animation must preserve solo-sword and enemy hit constants")
	_check(is_equal_approx(CHOREOGRAPHY.HIT_SECONDS, 0.145) and is_equal_approx(CHOREOGRAPHY.ACTIVE_SECONDS, 0.30), "paired sword/shield must use its deliberate 145ms hit and 300ms active window")
	_test_fixed_variants()
	_test_default_cycle()
	_test_rejections_and_overrides()
	_test_cancellation_and_menus()
	_test_equipment_and_shieldless_fallback()
	paused = initial_pause
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and _inventory_fingerprint(original.inventory) == original_inventory, "attack checks must restore the original expedition and preserve its inventory contents")
	_check(Input.mouse_mode == initial_cursor and paused == initial_pause, "attack checks must preserve the user's cursor and scene pause state")
	for failure in failures:
		push_error(failure)
	print("SWORD ATTACK VARIANTS %s: three actual paired attacks, 145ms/300ms paired versus 55ms/160ms solo timing, unchanged one-hit/cost transactions, commit-only cycle, cancellation and menu/equipment reset" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_fixed_variants() -> void:
	for variant: String in VARIANTS:
		_ready_for_attack()
		_check(player.set_sword_attack_mode(variant), "fixed mode must accept " + variant)
		_check(player.get_next_sword_attack_variant() == variant, "fixed mode must select " + variant)
		var result := player.begin_sword_attack()
		_check(bool(result.accepted), "actual fixed attack must start: " + variant)
		if not bool(result.accepted):
			continue
		_check(float(result.stamina_spent) == 0.0 and str(result.variant) == variant, "begin must select the requested style without spending stamina")
		_complete_started_attack(variant)
		_check(player.get_next_sword_attack_variant() == variant, "fixed mode must retain its style after recovery")
		_check_snapshot(variant, variant)
	# Holding a selected attack keeps the same style and existing charge math.
	_ready_for_attack()
	_check(player.set_sword_attack_mode("overhead"), "charged attack mode must select")
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("overhead", 0.74)
		_check(player.attack_charge > 0.49 and player.attack_charge < 0.51, "charged variant must retain the original charge clock")
	else:
		_check(false, "charged overhead attack must start")


func _test_default_cycle() -> void:
	_ready_for_attack()
	_check(player.set_sword_attack_mode("cycle"), "default three-style cycle must select")
	for index in 7:
		_ready_for_attack()
		var expected := VARIANTS[index % VARIANTS.size()]
		var following := VARIANTS[(index + 1) % VARIANTS.size()]
		_check(player.get_next_sword_attack_variant() == expected, "default LMB cycle must select the next committed style")
		# This is the unchanged LMB entry point; no synthetic Input event or
		# cursor capture is needed to exercise its production delegation.
		player._try_begin_attack()
		_check(player.combat_state == DungeonPlayer.CombatState.WINDUP, "legacy LMB wrapper must start a real sword windup")
		if player.combat_state != DungeonPlayer.CombatState.WINDUP:
			continue
		_check(player.get_next_sword_attack_variant() == expected, "starting a windup must not advance the cycle")
		_complete_started_attack(expected)
		_check(player.get_next_sword_attack_variant() == following, "exactly one commit must advance the cycle once")
		_check_snapshot("cycle", following)


func _test_rejections_and_overrides() -> void:
	_ready_for_attack()
	player.set_sword_attack_mode("cycle")
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("right_diagonal")
	_check(player.get_next_sword_attack_variant() == "left_reverse", "override setup must retain a nonzero cycle position")
	_ready_for_attack()
	var selection := _selection()
	_rejected_start("not_a_sword_attack", "invalid_variant")
	_check(not player.set_sword_attack_mode("not_a_mode") and _selection() == selection, "invalid mode must leave current and next choices unchanged")
	player.stamina = player.get_melee_stamina_cost(0.0) - 0.1
	_rejected_start("", "not_enough_stamina")
	player.stamina = player.MAX_STAMINA
	player.blocking = true
	_rejected_start("", "busy")
	player.blocking = false
	player.camping = true
	_rejected_start("", "busy")
	player.camping = false
	paused = true
	_rejected_start("", "paused")
	paused = false
	_check(_selection() == selection, "failed starts must not consume the waiting cycle style")
	var result := player.begin_sword_attack("overhead")
	_check(bool(result.accepted), "explicit one-off override must start")
	if bool(result.accepted):
		_rejected_start("right_diagonal", "busy")
		_check(not player.set_sword_attack_mode("left_reverse") and player.sword_attack_variant == "overhead", "active windup must lock its selected mode and style")
		_complete_started_attack("overhead")
	_check(player.sword_attack_mode == "cycle" and player.get_next_sword_attack_variant() == "left_reverse", "explicit override must leave the pending default cycle unchanged")
	_ready_for_attack()
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("left_reverse")
	_check(player.get_next_sword_attack_variant() == "overhead", "the next default attack must resume the unconsumed cycle")
	var before := _effect_state()
	player._commit_attack()
	player._resolve_active_attack()
	_check(_effect_state() == before, "commit and resolution while READY must never spend or hit")


func _test_cancellation_and_menus() -> void:
	_ready_for_attack()
	player.set_sword_attack_mode("cycle")
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("right_diagonal")
	_ready_for_attack()
	var effects := _effect_state()
	_check(bool(player.begin_sword_attack().accepted), "cancellable next cycle attack must start")
	_tick(0.15)
	player.attack_release_requested = true
	player.cancel_sword_attack(false)
	_check(player.get_next_sword_attack_variant() == "left_reverse", "cancel(false) must preserve the uncommitted cycle position")
	player._commit_attack()
	_tick(2.0)
	_check(_effect_state() == effects and player.combat_state == DungeonPlayer.CombatState.READY, "cancelled preparation and its late release must cause no damage or cost")
	_check(not player.attack_release_requested and player.attack_charge == 0.0 and player.attack_hit_ids.is_empty(), "cancel must clear queued release, charge and hit tracking")
	_check(bool(player.begin_sword_attack().accepted), "menu-interrupted attack must start")
	_tick(0.10)
	player.prepare_for_inventory()
	_check(player.get_next_sword_attack_variant() == "right_diagonal" and player.combat_state == DungeonPlayer.CombatState.READY, "inventory/F2 preparation hook must reset the cycle and cancel windup")
	player._commit_attack()
	_tick(1.0)
	_check(_effect_state() == effects, "opening the menu before commit must consume nothing and prevent a delayed hit")
	# F2 selects its trial while paused, but combat cannot start or advance.
	paused = true
	_check(player.set_sword_attack_mode("left_reverse"), "paused menu may safely select a style while READY")
	_rejected_start("", "paused")
	paused = false
	_check(bool(player.begin_sword_attack().accepted), "selected trial must start after unpausing")
	_tick(0.10)
	var windup_time := player.state_time
	var charge := player.attack_charge
	paused = true
	player.attack_release_requested = true
	player.advance_action_timers(3.0)
	player.advance_combat_state(3.0, false)
	player._commit_attack()
	_check(player.state_time == windup_time and player.attack_charge == charge and _effect_state() == effects, "paused windup and attempted commit must freeze time, damage and cost")
	paused = false
	player.cancel_sword_attack()
	_check(player.sword_attack_mode == "left_reverse" and player.get_next_sword_attack_variant() == "left_reverse", "default cancellation must retain an explicitly selected trial mode")
	# An already committed strike retains its paid cost; menu cancellation
	# prevents its pending hit and any second resource transaction.
	_ready_for_attack()
	_check(bool(player.begin_sword_attack().accepted), "post-commit menu fixture must start")
	player.attack_release_requested = true
	_tick(0.221)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "actual release must commit before active cancellation")
	var committed := _effect_state()
	player.prepare_for_inventory()
	player._commit_attack()
	_tick(1.0)
	_check(_effect_state() == committed and player.combat_state == DungeonPlayer.CombatState.READY, "menu interruption after commit must keep its single paid cost and suppress the pending hit")
	_ready_for_attack()
	player.set_sword_attack_mode("cycle")
	_check(bool(player.begin_sword_attack().accepted), "safe-zone cancellation fixture must start")
	effects = _effect_state()
	player.configure_safe_zone(true)
	_rejected_start("", "safe_zone")
	player._commit_attack()
	_tick(1.0)
	_check(_effect_state() == effects and player.combat_state == DungeonPlayer.CombatState.READY, "entering a safe zone must cancel pending sword combat")
	player.configure_safe_zone(false)


func _test_equipment_and_shieldless_fallback() -> void:
	_ready_for_attack()
	player.set_sword_attack_mode("cycle")
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("right_diagonal")
	_ready_for_attack()
	_check(bool(player.begin_sword_attack().accepted) and player.sword_attack_variant == "left_reverse", "shield removal must be tested during the second real style")
	var effects := _effect_state()
	_check(bool(bag.unequip("offhand").accepted), "actual inventory must unequip the shield")
	_check(player.combat_state == DungeonPlayer.CombatState.READY and player.get_next_sword_attack_variant() == "right_diagonal", "removing a required shield must synchronously cancel and reset the attack")
	player._commit_attack()
	_tick(1.0)
	_check(_effect_state() == effects, "shield removal must prevent queued damage and cost")
	for _index in 3:
		_ready_for_attack()
		player._try_begin_attack()
		if player.combat_state == DungeonPlayer.CombatState.WINDUP:
			_complete_started_attack("right_diagonal")
		else:
			_check(false, "sword-only LMB must remain available")
		_check(player.get_next_sword_attack_variant() == "right_diagonal", "sword without a shield must retain the established attack instead of cycling")
	_ready_for_attack()
	_check(player.set_sword_attack_mode("left_reverse"), "menu mode preference may persist with the shield unequipped")
	_rejected_start("left_reverse", "shield_required")
	_rejected_start("overhead", "shield_required")
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("right_diagonal")
	else:
		_check(false, "default sword-only attack must fall back even when a shield style was selected")
	_check(_equip("round_shield"), "real inventory must restore the shield")
	_ready_for_attack()
	player.set_sword_attack_mode("cycle")
	_check(bool(player.begin_sword_attack().accepted), "weapon replacement fixture must start")
	effects = _effect_state()
	_check(_equip("hunting_bow"), "real inventory must replace sword with bow")
	_check(player.combat_state == DungeonPlayer.CombatState.READY and player.get_next_sword_attack_variant() == "right_diagonal", "changing the real weapon must reset pending sword combat")
	_rejected_start("", "sword_required")
	player._commit_attack()
	_tick(1.0)
	_check(_effect_state() == effects, "weapon change must not leave a delayed sword transaction")
	_check(_equip("rusted_sword"), "real inventory must restore the sword")
	_ready_for_attack()
	if bool(player.begin_sword_attack().accepted):
		_complete_started_attack("right_diagonal")
	else:
		_check(false, "restored sword/shield must restart its cycle")


func _complete_started_attack(expected_variant: String, hold_time: float = 0.10) -> void:
	var stamina_before := player.stamina
	var health_before := enemy.health
	var hits_before := landed_hits.size()
	var next_before := player.get_next_sword_attack_variant()
	var paired := str(bag.equipment.get("offhand", "")) == "round_shield"
	var hit_time := player.get_melee_hit_time()
	var active_duration := player.get_melee_active_duration()
	_check(is_equal_approx(hit_time, 0.145 if paired else 0.055) and is_equal_approx(active_duration, 0.30 if paired else 0.16), "real equipment must select paired timing while preserving the established sword-only attack")
	_check(player.combat_state == DungeonPlayer.CombatState.WINDUP and player.sword_attack_variant == expected_variant, "real windup must retain selected style " + expected_variant)
	_tick(hold_time)
	_check(player.combat_state == DungeonPlayer.CombatState.WINDUP and player.stamina == stamina_before and enemy.health == health_before, "held windup must cause neither premature cost nor damage")
	# Explicit deterministic release input, identical to LMB-up's queued flag.
	# The production combat clock, rather than the test, decides when to commit.
	player.attack_release_requested = true
	if hold_time < 0.219:
		_tick(0.219 - hold_time)
		_check(player.combat_state == DungeonPlayer.CombatState.WINDUP and player.stamina == stamina_before and player.get_next_sword_attack_variant() == next_before, "release before 0.22 seconds must not commit or consume the cycle")
		_tick(0.0011)
	else:
		_tick(0.0001)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "release must enter the actual active phase")
	if player.combat_state != DungeonPlayer.CombatState.ACTIVE:
		return
	var cost := player.get_melee_stamina_cost(player.attack_charge)
	var damage := player.get_melee_damage(player.attack_charge)
	_check(is_equal_approx(player.stamina, stamina_before - cost), "each style must pay exactly its existing charge-dependent stamina cost")
	var next_after_commit := player.get_next_sword_attack_variant()
	player._commit_attack()
	_check(is_equal_approx(player.stamina, stamina_before - cost) and player.get_next_sword_attack_variant() == next_after_commit, "duplicate active commit must not spend or advance again")
	if paired:
		_tick(DungeonPlayer.ATTACK_HIT_TIME + 0.001)
		_check(enemy.health == health_before and landed_hits.size() == hits_before, "paired sword must not apply its new body hit at the earlier solo-sword checkpoint")
	_tick(hit_time - 0.001 - player.state_time)
	_check(enemy.health == health_before and landed_hits.size() == hits_before, "real target must remain unharmed before its equipment-specific hit checkpoint")
	_tick(0.0011)
	_check(is_equal_approx(enemy.health, health_before - damage), "selected style must inflict its actual body damage at its equipment-specific hit checkpoint")
	_check(landed_hits.size() == hits_before + 1, "a committed style must emit exactly one actual hit")
	if landed_hits.size() > hits_before:
		_check(not bool(landed_hits.back().headshot) and is_equal_approx(float(landed_hits.back().damage), damage), "real hit signal must match the target's damage")
	player._resolve_active_attack()
	_tick(0.04)
	_check(is_equal_approx(enemy.health, health_before - damage) and landed_hits.size() == hits_before + 1, "repeated active resolution must never hit the same target twice")
	_tick(active_duration - 0.001 - player.state_time)
	_check(player.combat_state == DungeonPlayer.CombatState.ACTIVE, "actual swing must remain active until its selected equipment duration expires")
	_tick(0.002)
	_check(player.combat_state == DungeonPlayer.CombatState.RECOVERY, "equipment-specific active duration must end in real recovery")
	_tick(lerpf(0.47, 0.68, player.attack_charge) + 0.001)
	_check(player.combat_state == DungeonPlayer.CombatState.READY and player.sword_attack_variant == expected_variant, "completed style must return to READY with its recorded variant")
	_check(is_equal_approx(player.stamina, stamina_before - cost) and is_equal_approx(enemy.health, health_before - damage) and landed_hits.size() == hits_before + 1, "full start/release/recovery cycle must contain one damage and one cost transaction")


func _ready_for_attack() -> void:
	player.cancel_sword_attack(false)
	player.stamina = player.MAX_STAMINA
	player.camera.position = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player._camera_shake = 0.0
	enemy.health = enemy.max_health
	enemy.velocity = Vector3.ZERO
	enemy._set_state(DungeonEnemy.AIState.IDLE)


func _tick(delta: float) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, false)
	player._update_viewmodel(delta)
	player._resolve_active_attack()
	# Stamina regeneration and enemy AI are deliberately not advanced: this
	# measures the real attack transaction, without unrelated recovery/motion.


func _rejected_start(variant: String, reason: String) -> void:
	var effects := _effect_state()
	var selection := _selection()
	var phase := player.combat_state
	var time := player.state_time
	var result := player.begin_sword_attack(variant)
	_check(not bool(result.accepted) and str(result.get("reason", "")) == reason and float(result.stamina_spent) == 0.0, "rejected start must explain " + reason)
	_check(_effect_state() == effects and _selection() == selection and player.combat_state == phase and player.state_time == time, "rejected " + reason + " must preserve effects, phase and cycle")


func _selection() -> Dictionary:
	return {"mode": player.sword_attack_mode, "variant": player.sword_attack_variant, "next": player.get_next_sword_attack_variant()}


func _effect_state() -> Dictionary:
	return {"stamina": player.stamina, "health": enemy.health, "hits": landed_hits.size()}


func _check_snapshot(mode: String, following: String) -> void:
	var snapshot := player.get_first_person_motion_snapshot()
	_check(str(snapshot.get("sword_attack_mode", "")) == mode and str(snapshot.get("sword_attack_variant", "")) == player.sword_attack_variant and str(snapshot.get("sword_next_attack_variant", "")) == following, "public snapshot must expose actual mode, committed variant and next choice")


func _equip(item_id: String) -> bool:
	var slot := str(ExpeditionInventory.get_item_definition(item_id).get("equip_slot", ""))
	if str(bag.equipment.get(slot, "")) == item_id:
		return true
	for index in bag.slots.size():
		if str(bag.slots[index].id) == item_id:
			return bool(bag.equip_from_slot(index).accepted)
	return false


func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null:
		return "no_inventory"
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text()


func _on_attack_landed(damage: float, headshot: bool) -> void:
	landed_hits.append({"damage": damage, "headshot": headshot})


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
