extends CanvasLayer
## Optional live measurements owned by the isolated test session.

const SAMPLER := preload("res://scripts/performance_sampler.gd")
const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const HISTORY_FRAMES := 300

var sampler := SAMPLER.new()
var label: Label
var enabled := false
var _scene_id := 0
var _previous_usec := 0
var _warmup_left := 1.0
var _refresh_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 79
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.position = Vector2(12, 58)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.035, 0.88)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", 14)
	panel.add_child(label)
	set_enabled(false)


func set_enabled(value: bool) -> void:
	sampler.end()
	enabled = value
	visible = value
	_scene_id = 0
	_previous_usec = 0
	_warmup_left = 1.0
	sampler.samples.clear()
	if is_instance_valid(label):
		label.text = "성능 측정 준비 중 · 목표 60 FPS"


func _exit_tree() -> void:
	sampler.end()


func _process(delta: float) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_usec()
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or get_tree().paused:
		_previous_usec = 0
		label.text = "성능 측정 대기 · 플레이를 재개하면 측정합니다"
		return
	if DisplayServer.get_name() == "headless":
		label.text = "화면 렌더러가 없는 실행에서는 FPS를 측정하지 않습니다"
		return
	if _scene_id != scene.get_instance_id():
		_scene_id = scene.get_instance_id()
		sampler.begin(SAMPLER.collect_viewports(get_tree().root))
		_warmup_left = 1.0
		_previous_usec = 0
	_warmup_left -= delta
	if _previous_usec == 0 or _warmup_left > 0.0:
		_previous_usec = now
		return
	sampler.record(float(now - _previous_usec) / 1000.0)
	_previous_usec = now
	if sampler.samples.size() > HISTORY_FRAMES:
		sampler.samples.pop_front()
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.5
		_refresh_label()


func _refresh_label() -> void:
	var result := sampler.summary()
	if result.is_empty():
		return
	var fps := 1000.0 / maxf(float(result.wall_ms.mean), 0.01)
	label.text = "%.0f FPS · 목표 60\n프레임 %.1f ms · 느린 5%% %.1f ms\nGPU %.1f ms · 그리기 %d회\nF2 시험 메뉴 → 성능 측정으로 끄기" % [fps, result.wall_ms.mean, result.wall_ms.p95, result.render_gpu_ms.mean, roundi(result.draw_calls.mean)]
