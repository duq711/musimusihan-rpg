extends SceneTree
## Actual restored mine encounter; native input and automatic gameplay stay off.

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() != "embedded":
		quit(2)
		return
	var tag := OS.get_environment("CAVE_STORE_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):
		quit(2)
		return
	var path := ProjectSettings.globalize_path("res://artifacts/visual_qa/cave_store/" + tag)
	if DirAccess.dir_exists_absolute(path):
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(path)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var before := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var view := SubViewport.new()
	view.size = Vector2i(1280, 720)
	view.own_world_3d = true
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var mine: Node = load("res://tests/performance_scene_factory.gd").create("mine")
	view.add_child(mine)
	load("res://tests/item_detail_preview.gd").stop_external_execution(mine)
	var enemy: DungeonEnemy
	for actor in mine.get_children():
		if actor is DungeonEnemy and actor.display_name == "동쪽 창고의 검지기":
			enemy = actor
	assert(enemy != null and enemy.get_script() == load("res://scripts/enemy.gd"))
	assert(mine.enemies_alive == 6)
	var eye := enemy.global_position + Vector3(0, 0.7, -3.4)
	load("res://tests/performance_preview.gd").position_player(mine, {"position": eye, "target": enemy.global_position + Vector3(0, 0.65, 0)}, true)
	enemy._face_direction((mine.player.global_position - enemy.global_position).normalized(), 1)
	enemy._set_state(DungeonEnemy.AIState.IDLE)
	enemy._update_visual_pose(0.5)
	enemy._update_weapon_pose(0.5)
	mine._update_chamber_hud()
	for i in 30:
		mine.player._update_viewmodel(1.0 / 60.0)
		mine.player._update_torch(1.0 / 60.0)
		await process_frame
	mine.player.viewmodel_renderer.sync_view()
	for i in 8:
		await process_frame
	RenderingServer.force_draw(false)
	assert(view.get_texture().get_image().save_png(path.path_join("restored_store_warden.png")) == OK)
	var actor_name := enemy.display_name
	mine.suspend_stress_effects()
	view.queue_free()
	await process_frame
	sandbox.finish()
	assert(before == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode)
	var file := FileAccess.open(path.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(), "actor": actor_name, "enemy_count": 6, "preserved_session_cursor": true}, "\t"))
	print("CAVE STORE ENEMY PREVIEW PASS: ", path)
	quit()
