extends SceneTree

const TEN_MINUTES := 600.0
const SAMPLE_SECONDS := 60.0
const FLOAT_TOLERANCE := 0.002

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_authored_pacing()
	_test_condition_multipliers_and_expiry()
	_test_new_journey_reset()
	_test_survival_consumables()
	_test_damage_ailments()
	await _test_scene_tick_policy()
	_finish()


func _test_authored_pacing() -> void:
	_check(is_equal_approx(ExpeditionSession.MAX_NEED, 100.0), "survival needs must use a 0 to 100 scale")
	_check(is_equal_approx(ExpeditionSession.HUNGER_FULL_DURATION_SECONDS, 5400.0), "full hunger must last ninety realtime dungeon minutes")
	_check(is_equal_approx(ExpeditionSession.THIRST_FULL_DURATION_SECONDS, 3600.0), "full thirst must last sixty realtime dungeon minutes")
	_check(is_equal_approx(ExpeditionSession.MAX_DRAIN_MULTIPLIER, 2.25), "stacked ailments must keep the authored 2.25 drain cap")

	ExpeditionSession.begin_new_journey()
	ExpeditionSession.advance_survival(TEN_MINUTES)
	var expected_hunger := ExpeditionSession.MAX_NEED * (1.0 - TEN_MINUTES / ExpeditionSession.HUNGER_FULL_DURATION_SECONDS)
	var expected_thirst := ExpeditionSession.MAX_NEED * (1.0 - TEN_MINUTES / ExpeditionSession.THIRST_FULL_DURATION_SECONDS)
	_check_close(ExpeditionSession.hunger, expected_hunger, "ten calm dungeon minutes must consume exactly one ninth of hunger")
	_check_close(ExpeditionSession.thirst, expected_thirst, "ten calm dungeon minutes must consume exactly one sixth of thirst")
	_check(ExpeditionSession.hunger > 85.0 and ExpeditionSession.thirst > 80.0, "baseline survival pacing must remain tense without becoming fast")


func _test_condition_multipliers_and_expiry() -> void:
	var bonuses := ExpeditionSession.CONDITION_DRAIN_BONUSES
	_check_close(float(bonuses.get("bleeding", -1.0)), 0.60, "bleeding must add 0.60 to survival drain")
	_check_close(float(bonuses.get("fracture", -1.0)), 0.35, "fracture must add 0.35 to survival drain")
	_check_close(float(bonuses.get("curse", -1.0)), 0.50, "curse must add 0.50 to survival drain")

	var baseline := _measure_survival_loss([])
	var bleeding := _measure_survival_loss(["bleeding"])
	var fracture := _measure_survival_loss(["fracture"])
	var curse := _measure_survival_loss(["curse"])
	var stacked := _measure_survival_loss(["bleeding", "fracture", "curse"])
	_check_loss_multiplier(bleeding, baseline, 1.60, "bleeding")
	_check_loss_multiplier(fracture, baseline, 1.35, "fracture")
	_check_loss_multiplier(curse, baseline, 1.50, "curse")
	_check_loss_multiplier(stacked, baseline, ExpeditionSession.MAX_DRAIN_MULTIPLIER, "stacked ailments")

	ExpeditionSession.begin_new_journey()
	ExpeditionSession.apply_condition("bleeding", 30.0)
	ExpeditionSession.advance_survival(29.0)
	_check(ExpeditionSession.has_condition("bleeding"), "an ailment must remain active before its duration expires")
	ExpeditionSession.advance_survival(1.1)
	_check(not ExpeditionSession.has_condition("bleeding"), "an ailment must clear when its duration expires")
	var hunger_before := ExpeditionSession.hunger
	var thirst_before := ExpeditionSession.thirst
	ExpeditionSession.advance_survival(SAMPLE_SECONDS)
	_check_close(hunger_before - ExpeditionSession.hunger, baseline.x, "expired bleeding must restore baseline hunger drain")
	_check_close(thirst_before - ExpeditionSession.thirst, baseline.y, "expired bleeding must restore baseline thirst drain")

	ExpeditionSession.apply_condition("curse", 90.0)
	ExpeditionSession.clear_condition("curse")
	_check(not ExpeditionSession.has_condition("curse"), "clear_condition must remove an active ailment immediately")


func _measure_survival_loss(condition_ids: Array) -> Vector2:
	ExpeditionSession.begin_new_journey()
	for condition_id in condition_ids:
		ExpeditionSession.apply_condition(condition_id, SAMPLE_SECONDS * 2.0)
	var hunger_before := ExpeditionSession.hunger
	var thirst_before := ExpeditionSession.thirst
	ExpeditionSession.advance_survival(SAMPLE_SECONDS)
	return Vector2(hunger_before - ExpeditionSession.hunger, thirst_before - ExpeditionSession.thirst)


func _check_loss_multiplier(actual: Vector2, baseline: Vector2, expected_multiplier: float, label: String) -> void:
	_check(baseline.x > 0.0 and baseline.y > 0.0, "baseline drain fixture must lose both needs")
	if baseline.x <= 0.0 or baseline.y <= 0.0:
		return
	_check_close(actual.x / baseline.x, expected_multiplier, "%s must apply its authored hunger multiplier" % label)
	_check_close(actual.y / baseline.y, expected_multiplier, "%s must apply its authored thirst multiplier" % label)


func _test_new_journey_reset() -> void:
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.advance_survival(900.0)
	ExpeditionSession.apply_condition("bleeding", 120.0)
	ExpeditionSession.apply_condition("curse", 120.0)
	ExpeditionSession.begin_new_journey()
	_check_close(ExpeditionSession.hunger, ExpeditionSession.MAX_NEED, "a new journey must reset hunger")
	_check_close(ExpeditionSession.thirst, ExpeditionSession.MAX_NEED, "a new journey must reset thirst")
	_check(ExpeditionSession.active_conditions.is_empty(), "a new journey must clear every survival ailment")
	var snapshot := ExpeditionSession.get_survival_snapshot()
	_check_close(float(snapshot.get("hunger", -1.0)), ExpeditionSession.MAX_NEED, "the survival snapshot must expose reset hunger")
	_check_close(float(snapshot.get("thirst", -1.0)), ExpeditionSession.MAX_NEED, "the survival snapshot must expose reset thirst")


func _test_survival_consumables() -> void:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var player := DungeonPlayer.new()
	_check(not ExpeditionInventory.get_item_definition("pilgrim_ration").is_empty(), "the survival catalog must include pilgrim rations")
	_check(not ExpeditionInventory.get_item_definition("boiled_rainwater").is_empty(), "the survival catalog must include boiled rainwater")
	inventory.add_item("pilgrim_ration", 2)
	inventory.add_item("boiled_rainwater", 2)

	ExpeditionSession.hunger = 50.0
	ExpeditionSession.thirst = 40.0
	var ration_count := inventory.count_item("pilgrim_ration")
	var ration_result := player.use_consumable("pilgrim_ration", inventory)
	_check(bool(ration_result.get("accepted", false)), "a ration must be usable while hunger is missing")
	_check(inventory.count_item("pilgrim_ration") == ration_count - 1, "using a ration must consume exactly one item")
	_check_close(ExpeditionSession.hunger, 82.0, "a ration must restore exactly 32 hunger")
	_check_close(ExpeditionSession.thirst, 40.0, "a ration must not change thirst")
	_check_close(float(ration_result.get("hunger_restored", -1.0)), 32.0, "ration result must report the exact hunger restored")
	_check_close(float(ration_result.get("thirst_restored", -1.0)), 0.0, "ration result must report no thirst restoration")

	var water_count := inventory.count_item("boiled_rainwater")
	var water_result := player.use_consumable("boiled_rainwater", inventory)
	_check(bool(water_result.get("accepted", false)), "boiled rainwater must be usable while thirst is missing")
	_check(inventory.count_item("boiled_rainwater") == water_count - 1, "drinking water must consume exactly one item")
	_check_close(ExpeditionSession.thirst, 78.0, "boiled rainwater must restore exactly 38 thirst")
	_check_close(ExpeditionSession.hunger, 82.0, "boiled rainwater must not change hunger")
	_check_close(float(water_result.get("thirst_restored", -1.0)), 38.0, "water result must report the exact thirst restored")
	_check_close(float(water_result.get("hunger_restored", -1.0)), 0.0, "water result must report no hunger restoration")

	ExpeditionSession.hunger = ExpeditionSession.MAX_NEED
	ration_count = inventory.count_item("pilgrim_ration")
	var full_ration_result := player.use_consumable("pilgrim_ration", inventory)
	_check(not bool(full_ration_result.get("accepted", true)), "a ration must be rejected when hunger is already full")
	_check(inventory.count_item("pilgrim_ration") == ration_count, "a rejected full-hunger ration must not be consumed")

	ExpeditionSession.thirst = ExpeditionSession.MAX_NEED
	water_count = inventory.count_item("boiled_rainwater")
	var full_water_result := player.use_consumable("boiled_rainwater", inventory)
	_check(not bool(full_water_result.get("accepted", true)), "water must be rejected when thirst is already full")
	_check(inventory.count_item("boiled_rainwater") == water_count, "rejected water at full thirst must not be consumed")

	ExpeditionSession.hunger = 90.0
	var capped_result := player.use_consumable("pilgrim_ration", inventory)
	_check(bool(capped_result.get("accepted", false)), "a ration must still be usable when some hunger is missing")
	_check_close(ExpeditionSession.hunger, ExpeditionSession.MAX_NEED, "ration restoration must clamp at maximum hunger")
	_check_close(float(capped_result.get("hunger_restored", -1.0)), 10.0, "a capped ration must report only the amount actually restored")
	player.free()


func _test_damage_ailments() -> void:
	ExpeditionSession.begin_new_journey()
	var player := DungeonPlayer.new()
	root.add_child(player)
	var front := -player.global_transform.basis.z
	player.blocking = true
	player.block_time = 0.1
	var health_before := player.health
	var parry_result := player.receive_attack(20.0, player.global_position + front * 1.5, "bleeding")
	_check(bool(parry_result.get("parried", false)), "the combat fixture must produce a just guard")
	_check_close(player.health, health_before, "a parry must prevent health damage")
	_check(not ExpeditionSession.has_condition("bleeding"), "a zero-damage parry must not inflict its attack ailment")

	player.blocking = false
	var hit_result := player.receive_attack(8.0, player.global_position + front * 1.5, "fracture")
	_check(float(hit_result.get("damage", 0.0)) > 0.0, "the direct-hit fixture must deal real health damage")
	_check(ExpeditionSession.has_condition("fracture"), "a damaging enemy attack must inflict its authored ailment")
	player.receive_environment_damage(4.0, "test curse trap", "curse")
	_check(ExpeditionSession.has_condition("curse"), "damaging environment or trap attacks must inflict their authored ailment")
	player.free()


func _test_scene_tick_policy() -> void:
	ExpeditionSession.begin_new_journey()
	var dungeon_scene := load("res://main.tscn") as PackedScene
	_check(dungeon_scene != null, "dungeon scene must load for survival tick integration")
	if dungeon_scene == null:
		return
	var dungeon := dungeon_scene.instantiate()
	root.add_child(dungeon)
	current_scene = dungeon
	await process_frame
	await physics_frame
	_check(dungeon.has_method("_process") and dungeon.has_method("_pause_game"), "dungeon gameplay script must load for survival tick integration")
	if not dungeon.has_method("_process") or not dungeon.has_method("_pause_game"):
		dungeon.queue_free()
		await process_frame
		return

	var hunger_before := ExpeditionSession.hunger
	var thirst_before := ExpeditionSession.thirst
	dungeon._process(SAMPLE_SECONDS)
	_check(ExpeditionSession.hunger < hunger_before and ExpeditionSession.thirst < thirst_before, "survival needs must fall while the realtime dungeon is running")

	dungeon._pause_game()
	var paused_hunger := ExpeditionSession.hunger
	var paused_thirst := ExpeditionSession.thirst
	dungeon._process(TEN_MINUTES)
	_check_close(ExpeditionSession.hunger, paused_hunger, "hunger must stop while the dungeon is paused")
	_check_close(ExpeditionSession.thirst, paused_thirst, "thirst must stop while the dungeon is paused")
	dungeon._resume_game()
	dungeon.queue_free()
	await process_frame

	ExpeditionSession.hunger = 64.0
	ExpeditionSession.thirst = 53.0
	ExpeditionSession.apply_condition("bleeding", 7200.0)
	var hideout_scene := load("res://hideout.tscn") as PackedScene
	_check(hideout_scene != null, "hideout scene must load for safe-zone survival integration")
	if hideout_scene == null:
		return
	var hideout := hideout_scene.instantiate() as SanctuaryHideout
	_check(hideout != null, "hideout gameplay script must load for safe-zone survival integration")
	if hideout == null:
		return
	root.add_child(hideout)
	current_scene = hideout
	await process_frame
	await physics_frame
	_check(hideout.player != null and hideout.player.safe_zone_mode, "hideout survival fixture must use the safe-zone player")
	var safe_hunger := ExpeditionSession.hunger
	var safe_thirst := ExpeditionSession.thirst
	var bleeding_duration := float(ExpeditionSession.active_conditions.get("bleeding", -1.0))
	_check_close(safe_hunger, 64.0, "entering the hideout must preserve session hunger")
	_check_close(safe_thirst, 53.0, "entering the hideout must preserve session thirst")
	_check(ExpeditionSession.has_condition("bleeding"), "entering the hideout must preserve active session ailments")
	hideout._process(3600.0)
	_check_close(ExpeditionSession.hunger, safe_hunger, "hunger must not fall in the hideout safe zone")
	_check_close(ExpeditionSession.thirst, safe_thirst, "thirst must not fall in the hideout safe zone")
	_check_close(float(ExpeditionSession.active_conditions.get("bleeding", -1.0)), bleeding_duration, "ailment duration must not elapse in the hideout safe zone")
	hideout.queue_free()
	await process_frame


func _check_close(actual: float, expected: float, message: String) -> void:
	_check(absf(actual - expected) <= FLOAT_TOLERANCE, "%s (expected %.4f, got %.4f)" % [message, expected, actual])


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("SURVIVAL SYSTEM TEST PASS: pacing, ailments, consumables, damage, pause, safe zone, and reset")
		quit(0)
		return
	for failure in failures:
		push_error("SURVIVAL SYSTEM TEST FAIL: %s" % failure)
	quit(1)
