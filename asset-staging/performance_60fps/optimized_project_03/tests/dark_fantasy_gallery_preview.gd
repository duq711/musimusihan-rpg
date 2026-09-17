extends SceneTree
## Only an unhosted embedded renderer is allowed. This script never instantiates
## a running game, opens a window, takes desktop screenshots or injects input.

const GALLERY := preload("res://scripts/dark_fantasy_gallery.gd")
const CATALOG := preload("res://scripts/dark_fantasy_object_catalog.gd")
const EVIDENCE := preload("res://tests/dark_fantasy_capture_evidence.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/dark_fantasy_objects"
var failed := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Object captures require the reviewed tests/run_embedded_preview.sh embedded Vulkan renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("DARK_FANTASY_QA_ITERATION").strip_edges()
	if iteration.is_empty():
		iteration = "iteration_01"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("DARK_FANTASY_QA_ITERATION must be a plain folder name.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	# Previous iterations are evidence. An explicit new folder is mandatory.
	if DirAccess.dir_exists_absolute(output):
		push_error("Refusing to overwrite an existing object capture iteration: " + output)
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var sources := EVIDENCE.collect()
	var entry_source_hashes := {}
	var gallery := GALLERY.new()
	root.add_child(gallery)
	var objects := CATALOG.entries()
	if OS.get_environment("DARK_FANTASY_QA_MINE_FIRST") == "1":
		objects.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return str(first.factory_type) in ["mine_node", "rock", "board", "mine_water"] and str(second.factory_type) not in ["mine_node", "rock", "board", "mine_water"])
	var selected := OS.get_environment("DARK_FANTASY_QA_OBJECTS").split(",", false)
	for selected_id in selected:
		if not objects.any(func(entry: Dictionary) -> bool: return str(entry.id) == selected_id):
			push_error("Unknown requested gallery object: " + selected_id)
			failed = true
	var records: Array[Dictionary] = []
	for entry in objects:
		var id := str(entry.id)
		if not selected.is_empty() and id not in selected:
			continue
		if failed:
			break
		if not gallery.select_object(id):
			push_error("Production object has no renderable geometry: " + id)
			failed = true
			break
		var source_path := "res://" + str(entry.get("source_path", "")).trim_prefix("godot-game/").trim_prefix("res://")
		if not entry_source_hashes.has(source_path):
			entry_source_hashes[source_path] = FileAccess.get_sha256(source_path) if FileAccess.file_exists(source_path) else ""
		var record := {"source_path": source_path, "source_sha256": entry_source_hashes[source_path], "id": id, "title": entry.title, "factory": entry.get("factory", ""), "images": [], "bounds": {"position": _vector(gallery.object_bounds.position), "size": _vector(gallery.object_bounds.size)}}
		var sheet := Image.create(GALLERY.CAPTURE_SIZE.x * 3, GALLERY.CAPTURE_SIZE.y * 2, false, Image.FORMAT_RGBA8)
		for index in GALLERY.VIEWS.size():
			var view_name := GALLERY.VIEWS[index]
			gallery.set_view(view_name)
			for frame in range(6):
				await process_frame
			RenderingServer.force_draw(false)
			var captured := gallery.viewport.get_texture().get_image()
			if captured == null or captured.is_empty():
				push_error("Actual renderer returned an empty image: " + id + "/" + view_name)
				failed = true
				break
			captured.convert(Image.FORMAT_RGBA8)
			var filename := id + "_" + view_name + ".png"
			if captured.save_png(output.path_join(filename)) != OK:
				failed = true
				break
			record.images.append({"view": view_name, "file": filename, "sha256": FileAccess.get_sha256(output.path_join(filename))})
			sheet.blit_rect(captured, Rect2i(Vector2i.ZERO, GALLERY.CAPTURE_SIZE), Vector2i(index % 3, index / 3) * GALLERY.CAPTURE_SIZE)
		record["sheet"] = id + "_six_views.png"
		if sheet.save_png(output.path_join(record.sheet)) != OK:
			failed = true
		records.append(record)
		print("OBJECT CAPTURE: %s (%d/%d)" % [id, records.size(), objects.size() if selected.is_empty() else selected.size()])
	var gallery_ui_saved := await _capture_gallery_ui(gallery, output)
	failed = failed or not gallery_ui_saved
	if is_instance_valid(gallery):
		gallery.free()
	await process_frame
	var preserved := Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot
	failed = failed or not preserved
	var sources_unchanged := sources == EVIDENCE.collect()
	if selected.is_empty() and not sources_unchanged:
		push_error("Production art sources changed during the complete catalog capture; freeze sources and use a new iteration.")
		failed = true
	var manifest := {"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "capture_kind": "Actual production geometry in the same isolated six-view viewport as the in-game test-room gallery", "desktop_capture": false, "external_input": false, "gallery_ui": "gallery_ui.png" if gallery_ui_saved else "", "expedition_and_cursor_preserved": preserved, "catalog_count": objects.size(), "captured_count": records.size(), "complete_catalog": selected.is_empty() and records.size() == objects.size() and not failed, "view_order": GALLERY.VIEWS, "view_axes": {"front": "-Z", "back": "+Z", "left": "-X", "right": "+X", "top": "+Y", "bottom": "-Y"}, "lighting": {"ambient_energy": 0.48, "key_energy": 1.15, "fill_energy": 0.48, "rim_energy": 0.32, "background": "#171a1a", "tonemap": "filmic"}, "sources": sources, "objects": records}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	manifest["source_files_unchanged"] = sources_unchanged
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("DARK FANTASY GALLERY PREVIEW %s: %d production objects, six real-renderer directions, expedition and cursor %s; %s" % ["FAIL" if failed else "PASS", records.size(), "preserved" if preserved else "CHANGED", output])
	quit(1 if failed else 0)


func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _capture_gallery_ui(gallery: Control, output: String) -> bool:
	# Return to the same first object the real gallery opens with; a final thin
	# floor-pad entry otherwise makes the front-facing UI evidence look blank.
	if not gallery.select_object(str(CATALOG.entries()[0].id)):
		return false
	var ui := SubViewport.new()
	ui.size = Vector2i(1280, 720)
	ui.gui_disable_input = true
	ui.physics_object_picking = false
	ui.audio_listener_enable_2d = false
	ui.audio_listener_enable_3d = false
	ui.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(ui)
	var font_theme := Theme.new()
	var font_variation := FontVariation.new()
	font_variation.base_font = load("res://assets/fonts/NotoSansKR-Variable.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	font_theme.default_font = font_variation
	font_theme.default_font_size = 16
	gallery.theme = font_theme
	gallery.reparent(ui, false)
	gallery.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gallery.set_view("front")
	for frame in range(12):
		await process_frame
	RenderingServer.force_draw(false)
	var rendered := ui.get_texture().get_image()
	var saved := rendered != null and not rendered.is_empty() and rendered.save_png(output.path_join("gallery_ui.png")) == OK
	ui.free()
	return saved
