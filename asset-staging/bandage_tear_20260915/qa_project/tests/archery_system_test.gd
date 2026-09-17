extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "jump", "interact", "attack", "block"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	_test_input_draw_and_ammo()
	_test_failure_gates()
	_test_cancellation_and_weapon_transitions()
	await _test_runtime_pause_and_loot()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if failures.is_empty():
		print("ARCHERY SYSTEM TEST PASS: input, draw strength, ammo, stamina, cooldown, safe zone, interruption, weapon transitions, HUD, pause and dungeon loot")
		quit(0)
	else:
		for failure in failures:
			push_error("ARCHERY SYSTEM TEST FAIL: " + failure)
		quit(1)


func _fixture() -> Dictionary:
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	var world := Node3D.new()
	root.add_child(world)
	var hud := DungeonHUD.new()
	world.add_child(hud)
	var player := DungeonPlayer.new()
	player.setup(world, hud, inventory)
	world.add_child(player)
	player.set_physics_process(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return {"world": world, "player": player, "inventory": inventory, "hud": hud}


func _equip(inventory: ExpeditionInventory, item_id: String) -> bool:
	for index in range(inventory.slots.size()):
		if inventory.slots[index].id == item_id:
			return bool(inventory.equip_from_slot(index).get("accepted", false))
	return false


func _input(player: DungeonPlayer, action: String, pressed: bool) -> void:
	# Headless DisplayServer cannot capture a mouse. Exercise the same public
	# commands there; the rendered run also verifies the real input dispatcher.
	if DisplayServer.get_name() == "headless":
		if action == "attack" and pressed:
			player.begin_bow_draw()
		elif action == "attack" and not pressed:
			player.release_bow_shot()
		elif action == "block" and pressed:
			player.cancel_bow_draw()
		return
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	player._unhandled_input(event)


func _test_input_draw_and_ammo() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	var hud: DungeonHUD = fixture.hud
	_check(_equip(inventory, "hunting_bow"), "starter bow must equip through the actual inventory")
	_check(player.bow_visual_root.visible and not player.sword_visual_root.visible and not player.staff_visual_root.visible, "equipped bow must replace sword and staff visuals")
	_check(not player.shield_pivot.visible and hud.archery_panel.visible and not hud.magic_panel.visible, "two-handed bow must hide shield and show archery HUD")
	var count := player.get_arrow_count()
	_input(player, "attack", true)
	_check(player.bow_drawing and player.get_arrow_count() == count, "pressing attack must draw without spending ammo")
	player._update_combat(0.5)
	_check(is_equal_approx(player.get_bow_draw_ratio(), 0.5), "half a second must draw to 50 percent")
	_check(is_equal_approx(hud.bow_draw_bar.value, 50.0), "HUD must display draw amount")
	_input(player, "block", true)
	_check(not player.bow_drawing and not player.blocking and player.get_arrow_count() == count, "RMB must cancel without guarding or consuming an arrow")
	_input(player, "attack", false)
	_check(_projectiles(fixture.world).is_empty(), "releasing after cancel must not fire")
	_check(bool(player.begin_bow_draw().accepted), "draw can restart after cancellation")
	var quick := player.release_bow_shot()
	_check(bool(quick.accepted) and quick.projectile is ArrowProjectile, "quick release must spawn an actual arrow")
	_check(is_equal_approx(quick.projectile.damage, 18.0) and is_zero_approx(quick.projectile.speed) and quick.projectile.velocity.is_equal_approx(Vector3.DOWN), "an immediate release must retain base damage but drop down without forward launch speed")
	_check(player.get_arrow_count() == count - 1 and is_equal_approx(player.stamina, 89.0), "quick shot must spend one arrow with no extra stamina after the earlier 0.5-second draw cost")
	_check(hud.arrow_count_label.text.contains(str(count - 1)), "HUD must immediately reflect ammo consumption")
	_check(not bool(player.begin_bow_draw().accepted), "reload cooldown must prevent a second shot")
	player.bow_cooldown = 0.0
	player.stamina = 100.0
	_input(player, "attack", true)
	player._update_combat(2.0)
	_check(player.bow_drawing and is_equal_approx(player.get_bow_draw_ratio(), 1.0), "full draw must clamp at 100 percent and wait for release")
	_input(player, "attack", false)
	var arrows := _projectiles(fixture.world)
	_check(arrows.size() == 2, "LMB release must produce exactly one further projectile")
	if arrows.size() == 2:
		_check(is_equal_approx(arrows[1].damage, 46.0) and is_equal_approx(arrows[1].speed, 42.0), "full draw must increase damage and speed")
	_check(player.get_arrow_count() == count - 2 and is_equal_approx(player.stamina, 56.0), "holding a full draw for two seconds must spend 44 stamina and release only one arrow")
	_input(player, "attack", false)
	_check(_projectiles(fixture.world).size() == 2, "duplicate release must not fire twice")
	fixture.world.free()


func _test_failure_gates() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_check(str(player.begin_bow_draw().reason) == "bow_required", "carrying but not equipping a bow must reject drawing")
	_equip(inventory, "hunting_bow")
	player.configure_safe_zone(true)
	_check(str(player.begin_bow_draw().reason) == "safe_zone", "safe-zone combat must reject archery")
	player.configure_safe_zone(false)
	player.stamina = 0.0
	_check(str(player.begin_bow_draw().reason) == "not_enough_stamina", "zero stamina must reject drawing")
	player.stamina = 5.0
	var count := player.get_arrow_count()
	_check(bool(player.begin_bow_draw().accepted), "any positive stamina must allow drawing without a minimum flat cost")
	player._update_combat(1.0)
	var expensive := player.release_bow_shot()
	_check(not bool(expensive.accepted) and str(expensive.reason) == "not_drawing", "exhaustion must already release the bow once before a later mouse release")
	_check(player.get_arrow_count() == count - 1 and is_zero_approx(player.stamina) and not player.bow_drawing and _projectiles(fixture.world).size() == 1, "exhaustion must spend only available stamina and automatically release exactly one arrow")
	player.stamina = 100.0
	player.bow_cooldown = 0.0
	count = player.get_arrow_count()
	inventory.remove_item("wooden_arrow", count)
	_check(str(player.begin_bow_draw().reason) == "no_ammo", "empty ammunition must reject drawing")
	inventory.add_item("wooden_arrow", 1)
	player.begin_bow_draw()
	inventory.remove_item("wooden_arrow", 1)
	_check(not bool(player.release_bow_shot().accepted), "removing ammo mid-draw must reject release")
	_check(_projectiles(fixture.world).size() == 1 and is_equal_approx(player.stamina, 100.0), "rejected shots must create no additional arrows or stamina cost")
	inventory.add_item("wooden_arrow", 1)
	player.combat_state = DungeonPlayer.CombatState.GUARD_BREAK
	_check(str(player.begin_bow_draw().reason) == "busy", "staggered player must not draw")
	player.combat_state = DungeonPlayer.CombatState.DEAD
	_check(str(player.begin_bow_draw().reason) == "dead", "dead player must not draw")
	fixture.world.free()


func _test_cancellation_and_weapon_transitions() -> void:
	var fixture := _fixture()
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_equip(inventory, "hunting_bow")
	var count := player.get_arrow_count()
	player.begin_bow_draw()
	player.prepare_for_inventory()
	_check(not player.bow_drawing, "inventory preparation must cancel drawing")
	player.begin_bow_draw()
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not player.bow_drawing, "losing window focus must cancel a draw even when its release event is lost")
	player.begin_bow_draw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player._unhandled_input(InputEventMouseMotion.new())
	_check(not player.bow_drawing, "losing mouse capture must cancel drawing")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	player.begin_bow_draw()
	player.receive_environment_damage(1.0, "test")
	_check(not player.bow_drawing, "taking damage must cancel the draw")
	player.begin_bow_draw()
	player.configure_safe_zone(true)
	_check(not player.bow_drawing and not player.weapon_pivot.visible and not player.shield_pivot.visible, "entering a safe zone must cancel and hide weapons")
	player.configure_safe_zone(false)
	player.begin_bow_draw()
	_check(_equip(inventory, "rusted_sword"), "sword must remain available after equipping bow")
	_check(not player.bow_drawing and not player.bow_visual_root.visible and player.sword_visual_root.visible and player.shield_pivot.visible, "switching to sword must clear draw and restore sword/shield")
	_check(not fixture.hud.archery_panel.visible, "switching away must hide bow HUD")
	player._try_begin_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.WINDUP, "melee must still work after using bow")
	_equip(inventory, "hunting_bow")
	player._try_begin_attack()
	_check(player.combat_state == DungeonPlayer.CombatState.READY and not player.is_sword_attack_active(), "bow must never use sword hit/clash path")
	inventory.add_item("weathered_staff")
	player.begin_bow_draw()
	_equip(inventory, "weathered_staff")
	_check(not player.bow_drawing and player.staff_visual_root.visible and not fixture.hud.archery_panel.visible, "staff switch must cleanly cancel and replace bow")
	_check(player.get_arrow_count() == count and _projectiles(fixture.world).is_empty(), "all cancellation paths must preserve every arrow")
	fixture.world.free()


func _test_runtime_pause_and_loot() -> void:
	ExpeditionSession.begin_new_journey()
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	game.loot_spawn_seed = preload("res://tests/loot_test_helpers.gd").seed_with_items("reliquary", ["hunting_bow", "wooden_arrow"])
	root.add_child(game)
	await process_frame
	game.player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	var supply := preload("res://tests/loot_test_helpers.gd").chest_with_item(game, "hunting_bow")
	_check(is_instance_valid(supply), "a seeded visit containing archery supplies must create its real supply container")
	if not is_instance_valid(supply):
		game.free()
		return
	var entrance: LootContainer = supply.container
	var loot_ids: Array[String] = []
	for stack in entrance.items:
		loot_ids.append(str(stack.id))
	_check(loot_ids.has("hunting_bow") and loot_ids.has("wooden_arrow"), "an occupied dungeon supply site must provide bow and arrows")
	_equip(game.inventory, "hunting_bow")
	game.player.begin_bow_draw()
	game._pause_game()
	_check(not game.player.bow_drawing and not bool(game.player.begin_bow_draw().accepted), "normal game pause must cancel and reject a new draw")
	game._resume_game()
	game.player.begin_bow_draw()
	var shot: Dictionary = game.player.release_bow_shot()
	_check(bool(shot.accepted), "shooting must resume after closing pause")
	if bool(shot.accepted):
		var arrow := shot.projectile as ArrowProjectile
		game._pause_game()
		var position_before := arrow.global_position
		var lifetime_before := arrow.lifetime
		for _index in range(3):
			await physics_frame
		_check(arrow.global_position.is_equal_approx(position_before) and is_equal_approx(arrow.lifetime, lifetime_before), "projectiles must stop moving and aging in normal pause")
		game._resume_game()
	game.free()
	paused = false


func _projectiles(world: Node) -> Array[ArrowProjectile]:
	var result: Array[ArrowProjectile] = []
	for child in world.get_children():
		if child is ArrowProjectile:
			result.append(child)
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
