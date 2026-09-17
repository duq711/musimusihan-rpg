extends Control
## Controls the real player's temporary hand pose. No duplicate rig, camera,
## inventory, simulation clock or mouse capture belongs to this panel.

signal closed

const DIGITS := ["thumb", "index", "middle", "ring", "little"]
const LABELS := ["엄지", "검지", "중지", "약지", "소지"]
const SEQUENCE_STEP := 1.0

var sliders: Dictionary = {}
var side_selector: OptionButton
var view_selector: OptionButton
var preset_open_button: Button
var preset_fist_button: Button
var sequence_button: Button
var close_button: Button
var sequence_active := false
var selected_side := 0
var _player: Node3D
var _panel: PanelContainer
var _status: Label
var _numbers: Dictionary = {}
var _sequence_time := 0.0


func setup(player_ref: Node3D) -> void:
	_player = player_ref
	if is_inside_tree():
		_build()
		_refresh_sliders()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	get_viewport().size_changed.connect(_resize)
	_resize()
	_refresh_sliders()


func _build() -> void:
	if is_instance_valid(_panel):
		return
	_panel = PanelContainer.new()
	_panel.name = "FingerJointPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.037, 0.96)
	style.border_color = Color(0.35, 0.43, 0.36)
	style.set_border_width_all(1)
	style.set_content_margin_all(16)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	_panel.add_child(content)
	var title := Label.new()
	title.text = "손가락 마디 시험"
	title.add_theme_font_size_override("font_size", 23)
	content.add_child(title)
	var description := Label.new()
	description.text = "마디를 따로 굽혀 관절과 피부 변형을 확인합니다.\n적과 생존 시간은 멈춰 있습니다."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	var selectors := HBoxContainer.new()
	content.add_child(selectors)
	side_selector = OptionButton.new()
	side_selector.name = "HandSideSelector"
	side_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_selector.add_item("양손 함께", 0)
	side_selector.add_item("왼손", -1)
	side_selector.add_item("오른손", 1)
	side_selector.item_selected.connect(func(index: int) -> void: select_side([0, -1, 1][index]))
	selectors.add_child(side_selector)
	view_selector = OptionButton.new()
	view_selector.name = "HandViewSelector"
	view_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_selector.add_item("손등 보기")
	view_selector.add_item("손바닥 보기")
	view_selector.add_item("손목 옆면")
	view_selector.item_selected.connect(func(index: int) -> void: select_view(["dorsal", "palm", "wrist_side"][index]))
	selectors.add_child(view_selector)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 9)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for text_value: String in ["손가락", "뿌리", "가운데", "끝"]:
		var heading := Label.new()
		heading.text = text_value
		grid.add_child(heading)
	for digit_index in DIGITS.size():
		var digit := str(DIGITS[digit_index])
		var name_label := Label.new()
		name_label.text = LABELS[digit_index]
		grid.add_child(name_label)
		for joint in 3:
			var key := "%s:%d" % [digit, joint]
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(column)
			var slider := HSlider.new()
			slider.name = "Joint_" + digit + "_" + str(joint)
			slider.min_value = 0.0
			slider.max_value = 1.0
			slider.step = 0.01
			slider.custom_minimum_size = Vector2(65, 26)
			slider.tooltip_text = "%s · %s 마디" % [LABELS[digit_index], ["뿌리", "가운데", "끝"][joint]]
			slider.value_changed.connect(_on_joint_changed.bind(digit, joint))
			column.add_child(slider)
			sliders[key] = slider
			var number := Label.new()
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			number.add_theme_font_size_override("font_size", 12)
			column.add_child(number)
			_numbers[key] = number
	var presets := HBoxContainer.new()
	content.add_child(presets)
	preset_open_button = _button("펴기", func() -> void: apply_preset("open"))
	preset_fist_button = _button("주먹", func() -> void: apply_preset("fist"))
	sequence_button = _button("마디 순차", _toggle_sequence)
	presets.add_child(preset_open_button)
	presets.add_child(preset_fist_button)
	presets.add_child(sequence_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 48
	content.add_child(_status)
	close_button = _button("시험 메뉴 · F2", request_close)
	close_button.name = "CloseFingerJointReview"
	content.add_child(close_button)
	_resize()


func _button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 38
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(action)
	return button


func _resize() -> void:
	if not is_instance_valid(_panel):
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_panel.offset_left = -clampf(viewport_size.x * 0.34, 340.0, 420.0)
	_panel.offset_right = -12.0
	_panel.offset_top = 16.0
	_panel.offset_bottom = -16.0


func select_side(side: int) -> bool:
	if side not in [-1, 0, 1]:
		return false
	_stop_sequence()
	selected_side = side
	if is_instance_valid(side_selector):
		side_selector.select([0, -1, 1].find(side))
	_refresh_sliders()
	return true


func _on_joint_changed(value: float, digit: String, joint: int) -> void:
	set_joint_value(digit, joint, value)


func select_view(view: String) -> bool:
	if not is_instance_valid(_player) or not bool(_player.call("set_review_hand_view", view)):
		return false
	if is_instance_valid(view_selector):
		view_selector.select(["dorsal", "palm", "wrist_side"].find(view))
	return true


func set_joint_value(digit: String, joint: int, value: float) -> bool:
	if not is_instance_valid(_player) or not is_finite(value):
		return false
	var accepted := bool(_player.call("set_review_joint_flexion", digit, joint, value, selected_side))
	if accepted:
		_stop_sequence()
		_refresh_sliders()
	return accepted


func apply_preset(preset: String) -> bool:
	if preset not in ["open", "fist"] or not is_instance_valid(_player):
		return false
	_stop_sequence()
	var accepted := _set_all(0.0 if preset == "open" else 1.0)
	_refresh_sliders()
	return accepted


func _set_all(value: float) -> bool:
	if not is_instance_valid(_player):
		return false
	for digit: String in DIGITS:
		if not bool(_player.call("set_review_digit_flexion", digit, Vector3.ONE * value, selected_side)):
			return false
	return true


func _toggle_sequence() -> void:
	if sequence_active:
		_stop_sequence()
		return
	if not apply_preset("open"):
		return
	_sequence_time = 0.0
	sequence_active = true
	sequence_button.text = "순차 멈춤"


func _stop_sequence() -> void:
	sequence_active = false
	if is_instance_valid(sequence_button):
		sequence_button.text = "마디 순차"


func _process(delta: float) -> void:
	advance_sequence(delta)


func advance_sequence(delta: float) -> void:
	if not sequence_active or not is_finite(delta) or delta <= 0.0:
		return
	_sequence_time += delta
	if not _set_all(0.0):
		_stop_sequence()
		return
	var step := floori(_sequence_time / SEQUENCE_STEP)
	if step >= DIGITS.size() * 3:
		_stop_sequence()
		_refresh_sliders()
		return
	var amount := sin(PI * fmod(_sequence_time, SEQUENCE_STEP) / SEQUENCE_STEP)
	_player.call("set_review_joint_flexion", str(DIGITS[floori(float(step) / 3.0)]), step % 3, amount, selected_side)
	_refresh_sliders()


func _refresh_sliders() -> void:
	if not is_instance_valid(_player) or sliders.is_empty():
		return
	var snapshot: Dictionary = _player.call("get_finger_joint_review_snapshot")
	if not bool(snapshot.get("active", false)):
		_stop_sequence()
		return
	var values: Dictionary = snapshot.get("values", {})
	for digit: String in DIGITS:
		var angles: Vector3 = values[selected_side][digit] if selected_side != 0 else ((values[-1][digit] as Vector3) + (values[1][digit] as Vector3)) * 0.5
		for joint in 3:
			var key := "%s:%d" % [digit, joint]
			(sliders[key] as HSlider).set_value_no_signal(angles[joint])
			(_numbers[key] as Label).text = "%d%%" % roundi(angles[joint] * 100.0)
	_status.text = "양손 값을 함께 바꿉니다. 서로 다른 값은 평균으로 표시합니다." if selected_side == 0 else ("왼손만 조절합니다." if selected_side < 0 else "오른손만 조절합니다.")


func request_close() -> void:
	_stop_sequence()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F2 or event.physical_keycode == KEY_F2)):
		request_close()
		get_viewport().set_input_as_handled()
