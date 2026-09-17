extends SceneTree

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	bag.add_item("wooden_arrow", 7)
	ExpeditionSession.crowns = 73
	ExpeditionSession.hunger = 42
	var snapshot := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load("res://test_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	await process_frame
	room.run_feature("performance")
	await process_frame
	check(not paused and not room.panel_open, "performance entry must resume real gameplay")
	check(is_instance_valid(sandbox.performance_overlay) and sandbox.performance_overlay.enabled, "catalog action must enable the real session-owned monitor")
	check(room.player.is_physics_processing(), "monitor must keep actual player simulation active")
	check(sandbox.performance_overlay.sampler.samples.is_empty(), "dummy headless renderer must not produce fake FPS samples")
	check(sandbox.performance_overlay.label.text.contains("FPS를 측정하지"), "headless UI must explain that rendering measurements are unavailable")
	var overlay: CanvasLayer = sandbox.performance_overlay
	room._show_test_panel()
	await process_frame
	check(paused and overlay.label.text.contains("대기"), "paused test menu must not inflate performance results")
	room.run_feature("performance")
	check(not overlay.enabled and not overlay.visible, "reselecting performance must turn off the actual overlay")
	room._show_test_panel()
	room.run_feature("performance")
	room.queue_free()
	await process_frame
	var linked := Node3D.new()
	root.add_child(linked)
	current_scene = linked
	await process_frame
	check(is_instance_valid(overlay) and overlay.enabled and overlay.get_parent() == sandbox, "performance monitor must survive linked trial scene changes")
	sandbox.reset_loadout()
	check(not overlay.enabled, "reset must clear temporary performance UI")
	sandbox.toggle_performance_monitor()
	sandbox.finish()
	await process_frame
	check(not is_instance_valid(sandbox.performance_overlay), "ending test session must free viewport measurement UI")
	check(ExpeditionSession.get_inventory() == bag and ExpeditionSession.capture_snapshot() == snapshot, "monitor trial must restore original inventory identity and complete expedition state")
	linked.queue_free()
	paused = false
	await process_frame
	if failures.is_empty():
		print("PERFORMANCE UI PASS: executable catalog, real resumed simulation, pause exclusion, toggle, linked scenes, reset and original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
