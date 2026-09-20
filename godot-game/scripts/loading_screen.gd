extends Control
class_name SanctuaryLoadingScreen

signal load_failed(error_code: int)

@export_file("*.tscn") var target_scene_path := ""
@export var loading_title := "잔향의 성소"
@export_multiline var loading_detail := ""
@export var status_message := "첫 화면을 준비하는 중"
@export_range(0.0, 5.0, 0.05) var minimum_visible_time := 0.9
@export var auto_start := true

const BACKDROP := preload("res://assets/ui/main_menu_background.png")
const BACKDROP_SHADER := preload("res://shaders/loading_backdrop.gdshader")
const LOADING_FONT := preload("res://assets/fonts/NotoSerifKR-Variable.ttf")
const COLOR_IVORY := Color(0.85, 0.83, 0.77)
const COLOR_TEXT := Color(0.58, 0.58, 0.55)
const TIPS := [
	"체력이 0이 된 부위는 수술한 뒤 회복할 수 있습니다.",
	"아이템을 사용하는 도중 F를 누르면 취소합니다.",
	"출혈은 붕대로, 골절은 부목으로 치료합니다.",
]
const OVERLAY_LAYER := 1000
const OVERLAY_HOST_META := &"sanctuary_loading_host"

var loading_spinner: Control
var title_label: Label
var detail_label: Label
var activity_label: Label
var progress_bar: ProgressBar
var backdrop: TextureRect
var content: Control

var _loading_font: Font
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
		activity_label.text = "불러오기 완료"
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
		activity_label.text = "오류 코드 %d" % error_code
	if is_instance_valid(loading_spinner):
		loading_spinner.hide()
	if is_instance_valid(progress_bar):
		progress_bar.hide()
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


func _animate_activity() -> void:
	if _request_failed:
		return
	if is_instance_valid(loading_spinner):
		loading_spinner.rotation = _elapsed * 1.7
	if is_instance_valid(activity_label) and not _transition_committed:
		activity_label.text = "불러오는 중" + ".".repeat(1 + floori(_elapsed * 1.5) % 3)


func _apply_loading_copy() -> void:
	if not _interface_ready:
		return
	# Callers retain their transition metadata; the screen uses concise place names.
	var destination := "잔향의 성소"
	match target_scene_path.get_file():
		"hideout.tscn": destination = "은신처"
		"main.tscn": destination = "검은 성물실"
		"cave_dungeon.tscn": destination = "폐광"
		"merchant.tscn": destination = "상인"
		"test_room.tscn": destination = "테스트룸"
	title_label.text = destination
	detail_label.text = TIPS[absi(target_scene_path.hash()) % TIPS.size()]
	activity_label.text = "불러오는 중..."
	loading_spinner.show()
	progress_bar.show()


func _build_interface() -> void:
	_loading_font = LOADING_FONT
	var background := ColorRect.new()
	background.name = "LoadingBackground"
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	backdrop = TextureRect.new()
	backdrop.name = "LoadingScene"
	backdrop.texture = BACKDROP
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var treatment := ShaderMaterial.new()
	treatment.shader = BACKDROP_SHADER
	backdrop.material = treatment
	add_child(backdrop)

	content = Control.new()
	content.name = "LoadingCopy"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	title_label = _label("", 15, COLOR_TEXT)
	title_label.name = "LoadingDestination"
	content.add_child(title_label)
	activity_label = _label("불러오는 중...", 23, COLOR_IVORY)
	activity_label.name = "LoadingActivity"
	content.add_child(activity_label)
	detail_label = _label("", 13, COLOR_TEXT)
	detail_label.name = "LoadingTip"
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail_label)

	loading_spinner = Control.new()
	loading_spinner.name = "LoadingActivityRing"
	loading_spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(loading_spinner)
	for index in range(12):
		var angle := TAU * float(index) / 12.0
		var mark := ColorRect.new()
		mark.size = Vector2(1.5, 4)
		mark.position = Vector2(cos(angle), sin(angle)) * 8.0 - mark.size * 0.5
		mark.pivot_offset = mark.size * 0.5
		mark.rotation = angle + PI * 0.5
		mark.color = Color(COLOR_IVORY, 0.12 + float(index + 1) * 0.065)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		loading_spinner.add_child(mark)

	progress_bar = ProgressBar.new()
	progress_bar.name = "LoadingProgress"
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.7, 0.68, 0.62, 0.12)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.68, 0.65, 0.56, 0.65)
	progress_bar.add_theme_stylebox_override("background", track)
	progress_bar.add_theme_stylebox_override("fill", fill)
	content.add_child(progress_bar)
	resized.connect(_layout_interface)
	_layout_interface()


func _layout_interface() -> void:
	if not is_instance_valid(content):
		return
	var factor := clampf(size.y / 720.0, 0.75, 1.5)
	var width := minf(760.0, (size.x - 48.0) / factor)
	content.scale = Vector2.ONE * factor
	content.position = Vector2(size.x * 0.5, size.y - 142 * factor)
	for label in [title_label, activity_label, detail_label]:
		label.position.x = -width * 0.5
		label.size.x = width
	title_label.position.y = 0
	title_label.size.y = 24
	activity_label.position.y = 28
	activity_label.size.y = 38
	detail_label.position.y = 94
	detail_label.size.y = 42
	loading_spinner.position = Vector2(-106, 49)
	progress_bar.position = Vector2(-110, 79)
	progress_bar.size = Vector2(220, 1)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", _loading_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
