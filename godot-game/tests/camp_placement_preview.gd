extends SceneTree
## Shared by the headless fixture test and the audited embedded renderer.
## All poses and menus come from the production placement/camp code.

const HELPERS := preload("res://tests/item_detail_preview.gd")
const SCENE := preload("res://tests/camp_placement_preview_scene.gd")
const VISUALS := preload("res://scripts/camp_visuals.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/camp_placement"
const SOURCE_PATHS := [
	"scripts/game.gd", "scripts/player.gd", "scripts/camp_controller.gd",
	"scripts/camp_placement_probe.gd", "scripts/camp_visuals.gd",
	"scripts/camp_overlay.gd", "scripts/camp_placement_overlay.gd",
	"scripts/camp_cooking_catalog.gd", "scripts/inventory_model.gd",
	"scripts/inventory_overlay.gd", "scripts/expedition_session.gd",
	"scripts/hud.gd", "scripts/dungeon_combat_hud.gd",
	"scripts/dark_fantasy_materials.gd", "scripts/flame_visuals.gd",
	"tests/camp_placement_preview.gd", "tests/camp_placement_preview_scene.gd",
	"tests/camp_placement_preview_test.gd", "tests/performance_scene_factory.gd",
	"tests/performance_preview.gd", "tests/item_detail_preview.gd",
	"tests/hideout_ruin_preview.gd", "tests/run_embedded_preview.sh",
	"assets/fonts/NotoSansKR-Variable.ttf",
	"assets/ai/materials/concept_ember_coal.png", "assets/ai/vfx/torch_flame.png"
]


func _init() -> void:
	call_deferred("_run")


static func shots() -> Array[Dictionary]:
	return [
		{"id": "01_valid_ground", "size": Vector2i(1280, 720), "action": "valid"},
		{"id": "02_blocked_wall", "size": Vector2i(1280, 720), "action": "blocked"},
		{"id": "03_deployed_tent", "size": Vector2i(1280, 720), "action": "deployed"},
		{"id": "04_seated_cooking", "size": Vector2i(1280, 720), "action": "cooking"},
		{"id": "05_seated_recipes_small", "size": Vector2i(960, 540), "action": "recipes"}
	]


static func create_fixture(viewport: SubViewport, shot: Dictionary) -> Dictionary:
	viewport.get_tree().paused = false
	ExpeditionSession.begin_new_journey(false)
	ExpeditionSession.hunger = 45.0
	ExpeditionSession.thirst = 65.0
	ExpeditionSession.stress = 0.0
	var game := SCENE.new()
	viewport.add_child(game)
	HELPERS.stop_external_execution(game)
	var player: DungeonPlayer = game.player
	var bag: ExpeditionInventory = game.inventory
	for entry: Dictionary in [{"id": "camp_kit", "count": 2}, {"id": "raw_meat", "count": 3}, {"id": "edible_mushroom", "count": 4}, {"id": "boiled_rainwater", "count": 3}]:
		bag.add_item(str(entry.id), int(entry.count), false)
	bag.changed.emit()
	var blocked := str(shot.action) == "blocked"
	player.global_position = Vector3(2.8, 1.0, 12.7) if blocked else Vector3(-2.0, 1.0, 14.2)
	# Establish real floor contact while all external and automatic processing
	# remains disabled. No is_on_floor override or fabricated floor state.
	for frame in 24:
		await viewport.get_tree().physics_frame
		player.velocity = Vector3.DOWN * 3.0
		player.move_and_slide()
		if player.is_on_floor():
			break
	player.velocity = Vector3.ZERO
	player.trap_lockout = 0.0
	_aim_at(player, Vector3(2.8, 0.0, 9.8) if blocked else Vector3(-2.0, 0.0, 11.3))
	for frame in 24:
		player._update_viewmodel(1.0 / 60.0)
		player._update_torch(1.0 / 60.0)
	player.viewmodel_renderer.sync_view()
	var responses: Array[Dictionary] = []
	var initial_kit := bag.count_item("camp_kit")
	var initial_meat := bag.count_item("raw_meat")
	# begin_placement's production signals create/update/show the actual HUD.
	responses.append(game.open_camp())
	responses.append(game.camp.update_placement())
	var placement: Dictionary = game.camp.placement_snapshot.duplicate(true)
	var original_preview: Node3D = game.camp.preview_visual
	game.camp.update_placement()
	var reused_preview: bool = original_preview == game.camp.preview_visual
	if str(shot.action) in ["deployed", "cooking", "recipes"] and bool(placement.get("accepted", false)):
		responses.append(game.camp.confirm_placement())
		HELPERS.stop_external_execution(game)
		await viewport.get_tree().physics_frame
		if str(shot.action) in ["cooking", "recipes"]:
			responses.append(game.camp.interact(player))
			game.camp.overlay.select_category("cooking")
			if str(shot.action) == "cooking" and game.camp.state == "planning":
				responses.append(game.camp.start_action("cook:roast_meat"))
				game.camp.advance_rest(5.0)
		if is_instance_valid(game.camp.camp_visual):
			VISUALS.animate(game.camp.camp_visual, 2.5, game.camp.warmth)
		player.viewmodel_renderer.sync_view()
	game.hud._process(0.0)
	HELPERS.stop_external_execution(game)
	# Finish already-created local feedback tweens. This does not run the
	# player/controller clocks, deliver input, or alter the actual camp state.
	for tween in viewport.get_tree().get_processed_tweens():
		tween.custom_step(5.0)
	return {"game": game, "placement": placement, "responses": responses, "initial_kit": initial_kit, "initial_meat": initial_meat, "reused_preview": reused_preview}


static func _aim_at(player: DungeonPlayer, target: Vector3) -> void:
	var direction := (target - player.camera.global_position).normalized()
	player.rotation.y = atan2(-direction.x, -direction.z)
	var pitch := asin(direction.y)
	player.set("_pitch", pitch)
	player.head.rotation.x = pitch
	player.camera.rotation = Vector3.ZERO


static func inspect_fixture(viewport: SubViewport, fixture: Dictionary, shot: Dictionary) -> Dictionary:
	var failures: Array[String] = []
	var game: Node = fixture.game
	var player: DungeonPlayer = game.player
	var camp: DungeonCamp = game.camp
	var action := str(shot.action)
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(viewport.size))
	if not player.is_on_floor(): failures.append("Player never acquired real floor contact")
	if not bool(fixture.responses[0].get("accepted", false)): failures.append("Production placement entry rejected: %s" % fixture.responses[0])
	if not fixture.reused_preview: failures.append("Placement updates recreated the ghost model")
	if not HELPERS.execution_isolated(game) or not viewport.gui_disable_input: failures.append("External execution or input remains enabled")
	if action in ["valid", "blocked"]:
		var accepted := action == "valid"
		if camp.state != "placing" or bool(fixture.placement.get("accepted", false)) != accepted: failures.append("Unexpected actual placement decision: %s" % fixture.placement)
		if not game.camp_placement_overlay.overlay_root.is_visible_in_tree(): failures.append("Production placement signals did not show HUD")
		if not viewport_rect.encloses(game.camp_placement_overlay.panel_root.get_global_rect()): failures.append("Placement instructions exceed the viewport: panel=%s viewport=%s minimum=%s" % [game.camp_placement_overlay.panel_root.get_global_rect(), viewport_rect, game.camp_placement_overlay.panel_root.get_combined_minimum_size()])
		if not is_instance_valid(camp.preview_visual) or bool(camp.preview_visual.get_meta("placement_valid", not accepted)) != accepted: failures.append("Ghost tint did not follow actual validity")
		if is_instance_valid(camp.preview_visual):
			if _count_types(camp.preview_visual, "CollisionObject3D") != 0 or _count_types(camp.preview_visual, "Light3D") != 0: failures.append("Ghost spawned collision or a real light")
		if game.inventory.count_item("camp_kit") != int(fixture.initial_kit): failures.append("Preview spent a camp kit")
	else:
		if not is_instance_valid(camp.camp_visual):
			failures.append("Camp commit did not create the actual tent/fire")
		else:
			if not camp.camp_visual.has_node("Tent/TentInteraction") or camp.camp_visual.get_node("Tent/TentInteraction").get_meta("interaction_owner") != camp: failures.append("Tent interaction is not bound to the production controller")
			if not camp.camp_visual.has_node("Tent/TentBody") or not camp.camp_visual.has_node("CampfireLight"): failures.append("Missing physical tent or actual campfire")
		if game.inventory.count_item("camp_kit") != int(fixture.initial_kit) - 1 or not camp.kit_spent: failures.append("Commit must consume exactly one camp kit")
		if game.camp_placement_overlay.overlay_root.visible: failures.append("Placement HUD remained after commit")
		if action == "deployed":
			if camp.state != "deployed" or player.camping: failures.append("Deployment automatically sat the player")
		else:
			if not player.camping or not camp.overlay.overlay_root.is_visible_in_tree(): failures.append("Tent interaction did not open the actual seated menu")
			if not viewport_rect.encloses(camp.overlay.panel_root.get_global_rect()): failures.append("Camp menu exceeds the viewport")
			if not viewport_rect.encloses(camp.overlay.leave_button.get_global_rect()): failures.append("Stand-up button is unreachable")
			if player.weapon_pivot.visible or player.shield_pivot.visible: failures.append("Seated player still holds combat equipment")
			if is_instance_valid(camp.camp_visual):
				var fire_screen := player.camera.unproject_position(camp.camp_visual.global_position + Vector3(0, 0.35, 0))
				if not viewport_rect.has_point(fire_screen) or camp.overlay.panel_root.get_global_rect().has_point(fire_screen): failures.append("The menu covers the fire in the actual seated camera")
			if action == "recipes":
				if camp.state != "planning" or not game.get_tree().paused or camp.overlay.selected_category != "cooking": failures.append("Seated recipe menu did not use actual paused planning")
				if game.inventory.count_item("raw_meat") != int(fixture.initial_meat): failures.append("Opening recipes spent ingredients")
			else:
				if camp.state != "resting" or game.get_tree().paused or not camp.get_snapshot().get("is_cooking", false): failures.append("Cooking did not run the live production action")
				if not is_equal_approx(camp.rest_elapsed, 5.0) or not is_equal_approx(camp.overlay.progress_bar.value, 0.625): failures.append("Cooking display is not driven by real elapsed time: elapsed=%.8f duration=%.8f snapshot=%.8f bar=%.8f max=%.8f step=%.8f" % [camp.rest_elapsed, camp.rest_duration, float(camp.get_snapshot().get("progress", -1)), camp.overlay.progress_bar.value, camp.overlay.progress_bar.max_value, camp.overlay.progress_bar.step])
				if game.inventory.count_item("raw_meat") != int(fixture.initial_meat) - 1: failures.append("Cooking failed to spend the actual ingredient")
				if is_instance_valid(camp.camp_visual):
					var spit: Node3D = camp.camp_visual.get_node("CookingTools/RoastingSpit/SpitSkewer")
					var food_screen := player.camera.unproject_position(spit.global_position)
					if not spit.is_visible_in_tree() or not viewport_rect.has_point(food_screen) or camp.overlay.panel_root.get_global_rect().has_point(food_screen): failures.append("Actual cooking food is hidden or covered")
	for response: Dictionary in fixture.responses:
		if action != "blocked" and not bool(response.get("accepted", false)): failures.append("Production action rejected: %s" % response)
	return {"id": str(shot.id), "size": [viewport.size.x, viewport.size.y], "state": camp.state, "placement": fixture.placement, "responses": fixture.responses, "camp": camp.get_snapshot(), "on_floor": player.is_on_floor(), "seated": player.camping, "camera_position": player.camera.global_position, "reused_preview": fixture.reused_preview, "failures": failures}


static func _count_types(node: Node, type_name: String) -> int:
	var count := 1 if node.is_class(type_name) else 0
	for child in node.get_children():
		count += _count_types(child, type_name)
	return count


static func collect_hashes() -> Dictionary:
	var hashes := {}
	for path: String in SOURCE_PATHS:
		hashes["res://" + path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Camp captures require run_embedded_preview.sh camp_placement_preview.gd.")
		quit(2)
		return
	var iteration := OS.get_environment("CAMP_PLACEMENT_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Choose a new CAMP_PLACEMENT_QA_ITERATION folder.")
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
	var paused_before := paused
	var hashes := collect_hashes()
	var failures: Array[String] = []
	for path in hashes:
		if str(hashes[path]).is_empty(): failures.append("Missing source provenance: " + str(path))
	var captures: Array[Dictionary] = []
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	for shot in shots():
		var before := collect_hashes()
		if before != hashes: failures.append(str(shot.id) + ": source changed before capture")
		var viewport := HELPERS.create_viewport(shot.size)
		root.add_child(viewport)
		var fixture := await create_fixture(viewport, shot)
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
		report["source_sha256_before"] = before
		report["source_sha256_after"] = collect_hashes()
		if report.source_sha256_after != hashes: failures.append(str(shot.id) + ": source changed during capture")
		captures.append(report)
		viewport.free()
		paused = false
		await process_frame
	sandbox.finish()
	paused = paused_before
	var preserved := ExpeditionSession.capture_snapshot() == original and HELPERS.PRESERVATION.inventory_fingerprint(original_bag) == original_bag_hash and Input.mouse_mode == mouse_before and HELPERS.PRESERVATION.sandbox_snapshot(sandbox) == sandbox_before
	if not preserved: failures.append("Original expedition, inventory, sandbox or cursor changed")
	if collect_hashes() != hashes: failures.append("Production sources changed during capture")
	var manifest := {"display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "native_mouse_hook_bypassed": true, "hardware_input_verified": false, "preserved": preserved, "source_sha256": hashes, "captures": captures, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not save capture manifest")
	for failure in failures: push_error(failure)
	print("CAMP PLACEMENT PREVIEW %s: %d actual gameplay captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)
