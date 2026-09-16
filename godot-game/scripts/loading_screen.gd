extends Control
class_name SanctuaryLoadingScreen

signal load_failed(error_code: int)

@export_file("*.tscn") var target_scene_path := ""
@export var loading_title := "성소를 밝히는 중"
@export_multiline var loading_detail := "기억과 길을 불러오고 있습니다"
@export var status_message := "첫 화면을 준비하는 중"
@export_range(0.0, 5.0, 0.05) var minimum_visible_time := 0.9
@export var auto_start := true

const COLOR_BACKGROUND := Color(0.004, 0.007, 0.009, 1.0)
const COLOR_PANEL := Color(0.008, 0.016, 0.018, 0.97)
const COLOR_IVORY := Color(0.92, 0.91, 0.87)
const COLOR_TEXT := Color(0.68, 0.72, 0.69)
const COLOR_MUTED := Color(0.42, 0.48, 0.46)
const COLOR_TEAL := Color(0.47, 0.66, 0.61)
const COLOR_TEAL_BRIGHT := Color(0.68, 0.84, 0.77)
const COLOR_DANGER := Color(0.72, 0.36, 0.32)
const OVERLAY_LAYER := 1000
const OVERLAY_HOST_META := &"sanctuary_loading_host"

var loading_spinner: Control
var title_label: Label
var detail_label: Label
var activity_label: Label
var elapsed_label: Label
var progress_label: Label
var progress_bar: ProgressBar
var progress_glint: ColorRect

var _loading_font: SystemFont
var _elapsed := 0.0
var _displayed_progress := 0.0
var _request_started := false
var _request_failed := false
var _transition_committed := false
var _waiting_for_scene := false
var _scene_ready_elapsed := 0.0
var _interface_ready := false
var _loaded_scene: PackedScene
var _progress_values: Array = []


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	_build_interface()
	_interface_ready = true
	_apply_loading_copy()
	if auto_start and not _request_started:
		_begin_loading()


func configure(scene_path: String, title_text: String, detail_text: String, status_text := "계속 준비하는 중", minimum_time := 0.7) -> void:
	target_scene_path = scene_path
	loading_title = title_text
	loading_detail = detail_text
	status_message = status_text
	minimum_visible_time = minimum_time
	if _interface_ready:
		_apply_loading_copy()


func start_loading(scene_path: String, title_text: String, detail_text: String, status_text := "계속 준비하는 중", minimum_time := 0.7) -> void:
	configure(scene_path, title_text, detail_text, status_text, minimum_time)
	_reset_loading_state()
	_begin_loading()


func attach_as_overlay(scene_tree: SceneTree) -> void:
	var host := CanvasLayer.new()
	host.name = "LoadingScreenLayer"
	host.layer = OVERLAY_LAYER
	host.process_mode = Node.PROCESS_MODE_ALWAYS
	host.set_meta(OVERLAY_HOST_META, true)
	scene_tree.root.add_child(host)
	host.add_child(self)


func dismiss() -> void:
	var host := get_parent()
	if host is CanvasLayer and bool(host.get_meta(OVERLAY_HOST_META, false)):
		host.queue_free()
	else:
		queue_free()


func _process(delta: float) -> void:
	_elapsed += delta
	_animate_activity()
	if _waiting_for_scene:
		var current_scene := get_tree().current_scene
		if current_scene != null and current_scene.scene_file_path == target_scene_path:
			_scene_ready_elapsed += delta
			if _scene_ready_elapsed >= 0.18:
				dismiss()
		return
	if not _request_started or _request_failed or _transition_committed:
		return
	if _loaded_scene != null:
		_complete_loaded_request()
		return

	_progress_values.clear()
	var load_status := _threaded_status(_progress_values)
	var reported_progress := 0.0
	if not _progress_values.is_empty():
		reported_progress = clampf(float(_progress_values[0]), 0.0, 1.0)

	match load_status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_set_progress(maxf(_displayed_progress, reported_progress * 0.94))
		ResourceLoader.THREAD_LOAD_LOADED:
			if _loaded_scene == null:
				_loaded_scene = _threaded_get() as PackedScene
			if _loaded_scene == null:
				_report_failure(ERR_PARSE_ERROR)
				return
			_complete_loaded_request()
		ResourceLoader.THREAD_LOAD_FAILED:
			_report_failure(ERR_CANT_OPEN)
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_report_failure(ERR_FILE_NOT_FOUND)


func _complete_loaded_request() -> void:
	_set_progress(1.0)
	status_message = "준비를 마무리하는 중"
	if _elapsed >= _effective_minimum_time():
		_transition_committed = true
		activity_label.text = "준비 완료 · 문을 여는 중"
		call_deferred("_finish_transition")


func _begin_loading() -> void:
	if _request_started:
		return
	if target_scene_path.is_empty():
		_report_failure(ERR_INVALID_PARAMETER)
		return
	_request_started = true
	_request_failed = false
	_transition_committed = false
	var error := _threaded_request()
	if error != OK:
		_report_failure(error)


func _threaded_request() -> Error:
	return ResourceLoader.load_threaded_request(target_scene_path, "PackedScene")


func _threaded_status(progress: Array) -> ResourceLoader.ThreadLoadStatus:
	return ResourceLoader.load_threaded_get_status(target_scene_path, progress)


func _threaded_get() -> Resource:
	return ResourceLoader.load_threaded_get(target_scene_path)


func _finish_transition() -> void:
	if _loaded_scene == null or not is_inside_tree():
		_transition_committed = false
		return
	var should_persist := get_tree().current_scene != self
	get_tree().paused = false
	var error := get_tree().change_scene_to_packed(_loaded_scene)
	if error != OK:
		_transition_committed = false
		_report_failure(error)
	elif should_persist:
		_waiting_for_scene = true
		_scene_ready_elapsed = 0.0


func _report_failure(error_code: int) -> void:
	_request_started = false
	_request_failed = true
	_transition_committed = false
	_waiting_for_scene = false
	_scene_ready_elapsed = 0.0
	_set_progress(0.0)
	if is_instance_valid(title_label):
		title_label.text = "불러오지 못했습니다"
	if is_instance_valid(detail_label):
		detail_label.text = "게임 파일을 확인한 뒤 다시 시도해 주세요"
	if is_instance_valid(activity_label):
		activity_label.text = "준비가 중단되었습니다"
	if is_instance_valid(elapsed_label):
		elapsed_label.text = "오류 코드 · %d" % error_code
	load_failed.emit(error_code)


func _reset_loading_state() -> void:
	_elapsed = 0.0
	_displayed_progress = 0.0
	_request_started = false
	_request_failed = false
	_transition_committed = false
	_waiting_for_scene = false
	_scene_ready_elapsed = 0.0
	_loaded_scene = null
	_progress_values.clear()
	_set_progress(0.0)
	_apply_loading_copy()


func _effective_minimum_time() -> float:
	if DisplayServer.get_name() == "headless":
		return minf(minimum_visible_time, 0.05)
	return minimum_visible_time


func _set_progress(progress_value: float) -> void:
	_displayed_progress = clampf(progress_value, 0.0, 1.0)
	if is_instance_valid(progress_bar):
		progress_bar.value = _displayed_progress * 100.0
	if is_instance_valid(progress_label):
		progress_label.text = "%d%%" % roundi(_displayed_progress * 100.0)


func _animate_activity() -> void:
	if is_instance_valid(loading_spinner):
		loading_spinner.rotation = _elapsed * 2.35
		var pulse := 1.0 + sin(_elapsed * 3.4) * 0.035
		loading_spinner.scale = Vector2.ONE * pulse
		loading_spinner.modulate.a = 0.88 + sin(_elapsed * 4.1) * 0.12
	if is_instance_valid(progress_glint) and is_instance_valid(progress_bar):
		progress_glint.position.x = fmod(_elapsed * 105.0, progress_bar.size.x + progress_glint.size.x) - progress_glint.size.x
	if _request_failed:
		return
	if is_instance_valid(activity_label):
		var dots := ""
		var dot_count := 1 + (floori(_elapsed * 2.4) % 3)
		for index in range(dot_count):
			dots += "·"
		activity_label.text = "%s %s" % [status_message, dots]
	if is_instance_valid(elapsed_label):
		elapsed_label.text = "계속 준비 중 · %02d초" % maxi(0, floori(_elapsed))


func _apply_loading_copy() -> void:
	if is_instance_valid(title_label):
		title_label.text = loading_title
	if is_instance_valid(detail_label):
		detail_label.text = loading_detail
	if is_instance_valid(activity_label):
		activity_label.text = status_message
	if is_instance_valid(elapsed_label):
		elapsed_label.text = "계속 준비 중 · 00초"


func _build_interface() -> void:
	_loading_font = SystemFont.new()
	_loading_font.font_names = PackedStringArray([
		"Apple SD Gothic Neo",
		"Noto Sans CJK KR",
		"Malgun Gothic",
		"Arial Unicode MS",
		"sans-serif",
	])
	var loading_theme := Theme.new()
	loading_theme.default_font = _loading_font
	loading_theme.default_font_size = 14
	theme = loading_theme

	var background := ColorRect.new()
	background.name = "LoadingBackground"
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var ambient_left := ColorRect.new()
	ambient_left.color = Color(0.08, 0.21, 0.18, 0.16)
	ambient_left.anchor_top = 0.5
	ambient_left.anchor_bottom = 0.5
	ambient_left.offset_left = 0.0
	ambient_left.offset_top = -1.0
	ambient_left.offset_right = 420.0
	ambient_left.offset_bottom = 1.0
	ambient_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ambient_left)

	var ambient_right := ColorRect.new()
	ambient_right.color = Color(0.08, 0.21, 0.18, 0.16)
	ambient_right.anchor_left = 1.0
	ambient_right.anchor_top = 0.5
	ambient_right.anchor_right = 1.0
	ambient_right.anchor_bottom = 0.5
	ambient_right.offset_left = -420.0
	ambient_right.offset_top = -1.0
	ambient_right.offset_right = 0.0
	ambient_right.offset_bottom = 1.0
	ambient_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ambient_right)

	var card := Panel.new()
	card.name = "LoadingCard"
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -320.0
	card.offset_top = -190.0
	card.offset_right = 320.0
	card.offset_bottom = 190.0
	card.add_theme_stylebox_override("panel", _panel_style(COLOR_PANEL, Color(0.3, 0.43, 0.39, 0.82), 1, 3))
	add_child(card)

	var kicker := _label("잔향의 성소 · 원정 준비", 11, COLOR_TEAL)
	kicker.name = "LoadingKicker"
	kicker.position = Vector2(38, 30)
	kicker.size = Vector2(564, 22)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(kicker)

	title_label = _label(loading_title, 27, COLOR_IVORY)
	title_label.name = "LoadingTitle"
	title_label.position = Vector2(38, 58)
	title_label.size = Vector2(564, 42)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(title_label)

	detail_label = _label(loading_detail, 13, COLOR_TEXT)
	detail_label.name = "LoadingDetail"
	detail_label.position = Vector2(38, 102)
	detail_label.size = Vector2(564, 28)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(detail_label)

	loading_spinner = Control.new()
	loading_spinner.name = "MovingLoadingSigil"
	loading_spinner.position = Vector2(278, 138)
	loading_spinner.size = Vector2(84, 84)
	loading_spinner.pivot_offset = loading_spinner.size * 0.5
	loading_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(loading_spinner)
	_build_spinner_marks()

	progress_bar = ProgressBar.new()
	progress_bar.name = "LoadingProgress"
	progress_bar.position = Vector2(82, 242)
	progress_bar.size = Vector2(476, 8)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_bar.clip_contents = true
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", _panel_style(Color(0.035, 0.055, 0.052, 1), Color(0.19, 0.27, 0.25, 0.9), 1, 4))
	progress_bar.add_theme_stylebox_override("fill", _panel_style(Color(0.42, 0.66, 0.59, 1), COLOR_TEAL_BRIGHT, 1, 4))
	card.add_child(progress_bar)

	progress_glint = ColorRect.new()
	progress_glint.name = "LoadingProgressGlint"
	progress_glint.position = Vector2(-40, 2)
	progress_glint.size = Vector2(40, 4)
	progress_glint.color = Color(0.83, 0.95, 0.89, 0.72)
	progress_glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_child(progress_glint)

	activity_label = _label(status_message, 12, COLOR_TEAL_BRIGHT)
	activity_label.name = "LoadingActivity"
	activity_label.position = Vector2(82, 270)
	activity_label.size = Vector2(390, 24)
	card.add_child(activity_label)

	progress_label = _label("0%", 12, COLOR_TEAL_BRIGHT)
	progress_label.name = "LoadingPercent"
	progress_label.position = Vector2(478, 270)
	progress_label.size = Vector2(80, 24)
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	card.add_child(progress_label)

	elapsed_label = _label("계속 준비 중 · 00초", 11, COLOR_MUTED)
	elapsed_label.name = "LoadingElapsed"
	elapsed_label.position = Vector2(82, 305)
	elapsed_label.size = Vector2(476, 22)
	elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(elapsed_label)

	var footer := _label("표식과 시간이 움직이는 동안 게임은 정상적으로 준비되고 있습니다", 11, Color(0.46, 0.54, 0.51))
	footer.name = "LoadingFooterHint"
	footer.anchor_top = 1.0
	footer.anchor_right = 1.0
	footer.anchor_bottom = 1.0
	footer.offset_top = -54.0
	footer.offset_bottom = -24.0
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)


func _build_spinner_marks() -> void:
	for index in range(10):
		var angle := TAU * float(index) / 10.0
		var mark := ColorRect.new()
		mark.name = "SpinnerMark%02d" % index
		mark.size = Vector2(4, 13)
		mark.position = Vector2(42, 42) + Vector2(cos(angle), sin(angle)) * 31.0 - mark.size * 0.5
		mark.pivot_offset = mark.size * 0.5
		mark.rotation = angle + PI * 0.5
		mark.color = Color(COLOR_TEAL_BRIGHT, 0.18 + float(index + 1) * 0.075)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		loading_spinner.add_child(mark)

	var diamond := Polygon2D.new()
	diamond.name = "LoadingCoreDiamond"
	diamond.polygon = PackedVector2Array([
		Vector2(42, 29),
		Vector2(55, 42),
		Vector2(42, 55),
		Vector2(29, 42),
	])
	diamond.color = Color(0.43, 0.68, 0.61, 0.72)
	loading_spinner.add_child(diamond)

	var inner := Polygon2D.new()
	inner.name = "LoadingCore"
	inner.polygon = PackedVector2Array([
		Vector2(42, 35),
		Vector2(49, 42),
		Vector2(42, 49),
		Vector2(35, 42),
	])
	inner.color = Color(0.75, 0.9, 0.83, 0.92)
	loading_spinner.add_child(inner)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", _loading_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
