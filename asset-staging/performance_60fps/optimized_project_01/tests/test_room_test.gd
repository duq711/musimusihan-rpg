extends SceneTree

# Headless cannot capture a pointer. Replace only that platform input boundary;
# all timers, audio generation, 3D placement, thresholds and cleanup stay real.
class CapturedStressPerception extends StressPerception:
	func _has_input_capture() -> bool:
		return true if DisplayServer.get_name() == "headless" else super._has_input_capture()


var failures: Array[String] = []
var room: Node3D
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 7)
	original.equipment["weapon"] = "hunting_bow"
	var original_arrows := original.count_item("wooden_arrow")
	var original_flails := original.count_item("chain_flail")
	var original_camp_kits := original.count_item("camp_kit")
	var original_ingredients := {"raw_meat": original.count_item("raw_meat"), "edible_mushroom": original.count_item("edible_mushroom")}
	var original_slots := original.slots.duplicate(true)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 61
	ExpeditionSession.set_stress(37.5)
	ExpeditionSession.learn_spell("water_bolt")
	sandbox = root.get_node("TestRoomSandbox")
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	await process_frame
	_check(sandbox.active, "room must start an isolated test session")
	_check(room.inventory != original, "sandbox must not use the original inventory")
	_check(room.panel_open and paused, "room must start with the paused test menu")
	_check(not room.player.chest_equipment_stowed and is_instance_valid(room.player.chest_hands) and not room.player.chest_hands.visible, "isolated room entry must start without a hand interaction or hidden weapon state")
	_check(room.enemies_alive == 2 and get_nodes_in_group("trap").size() == 2, "two enemies and two traps must be available")
	_check(ExpeditionSession.crowns == 9999, "sandbox must provide shop funds")
	_check(ExpeditionSession.stress == 0.0, "new trial must begin calm without carrying the original stress")
	_test_catalog()
	await _test_menu_keys()
	await _test_pause_and_recovery()
	_test_features()
	await _test_archery_fixture()
	await _test_archery_accuracy_fixture()
	await _test_archery_power_fixture()
	await _test_flail_fixture()
	await _test_camping_fixture()
	await _test_cooking_fixture()
	await _test_stress_fixtures()
	await _test_chest_fixture()
	await _test_interaction_positions()
	await process_frame
	_test_reset_and_results()
	await process_frame
	await _test_scene_roundtrip()
	_check(ExpeditionSession.get_inventory() == original, "leaving must restore the original inventory identity")
	_check(original.count_item("wooden_arrow") == original_arrows and original.slots == original_slots, "sandbox shooting and restocking must not change the original arrow stacks")
	_check(original.equipment.weapon == "hunting_bow", "leaving must restore the original equipped bow")
	_check(original.count_item("chain_flail") == original_flails, "flail strikes, throws and fixture resets must preserve the original flail inventory")
	_check(original.count_item("camp_kit") == original_camp_kits, "camp setup, meals, treatment and trial resupply must restore the original camping kit count")
	for ingredient_id in original_ingredients:
		_check(original.count_item(ingredient_id) == original_ingredients[ingredient_id], "actual cooking, interrupted recipes and restocking must restore original ingredient quantities: " + ingredient_id)
	_check(ExpeditionSession.crowns == 73 and ExpeditionSession.hunger == 61, "leaving must restore wallet and survival")
	_check(is_equal_approx(ExpeditionSession.stress, 37.5), "leaving must restore original stress after actual trial accumulation, hallucinations, camping and scene changes")
	_check(ExpeditionSession.get_learned_spell_ids() == ["water_bolt"], "sandbox spells must not leak")
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	await process_frame
	paused = false
	if failures.is_empty():
		print("TEST ROOM PASS: catalog, actors, chest hands/equipment/repeat/cancellation, stress accumulation/recovery/perception/isolation, pause, camping, flail, archery, fixtures, results, reset, scene roundtrip and original session restoration")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)


func _test_catalog() -> void:
	var ids: Dictionary = {}
	for entry in room.feature_entries:
		_check(not ids.has(entry.id), "feature IDs must be unique: " + entry.id)
		ids[entry.id] = true
		_check(entry.action in ["movement", "performance", "armed", "wall_equipment", "skeleton", "flail", "camping", "cooking", "stress", "survival_controls", "archery", "archery_accuracy", "archery_power", "torch", "inventory", "player_appearance", "player_arm_motion", "dark_fantasy_gallery", "chest", "traps", "ai", "respawn", "extraction", "death", "spell", "learn_books", "needs", "wounded", "time", "cleanse", "condition", "item", "scene", "cave_zone"], "every entry must have an executable action")
	_check(ids.has("survival_controls"), "actual status controls must have an executable catalog entry")
	_check(ids.has("cave_dungeon"), "the 131m by 139m cave must have an executable real-scene entry")
	_check(ids.has("archery"), "archery must have an explicit executable system fixture in addition to automatic item entries")
	_check(ids.has("archery_accuracy"), "draw-dependent accuracy must have an explicit playable comparison fixture")
	_check(ids.has("archery_power"), "draw-dependent damage and sustained stamina must have an explicit playable fixture")
	_check(ids.has("flail") and ids.has("item:chain_flail"), "flail actions need an explicit fixture while the weapon itself remains automatically catalogued")
	_check(ids.has("camping") and ids.has("item:camp_kit"), "camping needs an executable survival fixture and automatic kit registration")
	_check(ids.has("cooking") and ids.has("item:raw_meat") and ids.has("item:edible_mushroom"), "cooking needs an actual camp fixture while ingredients remain automatically catalogued")
	_check(ids.has("stress_meter") and ids.has("stress_audio") and ids.has("stress_vision"), "stress needs actual accumulation, audio and visual perception fixtures")
	var stocked: Dictionary = {}
	for chest in room.loot_chests:
		for stack in chest.container.items:
			stocked[stack.id] = true
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		_check(ids.has("item:" + item_id), "all items must automatically appear in the menu")
		_check(stocked.has(item_id), "all items must be present in searchable chests: " + item_id)
	for spell_id in SpellCatalog.ordered_spell_ids():
		_check(ids.has("spell:" + spell_id), "all spells must automatically appear")
	for condition_id in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		_check(ids.has("condition:" + condition_id), "all conditions must automatically appear")
	for category in TestRoomCatalog.CATEGORIES:
		room._select_category(category)
		_check(room.entry_list.get_child_count() > 0, "each category must render usable buttons")


func _test_menu_keys() -> void:
	await _press_key(KEY_F2)
	_check(not room.panel_open and not paused, "F2 must close the menu through the input pipeline")
	await _press_key(KEY_F2)
	_check(room.panel_open and paused, "F2 must reopen the menu through the input pipeline")
	room.run_feature("inventory")
	await _press_key(KEY_F2)
	_check(room.panel_open and not room.inventory_overlay.is_open(), "F2 from inventory must return to the test menu")


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _test_pause_and_recovery() -> void:
	var enemy := get_nodes_in_group("enemy")[0] as DungeonEnemy
	var trap := get_nodes_in_group("trap")[0] as RuneTrap
	room.player.stamina = 20
	room.player.stamina_regen_delay = 0
	room._set_enemy_ai(true)
	trap.state = RuneTrap.TrapState.DISARMING
	trap.player = room.player
	room.player.current_trap = trap
	var enemy_time := enemy.state_time
	var trap_time := trap.needle_phase
	var hunger_before := ExpeditionSession.hunger
	ExpeditionSession.set_stress(65.0)
	var stress_before := ExpeditionSession.stress
	await create_timer(0.1, true).timeout
	_check(room.player.stamina == 20 and enemy.state_time == enemy_time and trap.needle_phase == trap_time, "test menu must freeze actor and trap time")
	_check(ExpeditionSession.hunger == hunger_before, "test menu must freeze survival")
	_check(ExpeditionSession.stress == stress_before, "test menu must freeze stress accumulation")
	room._recover_player()
	_check(trap.state == RuneTrap.TrapState.ARMED and room.player.current_trap == null, "recovery must cancel both sides of a trap interaction")
	_check(room.player.health == 100 and room.player.stamina == 100, "recovery must refill health and stamina")
	_check(ExpeditionSession.stress == 0.0, "recovery must also clear stress")
	room._set_enemy_ai(false)
	room._hide_test_panel()
	room._process(2)
	_check(ExpeditionSession.hunger < hunger_before, "survival must resume in the playable room")
	room._show_test_panel()


func _test_features() -> void:
	room.run_feature("needs")
	_check(ExpeditionSession.hunger == 10 and ExpeditionSession.thirst == 10, "low needs fixture must be reproducible")
	room.run_feature("wounded")
	_check(room.player.health == 25 and ExpeditionSession.has_condition("bleeding"), "wounded fixture must apply damage and bleeding")
	for condition_id in ExpeditionSession.CONDITION_DRAIN_BONUSES:
		room.run_feature("condition:" + condition_id)
		_check(ExpeditionSession.has_condition(condition_id), "condition fixture must apply " + condition_id)
	room.run_feature("cleanse")
	_check(ExpeditionSession.active_conditions.is_empty() and ExpeditionSession.hunger == 100, "cleanse must restore survival")
	room.run_feature("learn_books")
	_check(ExpeditionSession.learned_spells.is_empty(), "book fixture must permit learning again")
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		if ExpeditionInventory.get_item_definition(item_id).get("effect", "") == "learn_spell":
			_check(room.inventory.count_item(item_id) > 0, "book fixture must supply every book")
	for spell_id in SpellCatalog.ordered_spell_ids():
		room.run_feature("spell:" + spell_id)
		_check(room.inventory.equipment.weapon == "weathered_staff", "spell fixture must equip a staff")
		_check(ExpeditionSession.get_selected_spell() == spell_id, "spell fixture must select the requested spell")
		var result: Dictionary = room.player.cast_spell(spell_id, Vector3.FORWARD)
		_check(bool(result.get("accepted", false)), "spell fixture must actually cast: " + spell_id)
		room._show_test_panel()
	room.run_feature("melee")
	_check(room.enemy_ai_enabled and room.inventory.equipment.weapon == "rusted_sword", "melee fixture must enable real combat")
	room._show_test_panel()
	room.run_feature("skeleton")
	_check((get_nodes_in_group("enemy")[0] as DungeonEnemy).is_reference_skeleton, "skeleton fixture must use the anatomical model")
	room._show_test_panel()
	room.run_feature("respawn")
	_check(room.enemies_alive == 2 and not room.enemy_ai_enabled, "respawn must reset targets to safe stationary mode")
	room.run_feature("chest")
	_check(room.player.position.distance_to(room.loot_chests[0].position + Vector3(0, 1, 1.6)) < 0.01 and room.player._pitch < 0.0, "chest fixture must move 1.6 metres in front and aim down at the actual lock")
	room._show_test_panel()
	room.run_feature("respawn")
	room.run_feature("traps")
	_check(room.player.head.rotation.x < 0, "trap fixture must look down at the pressure plate")
	room._show_test_panel()
	room.run_feature("inventory")
	_check(room.inventory_overlay.is_open() and paused, "inventory fixture must open the real inventory")
	room._close_inventory()
	room._show_test_panel()
	var before: int = room.inventory.count_item("black_salt")
	room.run_feature("item:black_salt")
	_check(room.inventory.count_item("black_salt") == before + 1, "item fixture must grant exactly one")
	while room.inventory.slots.size() < ExpeditionInventory.MAX_SLOTS:
		room.inventory.add_item("reliquary")
	var count: int = room.inventory.count_item("weathered_staff")
	room.run_feature("item:weathered_staff")
	_check(room.inventory.count_item("weathered_staff") == count and "가득" in room.status_label.text, "full bag must reject grants visibly")


func _test_reset_and_results() -> void:
	ExpeditionSession.set_stress(90.0)
	room.reset_room()
	_check(ExpeditionSession.stress == 0.0, "reset must begin a new calm trial while keeping the original backup")
	_check(room.inventory == ExpeditionSession.get_inventory() and room.player.inventory_model == room.inventory, "reset must rebind the new sandbox inventory")
	room.run_feature("death")
	_check(room.game_mode == room.GameMode.DEAD and paused, "death fixture must show a paused result")
	var restart := InputEventKey.new()
	restart.physical_keycode = KEY_R
	restart.pressed = true
	room._unhandled_input(restart)
	_check(room.panel_open and room.player.health == 100 and room.player.combat_state == DungeonPlayer.CombatState.READY, "R after death must reset this room, not enter the dungeon")
	room.run_feature("extraction")
	room._on_extraction_body_entered(room.player)
	_check(room.game_mode == room.GameMode.WON, "extraction fixture must use the real win condition")
	room._unhandled_input(restart)
	_check(room.panel_open and room.enemies_alive == 2 and room.player.position == room.HOME_POSITION, "R after success must restore the test room")


func _test_archery_fixture() -> void:
	# The previous fixture deliberately left a full bag. Remove its starter arrows
	# and fill the gap to exercise the explicit sandbox-only replacement path.
	var existing_arrows: int = room.inventory.count_item("wooden_arrow")
	if existing_arrows > 0:
		room.inventory.remove_item("wooden_arrow", existing_arrows)
	while room.inventory.slots.size() < ExpeditionInventory.MAX_SLOTS:
		room.inventory.add_item("reliquary")
	room.run_feature("archery")
	_check(not room.panel_open and not paused, "archery fixture must return to real gameplay")
	_check(room.inventory.equipment.weapon == "hunting_bow" and room.player.get_arrow_count() == 30, "archery fixture must equip the bow and supply 30 arrows even with a full bag")
	_check(room.inventory.slots.size() == ExpeditionInventory.MAX_SLOTS and "교체" in room.status_label.text, "full-bag fixture must keep bag capacity and disclose the sandbox stack replacement")
	var target := get_nodes_in_group("enemy")[0] as DungeonEnemy
	_check(not room.enemy_ai_enabled and not target.is_physics_processing(), "archery must prepare a safe stationary target")
	_check(is_equal_approx(room.player.position.distance_to(target.position), 8.0), "archery fixture must place the player eight metres from the target")
	# Disable player movement for deterministic headless physics, keeping the
	# production projectile and enemy collision running in the real room.
	room.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	var start: Dictionary = room.player.begin_bow_draw()
	_check(bool(start.get("accepted", false)), "archery fixture must begin the actual bow draw")
	_check(room.player.get_arrow_count() == 30, "drawing must not consume a test arrow")
	room.player._update_combat(room.player.BOW_DRAW_DURATION)
	var shot: Dictionary = room.player.release_bow_shot()
	_check(bool(shot.get("accepted", false)), "archery fixture must fire through the real player action")
	_check(room.player.get_arrow_count() == 29 and room.player.stamina < room.player.MAX_STAMINA, "firing must consume exactly one arrow and real stamina")
	var projectiles := _room_arrows()
	_check(projectiles.size() == 1, "real archery must spawn exactly one physical arrow")
	if not projectiles.is_empty():
		var projectile := projectiles[0] as Node3D
		_check(projectile.process_mode == Node.PROCESS_MODE_PAUSABLE, "test-room arrow simulation must be pausable")
		room._show_test_panel()
		var arrow_position := projectile.position
		await create_timer(0.1, true).timeout
		_check(is_instance_valid(projectile) and projectile.position == arrow_position, "opening the test menu must freeze an arrow in flight")
		room._hide_test_panel()
	var target_health := target.health
	for frame in range(90):
		await physics_frame
		if target.health < target_health:
			break
	_check(target.health < target_health, "the fixture's initial aim must hit the actual stationary enemy with an arrow")
	room.player.bow_cooldown = 2.0
	room.player.bow_drawing = true
	room.player.bow_draw_time = 0.5
	room._recover_player()
	_check(not room.player.bow_drawing and room.player.bow_draw_time == 0 and room.player.bow_cooldown == 0, "recovery must reset bow draw and cooldown for another test")
	_check(room.player.get_arrow_count() == 29, "health recovery must not silently grant ammunition")
	room._show_test_panel()
	room.run_feature("archery")
	_check(room.player.get_arrow_count() == 30 and _room_arrows().is_empty(), "repeating archery must restock exactly 30 arrows and clear old shots")
	room.player.begin_bow_draw()
	room.player.release_bow_shot()
	_check(_room_arrows().size() == 1, "cleanup fixture must first have a real arrow in flight")
	room._show_test_panel()
	room.run_feature("respawn")
	_check(_room_arrows().is_empty(), "target regeneration must also remove in-flight arrows")
	room.run_feature("archery")
	room.player.begin_bow_draw()
	room._show_test_panel()
	_check(not room.player.bow_drawing and room.player.get_arrow_count() == 30, "opening the test menu while drawing must cancel without consuming arrows")
	room._hide_test_panel()
	room.player.begin_bow_draw()
	room._open_inventory()
	_check(not room.player.bow_drawing and room.player.get_arrow_count() == 30, "opening real inventory while drawing must cancel without consuming arrows")
	room._close_inventory()
	room._show_test_panel()
	room.player.set_physics_process(true)


func _room_arrows() -> Array[Node]:
	var arrows: Array[Node] = []
	for child in room.get_children():
		if child is ArrowProjectile:
			arrows.append(child)
	return arrows


func _test_archery_accuracy_fixture() -> void:
	room.run_feature("archery_accuracy")
	_check(not room.panel_open and not paused, "accuracy fixture must enter actual gameplay without auto-firing")
	_check(room.inventory.equipment.weapon == "hunting_bow" and room.player.get_arrow_count() == 30 and _room_arrows().is_empty(), "accuracy fixture must equip a bow, restock 30 arrows and wait for player input")
	var board := room.get_node_or_null("ArcheryAccuracyTarget") as StaticBody3D
	_check(board != null and get_nodes_in_group("enemy").is_empty(), "accuracy fixture must offer a real unobstructed collision target")
	if board == null:
		return
	_check(is_equal_approx(room.player.position.z - board.position.z, 8.0) and board.collision_layer == ArrowProjectile.WORLD_LAYER, "accuracy board must be eight metres away on the production arrow world layer")
	_check(board.get_node_or_null("TargetRing4") != null and board.get_node_or_null("AccuracyInstructions") != null, "accuracy board must have a visible bullseye and draw comparison instructions")
	_check("조준선" in room.status_label.text and "당길수록 축소" in (board.get_node("AccuracyInstructions") as Label3D).text, "existing accuracy fixture must explain the executable draw-reticle comparison")
	room.player.set_physics_process(false)
	await physics_frame
	await physics_frame
	await _test_archery_reticle_cycle()
	var expected_spreads := [12.0, 3.0, 0.0]
	var deviations: Array[float] = []
	var shots: Array[ArrowProjectile] = []
	var shot_origins: Array[Vector3] = []
	var aim: Vector3 = -room.player.camera.global_basis.z
	var aim_rotation: Vector3 = room.player.head.rotation
	for index in range(3):
		room._recover_player()
		# The same random sample isolates the charge curve from random luck.
		room.player.bow_shot_rng.seed = 711
		var begin: Dictionary = room.player.begin_bow_draw()
		_check(bool(begin.get("accepted", false)), "each accuracy comparison must begin a real bow draw")
		room.player._update_combat(room.player.BOW_DRAW_DURATION * index * 0.5)
		_check(is_equal_approx(room.player.get_bow_spread_degrees(), expected_spreads[index]), "live draw spread must match short / half / full comparison")
		var shot: Dictionary = room.player.release_bow_shot()
		_check(bool(shot.get("accepted", false)), "each accuracy comparison must fire the production bow action")
		if not bool(shot.get("accepted", false)):
			continue
		var direction: Vector3 = shot.get("shot_direction", Vector3.ZERO)
		var reported_aim: Vector3 = shot.get("aim_direction", Vector3.ZERO)
		var deviation := rad_to_deg(aim.angle_to(direction))
		deviations.append(deviation)
		_check(reported_aim.is_equal_approx(aim) and room.player.head.rotation.is_equal_approx(aim_rotation), "release recoil must preserve the actual aim for repeat comparisons")
		_check(is_equal_approx(float(shot.get("spread_degrees", -1.0)), expected_spreads[index]), "each shot must retain its draw-dependent spread profile")
		if index > 0:
			_check(deviation <= expected_spreads[index] + 0.001, "tensioned shots must stay inside their draw-dependent aim cone")
		_check(room.player.get_arrow_count() == 29 - index, "each accuracy shot must spend exactly one test arrow")
		var projectile := shot.get("projectile") as ArrowProjectile
		_check(projectile != null, "each accuracy shot must create a physical arrow")
		if projectile != null:
			_check(projectile.velocity.normalized().is_equal_approx(direction), "reported spread must drive the actual physical arrow, not just fixture text")
			if index == 0:
				_check(projectile.velocity.is_equal_approx(Vector3.DOWN) and is_zero_approx(projectile.speed) and is_equal_approx(projectile.gravity, 9.8), "an immediate release must drop straight down at one metre per second with no forward launch speed")
			shots.append(projectile)
			shot_origins.append(projectile.global_position)
	_check(deviations.size() == 3 and deviations[1] > deviations[2] and deviations[2] < 0.001, "same-seed tensioned shots must converge from half to perfectly aimed full draw")
	for frame in range(90):
		await physics_frame
		if shots.all(func(projectile: ArrowProjectile) -> bool: return projectile.impacted):
			break
	_check(shots.size() == 3 and shots.all(func(projectile: ArrowProjectile) -> bool: return projectile.impacted), "all comparison arrows must fly and collide in the actual room")
	if shots.size() == 3:
		_check_floor_drop(shots[0], shot_origins[0], "immediate accuracy comparison")
		for projectile in [shots[1], shots[2]]:
			var stuck_ref: WeakRef = projectile.get("_stuck_target")
			_check(stuck_ref != null and stuck_ref.get_ref() == board, "seeded half and full comparison arrows must hit the real board")
		_check(absf(shots[1].global_position.x) > absf(shots[2].global_position.x), "tensioned board impacts must converge horizontally as the same-seed draw strengthens")
		var full_shot := shots[2]
		var target_ref: WeakRef = full_shot.get("_stuck_target")
		_check(target_ref != null and target_ref.get_ref() == board, "full-draw arrow must impact the actual accuracy board")
		_check(absf(full_shot.global_position.x - board.position.x) < 0.01 and absf(full_shot.global_position.y - board.position.y) < 0.2, "full draw must land near the bullseye with only the retained gravity drop")
	room._show_test_panel()
	room.run_feature("archery_accuracy")
	_check(room.player.get_arrow_count() == 30 and _room_arrows().is_empty() and get_nodes_in_group("test_fixture_prop").size() == 1, "repeating accuracy must restock, clear all shots and replace rather than accumulate boards")
	room._show_test_panel()
	room.run_feature("archery")
	_check(get_nodes_in_group("test_fixture_prop").is_empty() and get_nodes_in_group("enemy").size() == 1, "switching back to enemy archery must remove the accuracy board")
	room._show_test_panel()
	room.run_feature("archery_accuracy")
	room.player.begin_bow_draw()
	room.player.release_bow_shot()
	room._show_test_panel()
	room.run_feature("respawn")
	_check(get_nodes_in_group("test_fixture_prop").is_empty() and _room_arrows().is_empty() and room.enemies_alive == 2, "target regeneration must clear accuracy board and arrows and restore standard actors")
	room.run_feature("archery_accuracy")
	room.reset_room()
	_check(get_nodes_in_group("test_fixture_prop").is_empty() and _room_arrows().is_empty() and room.panel_open, "room reset must also clean the accuracy comparison fixture")
	room.player.set_physics_process(true)


func _test_archery_reticle_cycle() -> void:
	var idle_radius: float = room.hud.bow_spread_radius
	var center_position: Vector2 = room.hud.crosshair.position
	_check(is_equal_approx(idle_radius, 4.0) and is_equal_approx(room.hud.bow_spread_tick_length, 9.0), "accuracy fixture must start with the original small idle crosshair")
	_check(bool(room.player.begin_bow_draw().accepted), "reticle comparison must begin through the actual player draw action")
	var start_radius: float = room.hud.bow_spread_radius
	_check(start_radius > idle_radius and is_equal_approx(room.hud.bow_spread_tick_length, 15.0), "the instant a real draw begins the reticle must spread wide and lengthen its four ticks")
	var focal_length: float = room.get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(room.player.camera.fov) * 0.5)
	_check(is_equal_approx(start_radius, 4.0 + focal_length * tan(deg_to_rad(12.0))), "draw-start reticle must project actual 12-degree spread with the retained four-pixel centre gap")
	var previous_radius := start_radius
	var previous_tick := 15.0
	for step in range(1, 5):
		room.player._update_combat(0.25)
		var radius: float = room.hud.bow_spread_radius
		var tick_length: float = room.hud.bow_spread_tick_length
		var ratio := float(step) * 0.25
		_check(radius < previous_radius and tick_length < previous_tick, "both the actual reticle gap and tick length must continually shrink during the draw")
		_check(is_equal_approx(radius, 4.0 + focal_length * tan(deg_to_rad(room.player.get_bow_spread_degrees()))) and is_equal_approx(tick_length, lerpf(15.0, 9.0, ratio)), "every draw step must update the live HUD from real spread and charge")
		_check(room.hud.crosshair.position == center_position and room.hud.crosshair.visible, "the original central aiming dot must remain fixed during reticle expansion and contraction")
		previous_radius = radius
		previous_tick = tick_length
	_check(is_equal_approx(room.hud.bow_spread_radius, 4.0), "full draw must reach the original four-pixel centre gap")
	var full_positions: Array[Vector2] = []
	var full_sizes: Array[Vector2] = []
	for index in range(4):
		var tick := room.hud.bow_spread_ticks[index] as ColorRect
		full_positions.append(tick.position)
		full_sizes.append(tick.size)
		_check(tick.size == (Vector2(9, 4) if index < 2 else Vector2(4, 9)), "full-draw tick dimensions must preserve the original small crosshair shape")
	room.player._update_combat(0.5)
	for index in range(4):
		_check(room.hud.bow_spread_ticks[index].position == full_positions[index] and room.hud.bow_spread_ticks[index].size == full_sizes[index], "holding full draw must preserve the small completed reticle without further contraction")
	_check(is_equal_approx(room.player.stamina, 67.0) and room.player.get_arrow_count() == 30, "reticle animation must retain continuous stamina drain and not auto-fire before exhaustion")
	room.player.cancel_bow_draw()
	_check(is_equal_approx(room.hud.bow_spread_radius, idle_radius) and is_equal_approx(room.hud.bow_spread_tick_length, 9.0), "cancel must restore the small idle reticle immediately")
	room.player.begin_bow_draw()
	_check(is_equal_approx(room.hud.bow_spread_radius, start_radius), "a repeated draw must reopen the same maximum reticle rather than inherit the previous charge")
	room._show_test_panel()
	_check(not room.player.bow_drawing and not room.hud._archery_reticle_should_show(true), "opening the real test menu must cancel drawing and hide the reticle")
	await process_frame
	_check(not room.hud.bow_spread_reticle.visible, "paused test menu must actually hide the spread ticks")
	room._hide_test_panel()
	room.player.begin_bow_draw()
	room._open_inventory()
	_check(not room.player.bow_drawing and not room.hud._archery_reticle_should_show(true), "opening actual inventory must retain draw cancellation and reticle suppression")
	room._close_inventory()
	room._equip_weapon("rusted_sword")
	_check(not room.hud._archery_reticle_should_show(true), "changing away from a bow must keep the archery reticle hidden")
	room._equip_weapon("hunting_bow")
	room.player.stamina = 1.0
	room.player.begin_bow_draw()
	room.player.cancel_bow_draw()
	room.player._update_combat(0.1)
	_check(not room.player.bow_drawing and is_equal_approx(room.hud.bow_spread_radius, idle_radius) and room.player.get_arrow_count() == 30, "manual cancellation with low stamina must restore the reticle and prevent later automatic fire")
	room._recover_player()
	_check(is_equal_approx(room.hud.bow_spread_radius, idle_radius) and room.player.stamina == 100.0, "fixture recovery must leave the small ready reticle for the existing real shot comparisons")


func _test_archery_power_fixture() -> void:
	var durations := [0.0, 0.5, 1.0, 2.0]
	var damages := [18.0, 32.0, 46.0, 46.0]
	var centered_seed := _centered_bow_seed()
	room.player.set_physics_process(false)
	for index in range(durations.size()):
		room.run_feature("archery_power")
		_check(not room.panel_open and not paused, "power fixture must enter real gameplay without an automatic draw or shot")
		_check(room.player.get_arrow_count() == 30 and room.player.stamina == 100.0 and _room_arrows().is_empty(), "power fixture must recover stamina, restock exactly 30 arrows and clear previous shots")
		var target := room.archery_power_target as DungeonEnemy
		_check(is_instance_valid(target) and get_nodes_in_group("enemy").size() == 1 and not target.is_physics_processing(), "power fixture must prepare one real stationary damageable enemy")
		_check(is_equal_approx(room.player.position.distance_to(target.position), 8.0) and is_equal_approx(target.health, 150.0), "power fixture must start eight metres from a fresh 150-health target")
		var instructions := room.get_node_or_null("ArcheryPowerInstructions") as Label3D
		_check(instructions != null and "18" in instructions.text and "46" in instructions.text and "초당 22" in instructions.text, "power fixture must display the actual damage curve and sustained stamina instructions")
		await physics_frame
		await physics_frame
		# A near-centre production RNG sample isolates damage from the separate
		# accuracy test without disabling spread or bypassing real collisions.
		room.player.bow_shot_rng.seed = centered_seed
		_check(bool(room.player.begin_bow_draw().accepted), "each power comparison must start the real draw action")
		room.player._update_combat(durations[index])
		var before_release: float = room.player.stamina
		_check(is_equal_approx(before_release, 100.0 - durations[index] * 22.0), "actual draw updates must spend 22 stamina per second, including time held at full draw")
		var shot: Dictionary = room.player.release_bow_shot()
		_check(bool(shot.get("accepted", false)), "each power comparison must fire the production player action")
		_check(is_equal_approx(room.player.stamina, before_release) and room.player.get_arrow_count() == 29, "release must consume only one arrow with no additional stamina charge")
		_check(is_equal_approx(float(shot.get("draw_stamina_spent", -1.0)), durations[index] * 22.0) and is_zero_approx(float(shot.get("release_stamina_spent", -1.0))), "shot diagnostics must report cumulative draw cost separately from zero release cost")
		var projectile := shot.get("projectile") as ArrowProjectile
		_check(projectile != null and is_equal_approx(projectile.damage, damages[index]), "actual projectile damage must rise 18 / 32 / 46 and remain capped after full draw")
		var shot_origin := projectile.global_position if projectile != null else Vector3.ZERO
		var target_health := target.health
		for frame in range(90):
			await physics_frame
			if projectile != null and projectile.impacted:
				break
		if index == 0:
			_check_floor_drop(projectile, shot_origin, "immediate power comparison")
			_check(is_equal_approx(target.health, target_health) and is_zero_approx(room.archery_power_last_damage), "a slack arrow must fall at the player's feet without damaging the eight-metre enemy")
		else:
			_check(is_equal_approx(target_health - target.health, damages[index]), "actual body collision must reduce the real enemy's health by exactly the draw-dependent damage")
			_check(is_equal_approx(room.archery_power_last_damage, damages[index]) and "실제 명중" in room.hud.objective_label.text, "power fixture feedback must use the real projectile impact and applied damage")
		room._show_test_panel()
	room.run_feature("archery_power")
	_check(get_nodes_in_group("test_fixture_prop").size() == 1 and _room_arrows().is_empty(), "repeating power fixture must replace its instructions and clear previous arrows")
	room.player.begin_bow_draw()
	room.player._update_combat(0.25)
	var spent_stamina: float = room.player.stamina
	room._show_test_panel()
	_check(not room.player.bow_drawing and is_equal_approx(spent_stamina, 94.5) and is_equal_approx(room.player.stamina, spent_stamina), "test menu must cancel the held draw without refunding spent stamina")
	room.player._update_combat(2.0)
	await create_timer(0.1, true).timeout
	_check(is_equal_approx(room.player.stamina, spent_stamina) and room.player.get_arrow_count() == 30, "paused menu must freeze both stamina drain and regeneration without consuming ammunition")
	room._hide_test_panel()
	await _test_archery_exhaustion_shots(centered_seed)
	room._show_test_panel()
	room.run_feature("archery_accuracy")
	_check(room.archery_power_target == null and is_zero_approx(room.archery_power_last_damage) and room.get_node_or_null("ArcheryPowerInstructions") == null, "switching fixtures must clear power target state and instructions")
	room.reset_room()
	room.player.set_physics_process(true)


func _centered_bow_seed() -> int:
	var rng := RandomNumberGenerator.new()
	for candidate in range(4096):
		rng.seed = candidate
		var direction := BowShotProfile.sample_direction(Vector3.FORWARD, 0.5, rng)
		if rad_to_deg(Vector3.FORWARD.angle_to(direction)) < 0.15:
			return candidate
	_check(false, "damage comparison must find a deterministic near-centre production spread sample")
	return 711


func _test_archery_exhaustion_shots(centered_seed: int) -> void:
	var available_stamina := [100.0, 11.0, 1.1]
	var expected_charge := [1.0, 0.5, 0.05]
	for index in range(available_stamina.size()):
		room.run_feature("archery_power")
		await physics_frame
		await physics_frame
		var target := room.archery_power_target as DungeonEnemy
		var target_health := target.health
		room.player.stamina = available_stamina[index]
		room.player.bow_shot_rng.seed = centered_seed
		var fired_costs: Array[float] = []
		var fired_callback := func(_charge: float, cost: float) -> void: fired_costs.append(cost)
		room.player.arrow_fired.connect(fired_callback)
		_check(bool(room.player.begin_bow_draw().accepted), "exhaustion fixture must begin with its actual remaining stamina")
		# A long frame must advance charge only until the available stamina runs
		# out, then fire exactly once with that charge through production code.
		room.player._update_combat(6.0)
		room.player.arrow_fired.disconnect(fired_callback)
		var arrows := _room_arrows()
		_check(not room.player.bow_drawing and is_zero_approx(room.player.stamina) and room.player.get_arrow_count() == 29 and arrows.size() == 1, "exhaustion must release exactly one real arrow and spend exactly one ammunition item")
		_check(fired_costs.size() == 1 and is_equal_approx(fired_costs[0], available_stamina[index]), "automatic release must report only already spent draw stamina, with no extra release cost")
		_check(room.player.bow_cooldown > 0.0 and is_equal_approx(room.hud.bow_spread_radius, 4.0) and not room.hud._archery_reticle_should_show(true), "exhaustion release must restore the small reticle and enforce its normal hidden cooldown")
		if arrows.size() == 1:
			var projectile := arrows[0] as ArrowProjectile
			var shot_origin := projectile.global_position
			_check(is_equal_approx(projectile.charge, expected_charge[index]) and is_equal_approx(projectile.damage, lerpf(18.0, 46.0, expected_charge[index])), "automatic arrow strength and damage must match the draw reached at the exact exhaustion moment")
			if index == 2:
				_check(projectile.velocity.is_equal_approx(Vector3.DOWN) and is_zero_approx(projectile.speed), "exhausting before the slack threshold must release a downward drop, not a powered shot")
			for frame in range(90):
				await physics_frame
				if projectile.impacted:
					break
			if index == 2:
				_check_floor_drop(projectile, shot_origin, "slack exhaustion release")
				_check(is_equal_approx(target.health, target_health), "a low-stamina slack automatic arrow must not hit the distant target")
			else:
				_check(is_equal_approx(target_health - target.health, projectile.damage), "full and partial exhaustion releases must actually hit the fixture enemy with their current damage")
		_check(not bool(room.player.release_bow_shot().accepted) and room.player.get_arrow_count() == 29 and _room_arrows().size() == 1, "later mouse release must not duplicate an exhaustion shot")
		room.player._update_combat(1.0)
		_check(_room_arrows().size() == 1 and room.player.get_arrow_count() == 29, "later combat updates must not repeat an exhausted draw's automatic shot")
		room._show_test_panel()


func _check_floor_drop(projectile: ArrowProjectile, release_origin: Vector3, context: String) -> void:
	_check(projectile != null and projectile.impacted, context + " must complete an actual collision")
	if projectile == null:
		return
	var stuck_ref: WeakRef = projectile.get("_stuck_target")
	_check(stuck_ref != null and stuck_ref.get_ref() == room.get_node("TestFloor"), context + " must stick to the actual floor rather than the distant target")
	var horizontal_delta := Vector2(projectile.global_position.x - release_origin.x, projectile.global_position.z - release_origin.z)
	_check(horizontal_delta.length() < 0.01 and absf(projectile.global_position.y) < 0.01, context + " must land directly below the release position with no forward travel")


func _test_flail_fixture() -> void:
	room.run_feature("flail")
	room.player.set_physics_process(false)
	_check(not room.panel_open and not paused and room.inventory.equipment.weapon == "chain_flail", "flail fixture must equip the actual weapon and enter gameplay")
	var near_target := room.flail_near_target as DungeonEnemy
	var far_target := room.flail_far_target as DungeonEnemy
	_check(is_instance_valid(near_target) and is_instance_valid(far_target) and not room.enemy_ai_enabled, "flail fixture must prepare two safe actual enemies")
	_check(is_equal_approx(near_target.health, 200.0) and is_equal_approx(far_target.health, 200.0) and is_equal_approx(room.player.position.distance_to(near_target.position), 2.0), "flail fixture must offer two fresh 200-health targets and a two-metre melee start")
	_check(room.get_node_or_null("FlailNearLane") != null and room.get_node_or_null("FlailFarLane") != null and room.get_node_or_null("FlailFarInstructions") != null, "flail lanes must have visible movement markers and actionable instructions")
	var flail_count: int = room.inventory.count_item("chain_flail")
	var arrow_count: int = room.player.get_arrow_count()
	await physics_frame
	await physics_frame
	_check_station_label_in_view(room.get_node("FlailNearInstructions") as Label3D, "near flail instructions")
	_check(bool(room.player.begin_flail_melee().accepted), "flail fixture melee must use the real player action")
	room.player._update_flail(0.21)
	_check(is_equal_approx(near_target.health, 168.0) and is_equal_approx(far_target.health, 200.0), "actual short-range flail strike must damage only its nearby target for 32")
	_check(is_equal_approx(room.flail_last_damage, 32.0) and "철퇴 명중" in room.hud.objective_label.text, "flail fixture must report the real melee impact")
	room.player._update_flail(0.5)
	room._recover_player()
	room._teleport(Vector3(3, 1, 5))
	_check(is_equal_approx(room.player.position.distance_to(far_target.position), 8.0), "the marked right lane must give an unobstructed eight-metre throw")
	await physics_frame
	_check(bool(room.player.begin_flail_spin().accepted), "flail fixture must begin the real rotating attack")
	room.player._update_flail(1.2)
	_check(room.player.flail_state == "spinning" and is_equal_approx(room.player.stamina, 76.0), "full spin must charge to throw with one upfront 24-stamina cost")
	var throw_result: Dictionary = room.player.release_flail_throw()
	_check(bool(throw_result.get("accepted", false)), "flail fixture release must create a real physical throw")
	var projectiles := get_nodes_in_group("flail_projectile")
	_check(projectiles.size() == 1 and projectiles[0].process_mode == Node.PROCESS_MODE_PAUSABLE, "flail fixture must create exactly one pausable physical head")
	for frame in range(180):
		await physics_frame
		room.player._update_flail(1.0 / 60.0)
		if room.player.flail_state == "ready":
			break
	_check(is_equal_approx(far_target.health, 140.0) and is_equal_approx(near_target.health, 168.0), "the full throw must hit the distant enemy once for 60 with no return damage")
	_check(is_equal_approx(room.flail_last_damage, 60.0) and room.player.flail_state == "ready" and get_nodes_in_group("flail_projectile").is_empty(), "the actual throw must report its hit, return and rearm without a stray projectile")
	_check(room.inventory.count_item("chain_flail") == flail_count and room.player.get_arrow_count() == arrow_count and is_equal_approx(room.player.stamina, 76.0), "melee and throw must not consume flails, arrows or extra return stamina")
	room.player.begin_flail_spin()
	room.player._update_flail(0.5)
	var spin_stamina: float = room.player.stamina
	room._show_test_panel()
	room.player._update_flail(2.0)
	_check(room.player.flail_state == "ready" and get_nodes_in_group("flail_projectile").is_empty() and is_equal_approx(room.player.stamina, spin_stamina), "the test menu must safely cancel spinning, pause action time and retain spent stamina")
	room.run_feature("flail")
	_check(room.flail_last_damage == 0.0 and room.flail_near_target.health == 200.0 and room.flail_far_target.health == 200.0 and room.player.stamina == 100.0, "repeating the fixture must restore both targets, feedback and stamina")
	room.player.begin_flail_spin()
	room.player._update_flail(1.2)
	room.player.release_flail_throw()
	room._recover_player()
	await process_frame
	_check(room.player.flail_state == "ready" and get_nodes_in_group("flail_projectile").is_empty(), "recovery must cancel an outbound flail and restore its head without a lingering projectile")
	room.player.begin_flail_spin()
	room._open_inventory()
	_check(room.player.flail_state == "ready" and get_nodes_in_group("flail_projectile").is_empty(), "opening actual inventory must cancel a flail spin")
	room._close_inventory()
	room._show_test_panel()
	room.run_feature("archery")
	_check(room.flail_near_target == null and room.flail_far_target == null and room.get_node_or_null("FlailNearLane") == null and get_nodes_in_group("flail_projectile").is_empty(), "switching fixtures must clear flail actors, lane props and thrown head")
	room.reset_room()
	room.player.set_physics_process(true)


func _test_camping_fixture() -> void:
	for item_id in ["camp_kit", "pilgrim_ration", "boiled_rainwater", "linen_bandage"]:
		var count: int = room.inventory.count_item(item_id)
		if count > 0:
			room.inventory.remove_item(item_id, count)
	while room.inventory.slots.size() < ExpeditionInventory.MAX_SLOTS:
		room.inventory.add_item("reliquary")
	room.run_feature("camping")
	_check(not room.panel_open and not paused and room.camp.state == "closed", "camping fixture must enter the real safe world without automatically opening camp")
	_check(room.player.position == Vector3(0, 1, 12) and get_nodes_in_group("enemy").is_empty() and get_nodes_in_group("trap").is_empty(), "camping fixture must prepare an unobstructed safe starting point")
	_check(room.player.health == 35.0 and room.player.stamina == 20.0 and ExpeditionSession.hunger == 25.0 and ExpeditionSession.thirst == 25.0, "camping fixture must prepare visibly reduced health, stamina and needs")
	_check(ExpeditionSession.active_conditions == {"bleeding": 180.0, "fracture": 300.0, "curse": 240.0}, "camping fixture must provide actual timed ailments for rest and treatment comparisons")
	for item_id in ["camp_kit", "pilgrim_ration", "boiled_rainwater", "linen_bandage"]:
		_check(room.inventory.count_item(item_id) == 2, "camping fixture must supply exactly two " + item_id + " even from a full trial bag")
	_check("교체" in room.status_label.text and room.inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "full-bag camping resupply must disclose bounded trial-only replacement")
	await _settle_camping_player()
	_check_station_label_in_view(room.get_node("CampingInstructions") as Label3D, "camping instructions")
	var health_before: float = room.player.health
	var stamina_before: float = room.player.stamina
	var opened: Dictionary = room.open_camp()
	_check(bool(opened.get("accepted", false)), "camping fixture must open the actual installed camp after the player reaches the floor: " + str(opened.get("reason", "")))
	_check(room.camp.state == "planning" and paused and room.game_mode == room.GameMode.CAMPING, "camp planning must pause the real world")
	var planning_hunger := ExpeditionSession.hunger
	room._process(20.0)
	await create_timer(0.05, true).timeout
	_check(is_equal_approx(ExpeditionSession.hunger, planning_hunger), "planning must not advance ordinary dungeon survival time")
	_check(bool(room.camp.start_action("rest").get("accepted", false)), "rest must start through the real camp controller")
	_check(room.camp.state == "resting" and not paused and room.inventory.count_item("camp_kit") == 1 and room.camp.warmth == 2, "starting the first rest must consume one kit and one warmth immediately")
	var resting_hunger := ExpeditionSession.hunger
	room._process(20.0)
	_check(is_equal_approx(ExpeditionSession.hunger, resting_hunger), "ordinary game processing must not double-count survival time during a camp activity")
	room.camp.advance_rest(8.0)
	_check(room.camp.state == "planning" and paused and is_equal_approx(room.player.health, health_before + 20.0) and is_equal_approx(room.player.stamina, minf(100.0, stamina_before + 70.0)), "completed real rest must apply its health/stamina rewards and return to paused planning")
	_check(is_equal_approx(float(room.camp.last_result.get("survival_seconds", -1.0)), 60.0), "a completed fixture rest must advance exactly sixty survival seconds")
	_check(ExpeditionSession.hunger < resting_hunger and room.inventory.count_item("camp_kit") == 1, "rest must advance survival time without repeatedly consuming the setup kit")
	_check(bool(room.camp.start_action("treat").get("accepted", false)), "treatment must use the same installed camp")
	_check(room.inventory.count_item("linen_bandage") == 1 and room.inventory.count_item("camp_kit") == 1, "treatment must consume only one bandage after camp setup")
	room.camp.advance_rest(6.0)
	_check(is_equal_approx(float(room.camp.last_result.get("survival_seconds", -1.0)), 30.0), "fixture treatment must advance exactly thirty survival seconds")
	_check(not ExpeditionSession.has_condition("bleeding") and ExpeditionSession.has_condition("fracture") and ExpeditionSession.has_condition("curse"), "camp treatment must clear bleeding without incorrectly curing other ailments")
	_check(is_equal_approx(room.player.health, health_before + 38.0) and room.camp.warmth == 1, "completed treatment must restore 18 health and spend one further warmth")
	var food_before: int = room.inventory.count_item("pilgrim_ration")
	var water_before: int = room.inventory.count_item("boiled_rainwater")
	_check(not bool(room.camp.start_action("meal").get("accepted", false)) and room.inventory.count_item("pilgrim_ration") == food_before and room.inventory.count_item("boiled_rainwater") == water_before, "insufficient warmth must reject a meal without consuming its food or water")
	room._show_test_panel()
	_check(room.camp.state == "closed" and paused and room.panel_open, "F2 test menu must close the installed camp and retain the test pause")
	room.run_feature("camping")
	await _settle_camping_player()
	room.open_camp()
	room.inventory.remove_item("pilgrim_ration", 2)
	_check(not bool(room.camp.start_action("meal").get("accepted", false)) and room.inventory.count_item("camp_kit") == 2 and room.camp.warmth == 3, "missing meal resources must reject before consuming a kit or warmth")
	room.inventory.add_item("pilgrim_ration", 2)
	var meal_health: float = room.player.health
	var meal_hunger := ExpeditionSession.hunger
	var meal_thirst := ExpeditionSession.thirst
	_check(bool(room.camp.start_action("meal").get("accepted", false)), "stocked fixture must begin an actual camp meal")
	_check(room.inventory.count_item("camp_kit") == 1 and room.inventory.count_item("pilgrim_ration") == 1 and room.inventory.count_item("boiled_rainwater") == 1, "meal costs must be paid once at the start")
	room.camp.advance_rest(14.0)
	_check(is_equal_approx(float(room.camp.last_result.get("survival_seconds", -1.0)), 180.0), "fixture meal must advance exactly three minutes without ordinary-time double counting")
	_check(room.camp.state == "planning" and is_equal_approx(room.player.health, meal_health + 45.0) and room.player.stamina == 100.0, "completed meal must heal 45 and fully restore stamina")
	_check(ExpeditionSession.hunger > meal_hunger and ExpeditionSession.thirst > meal_thirst and room.camp.warmth == 1, "actual meal must restore hunger and thirst with the catalogue supplies and spend two warmth")
	room._show_test_panel()
	room.run_feature("camping")
	await _settle_camping_player()
	room.open_camp()
	var interrupted_health: float = room.player.health
	room.camp.start_action("rest")
	room.camp.advance_rest(3.0)
	await _press_key(KEY_F2)
	var interrupted_hunger := ExpeditionSession.hunger
	room.camp.advance_rest(30.0)
	_check(room.panel_open and paused and room.camp.state == "closed" and is_equal_approx(room.player.health, interrupted_health), "F2 during rest must cancel without granting completion rewards")
	_check(room.inventory.count_item("camp_kit") == 1 and is_equal_approx(ExpeditionSession.hunger, interrupted_hunger), "cancelled rest must not refund its kit or continue advancing survival time")
	room.run_feature("camping")
	await _settle_camping_player()
	room.open_camp()
	room.camp.start_action("rest")
	room._spawn_enemy("굶주린 야영 습격자", room.player.position + Vector3(0, 0, -5), 200, 18, 2.65, Color(0.21, 0.125, 0.105))
	room._set_enemy_ai(false)
	room.camp.advance_rest(0.1)
	_check(room.camp.state == "closed" and room.inventory.count_item("camp_kit") == 1, "an actual nearby enemy must interrupt ongoing camping without refunding the kit")
	room._show_test_panel()
	room.run_feature("camping")
	await _settle_camping_player()
	room.open_camp()
	room.camp.start_action("rest")
	room._on_player_died()
	_check(room.camp.state == "closed" and not room.player.camping and paused and room.game_mode == room.GameMode.DEAD, "the test-room death callback must explicitly cancel camping even when invoked directly")
	room._show_test_panel()
	room.run_feature("archery")
	_check(room.camp.state == "closed" and room.get_node_or_null("CampingInstructions") == null, "switching fixtures must remove camp activity and trial instructions")
	room.reset_room()
	room.player.set_physics_process(true)


func _test_cooking_fixture() -> void:
	var supplies: Dictionary = room._cooking_fixture_supplies()
	_check(supplies == {"camp_kit": 2, "raw_meat": 3, "edible_mushroom": 4, "boiled_rainwater": 3}, "cooking fixture supplies must derive all three recipes plus one spare of each ingredient")
	for item_id in supplies:
		var count: int = room.inventory.count_item(item_id)
		if count > 0:
			room.inventory.remove_item(item_id, count)
	while room.inventory.slots.size() < ExpeditionInventory.MAX_SLOTS:
		room.inventory.add_item("reliquary")
	room.run_feature("cooking")
	_check(not room.panel_open and not paused and room.camp.state == "closed", "cooking fixture must prepare actual play without automatically opening or starting camp")
	_check(room.player.position == room.HOME_POSITION and get_nodes_in_group("enemy").is_empty() and get_nodes_in_group("trap").is_empty(), "cooking fixture must clear threats at its real safe camp location")
	_check(room.player.health == 35.0 and room.player.stamina == 20.0 and ExpeditionSession.hunger == 15.0 and ExpeditionSession.thirst == 20.0 and ExpeditionSession.stress == 55.0 and ExpeditionSession.active_conditions.is_empty(), "cooking fixture must reproducibly prepare wounded, hungry, thirsty and stressed values without ailments")
	for item_id in supplies:
		_check(room.inventory.count_item(item_id) == supplies[item_id], "full trial bag must still receive the exact cooking supply: " + item_id)
	_check("교체" in room.status_label.text and room.inventory.slots.size() == ExpeditionInventory.MAX_SLOTS, "full-bag recipe restocking must disclose bounded trial-only stack replacement")
	await _settle_camping_player()
	_check_station_label_in_view(room.get_node("CookingInstructions") as Label3D, "cooking instructions")
	_check(bool(room.open_camp().get("accepted", false)), "prepared cooking fixture must open the actual camp")
	(room.camp.overlay.category_buttons.cooking as Button).pressed.emit()
	_check(room.camp.overlay.selected_category == "cooking" and room.camp.overlay.cooking_hint_label.visible, "actual cooking tab must expose its recipe guidance")
	var offered: Dictionary = {}
	for action: Dictionary in room.camp.get_snapshot().actions:
		offered[action.id] = true
	for recipe_id in CampCookingCatalog.ordered_recipe_ids():
		_check(offered.has(CampCookingCatalog.action_id(recipe_id)), "actual camp must offer every authoritative cooking recipe: " + recipe_id)
	var completed := 0
	for recipe_id in CampCookingCatalog.ordered_recipe_ids():
		var recipe := CampCookingCatalog.get_recipe(recipe_id)
		var action_id := CampCookingCatalog.action_id(recipe_id)
		if room.camp.warmth < int(recipe.warmth):
			var before_rejection := _cooking_inventory_counts()
			_check(not bool(room.camp.start_action(action_id).get("accepted", false)) and _cooking_inventory_counts() == before_rejection, "insufficient warmth must reject a real recipe without spending its ingredients")
			room.cancel_camp()
			_check(bool(room.open_camp().get("accepted", false)), "finite fixture warmth must permit a second actual camp using the spare kit")
		var health_before: float = room.player.health
		var stamina_before: float = room.player.stamina
		var hunger_before := ExpeditionSession.hunger
		var thirst_before := ExpeditionSession.thirst
		var stress_before := ExpeditionSession.stress
		room._process(30.0)
		_check(paused and room.camp.state == "planning" and ExpeditionSession.hunger == hunger_before and ExpeditionSession.stress == stress_before, "choosing a recipe in paused planning must not advance survival or stress")
		var expected_costs: Dictionary = recipe.resources.duplicate(true)
		if not room.camp.kit_spent:
			expected_costs["camp_kit"] = 1
		var counts_before := _cooking_inventory_counts()
		room.camp.overlay.select_category("cooking")
		var recipe_button := room.camp.overlay.action_buttons[action_id] as Button
		_check(recipe_button.is_visible_in_tree() and not recipe_button.disabled, "actual cooking tab must offer a usable stocked recipe button: " + recipe_id)
		recipe_button.pressed.emit()
		_check(room.camp.state == "resting" and not paused and bool(room.camp.get_snapshot().get("is_cooking", false)) and str(room.camp.get_snapshot().get("active_action_id", "")) == action_id, "pressing a stocked recipe's actual UI button must start real live cooking: " + recipe_id)
		for item_id in counts_before:
			_check(room.inventory.count_item(item_id) == int(counts_before[item_id]) - int(expected_costs.get(item_id, 0)), "cooking must spend exact starting resources and no other items: " + recipe_id + "/" + item_id)
		var bag_after_cost: Array = room.inventory.slots.duplicate(true)
		room.camp.advance_rest(float(recipe.duration) * 0.5)
		_check(room.player.health == health_before and room.player.stamina == stamina_before and ExpeditionSession.stress == stress_before, "unfinished cooking must grant no food healing, stamina or stress relief")
		var midway_hunger := ExpeditionSession.hunger
		room._process(30.0)
		_check(ExpeditionSession.hunger == midway_hunger, "ordinary game processing must not double-count recipe survival time")
		room.camp.advance_rest(float(recipe.duration))
		var expected_hunger := clampf(hunger_before - float(recipe.survival) * ExpeditionSession.MAX_NEED / ExpeditionSession.HUNGER_FULL_DURATION_SECONDS + float(recipe.hunger), 0.0, 100.0)
		var expected_thirst := clampf(thirst_before - float(recipe.survival) * ExpeditionSession.MAX_NEED / ExpeditionSession.THIRST_FULL_DURATION_SECONDS + float(recipe.thirst), 0.0, 100.0)
		_check(room.camp.state == "planning" and paused and not bool(room.camp.get_snapshot().get("is_cooking", false)), "finished cooking must return to paused camp planning")
		_check(is_equal_approx(room.player.health, minf(100.0, health_before + float(recipe.health))) and is_equal_approx(room.player.stamina, minf(100.0, stamina_before + float(recipe.stamina))), "finishing must automatically eat the real recipe and grant only its health/stamina effects: " + recipe_id)
		_check(is_equal_approx(ExpeditionSession.hunger, expected_hunger) and is_equal_approx(ExpeditionSession.thirst, expected_thirst) and is_equal_approx(ExpeditionSession.stress, maxf(0.0, stress_before - float(recipe.stress))), "automatic eating must apply catalogue needs and stress effects after exact survival time: " + recipe_id)
		_check(is_equal_approx(float(room.camp.last_result.get("survival_seconds", -1.0)), float(recipe.survival)) and room.inventory.slots == bag_after_cost, "completed recipe must clamp its elapsed survival time and create no stored meal or duplicate resources")
		completed += 1
	_check(completed == 3 and room.inventory.count_item("camp_kit") == 0, "all three actual recipes must be testable across two finite-warmth camps")
	for item_id in ["raw_meat", "edible_mushroom", "boiled_rainwater"]:
		_check(room.inventory.count_item(item_id) == 1, "one complete recipe comparison must leave only the documented spare ingredient: " + item_id)
	room._show_test_panel()
	room.run_feature("cooking")
	await _settle_camping_player()
	room.open_camp()
	room.inventory.remove_item("raw_meat", room.inventory.count_item("raw_meat"))
	var missing_before := _cooking_inventory_counts()
	_check(not bool(room.camp.start_action("cook:roast_meat").get("accepted", false)) and _cooking_inventory_counts() == missing_before and room.camp.warmth == 3, "missing actual cooking ingredients must reject before consuming kit or warmth")
	room._show_test_panel()
	room.run_feature("cooking")
	await _settle_camping_player()
	room.open_camp()
	var cancelled_health: float = room.player.health
	var cancelled_stamina: float = room.player.stamina
	var cancelled_stress := ExpeditionSession.stress
	room.camp.start_action("cook:roast_meat")
	room.camp.advance_rest(2.0)
	await _press_key(KEY_F2)
	var cancelled_counts := _cooking_inventory_counts()
	var cancelled_hunger := ExpeditionSession.hunger
	room.camp.advance_rest(30.0)
	_check(room.panel_open and paused and room.camp.state == "closed" and room.inventory.count_item("raw_meat") == 2 and room.inventory.count_item("camp_kit") == 1, "F2 must interrupt cooking without refunding consumed meat or the camp kit")
	_check(room.player.health == cancelled_health and room.player.stamina == cancelled_stamina and ExpeditionSession.stress == cancelled_stress and ExpeditionSession.hunger == cancelled_hunger and _cooking_inventory_counts() == cancelled_counts, "cancelled cooking must neither auto-eat nor continue timers or create output food")
	room.run_feature("cooking")
	await _settle_camping_player()
	room.open_camp()
	room.camp.start_action("cook:mushroom_soup")
	room.camp.advance_rest(2.0)
	var old_inventory: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.camp.state == "closed" and not room.player.camping and room.inventory != old_inventory and room.get_node_or_null("CookingInstructions") == null, "reset during cooking must cancel the active recipe and rebind a fresh isolated inventory")
	_check(ExpeditionSession.hunger == 100.0 and ExpeditionSession.stress == 0.0, "reset must remove recipe recovery state without changing the saved original expedition")
	room.player.set_physics_process(true)


func _cooking_inventory_counts() -> Dictionary:
	var counts: Dictionary = {}
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		counts[item_id] = room.inventory.count_item(item_id)
	return counts


func _test_stress_fixtures() -> void:
	var effects := _install_stress_probe(room)
	room.run_feature("stress_meter")
	_check(not room.panel_open and not paused and ExpeditionSession.stress == 30.0, "stress accumulation fixture must start actual play at exactly 30")
	_check(room.player.position == room.HOME_POSITION and room.player.health == 35.0 and room.player.stamina == 30.0, "accumulation fixture must prepare its safe position and wounded player")
	_check(ExpeditionSession.hunger == 20.0 and ExpeditionSession.thirst == 20.0 and ExpeditionSession.has_condition("bleeding"), "accumulation fixture must use actual needs and injury causes")
	_check(get_nodes_in_group("enemy").is_empty() and get_nodes_in_group("trap").is_empty(), "stress fixtures must not create a real combat threat")
	for item_id in ["camp_kit", "pilgrim_ration", "boiled_rainwater", "linen_bandage"]:
		_check(room.inventory.count_item(item_id) == 2, "stress recovery comparison must provide two real " + item_id)
	room._process(10.0)
	var lit_gain := ExpeditionSession.stress - 30.0
	_check(lit_gain > 0.0 and not effects.trigger_event("whisper") and not effects.trigger_event("vision"), "actual low-needs/injury simulation must accumulate stress without early hallucinations")
	room.player.set_torch_enabled(false)
	var dark_start := ExpeditionSession.stress
	room._process(10.0)
	_check(ExpeditionSession.stress - dark_start > lit_gain, "turning off the actual torch must add to the fixture's stress accumulation")
	room.run_feature("stress_audio")
	await _settle_camping_player()
	_check_station_label_in_view(room.get_node("StressInstructions") as Label3D, "stress instructions")
	_check(ExpeditionSession.stress == 65.0 and room.player.health == 100.0 and ExpeditionSession.active_conditions.is_empty() and room.player.torch_enabled, "audio comparison must prepare healthy, lit, reproducible stress 65")
	var healthy_stress := ExpeditionSession.stress
	room._process(10.0)
	_check(ExpeditionSession.stress == healthy_stress, "healthy and lit stress fixture must not accumulate passive stress")
	_check(is_equal_approx(room.hud.stress_bar.value, 65.0) and "동요" in room.hud.stress_label.text, "fixture must update the actual stress meter and stage label")
	effects.clear_effects()
	var count_before := effects.event_count
	effects.advance(2.01)
	_check(effects.event_count == count_before + 1 and effects.last_event in ["whisper", "footsteps"], "audio fixture must naturally schedule a production perception event after entry delay")
	_check(effects.audio_player.stream is AudioStreamWAV and (effects.audio_player.stream as AudioStreamWAV).data.size() > 1000 and effects.audio_player.playing, "natural hallucination must play actual PCM audio, not only a caption")
	_check(not effects.trigger_event("vision") and not is_instance_valid(effects.ghost), "stress 65 must not allow a visual hallucination")
	for kind in ["whisper", "footsteps"]:
		effects.clear_effects()
		_check(effects.trigger_event(kind) and effects.last_event == kind and effects.audio_player.playing, "the real perception pipeline must support " + kind)
	room._show_test_panel()
	_check_stress_silent(effects, "opening F2 menu")
	var paused_stress := ExpeditionSession.stress
	var paused_events := effects.event_count
	room._process(60.0)
	effects.advance(60.0)
	_check(ExpeditionSession.stress == paused_stress and effects.event_count == paused_events, "menu pause must freeze stress and produce no delayed audio or visions")
	room.run_feature("stress_vision")
	await _settle_camping_player()
	effects.rng.seed = 711
	var before_health: float = room.player.health
	var before_bag: Array = room.inventory.slots.duplicate(true)
	_check(effects.trigger_event("vision") and is_instance_valid(effects.ghost), "high-stress fixture must place a real visible peripheral apparition on the test-room floor")
	if is_instance_valid(effects.ghost):
		_check(bool(effects.ghost.get_meta("perception_only", false)) and effects.ghost.find_children("*", "CollisionObject3D", true, false).is_empty(), "apparition must be non-combat geometry with no collision bodies")
		_check(not effects.ghost.is_in_group("enemy") and not effects.ghost.has_method("take_damage"), "hallucinations must not enter actual enemy targeting or loot rules")
	_check(effects.trigger_event("whisper") and effects.audio_player.playing, "high stress must support actual audio together with a vision")
	_check(room.player.health == before_health and room.inventory.slots == before_bag and room.enemies_alive == 0, "perception must not damage the player, spend items or change real enemy counts")
	room._open_inventory()
	_check_stress_silent(effects, "opening real inventory")
	room._close_inventory()
	room._update_stress_presentation()
	_check(effects.trigger_event("vision"), "closing inventory must permit current high-stress perception again")
	room._recover_player()
	_check_stress_silent(effects, "recovering player")
	_check(ExpeditionSession.stress == 0.0 and room.hud.stress_bar.value == 0.0, "recovery must immediately clear both actual stress and HUD")
	room.run_feature("stress_vision")
	await _settle_camping_player()
	_check(bool(room.open_camp().get("accepted", false)), "stress fixture must allow actual camping at its prepared floor")
	_check_stress_silent(effects, "planning camp")
	_check(bool(room.camp.start_action("rest").get("accepted", false)), "a healthy but stressed player must be able to take a real recovery rest")
	room.camp.advance_rest(8.0)
	_check(is_equal_approx(ExpeditionSession.stress, 72.0) and room.inventory.count_item("camp_kit") == 1, "completed real rest must relieve exactly 18 stress and spend its real kit")
	room._show_test_panel()
	room.run_feature("stress_vision")
	await _settle_camping_player()
	room.open_camp()
	room.camp.start_action("rest")
	room.camp.advance_rest(3.0)
	room._show_test_panel()
	room.camp.advance_rest(8.0)
	_check(is_equal_approx(ExpeditionSession.stress, 90.0) and room.inventory.count_item("camp_kit") == 1, "interrupted stress recovery must grant no relief and refund no spent kit")
	room.run_feature("stress_vision")
	await _settle_camping_player()
	_check(effects.trigger_event("vision"), "repeated high-stress fixture must be immediately testable again")
	room.run_feature("movement")
	_check_stress_silent(effects, "switching to another fixture")
	room.run_feature("stress_vision")
	await _settle_camping_player()
	effects.trigger_event("vision")
	room._on_player_died()
	_check_stress_silent(effects, "direct test-room death callback")
	room.reset_room()
	_check_stress_silent(effects, "resetting the test room")
	_check(ExpeditionSession.stress == 0.0 and room.get_node_or_null("StressInstructions") == null, "reset must clear stress, old instructions and transient perception without touching the original backup")
	effects.set_process(true)
	room.player.set_physics_process(true)


func _install_stress_probe(scene: Node3D) -> StressPerception:
	var old_effects := scene.get("stress_effects") as Node
	if is_instance_valid(old_effects):
		scene.remove_child(old_effects)
		old_effects.queue_free()
	var effects := CapturedStressPerception.new()
	effects.setup(scene.get_node("Player") as DungeonPlayer)
	scene.add_child(effects)
	scene.set("stress_effects", effects)
	effects.set_process(false)
	return effects


func _check_stress_silent(effects: StressPerception, context: String) -> void:
	_check(not effects.active and not is_instance_valid(effects.ghost) and not effects.audio_player.playing and effects.audio_player.stream == null and not effects.vignette_layer.visible, context + " must immediately stop audio, remove visions and hide the vignette")


func _settle_camping_player() -> void:
	room.player.set_physics_process(true)
	for frame in range(60):
		await physics_frame
		if room.player.is_on_floor():
			break
	room.player.set_physics_process(false)
	_check(room.player.is_on_floor(), "camping fixture must settle onto the actual floor before installation")


func _check_station_label_in_view(label: Label3D, context: String) -> void:
	var bounds := label.get_aabb()
	_check(bounds.size.x > 0.0 and bounds.size.y > 0.0, context + " must expose laid-out text bounds")
	var viewport_rect: Rect2 = room.get_viewport().get_visible_rect().grow(-12.0)
	var camera := room.player.camera as Camera3D
	for x in [bounds.position.x, bounds.end.x]:
		for y in [bounds.position.y, bounds.end.y]:
			for z in [bounds.position.z, bounds.end.z]:
				var world_corner := label.to_global(Vector3(x, y, z))
				_check(not camera.is_position_behind(world_corner) and viewport_rect.has_point(camera.unproject_position(world_corner)), context + " must fit entirely inside the actual starting camera view")


func _test_chest_fixture() -> void:
	room.player.set_physics_process(false)
	var previous_chest: DungeonLootChest
	for weapon_id in ["rusted_sword", "hunting_bow", "chain_flail", "weathered_staff", ""]:
		room._show_test_panel()
		room._equip_weapon(weapon_id)
		var saved_equipment: Dictionary = room.inventory.equipment.duplicate(true)
		var saved_bag: Array = room.inventory.slots.duplicate(true)
		room.run_feature("chest")
		var chest := room.loot_chests[0] as DungeonLootChest
		_check(chest != previous_chest and chest.state == DungeonLootChest.ChestState.CLOSED and not chest.opened and not chest.container.ever_opened, "reselecting chest must prepare a new unopened actual container")
		previous_chest = chest
		_check(room.inventory.equipment == saved_equipment and room.inventory.slots == saved_bag, "chest fixture must retain the current weapon, including empty hands, without consuming bag capacity")
		_check(get_nodes_in_group("enemy").is_empty() and get_nodes_in_group("trap").is_empty(), "chest hand comparison must clear previous combat fixtures")
		var catalog_items: Dictionary = {}
		for supply_chest: DungeonLootChest in room.loot_chests:
			for stack: Dictionary in supply_chest.container.items:
				catalog_items[stack.id] = true
		for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
			_check(catalog_items.has(item_id), "repeatable chest fixture must keep automatic catalog supplies: " + item_id)
		await physics_frame
		await physics_frame
		_check(_aimed_interactable() == chest, "new chest fixture must aim the actual interaction ray at the lock")
		_check(is_equal_approx(Vector2(room.player.position.x - chest.position.x, room.player.position.z - chest.position.z).length(), 1.6), "chest comparison must begin 1.6 metres horizontally from its root")
		var visibility := _equipment_visibility()
		chest.interact(room.player)
		_check(chest.state == DungeonLootChest.ChestState.OPENING and room.player.is_timed_interacting() and not paused, "E interaction must begin real unpaused chest opening")
		_check(is_equal_approx(room.player.timed_interaction_duration, 1.2), "hands must use the existing 1.2-second production interaction")
		room.player.advance_timed_interaction(0.5)
		_check(room.player.chest_equipment_stowed and not room.player.weapon_pivot.visible and not room.player.shield_pivot.visible and not room.player.torch_pivot.visible, "opening a chest must hide equipment visuals without unequipping items")
		_check(is_instance_valid(room.player.chest_hands) and room.player.chest_hands.visible, "partial opening must display the actual bare-hand model")
		_check(room.player.chest_hands.phase == "fidget" and room.player.chest_hands.left_hand.visible and room.player.chest_hands.right_hand.visible, "both actual hands must manipulate the lock at the production interaction phase")
		_check(room.inventory.equipment == saved_equipment and room.inventory.slots == saved_bag and not chest.container.ever_opened, "partial hand interaction must not alter inventory or prematurely open loot")
		room.player.advance_timed_interaction(0.5)
		_check(room.player.chest_hands.phase == "lift" and absf(chest.lid_pivot.rotation.x) > 0.01 and not chest.opened, "hands and real chest lid must share the lift phase before completion")
		room.player.advance_timed_interaction(0.21)
		_check(chest.opened and chest.container.ever_opened and room.game_mode == room.GameMode.INVENTORY and room.inventory_overlay.is_open() and paused, "completed hand interaction must open the real paused searchable container")
		_check(not room.player.is_timed_interacting() and room.player.chest_equipment_stowed and not room.player.weapon_pivot.visible, "container browsing must keep weapons stowed after timed opening completes")
		_check(chest.container.identified_stack_count() == 0, "opening with hands must preserve the original concealed-search rule")
		room._close_inventory()
		_check(not room.player.chest_equipment_stowed and not room.player.chest_hands.visible and _equipment_visibility() == visibility, "closing the actual container must hide hands and restore the original equipment visuals")
		var remaining_units := chest.container.item_count()
		chest.interact(room.player)
		_check(not room.player.is_timed_interacting() and room.inventory_overlay.is_open() and chest.container.item_count() == remaining_units, "revisiting the same opened chest must still bypass the timer without duplicating its loot")
		room._close_inventory()
		_check(room.inventory.equipment == saved_equipment and room.inventory.slots == saved_bag, "hand opening and browsing must never consume or duplicate weapon items")
	room._show_test_panel()
	room._equip_weapon("hunting_bow")
	room.run_feature("chest")
	await physics_frame
	var cancel_chest := room.loot_chests[0] as DungeonLootChest
	cancel_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	room.player.cancel_timed_interaction("맨손 열기 취소 시험")
	_check(cancel_chest.state == DungeonLootChest.ChestState.CLOSED and not cancel_chest.opened and not room.player.chest_equipment_stowed and not room.player.chest_hands.visible, "cancelling must close the partial chest and restore equipment without changing loot")
	cancel_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	await _press_key(KEY_F2)
	_check(room.panel_open and paused and cancel_chest.state == DungeonLootChest.ChestState.CLOSED and not room.player.chest_equipment_stowed, "F2 must cancel both chest opening and hands before pausing the fixture")
	var cancelled_items := cancel_chest.container.item_count()
	await create_timer(0.05, true).timeout
	_check(not room.player.is_timed_interacting() and not room.player.chest_hands.visible and cancel_chest.container.item_count() == cancelled_items, "paused chest fixture must not complete opening or change supplies")
	room._hide_test_panel()
	cancel_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	room._recover_player()
	_check(cancel_chest.state == DungeonLootChest.ChestState.CLOSED and not room.player.chest_equipment_stowed and not room.player.chest_hands.visible, "recovery must cancel hand manipulation on both player and chest")
	cancel_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	room.run_feature("respawn")
	_check(not room.player.is_timed_interacting() and not room.player.chest_equipment_stowed and not room.player.chest_hands.visible and cancel_chest.is_queued_for_deletion(), "target regeneration must remove old opening chest and restore the player's hands and equipment")
	room.run_feature("chest")
	await physics_frame
	var final_chest := room.loot_chests[0] as DungeonLootChest
	final_chest.interact(room.player)
	room.player.advance_timed_interaction(1.2)
	await _press_key(KEY_F2)
	_check(room.panel_open and paused and not room.inventory_overlay.is_open() and not room.player.chest_equipment_stowed, "F2 from completed chest browsing must restore equipment and return to the real test menu")
	room.run_feature("chest")
	var death_chest := room.loot_chests[0] as DungeonLootChest
	death_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	room._on_player_died()
	_check(death_chest.state == DungeonLootChest.ChestState.CLOSED and not room.player.chest_equipment_stowed and not room.player.chest_hands.visible, "direct test-room death callback must cancel the chest and hide hand visuals")
	room.reset_room()
	_check(not room.player.chest_equipment_stowed and not room.player.chest_hands.visible, "room reset must not retain scene-local hand or stowed-equipment state")
	room.player.set_physics_process(true)


func _equipment_visibility() -> Dictionary:
	var result: Dictionary = {}
	for property in ["weapon_pivot", "sword_visual_root", "staff_visual_root", "bow_visual_root", "flail_visual_root", "shield_pivot", "torch_pivot"]:
		var visual := room.player.get(property) as Node3D
		result[property] = visual.visible
	return result


func _test_interaction_positions() -> void:
	room.reset_room()
	room.run_feature("chest")
	await physics_frame
	await physics_frame
	_check(_aimed_interactable() == room.loot_chests[0], "chest shortcut must immediately target the real chest")
	room._show_test_panel()
	room.run_feature("respawn")
	room.run_feature("traps")
	await physics_frame
	await physics_frame
	_check(_aimed_interactable() is RuneTrap, "trap shortcut must immediately target a real trap")
	room._show_test_panel()


func _aimed_interactable() -> Node:
	# Headless display cannot capture a cursor; verify the same interaction ray
	# directly so shortcut placement is tested on both display backends.
	var camera: Camera3D = room.player.camera
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 3.0, DungeonPlayer.INTERACT_LAYER)
	ray.collide_with_areas = true
	ray.collide_with_bodies = false
	var hit := room.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return null
	return hit.collider.get_meta("interaction_owner", null) as Node


func _test_scene_roundtrip() -> void:
	room.run_feature("cooking")
	await _settle_camping_player()
	ExpeditionSession.set_stress(65.0)
	room.open_camp()
	room.camp.start_action("cook:roast_meat")
	room.camp.advance_rest(2.0)
	var cooking_health: float = room.player.health
	var meat_after_cooking_start: int = room.inventory.count_item("raw_meat")
	room.run_feature("merchant")
	_check(room.camp.state == "closed" and room.player.health == cooking_health, "leaving for a connected scene must cancel ongoing cooking before it can grant food healing")
	await _wait_for_scene("res://merchant.tscn")
	_check(is_instance_valid(current_scene) and current_scene.scene_file_path == "res://merchant.tscn", "shop fixture must load the real merchant")
	_check(ExpeditionSession.get_inventory().count_item("raw_meat") == meat_after_cooking_start, "ingredient costs must remain spent across linked scenes after a cancelled recipe")
	# A normal scene transition must prevent a second F2 transition.
	var blocker := CanvasLayer.new()
	blocker.set_meta(&"sanctuary_loading_host", true)
	root.add_child(blocker)
	await _press_key(KEY_F2)
	_check(not is_instance_valid(sandbox.loading_screen), "global scene loading must block duplicate F2 return")
	blocker.queue_free()
	await process_frame
	sandbox.return_to_room()
	await _wait_for_scene("res://test_room.tscn")
	room = current_scene as Node3D
	_check(room != null and room.scene_file_path == "res://test_room.tscn", "F2 return must keep the isolated session alive")
	if room == null:
		return
	_check(sandbox.active and ExpeditionSession.crowns == 9999, "roundtrip must preserve sandbox funds")
	_check(ExpeditionSession.stress == 65.0, "merchant and room transitions must preserve the trial stress, not restore the original early")
	room.run_feature("dungeon")
	await _wait_for_scene("res://main.tscn")
	var dungeon := current_scene as Node3D
	var dungeon_player := dungeon.get_node("Player") as DungeonPlayer
	var dungeon_effects := _install_stress_probe(dungeon)
	ExpeditionSession.set_stress(90.0)
	dungeon._update_stress_presentation()
	_check(dungeon_effects.trigger_event("whisper"), "connected dungeon must use actual perception for the current trial stress")
	dungeon_player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	var trial_inventory := ExpeditionSession.get_inventory()
	trial_inventory.equipment["weapon"] = "chain_flail"
	trial_inventory.changed.emit()
	_check(bool(dungeon_player.begin_flail_spin().accepted), "connected real dungeon must permit the sandbox flail to begin spinning")
	dungeon_player._update_flail(1.2)
	_check(bool(dungeon_player.release_flail_throw().accepted) and get_nodes_in_group("flail_projectile").size() == 1, "linked dungeon return regression must start with an actual thrown head")
	sandbox.return_to_room()
	_check_stress_silent(dungeon_effects, "returning from a connected dungeon")
	_check(dungeon_player.flail_state == "ready", "sandbox return must cancel and recall the old scene's active flail immediately")
	await _wait_for_scene("res://test_room.tscn")
	room = current_scene as Node3D
	_check(room != null and get_nodes_in_group("flail_projectile").is_empty() and room.player.flail_state == "ready", "returning from the dungeon must not carry a projectile or active weapon action into the new test room")
	_check(ExpeditionSession.stress >= 90.0 and not room.stress_effects.active and not is_instance_valid(room.stress_effects.ghost) and not room.stress_effects.audio_player.playing, "trial stress must cross connected scenes while old sounds, visions and active timers do not")
	room.run_feature("dungeon")
	await _wait_for_scene("res://main.tscn")
	var camping_dungeon := current_scene as Node3D
	var camping_player := camping_dungeon.get_node("Player") as DungeonPlayer
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	for frame in range(60):
		await physics_frame
		if camping_player.is_on_floor():
			break
	camping_player.set_physics_process(false)
	camping_player.health = 35.0
	camping_player.stamina = 20.0
	_check(bool(camping_dungeon.open_camp().get("accepted", false)), "connected dungeon must open real camping at its safe entry floor")
	_check(bool(camping_dungeon.camp.start_action("rest").get("accepted", false)), "connected dungeon must start an actual resource-consuming rest")
	camping_dungeon.camp.advance_rest(3.0)
	var kits_after_start: int = ExpeditionSession.get_inventory().count_item("camp_kit")
	sandbox.return_to_room()
	_check(camping_dungeon.camp.state == "closed" and is_equal_approx(camping_player.health, 35.0), "sandbox scene return must cancel a pending rest immediately without awarding its completion healing")
	await _wait_for_scene("res://test_room.tscn")
	room = current_scene as Node3D
	_check(room.camp.state == "closed" and not room.player.camping and ExpeditionSession.get_inventory().count_item("camp_kit") == kits_after_start, "camping state and its visual must not cross scene return, while spent trial supplies remain spent")
	room.run_feature("chest")
	room.player.set_physics_process(false)
	await physics_frame
	var exit_chest := room.loot_chests[0] as DungeonLootChest
	exit_chest.interact(room.player)
	room.player.advance_timed_interaction(0.4)
	_check(room.player.chest_equipment_stowed and room.player.is_timed_interacting(), "exit restoration must begin with actual unfinished hand manipulation")
	room.leave_room()
	_check(not room.player.chest_equipment_stowed and not room.player.chest_hands.visible and exit_chest.state == DungeonLootChest.ChestState.CLOSED, "leaving the trial must immediately cancel hand manipulation before original session restoration")
	await _wait_for_scene("res://main_menu.tscn")
	await process_frame
	_check(not sandbox.active, "returning to main menu must end the sandbox")


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var loading := false
		for child in root.get_children():
			if bool(child.get_meta(&"sanctuary_loading_host", false)):
				loading = true
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			return
	_check(false, "scene transition timed out: " + path)


func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
