extends SceneTree

const LAYOUT := preload("res://scripts/cave_layout.gd")

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var packed := load("res://cave_dungeon.tscn") as PackedScene
	_check(packed != null, "the cave must load as a real playable PackedScene")
	if packed == null:
		_finish()
		return
	var cave = packed.instantiate()
	root.add_child(cave)
	current_scene = cave
	cave.set_process(false)
	var player := cave.player as DungeonPlayer
	var enemies := get_nodes_in_group("enemy")
	var traps := get_nodes_in_group("trap")
	for actor in enemies:
		actor.set_process(false)
		actor.set_physics_process(false)
	_check(is_instance_valid(player), "the cave must create the existing playable combat controller")
	if not is_instance_valid(player):
		cave.free()
		_finish()
		return
	player.set_physics_process(false)
	_check(player.position.is_equal_approx(LAYOUT.spawn_position()), "the cave must spawn at its authored southern entry")
	for _frame in range(30):
		await physics_frame
		await process_frame
		player._physics_process(1.0 / 60.0)
		if player.is_on_floor():
			break
	_check(player.is_on_floor() and player.position.y > 0.8, "the real player must stand on collision floor without falling through")
	var info: Dictionary = cave.get_dungeon_info()
	_check(is_equal_approx(float(info.width_m), 131.0) and is_equal_approx(float(info.depth_m), 139.0), "the cave footprint must be exactly 131 by 139 metres")
	_check(info.chambers == 18 and enemies.size() == 6 and cave.enemies_alive == 6, "eighteen reference-traced chambers must contain six live encounters")
	_check(traps.size() == 4 and preload("res://tests/loot_test_helpers.gd").valid_count(cave), "four real traps and the visit's selected loot sites must be spawned")
	_check(enemies.filter(func(actor): return actor.display_name == "동쪽 창고의 검지기" and actor.get_script() == preload("res://scripts/enemy.gd")).size() == 1, "eastern store encounter must use the restored warden")
	var has_poison_source := false
	var has_paralysis_source := false
	for actor: DungeonEnemy in enemies:
		has_poison_source = has_poison_source or actor.inflicted_condition == "poison"
	for trap: RuneTrap in traps:
		has_paralysis_source = has_paralysis_source or trap.inflicted_condition == "paralysis"
	_check(has_poison_source and has_paralysis_source, "the real cave must expose a poison enemy and paralysis trap through the authored encounter paths")
	_check(cave.restart_scene_path() == "res://cave_dungeon.tscn", "retry must target the cave")
	_check(cave.get_node_or_null("CaveGeometry") != null, "the gameplay scene must use the authoritative cave geometry")
	var world_environment := cave.get_node("WorldEnvironment") as WorldEnvironment
	_test_environment(world_environment.environment, player)
	_check(_count_directional_lights(cave) == 0, "an underground cave must not receive directional sunlight")
	for room: Dictionary in LAYOUT.rooms():
		var center := LAYOUT.room_position(str(room.id))
		_check(cave.chamber_title_at(center) == str(room.title), "location HUD must identify actual chamber: " + str(room.id))
		var floor_hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3(0, 1.9, 0), center - Vector3(0, 1, 0), 2))
		_check(not floor_hit.is_empty(), "every chamber center must have real collision ground: " + str(room.id))
	for actor: DungeonEnemy in enemies:
		_check(actor.target == player and actor.game == cave and actor.hud == cave.hud, "each enemy must be connected to real combat and rewards")
		_check(_has_actor_clearance(actor.global_position, player), "enemy spawn must not overlap cave walls or solid props: " + actor.display_name)
		var ground_hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(actor.global_position, actor.global_position - Vector3(0, 2, 0), 2))
		_check(not ground_hit.is_empty(), "enemy encounter must have a floor: " + actor.display_name)
	for chest: DungeonLootChest in cave.loot_chests:
		_check(not chest.opened and not chest.container.items.is_empty(), "each chamber chest must start closed with actual concealed loot")
		for stack: Dictionary in chest.container.items:
			_check(not ExpeditionInventory.get_item_definition(str(stack.id)).is_empty() and not bool(stack.identified), "cave chest contents must use real catalog items and remain concealed")
	var gate := cave.get_node("ExtractionArea") as Area3D
	_check(gate.position.is_equal_approx(LAYOUT.extraction_position() + Vector3(0, 1.8, 0)), "the actual extraction trigger must move with the cave's northern exit")
	_check(cave.portal_visual.position.is_equal_approx(LAYOUT.extraction_position() + Vector3(0, 2.42, -0.35)), "the rendered portal must accompany the northeastern shrine extraction trigger")
	if traps.size() > 0:
		_test_trap(cave, player, traps[0] as RuneTrap)
	if not cave.loot_chests.is_empty():
		_test_chest(cave, player, cave.loot_chests[0] as DungeonLootChest)
	_test_extraction(cave, player, enemies)
	paused = false
	cave.suspend_stress_effects()
	cave.free()
	await process_frame
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_finish()


func _test_environment(environment: Environment, player: DungeonPlayer) -> void:
	var production: Environment = load("res://scripts/cave_art_direction.gd").make_environment()
	for property in ["background_mode", "background_color", "ambient_light_source", "ambient_light_color", "ambient_light_energy", "reflected_light_source", "fog_enabled", "fog_light_color", "fog_density", "volumetric_fog_enabled", "volumetric_fog_density", "tonemap_mode", "tonemap_exposure"]:
		_check(environment.get(property) == production.get(property), "playable cave atmosphere must match the shared production profile: " + property)
	var background := environment.background_color
	_check(environment.background_mode == Environment.BG_COLOR and maxf(background.r, maxf(background.g, background.b)) < 0.05, "the underground background must remain near black instead of a daylight sky")
	_check(environment.fog_enabled and environment.fog_density > 0.0, "actual mist must separate the dark passages")
	_check(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and environment.ambient_light_energy > 0.0 and environment.ambient_light_color.b > environment.ambient_light_color.r, "dark photographic rock needs the shared cool ambient light for readable surfaces")
	# Ambient energy alone is not a rendered brightness measurement: the
	# new dark rock maps need more fill than the old pale limestone. Actual
	# readability/contrast is checked in native art_direction_preview pixels.
	_check(player.torch.light_color.r > player.torch.light_color.b and player.torch_fill.light_color.r > player.torch_fill.light_color.b, "the carried fire must contrast with the cool cave ambience")
	_check(player.torch.spot_range > 0.0 and player.torch.spot_range < minf(LAYOUT.WIDTH, LAYOUT.DEPTH) * 0.25 and player.torch_fill.omni_range > 0.0 and player.torch_fill.omni_range < player.torch.spot_range, "carried light must illuminate a local pool rather than fill the whole mine")
	_check(player.torch.spot_attenuation > 0.0 and player.torch_fill.omni_attenuation > 0.0, "local torch light must fall off with distance")
	var enabled := player.torch_enabled
	var ambient := environment.ambient_light_energy
	var base := float(player.torch.get_meta("base_energy", 0.0))
	player.set_torch_enabled(false)
	_check(not player.torch.visible and not player.torch_fill.visible and environment.ambient_light_energy == ambient, "switching off the real torch must remove its local lighting and preserve the cave atmosphere")
	player.set_torch_enabled(true)
	player._update_torch(0.25)
	_check(base > 0.0 and player.torch.visible and player.torch_fill.visible and absf(player.torch.light_energy - base) < base * 0.15, "relighting the cave torch must retain the production flicker profile")
	player.set_torch_enabled(enabled)


func _test_trap(cave: Node3D, player: DungeonPlayer, trap: RuneTrap) -> void:
	player.position = trap.position + Vector3(0, 1, 1.5)
	player.velocity = Vector3.ZERO
	trap.interact(player)
	_check(trap.state == RuneTrap.TrapState.INSPECTING and player.is_timed_interacting(), "cave trap must use the real timed inspection")
	player.advance_timed_interaction(RuneTrap.INSPECT_DURATION + 0.1)
	_check(trap.state == RuneTrap.TrapState.DISARMING, "cave trap inspection must enter its actual minigame")
	trap.needle_value = (trap.success_start + trap.success_end) * 0.5
	trap.confirm_disarm()
	_check(trap.state == RuneTrap.TrapState.DISARMED and cave.traps_disarmed == 1, "a successful cave trap must update the real expedition counter")
	player.trap_lockout = 0.0


func _test_chest(cave: Node3D, player: DungeonPlayer, chest: DungeonLootChest) -> void:
	player.position = chest.position + Vector3(0, 1, 1.8)
	player.velocity = Vector3.ZERO
	chest.interact(player)
	_check(chest.state == DungeonLootChest.ChestState.OPENING, "cave chest must begin the actual timed opening")
	player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION + 0.1)
	_check(chest.opened and cave.inventory_overlay.is_open() and paused, "completed cave chest opening must show its real paused inventory UI")
	_check(cave.active_loot_chest == chest, "cave inventory must read the actual authored chest container")
	cave._close_inventory()
	_check(not paused and cave.game_mode == cave.GameMode.RUNNING, "closing a cave chest must restore live gameplay")


func _test_extraction(cave: Node3D, player: DungeonPlayer, enemies: Array[Node]) -> void:
	cave._on_extraction_body_entered(player)
	_check(cave.game_mode == cave.GameMode.RUNNING and not paused, "extraction must stay sealed while cave enemies are alive")
	for actor: DungeonEnemy in enemies:
		actor.receive_hit(999.0, player.global_position, 1.0, true)
	_check(cave.enemies_alive == 0, "actual enemy deaths must remove all six cave seals")
	_check(cave.portal_material.emission.g > cave.portal_material.emission.r, "last real enemy death must visibly unlock the portal")
	cave._on_extraction_body_entered(player)
	_check(cave.game_mode == cave.GameMode.WON and paused, "the unlocked cave exit must enter the inherited expedition result state")
	_check(cave.hud.overlay_detail.text.contains("검은 물길 동굴"), "extraction results must name the new cave")


func _has_actor_clearance(position: Vector3, player: DungeonPlayer) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.43
	shape.height = 1.78
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position)
	query.collision_mask = 2
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _count_directional_lights(node: Node) -> int:
	var count := 1 if node is DirectionalLight3D else 0
	for child in node.get_children():
		count += _count_directional_lights(child)
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("CAVE DUNGEON TEST PASS: 131 × 139 m scene, grounded player / encounters, dark cave environment, real trap and chest actions, six-kill extraction and cave retry contract")
		quit(0)
		return
	for failure in failures:
		push_error("CAVE DUNGEON TEST FAIL: " + failure)
	quit(1)
