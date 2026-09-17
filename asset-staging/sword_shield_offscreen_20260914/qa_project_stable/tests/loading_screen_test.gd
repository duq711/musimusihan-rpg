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
	await _test_real_main_menu_threaded_transition()
	_finish()


func _test_loading_interface_and_activity() -> void:
	var loading := SanctuaryLoadingScreen.new()
	loading.auto_start = false
	root.add_child(loading)

	_check(loading.process_mode == Node.PROCESS_MODE_ALWAYS, "loading screen must keep processing while the SceneTree is paused")
	_check(loading.mouse_filter == Control.MOUSE_FILTER_STOP, "loading screen must block input from reaching the scene behind it")
	_check(loading.loading_spinner != null and loading.loading_spinner.name == "MovingLoadingSigil", "loading screen must expose the moving sigil")
	_check(loading.loading_spinner != null and loading.loading_spinner.get_child_count() >= 12, "moving sigil must contain visible asymmetric marks")
	_check(loading.elapsed_label != null and loading.elapsed_label.text.contains("00초"), "loading screen must expose an elapsed-time readout")
	_check(loading.progress_bar != null and loading.progress_bar.min_value == 0.0 and loading.progress_bar.max_value == 100.0, "loading progress must use a zero-to-one-hundred range")
	_check(loading.progress_label != null and loading.progress_label.text == "0%", "loading progress must start at zero percent")
	_check(loading.activity_label != null and not loading.activity_label.text.is_empty(), "loading screen must explain that work is still continuing")

	var previous_rotation := loading.loading_spinner.rotation
	for frame_index in range(6):
		loading._process(0.1)
		var current_rotation := loading.loading_spinner.rotation
		_check(not is_equal_approx(current_rotation, previous_rotation), "moving sigil must rotate on every processed frame")
		previous_rotation = current_rotation
	loading._process(0.5)
	_check(loading.elapsed_label.text.contains("01초"), "elapsed-time readout must advance after one second")

	loading._set_progress(0.42)
	_check(is_equal_approx(loading.progress_bar.value, 42.0), "reported progress must update the visible progress bar")
	_check(loading.progress_label.text == "42%", "reported progress must update the visible percentage")

	var paused_rotation := loading.loading_spinner.rotation
	paused = true
	await create_timer(0.06, true).timeout
	paused = false
	_check(not is_equal_approx(loading.loading_spinner.rotation, paused_rotation), "PROCESS_MODE_ALWAYS must keep the moving sigil alive while the SceneTree is paused")

	root.remove_child(loading)
	loading.free()


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
	_check(loading.is_visible_in_tree() and loading.loading_spinner.is_visible_in_tree(), "boot loading UI and moving sigil must be visible during the request")

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
		print("LOADING SCREEN TEST PASS: always-active UI, per-frame motion, elapsed time, progress, and real threaded main-menu transition")
		quit(0)
		return
	for failure in failures:
		push_error("LOADING SCREEN TEST FAIL: %s" % failure)
	quit(1)
