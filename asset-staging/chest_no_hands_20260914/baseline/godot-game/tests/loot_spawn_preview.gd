extends SceneTree
## Actual supplied containers and authored map sites, in an input-free viewport.
## No gameplay entry, external events, desktop capture or window is used.

const LOCATIONS := preload("res://tests/dark_fantasy_scene_preview.gd")
const CATALOG := preload("res://scripts/loot_spawn_catalog.gd")
var records: Array[Dictionary] = []
var failures: Array[String] = []
var output := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		quit(2)
		return
	var iteration := OS.get_environment("LOOT_SPAWN_QA_ITERATION")
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	output = ProjectSettings.globalize_path("res://artifacts/visual_qa/loot_spawns/" + iteration)
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var original := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var sources := _hashes()
	await _capture_models()
	for map_id: String in CATALOG.map_ids():
		await _capture_map(map_id)
	if ExpeditionSession.capture_snapshot() != original or Input.mouse_mode != mouse_mode:
		failures.append("Expedition or cursor changed")
	if _hashes() != sources:
		failures.append("Source files changed during capture")
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(), "display": DisplayServer.get_name(), "desktop_capture": false, "external_input": false, "state_preserved": ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_mode, "sources": sources, "captures": records, "failures": failures}, "\t"))
	print("LOOT SPAWN PREVIEW %s: %d actual model/site frames; %s" % ["PASS" if failures.is_empty() else "FAIL", records.size(), output])
	quit(0 if failures.is_empty() else 1)


func _capture_models() -> void:
	var viewport := LOCATIONS.create_viewport("dungeon")
	root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.065, 0.075, 0.08)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.8, 0.85)
	environment.environment.ambient_light_energy = 0.55
	stage.add_child(environment)
	for settings in [[Vector3(-45, -35, 0), 1.15], [Vector3(-20, 140, 0), 0.65]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = settings[0]
		light.light_energy = settings[1]
		stage.add_child(light)
	var camera := Camera3D.new()
	camera.fov = 43
	stage.add_child(camera)
	camera.make_current()
	var player := DungeonPlayer.new()
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.set_process_input(false)
	var inventory := ExpeditionInventory.new()
	inventory.seed_default_loadout()
	player.bind_inventory(inventory)
	for variant: String in DungeonLootChest.SUPPLIED_MODELS:
		player.hide()
		camera.make_current()
		var chest := DungeonLootChest.new().configure_visual(variant)
		stage.add_child(chest)
		var center := chest.visual_bounds().get_center()
		camera.position = center + Vector3(2.25, 1.6, -3.1)
		camera.look_at(center)
		await _capture(viewport, variant + "_closed", {"kind": "model", "variant": variant, "state": "closed"})
		chest._set_lid_pull(1.0)
		await _capture(viewport, variant + "_open", {"kind": "model", "variant": variant, "state": "fully_open"})
		chest._set_lid_pull(0.0)
		player.show()
		player.camera.make_current()
		var camera_position := Vector3(0.0, 1.57, -chest.visual_bounds().size.z * 0.5 - 0.65)
		LOCATIONS.MINE_PREVIEW.configure_shot(player, {"name": variant, "position": camera_position, "target": Vector3(0, chest.visual_bounds().size.y * 0.8, 0), "equipment": true})
		chest.interact(player)
		if not player.is_timed_interacting() or not chest.is_within_hand_reach(player):
			failures.append("Actual hand interaction failed to start: " + variant)
		player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.55)
		player._update_viewmodel(1.0)
		player.viewmodel_renderer.sync_view()
		await _capture(viewport, variant + "_hands_contact", {"kind": "hands", "variant": variant, "progress": 0.55})
		if not player.chest_hands.active or not is_equal_approx(player.get_timed_interaction_progress(), 0.55):
			failures.append("Hand contact did not remain active: " + variant)
		player.advance_timed_interaction(DungeonLootChest.OPEN_DURATION * 0.31)
		player._update_viewmodel(1.0)
		player.viewmodel_renderer.sync_view()
		await _capture(viewport, variant + "_hands_lift", {"kind": "hands", "variant": variant, "progress": 0.86})
		if not player.chest_hands.active or not is_equal_approx(player.get_timed_interaction_progress(), 0.86):
			failures.append("Hand lift did not remain active: " + variant)
		player.cancel_timed_interaction()
		chest.free()
	viewport.free()
	await process_frame


func _capture_map(map_id: String) -> void:
	var scene_id := "dungeon" if map_id == "reliquary" else "mine"
	var viewport := LOCATIONS.create_viewport(scene_id)
	root.add_child(viewport)
	LOCATIONS.populate_viewport(viewport)
	if scene_id == "mine":
		if not await LOCATIONS.MINE_PREVIEW.await_geometry_ready(viewport.find_child("CaveGeometry", true, false)):
			failures.append("Mine dressing and lighting failed to become ready")
	# Remove the scene preview's sampled chests; inspect each production site
	# explicitly once with and once without a chest at identical camera angles.
	_remove_preview_chests(viewport)
	for frame in range(24):
		await process_frame
	for site: Dictionary in CATALOG.candidates(map_id):
		var chest := DungeonLootChest.new().configure(str(site.title), site.items, str(site.subtitle)).configure_visual(str(site.model_variant))
		chest.position = site.position
		chest.rotation.y = float(site.yaw)
		viewport.add_child(chest)
		# Use the same independently checked standing point as actual opening;
		# a distant cinematic camera can sit behind a curved cave wall.
		var position: Vector3 = site.approach_position + Vector3.UP * 0.67
		var target: Vector3 = site.position + Vector3.UP * chest.visual_bounds().size.y * 0.55
		LOCATIONS.configure_shot(viewport, {"id": str(site.id), "scene": scene_id, "position": position, "target": target})
		await _capture(viewport, map_id + "_" + str(site.id) + "_present", {"kind": "site", "map": map_id, "site": site.id, "context": site.context, "occupied": true, "camera": str(position), "target": str(target)})
		chest.hide()
		await _capture(viewport, map_id + "_" + str(site.id) + "_absent", {"kind": "site", "map": map_id, "site": site.id, "occupied": false, "camera": str(position), "target": str(target)})
		chest.free()
	viewport.free()
	await process_frame


func _remove_preview_chests(node: Node) -> void:
	for child in node.get_children():
		if child.has_meta("loot_site_id"):
			child.free()
		else:
			_remove_preview_chests(child)


func _capture(viewport: SubViewport, id: String, record: Dictionary) -> void:
	for frame in range(8):
		await process_frame
	RenderingServer.force_draw(false)
	var captured := viewport.get_texture().get_image()
	if captured == null or captured.is_empty() or captured.save_png(output.path_join(id + ".png")) != OK:
		failures.append("Empty or failed image: " + id)
		return
	record["image"] = id + ".png"
	record["sha256"] = FileAccess.get_sha256(output.path_join(id + ".png"))
	records.append(record)
	print("LOOT CAPTURE: " + id)


func _hashes() -> Dictionary:
	var result := {}
	var paths := ["res://scripts/loot_chest.gd", "res://scripts/loot_spawn_catalog.gd", "res://scripts/game.gd", "res://scripts/cave_dungeon.gd", "res://tests/loot_spawn_preview.gd", "res://scripts/chest_hand_visuals.gd", "res://scripts/player.gd"]
	paths.append_array(DungeonLootChest.SUPPLIED_MODELS.values())
	for path: String in paths:
		result[path] = FileAccess.get_sha256(path)
	return result
