extends Control
## The unified character page chrome. Its meters consume actual player state;
## equipment and treatment inputs remain owned by their production panels.

signal equipment_requested
signal health_requested
signal close_requested

const FONT := preload("res://assets/fonts/NotoSerifKR-Variable.ttf")
const BACKGROUND_PATH := "res://assets/ui/unified_character_inventory_v1.png"
const FALLBACK_BACKGROUND_PATH := "res://assets/ui/health_reference_sanctuary_v1.png"
const INK := Color(0.72, 0.64, 0.49)
const RULE := Color(0.34, 0.29, 0.21)
const TEXT := Color(0.81, 0.74, 0.62)
const KEYS := ["overview", "equipment", "skills", "map", "quests"]
const TITLES := ["종합정보", "장비·건강상태", "스킬", "지도", "임무"]
const TAB_RECTS := [Rect2(21, 12, 180, 40), Rect2(203, 12, 260, 40), Rect2(465, 12, 172, 40), Rect2(639, 12, 166, 40), Rect2(807, 12, 171, 40)]
const METER_KEYS := ["hunger", "thirst", "stamina", "stress"]
const METER_TITLES := ["배고픔", "갈증", "기력", "스트레스"]
const METER_COLORS := [Color(0.59, 0.46, 0.30), Color(0.35, 0.51, 0.55), Color(0.45, 0.39, 0.51), Color(0.51, 0.51, 0.48)]
const METER_WIDTH := 120.0

var tab_buttons: Dictionary = {}
var survival_bars: Dictionary = {}
var survival_value_labels: Dictionary = {}
var close_button: Button
var background_texture: Texture2D
var _built := false


func _ready() -> void:
	build()


func build() -> void:
	if _built:
		return
	_built = true
	size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := FontVariation.new()
	font.base_font = FONT
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	theme = Theme.new()
	theme.default_font = font
	if ResourceLoader.exists(BACKGROUND_PATH):
		background_texture = load(BACKGROUND_PATH)
	elif ResourceLoader.exists(FALLBACK_BACKGROUND_PATH):
		background_texture = load(FALLBACK_BACKGROUND_PATH)
	for i in KEYS.size():
		var button := Button.new()
		button.name = "CharacterNavigation_" + KEYS[i]
		button.position = TAB_RECTS[i].position
		button.size = TAB_RECTS[i].size
		button.text = TITLES[i]
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 19)
		button.add_theme_color_override("font_color", TEXT)
		button.add_theme_color_override("font_disabled_color", Color(0.68, 0.62, 0.51))
		button.add_theme_color_override("font_hover_color", Color(0.95, 0.87, 0.71))
		button.add_theme_color_override("font_focus_color", TEXT)
		for state in ["normal", "disabled", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.13, 0.045, 0.034, 0.50) if i == 1 else Color.TRANSPARENT
			if state in ["hover", "pressed"]:
				style.bg_color = Color(0.22, 0.14, 0.085, 0.3)
			style.content_margin_left = 35.0
			style.content_margin_right = 0.0
			if state == "focus":
				style.set_border_width_all(1)
				style.border_color = INK
			button.add_theme_stylebox_override(state, style)
		button.disabled = i != 1
		add_child(button)
		tab_buttons[KEYS[i]] = button
	# Both old handles refer to one physical tab, and a click dispatches once.
	tab_buttons["health"] = tab_buttons["equipment"]
	(tab_buttons.equipment as Button).pressed.connect(func() -> void: equipment_requested.emit())
	close_button = Button.new()
	close_button.name = "CloseCharacterPage"
	close_button.text = "‹  뒤로가기"
	close_button.position = Vector2(1103, 12)
	close_button.size = Vector2(151, 40)
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.tooltip_text = "뒤로가기 · ESC"
	close_button.add_theme_font_size_override("font_size", 19)
	close_button.add_theme_color_override("font_color", INK)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.018, 0.012, 0.35)
		style.border_color = RULE if state == "normal" else INK
		if state != "normal":
			style.set_border_width_all(1)
		close_button.add_theme_stylebox_override(state, style)
	add_child(close_button)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	for i in METER_KEYS.size():
		var x := 35.0 + i * 147.0
		var title := _label(METER_TITLES[i], Vector2(x + 35, 621), Vector2(109, 27), 17, TEXT)
		title.name = "SurvivalTitle_" + METER_KEYS[i]
		var value := _label("", Vector2(x + 35, 648), Vector2(101, 21), 12, Color(0.63, 0.57, 0.47))
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		survival_value_labels[METER_KEYS[i]] = value
		var bar := ProgressBar.new()
		bar.name = "SurvivalMeter_" + METER_KEYS[i]
		bar.position = Vector2(x + 13, 676)
		bar.size = Vector2(METER_WIDTH, 9)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_PASS
		var under := StyleBoxFlat.new()
		under.bg_color = Color(0.035, 0.034, 0.029)
		under.content_margin_left = 0
		under.content_margin_top = 0
		under.content_margin_right = 0
		under.content_margin_bottom = 0
		bar.add_theme_stylebox_override("background", under)
		var fill := StyleBoxFlat.new()
		fill.bg_color = METER_COLORS[i]
		fill.border_color = METER_COLORS[i].lightened(0.15)
		fill.border_width_top = 1
		fill.border_width_bottom = 1
		fill.content_margin_left = 0
		fill.content_margin_top = 0
		fill.content_margin_right = 0
		fill.content_margin_bottom = 0
		bar.add_theme_stylebox_override("fill", fill)
		add_child(bar)
		survival_bars[METER_KEYS[i]] = bar
	queue_redraw()


func update_status(actor: Dictionary, survival: Dictionary) -> void:
	build()
	var maximum := maxf(1.0, float(survival.get("maximum", 100.0)))
	var amounts := {"hunger": float(survival.get("hunger", maximum)), "thirst": float(survival.get("thirst", maximum)), "stamina": float(actor.get("stamina", 100.0)), "stress": float(survival.get("stress", ExpeditionSession.stress))}
	for key in METER_KEYS:
		var cap := maxf(1.0, float(actor.get("max_stamina", 100.0))) if key == "stamina" else maximum
		var amount := clampf(float(amounts[key]), 0.0, cap)
		var bar: ProgressBar = survival_bars[key]
		bar.max_value = cap
		bar.value = amount
		# Reapply after theme minimums settle so the actual bar stays thin.
		bar.size = Vector2(METER_WIDTH, 9)
		(survival_value_labels[key] as Label).text = "%d / %d" % [roundi(amount), roundi(cap)]
		bar.tooltip_text = {"hunger": "포만감 · 높을수록 배가 든든합니다", "thirst": "수분 · 높을수록 갈증이 적습니다", "stamina": "기력 · 공격과 이동에 사용하는 힘", "stress": "스트레스 · 높을수록 불안정합니다"}[key]


func _label(text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = extent
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", theme.default_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.015, 0.014, 0.011))
	if background_texture != null:
		var dimensions := background_texture.get_size()
		var factor := maxf(1280.0 / dimensions.x, 720.0 / dimensions.y)
		var extent := dimensions * factor
		draw_texture_rect(background_texture, Rect2(Vector2(640, 360) - extent * 0.5, extent), false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 86109
	for i in 900:
		var at := Vector2(rng.randf_range(13, 1267), rng.randf_range(9, 704))
		draw_line(at, at + Vector2(rng.randf_range(1, 4), 0), Color(0.23, 0.21, 0.16, 0.025), 1)
	draw_rect(Rect2(12, 8, 1256, 697), RULE, false, 1.0)
	draw_rect(Rect2(16, 12, 1248, 689), Color(0.16, 0.135, 0.095), false, 1.0)
	draw_rect(Rect2(17, 13, 1246, 44), Color(0.012, 0.011, 0.008, 0.80))
	draw_line(Vector2(16, 59), Vector2(1264, 59), RULE, 1.0)
	draw_line(Vector2(20, 62), Vector2(1260, 62), Color(0.18, 0.15, 0.105), 1.0)
	# This layer provides only the outer boundary of the equipment area.
	draw_rect(Rect2(644, 67, 614, 631), Color(0.32, 0.27, 0.19), false, 1.0)
	draw_line(Vector2(639, 67), Vector2(639, 699), Color(0.20, 0.17, 0.12), 1.0)
	draw_rect(Rect2(25, 608, 609, 89), Color(0.009, 0.009, 0.007, 0.82))
	draw_line(Vector2(25, 605), Vector2(634, 605), RULE, 1.0)
	draw_line(Vector2(29, 608), Vector2(630, 608), Color(0.18, 0.15, 0.105), 1.0)
	for i in KEYS.size():
		var rect: Rect2 = TAB_RECTS[i]
		if i > 0:
			draw_line(Vector2(rect.position.x - 1, 14), Vector2(rect.position.x - 1, 54), RULE, 1.0)
		_draw_icon(KEYS[i], Vector2(rect.position.x + 27, 32), 0.61, INK)
	for point in [Vector2(12, 8), Vector2(1268, 8), Vector2(12, 705), Vector2(1268, 705), Vector2(330, 605)]:
		_flourish(point, 0.65)
	for side in [12.0, 1268.0]:
		for y in [66.0, 274.0, 485.0, 686.0]:
			_flourish(Vector2(side, y), 0.42)
	for i in METER_KEYS.size():
		var x := 35.0 + i * 147.0
		if i > 0:
			draw_line(Vector2(x - 6, 621), Vector2(x - 6, 687), Color(0.24, 0.20, 0.14), 1.0)
		_draw_icon(["stomach", "drop", "moon", "star"][i], Vector2(x + 16, 639), 0.67, METER_COLORS[i].lightened(0.12))
		_path([Vector2(0, 6), Vector2(4, 0), Vector2(128, 0), Vector2(132, 6), Vector2(128, 13), Vector2(4, 13), Vector2(0, 6)], Vector2(x + 7, 674), 1.0, RULE)


func _flourish(center: Vector2, scale_value: float) -> void:
	_path([Vector2(0, -16), Vector2(4, -5), Vector2(14, 0), Vector2(4, 5), Vector2(0, 16), Vector2(-4, 5), Vector2(-14, 0), Vector2(-4, -5), Vector2(0, -16)], center, scale_value, RULE)
	_path([Vector2(0, -7), Vector2(6, 0), Vector2(0, 7), Vector2(-6, 0), Vector2(0, -7)], center, scale_value, INK.darkened(0.27))
	for side in [-1.0, 1.0]:
		_path([Vector2(4 * side, -11), Vector2(9 * side, -8), Vector2(7 * side, -3), Vector2(17 * side, 0), Vector2(7 * side, 3), Vector2(9 * side, 8), Vector2(4 * side, 11)], center, scale_value, RULE)


func _path(points: Array, origin: Vector2, scale_value: float, color: Color, width := 1.0) -> void:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		result.append(origin + point * scale_value)
	draw_polyline(result, color, width, true)


func _draw_icon(kind: String, center: Vector2, scale_value: float, color: Color) -> void:
	match kind:
		"overview":
			_path([Vector2(-12, -11), Vector2(-10, -17), Vector2(10, -17), Vector2(12, -11), Vector2(14, 16), Vector2(-14, 16), Vector2(-12, -11)], center, scale_value, color)
			_path([Vector2(-11, -10), Vector2(0, -6), Vector2(11, -10), Vector2(8, -1), Vector2(-8, -1), Vector2(-11, -10)], center, scale_value, color)
			for x in [-8.0, 3.0]:
				_path([Vector2(x, 3), Vector2(x + 5, 3), Vector2(x + 5, 13), Vector2(x, 13), Vector2(x, 3)], center, scale_value, color)
		"equipment":
			_path([Vector2(-15, 15), Vector2(-13, -3), Vector2(-8, -14), Vector2(0, -20), Vector2(8, -14), Vector2(13, -3), Vector2(15, 15), Vector2(6, 10), Vector2(5, -1), Vector2(-5, -1), Vector2(-6, 10), Vector2(-15, 15)], center, scale_value, color)
			_path([Vector2(-13, -3), Vector2(0, -7), Vector2(13, -3), Vector2(0, 0), Vector2(0, 17)], center, scale_value, color)
			_path([Vector2(0, -18), Vector2(0, -8)], center, scale_value, color)
		"health", "map", "star":
			var points: Array = []
			for i in 16:
				var length := (21.0 if i % 4 == 0 else 13.0) if i % 2 == 0 else 5.0
				points.append(Vector2(cos(i * PI / 8), sin(i * PI / 8)) * length)
			points.append(points[0])
			_path(points, center, scale_value, color)
			draw_circle(center, 3.0 * scale_value, color, false, 1.0, true)
			if kind == "health":
				_flourish(center, 0.8 * scale_value)
		"skills":
			_path([Vector2(0, -13), Vector2(-8, -17), Vector2(-18, -17), Vector2(-18, 14), Vector2(-8, 14), Vector2(0, 18), Vector2(8, 14), Vector2(18, 14), Vector2(18, -17), Vector2(8, -17), Vector2(0, -13), Vector2(0, 18)], center, scale_value, color)
			for y in [-10.0, -4.0, 2.0, 8.0]:
				_path([Vector2(-14, y), Vector2(-9, y), Vector2(-4, y + 2)], center, scale_value, color)
				_path([Vector2(14, y), Vector2(9, y), Vector2(4, y + 2)], center, scale_value, color)
		"quests":
			_path([Vector2(-12, -17), Vector2(12, -17), Vector2(12, 17), Vector2(-12, 17), Vector2(-12, -17)], center, scale_value, color)
			_path([Vector2(-7, -20), Vector2(7, -20), Vector2(7, -13), Vector2(-7, -13), Vector2(-7, -20)], center, scale_value, color)
			draw_circle(center + Vector2(0, -4) * scale_value, 4 * scale_value, color, false, 1.0, true)
			for y in [5.0, 10.0]:
				_path([Vector2(-7, y), Vector2(7, y)], center, scale_value, color)
		"drop":
			var shape := PackedVector2Array()
			for p in [Vector2(0,-24),Vector2(-13,2),Vector2(-14,10),Vector2(-8,17),Vector2(0,20),Vector2(8,17),Vector2(14,10),Vector2(13,2)]:
				shape.append(center + p * scale_value)
			draw_colored_polygon(shape, color.darkened(0.25))
			_path([Vector2(-7, 1), Vector2(-8, 9), Vector2(-4, 13)], center, scale_value, color.lightened(0.2), 1.4)
		"moon":
			draw_circle(center, 17 * scale_value, color.darkened(0.12), true, -1, true)
			draw_circle(center + Vector2(9, -6) * scale_value, 16 * scale_value, Color(0.012,0.011,0.009), true, -1, true)
		"stomach":
			var points := [Vector2(-6,-20),Vector2(-3,-9),Vector2(6,-6),Vector2(13,3),Vector2(12,13),Vector2(6,19),Vector2(-6,20),Vector2(-15,14),Vector2(-13,10),Vector2(-6,13),Vector2(0,9),Vector2(1,1),Vector2(-8,-4),Vector2(-12,-13),Vector2(-12,-20)]
			var shape := PackedVector2Array()
			for p: Vector2 in points:
				shape.append(center + p * scale_value)
			draw_colored_polygon(shape, color.darkened(0.08))
