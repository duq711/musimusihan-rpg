extends SceneTree

const THREADED_LOAD_TIMEOUT_MSEC := 30000

var failures: Array[String] = []
var threaded_error_code := OK


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(ResourceLoader.exists("res://boot.tscn", "PackedScene"), "boot loading scene must exist")
	_check(ResourceLoader.exists("res://main_menu.tscn", "PackedScene"), "main menu threaded-load target must exist")
	await _test_loading_interface_and_activity()
	await _test_compact_layout()
	await _test_real_main_menu_threaded_transition()
	_finish()


func _test_loading_interface_and_activity() -> void:
	var loading := SanctuaryLoadingScreen.new()
	loading.auto_start = false
	root.add_child(loading)

	_check(loading.process_mode == Node.PROCESS_MODE_ALWAYS, "loading screen must keep processing while the SceneTree is paused")
	_check(loading.mouse_filter == Control.MOUSE_FILTER_STOP, "loading screen must block input from reaching the scene behind it")
	_check(loading.backdrop != null and loading.backdrop.texture != null, "loading screen must display the existing sanctuary artwork")
	_check(loading.loading_spinner != null and loading.loading_spinner.name == "LoadingActivityRing", "loading screen must expose a small activity ring")
	_check(loading.find_child("LoadingCoreDiamond", true, false) == null and loading.find_child("LoadingCore", true, false) == null, "the activity ring must not retain the old ornamental core")
	_check(loading.find_child("LoadingCard", true, false) == null and loading.find_child("LoadingFooterHint", true, false) == null, "the artwork must remain free of the old card and reassurance footer")
	_check(loading.find_child("LoadingElapsed", true, false) == null and loading.find_child("LoadingPercent", true, false) == null, "normal loading must not show elapsed-time or percentage readouts")
	_check(loading.progress_bar != null and loading.progress_bar.min_value == 0.0 and loading.progress_bar.max_value == 100.0, "loading progress must use a zero-to-one-hundred range")
	_check(loading.progress_bar.is_visible_in_tree() and is_zero_approx(loading.progress_bar.value), "the understated progress bar must start empty")
	_check(loading.title_label != null and not loading.title_label.text.is_empty(), "loading screen must identify the destination")
	_check(loading.detail_label != null and not loading.detail_label.text.is_empty(), "loading screen must provide a brief gameplay tip")
	_check(loading.activity_label != null and not loading.activity_label.text.is_empty(), "loading screen must retain a readable loading status")

	var previous_rotation := loading.loading_spinner.rotation
	for frame_index in range(6):
		loading._process(0.1)
		var current_rotation := loading.loading_spinner.rotation
		_check(not is_equal_approx(current_rotation, previous_rotation), "the activity ring must rotate on every processed frame")
		previous_rotation = current_rotation
	loading._process(0.5)
	_check(is_zero_approx(loading.progress_bar.value), "elapsed time must not invent loading progress")

	loading._set_progress(0.42)
	_check(is_equal_approx(loading.progress_bar.value, 42.0), "reported progress must update the visible progress bar")
	loading._process(1.0)
	_check(is_equal_approx(loading.progress_bar.value, 42.0), "activity animation must leave reported progress unchanged")

	var paused_rotation := loading.loading_spinner.rotation
	paused = true
	await create_timer(0.06, true).timeout
	paused = false
	_check(not is_equal_approx(loading.loading_spinner.rotation, paused_rotation), "PROCESS_MODE_ALWAYS must keep the activity ring alive while the SceneTree is paused")

	var error_codes: Array[int] = []
	loading.load_failed.connect(func(code: int) -> void: error_codes.append(code))
	loading._report_failure(ERR_CANT_OPEN)
	_check(error_codes == [ERR_CANT_OPEN], "loading failures must emit the original error code once")
	_check(loading._request_failed and not loading._request_started and not loading._transition_committed, "failed loading must stop without committing a scene change")
	_check(loading.title_label.text.contains("불러오지 못") and not loading.detail_label.text.is_empty(), "failure must replace the destination and tip with a readable explanation")
	_check(loading.activity_label.text.contains(str(ERR_CANT_OPEN)), "failure status must retain the diagnostic error code")
	var failure_status := loading.activity_label.text
	loading._process(0.5)
	_check(loading.activity_label.text == failure_status, "normal activity updates must not overwrite an error")
	loading.configure("res://main_menu.tscn", "성소", "메인 메뉴", "불러오는 중", 0.0)
	loading._reset_loading_state()
	_check(not loading._request_failed and not loading._request_started and not loading._waiting_for_scene, "reset must clear error and transition state for another request")
	_check(loading.title_label.text == "잔향의 성소" and not loading.detail_label.text.is_empty(), "reset must restore the destination and normal gameplay tip")
	_check(is_zero_approx(loading.progress_bar.value), "reset must clear previous progress")

	root.remove_child(loading)
	loading.free()


func _test_compact_layout() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var loading := SanctuaryLoadingScreen.new()
	loading.auto_start = false
	viewport.add_child(loading)
	await process_frame
	await process_frame
	var visible_area := Rect2(Vector2.ZERO, Vector2(viewport.size))
	_check(loading.backdrop.get_global_rect().encloses(visible_area), "artwork must cover the complete 960 by 540 viewport")
	for control in [loading.title_label, loading.detail_label, loading.activity_label, loading.progress_bar]:
		_check(visible_area.encloses(control.get_global_rect()), "%s must fit inside the compact viewport" % control.name)
		_check(control.is_visible_in_tree(), "%s must remain visible at compact resolution" % control.name)
	viewport.queue_free()
	await process_frame


func _test_real_main_menu_threaded_transition() -> void:
	var packed := load("res://boot.tscn") as PackedScene
	_check(packed != null, "boot loading scene must load as a PackedScene")
	if packed == null:
		return

	var loading := packed.instantiate() as SanctuaryLoadingScreen
	_check(loading != null, "boot scene must instantiate as SanctuaryLoadingScreen")
	if loading == null:
		return
	loading.load_failed.connect(_on_threaded_load_failed)
	root.add_child(loading)
	current_scene = loading

	_check(loading.target_scene_path == "res://main_menu.tscn", "boot loader must target the main menu")
	_check(loading._request_started and not loading._request_failed, "boot loader must start a real threaded resource request")
	_check(loading.is_visible_in_tree() and loading.loading_spinner.is_visible_in_tree(), "boot loading UI and activity ring must be visible during the request")

	var saw_loading_screen := true
	var last_progress := -1.0
	var deadline := Time.get_ticks_msec() + THREADED_LOAD_TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline and threaded_error_code == OK:
		var scene := current_scene
		if scene != null and scene.scene_file_path == "res://main_menu.tscn":
			break
		await process_frame
		if current_scene is SanctuaryLoadingScreen:
			saw_loading_screen = true
			var active_loading := current_scene as SanctuaryLoadingScreen
			if is_instance_valid(active_loading):
				var current_progress := active_loading.progress_bar.value
				_check(current_progress >= 0.0 and current_progress <= 100.0, "threaded loading progress must stay inside its visible range")
				_check(last_progress < 0.0 or current_progress + 0.001 >= last_progress, "threaded loading progress must not move backwards")
				last_progress = maxf(last_progress, current_progress)

	_check(threaded_error_code == OK, "real main-menu threaded load must not report an error (code %d)" % threaded_error_code)
	_check(saw_loading_screen, "boot must expose the loading screen before the main menu")
	_check(current_scene != null and current_scene.scene_file_path == "res://main_menu.tscn", "real threaded request must finish at main_menu.tscn before the timeout")
	_check(current_scene is MainMenu, "threaded main-menu resource must instantiate as MainMenu")
	if current_scene is MainMenu:
		var menu := current_scene as MainMenu
		_check(menu.new_game_button != null and menu.new_game_button.text == "게임 시작", "threaded transition must deliver a ready main menu")


func _on_threaded_load_failed(error_code: int) -> void:
	threaded_error_code = error_code


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("LOADING SCREEN TEST PASS: artwork, compact layout, paused activity, honest progress, error/reset, and real threaded main-menu transition")
		quit(0)
		return
	for failure in failures:
		push_error("LOADING SCREEN TEST FAIL: %s" % failure)
	quit(1)
