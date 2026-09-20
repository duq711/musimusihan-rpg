extends CanvasLayer
class_name CampOverlay

signal action_requested(action_id: String)
signal leave_requested
signal pack_requested

const PANEL_COLOR := Color(0.018, 0.022, 0.019, 0.96)
const BORDER_COLOR := Color(0.47, 0.41, 0.28)
const TEXT_COLOR := Color(0.87, 0.84, 0.72)
const MUTED_COLOR := Color(0.63, 0.65, 0.55)

var overlay_root: ColorRect
var panel_root: PanelContainer
var title_label: Label
var stats_label: Label
var stress_label: Label
var resources_label: Label
var risk_label: Label
var progress_bar: ProgressBar
var status_label: Label
var action_scroll: ScrollContainer
var action_list: VBoxContainer
var action_buttons: Dictionary = {}
var action_details: Dictionary = {}
var action_costs: Dictionary = {}
var action_reasons: Dictionary = {}
var action_ingredients: Dictionary = {}
var action_cards: Dictionary = {}
var category_buttons: Dictionary = {}
var category_tabs: HBoxContainer
var selected_category := "rest"
var cooking_hint_label: Label
var activity_label: Label
var leave_button: Button
var pack_button: Button
var _snapshot: Dictionary = {}
var _action_ids: Array[String] = []


func _ready() -> void:
	_ensure_built()
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_ensure_built()
	_refresh()


func show_camp() -> void:
	_ensure_built()
	_update_layout()
	_refresh()
	overlay_root.visible = true


func hide_camp() -> void:
	if is_instance_valid(overlay_root):
		overlay_root.visible = false


func _ensure_built() -> void:
	if is_instance_valid(overlay_root):
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 85
	overlay_root = ColorRect.new()
	overlay_root.name = "CampBackdrop"
	overlay_root.color = Color(0.005, 0.008, 0.006, 0.12)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.visible = false
	add_child(overlay_root)
	panel_root = PanelContainer.new()
	panel_root.name = "CampPanel"
	panel_root.add_theme_stylebox_override("panel", _style(PANEL_COLOR, BORDER_COLOR, 2))
	overlay_root.add_child(panel_root)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel_root.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)
	title_label = _label("모닥불 곁", 23, TEXT_COLOR)
	content.add_child(title_label)
	category_tabs = HBoxContainer.new()
	category_tabs.name = "CampActivityTabs"
	category_tabs.add_theme_constant_override("separation", 8)
	content.add_child(category_tabs)
	for category: String in ["rest", "cooking"]:
		var tab := _button("휴식" if category == "rest" else "요리")
		tab.name = "CampTab_" + category
		tab.toggle_mode = true
		tab.custom_minimum_size.y = 34
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(select_category.bind(category))
		category_tabs.add_child(tab)
		category_buttons[category] = tab
	action_scroll = ScrollContainer.new()
	action_scroll.name = "CampContentScroll"
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.custom_minimum_size = Vector2(0.0, 60.0)
	content.add_child(action_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	action_scroll.add_child(body)
	stats_label = _label("", 13, TEXT_COLOR)
	body.add_child(stats_label)
	stress_label = _label("", 13, DungeonHUD.stress_color(0.0).lightened(0.2))
	body.add_child(stress_label)
	resources_label = _label("", 12, Color(0.78, 0.73, 0.53))
	body.add_child(resources_label)
	risk_label = _label("", 12, Color(0.86, 0.61, 0.35))
	body.add_child(risk_label)
	cooking_hint_label = _label("재료를 불에 조리해 완성 즉시 먹습니다. 완성 전에는 회복되지 않습니다.", 13, Color(0.81, 0.76, 0.56))
	cooking_hint_label.name = "CampCookingHint"
	body.add_child(cooking_hint_label)
	action_list = VBoxContainer.new()
	action_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_list.add_theme_constant_override("separation", 8)
	body.add_child(action_list)
	activity_label = _label("", 16, TEXT_COLOR)
	activity_label.name = "CampActiveActivity"
	body.add_child(activity_label)
	progress_bar = ProgressBar.new()
	progress_bar.name = "CampProgress"
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.step = 0.0
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0.0, 10.0)
	progress_bar.add_theme_font_size_override("font_size", 1)
	progress_bar.add_theme_stylebox_override("background", _style(Color(0.06, 0.07, 0.05), Color(0.24, 0.25, 0.19)))
	progress_bar.add_theme_stylebox_override("fill", _style(Color(0.66, 0.45, 0.19), Color(0.81, 0.59, 0.27)))
	body.add_child(progress_bar)
	status_label = _label("", 12, MUTED_COLOR)
	body.add_child(status_label)
	var exit_actions := HBoxContainer.new()
	exit_actions.name = "CampExitActions"
	exit_actions.add_theme_constant_override("separation", 8)
	content.add_child(exit_actions)
	leave_button = _button("일어서기 · Esc")
	leave_button.name = "StandUpButton"
	leave_button.custom_minimum_size.y = 34.0
	leave_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave_button.pressed.connect(_on_leave_requested)
	exit_actions.add_child(leave_button)
	pack_button = _button("야영지 정리")
	pack_button.name = "PackCampButton"
	pack_button.custom_minimum_size = Vector2(120.0, 34.0)
	pack_button.tooltip_text = "천막과 모닥불을 정리합니다. 사용한 야영 도구는 돌아오지 않습니다."
	pack_button.pressed.connect(_on_pack_requested)
	exit_actions.add_child(pack_button)
	if is_inside_tree():
		get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func _update_layout() -> void:
	if not is_instance_valid(panel_root) or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var inset := 40.0 if viewport_size.x >= 1000.0 else 12.0
	# Keep the fire at the center of the seated view visible, including at
	# smaller window sizes. Long recipe text remains in the existing scroll.
	var width := minf(510.0, maxf(0.0, viewport_size.x * 0.44))
	var vertical_inset := 70.0 if viewport_size.y >= 680.0 else 12.0
	panel_root.position = Vector2(viewport_size.x - inset - width, vertical_inset)
	panel_root.size = Vector2(width, maxf(0.0, viewport_size.y - vertical_inset * 2.0))


func _refresh() -> void:
	var resting := str(_snapshot.get("state", "planning")) == "resting"
	var cooking := resting and bool(_snapshot.get("is_cooking", false))
	var actions: Array = _snapshot.get("actions", [])
	var has_cooking := actions.any(func(action: Dictionary) -> bool: return _action_category(action) == "cooking")
	if cooking:
		selected_category = "cooking"
	elif not has_cooking:
		selected_category = "rest"
	var was_resting := not action_list.visible
	# During the actual rest, keep progress and interruption feedback in view
	# instead of filling the panel with three unavailable action cards.
	action_list.visible = not resting
	if was_resting != resting:
		action_scroll.scroll_vertical = 0
	title_label.text = "모닥불 곁 · 조리 중" if cooking else ("모닥불 곁 · 휴식 중" if resting else "모닥불 곁")
	category_tabs.visible = has_cooking and not resting
	for category: String in category_buttons:
		(category_buttons[category] as Button).set_pressed_no_signal(category == selected_category)
		(category_buttons[category] as Button).disabled = resting
	cooking_hint_label.visible = has_cooking and not resting and selected_category == "cooking"
	stats_label.text = "체력 %d/%d    기력 %d/%d\n포만감 %d    수분 %d    상태 · %s" % [roundi(float(_snapshot.get("health", 0.0))), roundi(float(_snapshot.get("max_health", 100.0))), roundi(float(_snapshot.get("stamina", 0.0))), roundi(float(_snapshot.get("max_stamina", 100.0))), roundi(float(_snapshot.get("hunger", 0.0))), roundi(float(_snapshot.get("thirst", 0.0))), str(_snapshot.get("conditions", "안정"))]
	var stress_maximum := maxf(1.0, float(_snapshot.get("max_stress", 100.0)))
	var stress := clampf(float(_snapshot.get("stress", 0.0)), 0.0, stress_maximum)
	var stage := str(_snapshot.get("stress_stage", StressProfile.stage_name(stress / stress_maximum * StressProfile.MAX_STRESS)))
	stress_label.text = "스트레스 %d/%d · %s · 높을수록 불안정" % [roundi(stress), roundi(stress_maximum), stage]
	stress_label.add_theme_color_override("font_color", DungeonHUD.stress_color(stress / stress_maximum * StressProfile.MAX_STRESS).lightened(0.2))
	var counts: Dictionary = _snapshot.get("inventory_counts", {})
	resources_label.text = "온기 %d · 야영 도구 %d · 식량 %d · 물 %d · 붕대 %d\n%s" % [int(_snapshot.get("warmth", 3)), int(counts.get("camp_kit", 0)), int(counts.get("pilgrim_ration", 0)), int(counts.get("boiled_rainwater", 0)), int(counts.get("linen_bandage", 0)), "야영 도구 사용 완료 · 일어서도 야영지는 유지됩니다." if bool(_snapshot.get("kit_spent", false)) else "설치를 확정하면 야영 도구 1개 소비"]
	if has_cooking:
		resources_label.text = "온기 %d · 야영 도구 %d · 식량 %d · 물 %d · 붕대 %d\n생고기 %d · 식용 버섯 %d\n%s" % [int(_snapshot.get("warmth", 3)), int(counts.get("camp_kit", 0)), int(counts.get("pilgrim_ration", 0)), int(counts.get("boiled_rainwater", 0)), int(counts.get("linen_bandage", 0)), int(counts.get("raw_meat", 0)), int(counts.get("edible_mushroom", 0)), "야영 도구 사용 완료 · 일어서도 야영지는 유지됩니다." if bool(_snapshot.get("kit_spent", false)) else "설치를 확정하면 야영 도구 1개 소비"]
	risk_label.text = "휴식 중에는 던전이 진행됩니다. 적 접근·피격 시 즉시 중단됩니다." if resting else "준비 중에는 시간이 멈춥니다. 휴식을 시작하면 적도 움직입니다."
	if cooking:
		risk_label.text = "조리 중에도 던전이 진행됩니다. 적 접근·피격 시 즉시 중단되며 재료는 반환되지 않습니다."
	elif has_cooking and not resting:
		risk_label.text = "준비 중에는 시간이 멈춥니다. 휴식·요리를 시작하면 적도 움직입니다."
	progress_bar.value = clampf(float(_snapshot.get("progress", 0.0)), 0.0, 1.0) if resting else 0.0
	progress_bar.visible = resting
	activity_label.visible = resting and not str(_snapshot.get("action_title", "")).is_empty()
	activity_label.text = "%s · %d%%" % [str(_snapshot.get("action_title", "")), roundi(progress_bar.value * 100.0)]
	for action: Dictionary in actions:
		if str(action.get("id", "")) == str(_snapshot.get("active_action_id", "")):
			activity_label.text += " · %.1f초 남음" % [maxf(0.0, float(action.get("duration", 0.0)) * (1.0 - progress_bar.value))]
			break
	if cooking:
		activity_label.text += "\n완성하면 바로 먹고 회복합니다."
	status_label.text = str(_snapshot.get("status", ""))
	if status_label.text.is_empty():
		status_label.text = "중단해도 이미 소비한 물품은 반환되지 않습니다." if resting else ("필요한 요리를 선택하세요." if selected_category == "cooking" else "필요한 휴식을 선택하세요.")
	leave_button.text = "조리 중단 · 일어서기 · 재료 반환 없음" if cooking else ("휴식 중단 · 일어서기 · 소모품 반환 없음" if resting else "일어서기 · Esc")
	pack_button.visible = not resting
	pack_button.disabled = resting
	var ids: Array[String] = []
	for action: Dictionary in actions:
		ids.append(str(action.get("id", "")))
	if ids != _action_ids:
		_build_actions(actions)
	for action: Dictionary in actions:
		var id := str(action.get("id", ""))
		var button := action_buttons[id] as Button
		button.text = str(action.get("title", id))
		button.disabled = resting or not bool(action.get("enabled", false))
		(action_cards[id] as PanelContainer).visible = _action_category(action) == selected_category
		(action_details[id] as Label).text = str(action.get("description", ""))
		(action_costs[id] as Label).text = "%s · %.1f초" % [str(action.get("cost", "")), float(action.get("duration", 0.0))]
		(action_ingredients[id] as Label).text = str(action.get("ingredient_text", ""))
		(action_ingredients[id] as Label).visible = not (action_ingredients[id] as Label).text.is_empty()
		(action_reasons[id] as Label).text = ("조리 중에는 다른 행동을 시작할 수 없습니다." if cooking else "휴식 중에는 다른 행동을 시작할 수 없습니다.") if resting else str(action.get("reason", ""))
		(action_reasons[id] as Label).visible = not (action_reasons[id] as Label).text.is_empty()
	# Wrapped labels can report an oversized minimum while the newly built
	# panel still has zero width. Fit again after container layout settles so
	# opening directly in a small window cannot strand the leave button below it.
	_update_layout.call_deferred()


func _build_actions(actions: Array) -> void:
	for child in action_list.get_children():
		child.free()
	_action_ids.clear()
	action_buttons.clear()
	action_details.clear()
	action_costs.clear()
	action_reasons.clear()
	action_ingredients.clear()
	action_cards.clear()
	for action: Dictionary in actions:
		var id := str(action.get("id", ""))
		_action_ids.append(id)
		var card := PanelContainer.new()
		card.name = "CampAction_" + id.replace(":", "_")
		card.add_theme_stylebox_override("panel", _style(Color(0.035, 0.041, 0.032), Color(0.26, 0.28, 0.21)))
		action_list.add_child(card)
		action_cards[id] = card
		var margin := MarginContainer.new()
		for side in ["left", "top", "right", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		card.add_child(margin)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		margin.add_child(column)
		var button := _button(str(action.get("title", id)))
		button.pressed.connect(_on_action_pressed.bind(id))
		column.add_child(button)
		action_buttons[id] = button
		var detail := _label("", 12, TEXT_COLOR)
		column.add_child(detail)
		action_details[id] = detail
		var cost := _label("", 11, Color(0.78, 0.73, 0.53))
		column.add_child(cost)
		action_costs[id] = cost
		var ingredients := _label("", 12, Color(0.72, 0.79, 0.62))
		column.add_child(ingredients)
		action_ingredients[id] = ingredients
		var reason := _label("", 11, Color(0.84, 0.47, 0.34))
		column.add_child(reason)
		action_reasons[id] = reason


func _on_action_pressed(action_id: String) -> void:
	if not overlay_root.visible or str(_snapshot.get("state", "planning")) == "resting":
		return
	for action: Dictionary in _snapshot.get("actions", []):
		if str(action.get("id", "")) == action_id and bool(action.get("enabled", false)) and _action_category(action) == selected_category:
			action_requested.emit(action_id)
			return


func select_category(category: String) -> void:
	if category not in ["rest", "cooking"] or str(_snapshot.get("state", "planning")) == "resting":
		return
	selected_category = category
	_refresh()
	action_scroll.scroll_vertical = 0


func _action_category(action: Dictionary) -> String:
	return str(action.get("category", "cooking" if str(action.get("id", "")).begins_with("cook:") else "rest"))


func _on_leave_requested() -> void:
	if overlay_root.visible:
		leave_requested.emit()


func _on_pack_requested() -> void:
	if overlay_root.visible and str(_snapshot.get("state", "planning")) != "resting":
		pack_requested.emit()


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_stylebox_override("normal", _style(Color(0.09, 0.105, 0.072), BORDER_COLOR))
	button.add_theme_stylebox_override("hover", _style(Color(0.16, 0.17, 0.11), Color(0.73, 0.62, 0.39)))
	button.add_theme_stylebox_override("pressed", _style(Color(0.06, 0.07, 0.05), BORDER_COLOR))
	button.add_theme_stylebox_override("disabled", _style(Color(0.025, 0.029, 0.024), Color(0.21, 0.23, 0.18)))
	return button


func _style(background: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	return style
