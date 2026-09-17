extends Button
## A quiet engraved plate: its live values and bar are regular child Controls.

const ICON_SHEET := preload("res://assets/ui/health_armor_icons.svg")
const ICON_COLUMNS := {"head": 0, "thorax": 1, "stomach": 2, "right_arm": 3, "left_arm": 3, "right_leg": 4, "left_leg": 4}
const BRONZE := Color(0.48, 0.40, 0.28, 0.85)
const PALE_BRONZE := Color(0.71, 0.61, 0.44, 0.90)

var part_id := "head"
var selected := false
var blacked := false


func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var edge := PALE_BRONZE if selected or is_hovered() else BRONZE
	var fill := Color(0.018, 0.014, 0.011, 0.85)
	if is_hovered():
		fill = Color(0.08, 0.035, 0.021, 0.88)
	if blacked:
		fill = Color(0.003, 0.003, 0.003, 0.93)
	var width := size.x
	var bottom := 53.0
	draw_colored_polygon(PackedVector2Array([Vector2(0, 1), Vector2(width - 22, 1), Vector2(width, 11), Vector2(width, bottom), Vector2(8, bottom), Vector2(0, bottom - 9)]), fill)
	draw_line(Vector2(0, 0), Vector2(width - 34, 0), edge, 1.0, true)
	draw_line(Vector2(width - 34, 0), Vector2(width - 8, 0), Color(edge, edge.a * 0.30), 1.0, true)
	draw_line(Vector2(0, bottom), Vector2(width, bottom), edge, 1.0, true)
	draw_line(Vector2(32, 29), Vector2(width, 29), Color(edge, edge.a * 0.55), 1.0, true)
	draw_line(Vector2(2, bottom - 2), Vector2(width, bottom - 2), Color(0.02, 0.018, 0.015, 0.8), 1.0)
	if selected:
		draw_polyline(PackedVector2Array([Vector2(1, 12), Vector2(1, 1), Vector2(12, 1)]), edge, 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(width - 12, bottom - 1), Vector2(width - 1, bottom - 1), Vector2(width - 1, bottom - 12)]), edge, 1.0, true)
		draw_polyline(PackedVector2Array([Vector2(width + 3, 22), Vector2(width + 6, 26), Vector2(width + 3, 30), Vector2(width, 26), Vector2(width + 3, 22)]), edge, 1.0, true)
	var icon_modulate := Color(0.95, 0.89, 0.78, 0.90) if not blacked else Color(0.58, 0.52, 0.44, 0.90)
	draw_texture_rect_region(ICON_SHEET, Rect2(1, 5, 28, 40), Rect2(int(ICON_COLUMNS.get(part_id, 0)) * 40, 0, 40, 56), icon_modulate)
