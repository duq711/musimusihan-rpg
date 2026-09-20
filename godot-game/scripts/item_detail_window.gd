extends Control
class_name ItemDetailWindow

signal closed
signal tag_requested(text: String)
signal discard_requested(quantity: int)
signal equip_requested
signal deploy_requested

const WINDOW_SIZE := Vector2(620.0, 610.0)
const UI_FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const COLOR_PANEL := Color(0.018, 0.019, 0.018, 1.0)
const COLOR_INNER := Color(0.008, 0.010, 0.009, 1.0)
const COLOR_BORDER := Color(0.28, 0.29, 0.27, 1.0)
const COLOR_TEXT := Color(0.85, 0.84, 0.78, 1.0)
const COLOR_MUTED := Color(0.57, 0.58, 0.53, 1.0)
const COLOR_ACCENT := Color(0.70, 0.65, 0.45, 1.0)
const CATEGORY_LABELS := {
	"equipment": "장비", "ammunition": "탄약", "consumable": "소비품",
	"supply": "재료", "treasure": "전리품", "key": "열쇠"
}

# These controls are public for the inventory integration and its UI tests.
var window_root: Panel
var title_label: Label
var category_label: Label
var weight_label: Label
var item_art: TextureRect
var tag_label: Label
var summary_label: Label
var stats_label: Label
var description_label: Label
var smithing_label: Label
var status_label: Label
var content_scroll: ScrollContainer
var close_button: Button
var tag_button: Button
var discard_button: Button
var equip_button: Button
var deploy_button: Button
var tag_editor: Panel
var tag_edit: LineEdit
var tag_save_button: Button
var tag_cancel_button: Button
var discard_editor: Panel
var discard_quantity: SpinBox
var discard_confirm_button: Button
var discard_cancel_button: Button

var _built := false
var _owned := false
var _equipped := false
var _quantity := 0
var _instance: Dictionary = {}
var _fallback_glyph: Label
var _tag_plate: Panel


func _ready() -> void:
	_ensure_built()
	_layout_window()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _built:
		_layout_window()


func present(item_id: String, quantity: int, instance: Dictionary, texture: Texture2D, owned: bool, equipped: bool) -> void:
	_ensure_built()
	_owned = owned
	_equipped = equipped
	_quantity = maxi(1, quantity)
	_instance = instance.duplicate(true)
	_cancel_editor()
	var definition := ExpeditionInventory.get_item_definition(item_id)
	var item_name := str(definition.get("name", item_id))
	var equipment_slot := str(definition.get("equip_slot", ""))
	var category := str(CATEGORY_LABELS.get(str(definition.get("category", "")), "물품"))
	var unit_weight := float(definition.get("weight", 0.0))
	title_label.text = item_name
	title_label.tooltip_text = item_name
	category_label.text = category
	if not equipment_slot.is_empty():
		category_label.text += "  /  %s" % str(ExpeditionInventory.EQUIPMENT_LABELS.get(equipment_slot, equipment_slot))
	weight_label.text = "%.3f kg" % unit_weight
	weight_label.tooltip_text = "개당 무게"
	item_art.texture = texture
	_fallback_glyph.visible = texture == null
	_fallback_glyph.text = str(definition.get("glyph", "?"))
	var item_tag := str(instance.get("item_tag", ""))
	tag_label.text = item_tag
	_tag_plate.visible = not item_tag.is_empty()
	tag_edit.text = item_tag
	summary_label.text = str(definition.get("summary", ""))
	summary_label.visible = not summary_label.text.is_empty()
	stats_label.text = "수량  %d개     |     총 무게  %.3f kg" % [_quantity, unit_weight * _quantity]
	description_label.text = str(definition.get("description", ""))
	smithing_label.text = ExpeditionInventory.smithing_description(instance)
	smithing_label.visible = not smithing_label.text.is_empty()
	if smithing_label.visible:
		var stats := ExpeditionInventory.smithing_stats(item_id, instance)
		summary_label.text = "경공격 피해 %.1f  ·  강공격 피해 %.1f  ·  기력 소모 ×%.2f" % [float(stats.get("light_damage", 0.0)), float(stats.get("heavy_damage", 0.0)), float(stats.get("stamina_scale", 1.0))]
		summary_label.visible = true
	tag_button.disabled = not owned
	discard_button.disabled = not owned
	equip_button.visible = not equipment_slot.is_empty()
	equip_button.disabled = not owned or equipped
	equip_button.text = "장착 중" if equipped else "장착하기"
	deploy_button.visible = item_id == "camp_kit"
	deploy_button.disabled = not owned
	_layout_action_buttons()
	discard_quantity.max_value = _quantity
	discard_quantity.value = 1
	status_label.text = "" if owned else "가방으로 옮기면 이름표와 장비를 관리할 수 있습니다."
	content_scroll.scroll_vertical = 0
	visible = true
	_layout_window()


func dismiss() -> void:
	if not _built:
		return
	_cancel_editor()
	visible = false


func is_open() -> bool:
	return _built and visible


func handle_cancel() -> bool:
	if not is_open():
		return false
	if tag_editor.visible or discard_editor.visible:
		_cancel_editor()
	else:
		_close_requested()
	return true


func set_status(message: String) -> void:
	_ensure_built()
	status_label.text = message


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	name = "ItemDetailWindow"
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	var readable_font := FontVariation.new()
	readable_font.base_font = UI_FONT
	readable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500}
	theme.default_font = readable_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var backdrop := ColorRect.new()
	backdrop.name = "DetailBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)
	window_root = _panel(self, "DetailPanel", Vector2.ZERO, WINDOW_SIZE, COLOR_PANEL)
	var header := _panel(window_root, "TitleBar", Vector2.ONE, Vector2(618, 40), Color(0.095, 0.102, 0.091), false)
	title_label = _label(header, "ItemName", Vector2(14, 7), Vector2(541, 26), 19, COLOR_TEXT)
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	close_button = _button(header, "Close", "×", Vector2(574, 3), Vector2(39, 33))
	close_button.add_theme_font_size_override("font_size", 25)
	close_button.tooltip_text = "상세 설명 닫기"
	close_button.pressed.connect(_close_requested)
	category_label = _label(window_root, "Category", Vector2(17, 45), Vector2(410, 20), 14, COLOR_MUTED)
	weight_label = _label(window_root, "Weight", Vector2(443, 45), Vector2(158, 20), 14, COLOR_TEXT)
	weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var art_panel := _panel(window_root, "ItemPreview", Vector2(1, 71), Vector2(618, 250), COLOR_INNER, false)
	item_art = TextureRect.new()
	item_art.name = "ItemArtwork"
	item_art.position = Vector2(18, 8)
	item_art.size = Vector2(582, 234)
	item_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_panel.add_child(item_art)
	_fallback_glyph = _label(art_panel, "ItemGlyph", Vector2(18, 8), Vector2(582, 234), 110, COLOR_ACCENT)
	_fallback_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tag_plate = _panel(art_panel, "NameTagPlate", Vector2(18, 218), Vector2(582, 26), Color(0.07, 0.075, 0.052, 0.96), false)
	tag_label = _label(_tag_plate, "NameTag", Vector2(9, 2), Vector2(564, 22), 15, COLOR_ACCENT)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var actions := _panel(window_root, "Actions", Vector2(1, 322), Vector2(618, 44), Color(0.057, 0.062, 0.053), false)
	equip_button = _button(actions, "Equip", "장착하기", Vector2(12, 6), Vector2(193, 32))
	deploy_button = _button(actions, "Install", "설치", Vector2(12, 6), Vector2(193, 32))
	deploy_button.visible = false
	deploy_button.pressed.connect(func() -> void:
		if _owned and deploy_button.visible: deploy_requested.emit())
	tag_button = _button(actions, "Tag", "이름표", Vector2(213, 6), Vector2(193, 32))
	discard_button = _button(actions, "Discard", "버리기", Vector2(414, 6), Vector2(192, 32))
	equip_button.pressed.connect(_equip_requested)
	tag_button.pressed.connect(_open_tag_editor)
	discard_button.pressed.connect(_open_discard_editor)
	_build_editors()
	content_scroll = ScrollContainer.new()
	content_scroll.name = "DescriptionScroll"
	content_scroll.position = Vector2(17, 377)
	content_scroll.size = Vector2(586, 201)
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	window_root.add_child(content_scroll)
	var content := VBoxContainer.new()
	content.name = "DescriptionContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	content_scroll.add_child(content)
	summary_label = _content_label(content, "Summary", 17, COLOR_ACCENT)
	stats_label = _content_label(content, "ItemFacts", 14, COLOR_MUTED)
	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _style(Color(0.24, 0.25, 0.22), false))
	divider.custom_minimum_size.y = 1
	content.add_child(divider)
	description_label = _content_label(content, "Description", 16, COLOR_TEXT)
	smithing_label = _content_label(content, "SmithingDetails", 16, COLOR_ACCENT)
	status_label = _label(window_root, "Status", Vector2(17, 584), Vector2(586, 18), 13, COLOR_MUTED)
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_layout_window()


func _build_editors() -> void:
	tag_editor = _panel(window_root, "TagEditor", Vector2(17, 375), Vector2(586, 74), Color(0.04, 0.045, 0.035))
	_label(tag_editor, "TagHint", Vector2(10, 5), Vector2(563, 20), 14, COLOR_MUTED).text = "이름표 · 24자까지 입력 / 비워서 저장하면 제거됩니다."
	tag_edit = LineEdit.new()
	tag_edit.name = "TagText"
	tag_edit.position = Vector2(10, 32)
	tag_edit.size = Vector2(379, 32)
	tag_edit.max_length = 24
	tag_edit.placeholder_text = "물품에 붙일 이름"
	tag_edit.add_theme_font_size_override("font_size", 16)
	tag_edit.add_theme_color_override("font_color", COLOR_TEXT)
	tag_edit.add_theme_stylebox_override("normal", _style(COLOR_INNER, true))
	tag_edit.add_theme_stylebox_override("focus", _style(Color(0.07, 0.075, 0.056), true, COLOR_ACCENT))
	tag_edit.text_submitted.connect(func(_text: String) -> void: _save_tag())
	tag_editor.add_child(tag_edit)
	tag_save_button = _button(tag_editor, "SaveTag", "저장", Vector2(397, 32), Vector2(82, 32))
	tag_cancel_button = _button(tag_editor, "CancelTag", "취소", Vector2(487, 32), Vector2(88, 32))
	tag_save_button.pressed.connect(_save_tag)
	tag_cancel_button.pressed.connect(_cancel_editor)
	tag_editor.visible = false
	discard_editor = _panel(window_root, "DiscardEditor", Vector2(17, 375), Vector2(586, 74), Color(0.055, 0.039, 0.029))
	_label(discard_editor, "DiscardHint", Vector2(10, 5), Vector2(563, 20), 14, COLOR_MUTED).text = "근처 바닥에 놓습니다. 이 장소를 떠나면 사라집니다."
	discard_quantity = SpinBox.new()
	discard_quantity.name = "DiscardQuantity"
	discard_quantity.position = Vector2(10, 32)
	discard_quantity.size = Vector2(169, 32)
	discard_quantity.min_value = 1
	discard_quantity.step = 1
	discard_quantity.rounded = true
	discard_quantity.suffix = "개"
	discard_quantity.add_theme_font_size_override("font_size", 16)
	discard_quantity.get_line_edit().add_theme_font_size_override("font_size", 16)
	discard_editor.add_child(discard_quantity)
	discard_confirm_button = _button(discard_editor, "ConfirmDiscard", "버리기", Vector2(397, 32), Vector2(82, 32))
	discard_cancel_button = _button(discard_editor, "CancelDiscard", "취소", Vector2(487, 32), Vector2(88, 32))
	discard_confirm_button.pressed.connect(_confirm_discard)
	discard_cancel_button.pressed.connect(_cancel_editor)
	discard_editor.visible = false


func _layout_window() -> void:
	if window_root == null:
		return
	var available := size
	if available.x <= 0.0 or available.y <= 0.0:
		available = get_viewport_rect().size
	var fit := minf(1.0, minf(maxf(1.0, available.x - 24.0) / WINDOW_SIZE.x, maxf(1.0, available.y - 24.0) / WINDOW_SIZE.y))
	window_root.scale = Vector2.ONE * fit
	window_root.position = (available - WINDOW_SIZE * fit) * 0.5


func _layout_action_buttons() -> void:
	if equip_button.visible or deploy_button.visible:
		tag_button.position.x = 213
		tag_button.size.x = 193
		discard_button.position.x = 414
		discard_button.size.x = 192
	else:
		tag_button.position.x = 12
		tag_button.size.x = 293
		discard_button.position.x = 313
		discard_button.size.x = 293


func _open_tag_editor() -> void:
	if not _owned:
		return
	_cancel_editor()
	tag_edit.text = str(_instance.get("item_tag", ""))
	tag_editor.visible = true
	_layout_content(true)


func _open_discard_editor() -> void:
	if not _owned:
		return
	_cancel_editor()
	discard_quantity.max_value = _quantity
	discard_quantity.value = 1
	discard_editor.visible = true
	_layout_content(true)


func _cancel_editor() -> void:
	if tag_editor != null:
		tag_editor.visible = false
	if discard_editor != null:
		discard_editor.visible = false
	_layout_content(false)


func _layout_content(editor_open: bool) -> void:
	if content_scroll == null:
		return
	content_scroll.position.y = 459 if editor_open else 377
	content_scroll.size.y = 119 if editor_open else 201


func _save_tag() -> void:
	if not _owned or not tag_editor.visible:
		return
	var value := tag_edit.text.strip_edges().left(24)
	_cancel_editor()
	tag_requested.emit(value)


func _confirm_discard() -> void:
	if not _owned or not discard_editor.visible:
		return
	discard_quantity.apply()
	var amount := clampi(roundi(discard_quantity.value), 1, _quantity)
	_cancel_editor()
	discard_requested.emit(amount)


func _equip_requested() -> void:
	if not _owned or _equipped or not equip_button.visible:
		return
	_cancel_editor()
	equip_requested.emit()


func _close_requested() -> void:
	dismiss()
	closed.emit()


func _panel(parent: Node, node_name: String, at: Vector2, extent: Vector2, color: Color, border: bool = true) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = at
	panel.size = extent
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", _style(color, border))
	parent.add_child(panel)
	return panel


func _label(parent: Node, node_name: String, at: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.name = node_name
	label.position = at
	label.size = extent
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _content_label(parent: Node, node_name: String, font_size: int, color: Color) -> Label:
	var label := _label(parent, node_name, Vector2.ZERO, Vector2.ZERO, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_constant_override("line_spacing", 5)
	return label


func _button(parent: Node, node_name: String, text_value: String, at: Vector2, extent: Vector2) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = at
	button.size = extent
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.97, 0.95, 0.84))
	button.add_theme_color_override("font_disabled_color", Color(0.39, 0.41, 0.36))
	button.add_theme_stylebox_override("normal", _style(Color(0.12, 0.13, 0.105), true))
	button.add_theme_stylebox_override("hover", _style(Color(0.22, 0.23, 0.17), true, COLOR_ACCENT))
	button.add_theme_stylebox_override("pressed", _style(Color(0.28, 0.29, 0.21), true, COLOR_ACCENT))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, true, COLOR_ACCENT))
	button.add_theme_stylebox_override("disabled", _style(Color(0.067, 0.073, 0.058), false))
	parent.add_child(button)
	return button


func _style(color: Color, border: bool, border_color: Color = COLOR_BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(1 if border else 0)
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style
