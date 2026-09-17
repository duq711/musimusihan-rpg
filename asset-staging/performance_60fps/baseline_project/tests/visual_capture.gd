extends SceneTree

# Reusable MovieWriter harness for visual regression captures.
# DARK_QA_VIEW accepts: enemy_front, enemy_side, enemy_close, enemy_attack,
# enemy_reference, chest, portal. DARK_QA_VARIANT accepts: warden, keeper, skeleton.

var game: Node3D


func _initialize() -> void:
	call_deferred("_setup_view")


func _setup_view() -> void:
	game = load("res://main.tscn").instantiate() as Node3D
	root.add_child(game)
	await process_frame
	await process_frame

	var player := game.get("player") as DungeonPlayer
	if player == null:
		push_error("Visual capture could not find DungeonPlayer")
		quit(1)
		return
	player.set_physics_process(false)
	for enemy in get_nodes_in_group("enemy"):
		(enemy as Node).set_physics_process(false)

	match OS.get_environment("DARK_QA_VIEW"):
		"chest":
			player.global_position = Vector3(4.0, 1.0, -7.65)
			player.rotation.y = 0.0
			var chests := get_nodes_in_group("loot_chest")
			if chests.size() > 1:
				(chests[1] as DungeonLootChest)._animate_open()
		"portal":
			player.global_position = Vector3(0.0, 1.0, -10.65)
			player.rotation.y = 0.0
			game.set("enemies_alive", 0)
			var portal_material := game.get("portal_material") as StandardMaterial3D
			if portal_material:
				portal_material.albedo_color = Color(0.12, 0.70, 0.62, 0.90)
				portal_material.emission = Color(0.06, 0.96, 0.78)
		"enemy_side", "enemy_close", "enemy_attack", "enemy_reference", "enemy_front", "enemy":
			_setup_enemy_view(player, OS.get_environment("DARK_QA_VIEW"))
		_:
			_setup_enemy_view(player, "enemy_front")


func _setup_enemy_view(player: DungeonPlayer, requested_view: String) -> void:
	var enemies := get_nodes_in_group("enemy")
	if enemies.is_empty():
		push_error("Visual capture could not find a DungeonEnemy")
		quit(1)
		return
	var requested_variant := OS.get_environment("DARK_QA_VARIANT")
	var selected := enemies[0] as DungeonEnemy
	for enemy_node in enemies:
		var enemy := enemy_node as DungeonEnemy
		var is_keeper := enemy.display_name.contains("굶주린")
		var wants_skeleton := requested_variant == "keeper" or requested_variant == "skeleton"
		var variant_matches := is_keeper if wants_skeleton else not is_keeper
		if variant_matches:
			selected = enemy
	for enemy_node in enemies:
		(enemy_node as DungeonEnemy).visible = enemy_node == selected

	selected.global_position = Vector3(0.0, 0.90, 1.9)
	selected.rotation = Vector3(0.0, PI, 0.0)
	var camera_offset := Vector3(0.0, 0.0, 3.4)
	player.camera.fov = 58.0
	match requested_view:
		"enemy_side":
			camera_offset = Vector3(3.0, 0.0, 0.0)
		"enemy_close":
			camera_offset = Vector3(0.0, 0.0, 2.25)
			player.camera.fov = 48.0
		"enemy_attack":
			camera_offset = Vector3(2.7, 0.0, 2.7)
			player.camera.fov = 56.0
			selected._set_state(DungeonEnemy.AIState.ACTIVE)
			selected._update_weapon_pose(1.0)
			selected._update_visual_pose(1.0)
		"enemy_reference":
			camera_offset = Vector3(0.0, 0.0, 3.8)
			player.camera.fov = 56.0
			selected._set_state(DungeonEnemy.AIState.ACTIVE)
			selected._update_weapon_pose(1.0)
			selected._update_visual_pose(1.0)

	player.global_position = selected.global_position + camera_offset
	player.look_at(Vector3(selected.global_position.x, player.global_position.y, selected.global_position.z), Vector3.UP)
	player.head.rotation.x = 0.0
