extends Control
class_name BodyHealthPanel
## Presentation consumes the player's body snapshot; treatment always returns
## through the inventory's existing production consumable signal.

signal treatment_part_selected(part_id: String)
signal consumable_requested(item_id: String)

const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const PART_ORDER := ["head", "thorax", "stomach", "left_arm", "right_arm", "left_leg", "right_leg"]
const CONDITION_NAMES := {"fracture": "골절", "bleeding": "출혈", "curse": "저주", "paralysis": "마비", "poison": "독"}
const TREATMENT_IDS := ["linen_bandage", "healing_draught", "surgery_kit", "splint", "antidote", "purifying_salt", "nerve_tonic"]
const COLOR_TEXT := Color(0.85, 0.86, 0.80)
const COLOR_MUTED := Color(0.52, 0.56, 0.50)
const COLOR_GREEN := Color(0.49, 0.68, 0.39)
const COLOR_GOLD := Color(0.80, 0.70, 0.40)
const CARD_POSITIONS := {"head": Vector2(18, 91), "left_arm": Vector2(18, 187), "left_leg": Vector2(18, 286), "thorax": Vector2(550, 91), "stomach": Vector2(550, 162), "right_arm": Vector2(550, 233), "right_leg": Vector2(550, 304)}
const FIGURE_ORIGIN := Vector2(385, 91)
const PART_POLYGONS := {
	"head": [Vector2(-19, 0), Vector2(19, 0), Vector2(25, 14), Vector2(19, 39), Vector2(10, 48), Vector2(-10, 48), Vector2(-19, 39), Vector2(-25, 14)],
	"thorax": [Vector2(-11, 49), Vector2(11, 49), Vector2(17, 58), Vector2(43, 64), Vector2(35, 113), Vector2(-35, 113), Vector2(-43, 64), Vector2(-17, 58)],
	"stomach": [Vector2(-35, 116), Vector2(35, 116), Vector2(31, 143), Vector2(35, 163), Vector2(14, 175), Vector2(-14, 175), Vector2(-35, 163), Vector2(-31, 143)],
	"left_arm": [Vector2(-46, 66), Vector2(-61, 74), Vector2(-71, 119), Vector2(-85, 165), Vector2(-86, 187), Vector2(-77, 195), Vector2(-66, 188), Vector2(-65, 168), Vector2(-47, 128), Vector2(-36, 92)],
	"right_arm": [Vector2(46, 66), Vector2(61, 74), Vector2(71, 119), Vector2(85, 165), Vector2(86, 187), Vector2(77, 195), Vector2(66, 188), Vector2(65, 168), Vector2(47, 128), Vector2(36, 92)],
	"left_leg": [Vector2(-34, 169), Vector2(-3, 178), Vector2(-8, 229), Vector2(-14, 275), Vector2(-12, 285), Vector2(-40, 285), Vector2(-41, 279), Vector2(-33, 268), Vector2(-33, 226)],
	"right_leg": [Vector2(34, 169), Vector2(3, 178), Vector2(8, 229), Vector2(14, 275), Vector2(12, 285), Vector2(40, 285), Vector2(41, 279), Vector2(33, 268), Vector2(33, 226)]
}
const PART_CENTERS := {"head": Vector2(0, 23), "thorax": Vector2(0, 86), "stomach": Vector2(0, 142), "left_arm": Vector2(-61, 126), "right_arm": Vector2(61, 126), "left_leg": Vector2(-21, 227), "right_leg": Vector2(21, 227)}

var part_buttons: Dictionary = {}
var part_value_labels: Dictionary = {}
var part_condition_labels: Dictionary = {}
var part_bars: Dictionary = {}
var treatment_buttons: Dictionary = {}
var automatic_button: Button
var total_label: Label
var conditions_label: Label
var selected_label: Label
var guidance_label: Label
var treatment_scroll: ScrollContainer
var treatment_grid: GridContainer
var snapshot: Dictionary = {}
var _built := false
var _treatment_signature := ""


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
		conditions_label.text = "상태이상 없음" if available else "플레이어의 건강 상태를 확인할 수 없습니다."
	for part_id in PART_ORDER:
		var data: Dictionary = parts.get(part_id, {})
		var button: Button = part_buttons[part_id]
		button.disabled = data.is_empty()
		var current := float(data.get("health", 0.0))
		var maximum := maxf(1.0, float(data.get("max_health", 1.0)))
		var blacked := bool(data.get("blacked", current <= 0.0)) and not data.is_empty()
		var accent := _part_color(data)
		button.add_theme_stylebox_override("normal", _style(Color(0.003, 0.004, 0.004) if blacked else Color(0.05, 0.06, 0.049), COLOR_GOLD if selected == part_id else Color(0.22, 0.27, 0.21), 2 if selected == part_id else 1))
		var value_label: Label = part_value_labels[part_id]
		value_label.text = "%s    %d / %d" % [str(data.get("name", part_id)), ceili(current), roundi(maximum)] if not data.is_empty() else "—"
		value_label.add_theme_color_override("font_color", COLOR_TEXT if not blacked else Color(0.68, 0.66, 0.61))
		var bar: ProgressBar = part_bars[part_id]
		bar.max_value = maximum
		bar.value = current
		bar.add_theme_stylebox_override("fill", _style(accent, accent, 0))
		var note: Label = part_condition_labels[part_id]
		note.text = _condition_text(data.get("conditions", {}))
		if blacked:
			note.text = "손상 · 일반 치료 불가" + ("  /  " + note.text if not note.text.is_empty() else "")
		elif note.text.is_empty():
			note.text = "치료 부위 선택됨" if selected == part_id else ""
		note.add_theme_color_override("font_color", Color(0.88, 0.56, 0.38) if blacked or not _condition_text(data.get("conditions", {})).is_empty() else COLOR_MUTED)
		button.set_meta("blacked", blacked)
		button.set_meta("selected", selected == part_id)
	automatic_button.disabled = not available
	automatic_button.add_theme_stylebox_override("normal", _style(Color(0.13, 0.15, 0.10) if selected.is_empty() else Color(0.05, 0.06, 0.05), COLOR_GOLD if selected.is_empty() else Color(0.25, 0.29, 0.23), 1))
	var selected_data: Dictionary = parts.get(selected, {})
	selected_label.text = "치료 대상  ·  자동 선택" if selected.is_empty() else "치료 대상  ·  %s" % str(selected_data.get("name", selected))
	if bool(selected_data.get("blacked", false)):
		guidance_label.text = "체력 0인 부위입니다. 수술 도구나 고위 치료 마법으로 1까지 복구한 뒤 치료하세요."
	else:
		guidance_label.text = "부위를 고른 뒤 아래 치료품을 사용하세요. 치료 마법도 선택한 부위를 대상으로 합니다."
	_update_treatments(inventory, available)
	queue_redraw()


func _build() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(784, 610)
	size = Vector2(784, 610)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = FONT
	_label(self, "HealthHeading", "건강 상태", Vector2(20, 12), Vector2(260, 30), 21, COLOR_TEXT)
	_label(self, "HealthCaption", "부위를 선택하여 치료", Vector2(20, 44), Vector2(370, 22), 13, COLOR_MUTED)
	total_label = _label(self, "TotalHealth", "— / 440", Vector2(538, 11), Vector2(225, 36), 28, COLOR_GREEN)
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	conditions_label = _label(self, "ActiveConditions", "", Vector2(298, 51), Vector2(465, 23), 13, Color(0.86, 0.64, 0.44))
	conditions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	conditions_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for part_id in PART_ORDER:
		var button := _button(self, part_id + "Part", "", CARD_POSITIONS[part_id], Vector2(216, 62))
		button.pressed.connect(_select_part.bind(part_id))
		button.tooltip_text = "이 부위를 치료 대상으로 선택"
		part_buttons[part_id] = button
		part_value_labels[part_id] = _label(button, "HealthValue", "", Vector2(10, 5), Vector2(198, 21), 14, COLOR_TEXT)
		var bar := ProgressBar.new()
		bar.name = "PartHealthBar"
		bar.position = Vector2(10, 29)
		bar.size = Vector2(196, 5)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", _style(Color(0.005, 0.009, 0.006), Color.TRANSPARENT, 0))
		button.add_child(bar)
		part_bars[part_id] = bar
		part_condition_labels[part_id] = _label(button, "PartConditions", "", Vector2(10, 38), Vector2(198, 18), 11, COLOR_MUTED)
		(part_condition_labels[part_id] as Label).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_label = _label(self, "TreatmentTarget", "", Vector2(20, 390), Vector2(558, 25), 17, COLOR_GOLD)
	automatic_button = _button(self, "AutomaticTarget", "자동 선택", Vector2(642, 386), Vector2(122, 32))
	automatic_button.pressed.connect(_select_part.bind(""))
	guidance_label = _label(self, "TreatmentGuidance", "", Vector2(20, 421), Vector2(744, 40), 13, COLOR_MUTED)
	guidance_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(self, "TreatmentHeading", "보유 치료품", Vector2(20, 463), Vector2(290, 20), 13, COLOR_TEXT)
	treatment_scroll = ScrollContainer.new()
	treatment_scroll.position = Vector2(20, 490)
	treatment_scroll.size = Vector2(744, 102)
	treatment_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(treatment_scroll)
	treatment_grid = GridContainer.new()
	treatment_grid.columns = 3
	treatment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	treatment_grid.add_theme_constant_override("h_separation", 7)
	treatment_grid.add_theme_constant_override("v_separation", 6)
	treatment_scroll.add_child(treatment_grid)


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
		var button := _button(treatment_grid, "Treatment_" + item_id, "%s  ×%d" % [str(definition.get("name", item_id)), int(stacks[item_id])], Vector2.ZERO, Vector2(239, 30))
		button.custom_minimum_size = Vector2(237, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 12)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(definition.get("summary", "")) + "\n" + str(definition.get("description", ""))
		button.disabled = not available
		button.pressed.connect(func() -> void: consumable_requested.emit(item_id))
		treatment_buttons[item_id] = button
	if stacks.is_empty():
		_label(treatment_grid, "NoTreatments", "가방에 치료품이 없습니다.", Vector2.ZERO, Vector2(600, 28), 14, COLOR_MUTED)


func _select_part(part_id: String) -> void:
	if part_id.is_empty() or snapshot.get("parts", {}).has(part_id):
		treatment_part_selected.emit(part_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		for part_id in PART_ORDER:
			if Geometry2D.is_point_in_polygon(event.position - FIGURE_ORIGIN, PackedVector2Array(PART_POLYGONS[part_id])):
				_select_part(part_id)
				accept_event()
				return


func _draw() -> void:
	if not _built:
		return
	draw_style_box(_style(Color(0.015, 0.020, 0.016, 0.98), Color(0.28, 0.31, 0.25), 1), Rect2(Vector2.ZERO, size))
	var parts: Dictionary = snapshot.get("parts", {})
	var selected := str(snapshot.get("selected_part", ""))
	for part_id in PART_ORDER:
		var data: Dictionary = parts.get(part_id, {})
		var polygon := PackedVector2Array()
		for point in PART_POLYGONS[part_id]:
			polygon.append(FIGURE_ORIGIN + point)
		var accent := _part_color(data)
		draw_colored_polygon(polygon, accent.darkened(0.40))
		polygon.append(polygon[0])
		draw_polyline(polygon, COLOR_GOLD if selected == part_id else accent.lightened(0.15), 2.0 if selected == part_id else 1.0, true)
		var card: Vector2 = CARD_POSITIONS[part_id]
		var from := card + Vector2(216 if card.x < FIGURE_ORIGIN.x else 0, 28)
		var to: Vector2 = FIGURE_ORIGIN + PART_CENTERS[part_id]
		var bend := Vector2(from.x + (27 if from.x < to.x else -27), from.y)
		draw_polyline(PackedVector2Array([from, bend, to]), COLOR_GOLD.darkened(0.25) if selected == part_id else Color(0.29, 0.35, 0.27, 0.65), 1.0, true)
		draw_circle(to, 2.3, COLOR_GOLD if selected == part_id else COLOR_MUTED)


func _part_color(data: Dictionary) -> Color:
	if data.is_empty():
		return Color(0.23, 0.26, 0.23)
	var hp := float(data.get("health", 0.0))
	if hp <= 0.0:
		return Color(0.06, 0.065, 0.059)
	var ratio := hp / maxf(1.0, float(data.get("max_health", 1.0)))
	if ratio <= 0.30:
		return Color(0.80, 0.27, 0.16)
	if ratio <= 0.65:
		return Color(0.82, 0.62, 0.25)
	return COLOR_GREEN


func _condition_text(conditions: Variant) -> String:
	var labels: Array[String] = []
	if conditions is Dictionary:
		for condition_id in conditions:
			if float(conditions[condition_id]) > 0.0:
				labels.append(str(CONDITION_NAMES.get(str(condition_id), condition_id)))
	return "  ·  ".join(labels)


func _label(parent: Node, node_name: String, text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text_value
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, node_name: String, text_value: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = at
	button.size = extent
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style(Color(0.05, 0.06, 0.049), Color(0.23, 0.28, 0.21), 1))
	button.add_theme_stylebox_override("hover", _style(Color(0.11, 0.14, 0.09), COLOR_GOLD, 1))
	button.add_theme_stylebox_override("pressed", _style(Color(0.16, 0.18, 0.10), COLOR_GOLD, 2))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, COLOR_GOLD, 1))
	parent.add_child(button)
	return button


func _style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	return style
