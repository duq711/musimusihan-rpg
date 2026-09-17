extends RefCounted
## Only scene entry that changes native input is replaced. Gameplay is inherited.

class Motion extends Node:
	var player: DungeonPlayer
	var elapsed := 0.0
	var last_attack_cycle := -1
	var starting_camera_rotation := Vector3.ZERO
	var distance_travelled := 0.0
	var last_position := Vector3.ZERO
	var attack_requests := 0
	func _ready() -> void:
		process_physics_priority = -100
		starting_camera_rotation = player.camera.rotation
		last_position = player.global_position
	func _physics_process(delta: float) -> void:
		elapsed += delta
		distance_travelled += player.global_position.distance_to(last_position)
		last_position = player.global_position
		# Local scripted steering, not Input events: actual production movement
		# still applies acceleration, gravity, move_and_slide, bob and contacts.
		player.velocity.x = sin(elapsed * PI) * 1.3
		player.camera.rotation = starting_camera_rotation + Vector3(0, sin(elapsed * 0.7) * 0.22, 0)
		var cycle := int(elapsed / 2.0)
		if not player.safe_zone_mode and cycle != last_attack_cycle:
			last_attack_cycle = cycle
			player.call("_try_begin_attack")
			player.attack_release_requested = true
			attack_requests += 1

class Dungeon extends "res://scripts/game.gd":
	func _ready() -> void:
		load("res://tests/performance_scene_factory.gd").prepare_game(self)
	func _notification(_what: int) -> void:
		pass
	func _on_player_died() -> void:
		set_meta("benchmark_player_died", true)
		game_mode = GameMode.DEAD


class Hideout extends "res://scripts/hideout.gd":
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		ExpeditionSession.ensure_journey()
		inventory = ExpeditionSession.get_inventory()
		_build_fonts()
		_build_materials()
		_build_world()
		_spawn_hud()
		_spawn_inventory_overlay()
		_spawn_player()
		_build_interface()
		get_tree().paused = false
		hideout_mode = HideoutMode.RUNNING
	func _notification(_what: int) -> void:
		pass


static func prepare_game(game: Node) -> void:
	game.inventory = ExpeditionSession.get_inventory()
	for method in ["_build_materials", "_build_environment", "_build_dungeon", "_spawn_hud", "_spawn_inventory_overlay", "_spawn_player", "_spawn_stress_effects", "_spawn_camp", "_spawn_encounters", "_spawn_loot_chests", "_build_extraction_gate"]:
		game.call(method)
	game.hud.update_objective(game.enemies_alive, game.loot_count, game.traps_disarmed)
	game.call("_refresh_survival_hud")
	game.set("_stress_warning_stage", StressProfile.stage_index(ExpeditionSession.stress))
	game.get_tree().paused = false
	game.game_mode = 0


static func create(scene_id: String) -> Node:
	match scene_id:
		"hideout": return Hideout.new()
		"dungeon": return Dungeon.new()
		"mine": return load("res://tests/performance_mine_scene.gd").new()
	return null


static func disable_event_delivery(node: Node) -> void:
	# The unhosted embedded display has no native input source. Disable Godot
	# event handlers too; actual polling sees only the untouched empty state.
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	if node is Control:
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		disable_event_delivery(child)
