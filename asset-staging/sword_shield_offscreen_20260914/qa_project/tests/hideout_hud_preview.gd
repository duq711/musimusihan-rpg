extends SceneTree
## Actual hideout.tscn with its production HUD and carried torch. Reuses the
## reviewed scene-entry adapter; no native window, input, focus or mouse change.
## This harness never changes a HUD node's visibility, text, font or geometry.
const SCENE := preload("res://hideout.tscn")
const PERFORMANCE := preload("res://tests/performance_preview.gd")
const FACTORY := preload("res://tests/performance_scene_factory.gd")
const RUIN_PREVIEW := preload("res://tests/hideout_ruin_preview.gd")
const VIEWS := preload("res://scripts/hideout_ruin_views.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/hideout_hud"
const HIDDEN_HUD_NODES := ["LocationCard", "SurvivalCard", "LivingGuide", "ControlLegend"]


func _init() -> void:
	call_deferred("_run")


static func create_viewport() -> SubViewport:
	var viewport := PERFORMANCE.create_viewport(IMAGE_SIZE)
	viewport.name = "IsolatedProductionHideoutHUD"
	return viewport


static func create_scene() -> Control:
	# Preserve the packed scene's real layout. The reviewed adapter replaces
	# only scene entry / native-window notifications, retaining all production
	# world, HUD, player and destination interface construction methods.
	var game := SCENE.instantiate() as Control
	game.set_script(FACTORY.Hideout)
	return game


static func stop_execution(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	FACTORY.disable_event_delivery(node)
	for child in node.get_children():
		stop_execution(child)


static func configure_shot(game: Control) -> void:
	var shot := VIEWS.get_shot("central")
	PERFORMANCE.position_player(game, shot, true)
	var player: DungeonPlayer = game.get("player")
	player.camera.fov = float(shot.fov)
	player.camera.current = true
	# Settle the actual safe-zone torch pose without hardware input or moving
	# the physics body. All equipment meshes and both torch lights are retained.
	for frame in 60:
		player.call("_update_viewmodel", 1.0 / 60.0)
		player.call("_update_torch", 1.0 / 60.0)
	player.viewmodel_renderer.sync_view()


static func inspect_hud(game: Control) -> Dictionary:
	var hud: DungeonHUD = game.get("hideout_hud")
	var hidden := {}
	var failures: Array[String] = []
	for node_name in HIDDEN_HUD_NODES:
		var node := hud.find_child(node_name, true, false) as Control
		var is_hidden := is_instance_valid(node) and not node.is_visible_in_tree()
		hidden[node_name] = is_hidden
		if not is_hidden:
			failures.append("Production HUD still displays " + node_name)
	var door: Button = game.get("door_button")
	hidden["SanctuaryDoorButton"] = is_instance_valid(door) and not door.is_visible_in_tree()
	if not hidden.SanctuaryDoorButton:
		failures.append("Production destination button is still visible.")
	var crosshair := hud.crosshair
	var crosshair_visible := is_instance_valid(crosshair) and crosshair.is_visible_in_tree()
	var crosshair_size := crosshair.get_theme_font_size("font_size") if is_instance_valid(crosshair) else 0
	if not crosshair_visible or crosshair_size != 56:
		failures.append("The actual crosshair must stay visible at font size 56 (twice its previous 28).")
	return {"hidden_production_controls": hidden, "crosshair_visible": crosshair_visible, "crosshair_font_size": crosshair_size, "crosshair_text": crosshair.text if is_instance_valid(crosshair) else "", "crosshair_rect": str(crosshair.get_global_rect()) if is_instance_valid(crosshair) else "", "hud_layer_visible": hud.visible, "harness_changes_hud_presentation": false, "failures": failures}


static func execution_stopped(node: Node) -> bool:
	if node.is_processing() or node.is_physics_processing() or node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing_unhandled_key_input():
		return false
	for child in node.get_children():
		if not execution_stopped(child):
			return false
	return true


static func collect_source_hashes() -> Dictionary:
	# Hash the UI implementation and its entry/capture dependencies explicitly;
	# this is HUD evidence rather than a claim to audit all artwork in the game.
	var hashes := {}
	for path in ["res://project.godot", "res://hideout.tscn", "res://scripts/hideout.gd", "res://scripts/hideout_hud.gd", "res://scripts/hud.gd", "res://scripts/player.gd", "res://scripts/hideout_ruin_views.gd", "res://scripts/test_room_sandbox.gd", "res://assets/fonts/NotoSansKR-Variable.ttf", "res://tests/hideout_hud_preview.gd", "res://tests/performance_preview.gd", "res://tests/performance_scene_factory.gd", "res://tests/hideout_ruin_preview.gd", "res://tests/run_embedded_preview.sh"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the reviewed run_embedded_preview.sh hideout_hud_preview.gd renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("HIDEOUT_HUD_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Choose a new safe HIDEOUT_HUD_QA_ITERATION folder name.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Existing hideout HUD evidence is preserved; choose a new iteration.")
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("HUD preview requires a fresh isolated process without an active test-room session.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var bag_hash := RUIN_PREVIEW.inventory_fingerprint(original_bag)
	var sandbox_before := RUIN_PREVIEW.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var paused_before := paused
	var hashes := collect_source_hashes()
	var failures: Array[String] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var game := create_scene()
	viewport.add_child(game)
	stop_execution(game)
	configure_shot(game)
	for frame in 32:
		await process_frame
	var hud_state := inspect_hud(game)
	for failure in hud_state.failures:
		failures.append(str(failure))
	if not execution_stopped(game):
		failures.append("Preview scene still processes gameplay or external input.")
	var player: DungeonPlayer = game.get("player")
	var camera_state := {"position": str(player.camera.global_position), "transform": str(player.camera.global_transform), "fov": player.camera.fov}
	var torch_retained := player.torch.is_visible_in_tree() and player.torch_fill.is_visible_in_tree()
	if not torch_retained:
		failures.append("Actual safe-zone handheld torch lights were disabled.")
	RenderingServer.force_draw(false)
	var pixels := viewport.get_texture().get_image()
	var image_path := output.path_join("01_central_hall_default_hud.png")
	var saved := pixels != null and not pixels.is_empty() and pixels.save_png(image_path) == OK
	if not saved:
		failures.append("Real renderer failed to save the actual hideout HUD pixels.")
	viewport.free()
	await process_frame
	sandbox.finish()
	paused = paused_before
	var restored := ExpeditionSession.capture_snapshot()
	var preserved: bool = restored == original and restored.inventory == original_bag and RUIN_PREVIEW.inventory_fingerprint(original_bag) == bag_hash and Input.mouse_mode == mouse_before
	var sandbox_preserved := RUIN_PREVIEW.sandbox_snapshot(sandbox) == sandbox_before
	var unchanged := collect_source_hashes() == hashes
	if not preserved or not sandbox_preserved:
		failures.append("Original journey, inventory identity/content, sandbox or cursor changed.")
	if not unchanged:
		failures.append("Source files changed during capture; use a new iteration after changes settle.")
	for path in hashes:
		if str(hashes[path]).is_empty():
			failures.append("Source hash missing: " + str(path))
	var manifest := {"capture_kind": "Unretouched production hideout.tscn and default HUD via reviewed native-input-free entry adapter", "source_scene": "res://hideout.tscn", "display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "hud": hud_state, "camera": camera_state, "carried_geometry_visible": true, "production_torch_lights_visible": torch_retained, "image": {"file": image_path.get_file(), "size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "sha256": FileAccess.get_sha256(image_path) if saved else ""}, "source_sha256": hashes, "source_files_unchanged": unchanged, "expedition_inventory_and_cursor_preserved": preserved, "sandbox_preserved": sandbox_preserved, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write hideout HUD capture manifest.")
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	for failure in failures:
		push_error(failure)
	print("HIDEOUT HUD PREVIEW %s: actual default UI and enlarged crosshair; %s" % ["PASS" if failures.is_empty() else "FAIL", output])
	quit(0 if failures.is_empty() else 1)
