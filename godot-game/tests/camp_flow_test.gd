extends SceneTree

const CAMP_TEST := preload("res://tests/camp_test_helpers.gd")

var failures: Array[String] = []
var game: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	game = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.set_process_unhandled_input(false)
	game.player.set_process_unhandled_input(false)
	for enemy in get_nodes_in_group("enemy"):
		enemy.set_physics_process(false)
	for frame in range(12):
		await physics_frame
	game.camp.set_process(false)
	var player := game.player as DungeonPlayer
	var bag := game.inventory as ExpeditionInventory
	_check(player.is_on_floor(), "real dungeon entrance must provide grounded camp placement")
	player.health = 35.0
	player.stamina = 20.0
	ExpeditionSession.hunger = 25.0
	ExpeditionSession.thirst = 25.0
	var slots_before := bag.slots.duplicate(true)
	var pitch_before := player._pitch
	_key(KEY_C)
	_check(game.camp.state == "closed" and not paused and bag.slots == slots_before, "C must no longer install or open a camp")
	_check(bool(CAMP_TEST.deploy_and_open(game.camp).accepted) and game.camp.is_open() and game.game_mode == game.GameMode.CAMPING and paused, "confirmed ground placement and tent entry must open the real paused camp")
	_check(player.camping and not player.weapon_pivot.visible and not player.torch_pivot.visible and not game.hud.crosshair.visible, "camping must stow the weapon and torch and hide aiming")
	_check(bag.count_item("camp_kit") == 0, "confirmed installation must already have spent exactly one kit")
	game.camp.overlay.action_buttons["rest"].pressed.emit()
	_check(game.camp.state == "resting" and not paused and game.game_mode == game.GameMode.CAMPING, "actual action button must resume the live dungeon for rest")
	_check(bag.count_item("camp_kit") == 0 and game.camp.warmth == 2, "first rest must spend one warmth while reusing the already paid kit")
	var position_before := player.position
	var stamina_before := player.stamina
	var hunger_before := ExpeditionSession.hunger
	player._physics_process(10.0)
	player._update_combat(10.0)
	player._update_movement(10.0)
	_check(player.position == position_before and is_equal_approx(player.stamina, stamina_before), "rest must prevent player movement and passive stamina regeneration")
	_check(not bool(player.begin_bow_draw().accepted) and not bool(player.begin_flail_spin().accepted) and not bool(player.cast_spell("healing_light").accepted), "rest must reject all weapon entry points")
	_check(not bool(player.use_consumable("healing_draught", bag).accepted), "camp must not allow parallel inventory consumption")
	game._process(2.0)
	_check(is_equal_approx(ExpeditionSession.hunger, hunger_before), "ordinary dungeon ticking must not double-count camp survival time")
	game.camp.advance_rest(2.0)
	_check(ExpeditionSession.hunger < hunger_before and is_equal_approx(player.health, 35.0), "rest progress must pass survival time without granting early healing")
	_key(KEY_I)
	_check(not game.camp.is_open() and not player.camping and game.game_mode == game.GameMode.INVENTORY and paused, "I during rest must close camp and open a paused inventory")
	_check(bag.count_item("camp_kit") == 0 and is_equal_approx(player.health, 35.0), "interruption must retain spent kit and award no completion healing")
	_check(player.weapon_pivot.visible and player.torch_pivot.visible and is_equal_approx(player._pitch, pitch_before), "leaving camp must restore weapon, torch and original camera pitch")
	_key(KEY_I)
	_check(game.game_mode == game.GameMode.RUNNING and not paused, "inventory close must resume ordinary exploration")
	_check(game.camp.state == "deployed" and is_instance_valid(game.camp.camp_visual), "inventory interruption must preserve the installed camp")
	game.cancel_camp("시험용 새 야영지", true)
	bag.add_item("camp_kit", 1)
	_check(bool(CAMP_TEST.deploy_and_open(game.camp).accepted), "a supplied camp must deploy after dismantling the previous camp")
	_check(bool(game.camp.start_action("rest").accepted), "fresh camp must accept rest")
	game.camp.advance_rest(8.0)
	_check(game.camp.state == "planning" and paused and is_equal_approx(player.health, 55.0) and is_equal_approx(player.stamina, 90.0), "completed rest must heal once and return to the paused camp plan")
	game.camp.advance_rest(100.0)
	_check(is_equal_approx(player.health, 55.0) and is_equal_approx(player.stamina, 90.0), "completed or paused action cannot grant duplicate rewards")
	_check(bool(game.camp.start_action("rest").accepted), "second rest can reuse the already-paid kit")
	var paid_slots := bag.slots.duplicate(true)
	game._pause_game()
	_check(not game.camp.is_open() and game.game_mode == game.GameMode.PAUSED and paused and bag.slots == paid_slots, "ordinary pause must cancel the action without spending or refunding again")
	game._resume_game()
	bag.add_item("camp_kit", 1)
	_check(bool(CAMP_TEST.deploy_and_open(game.camp).accepted), "post-pause camp must reopen normally")
	game.camp.start_action("rest")
	player.receive_environment_damage(5.0, "야영 중 피격 시험")
	_check(not game.camp.is_open() and not player.camping and not paused and is_equal_approx(player.health, 50.0), "actual damage must interrupt camping and apply damage without rest rewards")
	bag.add_item("camp_kit", 1)
	_check(bool(CAMP_TEST.deploy_and_open(game.camp).accepted), "post-hit camp must reopen when safe")
	game.camp.start_action("rest")
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(not game.camp.is_open() and game.game_mode == game.GameMode.PAUSED and paused, "lost window focus must safely pause an exposed resting player")
	game._resume_game()
	var enemy := get_nodes_in_group("enemy")[0] as DungeonEnemy
	var enemy_position := enemy.position
	enemy.position = player.position + Vector3(0, 0, -4)
	bag.add_item("camp_kit", 1)
	var unsafe_slots := bag.slots.duplicate(true)
	_check(not bool(CAMP_TEST.deploy_and_open(game.camp).accepted) and bag.slots == unsafe_slots, "nearby live enemies must reject placement without spending")
	enemy.position = enemy_position
	_check(bool(CAMP_TEST.deploy_and_open(game.camp).accepted), "safe camp must reopen after threat moves away")
	game.camp.start_action("rest")
	enemy.position = player.position + Vector3(0, 0, -5)
	game.camp.advance_rest(0.1)
	_check(not game.camp.is_open() and not player.camping and game.game_mode == game.GameMode.RUNNING, "a real enemy approaching during rest must interrupt and return control")
	game.cancel_camp("", false)
	game.queue_free()
	await process_frame
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ExpeditionSession.restore_snapshot(original)
	if failures.is_empty():
		print("CAMP FLOW TEST PASS: removed C shortcut, real placement/tent and action UI, paused plan/live rest, player locks, atomic costs, one survival clock, rewards, inventory/pause/focus/damage/approach cleanup")
		quit(0)
	else:
		for failure in failures:
			push_error("CAMP FLOW TEST FAIL: " + failure)
		quit(1)


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	game._unhandled_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
