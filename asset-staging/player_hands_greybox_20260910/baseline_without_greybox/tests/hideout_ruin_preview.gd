extends SceneTree
## Reviewed embedded-only production world inspection. No live hideout _ready,
## scene change, external input, mouse capture, focus or desktop screenshot.
const VIEWS := preload("res://scripts/hideout_ruin_views.gd")
const PRODUCTION := preload("res://tests/dark_fantasy_scene_preview.gd")
const EVIDENCE := preload("res://tests/dark_fantasy_capture_evidence.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/hideout_ruins"
const IMAGE_SIZE := VIEWS.IMAGE_SIZE


func _init() -> void:
	call_deferred("_run")


static func create_viewport() -> SubViewport:
	var viewport := PRODUCTION.create_viewport("hideout")
	viewport.name = "IsolatedProductionHideoutRooms"
	return viewport


static func populate_viewport(viewport: SubViewport) -> void:
	PRODUCTION.populate_viewport(viewport)


static func configure_shot(viewport: SubViewport, shot: Dictionary) -> bool:
	if str(shot.get("id", "")) not in VIEWS.ordered_ids():
		return false
	var parameters := shot.duplicate(true)
	parameters["scene"] = "hideout"
	if not PRODUCTION.configure_shot(viewport, parameters):
		return false
	PRODUCTION.active_camera(viewport).fov = float(shot.fov)
	return true


static func inventory_fingerprint(bag: ExpeditionInventory) -> String:
	if bag == null:
		return "no_inventory"
	return JSON.stringify({"slots": bag.slots, "equipment": bag.equipment, "equipment_data": bag.equipment_data}).sha256_text()


static func sandbox_snapshot(sandbox: Node) -> Dictionary:
	# Capture all script state, including pending requests added in the future.
	# Object values preserve identity, dictionaries/arrays are copied deeply.
	var result := {}
	for property in sandbox.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = sandbox.get(property.name)
			result[str(property.name)] = value.duplicate(true) if value is Dictionary or value is Array else value
	return result


static func collect_source_hashes() -> Dictionary:
	var result := EVIDENCE.collect()
	for path in ["res://project.godot", "res://tests/hideout_ruin_preview.gd", "res://tests/run_embedded_preview.sh", "res://tests/art_direction_preview.gd"]:
		result[path] = FileAccess.get_sha256(path)
	for folder in ["res://assets/3d/hideout_ruins", "res://assets/ai/hideout_ruins"]:
		_collect_folder(result, folder)
	return result


static func _collect_folder(result: Dictionary, folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file in DirAccess.get_files_at(folder):
		if not file.begins_with("."):
			var path := folder.path_join(file)
			result[path] = FileAccess.get_sha256(path)
	for child in DirAccess.get_directories_at(folder):
		if not child.begins_with("."):
			_collect_folder(result, folder.path_join(child))


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the reviewed run_embedded_preview.sh hideout_ruin_preview.gd renderer.")
		quit(2)
		return
	var shots := VIEWS.selected_shots(OS.get_environment("HIDEOUT_RUIN_QA_ROOMS"))
	var iteration := OS.get_environment("HIDEOUT_RUIN_QA_ITERATION").strip_edges()
	if shots.is_empty() or iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Select known hideout rooms and a new safe HIDEOUT_RUIN_QA_ITERATION name.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Existing room evidence is preserved; choose a new iteration folder.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_bag: ExpeditionInventory = original.inventory
	var original_bag_hash := inventory_fingerprint(original_bag)
	var mouse_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_before := sandbox_snapshot(sandbox)
	var source_hashes := collect_source_hashes()
	var failures: Array[String] = []
	var records: Array[Dictionary] = []
	# The original inventory is never given to production constructors.
	ExpeditionSession.begin_new_journey()
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var viewport := create_viewport()
	root.add_child(viewport)
	populate_viewport(viewport)
	await physics_frame
	await physics_frame
	for shot in shots:
		if not configure_shot(viewport, shot):
			failures.append("Production room camera failed: " + str(shot.id))
			continue
		for frame in range(24):
			await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var filename := str(shot.id) + ".png"
		if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(filename)) != OK:
			failures.append("Actual room renderer pixels missing: " + str(shot.id))
			continue
		var camera := PRODUCTION.active_camera(viewport)
		var player := viewport.find_child("ProductionTorchCamera", true, false) as DungeonPlayer
		var torch_retained := player.torch.is_visible_in_tree() and player.torch_fill.is_visible_in_tree()
		if not torch_retained:
			failures.append("Actual handheld torch lights were disabled: " + str(shot.id))
		records.append({"id": shot.id, "region_id": shot.region_id, "title": shot.title, "file": filename, "sha256": FileAccess.get_sha256(output.path_join(filename)), "size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "position": PRODUCTION._vector(camera.global_position), "target": PRODUCTION._vector(shot.target), "fov": camera.fov, "production_torch_spot_and_fill_visible": torch_retained})
		print("HIDEOUT RUIN CAPTURE: " + filename)
	viewport.free()
	await process_frame
	ExpeditionSession.restore_snapshot(original)
	var preserved: bool = ExpeditionSession.capture_snapshot() == original and ExpeditionSession.capture_snapshot().inventory == original_bag and inventory_fingerprint(original_bag) == original_bag_hash and Input.mouse_mode == mouse_before
	var sandbox_preserved := sandbox_snapshot(sandbox) == sandbox_before
	var sources_unchanged := source_hashes == collect_source_hashes()
	if not preserved or not sandbox_preserved:
		failures.append("Original journey, bag identity/content, test-room state or cursor changed.")
	if not sources_unchanged:
		failures.append("Production sources changed during capture; freeze them and capture a fresh iteration.")
	for source in source_hashes:
		if str(source_hashes[source]).is_empty():
			failures.append("Source fingerprint missing: " + str(source))
	if records.size() != shots.size():
		failures.append("Incomplete selected-room capture.")
	var manifest := {"capture_kind": "Unretouched actual production hideout, one room per image", "display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "carried_geometry_visible": false, "source_sha256": source_hashes, "source_files_unchanged": sources_unchanged, "expedition_and_cursor_preserved": preserved, "sandbox_preserved": sandbox_preserved, "original_bag_sha256": original_bag_hash, "complete_rooms": records.size() == VIEWS.SHOTS.size() and failures.is_empty(), "images": records, "failures": failures}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file == null:
		failures.append("Cannot write hideout room evidence manifest.")
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	for failure in failures:
		push_error(failure)
	print("HIDEOUT RUIN PREVIEW %s: %d separate production room images; %s" % ["PASS" if failures.is_empty() else "FAIL", records.size(), output])
	quit(0 if failures.is_empty() else 1)
