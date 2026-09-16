extends Control
## Dungeon-only presentation and shortcuts; inventory/player own transactions.
const FONT := preload("res://assets/fonts/NotoSerifKR-Variable.ttf")
const NUMBERS := preload("res://assets/fonts/Cinzel-Variable.ttf")
const KEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]
const DEFAULT_ITEMS := ["rusted_sword", "hunting_bow", "field_torch", "healing_draught", "linen_bandage", "pilgrim_ration", "boiled_rainwater", "antidote", "purifying_salt", "weathered_staff"]
const GOLD := Color(0.58, 0.48, 0.30)
const INK := Color(0.91, 0.84, 0.67)
const PART_SHAPES := {
 "head": [Vector2(49,4),Vector2(59,0),Vector2(70,4),Vector2(74,14),Vector2(71,28),Vector2(65,34),Vector2(65,41),Vector2(54,41),Vector2(54,33),Vector2(48,27),Vector2(45,14)],
 "thorax": [Vector2(53,38),Vector2(66,38),Vector2(78,43),Vector2(83,55),Vector2(77,85),Vector2(69,95),Vector2(50,95),Vector2(42,85),Vector2(36,55),Vector2(42,44)],
 "stomach": [Vector2(45,88),Vector2(74,88),Vector2(76,112),Vector2(81,132),Vector2(67,145),Vector2(60,134),Vector2(52,145),Vector2(38,132),Vector2(43,111)],
 "right_arm": [Vector2(39,45),Vector2(44,57),Vector2(35,87),Vector2(28,104),Vector2(25,128),Vector2(18,152),Vector2(10,158),Vector2(6,151),Vector2(12,130),Vector2(14,101),Vector2(22,84),Vector2(23,63),Vector2(29,49)],
 "left_arm": [Vector2(80,45),Vector2(90,49),Vector2(97,63),Vector2(97,84),Vector2(106,101),Vector2(107,130),Vector2(114,151),Vector2(110,158),Vector2(102,152),Vector2(94,128),Vector2(92,104),Vector2(85,87),Vector2(76,57)],
 "right_leg": [Vector2(39,133),Vector2(56,141),Vector2(57,164),Vector2(52,188),Vector2(51,210),Vector2(44,239),Vector2(45,250),Vector2(35,257),Vector2(20,256),Vector2(20,251),Vector2(31,241),Vector2(33,211),Vector2(32,190),Vector2(33,162)],
 "left_leg": [Vector2(64,141),Vector2(81,133),Vector2(87,162),Vector2(88,190),Vector2(87,211),Vector2(89,241),Vector2(100,251),Vector2(100,256),Vector2(85,257),Vector2(75,250),Vector2(76,239),Vector2(69,210),Vector2(68,188),Vector2(63,164)]
}
var player: DungeonPlayer
var bag: ExpeditionInventory
var texture_provider := Callable()
var item_ids: Array[String] = []
var textures: Dictionary = {}
var body_snapshot := {}
var warnings: Array[String] = []
var elapsed := 0.0
var meter_health := 1.0
var meter_stamina := 1.0
var selected_index := 0
var last_result := {}

func setup(actor: DungeonPlayer, inventory: ExpeditionInventory, provider: Callable) -> void:
 player = actor
 bag = inventory
 texture_provider = provider
 item_ids.assign(DEFAULT_ITEMS)
 var weapon := str(bag.equipment.get("weapon", ""))
 if not weapon.is_empty() and weapon not in item_ids:
  item_ids[0] = weapon
 for id in item_ids:
  textures[id] = texture_provider.call(id)
 refresh()

func _ready() -> void:
 mouse_filter = Control.MOUSE_FILTER_IGNORE
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _process(delta: float) -> void:
 elapsed += delta
 if elapsed >= 0.1:
  elapsed = 0.0
  refresh()

func refresh() -> void:
 if not is_instance_valid(player) or bag == null:
  return
 body_snapshot = player.get_body_health_snapshot()
 meter_health = float(body_snapshot.health) / maxf(1, float(body_snapshot.max_health))
 meter_stamina = player.stamina / player.MAX_STAMINA
 warnings.clear()
 if ExpeditionSession.hunger <= 25: warnings.append("hunger")
 if ExpeditionSession.thirst <= 25: warnings.append("thirst")
 if meter_stamina <= 0.25: warnings.append("fatigue")
 if ExpeditionSession.stress >= 60: warnings.append("dizziness")
 for id in ["bleeding", "fracture", "curse", "paralysis", "poison"]:
  if float(body_snapshot.get("conditions", {}).get(id, 0)) > 0:
   warnings.append(id)
 selected_index = -1
 for i in item_ids.size():
  if item_ids[i] == str(bag.equipment.get("weapon", "")): selected_index = i
 queue_redraw()

func handle_shortcut(event: InputEvent) -> bool:
 if not event is InputEventKey or not event.pressed or event.echo or event.alt_pressed or event.ctrl_pressed or event.meta_pressed:
  return false
 var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
 var index := KEYS.find(key)
 if index < 0: return false
 last_result = activate_slot(index)
 if is_instance_valid(player.hud):
  player.hud.show_event(str(last_result.get("message", "지금은 사용할 수 없습니다")), 1.1)
 return true

func activate_slot(index: int) -> Dictionary:
 if index < 0 or index >= item_ids.size() or not is_instance_valid(player):
  return {"accepted": false, "reason": "invalid"}
 if get_tree().paused or player.safe_zone_mode or player.camping or player.is_paralyzed() or player.current_trap != null or player.is_timed_interacting() or player.combat_state != DungeonPlayer.CombatState.READY or player.is_bandage_motion_active() or player.is_item_use_active():
  return {"accepted": false, "reason": "busy", "message": "행동을 마친 뒤 사용하세요"}
 var id := item_ids[index]
 var definition := ExpeditionInventory.get_item_definition(id)
 var equip_slot := str(definition.get("equip_slot", ""))
 var result := {"accepted": false, "reason": "missing", "message": "소지하지 않은 물품입니다"}
 if not equip_slot.is_empty():
  if str(bag.equipment.get(equip_slot, "")) == id:
   if id == "field_torch":
    player.toggle_torch()
   elif equip_slot == "weapon" and player._has_melee_weapon_equipped() and player._has_shield_equipped():
    player.request_primary_weapon()
   result = {"accepted": true, "message": ExpeditionInventory.get_item_name(id) + " 준비"}
  else:
   for i in bag.slots.size():
    if str(bag.slots[i].get("id", "")) == id:
     result = bag.equip_from_slot(i)
     result["message"] = ExpeditionInventory.get_item_name(id) + " 장착"
     break
 elif bag.count_item(id) > 0:
  result = player.begin_item_use(id, bag)
 refresh()
 return result

func _draw() -> void:
 if bag == null: return
 var factor := minf(size.x / 1280.0, size.y / 720.0)
 var origin := Vector2((size.x - 1280 * factor) * 0.5, size.y - 720 * factor)
 draw_set_transform(origin, 0, Vector2.ONE * factor)
 var start := Vector2(435, 18)
 for i in item_ids.size():
  var rect := Rect2(start + Vector2(i * 41, 0), Vector2(39, 47))
  var id := item_ids[i]
  var equipped := str(bag.equipment.get(str(ExpeditionInventory.get_item_definition(id).get("equip_slot", "")), "")) == id
  var count := bag.count_item(id) + (1 if equipped else 0)
  draw_rect(rect, Color(0.015, 0.014, 0.011, 0.85))
  draw_rect(rect, INK if i == selected_index else GOLD, false, 1.5 if i == selected_index else 1)
  draw_rect(rect.grow(-3), Color(GOLD, 0.25), false)
  var texture: Texture2D = textures.get(id)
  if texture != null:
   var available := rect.size - Vector2(10, 11)
   var extent := texture.get_size() * minf(available.x / texture.get_width(), available.y / texture.get_height())
   draw_texture_rect(texture, Rect2(rect.get_center() - extent * 0.5 + Vector2(0, 3), extent), false, Color(1,1,1,1 if count > 0 else 0.2))
  draw_string(NUMBERS, rect.position + Vector2(4,13), str((i+1)%10), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
  if count > 1: draw_string(NUMBERS, rect.end - Vector2(14,4), str(count), HORIZONTAL_ALIGNMENT_RIGHT, 12, 11, INK)
 # Actual total health and stamina. Seven independent regions color by damage.
 var base := Vector2(50,468)
 for part in PART_SHAPES:
  var info: Dictionary = body_snapshot.get("parts", {}).get(part, {})
  var ratio := float(info.get("health",1)) / maxf(1,float(info.get("max_health",1)))
  var tone := Color(0.32,0.76,0.31) if ratio > 0.65 else Color(0.88,0.64,0.2) if ratio > 0.3 else Color(0.83,0.18,0.12)
  if ratio <= 0: tone = Color(0.28,0.28,0.25)
  var points := PackedVector2Array()
  # Leave a visible gap between arm and torso outlines, including their glow.
  var arm_offset := Vector2(-18, 0) if part == "right_arm" else Vector2(18, 0) if part == "left_arm" else Vector2.ZERO
  for p in PART_SHAPES[part]: points.append(base + (p + arm_offset) * 0.84)
  draw_colored_polygon(points, Color(tone, 0.12))
  points.append(points[0])
  draw_polyline(points, Color(tone,0.16), 5, true)
  draw_polyline(points, tone, 1.2, true)
 # Subtle anatomical seams keep the human shape readable in shadow.
 for pair in [[Vector2(51,57),Vector2(68,57)],[Vector2(49,73),Vector2(70,73)],[Vector2(49,104),Vector2(71,104)],[Vector2(59,44),Vector2(59,124)]]:
  draw_line(base + pair[0]*0.84,base + pair[1]*0.84,Color(0.32,0.59,0.3,0.35),1,true)
 var meter := Rect2(23,475,8,211)
 draw_rect(meter,Color(0.018,0.018,0.013,0.9))
 draw_rect(Rect2(meter.position+Vector2(1,meter.size.y*(1-meter_health)),Vector2(6,meter.size.y*meter_health)),Color(0.70,0.08,0.09))
 draw_rect(meter,GOLD,false)
 draw_rect(Rect2(53,694,98,3),Color(0.08,0.08,0.05,0.8))
 draw_rect(Rect2(53,694,98*meter_stamina,3),Color(0.69,0.55,0.25))
 for i in warnings.size():
  var pos := Vector2(177+(i/5)*39,512+(i%5)*35)
  draw_rect(Rect2(pos,Vector2(28,28)),Color(0.018,0.016,0.012,0.9))
  draw_rect(Rect2(pos,Vector2(28,28)),GOLD,false)
  _warning_icon(warnings[i],pos+Vector2(14,14))
 var hints := [["B / I","소지품"],["L / F","횃불"],["C","야영"],["Esc","일시정지"]]
 for i in hints.size():
  var pos := Vector2(1142,544+i*36)
  draw_rect(Rect2(pos,Vector2(43,28)),Color(0.012,0.011,0.009,0.7))
  draw_rect(Rect2(pos,Vector2(43,28)),GOLD,false)
  draw_string(NUMBERS,pos+Vector2(4,19),hints[i][0],HORIZONTAL_ALIGNMENT_CENTER,35,12,INK)
  draw_string(FONT,pos+Vector2(53,20),hints[i][1],HORIZONTAL_ALIGNMENT_LEFT,-1,14,INK)
 if not player.is_item_use_active() and not get_tree().paused and not (is_instance_valid(player.hud) and player.hud.bow_spread_reticle.visible):
  var c := Vector2(640,360)
  for d in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
   draw_line(c+d*17,c+d*32,Color(0,0,0,0.65),3,true)
   draw_line(c+d*17,c+d*32,Color(0.93,0.92,0.85),1.3,true)

func _warning_icon(id: String, p: Vector2) -> void:
 var color := Color(0.85,0.24,0.21)
 match id:
  "thirst", "bleeding", "poison":
   color = Color(0.24,0.64,0.89) if id == "thirst" else Color(0.54,0.75,0.24) if id == "poison" else color
   draw_colored_polygon(PackedVector2Array([p+Vector2(0,-10),p+Vector2(-7,2),p+Vector2(-6,7),p+Vector2(0,10),p+Vector2(6,7),p+Vector2(7,2)]),color)
  "fatigue":
   draw_circle(p,10,Color(0.60,0.47,0.78))
   draw_circle(p+Vector2(5,-4),9,Color(0.018,0.016,0.012))
  "hunger":
   draw_line(p+Vector2(3,-11),p+Vector2(3,-3),color,3,true)
   draw_circle(p+Vector2(2,2),8,color)
   draw_circle(p+Vector2(-4,7),4,color)
  "dizziness":
   var line := PackedVector2Array()
   for i in 40:
    var t := i*0.24
    line.append(p+Vector2(cos(t),sin(t))*float(i)*0.25)
   draw_polyline(line,Color(0.77,0.61,0.91),2,true)
  "curse":
   for i in 5:
    var a := -PI/2+i*TAU/5
    var b := a+2*TAU/5
    draw_line(p+Vector2(cos(a),sin(a))*10,p+Vector2(cos(b),sin(b))*10,Color(0.65,0.4,0.85),1.5,true)
  "fracture":
   draw_polyline(PackedVector2Array([p+Vector2(-7,-10),p+Vector2(2,-2),p+Vector2(-3,2),p+Vector2(7,10)]),INK,3,true)
  "paralysis":
   draw_polyline(PackedVector2Array([p+Vector2(5,-11),p+Vector2(-4,0),p+Vector2(4,0),p+Vector2(-5,11)]),Color(0.88,0.76,0.3),3,true)
