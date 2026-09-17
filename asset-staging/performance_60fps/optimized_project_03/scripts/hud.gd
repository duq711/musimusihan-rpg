extends CanvasLayer
class_name DungeonHUD

const BOW_RETICLE_REST_RADIUS := 4.0
const BOW_RETICLE_TICK_LENGTH := 9.0
const BOW_RETICLE_DRAW_TICK_LENGTH := 15.0

var health_bar: ProgressBar
var stamina_bar: ProgressBar
var hunger_bar: ProgressBar
var thirst_bar: ProgressBar
var stress_bar: ProgressBar
var health_label: Label
var stamina_label: Label
var hunger_label: Label
var thirst_label: Label
var stress_label: Label
var condition_label: Label
var state_label: Label
var torch_status_label: Label
var objective_label: Label
var location_label: Label
var loot_label: Label
var prompt_label: Label
var event_label: Label
var crosshair: Label
var hit_marker: Label
var damage_flash: ColorRect
var healing_flash: ColorRect
var control_legend_label: Label
var magic_panel: Panel
var magic_title_label: Label
var magic_cost_label: Label
var magic_slots_label: Label
var archery_panel: Panel
var archery_title_label: Label
var bow_accuracy_label: Label
var bow_stamina_label: Label
var archery_help_label: Label
var arrow_count_label: Label
var bow_draw_bar: ProgressBar
var bow_spread_reticle: Control
var bow_spread_ticks: Array[ColorRect] = []
var bow_spread_radius := BOW_RETICLE_REST_RADIUS
var bow_spread_tick_length := BOW_RETICLE_TICK_LENGTH
var flail_panel: Panel
var flail_title_label: Label
var flail_detail_label: Label
var flail_charge_bar: ProgressBar
var flail_help_label: Label

var interaction_panel: Panel
var interaction_title: Label
var interaction_progress: ProgressBar
var interaction_help: Label

var trap_panel: Panel
var trap_title: Label
var trap_help: Label
var trap_success: ColorRect
var trap_needle: ColorRect

var overlay: ColorRect
var overlay_title: Label
var overlay_detail: Label

var _event_token := 0
var _hit_token := 0
var _archery_reticle_requested := false
var _archery_drawing := false
var _archery_draw_ratio := 0.0
var _archery_spread_degrees := 0.0
var _archery_camera_fov_degrees := 76.0
var _stress_fill_styles: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()


func _process(_delta: float) -> void:
	# HUD continues while the world is paused so inventory/F2 menus cannot
	# retain a stale aiming indicator when the player stops processing.
	_refresh_archery_reticle_visibility()
	if is_instance_valid(bow_spread_reticle) and bow_spread_reticle.visible:
		_update_archery_reticle_geometry()


func _build_interface() -> void:
	var root := Control.new()
	root.name = "HUDRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	damage_flash = ColorRect.new()
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.color = Color(0.55, 0.015, 0.01, 0.0)
	damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(damage_flash)
	healing_flash = ColorRect.new()
	healing_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	healing_flash.color = Color(0.22, 0.58, 0.38, 0.0)
	healing_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(healing_flash)

	var top_left := Panel.new()
	top_left.position = Vector2(24, 24)
	top_left.size = Vector2(330, 232)
	top_left.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.029, 0.035, 0.9), Color(0.43, 0.34, 0.2, 0.75)))
	root.add_child(top_left)

	var expedition := _label("원정자 · 잿빛 용병", 17, Color(0.86, 0.78, 0.61))
	expedition.position = Vector2(16, 10)
	top_left.add_child(expedition)
	torch_status_label = _label("횃불 · 장비 ON", 12, Color(1.0, 0.58, 0.25))
	torch_status_label.position = Vector2(192, 12)
	torch_status_label.size = Vector2(120, 20)
	torch_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_left.add_child(torch_status_label)

	health_bar = _bar(Vector2(16, 39), Vector2(298, 20), Color(0.58, 0.08, 0.055))
	top_left.add_child(health_bar)
	health_label = _label("체력 100 / 100", 13, Color(0.98, 0.91, 0.83))
	health_label.position = Vector2(24, 40)
	health_label.size = Vector2(280, 20)
	top_left.add_child(health_label)

	stamina_bar = _bar(Vector2(16, 68), Vector2(298, 18), Color(0.62, 0.48, 0.15))
	top_left.add_child(stamina_bar)
	stamina_label = _label("기력 100 / 100", 12, Color(0.98, 0.91, 0.75))
	stamina_label.position = Vector2(24, 67)
	stamina_label.size = Vector2(280, 20)
	top_left.add_child(stamina_label)

	hunger_bar = _bar(Vector2(16, 97), Vector2(298, 18), Color(0.55, 0.34, 0.12))
	top_left.add_child(hunger_bar)
	hunger_label = _label("포만감 100 / 100", 12, Color(0.94, 0.84, 0.64))
	hunger_label.position = Vector2(24, 96)
	hunger_label.size = Vector2(280, 20)
	top_left.add_child(hunger_label)

	thirst_bar = _bar(Vector2(16, 124), Vector2(298, 18), Color(0.10, 0.42, 0.52))
	top_left.add_child(thirst_bar)
	thirst_label = _label("수분 100 / 100", 12, Color(0.67, 0.88, 0.91))
	thirst_label.position = Vector2(24, 123)
	thirst_label.size = Vector2(280, 20)
	top_left.add_child(thirst_label)
	stress_bar = _bar(Vector2(16, 151), Vector2(298, 18), stress_color(0.0))
	top_left.add_child(stress_bar)
	stress_label = _label("스트레스 0 / 100 · 안정", 12, Color(0.77, 0.70, 0.85))
	stress_label.position = Vector2(24, 150)
	stress_label.size = Vector2(280, 20)
	top_left.add_child(stress_label)
	stress_bar.value = 0.0

	state_label = _label("무기 준비", 13, Color(0.72, 0.77, 0.78))
	state_label.position = Vector2(16, 181)
	state_label.size = Vector2(298, 24)
	top_left.add_child(state_label)
	condition_label = _label("상태 · 안정", 11, Color(0.55, 0.62, 0.61))
	condition_label.position = Vector2(16, 205)
	condition_label.size = Vector2(298, 18)
	condition_label.clip_text = true
	top_left.add_child(condition_label)

	var top_right := Panel.new()
	top_right.anchor_left = 1.0
	top_right.anchor_right = 1.0
	top_right.offset_left = -400.0
	top_right.offset_right = -24.0
	top_right.offset_top = 24.0
	top_right.offset_bottom = 128.0
	top_right.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.029, 0.035, 0.88), Color(0.24, 0.36, 0.39, 0.7)))
	root.add_child(top_right)

	location_label = _label("검은 성물실", 14, Color(0.53, 0.73, 0.72))
	location_label.position = Vector2(15, 10)
	top_right.add_child(location_label)
	objective_label = _label("감시자 2명을 처치하고 귀환문으로 탈출", 15, Color(0.9, 0.88, 0.8))
	objective_label.position = Vector2(15, 35)
	objective_label.size = Vector2(346, 38)
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top_right.add_child(objective_label)
	loot_label = _label("회수품 0 · 해제한 함정 0", 13, Color(0.64, 0.68, 0.66))
	loot_label.position = Vector2(15, 76)
	loot_label.size = Vector2(346, 20)
	top_right.add_child(loot_label)

	crosshair = _label("·", 31, Color(0.84, 0.78, 0.63, 0.85))
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -20
	crosshair.offset_top = -26
	crosshair.offset_right = 20
	crosshair.offset_bottom = 20
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(crosshair)
	_build_archery_reticle(root)

	hit_marker = _label("×", 30, Color(0.92, 0.84, 0.6, 0.0))
	hit_marker.anchor_left = 0.5
	hit_marker.anchor_top = 0.5
	hit_marker.anchor_right = 0.5
	hit_marker.anchor_bottom = 0.5
	hit_marker.offset_left = -22
	hit_marker.offset_top = -24
	hit_marker.offset_right = 22
	hit_marker.offset_bottom = 24
	hit_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hit_marker)

	prompt_label = _label("", 17, Color(0.9, 0.82, 0.61))
	prompt_label.anchor_left = 0.5
	prompt_label.anchor_top = 0.72
	prompt_label.anchor_right = 0.5
	prompt_label.anchor_bottom = 0.72
	prompt_label.offset_left = -260
	prompt_label.offset_top = -20
	prompt_label.offset_right = 260
	prompt_label.offset_bottom = 22
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)

	event_label = _label("", 22, Color(0.95, 0.75, 0.46))
	event_label.anchor_left = 0.5
	event_label.anchor_top = 0.18
	event_label.anchor_right = 0.5
	event_label.anchor_bottom = 0.18
	event_label.offset_left = -360
	event_label.offset_top = -20
	event_label.offset_right = 360
	event_label.offset_bottom = 26
	event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(event_label)

	var controls := Panel.new()
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.offset_left = 24
	controls.offset_top = -90
	controls.offset_right = 630
	controls.offset_bottom = -24
	controls.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.022, 0.027, 0.83), Color(0.17, 0.22, 0.23, 0.7)))
	root.add_child(controls)
	control_legend_label = _label("WASD 이동   SHIFT 달리기   SPACE 도약   C 야영\nLMB 공격/차지   RMB 방패   E 상호작용   I 인벤토리", 13, Color(0.65, 0.69, 0.67))
	control_legend_label.position = Vector2(15, 10)
	control_legend_label.size = Vector2(577, 48)
	controls.add_child(control_legend_label)

	_build_magic_panel(root)
	_build_archery_panel(root)
	_build_flail_panel(root)

	_build_trap_panel(root)
	_build_interaction_panel(root)
	_build_overlay(root)


func _build_archery_reticle(root: Control) -> void:
	bow_spread_reticle = Control.new()
	bow_spread_reticle.name = "BowSpreadReticle"
	bow_spread_reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bow_spread_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bow_spread_reticle.visible = false
	root.add_child(bow_spread_reticle)
	for tick_name in ["Left", "Right", "Top", "Bottom"]:
		var tick := ColorRect.new()
		tick.name = tick_name
		tick.color = Color(0.025, 0.018, 0.012, 0.9)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bow_spread_reticle.add_child(tick)
		bow_spread_ticks.append(tick)
		var ink := ColorRect.new()
		ink.name = "Ink"
		ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ink.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ink.offset_left = 1.0
		ink.offset_top = 1.0
		ink.offset_right = -1.0
		ink.offset_bottom = -1.0
		tick.add_child(ink)


func _build_archery_panel(root: Control) -> void:
	archery_panel = Panel.new()
	archery_panel.name = "ArcheryPanel"
	archery_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	archery_panel.offset_left = -490.0
	archery_panel.offset_top = -150.0
	archery_panel.offset_right = -24.0
	archery_panel.offset_bottom = -24.0
	archery_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	archery_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.027, 0.024, 0.017, 0.93), Color(0.56, 0.43, 0.23, 0.88)))
	archery_panel.visible = false
	root.add_child(archery_panel)
	archery_title_label = _label("사냥꾼의 활 · 준비", 14, Color(0.91, 0.77, 0.5))
	archery_title_label.position = Vector2(16, 9)
	archery_title_label.size = Vector2(310, 23)
	archery_panel.add_child(archery_title_label)
	bow_accuracy_label = _label("힘 부족 · 놓으면 바로 아래로 떨어짐", 12, Color(0.96, 0.49, 0.24))
	bow_accuracy_label.name = "BowAccuracyLabel"
	bow_accuracy_label.position = Vector2(16, 32)
	bow_accuracy_label.size = Vector2(434, 20)
	archery_panel.add_child(bow_accuracy_label)
	bow_stamina_label = _label("", 12, Color(0.87, 0.69, 0.37))
	bow_stamina_label.name = "BowStaminaLabel"
	bow_stamina_label.position = Vector2(16, 56)
	bow_stamina_label.size = Vector2(434, 20)
	archery_panel.add_child(bow_stamina_label)
	arrow_count_label = _label("화살 0발", 14, Color(0.91, 0.77, 0.5))
	arrow_count_label.position = Vector2(336, 9)
	arrow_count_label.size = Vector2(114, 23)
	arrow_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	archery_panel.add_child(arrow_count_label)
	bow_draw_bar = _bar(Vector2(16, 84), Vector2(434, 5), Color(0.8, 0.62, 0.28))
	# ProgressBar invalidates its minimum size asynchronously after theme changes.
	# Resize after that invalidation so a slim meter cannot overlap its help text.
	bow_draw_bar.add_theme_font_size_override("font_size", 1)
	bow_draw_bar.set_deferred("size", Vector2(434, 5))
	bow_draw_bar.value = 0.0
	archery_panel.add_child(bow_draw_bar)
	archery_help_label = _label("LMB 길게 당기기 · 놓아 발사    RMB 취소", 12, Color(0.69, 0.65, 0.54))
	archery_help_label.position = Vector2(16, 95)
	archery_help_label.size = Vector2(434, 22)
	archery_panel.add_child(archery_help_label)


func _build_flail_panel(root: Control) -> void:
	flail_panel = Panel.new()
	flail_panel.name = "FlailPanel"
	flail_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	flail_panel.offset_left = -490.0
	flail_panel.offset_top = -150.0
	flail_panel.offset_right = -24.0
	flail_panel.offset_bottom = -24.0
	flail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flail_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.024, 0.028, 0.029, 0.93), Color(0.47, 0.49, 0.43, 0.88)))
	flail_panel.visible = false
	root.add_child(flail_panel)
	flail_title_label = _label("사슬철퇴 · 준비", 14, Color(0.83, 0.85, 0.73))
	flail_title_label.position = Vector2(16, 9)
	flail_title_label.size = Vector2(434, 23)
	flail_panel.add_child(flail_title_label)
	flail_detail_label = _label("", 12, Color(0.72, 0.76, 0.71))
	flail_detail_label.position = Vector2(16, 33)
	flail_detail_label.size = Vector2(434, 44)
	flail_panel.add_child(flail_detail_label)
	flail_charge_bar = _bar(Vector2(16, 84), Vector2(434, 5), Color(0.64, 0.7, 0.53))
	flail_charge_bar.add_theme_font_size_override("font_size", 1)
	flail_charge_bar.set_deferred("size", Vector2(434, 5))
	flail_panel.add_child(flail_charge_bar)
	flail_help_label = _label("", 12, Color(0.73, 0.69, 0.58))
	flail_help_label.position = Vector2(16, 95)
	flail_help_label.size = Vector2(434, 22)
	flail_panel.add_child(flail_help_label)


func _build_magic_panel(root: Control) -> void:
	magic_panel = Panel.new()
	magic_panel.name = "SpellSelectorPanel"
	magic_panel.anchor_left = 1.0
	magic_panel.anchor_top = 1.0
	magic_panel.anchor_right = 1.0
	magic_panel.anchor_bottom = 1.0
	magic_panel.offset_left = -630.0
	magic_panel.offset_top = -90.0
	magic_panel.offset_right = -24.0
	magic_panel.offset_bottom = -24.0
	magic_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.025, 0.027, 0.9), Color(0.19, 0.48, 0.46, 0.82)))
	magic_panel.visible = false
	root.add_child(magic_panel)

	magic_title_label = _label("마법 · 배운 주문 없음", 14, Color(0.48, 0.85, 0.78))
	magic_title_label.position = Vector2(15, 7)
	magic_title_label.size = Vector2(390, 22)
	magic_panel.add_child(magic_title_label)
	magic_cost_label = _label("", 12, Color(0.85, 0.7, 0.3))
	magic_cost_label.position = Vector2(405, 7)
	magic_cost_label.size = Vector2(184, 22)
	magic_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	magic_panel.add_child(magic_cost_label)
	magic_slots_label = _label("[1] —   [2] —   [3] —   [4] —   [5] —", 12, Color(0.6, 0.69, 0.66))
	magic_slots_label.position = Vector2(15, 34)
	magic_slots_label.size = Vector2(576, 23)
	magic_slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	magic_panel.add_child(magic_slots_label)


func _build_trap_panel(root: Control) -> void:
	trap_panel = Panel.new()
	trap_panel.anchor_left = 0.5
	trap_panel.anchor_top = 0.5
	trap_panel.anchor_right = 0.5
	trap_panel.anchor_bottom = 0.5
	trap_panel.offset_left = -250
	trap_panel.offset_top = -112
	trap_panel.offset_right = 250
	trap_panel.offset_bottom = 112
	trap_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.026, 0.96), Color(0.61, 0.42, 0.16, 0.9)))
	trap_panel.visible = false
	root.add_child(trap_panel)

	trap_title = _label("룬 압력판 해제", 24, Color(0.94, 0.77, 0.43))
	trap_title.position = Vector2(28, 22)
	trap_title.size = Vector2(444, 32)
	trap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trap_panel.add_child(trap_title)

	var gauge := ColorRect.new()
	gauge.position = Vector2(48, 82)
	gauge.size = Vector2(404, 24)
	gauge.color = Color(0.09, 0.08, 0.07, 1.0)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trap_panel.add_child(gauge)

	trap_success = ColorRect.new()
	trap_success.position = Vector2(100, 2)
	trap_success.size = Vector2(90, 20)
	trap_success.color = Color(0.25, 0.57, 0.37, 0.9)
	trap_success.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(trap_success)

	trap_needle = ColorRect.new()
	trap_needle.position = Vector2(0, -5)
	trap_needle.size = Vector2(4, 34)
	trap_needle.color = Color(1.0, 0.82, 0.44, 1.0)
	trap_needle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.add_child(trap_needle)

	trap_help = _label("바늘이 녹색 구간에 들어올 때  E", 16, Color(0.78, 0.76, 0.69))
	trap_help.position = Vector2(28, 135)
	trap_help.size = Vector2(444, 24)
	trap_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trap_panel.add_child(trap_help)

	var warning := _label("해제 중에도 던전의 시간은 흐릅니다", 13, Color(0.64, 0.36, 0.31))
	warning.position = Vector2(28, 174)
	warning.size = Vector2(444, 20)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trap_panel.add_child(warning)


func _build_interaction_panel(root: Control) -> void:
	interaction_panel = Panel.new()
	interaction_panel.name = "TimedInteractionPanel"
	interaction_panel.anchor_left = 0.5
	interaction_panel.anchor_top = 0.68
	interaction_panel.anchor_right = 0.5
	interaction_panel.anchor_bottom = 0.68
	interaction_panel.offset_left = -260
	interaction_panel.offset_top = -42
	interaction_panel.offset_right = 260
	interaction_panel.offset_bottom = 42
	interaction_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.021, 0.021, 0.95), Color(0.53, 0.43, 0.24, 0.92), 1))
	interaction_panel.visible = false
	root.add_child(interaction_panel)

	interaction_title = _label("상호작용 중", 16, Color(0.91, 0.82, 0.62))
	interaction_title.position = Vector2(16, 8)
	interaction_title.size = Vector2(488, 22)
	interaction_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_panel.add_child(interaction_title)

	interaction_progress = _bar(Vector2(20, 35), Vector2(480, 14), Color(0.56, 0.43, 0.19))
	interaction_progress.name = "TimedInteractionProgress"
	interaction_progress.min_value = 0.0
	interaction_progress.max_value = 1.0
	interaction_progress.value = 0.0
	interaction_panel.add_child(interaction_progress)

	interaction_help = _label("시선을 유지하십시오", 11, Color(0.55, 0.57, 0.52))
	interaction_help.position = Vector2(16, 55)
	interaction_help.size = Vector2(488, 18)
	interaction_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_panel.add_child(interaction_help)


func _build_overlay(root: Control) -> void:
	overlay = ColorRect.new()
	overlay.color = Color(0.006, 0.008, 0.011, 0.9)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = false
	root.add_child(overlay)

	var sigil := _label("✦", 34, Color(0.54, 0.72, 0.67))
	sigil.anchor_left = 0.5
	sigil.anchor_top = 0.27
	sigil.anchor_right = 0.5
	sigil.anchor_bottom = 0.27
	sigil.offset_left = -40
	sigil.offset_top = -30
	sigil.offset_right = 40
	sigil.offset_bottom = 30
	sigil.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(sigil)

	overlay_title = _label("", 38, Color(0.91, 0.84, 0.7))
	overlay_title.anchor_left = 0.5
	overlay_title.anchor_top = 0.39
	overlay_title.anchor_right = 0.5
	overlay_title.anchor_bottom = 0.39
	overlay_title.offset_left = -440
	overlay_title.offset_top = -35
	overlay_title.offset_right = 440
	overlay_title.offset_bottom = 35
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay.add_child(overlay_title)

	overlay_detail = _label("", 18, Color(0.68, 0.71, 0.68))
	overlay_detail.anchor_left = 0.5
	overlay_detail.anchor_top = 0.54
	overlay_detail.anchor_right = 0.5
	overlay_detail.anchor_bottom = 0.54
	overlay_detail.offset_left = -440
	overlay_detail.offset_top = -70
	overlay_detail.offset_right = 440
	overlay_detail.offset_bottom = 100
	overlay_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay.add_child(overlay_detail)


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _bar(pos: Vector2, bar_size: Vector2, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = pos
	bar.size = bar_size
	bar.min_value = 0
	bar.max_value = 100
	bar.value = 100
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _panel_style(Color(0.075, 0.075, 0.07, 0.95), Color(0.18, 0.17, 0.15, 0.9), 2))
	bar.add_theme_stylebox_override("fill", _panel_style(fill_color, fill_color.lightened(0.12), 2))
	return bar


func _panel_style(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func update_health(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	health_label.text = "체력 %d / %d" % [roundi(current), roundi(maximum)]


func update_stamina(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	stamina_label.text = "기력 %d / %d" % [roundi(current), roundi(maximum)]


func update_stress(current: float, maximum := 100.0, stage := "") -> void:
	if not is_instance_valid(stress_bar):
		return
	var limit := maxf(1.0, maximum)
	var value := clampf(current, 0.0, limit)
	var normalized := value / limit * StressProfile.MAX_STRESS
	var caption := stage if not stage.is_empty() else StressProfile.stage_name(normalized)
	var accent := stress_color(normalized)
	stress_bar.max_value = limit
	stress_bar.value = value
	if not _stress_fill_styles.has(accent):
		_stress_fill_styles[accent] = _panel_style(accent.darkened(0.15), accent, 1)
	var fill: StyleBoxFlat = _stress_fill_styles[accent]
	if stress_bar.get_theme_stylebox("fill") != fill:
		stress_bar.add_theme_stylebox_override("fill", fill)
	_set_label_caption(stress_label, "스트레스 %d / %d · %s" % [roundi(value), roundi(limit), caption])
	# The label sits on the filled bar; a pale neutral remains readable even
	# when the extreme-stress fill is bright red.
	_set_label_color(stress_label, Color(0.98, 0.94, 0.98))


static func stress_color(value: float) -> Color:
	match StressProfile.stage_index(value):
		1: return Color(0.80, 0.67, 0.34)
		2: return Color(0.91, 0.48, 0.23)
		3: return Color(0.88, 0.27, 0.30)
	return Color(0.58, 0.51, 0.70)


func update_survival(hunger: float, thirst: float, maximum := 100.0) -> void:
	if is_instance_valid(hunger_bar):
		hunger_bar.max_value = maximum
		hunger_bar.value = hunger
	if is_instance_valid(thirst_bar):
		thirst_bar.max_value = maximum
		thirst_bar.value = thirst
	if is_instance_valid(hunger_label):
		_set_label_caption(hunger_label, "포만감 %d / %d" % [roundi(hunger), roundi(maximum)])
		_set_label_color(hunger_label, _need_color(hunger, Color(0.94, 0.84, 0.64)))
	if is_instance_valid(thirst_label):
		_set_label_caption(thirst_label, "수분 %d / %d" % [roundi(thirst), roundi(maximum)])
		_set_label_color(thirst_label, _need_color(thirst, Color(0.67, 0.88, 0.91)))


func update_conditions(conditions: Dictionary, drain_multiplier := 1.0) -> void:
	if not is_instance_valid(condition_label):
		return
	if conditions.is_empty():
		_set_label_caption(condition_label, "상태 · 안정")
		_set_label_color(condition_label, Color(0.55, 0.62, 0.61))
		return
	var entries: Array[String] = []
	for condition_id in ["bleeding", "fracture", "curse"]:
		if not conditions.has(condition_id):
			continue
		entries.append(ExpeditionSession.get_condition_display_name(condition_id))
	_set_label_caption(condition_label, "상태 · %s · 소모 ×%.2f" % [" / ".join(entries), drain_multiplier])
	_set_label_color(condition_label, Color(0.91, 0.42, 0.31))


func update_weapon_state(text_value: String, color := Color(0.72, 0.77, 0.78)) -> void:
	_set_label_caption(state_label, text_value)
	_set_label_color(state_label, color)


func _set_label_caption(label: Label, text_value: String) -> void:
	if label.text != text_value:
		label.text = text_value


func _set_label_color(label: Label, color: Color) -> void:
	if label.get_theme_color("font_color") != color:
		label.add_theme_color_override("font_color", color)


func update_magic(learned_spell_ids: Array, selected_spell: String, staff_equipped: bool) -> void:
	if is_instance_valid(control_legend_label):
		control_legend_label.text = (
			"WASD 이동   SHIFT 달리기   SPACE 도약   C 야영   1~5 주문\nLMB 마법 시전   RMB 방패   E 상호작용   I 인벤토리"
			if staff_equipped
			else "WASD 이동   SHIFT 달리기   SPACE 도약   C 야영\nLMB 공격/차지   RMB 방패   E 상호작용   I 인벤토리"
		)
	if not is_instance_valid(magic_panel):
		return
	magic_panel.visible = staff_equipped
	if not staff_equipped:
		return
	if is_instance_valid(flail_panel):
		flail_panel.visible = false
	if is_instance_valid(archery_panel):
		archery_panel.visible = false
	_archery_reticle_requested = false
	_refresh_archery_reticle_visibility()
	var learned_lookup := {}
	for spell_id_value in learned_spell_ids:
		learned_lookup[str(spell_id_value)] = true
	var entries: Array[String] = []
	for index in range(SpellCatalog.SPELL_ORDER.size()):
		var spell_id := str(SpellCatalog.SPELL_ORDER[index])
		var definition := SpellCatalog.get_spell_definition(spell_id)
		var short_name := str(definition.get("short_name", "?")) if learned_lookup.has(spell_id) else "—"
		var marker := "▶" if spell_id == selected_spell else ""
		entries.append("%s[%d] %s" % [marker, index + 1, short_name])
	magic_slots_label.text = "   ".join(entries)
	if selected_spell.is_empty() or not learned_lookup.has(selected_spell):
		magic_title_label.text = "마법 · 먼저 마법서를 사용해 주문을 익히십시오"
		magic_cost_label.text = "LMB 시전"
		return
	var selected_definition := SpellCatalog.get_spell_definition(selected_spell)
	magic_title_label.text = "마법 · %s" % str(selected_definition.get("name", selected_spell))
	magic_cost_label.text = "기력 %d · LMB 시전" % roundi(float(selected_definition.get("stamina_cost", 0.0)))


func update_archery(equipped: bool, arrows: int, draw_ratio: float, drawing: bool, cooldown: float, spread_degrees: float = 0.0, camera_fov_degrees: float = 76.0) -> void:
	if not is_instance_valid(archery_panel):
		return
	archery_panel.visible = equipped
	_archery_reticle_requested = equipped and arrows > 0 and cooldown <= 0.0
	_archery_drawing = _archery_reticle_requested and drawing
	_archery_draw_ratio = clampf(draw_ratio, 0.0, 1.0) if _archery_drawing else 0.0
	_archery_spread_degrees = clampf(spread_degrees, 0.0, 45.0)
	_archery_camera_fov_degrees = clampf(camera_fov_degrees, 1.0, 179.0)
	_update_archery_reticle_geometry()
	_refresh_archery_reticle_visibility()
	if not equipped:
		return
	if is_instance_valid(magic_panel):
		magic_panel.visible = false
	if is_instance_valid(flail_panel):
		flail_panel.visible = false
	control_legend_label.text = "WASD 이동   SHIFT 달리기   SPACE 도약   C 야영\nLMB 활 당기기/발사   RMB 취소   E 상호작용   I 인벤토리"
	arrow_count_label.text = "화살 %d발" % arrows
	_set_label_color(arrow_count_label, Color(0.91, 0.77, 0.5) if arrows > 0 else Color(0.95, 0.36, 0.23))
	var charge := clampf(draw_ratio, 0.0, 1.0)
	bow_draw_bar.value = charge * 100.0
	var accuracy_color := Color(0.96, 0.49, 0.24).lerp(Color(0.7, 0.92, 0.75), charge)
	_set_label_color(bow_accuracy_label, accuracy_color)
	bow_accuracy_label.text = (
		"정조준 · 시위 흔들림 없음"
		if _archery_spread_degrees <= 0.001
		else "흩어짐 ±%.1f° · 끝까지 당겨 정조준" % _archery_spread_degrees
	)
	if BowShotProfile.is_slack_draw(charge if drawing else 0.0):
		bow_accuracy_label.text = "힘 부족 · 놓으면 바로 아래로 떨어짐"
	for tick in bow_spread_ticks:
		(tick.get_node("Ink") as ColorRect).color = accuracy_color
	var draw_fill := bow_draw_bar.get_theme_stylebox("fill") as StyleBoxFlat
	draw_fill.bg_color = accuracy_color
	draw_fill.border_color = accuracy_color.lightened(0.12)
	var stamina_drain := roundi(BowShotProfile.STAMINA_DRAIN_PER_SECOND)
	bow_stamina_label.text = "당김·유지 기력 %d/초 · 발사 추가 소모 없음" % stamina_drain
	if drawing:
		var damage := roundi(BowShotProfile.damage_for_draw(charge))
		archery_title_label.text = "시위 %d%% · 피해 %d" % [roundi(charge * 100.0), damage]
		bow_stamina_label.text = "기력 -%d/초 · 고갈 시 현재 힘으로 자동 발사" % stamina_drain
		if charge >= 1.0:
			archery_title_label.text = "시위 100%% · 최대 피해 %d" % damage
			bow_stamina_label.text = "기력 -%d/초 · 완전 당김도 소모 · 고갈 시 자동 발사" % stamina_drain
	elif arrows <= 0:
		archery_title_label.text = "화살 없음 · 가방에 탄약을 준비하세요"
		bow_accuracy_label.text = "화살을 준비하면 조준 범위가 표시됩니다"
	elif cooldown > 0.0:
		archery_title_label.text = "다음 화살 준비 · %.1f초" % cooldown
		bow_accuracy_label.text = "바로 놓으면 아래로 낙하 · 끝까지 당겨 정조준"
	else:
		archery_title_label.text = "사냥꾼의 활 · 피해 %d~%d" % [roundi(BowShotProfile.MIN_DAMAGE), roundi(BowShotProfile.MAX_DAMAGE)]


func update_flail(equipped: bool, state: String, charge: float, cooldown: float) -> void:
	if not is_instance_valid(flail_panel):
		return
	flail_panel.visible = equipped
	if not equipped:
		return
	magic_panel.visible = false
	archery_panel.visible = false
	_archery_reticle_requested = false
	_archery_drawing = false
	_update_archery_reticle_geometry()
	_refresh_archery_reticle_visibility()
	control_legend_label.text = "WASD 이동   SHIFT 달리기   SPACE 도약   C 야영\nLMB 철퇴 휘두르기   RMB 회전/투척   E 상호작용   I 인벤토리"
	var power := clampf(charge, 0.0, 1.0)
	flail_charge_bar.visible = state == "spinning"
	flail_charge_bar.value = power * 100.0 if state == "spinning" else 0.0
	flail_title_label.text = "사슬철퇴 · 준비"
	flail_detail_label.text = "근접 피해 %d · 기력 %d\n회전 시작 기력 %d · 유지 추가 소모 없음" % [roundi(FlailProfile.MELEE_DAMAGE), roundi(FlailProfile.MELEE_STAMINA), roundi(FlailProfile.SPIN_STAMINA)]
	flail_help_label.text = "LMB 휘두르기 · RMB 길게 회전/놓아 던지기"
	match state:
		"melee":
			flail_title_label.text = "사슬철퇴 · 근접 휘두르기"
			flail_help_label.text = "휘두르기가 끝나면 다시 공격할 수 있습니다"
		"spinning":
			flail_title_label.text = "사슬철퇴 · 회전 %d%%" % roundi(power * 100.0)
			if power >= 1.0:
				flail_title_label.text = "사슬철퇴 · 최대 회전 100%"
			flail_detail_label.text = "투척 피해 %d · 사거리 %.1fm\n기력 %d 지불 · 유지 추가 소모 없음" % [roundi(FlailProfile.throw_damage(power)), FlailProfile.throw_range(power), roundi(FlailProfile.SPIN_STAMINA)]
			flail_help_label.text = "RMB 놓아 던지기 · 짧게 눌러도 %.2f초 회전" % FlailProfile.MIN_SPIN_DURATION
		"outbound", "returning":
			flail_title_label.text = "사슬철퇴 · 투척 중" if state == "outbound" else "사슬철퇴 · 회수 중"
			flail_detail_label.text = "철구가 돌아올 때까지 재공격 불가\n회수 중에는 피해 없음 · 무기 소모 없음"
			flail_help_label.text = "사슬을 따라 자동으로 돌아옵니다"
		"recovery":
			flail_title_label.text = "사슬철퇴 · 자세 회복 %.1f초" % maxf(0.0, cooldown)
			flail_help_label.text = "자세를 회복하면 다시 공격할 수 있습니다"


func _archery_reticle_should_show(mouse_captured: bool) -> bool:
	return (
		_archery_reticle_requested
		and mouse_captured
		and not get_tree().paused
		and not (is_instance_valid(overlay) and overlay.visible)
		and not (is_instance_valid(trap_panel) and trap_panel.visible)
		and not (is_instance_valid(interaction_panel) and interaction_panel.visible)
	)


func _refresh_archery_reticle_visibility() -> void:
	if is_instance_valid(bow_spread_reticle):
		bow_spread_reticle.visible = _archery_reticle_should_show(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func _update_archery_reticle_geometry() -> void:
	if bow_spread_ticks.size() != 4:
		return
	# Expand only while drawing, so a fresh press visibly opens the resting
	# crosshair. Camera3D KEEP_HEIGHT uses vertical FOV for the real launch cone.
	# Add the original 4 px gap instead of clamping to it: the reticle keeps
	# contracting until full draw, then exactly matches the original shape.
	var visual_spread := _archery_spread_degrees if _archery_drawing and _archery_draw_ratio < 1.0 else 0.0
	var focal_length := get_viewport().get_visible_rect().size.y * 0.5 / tan(deg_to_rad(_archery_camera_fov_degrees) * 0.5)
	bow_spread_radius = BOW_RETICLE_REST_RADIUS + focal_length * tan(deg_to_rad(visual_spread))
	bow_spread_tick_length = lerpf(BOW_RETICLE_DRAW_TICK_LENGTH, BOW_RETICLE_TICK_LENGTH, _archery_draw_ratio) if _archery_drawing else BOW_RETICLE_TICK_LENGTH
	bow_spread_ticks[0].position = Vector2(-bow_spread_radius - bow_spread_tick_length, -2.0)
	bow_spread_ticks[0].size = Vector2(bow_spread_tick_length, 4.0)
	bow_spread_ticks[1].position = Vector2(bow_spread_radius, -2.0)
	bow_spread_ticks[1].size = Vector2(bow_spread_tick_length, 4.0)
	bow_spread_ticks[2].position = Vector2(-2.0, -bow_spread_radius - bow_spread_tick_length)
	bow_spread_ticks[2].size = Vector2(4.0, bow_spread_tick_length)
	bow_spread_ticks[3].position = Vector2(-2.0, bow_spread_radius)
	bow_spread_ticks[3].size = Vector2(4.0, bow_spread_tick_length)


func update_torch(enabled: bool) -> void:
	if torch_status_label == null:
		return
	torch_status_label.text = "횃불 · 장비 %s" % ("ON" if enabled else "OFF")
	torch_status_label.add_theme_color_override("font_color", Color(1.0, 0.58, 0.25) if enabled else Color(0.4, 0.42, 0.4))


func update_objective(enemies_left: int, loot_count: int, traps_disarmed: int) -> void:
	if enemies_left > 0:
		objective_label.text = "감시자 %d명 처치 후 귀환문으로 탈출" % enemies_left
	else:
		objective_label.text = "귀환문이 열렸습니다 · 가장 깊은 방으로 이동"
	loot_label.text = "회수품 %d · 해제한 함정 %d" % [loot_count, traps_disarmed]


func set_prompt(text_value: String) -> void:
	prompt_label.text = text_value


func show_interaction_progress(title_text: String, duration: float) -> void:
	if interaction_panel == null:
		return
	interaction_title.text = title_text
	interaction_progress.min_value = 0.0
	interaction_progress.max_value = maxf(duration, 0.001)
	interaction_progress.value = 0.0
	interaction_panel.visible = true
	_refresh_archery_reticle_visibility()


func update_interaction_progress(elapsed: float, duration: float) -> void:
	if interaction_panel == null:
		return
	interaction_progress.max_value = maxf(duration, 0.001)
	interaction_progress.value = clampf(elapsed, 0.0, interaction_progress.max_value)


func hide_interaction_progress() -> void:
	if interaction_panel == null:
		return
	interaction_panel.visible = false
	interaction_progress.value = 0.0
	_refresh_archery_reticle_visibility()


func show_event(text_value: String, duration := 1.8) -> void:
	_event_token += 1
	var token := _event_token
	event_label.text = text_value
	await get_tree().create_timer(duration).timeout
	if token == _event_token:
		event_label.text = ""


func show_hit(headshot := false) -> void:
	_hit_token += 1
	var token := _hit_token
	hit_marker.text = "✣" if headshot else "×"
	hit_marker.add_theme_color_override("font_color", Color(1.0, 0.77, 0.35, 1.0) if headshot else Color(0.9, 0.82, 0.65, 1.0))
	await get_tree().create_timer(0.12).timeout
	if token == _hit_token:
		hit_marker.add_theme_color_override("font_color", Color(0.9, 0.82, 0.65, 0.0))


func flash_damage() -> void:
	damage_flash.color = Color(0.55, 0.01, 0.005, 0.38)
	var tween := create_tween()
	tween.tween_property(damage_flash, "color", Color(0.55, 0.01, 0.005, 0.0), 0.38)


func flash_healing() -> void:
	if not is_instance_valid(healing_flash):
		return
	healing_flash.color = Color(0.22, 0.58, 0.38, 0.24)
	var tween := create_tween()
	tween.tween_property(healing_flash, "color", Color(0.22, 0.58, 0.38, 0.0), 0.48)


func show_trap_meter(title_text: String, zone_start: float, zone_end: float) -> void:
	hide_interaction_progress()
	trap_title.text = title_text
	trap_panel.visible = true
	crosshair.visible = false
	_refresh_archery_reticle_visibility()
	update_trap_meter(0.0, zone_start, zone_end)


func update_trap_meter(value: float, zone_start: float, zone_end: float) -> void:
	var gauge_width := 404.0
	trap_success.position.x = zone_start * gauge_width
	trap_success.size.x = (zone_end - zone_start) * gauge_width
	trap_needle.position.x = clampf(value, 0.0, 1.0) * (gauge_width - trap_needle.size.x)


func hide_trap_meter() -> void:
	trap_panel.visible = false
	crosshair.visible = true
	_refresh_archery_reticle_visibility()


func show_overlay(title_text: String, detail_text: String) -> void:
	overlay_title.text = title_text
	overlay_detail.text = detail_text
	overlay.visible = true
	_refresh_archery_reticle_visibility()


func hide_overlay() -> void:
	overlay.visible = false
	_refresh_archery_reticle_visibility()


func _need_color(value: float, normal_color: Color) -> Color:
	if value <= 15.0:
		return Color(1.0, 0.28, 0.20)
	if value <= 30.0:
		return Color(1.0, 0.62, 0.24)
	return normal_color
