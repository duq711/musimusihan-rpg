extends DungeonHUD
class_name HideoutHUD

const UI_FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")

const COLOR_IVORY := Color(0.9, 0.86, 0.76)
const COLOR_MUTED := Color(0.58, 0.64, 0.62)
const COLOR_TEAL := Color(0.42, 0.66, 0.64)
const COLOR_AMBER := Color(0.94, 0.63, 0.3)


func _build_interface() -> void:
	var root := Control.new()
	root.name = "HideoutHUDRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_build_location_card(root)
	_build_survival_card(root)
	_build_living_guide(root)
	_build_center_feedback(root)
	_build_control_legend(root)
	_build_interaction_panel(root)
	_build_overlay(root)


func _build_location_card(root: Control) -> void:
	var card := Panel.new()
	card.name = "LocationCard"
	card.position = Vector2(24, 24)
	card.size = Vector2(390, 126)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.012, 0.019, 0.021, 0.9), Color(0.29, 0.47, 0.45, 0.78), 1)
	)
	root.add_child(card)

	var kicker := _hud_label("안전 지역 · 은신처 1단계", 13, COLOR_TEAL)
	kicker.name = "LocationKicker"
	kicker.position = Vector2(18, 13)
	kicker.size = Vector2(354, 21)
	card.add_child(kicker)

	var title := _hud_label("침수된 순례자 납골당", 24, COLOR_IVORY)
	title.name = "LocationTitle"
	title.position = Vector2(17, 37)
	title.size = Vector2(355, 36)
	card.add_child(title)

	var detail := _hud_label("검은 물 아래 남겨진 첫 번째 거처", 12, COLOR_MUTED)
	detail.name = "LocationDetail"
	detail.position = Vector2(19, 75)
	detail.size = Vector2(250, 22)
	card.add_child(detail)

	torch_status_label = _hud_label("횃불 · 켜짐", 12, COLOR_AMBER)
	torch_status_label.name = "TorchStatus"
	torch_status_label.position = Vector2(269, 75)
	torch_status_label.size = Vector2(101, 22)
	torch_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(torch_status_label)

	var status := _hud_label("휴식 효과 적용 중", 11, Color(0.48, 0.57, 0.53))
	status.name = "SafeZoneStatus"
	status.position = Vector2(19, 100)
	status.size = Vector2(352, 18)
	card.add_child(status)


func _build_survival_card(root: Control) -> void:
	var card := Panel.new()
	card.name = "SurvivalCard"
	card.position = Vector2(24, 158)
	card.size = Vector2(390, 92)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.012, 0.019, 0.021, 0.88), Color(0.27, 0.39, 0.37, 0.68), 1)
	)
	root.add_child(card)

	var heading := _hud_label("생존 상태 · 은신처에서는 감소하지 않음", 11, Color(0.48, 0.58, 0.55))
	heading.name = "SurvivalHeading"
	heading.position = Vector2(15, 7)
	heading.size = Vector2(360, 18)
	card.add_child(heading)

	hunger_bar = _bar(Vector2(14, 31), Vector2(174, 18), Color(0.52, 0.32, 0.11))
	hunger_bar.name = "HungerBar"
	card.add_child(hunger_bar)
	hunger_label = _hud_label("포만감 100 / 100", 10, Color(0.94, 0.84, 0.64))
	hunger_label.name = "HungerLabel"
	hunger_label.position = Vector2(21, 31)
	hunger_label.size = Vector2(160, 18)
	card.add_child(hunger_label)

	thirst_bar = _bar(Vector2(202, 31), Vector2(174, 18), Color(0.08, 0.40, 0.50))
	thirst_bar.name = "ThirstBar"
	card.add_child(thirst_bar)
	thirst_label = _hud_label("수분 100 / 100", 10, Color(0.67, 0.88, 0.91))
	thirst_label.name = "ThirstLabel"
	thirst_label.position = Vector2(209, 31)
	thirst_label.size = Vector2(160, 18)
	card.add_child(thirst_label)

	condition_label = _hud_label("상태 · 안정", 11, Color(0.55, 0.62, 0.59))
	condition_label.name = "ConditionLabel"
	condition_label.position = Vector2(15, 61)
	condition_label.size = Vector2(360, 20)
	condition_label.clip_text = true
	card.add_child(condition_label)


func _build_living_guide(root: Control) -> void:
	var guide := Panel.new()
	guide.name = "LivingGuide"
	guide.anchor_left = 1.0
	guide.anchor_right = 1.0
	guide.offset_left = -374.0
	guide.offset_right = -24.0
	guide.offset_top = 24.0
	guide.offset_bottom = 169.0
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.012, 0.018, 0.02, 0.88), Color(0.25, 0.35, 0.34, 0.72), 1)
	)
	root.add_child(guide)

	var heading := _hud_label("이곳에서 할 수 있는 일", 14, Color(0.72, 0.77, 0.7))
	heading.name = "LivingGuideTitle"
	heading.position = Vector2(17, 12)
	heading.size = Vector2(316, 22)
	guide.add_child(heading)

	var rule := ColorRect.new()
	rule.name = "LivingGuideRule"
	rule.position = Vector2(17, 39)
	rule.size = Vector2(316, 1)
	rule.color = Color(0.33, 0.47, 0.44, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.add_child(rule)

	var guide_text := _hud_label(
		"침상   휴식 · 체력 회복\n보관함   원정 물품 정리\n화로   불씨 켜기 · 끄기",
		13,
		Color(0.69, 0.72, 0.66)
	)
	guide_text.name = "LivingGuideText"
	guide_text.position = Vector2(18, 48)
	guide_text.size = Vector2(314, 82)
	guide_text.add_theme_constant_override("line_spacing", 7)
	guide.add_child(guide_text)


func _build_center_feedback(root: Control) -> void:
	crosshair = _hud_label("·", 28, Color(0.78, 0.82, 0.75, 0.78))
	crosshair.name = "HideoutCrosshair"
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -18.0
	crosshair.offset_top = -23.0
	crosshair.offset_right = 18.0
	crosshair.offset_bottom = 19.0
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(crosshair)

	prompt_label = _hud_label("", 16, Color(0.91, 0.83, 0.65))
	prompt_label.name = "InteractionPrompt"
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_top = 0.64
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_bottom = 0.64
	prompt_label.offset_left = -300.0
	prompt_label.offset_top = -20.0
	prompt_label.offset_right = 300.0
	prompt_label.offset_bottom = 22.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	event_label = _hud_label("", 19, Color(0.96, 0.74, 0.42))
	event_label.name = "HideoutEvent"
	event_label.anchor_left = 0.5
	event_label.anchor_top = 0.19
	event_label.anchor_right = 0.5
	event_label.anchor_bottom = 0.19
	event_label.offset_left = -370.0
	event_label.offset_top = -22.0
	event_label.offset_right = 370.0
	event_label.offset_bottom = 24.0
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(event_label)


func _build_control_legend(root: Control) -> void:
	var controls := Panel.new()
	controls.name = "ControlLegend"
	controls.anchor_left = 0.5
	controls.anchor_top = 1.0
	controls.anchor_right = 0.5
	controls.anchor_bottom = 1.0
	controls.offset_left = -430.0
	controls.offset_top = -61.0
	controls.offset_right = 430.0
	controls.offset_bottom = -20.0
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.009, 0.014, 0.016, 0.84), Color(0.2, 0.29, 0.28, 0.62), 1)
	)
	root.add_child(controls)

	var controls_text := _hud_label(
		"LMB  입구 선택      E  상호작용      I  가방      F  횃불      M  지도      ESC  일시정지",
		12,
		Color(0.61, 0.67, 0.63)
	)
	controls_text.name = "ControlLegendText"
	controls_text.position = Vector2(18, 10)
	controls_text.size = Vector2(824, 22)
	controls_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_child(controls_text)


func _build_interaction_panel(root: Control) -> void:
	interaction_panel = Panel.new()
	interaction_panel.name = "TimedInteractionPanel"
	interaction_panel.anchor_left = 0.5
	interaction_panel.anchor_top = 0.7
	interaction_panel.anchor_right = 0.5
	interaction_panel.anchor_bottom = 0.7
	interaction_panel.offset_left = -265.0
	interaction_panel.offset_top = -40.0
	interaction_panel.offset_right = 265.0
	interaction_panel.offset_bottom = 43.0
	interaction_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_panel.add_theme_stylebox_override(
		"panel",
		_panel_style(Color(0.01, 0.016, 0.017, 0.94), Color(0.48, 0.4, 0.24, 0.84), 1)
	)
	interaction_panel.visible = false
	root.add_child(interaction_panel)

	interaction_title = _hud_label("상호작용 중", 15, Color(0.91, 0.82, 0.63))
	interaction_title.name = "TimedInteractionTitle"
	interaction_title.position = Vector2(16, 7)
	interaction_title.size = Vector2(498, 22)
	interaction_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_panel.add_child(interaction_title)

	interaction_progress = _bar(Vector2(22, 35), Vector2(486, 12), Color(0.52, 0.42, 0.2))
	interaction_progress.name = "TimedInteractionProgress"
	interaction_progress.min_value = 0.0
	interaction_progress.max_value = 1.0
	interaction_progress.value = 0.0
	interaction_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_panel.add_child(interaction_progress)

	interaction_help = _hud_label("시선을 유지하십시오", 11, Color(0.5, 0.56, 0.52))
	interaction_help.name = "TimedInteractionHelp"
	interaction_help.position = Vector2(16, 55)
	interaction_help.size = Vector2(498, 18)
	interaction_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_panel.add_child(interaction_help)


func _build_overlay(root: Control) -> void:
	overlay = ColorRect.new()
	overlay.name = "HideoutPauseOverlay"
	overlay.color = Color(0.003, 0.007, 0.008, 0.91)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	overlay.z_index = 50
	root.add_child(overlay)

	var sigil := _hud_label("✦", 31, Color(0.46, 0.68, 0.63))
	sigil.name = "PauseSigil"
	sigil.anchor_left = 0.5
	sigil.anchor_top = 0.3
	sigil.anchor_right = 0.5
	sigil.anchor_bottom = 0.3
	sigil.offset_left = -36.0
	sigil.offset_top = -28.0
	sigil.offset_right = 36.0
	sigil.offset_bottom = 28.0
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(sigil)

	overlay_title = _hud_label("은신처 일시정지", 34, COLOR_IVORY)
	overlay_title.name = "PauseTitle"
	overlay_title.anchor_left = 0.5
	overlay_title.anchor_top = 0.42
	overlay_title.anchor_right = 0.5
	overlay_title.anchor_bottom = 0.42
	overlay_title.offset_left = -420.0
	overlay_title.offset_top = -34.0
	overlay_title.offset_right = 420.0
	overlay_title.offset_bottom = 34.0
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_title)

	overlay_detail = _hud_label("ESC 또는 클릭 · 계속", 16, Color(0.62, 0.68, 0.64))
	overlay_detail.name = "PauseDetail"
	overlay_detail.anchor_left = 0.5
	overlay_detail.anchor_top = 0.54
	overlay_detail.anchor_right = 0.5
	overlay_detail.anchor_bottom = 0.54
	overlay_detail.offset_left = -420.0
	overlay_detail.offset_top = -35.0
	overlay_detail.offset_right = 420.0
	overlay_detail.offset_bottom = 70.0
	overlay_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(overlay_detail)

	var pause_hint := _hud_label("안전 지역에서는 전투가 발생하지 않습니다", 12, Color(0.36, 0.49, 0.46))
	pause_hint.name = "PauseHint"
	pause_hint.anchor_left = 0.5
	pause_hint.anchor_top = 0.7
	pause_hint.anchor_right = 0.5
	pause_hint.anchor_bottom = 0.7
	pause_hint.offset_left = -280.0
	pause_hint.offset_top = -16.0
	pause_hint.offset_right = 280.0
	pause_hint.offset_bottom = 18.0
	pause_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(pause_hint)


func _hud_label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.72))
	label.add_theme_constant_override("outline_size", 2)
	return label


func update_health(_current: float, _maximum: float) -> void:
	pass


func update_stamina(_current: float, _maximum: float) -> void:
	pass


func update_weapon_state(_text_value: String, _color := Color(0.72, 0.77, 0.78)) -> void:
	pass


func update_torch(enabled: bool) -> void:
	if not is_instance_valid(torch_status_label):
		return
	torch_status_label.text = "횃불 · %s" % ("켜짐" if enabled else "꺼짐")
	torch_status_label.add_theme_color_override(
		"font_color",
		COLOR_AMBER if enabled else Color(0.39, 0.44, 0.42)
	)


func update_objective(_enemies_left: int, _loot_count: int, _traps_disarmed: int) -> void:
	pass


func show_hit(_headshot := false) -> void:
	pass


func flash_damage() -> void:
	pass


func show_trap_meter(_title_text: String, _zone_start: float, _zone_end: float) -> void:
	pass


func update_trap_meter(_value: float, _zone_start: float, _zone_end: float) -> void:
	pass


func hide_trap_meter() -> void:
	pass
