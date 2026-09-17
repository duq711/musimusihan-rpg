extends VBoxContainer
class_name TestRoomStatusControls

signal stat_changed(id: String, value: float)

const STAT_ORDER: Array[String] = ["health", "stamina", "hunger", "thirst", "stress"]
const STAT_LABELS := {
	"health": "체력",
	"stamina": "기력",
	"hunger": "포만감 · 낮을수록 허기",
	"thirst": "수분 · 낮을수록 갈증",
	"stress": "스트레스 · 높을수록 불안정",
}
const TEXT_COLOR := Color(0.87, 0.91, 0.85)
const MUTED_COLOR := Color(0.65, 0.74, 0.68)

var sliders: Dictionary = {}
var spin_boxes: Dictionary = {}
var hint_label: Label
# Confirmed simulation values retain fractions; only the controls round them.
var _values: Dictionary = {}
var _pending_text: Dictionary = {}
var _syncing := false
var _built := false


func _ready() -> void:
	_ensure_built()


func set_snapshot(snapshot: Dictionary) -> void:
	_ensure_built()
	_syncing = true
	for id in STAT_ORDER:
		var maximum := 100.0
		if id == "health" or id == "stamina":
			maximum = float(snapshot.get("max_" + id, 100.0))
		if not is_finite(maximum) or maximum < 1.0:
			maximum = 100.0
		var slider := sliders[id] as HSlider
		var number := spin_boxes[id] as SpinBox
		var value := float(snapshot.get(id, _values.get(id, 0.0 if id == "stress" else maximum)))
		if not is_finite(value):
			value = float(_values.get(id, slider.min_value))
		# Preserve the real fractional value separately from the integer form.
		# For example, an explicit 80 must still apply when 79.6 displays as 80.
		value = clampf(value, slider.min_value, maximum)
		_values[id] = value
		# A controller may refresh the whole snapshot after another row changes.
		# Do not replace unfinished text while the user is entering a number.
		if _pending_text.has(id):
			continue
		slider.max_value = maximum
		number.max_value = maximum
		_set_pair_value(id, value)
	_syncing = false


func focus_stat(id: String = "stress") -> void:
	_ensure_built()
	if not sliders.has(id):
		return
	(sliders[id] as HSlider).grab_focus()


func commit_pending_edits() -> void:
	_ensure_built()
	for id in STAT_ORDER:
		var edit := (spin_boxes[id] as SpinBox).get_line_edit()
		if _pending_text.has(id) or edit.text.strip_edges() != str(roundi(float(_values[id]))):
			_commit_edit(id)


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var card := PanelContainer.new()
	card.name = "StatusAdjustmentCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.045, 0.075, 0.065)
	background.border_color = Color(0.33, 0.47, 0.35)
	background.set_border_width_all(1)
	background.set_corner_radius_all(5)
	card.add_theme_stylebox_override("panel", background)
	add_child(card)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	card.add_child(margin)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)
	content.add_child(_make_label("현재 상태 직접 조절", 19, Color(0.86, 0.81, 0.61)))
	content.add_child(_make_label("슬라이더 또는 숫자 입력 · 변경 즉시 시험 캐릭터에 적용", 14, MUTED_COLOR))
	for id in STAT_ORDER:
		_build_row(content, id)
	hint_label = _make_label("스트레스 40 불안 · 60 환청 · 80 환영\n포만감·수분 0 = 고갈 · 체력 0은 사망 시험으로 확인", 14, MUTED_COLOR)
	hint_label.name = "StatusAdjustmentHint"
	content.add_child(hint_label)


func _build_row(parent: VBoxContainer, id: String) -> void:
	var row := HBoxContainer.new()
	row.name = "StatusRow_" + id
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var label := _make_label(str(STAT_LABELS[id]), 14, TEXT_COLOR)
	label.custom_minimum_size.x = 200
	label.size_flags_horizontal = Control.SIZE_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "StatusSlider_" + id
	slider.min_value = 1.0 if id == "health" else 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = 0.0 if id == "stress" else 100.0
	slider.custom_minimum_size = Vector2(80, 38)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_ALL
	slider.tick_count = 11
	slider.ticks_on_borders = true
	slider.tooltip_text = str(STAT_LABELS[id]) + " · 좌우 방향키로 1씩 조절"
	row.add_child(slider)
	sliders[id] = slider
	var number := SpinBox.new()
	number.name = "StatusNumber_" + id
	number.min_value = slider.min_value
	number.max_value = slider.max_value
	number.step = 1.0
	number.value = slider.value
	number.custom_minimum_size = Vector2(86, 38)
	number.size_flags_horizontal = Control.SIZE_FILL
	number.add_theme_font_size_override("font_size", 16)
	number.tooltip_text = str(STAT_LABELS[id]) + " · 숫자 입력 후 Enter 또는 F2로 적용"
	row.add_child(number)
	spin_boxes[id] = number
	var edit := number.get_line_edit()
	# SpinBox normally parses submitted text on a deferred callback. This form
	# commits synchronously before F2 can resume gameplay, so leaving that
	# callback connected would replay an old value after the latest snapshot.
	# Keep SpinBox's arrow/drag behavior but own strict numeric text commits.
	for connection: Dictionary in edit.get_signal_connection_list("text_submitted"):
		var callback: Callable = connection.callable
		if callback.get_object() == number:
			edit.disconnect("text_submitted", callback)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.select_all_on_focus = true
	edit.add_theme_font_size_override("font_size", 16)
	_values[id] = slider.value
	slider.value_changed.connect(_on_control_changed.bind(id))
	# Clicking the current rounded position is still an explicit selection.
	# A changed drag already applied its value, so comparison prevents repeats.
	slider.drag_ended.connect(func(_changed: bool) -> void: _on_control_changed(slider.value, id))
	number.value_changed.connect(_on_control_changed.bind(id))
	edit.text_changed.connect(_on_text_changed.bind(id))
	edit.text_submitted.connect(func(_text: String) -> void: _commit_edit(id, true))
	edit.focus_exited.connect(_commit_edit.bind(id))


func _make_label(caption: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _on_control_changed(value: float, id: String) -> void:
	if _syncing:
		return
	_pending_text.erase(id)
	var previous := float(_values.get(id, value))
	_values[id] = value
	_syncing = true
	_set_pair_value(id, value)
	_syncing = false
	# Thresholds use exact comparisons in gameplay: even 79.9999 -> 80 is
	# meaningful and must not be swallowed by approximate float equality.
	if previous != value:
		stat_changed.emit(id, value)


func _on_text_changed(text_value: String, id: String) -> void:
	if not _syncing:
		_pending_text[id] = text_value


func _commit_edit(id: String, explicit_submit: bool = false) -> void:
	if _syncing or not spin_boxes.has(id):
		return
	var number := spin_boxes[id] as SpinBox
	# Merely focusing the rounded display or closing the menu is not an edit.
	# Enter is explicit even if the submitted integer matches that display.
	if not explicit_submit and not _pending_text.has(id) and number.get_line_edit().text.strip_edges() == str(roundi(float(_values[id]))):
		return
	var text_value := str(_pending_text.get(id, number.get_line_edit().text)).strip_edges()
	var value := float(_values[id])
	if text_value.is_valid_float():
		var parsed := text_value.to_float()
		if is_finite(parsed):
			value = clampf(roundf(parsed), number.min_value, number.max_value)
	_on_control_changed(value, id)


func _set_pair_value(id: String, value: float) -> void:
	(sliders[id] as HSlider).set_value_no_signal(value)
	var number := spin_boxes[id] as SpinBox
	number.set_value_no_signal(value)
	# Restore a valid display even when an invalid edit resolves to the same
	# value; Range otherwise has no value change to refresh its text from.
	number.get_line_edit().text = str(roundi(value))
