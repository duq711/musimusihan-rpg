extends Control
class_name MainMenu

const GAME_SCENE_PATH := "res://main.tscn"
const CAVE_SCENE_PATH := "res://cave_dungeon.tscn"
const MERCHANT_SCENE_PATH := "res://merchant.tscn"
const HIDEOUT_SCENE_PATH := "res://hideout.tscn"
const TEST_ROOM_SCENE_PATH := "res://test_room.tscn"
const SETTINGS_PATH := "user://settings.cfg"
const BACKGROUND_TEXTURE := preload("res://assets/ui/main_menu_background.png")
const DESTINATION_MAP_TEXTURE := preload("res://assets/ui/sanctuary_route_map.png")
const UI_FONT_PATH := "res://assets/fonts/NotoSansKR-Variable.ttf"
const UI_FONT_FILE: FontFile = preload(UI_FONT_PATH)
const LOADING_SCREEN_SCRIPT := preload("res://scripts/loading_screen.gd")

const COLOR_IVORY := Color(0.92, 0.91, 0.88)
const COLOR_TEXT := Color(0.74, 0.77, 0.74)
const COLOR_MUTED := Color(0.46, 0.5, 0.48)
const COLOR_TEAL := Color(0.51, 0.61, 0.58)
const COLOR_GOLD := Color(0.74, 0.55, 0.29)
const COLOR_DANGER := Color(0.56, 0.25, 0.22)

var transition_duration := 0.25
var transitioning := false
var main_buttons: Array[Button] = []
var ui_kicker_font: FontVariation
var ui_title_font: FontVariation
var ui_font: FontVariation
var ui_medium_font: FontVariation
var ui_spaced_font: FontVariation
var ui_caption_font: FontVariation

var new_game_button: Button
var test_room_button: Button
var door_button: Button
var settings_button: Button
var controls_button: Button
var info_button: Button
var quit_button: Button
var modal_scrim: ColorRect
var settings_panel: Panel
var controls_panel: Panel
var info_panel: Panel
var quit_panel: Panel
var destination_panel: Panel
var destination_dungeon_button: Button
var destination_cave_button: Button
var destination_merchant_button: Button
var destination_cancel_button: Button
var quit_confirm_button: Button
var quit_cancel_button: Button
var volume_slider: HSlider
var volume_value_label: Label
var fullscreen_toggle: CheckButton
var footer_status_label: Label
var fade_layer: ColorRect
var loading_screen: SanctuaryLoadingScreen
var current_panel: Control
var _return_focus: Control


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_fonts()
	_build_interface()
	_load_settings()
	call_deferred("_focus_default")


func _build_fonts() -> void:
	ui_font = _font_variation(UI_FONT_FILE, 400, 0)
	ui_medium_font = _font_variation(UI_FONT_FILE, 500, 0)
	ui_spaced_font = _font_variation(UI_FONT_FILE, 400, 1)
	ui_caption_font = _font_variation(UI_FONT_FILE, 350, 1)
	ui_kicker_font = _font_variation(UI_FONT_FILE, 400, 3)
	ui_title_font = _font_variation(UI_FONT_FILE, 500, 4)
	var menu_theme := Theme.new()
	menu_theme.default_font = ui_font
	menu_theme.default_font_size = 13
	theme = menu_theme


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		if current_panel != null:
			_close_modal()
		else:
			_open_quit_confirmation()
		get_viewport().set_input_as_handled()
		return
	if current_panel == null and event.keycode in [KEY_W, KEY_UP]:
		_focus_relative(-1)
		get_viewport().set_input_as_handled()
	elif current_panel == null and event.keycode in [KEY_S, KEY_DOWN]:
		_focus_relative(1)
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	var background := TextureRect.new()
	background.name = "SanctuaryBackground"
	background.texture = BACKGROUND_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var darkness := ColorRect.new()
	darkness.name = "BackgroundDarkness"
	darkness.color = Color(0.005, 0.008, 0.01, 0.28)
	darkness.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	darkness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(darkness)

	var center_scrim := Panel.new()
	center_scrim.name = "SanctuaryMenuScrim"
	center_scrim.position = Vector2(34, 100)
	center_scrim.size = Vector2(314, 420)
	center_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_scrim.add_theme_stylebox_override("panel", _panel_style(Color(0.003, 0.005, 0.006, 0.34), Color.TRANSPARENT, 0, 0))
	add_child(center_scrim)

	var kicker := _label("어둠 속 마지막 원정", 11, Color(0.77, 0.79, 0.76))
	kicker.name = "LogoKicker"
	kicker.position = Vector2(64, 132)
	kicker.size = Vector2(300, 22)
	kicker.add_theme_font_override("font", ui_kicker_font)
	kicker.add_theme_constant_override("outline_size", 1)
	kicker.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(kicker)

	var title := _label("잔향의 성소", 44, COLOR_IVORY)
	title.name = "GameTitle"
	title.position = Vector2(58, 152)
	title.size = Vector2(360, 64)
	title.add_theme_font_override("font", ui_title_font)
	title.add_theme_constant_override("outline_size", 1)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_constant_override("shadow_outline_size", 3)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.94))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
	add_child(title)

	var subtitle := _label("검은 성물실", 13, Color(0.6, 0.63, 0.6))
	subtitle.name = "GameSubtitle"
	subtitle.position = Vector2(62, 216)
	subtitle.size = Vector2(300, 24)
	subtitle.add_theme_font_override("font", ui_spaced_font)
	subtitle.add_theme_constant_override("outline_size", 1)
	subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.88))
	add_child(subtitle)

	_build_main_buttons()
	_build_footer()
	_build_modals()

	fade_layer = ColorRect.new()
	fade_layer.name = "SceneFade"
	fade_layer.color = Color(0, 0, 0, 0)
	fade_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.z_index = 100
	add_child(fade_layer)


func _build_main_buttons() -> void:
	var menu_holder := Control.new()
	menu_holder.name = "MainButtonColumn"
	menu_holder.position = Vector2(62, 276)
	menu_holder.size = Vector2(220, 224)
	add_child(menu_holder)

	new_game_button = _menu_button("게임 시작", "StartGameButton")
	test_room_button = _menu_button("테스트룸", "TestRoomButton")
	test_room_button.tooltip_text = "원정 기록에 영향을 주지 않고 기능을 자유롭게 시험합니다."
	settings_button = _menu_button("설정", "SettingsButton")
	controls_button = _menu_button("조작법", "ControlsButton")
	info_button = _menu_button("정보", "InfoButton")
	quit_button = _menu_button("게임 종료", "QuitButton")
	main_buttons = [new_game_button, test_room_button, settings_button, controls_button, info_button, quit_button]

	for index in range(main_buttons.size()):
		var button := main_buttons[index]
		button.position = Vector2(0, index * 38)
		menu_holder.add_child(button)

	new_game_button.pressed.connect(_start_game)
	test_room_button.pressed.connect(_open_test_room)
	settings_button.pressed.connect(_open_settings)
	controls_button.pressed.connect(_open_controls)
	info_button.pressed.connect(_open_info)
	quit_button.pressed.connect(_open_quit_confirmation)


func _build_sanctuary_door() -> void:
	door_button = Button.new()
	door_button.name = "SanctuaryDoorButton"
	door_button.position = Vector2(486, 276)
	door_button.size = Vector2(308, 326)
	door_button.text = ""
	door_button.tooltip_text = "문을 열어 성소 이동 지도를 봅니다."
	door_button.focus_mode = Control.FOCUS_ALL
	door_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	door_button.add_theme_stylebox_override("normal", _panel_style(Color(0.01, 0.025, 0.025, 0.03), Color(0.43, 0.57, 0.54, 0.18), 1, 3))
	door_button.add_theme_stylebox_override("hover", _panel_style(Color(0.08, 0.16, 0.15, 0.18), Color(0.67, 0.78, 0.73, 0.88), 2, 3))
	door_button.add_theme_stylebox_override("focus", _panel_style(Color(0.08, 0.16, 0.15, 0.18), Color(0.67, 0.78, 0.73, 0.88), 2, 3))
	door_button.add_theme_stylebox_override("pressed", _panel_style(Color(0.1, 0.18, 0.17, 0.26), Color(0.82, 0.86, 0.8, 0.96), 2, 3))
	door_button.add_theme_stylebox_override("disabled", _panel_style(Color.TRANSPARENT, Color(0.2, 0.24, 0.23, 0.12), 1, 3))
	door_button.pressed.connect(_open_destination_map)
	add_child(door_button)

	var marker := _label("◇", 34, Color(0.74, 0.82, 0.77, 0.92))
	marker.name = "SanctuaryDoorMarker"
	marker.position = Vector2(119, 102)
	marker.size = Vector2(70, 54)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_theme_constant_override("outline_size", 5)
	marker.add_theme_color_override("font_outline_color", Color(0.03, 0.08, 0.075, 0.9))
	door_button.add_child(marker)

	var prompt := _label("문 열기\n이동 지도", 13, COLOR_IVORY)
	prompt.name = "SanctuaryDoorPrompt"
	prompt.position = Vector2(54, 242)
	prompt.size = Vector2(200, 54)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_font_override("font", ui_spaced_font)
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	door_button.add_child(prompt)


func _build_footer() -> void:
	var footer := Panel.new()
	footer.name = "FooterBar"
	footer.anchor_top = 1.0
	footer.anchor_right = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -64
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_theme_stylebox_override("panel", _panel_style(Color(0.002, 0.004, 0.005, 0.84), Color(0.22, 0.27, 0.26, 0.62), 1, 0))
	add_child(footer)

	footer_status_label = _label("전체 화면  ·  위아래 이동  ·  선택  ·  뒤로", 10, COLOR_MUTED)
	footer_status_label.name = "FooterStatus"
	footer_status_label.position = Vector2(28, 21)
	footer_status_label.size = Vector2(760, 20)
	footer_status_label.add_theme_font_override("font", ui_caption_font)
	footer.add_child(footer_status_label)

	var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var version_label := _label("버전 %s" % version, 10, COLOR_MUTED)
	version_label.name = "VersionLabel"
	version_label.position = Vector2(970, 21)
	version_label.size = Vector2(282, 20)
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version_label.add_theme_font_override("font", ui_caption_font)
	footer.add_child(version_label)


func _build_modals() -> void:
	modal_scrim = ColorRect.new()
	modal_scrim.name = "ModalScrim"
	modal_scrim.color = Color(0.002, 0.004, 0.005, 0.78)
	modal_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_scrim.z_index = 50
	modal_scrim.visible = false
	add_child(modal_scrim)

	settings_panel = _build_settings_panel()
	controls_panel = _build_controls_panel()
	info_panel = _build_info_panel()
	quit_panel = _build_quit_panel()
	modal_scrim.add_child(settings_panel)
	modal_scrim.add_child(controls_panel)
	modal_scrim.add_child(info_panel)
	modal_scrim.add_child(quit_panel)


func _build_settings_panel() -> Panel:
	var panel := _modal_panel("SettingsPanel", Vector2(390, 145), Vector2(500, 430))
	_add_modal_title(panel, "설정", "탐험 환경")

	var volume_label := _label("마스터 음량", 13, COLOR_TEXT)
	volume_label.position = Vector2(42, 94)
	volume_label.size = Vector2(250, 26)
	panel.add_child(volume_label)
	volume_value_label = _label("80%", 13, COLOR_TEAL)
	volume_value_label.position = Vector2(360, 94)
	volume_value_label.size = Vector2(98, 26)
	volume_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_value_label.add_theme_font_override("font", ui_spaced_font)
	panel.add_child(volume_value_label)

	volume_slider = HSlider.new()
	volume_slider.name = "MasterVolumeSlider"
	volume_slider.position = Vector2(42, 130)
	volume_slider.size = Vector2(416, 28)
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value_changed.connect(_on_volume_changed)
	panel.add_child(volume_slider)

	fullscreen_toggle = CheckButton.new()
	fullscreen_toggle.name = "FullscreenToggle"
	fullscreen_toggle.text = "전체 화면"
	fullscreen_toggle.position = Vector2(36, 184)
	fullscreen_toggle.size = Vector2(428, 44)
	fullscreen_toggle.add_theme_font_override("font", ui_font)
	fullscreen_toggle.add_theme_font_size_override("font_size", 13)
	fullscreen_toggle.add_theme_color_override("font_color", COLOR_TEXT)
	fullscreen_toggle.add_theme_color_override("font_hover_color", COLOR_IVORY)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	panel.add_child(fullscreen_toggle)

	var note := _label("변경한 설정은 즉시 적용되며 다음 실행에도 유지됩니다.", 11, COLOR_MUTED)
	note.position = Vector2(42, 249)
	note.size = Vector2(416, 46)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(note)

	var close := _modal_button("완료", "SettingsCloseButton", Vector2(160, 346), Vector2(180, 38))
	close.pressed.connect(_close_modal)
	panel.add_child(close)
	return panel


func _build_controls_panel() -> Panel:
	var panel := _modal_panel("ControlsPanel", Vector2(350, 112), Vector2(580, 496))
	_add_modal_title(panel, "조작법", "실시간 원정")

	var left := _label("이동\n달리기\n도약\n시점\n상호작용\n횃불", 13, COLOR_MUTED)
	left.position = Vector2(58, 92)
	left.size = Vector2(130, 220)
	left.add_theme_constant_override("line_spacing", 9)
	panel.add_child(left)
	var left_keys := _label("방향 입력\n달리기 보조 키\n공백 키\n마우스 이동\n상호작용 키\n횃불 키", 13, Color(0.86, 0.88, 0.85))
	left_keys.position = Vector2(176, 92)
	left_keys.size = Vector2(116, 220)
	left_keys.add_theme_font_override("font", ui_spaced_font)
	left_keys.add_theme_constant_override("line_spacing", 9)
	panel.add_child(left_keys)

	var right := _label("공격 / 차지\n방패 / 저스트 가드\n인벤토리\n일시정지\n결과 재시작", 13, COLOR_MUTED)
	right.position = Vector2(310, 92)
	right.size = Vector2(150, 190)
	right.add_theme_constant_override("line_spacing", 9)
	panel.add_child(right)
	var right_keys := _label("마우스 왼쪽\n마우스 오른쪽\n인벤토리 키\n취소 키\n재시작 키", 13, Color(0.86, 0.88, 0.85))
	right_keys.position = Vector2(456, 92)
	right_keys.size = Vector2(104, 190)
	right_keys.add_theme_font_override("font", ui_spaced_font)
	right_keys.add_theme_constant_override("line_spacing", 9)
	panel.add_child(right_keys)

	var tip := _label("활: 마우스 왼쪽을 길게 눌러 당기고 놓아 발사 · 오른쪽으로 취소\n상자와 함정은 정면에서 상호작용 키를 눌러 조사하십시오.", 11, COLOR_TEAL)
	tip.position = Vector2(58, 324)
	tip.size = Vector2(464, 54)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(tip)

	var close := _modal_button("닫기", "ControlsCloseButton", Vector2(200, 418), Vector2(180, 38))
	close.pressed.connect(_close_modal)
	panel.add_child(close)
	return panel


func _build_info_panel() -> Panel:
	var panel := _modal_panel("InfoPanel", Vector2(370, 126), Vector2(540, 468))
	_add_modal_title(panel, "정보", "잔향의 성소")

	var body := _label(
		"검은 성물실에 들어가 감시자를 쓰러뜨리고,\n성소의 회수품을 챙겨 귀환문으로 탈출하십시오.\n\n이 프로젝트는 실시간 1인칭 전투, 방향성 방패 방어,\n상호작용 조사, 함정 해제와 던전 회수 루프를\n검증하는 다크 판타지 플레이 수직 슬라이스입니다.",
		13,
		COLOR_TEXT
	)
	body.position = Vector2(48, 93)
	body.size = Vector2(444, 225)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_constant_override("line_spacing", 4)
	panel.add_child(body)

	var version := str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	var build := _label("빌드 %s" % version, 10, COLOR_MUTED)
	build.position = Vector2(48, 332)
	build.size = Vector2(444, 22)
	build.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(build)

	var skeleton_credit := _label(
		"BodyParts3D, © The Database Center for Life Science\nlicensed under CC Attribution 4.0 International",
		8,
		COLOR_MUTED
	)
	skeleton_credit.name = "BodyParts3DCredit"
	skeleton_credit.position = Vector2(48, 352)
	skeleton_credit.size = Vector2(444, 34)
	skeleton_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(skeleton_credit)

	var close := _modal_button("닫기", "InfoCloseButton", Vector2(180, 400), Vector2(180, 38))
	close.pressed.connect(_close_modal)
	panel.add_child(close)
	return panel


func _build_quit_panel() -> Panel:
	var panel := _modal_panel("QuitConfirmPanel", Vector2(430, 240), Vector2(420, 240))
	_add_modal_title(panel, "게임 종료", "성소를 떠나시겠습니까?")

	var prompt := _label("현재 원정 중인 내용은 저장되지 않습니다.", 12, COLOR_MUTED)
	prompt.position = Vector2(35, 94)
	prompt.size = Vector2(350, 24)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(prompt)

	quit_cancel_button = _modal_button("취소", "QuitCancelButton", Vector2(50, 158), Vector2(150, 38))
	quit_confirm_button = _modal_button("종료", "QuitConfirmButton", Vector2(220, 158), Vector2(150, 38), true)
	quit_cancel_button.pressed.connect(_close_modal)
	quit_confirm_button.pressed.connect(_confirm_quit)
	panel.add_child(quit_cancel_button)
	panel.add_child(quit_confirm_button)
	return panel


func _build_destination_panel() -> Panel:
	var panel := _modal_panel("DestinationPanel", Vector2(16, 16), Vector2(1248, 640))
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.006, 0.009, 0.01, 0.995), Color(0.37, 0.45, 0.42, 0.96), 1, 2))

	var map_frame := Panel.new()
	map_frame.name = "DestinationMapFrame"
	map_frame.position = Vector2(286, 0)
	map_frame.size = Vector2(676, 640)
	map_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.007, 0.008, 1), Color(0.29, 0.36, 0.34, 0.72), 1, 0))
	panel.add_child(map_frame)

	var map_art := TextureRect.new()
	map_art.name = "DestinationMapArtwork"
	map_art.texture = DESTINATION_MAP_TEXTURE
	map_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(map_art)

	var map_tint := ColorRect.new()
	map_tint.name = "DestinationMapTone"
	map_tint.color = Color(0.015, 0.022, 0.021, 0.14)
	map_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_frame.add_child(map_tint)

	var left_rail := Panel.new()
	left_rail.name = "DestinationLeftRail"
	left_rail.position = Vector2(0, 0)
	left_rail.size = Vector2(286, 640)
	left_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_rail.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.013, 0.014, 0.98), Color(0.3, 0.38, 0.36, 0.76), 1, 0))
	panel.add_child(left_rail)

	var kicker := _label("문 너머의 길", 10, COLOR_TEAL)
	kicker.position = Vector2(26, 28)
	kicker.size = Vector2(234, 18)
	kicker.add_theme_font_override("font", ui_kicker_font)
	left_rail.add_child(kicker)
	var title := _label("성소 이동 지도", 25, COLOR_IVORY)
	title.name = "DestinationPanelTitle"
	title.set_meta("font_role", "modal_title")
	title.position = Vector2(24, 49)
	title.size = Vector2(238, 40)
	title.add_theme_font_override("font", ui_medium_font)
	left_rail.add_child(title)
	var intro := _label("지도 위 표식을 선택해\n다음 행선지를 정하십시오.", 12, COLOR_TEXT)
	intro.position = Vector2(25, 101)
	intro.size = Vector2(236, 52)
	intro.add_theme_constant_override("line_spacing", 4)
	left_rail.add_child(intro)

	var left_divider := ColorRect.new()
	left_divider.position = Vector2(25, 171)
	left_divider.size = Vector2(236, 1)
	left_divider.color = Color(0.31, 0.4, 0.37, 0.68)
	left_divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_rail.add_child(left_divider)

	var destination_heading := _label("이동 가능 지역", 10, COLOR_MUTED)
	destination_heading.position = Vector2(25, 191)
	destination_heading.size = Vector2(236, 20)
	destination_heading.add_theme_font_override("font", ui_spaced_font)
	left_rail.add_child(destination_heading)
	_add_destination_legend(left_rail, "◆", "검은 성물실", "위험 지역 · 전투와 회수", Vector2(25, 224), COLOR_DANGER)
	_add_destination_legend(left_rail, "●", "성소의 중개인", "안전 지역 · 거래와 보급", Vector2(25, 309), COLOR_GOLD)
	_add_destination_legend(left_rail, "◆", "검은 물길 동굴", "131m × 139m · 침수된 지하 동굴", Vector2(25, 394), COLOR_TEAL)

	var location_panel := Panel.new()
	location_panel.name = "CurrentLocationCard"
	location_panel.position = Vector2(24, 508)
	location_panel.size = Vector2(238, 94)
	location_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.055, 0.052, 0.92), Color(0.38, 0.5, 0.46, 0.86), 1, 2))
	left_rail.add_child(location_panel)
	var location_kicker := _label("현재 위치", 9, COLOR_TEAL)
	location_kicker.position = Vector2(15, 13)
	location_kicker.size = Vector2(208, 18)
	location_kicker.add_theme_font_override("font", ui_spaced_font)
	location_panel.add_child(location_kicker)
	var location_name := _label("순례자의 은신처", 15, COLOR_IVORY)
	location_name.position = Vector2(15, 35)
	location_name.size = Vector2(208, 28)
	location_name.add_theme_font_override("font", ui_medium_font)
	location_panel.add_child(location_name)
	var location_note := _label("문이 열려 있습니다", 10, COLOR_MUTED)
	location_note.position = Vector2(15, 65)
	location_note.size = Vector2(208, 18)
	location_panel.add_child(location_note)

	var right_rail := Panel.new()
	right_rail.name = "DestinationRightRail"
	right_rail.position = Vector2(962, 0)
	right_rail.size = Vector2(286, 640)
	right_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_rail.add_theme_stylebox_override("panel", _panel_style(Color(0.007, 0.011, 0.012, 0.97), Color(0.3, 0.38, 0.36, 0.76), 1, 0))
	panel.add_child(right_rail)

	var question_kicker := _label("행선지 선택", 10, COLOR_TEAL)
	question_kicker.position = Vector2(25, 35)
	question_kicker.size = Vector2(166, 18)
	question_kicker.add_theme_font_override("font", ui_kicker_font)
	right_rail.add_child(question_kicker)
	var question := _label("어디로\n향하시겠습니까?", 25, COLOR_IVORY)
	question.position = Vector2(24, 61)
	question.size = Vector2(228, 78)
	question.add_theme_font_override("font", ui_medium_font)
	question.add_theme_constant_override("line_spacing", 2)
	right_rail.add_child(question)
	var explanation := _label("지도 표식에 마우스를 올리거나\n방향 키로 이동한 뒤 선택하십시오.", 11, COLOR_MUTED)
	explanation.position = Vector2(25, 158)
	explanation.size = Vector2(236, 52)
	explanation.add_theme_constant_override("line_spacing", 4)
	right_rail.add_child(explanation)

	var safety_title := _label("중개인", 12, COLOR_GOLD)
	safety_title.position = Vector2(25, 270)
	safety_title.size = Vector2(236, 24)
	safety_title.add_theme_font_override("font", ui_medium_font)
	right_rail.add_child(safety_title)
	var safety_copy := _label("원정 전에 보급품을 사고\n회수품을 판매할 수 있습니다.", 11, COLOR_TEXT)
	safety_copy.position = Vector2(25, 298)
	safety_copy.size = Vector2(236, 54)
	safety_copy.add_theme_constant_override("line_spacing", 3)
	right_rail.add_child(safety_copy)

	var danger_title := _label("검은 성물실", 12, Color(0.72, 0.43, 0.38))
	danger_title.position = Vector2(25, 386)
	danger_title.size = Vector2(236, 24)
	danger_title.add_theme_font_override("font", ui_medium_font)
	right_rail.add_child(danger_title)
	var danger_copy := _label("감시자를 쓰러뜨리고 성물을\n회수한 뒤 살아서 귀환하십시오.", 11, COLOR_TEXT)
	danger_copy.position = Vector2(25, 414)
	danger_copy.size = Vector2(236, 54)
	danger_copy.add_theme_constant_override("line_spacing", 3)
	right_rail.add_child(danger_copy)
	var cave_title := _label("검은 물길 동굴", 12, COLOR_TEAL)
	cave_title.position = Vector2(25, 492)
	cave_title.size = Vector2(236, 24)
	cave_title.add_theme_font_override("font", ui_medium_font)
	right_rail.add_child(cave_title)
	var cave_copy := _label("횃불을 따라 젖은 암굴과\n잊힌 지하 예배당을 탐색하십시오.", 11, COLOR_TEXT)
	cave_copy.position = Vector2(25, 520)
	cave_copy.size = Vector2(236, 46)
	cave_copy.add_theme_constant_override("line_spacing", 3)
	right_rail.add_child(cave_copy)
	var map_input_hint := _label("선택 키 · 이동   취소 키 · 지도 닫기", 10, COLOR_TEAL)
	map_input_hint.position = Vector2(25, 582)
	map_input_hint.size = Vector2(236, 22)
	map_input_hint.add_theme_font_override("font", ui_caption_font)
	right_rail.add_child(map_input_hint)

	destination_dungeon_button = _destination_marker_button(
		"◆  검은 성물실\n     위험 4 · 원정 시작",
		"DungeonDestinationButton",
		Vector2(718, 114),
		Vector2(228, 76),
		COLOR_DANGER
	)
	destination_dungeon_button.pressed.connect(_choose_dungeon_destination)
	panel.add_child(destination_dungeon_button)

	destination_cave_button = _destination_marker_button(
		"◆  검은 물길 동굴\n     131m × 139m · 원정 시작",
		"CaveDestinationButton",
		Vector2(692, 430),
		Vector2(254, 76),
		COLOR_TEAL
	)
	destination_cave_button.tooltip_text = "가로 131m · 세로 139m의 어두운 동굴 던전으로 출발합니다."
	destination_cave_button.pressed.connect(_choose_cave_destination)
	panel.add_child(destination_cave_button)

	destination_merchant_button = _destination_marker_button(
		"●  성소의 중개인\n     거래 · 보급 · 장비 정비",
		"MerchantDestinationButton",
		Vector2(304, 442),
		Vector2(248, 76),
		COLOR_GOLD
	)
	destination_merchant_button.pressed.connect(_choose_merchant_destination)
	panel.add_child(destination_merchant_button)

	var current_marker := Panel.new()
	current_marker.name = "HideoutMapMarker"
	current_marker.position = Vector2(563, 289)
	current_marker.size = Vector2(184, 58)
	current_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	current_marker.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.06, 0.057, 0.91), Color(0.54, 0.68, 0.63, 0.92), 1, 20))
	panel.add_child(current_marker)
	var marker_label := _label("◇  현재 위치\n   순례자의 은신처", 11, COLOR_IVORY)
	marker_label.position = Vector2(14, 8)
	marker_label.size = Vector2(156, 43)
	marker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	marker_label.add_theme_font_override("font", ui_medium_font)
	current_marker.add_child(marker_label)

	destination_cancel_button = _modal_button("닫기", "DestinationCancelButton", Vector2(1153, 24), Vector2(70, 38))
	destination_cancel_button.pressed.connect(_close_modal)
	panel.add_child(destination_cancel_button)
	destination_dungeon_button.focus_neighbor_left = NodePath("../MerchantDestinationButton")
	destination_dungeon_button.focus_neighbor_bottom = NodePath("../CaveDestinationButton")
	destination_dungeon_button.focus_neighbor_right = NodePath("../DestinationCancelButton")
	destination_merchant_button.focus_neighbor_top = NodePath("../DungeonDestinationButton")
	destination_merchant_button.focus_neighbor_right = NodePath("../CaveDestinationButton")
	destination_cave_button.focus_neighbor_top = NodePath("../DungeonDestinationButton")
	destination_cave_button.focus_neighbor_left = NodePath("../MerchantDestinationButton")
	destination_cave_button.focus_neighbor_right = NodePath("../DestinationCancelButton")
	destination_cancel_button.focus_neighbor_left = NodePath("../DungeonDestinationButton")
	destination_cancel_button.focus_neighbor_bottom = NodePath("../DungeonDestinationButton")
	return panel


func _open_destination_map() -> void:
	_show_panel(destination_panel, destination_merchant_button)


func _start_game() -> void:
	if transitioning:
		return
	ExpeditionSession.begin_new_journey()
	transitioning = true
	for button in main_buttons:
		button.disabled = true
	fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_layer, "color", Color(0, 0, 0, 1), transition_duration)
	await tween.finished
	get_tree().paused = false
	_start_scene_loading(
		HIDEOUT_SCENE_PATH,
		"은신처로 향하는 중",
		"성소의 불씨와 원정 기록을 준비하고 있습니다",
		"안전한 길을 확인하는 중"
	)


func _open_test_room() -> void:
	if transitioning:
		return
	transitioning = true
	for button in main_buttons:
		button.disabled = true
	fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_layer, "color", Color(0, 0, 0, 1), transition_duration)
	await tween.finished
	get_tree().paused = false
	_start_scene_loading(
		TEST_ROOM_SCENE_PATH,
		"테스트룸을 준비하는 중",
		"전투와 생활 기능을 자유롭게 시험할 공간을 준비합니다",
		"시험 장비와 대상을 배치하는 중"
	)


func _choose_dungeon_destination() -> void:
	_travel_to_destination(GAME_SCENE_PATH)


func _choose_cave_destination() -> void:
	_travel_to_destination(CAVE_SCENE_PATH)


func _choose_merchant_destination() -> void:
	_travel_to_destination(MERCHANT_SCENE_PATH)


func _travel_to_destination(scene_path: String) -> void:
	if transitioning:
		return
	ExpeditionSession.ensure_journey()
	transitioning = true
	if is_instance_valid(door_button):
		door_button.disabled = true
		door_button.focus_mode = Control.FOCUS_NONE
	for button in main_buttons:
		button.disabled = true
	for button in [destination_dungeon_button, destination_cave_button, destination_merchant_button, destination_cancel_button]:
		button.disabled = true
	fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_layer, "color", Color(0, 0, 0, 1), transition_duration)
	await tween.finished
	get_tree().paused = false
	if scene_path == GAME_SCENE_PATH:
		_start_scene_loading(
			scene_path,
			"검은 성물실로 향하는 중",
			"어둠 속 통로와 전투 구역을 준비하고 있습니다",
			"봉인된 길을 여는 중"
		)
	elif scene_path == CAVE_SCENE_PATH:
		_start_scene_loading(
			scene_path,
			"검은 물길 동굴로 향하는 중",
			"131m × 139m의 젖은 암굴과 지하 예배당을 준비하고 있습니다",
			"어두운 물길에 횃불을 밝히는 중"
		)
	else:
		_start_scene_loading(
			scene_path,
			"중개인을 찾아가는 중",
			"성소의 거래소와 원정 물품을 준비하고 있습니다",
			"희미한 등불을 따라가는 중"
		)


func _start_scene_loading(scene_path: String, title_text: String, detail_text: String, status_text: String) -> void:
	if is_instance_valid(loading_screen):
		return
	loading_screen = LOADING_SCREEN_SCRIPT.new() as SanctuaryLoadingScreen
	loading_screen.name = "SceneLoadingOverlay"
	loading_screen.configure(scene_path, title_text, detail_text, status_text, 0.7)
	loading_screen.load_failed.connect(_on_scene_loading_failed.bind(loading_screen))
	loading_screen.attach_as_overlay(get_tree())


func _on_scene_loading_failed(_error_code: int, failed_screen: SanctuaryLoadingScreen) -> void:
	if failed_screen != loading_screen:
		return
	failed_screen.dismiss()
	loading_screen = null
	transitioning = false
	fade_layer.color = Color(0, 0, 0, 0)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for button in [destination_dungeon_button, destination_cave_button, destination_merchant_button, destination_cancel_button]:
		if is_instance_valid(button):
			button.disabled = false
	if current_panel != null:
		_close_modal()
	else:
		for button in main_buttons:
			button.disabled = false
			button.focus_mode = Control.FOCUS_ALL
		if is_instance_valid(door_button):
			door_button.disabled = false
			door_button.focus_mode = Control.FOCUS_ALL
		_focus_default()
	if is_instance_valid(footer_status_label):
		footer_status_label.text = "불러오지 못했습니다 · 다시 시도해 주세요"


func _open_settings() -> void:
	_show_panel(settings_panel, volume_slider)


func _open_controls() -> void:
	var close := controls_panel.get_node_or_null("ControlsCloseButton") as Control
	_show_panel(controls_panel, close)


func _open_info() -> void:
	var close := info_panel.get_node_or_null("InfoCloseButton") as Control
	_show_panel(info_panel, close)


func _open_quit_confirmation() -> void:
	_show_panel(quit_panel, quit_cancel_button)


func _show_panel(panel: Control, focus_target: Control) -> void:
	if transitioning or panel == null:
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	for button in main_buttons:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	if is_instance_valid(door_button):
		door_button.disabled = true
		door_button.focus_mode = Control.FOCUS_NONE
	for candidate in [settings_panel, controls_panel, info_panel, quit_panel, destination_panel]:
		if is_instance_valid(candidate):
			candidate.visible = candidate == panel
	current_panel = panel
	modal_scrim.visible = true
	if focus_target != null:
		focus_target.grab_focus()


func _close_modal() -> void:
	if current_panel == null:
		return
	current_panel.visible = false
	current_panel = null
	modal_scrim.visible = false
	for button in main_buttons:
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	if is_instance_valid(door_button):
		door_button.disabled = false
		door_button.focus_mode = Control.FOCUS_ALL
	var focus_target := _return_focus
	_return_focus = null
	if is_instance_valid(focus_target):
		focus_target.grab_focus()
	else:
		_focus_default()


func _confirm_quit() -> void:
	get_tree().paused = false
	get_tree().quit()


func _load_settings() -> void:
	var config := ConfigFile.new()
	var volume := 80.0
	var fullscreen := false
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("audio", "master_volume", volume)), 0.0, 100.0)
		fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	volume_slider.set_value_no_signal(volume)
	fullscreen_toggle.set_pressed_no_signal(fullscreen)
	_apply_volume(volume)
	_apply_fullscreen(fullscreen)
	_refresh_footer(volume)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	config.save(SETTINGS_PATH)


func _on_volume_changed(value: float) -> void:
	_apply_volume(value)
	_refresh_footer(value)
	_save_settings()


func _apply_volume(value: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index < 0:
		return
	var linear := clampf(value / 100.0, 0.0001, 1.0)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
	AudioServer.set_bus_mute(bus_index, value <= 0.0)
	if volume_value_label != null:
		volume_value_label.text = "%d%%" % roundi(value)


func _on_fullscreen_toggled(enabled: bool) -> void:
	_apply_fullscreen(enabled)
	_save_settings()


func _apply_fullscreen(enabled: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)


func _toggle_fullscreen() -> void:
	var enabled := not fullscreen_toggle.button_pressed
	fullscreen_toggle.set_pressed_no_signal(enabled)
	_apply_fullscreen(enabled)
	_save_settings()


func _refresh_footer(volume: float) -> void:
	if footer_status_label == null:
		return
	footer_status_label.text = "게임 시작  ·  위아래 이동  ·  선택  ·  뒤로  ·  음량 %d%%" % roundi(volume)


func _focus_default() -> void:
	if is_instance_valid(new_game_button):
		new_game_button.grab_focus()


func _focus_relative(direction: int) -> void:
	if main_buttons.is_empty():
		return
	var focused := get_viewport().gui_get_focus_owner() as Button
	var current_index := main_buttons.find(focused)
	if current_index < 0:
		current_index = 0
	else:
		current_index = wrapi(current_index + direction, 0, main_buttons.size())
	main_buttons[current_index].grab_focus()


func _menu_button(text_value: String, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.size = Vector2(220, 34)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_spaced_font)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color(0.74, 0.76, 0.74))
	button.add_theme_color_override("font_hover_color", Color(0.94, 0.93, 0.9))
	button.add_theme_color_override("font_focus_color", Color(0.94, 0.93, 0.9))
	button.add_theme_color_override("font_pressed_color", COLOR_IVORY)
	button.add_theme_stylebox_override("normal", _menu_row_style(Color(0.006, 0.009, 0.01, 0.58), Color(0.25, 0.29, 0.28, 0.72), 0, 1))
	button.add_theme_stylebox_override("hover", _menu_row_style(Color(0.82, 0.85, 0.82, 0.13), Color(0.78, 0.8, 0.77, 0.88), 2, 1))
	button.add_theme_stylebox_override("focus", _menu_row_style(Color(0.82, 0.85, 0.82, 0.13), Color(0.78, 0.8, 0.77, 0.88), 2, 1))
	button.add_theme_stylebox_override("pressed", _menu_row_style(Color(0.86, 0.87, 0.83, 0.18), Color(0.88, 0.88, 0.84, 0.94), 2, 1))
	button.add_theme_stylebox_override("disabled", _menu_row_style(Color(0.004, 0.006, 0.007, 0.44), Color(0.14, 0.16, 0.15, 0.58), 0, 1))
	return button


func _modal_panel(node_name: String, panel_position: Vector2, panel_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = panel_position
	panel.size = panel_size
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.018, 0.02, 0.985), Color(0.37, 0.43, 0.4, 0.95), 1, 3))
	return panel


func _add_modal_title(panel: Panel, title_text: String, subtitle_text: String) -> void:
	var title := _label(title_text, 22, Color(0.87, 0.85, 0.8))
	title.name = "%sTitle" % panel.name
	title.set_meta("font_role", "modal_title")
	title.position = Vector2(24, 22)
	title.size = Vector2(panel.size.x - 48, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", ui_medium_font)
	panel.add_child(title)
	var subtitle := _label(subtitle_text, 10, COLOR_TEAL)
	subtitle.position = Vector2(24, 53)
	subtitle.size = Vector2(panel.size.x - 48, 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_override("font", ui_spaced_font)
	panel.add_child(subtitle)
	var divider := ColorRect.new()
	divider.position = Vector2(34, 75)
	divider.size = Vector2(panel.size.x - 68, 1)
	divider.color = Color(0.31, 0.39, 0.37, 0.65)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)


func _modal_button(text_value: String, node_name: String, button_position: Vector2, button_size: Vector2, danger := false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_spaced_font)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	var accent := Color(0.57, 0.25, 0.2) if danger else Color(0.28, 0.38, 0.36)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.035, 0.05, 0.052, 0.95), accent, 1, 2))
	button.add_theme_stylebox_override("hover", _panel_style(accent.darkened(0.32), accent.lightened(0.25), 2, 2))
	button.add_theme_stylebox_override("focus", _panel_style(accent.darkened(0.32), accent.lightened(0.25), 2, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(accent.darkened(0.45), accent.lightened(0.35), 2, 2))
	return button


func _destination_marker_button(
	text_value: String,
	node_name: String,
	button_position: Vector2,
	button_size: Vector2,
	accent: Color
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_medium_font)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color(0.88, 0.86, 0.8))
	button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	button.add_theme_color_override("font_focus_color", COLOR_IVORY)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	button.add_theme_constant_override("outline_size", 3)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.008, 0.014, 0.014, 0.89), accent.darkened(0.18), 1, 4))
	button.add_theme_stylebox_override("hover", _panel_style(accent.darkened(0.55), accent.lightened(0.28), 2, 4))
	button.add_theme_stylebox_override("focus", _panel_style(accent.darkened(0.55), accent.lightened(0.28), 2, 4))
	button.add_theme_stylebox_override("pressed", _panel_style(accent.darkened(0.68), accent.lightened(0.4), 2, 4))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.006, 0.008, 0.008, 0.7), Color(0.19, 0.21, 0.2, 0.7), 1, 4))
	return button


func _add_destination_legend(
	parent: Control,
	glyph: String,
	title_text: String,
	detail_text: String,
	legend_position: Vector2,
	accent: Color
) -> void:
	var card := Panel.new()
	card.position = legend_position
	card.size = Vector2(236, 68)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.029, 0.029, 0.9), accent.darkened(0.28), 1, 2))
	parent.add_child(card)
	var icon := _label(glyph, 19, accent.lightened(0.22))
	icon.position = Vector2(13, 13)
	icon.size = Vector2(28, 36)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(icon)
	var title := _label(title_text, 13, COLOR_IVORY)
	title.position = Vector2(50, 10)
	title.size = Vector2(171, 24)
	title.add_theme_font_override("font", ui_medium_font)
	card.add_child(title)
	var detail := _label(detail_text, 9, COLOR_MUTED)
	detail.position = Vector2(50, 37)
	detail.size = Vector2(171, 18)
	card.add_child(detail)


func _label(text_value: String, size_value: int, color_value: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color_value)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _font_variation(base_font: Font, weight: int, glyph_spacing: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base_font
	var text_server := TextServerManager.get_primary_interface()
	variation.variation_opentype = {text_server.name_to_tag("wght"): weight}
	variation.spacing_glyph = glyph_spacing
	return variation


func _menu_row_style(background: Color, edge: Color, left_width: int, bottom_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.border_width_left = left_width
	style.border_width_bottom = bottom_width
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _panel_style(background: Color, border: Color, width := 1, radius := 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
