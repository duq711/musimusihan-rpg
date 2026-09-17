extends Control
class_name BodyHealthPanel
## The artwork belongs to the inventory. This transparent layer holds only
## production health readouts, anatomical hit regions and treatment controls.

signal treatment_part_selected(part_id: String)
signal consumable_requested(item_id: String)

const FONT := preload("res://assets/fonts/NotoSerifKR-Variable.ttf")
const NUMBER_FONT := preload("res://assets/fonts/Cinzel-Variable.ttf")
const CARD := preload("res://scripts/health_gothic_card.gd")
const PART_ORDER := ["head", "thorax", "stomach", "left_arm", "right_arm", "left_leg", "right_leg"]
const PART_NAMES := {"head": "머리", "thorax": "흉부", "stomach": "복부", "right_arm": "오른쪽 팔", "left_arm": "왼쪽 팔", "right_leg": "오른쪽 다리", "left_leg": "왼쪽 다리"}
const CONDITION_NAMES := {"fracture": "골절", "bleeding": "출혈", "curse": "저주", "paralysis": "마비", "poison": "독"}
const TREATMENT_IDS := ["linen_bandage", "healing_draught", "surgery_kit", "splint", "antidote", "purifying_salt", "nerve_tonic"]
const COLOR_TEXT := Color(0.82, 0.75, 0.63)
const COLOR_MUTED := Color(0.59, 0.54, 0.45)
const COLOR_GOLD := Color(0.73, 0.62, 0.43)
const COLOR_RED := Color(0.36, 0.075, 0.060)
const CARD_SIZE := Vector2(184, 70)
const POPUP_LEFT_POSITION := Vector2(36, 282)
const POPUP_RIGHT_POSITION := Vector2(265, 282)
const CARD_POSITIONS := {"head": Vector2(415, 104), "thorax": Vector2(270, 205), "stomach": Vector2(270, 350), "right_arm": Vector2(72, 270), "left_arm": Vector2(430, 270), "right_leg": Vector2(78, 485), "left_leg": Vector2(410, 485)}
const FIGURE_ORIGIN := Vector2(340, 80)
# These invisible regions follow the figure in the background illustration.
# Anatomical right is on the viewer's left. No polygon is painted over the art.
const PART_POLYGONS := {
	"head": [Vector2(-31, 0), Vector2(31, 0), Vector2(39, 30), Vector2(26, 69), Vector2(-26, 69), Vector2(-39, 30)],
	"thorax": [Vector2(-30, 70), Vector2(30, 70), Vector2(69, 88), Vector2(51, 168), Vector2(-51, 168), Vector2(-69, 88)],
	"stomach": [Vector2(-50, 170), Vector2(50, 170), Vector2(50, 241), Vector2(28, 268), Vector2(-28, 268), Vector2(-50, 241)],
	"right_arm": [Vector2(-70, 85), Vector2(-103, 107), Vector2(-125, 183), Vector2(-151, 243), Vector2(-137, 278), Vector2(-111, 258), Vector2(-92, 199), Vector2(-61, 149)],
	"left_arm": [Vector2(70, 85), Vector2(103, 107), Vector2(125, 183), Vector2(151, 243), Vector2(137, 278), Vector2(111, 258), Vector2(92, 199), Vector2(61, 149)],
	"right_leg": [Vector2(-51, 258), Vector2(-4, 270), Vector2(-12, 362), Vector2(-25, 469), Vector2(-46, 502), Vector2(-82, 502), Vector2(-73, 477), Vector2(-58, 450), Vector2(-54, 360)],
	"left_leg": [Vector2(51, 258), Vector2(4, 270), Vector2(12, 362), Vector2(25, 469), Vector2(46, 502), Vector2(82, 502), Vector2(73, 477), Vector2(58, 450), Vector2(54, 360)]
}
const PART_CENTERS := {"head": Vector2(0, 33), "thorax": Vector2(0, 112), "stomach": Vector2(0, 216), "right_arm": Vector2(-108, 182), "left_arm": Vector2(108, 182), "right_leg": Vector2(-39, 390), "left_leg": Vector2(39, 390)}

var part_buttons: Dictionary = {}
var part_name_labels: Dictionary = {}
var part_value_labels: Dictionary = {}
var part_condition_labels: Dictionary = {}
var part_bars: Dictionary = {}
var treatment_buttons: Dictionary = {}
var automatic_button: Button
var total_label: Label
var conditions_label: Label
var selected_label: Label
var selected_health_label: Label
var guidance_label: Label
var treatment_popup: Panel
var popup_close_button: Button
var treatment_scroll: ScrollContainer
var treatment_grid: GridContainer
var snapshot: Dictionary = {}
var _built := false
var _treatment_signature := ""
var _bar_fill: StyleBoxTexture


func _ready() -> void:
	_build()


func show_snapshot(body: Dictionary, inventory: ExpeditionInventory) -> void:
	_build()
	snapshot = body.duplicate(true)
	var parts: Dictionary = snapshot.get("parts", {})
	var selected := str(snapshot.get("selected_part", ""))
	var available := not parts.is_empty()
	total_label.text = "%d / %d" % [ceili(float(body.get("health", 0.0))), roundi(float(body.get("max_health", 440.0)))] if available else "— / 440"
	conditions_label.text = _condition_text(body.get("conditions", {}))
	if conditions_label.text.is_empty():
		conditions_label.text = "상태이상 없음" if available else "건강 상태를 확인할 수 없습니다."
	for part_id in PART_ORDER:
		var data: Dictionary = parts.get(part_id, {})
		var button: Button = part_buttons[part_id]
		button.disabled = data.is_empty()
		var current := float(data.get("health", 0.0))
		var maximum := maxf(1.0, float(data.get("max_health", 1.0)))
		var blacked := bool(data.get("blacked", current <= 0.0)) and not data.is_empty()
		button.set("selected", selected == part_id)
		button.set("blacked", blacked)
		button.set_meta("blacked", blacked)
		button.set_meta("selected", selected == part_id)
		button.queue_redraw()
		var value_label: Label = part_value_labels[part_id]
		value_label.text = "%d/%d" % [ceili(current), roundi(maximum)] if not data.is_empty() else "—"
		value_label.add_theme_color_override("font_color", COLOR_TEXT if not blacked else COLOR_MUTED)
		var bar: ProgressBar = part_bars[part_id]
		bar.max_value = maximum
		bar.value = current
		bar.size = Vector2(96, 13)
		var note: Label = part_condition_labels[part_id]
		note.text = _condition_text(data.get("conditions", {}))
		if blacked:
			note.text = "손상 · 일반 치료 불가" + (" / " + note.text if not note.text.is_empty() else "")
		note.add_theme_color_override("font_color", Color(0.75, 0.49, 0.34))
		button.tooltip_text = "%s  %d / %d" % [str(PART_NAMES[part_id]), ceili(current), roundi(maximum)]
		if not note.text.is_empty():
			button.tooltip_text += "\n" + note.text
	automatic_button.disabled = not available
	automatic_button.add_theme_stylebox_override("normal", _style(Color(0.065, 0.040, 0.025), COLOR_GOLD if selected.is_empty() else Color(0.30, 0.25, 0.18), 1))
	selected_label.text = "치료 · 자동 선택" if selected.is_empty() else "치료 · %s" % str(PART_NAMES.get(selected, selected))
	var selected_data: Dictionary = parts.get(selected, {})
	selected_health_label.visible = not selected_data.is_empty()
	selected_health_label.text = "%d/%d" % [ceili(float(selected_data.get("health", 0.0))), roundi(float(selected_data.get("max_health", 0.0)))] if not selected_data.is_empty() else ""
	_position_treatment_popup(selected)
	if bool(selected_data.get("blacked", false)):
		guidance_label.text = "일반 치료 불가. 수술 도구나 고위 마법으로 1까지 복구한 뒤 치료하세요."
	else:
		guidance_label.text = "치료품을 고르세요. 치료 마법도 선택한 부위를 대상으로 합니다."
	_update_treatments(inventory, available)
	queue_redraw()


func close_treatment() -> void:
	if is_instance_valid(treatment_popup):
		treatment_popup.hide()


func reset_presentation() -> void:
	# The treatment target belongs to the player, not to this transient drawer.
	close_treatment()


func handle_cancel() -> bool:
	if is_instance_valid(treatment_popup) and treatment_popup.visible:
		close_treatment()
		return true
	return false


func _build() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(1280, 720)
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_PASS
	theme = Theme.new()
	var readable_font := FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	theme.default_font = readable_font
	_bar_fill = _make_bar_fill()
	for part_id in PART_ORDER:
		var button: Button = CARD.new()
		button.name = part_id + "Part"
		button.set("part_id", part_id)
		button.position = CARD_POSITIONS[part_id]
		button.size = CARD_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_part.bind(part_id))
		add_child(button)
		part_buttons[part_id] = button
		part_name_labels[part_id] = _label(button, "PartName", str(PART_NAMES[part_id]), Vector2(32, 1), Vector2(149, 28), 18, COLOR_TEXT)
		var value_label := _label(button, "HealthValue", "", Vector2(131, 28), Vector2(50, 25), 15, COLOR_TEXT)
		value_label.add_theme_font_override("font", NUMBER_FONT)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		part_value_labels[part_id] = value_label
		var bar := ProgressBar.new()
		bar.name = "PartHealthBar"
		bar.position = Vector2(32, 33)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var track := _style(Color(0.008, 0.007, 0.006, 0.98), Color(0.34, 0.29, 0.22), 1)
		track.content_margin_left = 2
		track.content_margin_top = 2
		track.content_margin_right = 2
		track.content_margin_bottom = 2
		bar.add_theme_stylebox_override("background", track)
		bar.add_theme_stylebox_override("fill", _bar_fill)
		bar.size = Vector2(96, 13)
		button.add_child(bar)
		part_bars[part_id] = bar
		var note := _label(button, "PartConditions", "", Vector2(2, 55), Vector2(180, 16), 11, COLOR_MUTED)
		note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		part_condition_labels[part_id] = note
	_build_treatment_popup()


func _build_treatment_popup() -> void:
	treatment_popup = Panel.new()
	treatment_popup.name = "TreatmentPopup"
	treatment_popup.position = POPUP_RIGHT_POSITION
	treatment_popup.size = Vector2(360, 308)
	treatment_popup.z_index = 30
	treatment_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var frame := _style(Color(0.022, 0.017, 0.013, 0.985), Color(0.42, 0.34, 0.23), 1)
	frame.shadow_color = Color(0, 0, 0, 0.8)
	frame.shadow_size = 12
	treatment_popup.add_theme_stylebox_override("panel", frame)
	add_child(treatment_popup)
	treatment_popup.draw.connect(_draw_popup_frame)
	selected_label = _label(treatment_popup, "TreatmentTarget", "", Vector2(19, 12), Vector2(210, 31), 19, COLOR_TEXT)
	selected_health_label = _label(treatment_popup, "TreatmentPartHealth", "", Vector2(237, 17), Vector2(72, 25), 17, COLOR_TEXT)
	selected_health_label.add_theme_font_override("font", NUMBER_FONT)
	selected_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	selected_health_label.hide()
	popup_close_button = _button(treatment_popup, "CloseTreatment", "×", Vector2(318, 12), Vector2(28, 28))
	popup_close_button.add_theme_font_size_override("font_size", 22)
	popup_close_button.tooltip_text = "치료창 닫기 · 선택 부위는 유지"
	popup_close_button.pressed.connect(close_treatment)
	_label(treatment_popup, "TotalCaption", "전체 체력", Vector2(20, 47), Vector2(88, 20), 13, COLOR_MUTED)
	total_label = _label(treatment_popup, "TotalHealth", "— / 440", Vector2(110, 47), Vector2(116, 20), 14, COLOR_TEXT)
	total_label.add_theme_font_override("font", NUMBER_FONT)
	conditions_label = _label(treatment_popup, "ActiveConditions", "", Vector2(20, 71), Vector2(322, 20), 13, Color(0.70, 0.48, 0.32))
	conditions_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	guidance_label = _label(treatment_popup, "TreatmentGuidance", "", Vector2(20, 98), Vector2(320, 40), 13, COLOR_MUTED)
	guidance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(treatment_popup, "TreatmentHeading", "보유 치료품", Vector2(20, 146), Vector2(200, 22), 14, COLOR_TEXT)
	automatic_button = _button(treatment_popup, "AutomaticTarget", "자동 선택", Vector2(244, 141), Vector2(96, 27))
	automatic_button.pressed.connect(_select_part.bind(""))
	treatment_scroll = ScrollContainer.new()
	treatment_scroll.name = "TreatmentScroll"
	treatment_scroll.position = Vector2(20, 179)
	treatment_scroll.size = Vector2(320, 117)
	treatment_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	treatment_popup.add_child(treatment_scroll)
	treatment_grid = GridContainer.new()
	treatment_grid.columns = 2
	treatment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	treatment_grid.add_theme_constant_override("h_separation", 6)
	treatment_grid.add_theme_constant_override("v_separation", 5)
	treatment_scroll.add_child(treatment_grid)
	treatment_popup.hide()


func _update_treatments(inventory: ExpeditionInventory, available: bool) -> void:
	var stacks: Dictionary = {}
	if inventory != null:
		for stack in inventory.slots:
			var item_id := str(stack.get("id", ""))
			var definition := ExpeditionInventory.get_item_definition(item_id)
			var effect := str(definition.get("effect", ""))
			if TREATMENT_IDS.has(item_id) or (str(definition.get("category", "")) == "consumable" and (effect.begins_with("heal") or effect in ["bandage", "cure_condition", "surgery"])):
				stacks[item_id] = int(stacks.get(item_id, 0)) + int(stack.get("quantity", 0))
	var signature := JSON.stringify(stacks) + str(available)
	if signature == _treatment_signature:
		return
	_treatment_signature = signature
	for child in treatment_grid.get_children():
		treatment_grid.remove_child(child)
		child.queue_free()
	treatment_buttons.clear()
	for item_id: String in stacks:
		var definition := ExpeditionInventory.get_item_definition(item_id)
		var button := _button(treatment_grid, "Treatment_" + item_id, "%s ×%d" % [str(definition.get("name", item_id)), int(stacks[item_id])], Vector2.ZERO, Vector2(154, 25))
		button.custom_minimum_size = Vector2(154, 25)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(definition.get("summary", "")) + "\n" + str(definition.get("description", ""))
		button.disabled = not available
		button.pressed.connect(func() -> void: consumable_requested.emit(item_id))
		treatment_buttons[item_id] = button
	if stacks.is_empty():
		_label(treatment_grid, "NoTreatments", "가방에 치료품이 없습니다.", Vector2.ZERO, Vector2(310, 28), 13, COLOR_MUTED)


func _select_part(part_id: String) -> void:
	if part_id.is_empty() or snapshot.get("parts", {}).has(part_id):
		_position_treatment_popup(part_id)
		treatment_popup.show()
		treatment_part_selected.emit(part_id)


func _position_treatment_popup(part_id: String) -> void:
	treatment_popup.position = POPUP_LEFT_POSITION if part_id in ["left_arm", "left_leg"] else POPUP_RIGHT_POSITION


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for part_id in PART_ORDER:
			if Geometry2D.is_point_in_polygon(event.position - FIGURE_ORIGIN, PackedVector2Array(PART_POLYGONS[part_id])):
				_select_part(part_id)
				accept_event()
				return
		if treatment_popup.visible and not treatment_popup.get_rect().has_point(event.position):
			close_treatment()
			accept_event()


func _has_point(point: Vector2) -> bool:
	# The sibling chrome owns navigation, survival readouts and its close
	# control. A transparent full-frame Control must not intercept them.
	if is_instance_valid(treatment_popup) and treatment_popup.visible and treatment_popup.get_rect().has_point(point):
		return true
	return point.y >= 65.0 and point.y < 600.0 and point.x >= 20.0 and point.x < 638.0


func _draw() -> void:
	if not _built:
		return
	var selected := str(snapshot.get("selected_part", ""))
	# The central plates sit on the figure. Outer plates use restrained leader
	# lines, with no opaque silhouette or generic dashboard behind them.
	for part_id in ["head", "right_arm", "left_arm", "right_leg", "left_leg"]:
		var card: Vector2 = CARD_POSITIONS[part_id]
		var target: Vector2 = FIGURE_ORIGIN + PART_CENTERS[part_id]
		var from := card + Vector2(CARD_SIZE.x if card.x < target.x else 0, 27)
		var bend := Vector2(from.x + (18 if from.x < target.x else -18), from.y)
		var color := Color(0.49, 0.39, 0.25, 0.38) if selected != part_id else Color(0.71, 0.58, 0.37, 0.66)
		draw_polyline(PackedVector2Array([from, bend, target]), color, 1.0, true)


func _draw_popup_frame() -> void:
	var edge := Color(0.64, 0.51, 0.32, 0.72)
	for corner in [Vector2(6, 6), Vector2(354, 6), Vector2(6, 302), Vector2(354, 302)]:
		var dx := 1.0 if corner.x < 180.0 else -1.0
		var dy := 1.0 if corner.y < 154.0 else -1.0
		treatment_popup.draw_polyline(PackedVector2Array([corner + Vector2(0, dy * 17), corner, corner + Vector2(dx * 17, 0)]), edge, 1.0, true)
	treatment_popup.draw_line(Vector2(20, 93), Vector2(340, 93), Color(edge, 0.32), 1.0)
	treatment_popup.draw_line(Vector2(20, 172), Vector2(340, 172), Color(edge, 0.32), 1.0)


func _make_bar_fill() -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.30, 0.73, 0.91, 1.0])
	gradient.colors = PackedColorArray([Color(0.57, 0.25, 0.20), Color(0.39, 0.13, 0.105), Color(0.34, 0.085, 0.068), Color(0.28, 0.064, 0.055), Color(0.19, 0.035, 0.029), Color(0.095, 0.015, 0.012)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 96
	texture.height = 13
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	var fill := StyleBoxTexture.new()
	fill.texture = texture
	fill.expand_margin_left = -2
	fill.expand_margin_top = -2
	fill.expand_margin_right = -2
	fill.expand_margin_bottom = -2
	return fill


func _part_color(data: Dictionary) -> Color:
	return Color(0.012, 0.009, 0.007) if float(data.get("health", 0.0)) <= 0.0 else COLOR_RED


func _condition_text(conditions: Variant) -> String:
	var labels: Array[String] = []
	if conditions is Dictionary:
		for condition_id in conditions:
			if float(conditions[condition_id]) > 0.0:
				labels.append(str(CONDITION_NAMES.get(str(condition_id), condition_id)))
	return " · ".join(labels)


func _label(parent: Node, node_name: String, text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = at
	label.size = extent
	label.add_theme_font_override("font", theme.default_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, node_name: String, text_value: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = at
	button.size = extent
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", theme.default_font)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.92, 0.83, 0.66))
	button.add_theme_color_override("font_pressed_color", Color(0.98, 0.89, 0.72))
	button.add_theme_stylebox_override("normal", _style(Color(0.047, 0.032, 0.020, 0.92), Color(0.31, 0.26, 0.18), 1))
	button.add_theme_stylebox_override("hover", _style(Color(0.13, 0.067, 0.035), COLOR_GOLD, 1))
	button.add_theme_stylebox_override("pressed", _style(Color(0.19, 0.071, 0.036), COLOR_GOLD, 1))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, COLOR_GOLD, 1))
	parent.add_child(button)
	return button


func _style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	return style
