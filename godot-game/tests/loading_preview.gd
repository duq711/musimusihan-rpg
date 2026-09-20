extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the reviewed embedded loading preview runner.")
		quit(2)
		return
	var iteration := OS.get_environment("LOADING_QA_ITERATION")
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	var output := "res://artifacts/visual_qa/loading/".path_join(iteration)
	if DirAccess.dir_exists_absolute(output):
		push_error("Preserve existing captures; choose a new iteration.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	root.gui_disable_input = true
	AudioServer.set_bus_mute(0, true)
	var hashes := _source_hashes()
	var captures: Array[Dictionary] = []
	var failures: Array[String] = []
	for shot in [
		{"id":"01_boot", "size":Vector2i(1280,720), "scene":"main_menu.tscn"},
		{"id":"02_hideout_small", "size":Vector2i(960,540), "scene":"hideout.tscn"},
		{"id":"03_dungeon_wide", "size":Vector2i(1920,1080), "scene":"main.tscn"},
		{"id":"04_failure", "size":Vector2i(1280,720), "scene":"missing.tscn"},
	]:
		var viewport := SubViewport.new()
		viewport.size = shot.size
		viewport.gui_disable_input = true
		viewport.physics_object_picking = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var loading := SanctuaryLoadingScreen.new()
		loading.auto_start = false
		loading.configure("res://" + shot.scene, "장면 제목", "긴 전환 설명은 정상 로딩에 표시하지 않습니다.", "상태")
		viewport.add_child(loading)
		loading.set_process(false)
		loading._process(1.2)
		loading._set_progress(0.47)
		if shot.id == "04_failure": loading._report_failure(ERR_CANT_OPEN)
		for frame in 4: await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
		for control in [loading.title_label, loading.activity_label, loading.detail_label, loading.progress_bar]:
			if not bounds.encloses(control.get_global_rect()): failures.append(shot.id + ": control exceeds viewport: " + control.name)
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var file := output.path_join(shot.id + ".png")
		if pixels == null or pixels.is_empty() or pixels.save_png(file) != OK: failures.append("Could not save " + file)
		captures.append({"image":shot.id + ".png", "size":[viewport.size.x,viewport.size.y], "destination":loading.title_label.text, "activity":loading.activity_label.text, "progress":loading.progress_bar.value})
		viewport.free()
		await process_frame
	var preserved := original == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode
	if not preserved: failures.append("Session or cursor changed")
	if hashes != _source_hashes(): failures.append("Sources changed during capture")
	var manifest := {"renderer":RenderingServer.get_current_rendering_driver_name(), "display":DisplayServer.get_name(), "preserved":preserved, "source_sha256":hashes, "captures":captures, "failures":failures}
	var record := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	record.store_string(JSON.stringify(manifest, "\t") + "\n")
	for failure in failures: push_error(failure)
	print("LOADING PREVIEW %s: %d captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), ProjectSettings.globalize_path(output)])
	quit(0 if failures.is_empty() else 1)

func _source_hashes() -> Dictionary:
	var hashes := {}
	for path in ["scripts/loading_screen.gd", "shaders/loading_backdrop.gdshader", "assets/ui/main_menu_background.png", "assets/fonts/NotoSerifKR-Variable.ttf", "tests/loading_preview.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes
