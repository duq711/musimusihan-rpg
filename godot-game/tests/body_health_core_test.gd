extends SceneTree

const BODY := preload("res://scripts/body_health.gd")
var failures: Array[String] = []

class PhysicsBodyPlayer extends DungeonPlayer:
	func _ready() -> void:
		collision_layer = PLAYER_LAYER
		collision_mask = WORLD_LAYER
		gravity = 0.0
		head = Node3D.new()
		add_child(head)
		var collision := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.height = 1.78
		capsule.radius = 0.36
		collision.shape = capsule
		add_child(collision)
		set_physics_process(false)
		set_process_unhandled_input(false)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_mouse := Input.mouse_mode
	_test_parts_damage_healing()
	_test_consumables_and_spells()
	_test_periodic_conditions()
	_test_targeted_conditions_and_curse()
	_test_death_and_transition()
	await _test_movement_and_paralysis()
	ExpeditionSession.restore_snapshot(original)
	check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == original_mouse, "Core tests must preserve the original session and OS mouse mode.")
	for failure in failures:
		push_error(failure)
	print("BODY HEALTH CORE TEST %s: seven parts, blackout/repair, selected/automatic treatment, real magic/item costs, DOT clock, targeted cures, movement/combat impairment, death and scene persistence" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _player() -> DungeonPlayer:
	ExpeditionSession.begin_new_journey()
	var player := DungeonPlayer.new()
	player.bind_inventory(ExpeditionSession.get_inventory())
	return player


func _test_parts_damage_healing() -> void:
	var state := BODY.create_state()
	check(BODY.total_health(state) == 440.0 and state.parts == {"head": 35.0, "thorax": 85.0, "stomach": 70.0, "left_arm": 60.0, "right_arm": 60.0, "left_leg": 65.0, "right_leg": 65.0}, "All seven health maxima must match the confirmed 440-point body.")
	var snapshot := BODY.snapshot(state)
	snapshot.parts.head.health = 0.0
	check(state.parts.head == 35.0, "UI health snapshots must be deeply isolated from live part values.")
	var initial := state.duplicate(true)
	check(not BODY.damage(state, "unknown", 5.0).accepted and not BODY.damage(state, "head", -1.0).accepted and state == initial, "Invalid part or negative damage must leave body state unchanged.")
	check(BODY.damage(state, "left_arm", 60.0).blacked and BODY.total_health(state) == 380.0 and not BODY.is_dead(state), "Zero arm health must disable that part without immediately killing the player.")
	check(BODY.heal(state, 100.0, "left_arm") == 0.0 and BODY.heal(state, 100.0) == 0.0, "Ordinary healing must not revive a zero part even in automatic mode.")
	BODY.damage(state, "left_arm", 10.0)
	check(is_equal_approx(BODY.total_health(state), 370.0) and state.parts.left_arm == 0.0 and state.parts.head < 35.0, "Hits on a disabled limb must spill damage into still-living body parts.")
	check(is_equal_approx(BODY.heal(state, 100.0), 10.0) and BODY.total_health(state) == 380.0, "Automatic normal healing must restore living wounds and preserve the blackout.")
	check(BODY.repair(state, "left_arm") == 1.0 and state.parts.left_arm == 1.0 and BODY.repair(state, "left_arm") == 0.0, "Surgical repair must change 0 to exactly 1 and reject a living part.")
	check(BODY.heal(state, 32.0, "left_arm") == 32.0 and state.parts.left_arm == 33.0, "A repaired limb must accept ordinary healing afterward.")
	for target in [25.0, 47.0, 57.0, 64.0, 100.0, 440.0]:
		BODY.set_total_for_debug(state, target)
		check(BODY.total_health(state) == target, "Explicit QA total must retain its exact requested value: %s" % target)


func _test_consumables_and_spells() -> void:
	var player := _player()
	var bag := player.inventory_model
	bag.add_item("surgery_kit", 2)
	bag.add_item("healing_draught", 3)
	player.apply_body_damage("left_arm", 60.0)
	player.select_treatment_part("left_arm")
	var supplies := bag.slots.duplicate(true)
	check(not player.use_consumable("healing_draught", bag).accepted and bag.slots == supplies, "Trying a normal potion on a selected blackout must consume nothing.")
	check(player.use_consumable("surgery_kit", bag).accepted and player.get_body_health_snapshot().parts.left_arm.health == 1.0 and bag.count_item("surgery_kit") == 1, "Actual surgery item must spend one kit and restore only the selected limb to 1.")
	check(player.use_consumable("healing_draught", bag).accepted and player.get_body_health_snapshot().parts.left_arm.health == 33.0, "Actual normal potion must heal the surgically restored limb.")
	player.select_treatment_part("right_arm")
	supplies = bag.slots.duplicate(true)
	check(not player.use_consumable("healing_draught", bag).accepted and bag.slots == supplies, "Selecting a full limb must reject treatment rather than silently consume or heal another limb.")
	player.select_treatment_part("")
	check(player.use_consumable("healing_draught", bag).accepted and player.get_body_health_snapshot().parts.left_arm.health == 60.0, "Automatic potion treatment must find an injured living limb.")
	player.apply_body_damage("right_leg", 65.0)
	player.select_treatment_part("right_leg")
	bag.equipment.weapon = "weathered_staff"
	ExpeditionSession.learn_spell("healing_light")
	ExpeditionSession.learn_spell("restorative_light")
	var stamina_before := player.stamina
	check(not player.cast_spell("healing_light").accepted and player.stamina == stamina_before and player.spell_cooldown == 0.0, "Actual low-tier healing must reject a blackout without stamina or cooldown cost.")
	var high := player.cast_spell("restorative_light")
	check(high.accepted and high.health_restored == 1.0 and player.get_body_health_snapshot().parts.right_leg.health == 1.0 and player.stamina == stamina_before - 55.0, "Actual high-tier restoration must cost 55 stamina and restore exactly 1 health.")
	player.spell_cooldown = 0.0
	player.stamina = 100.0
	check(player.cast_spell("healing_light").accepted and player.get_body_health_snapshot().parts.right_leg.health == 33.0, "Low-tier healing must work after high-tier restoration.")
	player.spell_cooldown = 0.0
	player.stamina = 100.0
	check(not player.cast_spell("restorative_light").accepted and player.stamina == 100.0 and player.spell_cooldown == 0.0, "High-tier restoration on a living target must consume no resources.")
	player.free()


func _test_periodic_conditions() -> void:
	var player := _player()
	player.apply_condition("bleeding", 30.0, "left_arm")
	player.apply_condition("poison", 30.0)
	var baseline := ExpeditionSession.capture_snapshot()
	ExpeditionSession.advance_survival(2.0)
	player.sync_body_health_from_session()
	check(player.health == 437.0 and player.get_body_health_snapshot().parts.left_arm.health == 59.0 and player.get_body_health_snapshot().parts.stomach.health == 68.0, "One survival tick must apply actual bleeding and poison damage to their body parts.")
	var after := ExpeditionSession.body_health.duplicate(true)
	player.advance_action_timers(2.0)
	player.sync_body_health_from_session()
	check(ExpeditionSession.body_health == after, "Player timers and synchronization must never tick condition damage a second time.")
	ExpeditionSession.restore_snapshot(baseline)
	ExpeditionSession.advance_survival(60.0)
	var large := ExpeditionSession.capture_snapshot()
	ExpeditionSession.restore_snapshot(baseline)
	for _step in 120:
		ExpeditionSession.advance_survival(0.5)
	var small := ExpeditionSession.capture_snapshot()
	check(is_equal_approx(BODY.total_health(large.body_health), BODY.total_health(small.body_health)) and is_equal_approx(large.hunger, small.hunger) and is_equal_approx(large.thirst, small.thirst) and large.active_conditions == small.active_conditions, "Long and small survival ticks must preserve condition expiry and total damage equivalence.")
	ExpeditionSession.restore_snapshot(baseline)
	ExpeditionSession.advance_survival(10.0, {"safe_zone": true})
	check(ExpeditionSession.body_health == baseline.body_health and ExpeditionSession.active_conditions == baseline.active_conditions and ExpeditionSession.hunger < baseline.hunger, "Safe-zone cooking must retain hunger costs while pausing condition damage and durations.")
	var safe := ExpeditionSession.capture_snapshot()
	ExpeditionSession.advance_survival(10.0, {"paused": true})
	check(ExpeditionSession.capture_snapshot() == safe, "Explicit paused survival context must stop needs and every condition clock.")
	player.free()


func _test_targeted_conditions_and_curse() -> void:
	var player := _player()
	var bag := player.inventory_model
	bag.add_item("splint", 3)
	bag.add_item("linen_bandage", 3)
	bag.add_item("purifying_salt", 1)
	player.apply_condition("fracture", 120.0, "left_leg")
	player.apply_condition("fracture", 120.0, "right_arm")
	check(player.get_body_movement_multiplier() == 0.65 and player.get_body_combat_multiplier() == 0.8 and is_equal_approx(player.get_melee_damage(), 27.0 * 0.8) and player.get_melee_stamina_cost() > 18.0, "Localized fractures must change actual movement and melee damage/stamina calculations.")
	player.select_treatment_part("left_leg")
	check(player.use_consumable("splint", bag).accepted and player.get_body_movement_multiplier() == 1.0 and player.get_body_combat_multiplier() == 0.8 and ExpeditionSession.has_condition("fracture"), "Selected-leg splint must preserve the separate arm fracture.")
	player.select_treatment_part("right_arm")
	check(player.use_consumable("splint", bag).accepted and not ExpeditionSession.has_condition("fracture"), "The final affected limb cure must remove the global fracture flag.")
	player.apply_condition("bleeding", 120.0, "left_arm")
	player.apply_condition("bleeding", 120.0, "right_leg")
	player.select_treatment_part("left_arm")
	check(player.use_consumable("linen_bandage", bag).accepted and ExpeditionSession.body_health.condition_parts.bleeding == ["right_leg"], "Selected bandage must preserve another limb's bleeding.")
	player.apply_body_damage("thorax", 40.0)
	player.apply_condition("curse", 120.0)
	check(player.restore_health(20.0, "thorax") == 10.0, "Curse must halve actual ordinary healing rather than only alter text or need drain.")
	check(player.use_consumable("purifying_salt", bag).accepted and player.restore_health(20.0, "thorax") == 20.0, "Actual curse cure must restore ordinary healing effectiveness.")
	player.free()


func _test_death_and_transition() -> void:
	var player := _player()
	player.apply_body_damage("left_leg", 20.0)
	player.select_treatment_part("left_leg")
	var next := DungeonPlayer.new()
	next.bind_inventory(ExpeditionSession.get_inventory())
	check(next.get_body_health_snapshot() == player.get_body_health_snapshot(), "A new scene actor bound to the same expedition must retain wounds and treatment selection.")
	var deaths := {"count": 0}
	next.died.connect(func() -> void: deaths.count += 1)
	next.apply_body_damage("head", 35.0)
	check(next.combat_state == DungeonPlayer.CombatState.DEAD and next.health > 0.0 and deaths.count == 1, "A zero vital head must cause death even while total limb health remains positive.")
	next.sync_body_health_from_session()
	next.apply_body_damage("thorax", 500.0)
	check(deaths.count == 1 and next.restore_health(500.0) == 0.0 and next.restore_body_part("head") == 0.0, "Death must emit once and reject all healing or surgical revival.")
	next.reset_body_health()
	check(next.health == 440.0 and next.combat_state == DungeonPlayer.CombatState.READY, "Explicit test reset must restore all parts and the living combat state.")
	next.apply_body_damage("thorax", 85.0)
	check(deaths.count == 2 and next.combat_state == DungeonPlayer.CombatState.DEAD, "The second vital body part must use the same death rule after a real reset.")
	next.free()
	player.free()


func _test_movement_and_paralysis() -> void:
	ExpeditionSession.begin_new_journey()
	var player := PhysicsBodyPlayer.new()
	root.add_child(player)
	player.bind_inventory(ExpeditionSession.get_inventory())
	for _step in 20:
		await physics_frame
		player.advance_movement(1.0 / 60.0, Vector2(0, -1), false)
	check(is_equal_approx(absf(player.velocity.z), DungeonPlayer.WALK_SPEED), "Uninjured production movement must reach its normal walking speed.")
	player.apply_condition("fracture", 120.0, "left_leg")
	for _step in 20:
		await physics_frame
		player.advance_movement(1.0 / 60.0, Vector2(0, -1), true)
	check(is_equal_approx(absf(player.velocity.z), DungeonPlayer.WALK_SPEED * 0.65), "Actual movement with a fractured leg must slow and reject sprint speed.")
	player.apply_condition("paralysis", 8.0)
	var before := player.global_position
	await physics_frame
	player.advance_movement(1.0 / 60.0, Vector2(1, -1), true)
	check(player.global_position.is_equal_approx(before) and Vector2(player.velocity.x, player.velocity.z) == Vector2.ZERO, "Paralysis must stop real collision-body movement.")
	check(not player.begin_sword_attack().accepted and not player.begin_bow_draw().accepted and not player.begin_flail_melee().accepted and not player.cast_spell("healing_light").accepted, "Paralysis must reject melee, bow, flail and spell actions at their real entrypoints.")
	player.inventory_model.add_item("nerve_tonic", 1)
	check(player.use_consumable("nerve_tonic", player.inventory_model).accepted and not player.is_paralyzed(), "The actual paralysis cure must remain usable to escape the action lock.")
	player.free()
	await process_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
