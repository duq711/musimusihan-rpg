extends SceneTree

const SCENE_TRANSITION_TIMEOUT_MSEC := 30000

var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(str(ProjectSettings.get_setting("application/run/main_scene", "")) == "res://boot.tscn", "project must boot through the threaded loading scene")
	_check(ResourceLoader.exists("res://boot.tscn", "PackedScene"), "threaded loading boot scene must exist")
	_check(ResourceLoader.exists(MainMenu.TEST_ROOM_SCENE_PATH, "PackedScene"), "test room scene must exist")
	_check(ResourceLoader.exists("res://assets/ui/main_menu_background.png"), "main menu background asset must exist")
	_check(ResourceLoader.exists(MainMenu.UI_FONT_PATH, "Font"), "packaged Noto Sans KR UI font must exist")
	_check(FileAccess.file_exists("res://assets/fonts/OFL-NotoSansKR.txt"), "Noto Sans KR OFL license must ship with the font source")
	var ui_resource := load(MainMenu.UI_FONT_PATH) as Font
	_check(ui_resource != null, "the packaged Korean UI font must load as a Font resource")
	_check_font_glyphs(ui_resource, "어둠 속 마지막 원정 잔향의 성소 검은 성물실 게임 시작 테스트룸 설정 조작법 정보 게임 종료 버전 빌드 음량 0123456789%·", "Korean UI font")

	var packed := load("res://main_menu.tscn") as PackedScene
	_check(packed != null, "main menu scene must load")
	if packed == null:
		_finish()
		return

	var menu := packed.instantiate() as MainMenu
	root.add_child(menu)
	current_scene = menu
	await process_frame
	_check_menu_font_contract(menu)
	_check_korean_only_text(menu)
	_check_menu_button_layout(menu)

	_check(not paused, "main menu must clear stale pause state")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "main menu must release the mouse")
	_check(menu.new_game_button != null and menu.new_game_button.name == "StartGameButton", "main menu must expose the start-game button")
	_check(menu.new_game_button != null and menu.new_game_button.text == "게임 시작", "start-game button must use the requested Korean label")
	_check(menu.test_room_button != null and menu.test_room_button.name == "TestRoomButton", "main menu must expose the test-room button")
	_check(menu.settings_button != null and menu.controls_button != null and menu.info_button != null and menu.quit_button != null, "main menu must expose settings, controls, information, and quit")
	_check(menu.main_buttons.size() == 6, "main menu must contain six primary actions including the test room")
	_check(_main_button_names(menu) == ["StartGameButton", "TestRoomButton", "SettingsButton", "ControlsButton", "InfoButton", "QuitButton"], "main menu primary actions must include a directly accessible test room")
	_check(_main_button_texts(menu) == ["게임 시작", "테스트룸", "설정", "조작법", "정보", "게임 종료"], "main menu primary actions must use the requested Korean labels")
	_check(menu.find_child("SanctuaryDoorButton", true, false) == null, "the sanctuary door must not appear on the boot menu")
	_check(menu.find_child("DestinationPanel", true, false) == null, "the destination map must not appear on the boot menu")
	_check(not menu.modal_scrim.visible and menu.current_panel == null, "main menu must start without a modal")
	_check(not menu.settings_panel.visible and not menu.controls_panel.visible and not menu.info_panel.visible and not menu.quit_panel.visible, "all main-menu auxiliary panels must start hidden")

	menu.settings_button.pressed.emit()
	_check(menu.modal_scrim.visible and menu.settings_panel.visible and menu.current_panel == menu.settings_panel, "settings button must open only the settings panel")
	_check(not menu.controls_panel.visible and not menu.info_panel.visible and not menu.quit_panel.visible, "settings panel must be modal-exclusive")
	for button in menu.main_buttons:
		_check(button.disabled, "an open modal must disable every background menu button")
		_check(button.focus_mode == Control.FOCUS_NONE, "an open modal must remove every background button from keyboard focus traversal")
	for tab_index in range(6):
		_send_tab()
		await process_frame
		var focus_owner := menu.get_viewport().gui_get_focus_owner()
		var background_button_focused := false
		for button in menu.main_buttons:
			if focus_owner == button:
				background_button_focused = true
		_check(focus_owner != null and not background_button_focused, "Tab focus must remain inside the active modal")
	_send_escape(menu)
	_check(not menu.modal_scrim.visible and menu.current_panel == null, "Escape must close an auxiliary panel")
	for button in menu.main_buttons:
		_check(not button.disabled, "closing a modal must restore every main menu button")
		_check(button.focus_mode == Control.FOCUS_ALL, "closing a modal must restore keyboard focus traversal")

	menu.controls_button.pressed.emit()
	_check(menu.controls_panel.visible and menu.current_panel == menu.controls_panel, "controls button must open the controls panel")
	menu._close_modal()
	menu.info_button.pressed.emit()
	_check(menu.info_panel.visible and menu.current_panel == menu.info_panel, "info button must open the info panel")
	var skeleton_credit := menu.info_panel.find_child("BodyParts3DCredit", true, false) as Label
	_check(skeleton_credit != null and skeleton_credit.text.contains("BodyParts3D") and skeleton_credit.text.contains("CC Attribution 4.0"), "info panel must ship the required BodyParts3D attribution")
	menu._close_modal()

	menu.quit_button.pressed.emit()
	_check(menu.quit_panel.visible and menu.current_panel == menu.quit_panel, "quit button must request confirmation")
	_check(menu.quit_confirm_button != null and menu.quit_cancel_button != null, "quit confirmation must expose confirm and cancel actions")
	menu.quit_cancel_button.pressed.emit()
	_check(not menu.modal_scrim.visible and menu.current_panel == null, "quit cancellation must return to the main buttons")

	ExpeditionSession.begin_new_journey()
	var stale_inventory := ExpeditionSession.get_inventory()
	ExpeditionSession.crowns = 1
	(ExpeditionSession.merchant_stock["linen_bandage"] as Dictionary)["quantity"] = 0
	menu.transition_duration = 0.0
	menu.new_game_button.pressed.emit()
	var hideout_transition := await _wait_for_scene("res://hideout.tscn")
	_check(bool(hideout_transition.get("saw_loading", false)), "game start must visibly pass through the animated loading screen")
	_check(current_scene is SanctuaryHideout, "game start must transition to the sanctuary hideout")
	_check(current_scene != null and current_scene.scene_file_path == "res://hideout.tscn", "game start must load hideout.tscn")
	_check(ExpeditionSession.journey_started, "game start must initialize the shared expedition session")
	_check(ExpeditionSession.get_inventory() != stale_inventory, "game start must replace any stale expedition inventory")
	_check(ExpeditionSession.crowns == ExpeditionSession.STARTING_CROWNS, "game start must reset expedition currency")
	_check(ExpeditionSession.get_stock_quantity("linen_bandage") == int((ExpeditionSession.DEFAULT_MERCHANT_STOCK["linen_bandage"] as Dictionary)["quantity"]), "game start must reset merchant stock")

	var menu_error := change_scene_to_file("res://main_menu.tscn")
	_check(menu_error == OK, "test-room navigation must return to the main menu")
	await _wait_for_scene("res://main_menu.tscn")
	menu = current_scene as MainMenu
	if menu != null:
		var journey_inventory := ExpeditionSession.get_inventory()
		ExpeditionSession.crowns = 17
		menu.transition_duration = 0.0
		menu.test_room_button.pressed.emit()
		_check(menu.transitioning, "test-room entry must lock scene navigation")
		_check(ExpeditionSession.get_inventory() == journey_inventory and ExpeditionSession.crowns == 17, "test-room entry must not reset the existing expedition before the room can preserve it")
		for button in menu.main_buttons:
			_check(button.disabled, "test-room entry must disable every main menu button")
		var test_room_transition := await _wait_for_scene(MainMenu.TEST_ROOM_SCENE_PATH)
		_check(bool(test_room_transition.get("saw_loading", false)), "test-room entry must visibly pass through the animated loading screen")
		_check(current_scene != null and current_scene.scene_file_path == MainMenu.TEST_ROOM_SCENE_PATH, "test-room button must load test_room.tscn")
	else:
		_check(false, "test-room navigation requires a main-menu instance")

	_finish()


func _wait_for_scene(scene_path: String, timeout_msec := SCENE_TRANSITION_TIMEOUT_MSEC) -> Dictionary:
	var saw_loading := _loading_screen_is_present()
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		saw_loading = saw_loading or _loading_screen_is_present()
		var scene := current_scene
		if scene != null and scene.scene_file_path == scene_path and not _loading_screen_is_present():
			return {"reached": true, "saw_loading": saw_loading}
		await process_frame
	_check(false, "scene transition to %s must finish and dismiss its loading overlay before the timeout" % scene_path)
	return {"reached": false, "saw_loading": saw_loading}


func _loading_screen_is_present() -> bool:
	if current_scene is SanctuaryLoadingScreen:
		return true
	for node in root.find_children("*", "", true, false):
		if node is SanctuaryLoadingScreen:
			return true
	return false


func _main_button_names(menu: MainMenu) -> Array[String]:
	var names: Array[String] = []
	for button in menu.main_buttons:
		names.append(str(button.name))
	return names


func _main_button_texts(menu: MainMenu) -> Array[String]:
	var labels: Array[String] = []
	for button in menu.main_buttons:
		labels.append(button.text)
	return labels


func _check_menu_button_layout(menu: MainMenu) -> void:
	var holder := menu.get_node("MainButtonColumn") as Control
	var scrim := menu.get_node("SanctuaryMenuScrim") as Control
	var previous_bottom := holder.global_position.y
	for button in menu.main_buttons:
		var button_rect := button.get_global_rect()
		_check(holder.get_global_rect().encloses(button_rect), "%s must remain inside the main button column" % button.name)
		_check(scrim.get_global_rect().encloses(button_rect), "%s must remain on the legible menu backdrop" % button.name)
		_check(button_rect.position.y >= previous_bottom, "%s must not overlap the preceding menu action" % button.name)
		_check(button.get_combined_minimum_size().x <= button.size.x + 1.0, "%s label must fit the menu width" % button.name)
		previous_bottom = button_rect.end.y


func _send_escape(menu: MainMenu) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	menu._unhandled_input(event)


func _send_tab() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	Input.parse_input_event(event)


func _check_font_glyphs(font: Font, sample: String, role: String) -> void:
	if font == null:
		return
	for index in range(sample.length()):
		var codepoint := sample.unicode_at(index)
		if codepoint == 32:
			continue
		_check(font.has_char(codepoint), "%s must contain U+%04X" % [role, codepoint])


func _check_menu_font_contract(menu: MainMenu) -> void:
	_check(menu.theme != null and _font_source_path(menu.theme.default_font) == MainMenu.UI_FONT_PATH, "main menu theme must resolve to the packaged Korean UI font")
	for descendant in menu.find_children("*", "", true, false):
		if not (descendant is Label or descendant is Button):
			continue
		var control := descendant as Control
		_check(_font_source_path(control.get_theme_font("font")) == MainMenu.UI_FONT_PATH, "%s must resolve the packaged Korean font" % control.name)
		if control is Label and (control as Label).autowrap_mode == TextServer.AUTOWRAP_OFF:
			var minimum := control.get_combined_minimum_size()
			_check(minimum.x <= control.size.x + 1.0 and minimum.y <= control.size.y + 1.0, "%s text must fit its authored bounds" % control.name)


func _check_korean_only_text(menu: MainMenu) -> void:
	for descendant in menu.find_children("*", "", true, false):
		var text_value := ""
		if descendant is Label:
			text_value = (descendant as Label).text
		elif descendant is Button:
			text_value = (descendant as Button).text
		else:
			continue
		if descendant.name == "BodyParts3DCredit":
			continue
		for index in range(text_value.length()):
			var codepoint := text_value.unicode_at(index)
			_check(not (codepoint >= 65 and codepoint <= 90) and not (codepoint >= 97 and codepoint <= 122), "%s must not expose English text" % descendant.name)


func _font_source_path(font: Font) -> String:
	var current := font
	while current is FontVariation:
		current = (current as FontVariation).base_font
	return current.resource_path if current != null else ""


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	paused = false
	if failures.is_empty():
		print("MAIN MENU TEST PASS: menu actions, modal navigation, fresh session, hideout and test-room transitions")
		quit(0)
		return
	for failure in failures:
		push_error("MAIN MENU TEST FAIL: %s" % failure)
	quit(1)
