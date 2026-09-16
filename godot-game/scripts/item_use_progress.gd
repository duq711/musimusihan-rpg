extends Control
const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
var snapshot: Dictionary = {}
func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 hide()
func update_state(state: Dictionary) -> void:
 snapshot = state
 visible = not state.is_empty()
 queue_redraw()
func _draw() -> void:
 if snapshot.is_empty(): return
 var center := size * 0.5
 var scale_factor := clampf(size.y / 720.0, 0.75, 1.5)
 draw_set_transform(center, 0, Vector2.ONE * scale_factor)
 var left := maxf(0.0, float(snapshot.get("remaining", 0)))
 var total := maxf(0.01, float(snapshot.get("duration", 1)))
 draw_circle(Vector2.ZERO, 29, Color(0.012,0.012,0.012,0.7))
 draw_arc(Vector2.ZERO,28,0,TAU,64,Color(0.3,0.3,0.28,0.8),3,true)
 draw_arc(Vector2.ZERO,28,-PI/2,-PI/2+TAU*(1-left/total),64,Color(0.95,0.92,0.82),3,true)
 draw_string(FONT,Vector2(-25,8),"%.1f" % left,HORIZONTAL_ALIGNMENT_CENTER,50,22,Color.WHITE)
 draw_style_box(_background(),Rect2(-156,40,312,55))
 draw_string(FONT,Vector2(-150,61),str(snapshot.get("name","아이템"))+" 사용 중",HORIZONTAL_ALIGNMENT_CENTER,300,15,Color(0.94,0.9,0.81))
 draw_string(FONT,Vector2(-100,84),"[ F ]  취소",HORIZONTAL_ALIGNMENT_CENTER,200,14,Color(0.85,0.82,0.72))
func _background() -> StyleBoxFlat:
 var box := StyleBoxFlat.new()
 box.bg_color = Color(0.012,0.012,0.012,0.72)
 box.set_corner_radius_all(3)
 return box
