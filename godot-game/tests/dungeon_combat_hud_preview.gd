extends SceneTree
const HELPERS := preload("res://tests/item_detail_preview.gd")
const FACTORY := preload("res://tests/performance_scene_factory.gd")
const PERFORMANCE := preload("res://tests/performance_preview.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/dungeon_combat_hud"
func _init() -> void: call_deferred("_run")
static func shots() -> Array[Dictionary]:
	if OS.get_environment("COMBAT_HUD_QA_SCOPE") == "routes":
		return [
			{"id":"07_mine_warnings","size":Vector2i(1280,720),"action":"warnings","scene":"mine"},
			{"id":"08_test_room_default","size":Vector2i(960,540),"action":"healthy","scene":"test_room"}
		]
	return [
		{"id":"01_dungeon_healthy","size":Vector2i(1280,720),"action":"healthy"},
		{"id":"02_dungeon_warnings","size":Vector2i(1280,720),"action":"warnings"},
		{"id":"03_dungeon_treated_small","size":Vector2i(960,540),"action":"treated"},
		{"id":"04_item_use_countdown","size":Vector2i(1280,720),"action":"countdown"},
		{"id":"05_bandage_countdown_small","size":Vector2i(960,540),"action":"bandage"},
		{"id":"06_item_use_cancelled","size":Vector2i(1280,720),"action":"cancelled"}
	]
static func create_fixture(viewport: SubViewport, shot: Dictionary) -> Dictionary:
	ExpeditionSession.begin_new_journey(false)
	ExpeditionSession.hunger = 100
	ExpeditionSession.thirst = 100
	ExpeditionSession.stress = 0
	var scene_id := str(shot.get("scene", "dungeon"))
	var game: Node = load("res://tests/combat_hud_room_scene.gd").new() if scene_id == "test_room" else FACTORY.create(scene_id)
	viewport.add_child(game)
	HELPERS.stop_external_execution(game)
	var player: DungeonPlayer = game.player
	var bag: ExpeditionInventory = game.inventory
	for id in ["healing_draught","linen_bandage","pilgrim_ration","boiled_rainwater","antidote","purifying_salt"]:
		bag.add_item(id,3)
	var eye := Vector3(0,1.72,13)
	var target := Vector3(0,1.4,3)
	if scene_id == "mine":
		eye = preload("res://scripts/cave_layout.gd").spawn_position() + Vector3(0, 0.72, -1)
		target = eye + Vector3(0, -0.1, -10)
	PERFORMANCE.position_player(game,{"position":eye,"target":target},true)
	for frame in 30:
		player._update_viewmodel(1.0/60.0)
		player._update_torch(1.0/60.0)
	player.viewmodel_renderer.sync_view()
	var panel: Control = game.hud.combat_panel
	var responses: Array = []
	if shot.action != "healthy":
		player.apply_body_damage("left_arm",45)
		player.apply_condition("curse",180)
		ExpeditionSession.hunger = 15
		ExpeditionSession.thirst = 15
		ExpeditionSession.stress = 65
		player.stamina = 15
		panel.refresh()
	if shot.action == "treated":
		for i in [3,5,6,8]:
			panel.activate_slot(i)
			player.advance_item_use(20)
			responses.append(player.last_item_use_result)
			panel.refresh()
		ExpeditionSession.relieve_stress(100)
		player.stamina = player.MAX_STAMINA
	if shot.action in ["countdown", "bandage", "cancelled"]:
		player.select_treatment_part("left_arm")
		var id := "linen_bandage" if shot.action == "bandage" else "healing_draught"
		var count := bag.count_item(id)
		responses.append(player.begin_item_use(id,bag))
		for frame in 36:
			player.advance_item_use(1.0/30.0)
			player._update_viewmodel(1.0/30.0)
		if shot.action == "cancelled": player.handle_torch_action()
		responses.append({"not_consumed":bag.count_item(id)==count})
		player.viewmodel_renderer.sync_view()
	panel.refresh()
	# Hit/damage flashes have their production timer stopped by this fixture.
	# Finish their already-created tweens locally before capturing the HUD.
	for tween in game.get_tree().get_processed_tweens(): tween.custom_step(5)
	return {"game":game,"panel":panel,"responses":responses}
static func inspect_fixture(viewport: SubViewport, fixture: Dictionary, shot: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var panel: Control = fixture.panel
	var game: Node = fixture.game
	if not game.hud.combat_enabled or not panel.is_visible_in_tree(): failures.append("Actual dungeon entry failed to enable combat HUD")
	for legacy in game.hud.legacy_panels:
		if legacy.is_visible_in_tree(): failures.append("Legacy HUD overlaps the new combat HUD")
	if panel.bag != game.inventory or panel.player != game.player: failures.append("HUD not bound to production state")
	if not Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel.get_global_rect()): failures.append("HUD exceeds viewport")
	if panel.textures.size()!=10: failures.append("Missing shortcut textures")
	if shot.action == "healthy" and not panel.warnings.is_empty(): failures.append("Healthy state shows warnings")
	if shot.action == "warnings" and panel.warnings != ["hunger","thirst","fatigue","dizziness","curse"]: failures.append("Wrong live condition icons")
	if shot.action == "treated":
		if not panel.warnings.is_empty() or not fixture.responses.all(func(r): return r.get("accepted",false)): failures.append("Treatments failed to clear warnings")
	if shot.action in ["countdown", "bandage", "cancelled"]:
		var active: bool = game.player.is_item_use_active()
		if active != (shot.action != "cancelled") or game.hud.item_use_progress.visible != active: failures.append("Countdown/cancel visibility incorrect")
		if not fixture.responses[1].not_consumed: failures.append("Item consumed before completion or on cancellation")
		if shot.action == "countdown" and not is_equal_approx(float(game.player.get_item_use_snapshot().remaining),1.8): failures.append("Wrong actual remaining seconds")
		if active and game.hud.crosshair.visible: failures.append("Reticle obscures countdown")
		if not Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(game.hud.item_use_progress.get_global_rect()): failures.append("Timer outside viewport")
	if not HELPERS.execution_isolated(game) or not viewport.gui_disable_input: failures.append("External execution enabled")
	return {"item_use":game.player.get_item_use_snapshot(),"timer_visible":game.hud.item_use_progress.visible,"warnings":panel.warnings.duplicate(),"health":panel.body_snapshot,"items":panel.item_ids,"responses":fixture.responses,"failures":failures}
static func collect_hashes() -> Dictionary:
	var result := {}
	for path in ["scripts/cave_dungeon.gd", "scripts/test_room.gd", "tests/combat_hud_room_scene.gd", "tests/performance_mine_scene.gd"]:
		result["res://"+path] = FileAccess.get_sha256("res://"+path)
	for path in ["scripts/item_use_progress.gd","scripts/bandage_use_visuals.gd","scripts/splint_use_visuals.gd","scripts/dungeon_combat_hud.gd","scripts/hud.gd","scripts/player.gd","scripts/game.gd","scripts/inventory_model.gd","scripts/inventory_overlay.gd","tests/dungeon_combat_hud_preview.gd","tests/performance_scene_factory.gd","tests/performance_preview.gd","tests/item_detail_preview.gd"]:
		result["res://"+path] = FileAccess.get_sha256("res://"+path)
	return result

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Combat HUD captures require run_embedded_preview.sh dungeon_combat_hud_preview.gd.")
		quit(2)
		return
	var iteration := OS.get_environment("COMBAT_HUD_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Choose a new COMBAT_HUD_QA_ITERATION folder.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Preserve existing captures; choose a new iteration folder.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := HELPERS.PRESERVATION.inventory_fingerprint(original_bag)
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := HELPERS.PRESERVATION.sandbox_snapshot(sandbox)
	var mouse_before := Input.mouse_mode
	var hashes := collect_hashes()
	var failures: Array[String] = []
	for path in hashes:
		if str(hashes[path]).is_empty():
			failures.append("Missing source provenance: " + str(path))
	var captures: Array[Dictionary] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	for shot in shots():
		var viewport := HELPERS.create_viewport(shot.size)
		root.add_child(viewport)
		var fixture := create_fixture(viewport, shot)
		for frame in 12:
			await process_frame
		var report := inspect_fixture(viewport, fixture, shot)
		for failure in report.failures:
			failures.append(str(shot.id) + ": " + str(failure))
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var image_path := output.path_join(str(shot.id) + ".png")
		if pixels == null or pixels.is_empty() or pixels.save_png(image_path) != OK:
			failures.append("Could not save actual renderer output: " + str(shot.id))
		report["image"] = image_path.get_file()
		captures.append(report)
		viewport.free()
		await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == original and HELPERS.PRESERVATION.inventory_fingerprint(original_bag) == original_bag_hash and Input.mouse_mode == mouse_before and HELPERS.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before
	if not preserved:
		failures.append("Original expedition, inventory, sandbox or cursor changed.")
	if collect_hashes() != hashes:
		failures.append("Production sources changed during capture.")
	var manifest := {"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not save capture manifest.")
	for failure in failures:
		push_error(failure)
	print("DUNGEON COMBAT HUD PREVIEW %s: %d actual dungeon UI captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)
