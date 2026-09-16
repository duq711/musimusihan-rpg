extends SceneTree
## Same six-view inspector as the actual test room, followed by the actual
## player's four combat states. Never accepts OS input or opens a window.
const GALLERY := preload("res://scripts/dark_fantasy_gallery.gd")
const POSE_PREVIEW := preload("res://tests/sword_shield_preview.gd")
const IDS := ["rusted_longsword", "weathered_round_shield"]
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded": quit(2); return
	var iteration := OS.get_environment("SWORD_SHIELD_MULTIVIEW_ITERATION")
	if not iteration.is_valid_filename() or iteration.begins_with("."): quit(2); return
	var output := ProjectSettings.globalize_path("res://artifacts/visual_qa/sword_shield_multiview/" + iteration)
	if DirAccess.dir_exists_absolute(output): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var saved := ExpeditionSession.capture_snapshot()
	var fingerprint := POSE_PREVIEW.PREVIEW.inventory_fingerprint(saved.inventory)
	var cursor := Input.mouse_mode
	var sources := _sources()
	var gallery := GALLERY.new()
	root.add_child(gallery)
	var records: Array[Dictionary] = []
	for id in IDS:
		if not gallery.select_object(id): failures.append("Missing production object " + id); continue
		for direction in GALLERY.VIEWS:
			gallery.set_view(direction)
			for frame in 8: await process_frame
			RenderingServer.force_draw(false)
			var filename: String = id + "_" + direction + ".png"
			var pixels := gallery.viewport.get_texture().get_image()
			if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(filename)) != OK: failures.append("Empty view " + filename)
			records.append({"object": id, "view": direction, "image": filename, "camera": str(gallery.camera.transform), "bounds": str(gallery.object_bounds), "source": gallery.object_root.get_meta("production_scene", "")})
	gallery.free()
	await process_frame
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var poses: Array[Dictionary] = []
	for pose in POSE_PREVIEW.POSES:
		var viewport := POSE_PREVIEW.create_studio_viewport()
		root.add_child(viewport)
		var fixture := POSE_PREVIEW.PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		if not POSE_PREVIEW.configure_pose(fixture, pose): failures.append("Invalid production pose " + pose)
		POSE_PREVIEW.configure_studio(fixture)
		fixture.player.viewmodel_renderer.sync_view()
		for frame in 12: await process_frame
		RenderingServer.force_draw(false)
		var filename: String = "first_person_" + pose + ".png"
		var pixels := viewport.get_texture().get_image()
		if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(filename)) != OK: failures.append("Empty pose " + pose)
		poses.append({"pose": pose, "image": filename, "production": fixture.player.get_first_person_motion_snapshot()})
		viewport.queue_free()
		await process_frame
	sandbox.finish()
	var preserved := saved == ExpeditionSession.capture_snapshot() and fingerprint == POSE_PREVIEW.PREVIEW.inventory_fingerprint(saved.inventory) and Input.mouse_mode == cursor
	if not preserved: failures.append("Original expedition or cursor changed")
	if sources != _sources(): failures.append("Capture sources changed")
	var manifest := {"actual_renderer": RenderingServer.get_current_rendering_driver_name(), "display_driver": DisplayServer.get_name(), "source_sha256": sources, "session_and_cursor_preserved": preserved, "views": records, "first_person": poses, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"))
	for failure in failures: push_error(failure)
	print("SWORD SHIELD MULTIVIEW PREVIEW %s: twelve production directions, four actual player poses; %s" % ["PASS" if failures.is_empty() else "FAIL", output])
	quit(0 if failures.is_empty() else 1)

func _sources() -> Dictionary:
	var paths: Array = POSE_PREVIEW.SOURCES.duplicate()
	paths.append_array(POSE_PREVIEW.PREVIEW.SOURCE_FILES)
	paths.append_array(["res://tests/sword_shield_multiview_preview.gd", "res://scripts/dark_fantasy_gallery.gd", "res://scripts/dark_fantasy_object_catalog.gd", "res://assets/art_direction/object_inventory.json", "res://assets/ai/sword_shield/weapon_material_atlas_v2.png", "res://../asset-staging/sword_shield_multiview/sword_views_v2.png", "res://../asset-staging/sword_shield_multiview/shield_views_v1.png", "res://../asset-staging/sword_shield_multiview/build_multiview_assets.py", "res://../asset-staging/sword_shield_multiview/sword_geometry.py", "res://../asset-staging/sword_shield_multiview/shield_geometry.py"])
	var result := {}
	for path in paths:
		var digest := FileAccess.get_sha256(path)
		if digest.length() != 64: failures.append("Missing source " + str(path))
		result[path] = digest
	return result
