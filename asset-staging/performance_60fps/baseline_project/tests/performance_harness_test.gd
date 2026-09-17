extends SceneTree

const PREVIEW := preload("res://tests/performance_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var samples: Array[float] = [40, 1, 16, 8, 20]
	var stats := PREVIEW.SAMPLER.summarize_values(samples)
	check(stats.p50 == 16 and stats.p95 == 40 and stats.p99 == 40 and stats.mean == 17, "nearest-rank percentiles must retain slow frames rather than average FPS")
	check(samples == [40.0, 1.0, 16.0, 8.0, 20.0], "summary must not reorder source frame evidence")
	var bag := ExpeditionSession.get_inventory()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	PREVIEW.FACTORY.disable_event_delivery(root)
	for scene_id in ["hideout", "dungeon", "mine"]:
		var viewport := PREVIEW.create_viewport(Vector2i(1280, 720))
		root.add_child(viewport)
		var game := PREVIEW.FACTORY.create(scene_id)
		viewport.add_child(game)
		PREVIEW.FACTORY.disable_event_delivery(game)
		await physics_frame
		await physics_frame
		if scene_id == "mine":
			check(await PREVIEW.GEOMETRY_READY.await_geometry_ready(game.get("cave_geometry")), "mine must finish actual collision-grounded dressing before measurement")
		var player: DungeonPlayer = game.get("player")
		check(player.is_physics_processing() and game.is_processing(), "actual player physics and production scene process must remain active: " + scene_id)
		check(player.viewmodel_renderer.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "actual equipment rendering must remain included")
		check(PREVIEW.SAMPLER.collect_viewports(viewport).size() >= 2, "world and real equipment viewports must both be measured")
		var sampler := PREVIEW.SAMPLER.new()
		sampler.begin(PREVIEW.SAMPLER.collect_viewports(viewport))
		sampler.end()
		check(sampler.viewports.is_empty(), "stopping performance display must disable measurements and clear viewport references")
		check(_handlers_disabled(game), "native input event handlers must remain disabled")
		var elapsed := float(game.get("elapsed"))
		for frame in 5:
			await process_frame
		check(float(game.get("elapsed")) > elapsed, "production game elapsed must advance during performance test")
		if scene_id == "dungeon":
			var motion := PREVIEW.FACTORY.Motion.new()
			motion.player = player
			game.add_child(motion)
			for frame in 20:
				await physics_frame
			check(motion.distance_travelled > 0.01 and motion.attack_requests > 0, "scripted steering must actually move the production collider and invoke combat")
			check(player.combat_state != DungeonPlayer.CombatState.READY, "motion case must run the actual sword state machine")
			motion.free()
		check(mouse == Input.mouse_mode, "safe adapter must never change native cursor mode")
		viewport.free()
		await process_frame
	sandbox.finish()
	check(snapshot == ExpeditionSession.capture_snapshot() and bag == ExpeditionSession.get_inventory() and Input.mouse_mode == mouse and not sandbox.active, "performance trial must restore original expedition, inventory identity, sandbox and cursor")
	check(PREVIEW.FACTORY.create("unknown") == null, "unknown production scene must fail closed")
	if failures.is_empty():
		print("PERFORMANCE HARNESS PASS: real three-scene gameplay, player physics, equipment viewports, correct frame percentiles and isolated session/input")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _handlers_disabled(node: Node) -> bool:
	if node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input():
		return false
	for child in node.get_children():
		if not _handlers_disabled(child):
			return false
	return true


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
