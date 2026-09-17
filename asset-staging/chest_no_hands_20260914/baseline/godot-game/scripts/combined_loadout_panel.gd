extends Control
## Read-only presentation of the existing bag and equipment. The inventory
## overlay owns all selection, equipment and consumable transactions.

signal inventory_pressed(index: int)
signal inventory_gui_input(event: InputEvent, index: int)
signal equipment_pressed(slot: String)
signal equipment_gui_input(event: InputEvent, slot: String)
signal quick_use_requested(item_id: String)

const FONT := preload("res://assets/fonts/NotoSerifKR-Variable.ttf")
const NUMBER_FONT := preload("res://assets/fonts/Cinzel-Variable.ttf")
const INPUT_RECT := Rect2(644, 65, 611, 630)
const EQUIPMENT_ORDER := ["head", "body", "weapon", "offhand", "utility"]
const EQUIPMENT_NAMES := {"head": "머리", "body": "흉부", "weapon": "무기", "offhand": "보조 장비", "utility": "도구"}
const EQUIPMENT_RECTS := {
	"head": Rect2(658, 108, 67, 80),
	"body": Rect2(733, 108, 127, 181),
	"weapon": Rect2(658, 196, 67, 191),
	"offhand": Rect2(733, 297, 60, 90),
	"utility": Rect2(801, 297, 59, 90),
}
const SECTIONS := [
	{"title": "장착 장비", "rect": Rect2(644, 65, 231, 345)},
	{"title": "주머니", "rect": Rect2(644, 417, 231, 158)},
	{"title": "허리 파우치", "rect": Rect2(885, 65, 370, 155)},
	{"title": "배낭", "rect": Rect2(885, 228, 370, 347)},
	{"title": "빠른 사용", "rect": Rect2(644, 585, 611, 110)},
]
const TEXT := Color(0.82, 0.75, 0.63)
const MUTED := Color(0.57, 0.52, 0.43)
const BRASS := Color(0.46, 0.38, 0.26)
const SELECTED_BRASS := Color(0.80, 0.64, 0.39)
const CELL_BACKGROUND := Color(0.018, 0.016, 0.013, 0.94)
const DEFAULT_STATUS := "우클릭: 상세 보기 · 장비 두 번 클릭: 해제"

var inventory_buttons: Array[Button] = []
var equipment_buttons: Dictionary = {}
var quick_use_buttons: Array[Button] = []
var quick_use_item_ids: Array[String] = []
var texture_provider := Callable()
var status_label: Label
var capacity_label: Label

var _built := false
var _cell_art: Dictionary = {}
var _cell_quantity: Dictionary = {}
var _cell_tag: Dictionary = {}
var _fallback_labels: Dictionary = {}
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat
var _section_style: StyleBoxFlat


func _ready() -> void:
	build()


func configure(provider: Callable) -> void:
	texture_provider = provider


func build() -> void:
	if _built:
		return
	_built = true
	name = "CombinedLoadoutPanel"
	size = Vector2(1280, 720)
	custom_minimum_size = Vector2(1280, 720)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var serif := FontVariation.new()
	serif.base_font = FONT
	serif.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	theme = Theme.new()
	theme.default_font = serif
	_normal_style = _style(CELL_BACKGROUND, Color(0.31, 0.28, 0.22), 1)
	_selected_style = _style(Color(0.09, 0.057, 0.030, 0.98), SELECTED_BRASS, 1)
	_section_style = _style(Color(0.015, 0.014, 0.012, 0.93), BRASS.darkened(0.16), 1)
	for section: Dictionary in SECTIONS:
		var rect: Rect2 = section.rect
		var heading := _label(self, str(section.title), rect.position + Vector2(14, 8), Vector2(rect.size.x - 28, 28), 20, TEXT)
		heading.name = "Heading_" + str(section.title)
	for slot: String in EQUIPMENT_ORDER:
		var button := _cell("Equipment_" + slot, EQUIPMENT_RECTS[slot], str(EQUIPMENT_NAMES[slot]))
		button.pressed.connect(_equipment_pressed.bind(slot))
		button.gui_input.connect(_equipment_input.bind(slot))
		button.set_meta("equipment_slot", slot)
		equipment_buttons[slot] = button
	for index in 30:
		var rect: Rect2
		if index < 8:
			rect = Rect2(Vector2(658 + (index % 4) * 51, 459 + (index / 4) * 51), Vector2(47, 47))
		elif index < 14:
			rect = Rect2(Vector2(899 + (index - 8) * 57, 111), Vector2(53, 91))
		else:
			var local_index := index - 14
			rect = Rect2(Vector2(899 + (local_index % 4) * 86, 274 + (local_index / 4) * 72), Vector2(81, 67))
		var button := _cell("Inventory_%02d" % index, rect)
		button.set_meta("inventory_index", index)
		button.pressed.connect(_inventory_pressed.bind(index))
		button.gui_input.connect(_inventory_input.bind(index))
		inventory_buttons.append(button)
	quick_use_item_ids.resize(10)
	quick_use_item_ids.fill("")
	for index in 10:
		var button := _cell("QuickUse_%d" % index, Rect2(658 + index * 59, 626, 55, 55))
		button.disabled = true
		button.pressed.connect(_quick_use_pressed.bind(index))
		var number := _label(button, str((index + 1) % 10), Vector2(3, 0), Vector2(15, 19), 12, TEXT)
		number.add_theme_font_override("font", NUMBER_FONT)
		number.name = "QuickUseNumber"
		number.z_index = 1
		quick_use_buttons.append(button)
	status_label = _label(self, DEFAULT_STATUS, Vector2(790, 597), Vector2(449, 19), 11, MUTED)
	status_label.name = "CombinedLoadoutStatus"
	status_label.tooltip_text = DEFAULT_STATUS
	capacity_label = _label(self, "", Vector2(1020, 238), Vector2(219, 23), 12, MUTED)
	capacity_label.name = "BagCapacityAndWeight"
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	queue_redraw()


func set_status(text_value: String) -> void:
	build()
	status_label.text = text_value if not text_value.is_empty() else DEFAULT_STATUS
	status_label.tooltip_text = status_label.text


func refresh(model: ExpeditionInventory, selected_source: String = "", selected_index: int = -1, selected_equipment_slot: String = "") -> void:
	build()
	capacity_label.text = "%d / 30칸 · %.1f kg" % [model.slots.size(), model.total_weight()] if model != null else "0 / 30칸 · 0.0 kg"
	capacity_label.tooltip_text = "주머니·허리 파우치·배낭 전체 수납량과 장착 장비를 포함한 실제 무게"
	for index in inventory_buttons.size():
		var stack: Dictionary = model.slots[index] if model != null and index < model.slots.size() else {}
		var item_id := str(stack.get("id", ""))
		var quantity := int(stack.get("quantity", 0))
		var instance: Dictionary = stack.get("instance", {})
		var tag := ExpeditionInventory.get_item_tag(instance)
		var button := inventory_buttons[index]
		button.disabled = model == null
		_set_cell(button, item_id, quantity, tag, selected_source == "inventory" and selected_index == index)
		if item_id.is_empty():
			button.tooltip_text = "빈 수납 칸"
	for slot: String in EQUIPMENT_ORDER:
		var item_id := str(model.equipment.get(slot, "")) if model != null else ""
		var instance: Dictionary = model.equipment_data.get(slot, {}) if model != null else {}
		var button: Button = equipment_buttons[slot]
		button.disabled = model == null
		_set_cell(button, item_id, 1 if not item_id.is_empty() else 0, ExpeditionInventory.get_item_tag(instance), selected_source == "equipment" and selected_equipment_slot == slot)
		if item_id.is_empty():
			button.tooltip_text = str(EQUIPMENT_NAMES[slot]) + " · 장착하지 않음"
	_refresh_quick_use(model)


func _refresh_quick_use(model: ExpeditionInventory) -> void:
	var ordered_ids: Array[String] = []
	var quantities: Dictionary = {}
	var tags: Dictionary = {}
	if model != null:
		for stack: Dictionary in model.slots:
			var item_id := str(stack.get("id", ""))
			var quantity := int(stack.get("quantity", 0))
			if quantity <= 0 or str(ExpeditionInventory.get_item_definition(item_id).get("category", "")) != "consumable":
				continue
			if item_id not in ordered_ids:
				ordered_ids.append(item_id)
			quantities[item_id] = int(quantities.get(item_id, 0)) + quantity
			var tag := ExpeditionInventory.get_item_tag(stack.get("instance", {}))
			var item_tags: Array = tags.get(item_id, [])
			if not tag.is_empty() and tag not in item_tags:
				item_tags.append(tag)
			tags[item_id] = item_tags
	for index in quick_use_buttons.size():
		var item_id := ordered_ids[index] if index < ordered_ids.size() else ""
		quick_use_item_ids[index] = item_id
		var button := quick_use_buttons[index]
		button.disabled = item_id.is_empty()
		var tag_text := " · ".join(tags.get(item_id, []))
		_set_cell(button, item_id, int(quantities.get(item_id, 0)), tag_text, false)
		if item_id.is_empty():
			button.tooltip_text = "빠른 사용 · 보유 치료품과 소모품이 표시됩니다"
		else:
			button.tooltip_text += "\n%s 키 · 빠른 사용" % str((index + 1) % 10)


func _cell(node_name: String, rect: Rect2, caption: String = "") -> Button:
	var button := Button.new()
	button.name = node_name
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", _normal_style)
	button.add_theme_stylebox_override("disabled", _normal_style)
	button.add_theme_stylebox_override("hover", _style(Color(0.065, 0.047, 0.030, 0.97), BRASS.lightened(0.15), 1))
	button.add_theme_stylebox_override("pressed", _selected_style)
	button.add_theme_stylebox_override("focus", _selected_style)
	add_child(button)
	var top_padding := 20.0 if not caption.is_empty() else 5.0
	if not caption.is_empty():
		var label := _label(button, caption, Vector2(4, 2), Vector2(rect.size.x - 8, 17), 10, MUTED)
		label.name = "EquipmentCaption"
	var art := TextureRect.new()
	art.name = "ItemIcon"
	art.position = Vector2(5, top_padding)
	art.size = Vector2(rect.size.x - 10, rect.size.y - top_padding - 5)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	_cell_art[button] = art
	var quantity := _label(button, "", Vector2(3, rect.size.y - 20), Vector2(rect.size.x - 7, 18), 12, TEXT)
	quantity.name = "ItemQuantity"
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity.add_theme_font_override("font", NUMBER_FONT)
	quantity.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	quantity.add_theme_constant_override("shadow_offset_x", 1)
	quantity.add_theme_constant_override("shadow_offset_y", 1)
	_cell_quantity[button] = quantity
	var tag_mark := _label(button, "◇", Vector2(rect.size.x - 15, 1), Vector2(13, 16), 12, SELECTED_BRASS)
	tag_mark.name = "ItemTagMark"
	tag_mark.hide()
	_cell_tag[button] = tag_mark
	var fallback := _label(button, "", Vector2(5, top_padding), art.size, 11, MUTED)
	fallback.name = "ItemNameFallback"
	fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_labels[button] = fallback
	return button


func _set_cell(button: Button, item_id: String, quantity: int, tag: String, selected: bool) -> void:
	var art: TextureRect = _cell_art[button]
	art.texture = null
	if not item_id.is_empty():
		if texture_provider.is_valid():
			art.texture = texture_provider.call(item_id) as Texture2D
		else:
			var icon_path := str(ExpeditionInventory.get_item_definition(item_id).get("icon_path", ""))
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path, "Texture2D"):
				art.texture = load(icon_path) as Texture2D
	var fallback: Label = _fallback_labels[button]
	fallback.text = ExpeditionInventory.get_item_name(item_id) if not item_id.is_empty() and art.texture == null else ""
	(_cell_quantity[button] as Label).text = "×%d" % quantity if quantity > 1 else ""
	(_cell_tag[button] as Label).visible = not tag.is_empty()
	button.set_meta("item_id", item_id)
	button.set_meta("quantity", quantity)
	button.set_meta("selected", selected)
	button.add_theme_stylebox_override("normal", _selected_style if selected else _normal_style)
	button.tooltip_text = "%s\n수량 %d" % [ExpeditionInventory.get_item_name(item_id), quantity] if not item_id.is_empty() else ""
	if not tag.is_empty():
		button.tooltip_text += "\n이름표 · " + tag


func _has_point(point: Vector2) -> bool:
	return INPUT_RECT.has_point(point)


func _inventory_pressed(index: int) -> void:
	inventory_pressed.emit(index)


func _inventory_input(event: InputEvent, index: int) -> void:
	inventory_gui_input.emit(event, index)


func _equipment_pressed(slot: String) -> void:
	equipment_pressed.emit(slot)


func _equipment_input(event: InputEvent, slot: String) -> void:
	equipment_gui_input.emit(event, slot)


func _quick_use_pressed(index: int) -> void:
	if index >= 0 and index < quick_use_item_ids.size() and not quick_use_item_ids[index].is_empty():
		quick_use_requested.emit(quick_use_item_ids[index])


func _draw() -> void:
	if not _built:
		return
	for section: Dictionary in SECTIONS:
		var rect: Rect2 = section.rect
		draw_style_box(_section_style, rect)
		draw_rect(rect.grow(-4), Color(0.25, 0.22, 0.17, 0.75), false, 1)
		draw_line(rect.position + Vector2(11, 37), Vector2(rect.end.x - 11, rect.position.y + 37), BRASS.darkened(0.38), 1)
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			var point: Vector2 = rect.position + rect.size * corner
			var direction := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
			draw_polyline(PackedVector2Array([point + Vector2(direction.x * 18, direction.y * 2), point + Vector2(direction.x * 8, direction.y * 2), point + Vector2(direction.x * 2, direction.y * 8), point + Vector2(direction.x * 2, direction.y * 18)]), BRASS, 1, true)
			var center := point + direction * 7
			draw_polyline(PackedVector2Array([center + Vector2(0, -3), center + Vector2(3, 0), center + Vector2(0, 3), center + Vector2(-3, 0), center + Vector2(0, -3)]), BRASS.darkened(0.10), 1, true)


func _label(parent: Node, text_value: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.size = extent
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label


func _style(background: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_content_margin_all(0)
	return style
