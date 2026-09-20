extends CanvasLayer
class_name CampPlacementOverlay

const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const READY_COLOR := Color(0.55, 0.88, 0.57)
const BLOCKED_COLOR := Color(0.94, 0.42, 0.34)

var overlay_root: Control
var panel_root: PanelContainer
var state_label: Label
var reason_label: Label
var controls_label: Label
var snapshot: Dictionary = {}
var _layout_pending := false


func _ready() -> void:
	_ensure_built()
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)
	_update_layout()


func show_placement() -> void:
	_ensure_built()
	_update_layout()
	overlay_root.show()


func hide_placement() -> void:
	if is_instance_valid(overlay_root):
		overlay_root.hide()


func set_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	_ensure_built()
	var accepted := bool(snapshot.get("accepted", false))
	state_label.text = "야영지 · 설치 가능" if accepted else "야영지 · 설치 불가"
	state_label.add_theme_color_override("font_color", READY_COLOR if accepted else BLOCKED_COLOR)
	var message := str(snapshot.get("message", ""))
	if message.is_empty():
		message = "야영 도구 1개를 사용합니다." if accepted else _reason_text(str(snapshot.get("reason", "")))
	reason_label.text = message
	controls_label.text = "[ LMB ] 설치     [ F ] 취소"
	controls_label.add_theme_color_override("font_color", Color(0.84, 0.81, 0.72) if accepted else Color(0.64, 0.62, 0.56))
	_queue_layout()


func _ensure_built() -> void:
	if is_instance_valid(overlay_root):
		return
	layer = 84
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_root = Control.new()
	overlay_root.name = "CampPlacementHUD"
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.hide()
	add_child(overlay_root)
	panel_root = PanelContainer.new()
	panel_root.name = "PlacementStatus"
	panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Font wrapping updates the container minimum over several layout passes.
	# Refit when that minimum changes and keep its final bottom edge anchored.
	panel_root.minimum_size_changed.connect(_queue_layout)
	panel_root.resized.connect(_position_panel)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.012, 0.013, 0.011, 0.86)
	background.border_color = Color(0.38, 0.35, 0.27, 0.75)
	background.border_width_bottom = 1
	background.content_margin_left = 18.0
	background.content_margin_right = 18.0
	background.content_margin_top = 10.0
	background.content_margin_bottom = 11.0
	panel_root.add_theme_stylebox_override("panel", background)
	overlay_root.add_child(panel_root)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	panel_root.add_child(content)
	state_label = _label("야영지 · 설치 불가", 18, BLOCKED_COLOR)
	state_label.name = "PlacementState"
	content.add_child(state_label)
	reason_label = _label("평평하고 비어 있는 바닥을 바라보세요.", 13, Color(0.82, 0.80, 0.73))
	reason_label.name = "PlacementReason"
	content.add_child(reason_label)
	controls_label = _label("[ LMB ] 설치     [ F ] 취소", 13, Color(0.70, 0.68, 0.61))
	controls_label.name = "PlacementControls"
	content.add_child(controls_label)
	_update_layout()


func _update_layout() -> void:
	_layout_pending = false
	if not is_instance_valid(panel_root) or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var width := minf(420.0, maxf(0.0, viewport_size.x - 24.0))
	panel_root.size = Vector2(width, 0.0)
	_position_panel()


func _queue_layout() -> void:
	if _layout_pending:
		return
	_layout_pending = true
	_update_layout.call_deferred()


func _position_panel() -> void:
	if not is_instance_valid(panel_root) or not is_inside_tree():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var bottom_margin := clampf(viewport_size.y * 0.11, 20.0, 90.0)
	panel_root.position = Vector2((viewport_size.x - panel_root.size.x) * 0.5, viewport_size.y - bottom_margin - panel_root.size.y)


func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _reason_text(reason: String) -> String:
	match reason:
		"enemy_nearby":
			return "적이 가까이 있습니다. 안전한 곳으로 이동하세요."
		"no_floor", "no_surface", "no_ground", "too_far", "out_of_range":
			return "가까운 바닥을 바라보세요."
		"steep_slope", "uneven_ground", "slope", "uneven_floor":
			return "평평한 바닥이 필요합니다."
		"camp_kit_missing", "missing_kit", "no_camp_kit":
			return "야영 도구가 필요합니다."
		"blocked_space", "blocked", "seat_blocked":
			return "천막과 모닥불, 앉을 자리가 비어 있어야 합니다."
		_:
			return "평평하고 비어 있는 바닥을 바라보세요."
