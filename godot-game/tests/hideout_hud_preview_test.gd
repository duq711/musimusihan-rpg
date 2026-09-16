extends SceneTree
## The capture adapter must render production UI defaults without applying them.
const PREVIEW := preload("res://tests/hideout_hud_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var bag_hash := PREVIEW.RUIN_PREVIEW.inventory_fingerprint(original_bag)
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := PREVIEW.RUIN_PREVIEW.sandbox_snapshot(sandbox)
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var game := PREVIEW.create_scene()
	viewport.add_child(game)
	PREVIEW.stop_execution(game)
	PREVIEW.configure_shot(game)
	await process_frame
	var state := PREVIEW.inspect_hud(game)
	for failure in state.failures:
		failures.append(str(failure))
	check(not state.harness_changes_hud_presentation and state.hud_layer_visible, "Capture must preserve the actual visible HUD layer and only inspect its production defaults.")
	check(viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d and not viewport.audio_listener_enable_2d, "Isolated viewport must disable external input, picking and audio listeners.")
	check(PREVIEW.execution_stopped(game), "Every scene node must stop gameplay and external input handlers before capture.")
	check(game.name == "SanctuaryHideout" and game.anchor_right == 1.0 and game.anchor_bottom == 1.0, "Safe scene adapter must retain the actual packed hideout scene and full-screen layout.")
	var player: DungeonPlayer = game.get("player")
	check(player.safe_zone_mode and player.torch.is_visible_in_tree() and player.torch_fill.is_visible_in_tree(), "Capture must retain the real safe-zone player and both handheld torch lights.")
	check(player.camera.global_position.distance_to(Vector3(0.0, 1.7, 8.4)) < 0.001, "Capture camera must use the shared central hall view.")
	check(Input.mouse_mode == mouse_before, "Scene construction and pose preparation must not change the OS cursor mode.")
	viewport.free()
	await process_frame
	sandbox.finish()
	var restored := ExpeditionSession.capture_snapshot()
	check(restored == original and restored.inventory == original_bag and PREVIEW.RUIN_PREVIEW.inventory_fingerprint(original_bag) == bag_hash, "Capture trial must restore original journey and inventory identity/content.")
	check(PREVIEW.RUIN_PREVIEW.sandbox_snapshot(sandbox) == sandbox_before and Input.mouse_mode == mouse_before, "Capture trial must preserve the sandbox and cursor.")
	for failure in failures:
		push_error(failure)
	print("HIDEOUT HUD PREVIEW TEST %s: real packed-scene UI defaults, safe renderer adapter and session restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
