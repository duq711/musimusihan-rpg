extends SceneTree

var failures: Array[String] = []

class QuietDungeon:
	extends "res://scripts/game.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _on_inventory_closed() -> void:
		game_mode = GameMode.RUNNING
		get_tree().paused = false

class QuietHideout:
	extends "res://scripts/hideout.gd"
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func _on_inventory_closed() -> void:
		hideout_mode = HideoutMode.RUNNING
		get_tree().paused = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	ExpeditionSession.begin_new_journey()
	await _host_treatment(false)
	ExpeditionSession.begin_new_journey()
	await _host_treatment(true)
	ExpeditionSession.begin_new_journey()
	await _attack_regions()
	ExpeditionSession.restore_snapshot(original)
	_check(ExpeditionSession.capture_snapshot() == original, "route checks must restore original body state, conditions and bag identity")
	_check(Input.mouse_mode == mouse_before, "route checks must not manipulate OS mouse mode")
	for failure in failures:
		push_error(failure)
	print("BODY HEALTH ROUTES TEST %s: production dungeon/hideout health actions, exact selected part, ordinary recovery barrier, approach-based melee and trap leg damage" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _host_treatment(safe: bool) -> void:
	var host: Node = QuietHideout.new() if safe else QuietDungeon.new()
	root.add_child(host)
	host.inventory = ExpeditionSession.get_inventory()
	host.inventory.add_item("surgery_kit", 1)
	host.inventory.add_item("splint", 1)
	if not safe:
		host._spawn_hud()
	host.player = DungeonPlayer.new()
	host.player.setup(host, null, host.inventory)
	host.add_child(host.player)
	host.player.set_physics_process(false)
	host.player.set_process_unhandled_input(false)
	host.player.configure_safe_zone(safe)
	host._spawn_inventory_overlay()
	if safe:
		host.hideout_mode = host.HideoutMode.INVENTORY
	else:
		host.game_mode = host.GameMode.INVENTORY
	var overlay: InventoryOverlay = host.inventory_overlay
	overlay.open_inventory(host.inventory, Callable(host.player, "get_inventory_status_snapshot"))
	overlay.open_health_tab()
	host.player.apply_body_damage("left_arm", 60.0)
	host.player.apply_body_damage("right_arm", 20.0)
	host.player.apply_condition("fracture", 300.0, "left_arm")
	overlay.treatment_part_selected.emit("left_arm")
	_check(str(host.player.get_body_health_snapshot().selected_part) == "left_arm", "health selection must reach the real %s host player" % ("hideout" if safe else "dungeon"))
	var before: int = host.inventory.count_item("healing_draught")
	_timed_treatment(host, safe, "healing_draught")
	_check(host.inventory.count_item("healing_draught") == before and _part(host.player, "left_arm") == 0.0 and _part(host.player, "right_arm") == 40.0, "ordinary treatment on a selected destroyed arm must preserve item and other arm")
	_timed_treatment(host, safe, "surgery_kit")
	_check(_part(host.player, "left_arm") == 1.0 and host.inventory.count_item("surgery_kit") == 0, "actual surgery signal must spend one kit and restore exactly one point")
	_check(ExpeditionSession.has_condition("fracture"), "surgery must not also cure a fracture")
	_timed_treatment(host, safe, "healing_draught")
	_check(_part(host.player, "left_arm") == 33.0 and _part(host.player, "right_arm") == 40.0, "ordinary healing after surgery must target the selected arm only")
	_timed_treatment(host, safe, "splint")
	_check(not ExpeditionSession.has_condition("fracture"), "actual splint signal must clear the selected fracture")
	host.player.apply_body_damage("left_leg", 65.0)
	host.player.restore_health(440.0)
	_check(_part(host.player, "left_leg") == 0.0, "generic rest/food/life-on-hit recovery must retain destroyed limbs even with surplus healing")
	var snapshot := ExpeditionSession.body_health.duplicate(true)
	var next_player := DungeonPlayer.new()
	next_player.setup(host, null, host.inventory)
	_check(ExpeditionSession.body_health == snapshot and _part(next_player, "left_leg") == 0.0, "creating a new scene actor must retain the injured journey body")
	next_player.free()
	host.free()
	await process_frame


func _attack_regions() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := DungeonPlayer.new()
	player.setup(world, null, ExpeditionSession.get_inventory())
	world.add_child(player)
	player.set_physics_process(false)
	var enemy := DungeonEnemy.new()
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.target = player
	for entry in [[Vector3(0, 0, -1), "thorax"], [Vector3(1, 0, 0), "right_arm"], [Vector3(-1, 0, 0), "left_arm"], [Vector3(0, 0, 1), "stomach"], [Vector3(0, 1, -1), "head"]]:
		enemy.position = entry[0]
		_check(enemy._target_body_part() == str(entry[1]), "actual enemy damage region must follow relative attack direction: " + str(entry[1]))
	player.receive_attack(10.0, Vector3(1, 0, 0), "bleeding", "right_arm")
	_check(_part(player, "right_arm") == 50.0 and _part(player, "thorax") == 85.0, "received melee hit must remove health only from its passed body region")
	player.receive_environment_damage(12.0, "route test trap", "paralysis", "left_leg")
	_check(_part(player, "left_leg") == 53.0 and ExpeditionSession.has_condition("paralysis"), "trap damage must affect leg and apply its authored condition")
	world.free()
	await process_frame


func _part(player: DungeonPlayer, id: String) -> float:
	return float(player.get_body_health_snapshot().parts[id].health)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func _timed_treatment(host: Node, safe: bool, id: String) -> void:
	host.inventory_overlay.consumable_requested.emit(id)
	if not host.player.is_item_use_active(): return
	_check(not host.inventory_overlay.is_open(), "Accepted treatment closes inventory for timed use")
	host.player.advance_item_use(30)
	if safe: host.hideout_mode = host.HideoutMode.INVENTORY
	else: host.game_mode = host.GameMode.INVENTORY
	host.inventory_overlay.open_inventory(host.inventory, Callable(host.player, "get_inventory_status_snapshot"))
	host.inventory_overlay.open_health_tab()
