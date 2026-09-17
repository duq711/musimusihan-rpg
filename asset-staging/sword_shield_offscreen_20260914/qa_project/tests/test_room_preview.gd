extends SceneTree

var room: Node3D


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	room = (load("res://test_room.tscn") as PackedScene).instantiate()
	viewport.add_child(room)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual_qa"))
	await _capture(viewport, "test_room_menu.png")
	room._hide_test_panel()
	room.player.set_physics_process(false)
	await _capture(viewport, "test_room_world.png")
	room._show_test_panel()
	room._select_category("물품")
	await _capture(viewport, "test_room_items.png")
	room.queue_free()
	await process_frame
	root.get_node("TestRoomSandbox").finish()
	paused = false
	print("TEST ROOM PREVIEW PASS")
	quit(0)


func _capture(viewport: SubViewport, file_name: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	var result := viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/visual_qa/" + file_name))
	if result != OK:
		push_error("Could not save preview: " + file_name)
		quit(1)
