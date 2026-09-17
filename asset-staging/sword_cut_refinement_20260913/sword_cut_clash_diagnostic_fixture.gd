extends SceneTree
const DATA := preload("res://scripts/reference_sword_motion.gd")
const GEOMETRY := preload("res://scripts/sword_clash_geometry.gd")
var output: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DATA.is_available()
	var current: Dictionary = DATA._clips
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/sword_cut_baseline_20260913.json"))
	var before: Dictionary = DATA._decode_manifest(raw)
	output["production_sha256"] = FileAccess.get_sha256(DATA.MANIFEST_PATH)
	output["samples"] = {}
	for version in ["current_fixed_lead", "current_natural_windup"]:
		DATA._clips = current
		var game: Node = load("res://main.tscn").instantiate()
		root.add_child(game)
		await process_frame
		await physics_frame
		await physics_frame
		game.set_process(false)
		game.set_physics_process(false)
		var player := get_first_node_in_group("player") as DungeonPlayer
		var enemy: DungeonEnemy = null
		for node in get_nodes_in_group("enemy"):
			node.set_physics_process(false)
			if node.sword_blade != null:
				enemy = node
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
		var floor_height := player.global_position.y
		player.global_position = Vector3(0, floor_height, 0)
		player.rotation = Vector3.ZERO
		player.head.rotation = Vector3.ZERO
		enemy.global_position = Vector3(.25, floor_height, -1.35 if version == "current_fixed_lead" else -1.1)
		enemy.rotation.y = PI if version == "current_fixed_lead" else atan2(enemy.global_position.x, enemy.global_position.z)
		player.velocity = Vector3.ZERO
		enemy.velocity = Vector3.ZERO
		player.cancel_sword_attack()
		player.stamina = player.MAX_STAMINA
		player.health = player.MAX_HEALTH
		var enemy_health := enemy.health
		enemy._set_state(DungeonEnemy.AIState.WINDUP)
		enemy._update_weapon_pose(1.0)
		enemy._update_visual_pose(1.0)
		if version == "current_natural_windup":
			for _frame in range(24):
				enemy._physics_process(1.0/60.0)
		var begun := player.begin_sword_attack("right_diagonal")
		player.attack_release_requested = true
		for _frame in range(30):
			player.advance_action_timers(1.0/60.0)
			player.advance_combat_state(1.0/60.0, false)
			player._update_viewmodel(1.0/60.0)
			if version == "current_natural_windup":
				enemy._physics_process(1.0/60.0)
			if player.combat_state != DungeonPlayer.CombatState.WINDUP:
				break
		if version == "current_fixed_lead":
			for _frame in range(3):
				player.advance_action_timers(1.0/60.0)
				player.advance_combat_state(1.0/60.0, false)
				player._update_viewmodel(1.0/60.0)
				player._resolve_active_attack()
			enemy._set_state(DungeonEnemy.AIState.ACTIVE)
		var frames: Array = []
		var tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
		var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
		for frame in range(12):
			player.advance_action_timers(1.0/60.0)
			player.advance_combat_state(1.0/60.0, false)
			player._update_viewmodel(1.0/60.0)
			enemy._physics_process(1.0/60.0)
			var a := player.get_sword_clash_proxy()
			var b := enemy.get_sword_clash_proxy()
			var record := {"frame": frame, "player_time": player.state_time, "enemy_time": enemy.state_time,
				"player_phase": player.combat_state, "enemy_phase": enemy.ai_state,
				"overlap": GEOMETRY.proxies_overlap(a,b,player.SWORD_CLASH_MARGIN),
				"player": _proxy(a), "enemy": _proxy(b), "tip": _array(tip.global_position), "grip": _array(grip.global_position),
				"camera": _array(player.camera.global_position)}
			player._resolve_active_attack()
			enemy._resolve_active_attack()
			record["player_health"] = player.health
			record["enemy_health"] = enemy.health
			record["player_phase_after"] = player.combat_state
			record["enemy_phase_after"] = enemy.ai_state
			frames.append(record)
			if player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER:
				break
		output.samples[version] = {"frames": frames, "begun": begun, "floor_height": floor_height, "enemy_name": enemy.display_name,
			"initial_enemy_health": enemy_health, "final_player_health": player.health, "final_enemy_health": enemy.health,
			"clashed": player.combat_state == DungeonPlayer.CombatState.RECOVERY and enemy.ai_state == DungeonEnemy.AIState.STAGGER}
		print("CLASH DIAGNOSTIC ", version, " ", output.samples[version].clashed, " player_health=", player.health, " enemy_health=", enemy.health)
		game.queue_free()
		await process_frame
	DATA._clips = current
	var path := ProjectSettings.globalize_path("res://").path_join("../asset-staging/sword_cut_refinement_20260913/clash_diagnostic_fixture_v3.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t",true,true))
	print("CLASH DIAGNOSTIC SAVED ",path)
	quit(0)

func _array(v: Vector3) -> Array:
	return [v.x,v.y,v.z]

func _proxy(p: Dictionary) -> Dictionary:
	return {"center":_array(p.center),"axes":[_array(p.axes[0]),_array(p.axes[1]),_array(p.axes[2])],"half_extents":_array(p.half_extents)}
