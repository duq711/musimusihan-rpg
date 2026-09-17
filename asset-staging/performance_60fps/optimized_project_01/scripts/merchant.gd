extends Control
class_name MerchantScreen

const GAME_SCENE_PATH := "res://main.tscn"
const HIDEOUT_SCENE_PATH := "res://hideout.tscn"
const UI_FONT_PATH := "res://assets/fonts/NotoSansKR-Variable.ttf"
const UI_FONT_FILE: FontFile = preload(UI_FONT_PATH)
const ITEM_ATLAS := preload("res://assets/ui/inventory_item_atlas.png")
const LOADING_SCREEN_SCRIPT := preload("res://scripts/loading_screen.gd")

const COLOR_BG := Color(0.018, 0.021, 0.018)
const COLOR_PANEL := Color(0.018, 0.023, 0.022, 0.97)
const COLOR_EDGE := Color(0.31, 0.34, 0.29, 0.92)
const COLOR_IVORY := Color(0.91, 0.89, 0.82)
const COLOR_TEXT := Color(0.74, 0.75, 0.69)
const COLOR_MUTED := Color(0.45, 0.47, 0.42)
const COLOR_GOLD := Color(0.72, 0.61, 0.37)
const COLOR_OLIVE := Color(0.39, 0.43, 0.31)
const COLOR_TEAL := Color(0.38, 0.57, 0.54)

var transition_duration := 0.22
var transitioning := false
var inventory: ExpeditionInventory

var merchant_stage: Control
var merchant_artwork_slot: Panel
var dialogue_panel: Panel
var trade_panel: Panel
var portrait_slot: Panel
var merchant_name_label: Label
var dialogue_line_label: Label
var dialogue_buttons: Array[Button] = []
var trade_option_button: Button
var rumor_option_button: Button
var work_option_button: Button
var dungeon_option_button: Button
var leave_option_button: Button

var currency_label: Label
var capacity_label: Label
var stock_rows: VBoxContainer
var bag_rows: VBoxContainer
var buy_detail_label: Label
var sell_detail_label: Label
var buy_button: Button
var sell_button: Button
var trade_status_label: Label
var trade_back_button: Button
var trade_dungeon_button: Button
var stock_buttons: Dictionary = {}
var bag_buttons: Dictionary = {}
var selected_buy_id := ""
var selected_sell_id := ""
var fade_layer: ColorRect
var loading_screen: SanctuaryLoadingScreen

var ui_font: FontVariation
var ui_medium_font: FontVariation
var ui_title_font: FontVariation
var ui_spaced_font: FontVariation


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ExpeditionSession.ensure_journey()
	inventory = ExpeditionSession.get_inventory()
	_build_fonts()
	_build_interface()
	_show_dialogue()
	call_deferred("_focus_dialogue_default")


func _build_fonts() -> void:
	ui_font = _font_variation(UI_FONT_FILE, 400, 0)
	ui_medium_font = _font_variation(UI_FONT_FILE, 520, 0)
	ui_title_font = _font_variation(UI_FONT_FILE, 620, 2)
	ui_spaced_font = _font_variation(UI_FONT_FILE, 420, 1)
	var merchant_theme := Theme.new()
	merchant_theme.default_font = ui_font
	merchant_theme.default_font_size = 14
	theme = merchant_theme


func _build_interface() -> void:
	var background := ColorRect.new()
	background.name = "MerchantBackground"
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	merchant_stage = Control.new()
	merchant_stage.name = "MerchantStage"
	merchant_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	merchant_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(merchant_stage)
	_build_stall_environment(merchant_stage)
	_build_merchant_placeholder(merchant_stage)
	_build_dialogue_panel()
	_build_trade_panel()

	fade_layer = ColorRect.new()
	fade_layer.name = "MerchantSceneFade"
	fade_layer.color = Color(0, 0, 0, 0)
	fade_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.z_index = 100
	add_child(fade_layer)


func _build_stall_environment(parent: Control) -> void:
	var wall := ColorRect.new()
	wall.name = "PlaceholderShopWall"
	wall.color = Color(0.075, 0.077, 0.064)
	wall.position = Vector2.ZERO
	wall.size = Vector2(1280, 492)
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(wall)
	for row in range(5):
		for column in range(10):
			var block := ColorRect.new()
			block.color = Color(0.105, 0.102, 0.083, 0.36 if (row + column) % 2 == 0 else 0.22)
			block.position = Vector2(column * 130 - (65 if row % 2 == 1 else 0), row * 94)
			block.size = Vector2(126, 90)
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wall.add_child(block)

	var ceiling_shadow := ColorRect.new()
	ceiling_shadow.color = Color(0.008, 0.01, 0.009, 0.72)
	ceiling_shadow.position = Vector2(0, 0)
	ceiling_shadow.size = Vector2(1280, 56)
	parent.add_child(ceiling_shadow)
	for lamp_x in [230, 640, 1040]:
		var lamp := Panel.new()
		lamp.position = Vector2(lamp_x - 72, 25)
		lamp.size = Vector2(144, 10)
		lamp.add_theme_stylebox_override("panel", _panel_style(Color(0.75, 0.63, 0.38, 0.72), Color(0.9, 0.79, 0.48, 0.74), 1, 3))
		parent.add_child(lamp)

	_build_shelf(parent, Vector2(26, 78), Vector2(340, 332), ["◉", "†", "♨", "▰", "◆", "⚿"])
	_build_shelf(parent, Vector2(924, 78), Vector2(330, 332), ["✚", "◈", "✥", "♜", "▥", "⌃"])

	var counter := Panel.new()
	counter.name = "MerchantCounter"
	counter.position = Vector2(244, 358)
	counter.size = Vector2(792, 134)
	counter.add_theme_stylebox_override("panel", _panel_style(Color(0.105, 0.072, 0.041), Color(0.22, 0.15, 0.08), 2, 4))
	parent.add_child(counter)
	var counter_edge := ColorRect.new()
	counter_edge.color = Color(0.34, 0.25, 0.13)
	counter_edge.position = Vector2(0, 0)
	counter_edge.size = Vector2(792, 7)
	counter.add_child(counter_edge)

	var location := _label("성소 외곽 · 회수품 중개소", 11, Color(0.64, 0.61, 0.49))
	location.position = Vector2(28, 52)
	location.size = Vector2(420, 20)
	location.add_theme_font_override("font", ui_spaced_font)
	parent.add_child(location)


func _build_shelf(parent: Control, shelf_position: Vector2, shelf_size: Vector2, glyphs: Array[String]) -> void:
	var shelf := Panel.new()
	shelf.position = shelf_position
	shelf.size = shelf_size
	shelf.add_theme_stylebox_override("panel", _panel_style(Color(0.035, 0.04, 0.033), Color(0.18, 0.19, 0.15), 2, 2))
	parent.add_child(shelf)
	for row in range(3):
		var plank := ColorRect.new()
		plank.position = Vector2(12, 98 + row * 101)
		plank.size = Vector2(shelf_size.x - 24, 8)
		plank.color = Color(0.19, 0.14, 0.08)
		shelf.add_child(plank)
	for index in range(glyphs.size()):
		var crate := Panel.new()
		var column := index % 2
		var row := index / 2
		crate.position = Vector2(24 + column * (shelf_size.x * 0.47), 18 + row * 101)
		crate.size = Vector2(112, 68)
		crate.add_theme_stylebox_override("panel", _panel_style(Color(0.09, 0.095, 0.071), Color(0.29, 0.28, 0.2), 1, 2))
		shelf.add_child(crate)
		var glyph := _label(glyphs[index], 26, Color(0.48, 0.48, 0.37))
		glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		crate.add_child(glyph)


func _build_merchant_placeholder(parent: Control) -> void:
	merchant_artwork_slot = Panel.new()
	merchant_artwork_slot.name = "MerchantArtworkSlot"
	merchant_artwork_slot.position = Vector2(444, 54)
	merchant_artwork_slot.size = Vector2(392, 414)
	merchant_artwork_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	merchant_artwork_slot.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.019, 0.016, 0.26), Color(0.29, 0.31, 0.25, 0.24), 1, 8))
	parent.add_child(merchant_artwork_slot)

	var halo := Panel.new()
	halo.position = Vector2(75, 30)
	halo.size = Vector2(242, 338)
	halo.add_theme_stylebox_override("panel", _panel_style(Color(0.25, 0.25, 0.18, 0.11), Color.TRANSPARENT, 0, 110))
	merchant_artwork_slot.add_child(halo)

	var body := Polygon2D.new()
	body.name = "MerchantSilhouetteBody"
	body.polygon = PackedVector2Array([
		Vector2(66, 389), Vector2(91, 231), Vector2(128, 174), Vector2(155, 151),
		Vector2(237, 151), Vector2(266, 177), Vector2(304, 236), Vector2(331, 389)
	])
	body.color = Color(0.055, 0.061, 0.052)
	merchant_artwork_slot.add_child(body)

	var shoulders := Panel.new()
	shoulders.position = Vector2(116, 142)
	shoulders.size = Vector2(160, 82)
	shoulders.add_theme_stylebox_override("panel", _panel_style(Color(0.075, 0.081, 0.068), Color(0.14, 0.15, 0.12), 1, 36))
	merchant_artwork_slot.add_child(shoulders)
	var head := Panel.new()
	head.name = "MerchantSilhouetteHead"
	head.position = Vector2(158, 65)
	head.size = Vector2(78, 102)
	head.add_theme_stylebox_override("panel", _panel_style(Color(0.065, 0.071, 0.06), Color(0.16, 0.17, 0.13), 1, 38))
	merchant_artwork_slot.add_child(head)
	var pendant := Label.new()
	pendant.text = "◆"
	pendant.position = Vector2(180, 208)
	pendant.size = Vector2(40, 50)
	pendant.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pendant.add_theme_font_size_override("font_size", 24)
	pendant.add_theme_color_override("font_color", Color(0.52, 0.42, 0.2))
	merchant_artwork_slot.add_child(pendant)


func _build_dialogue_panel() -> void:
	dialogue_panel = Panel.new()
	dialogue_panel.name = "MerchantDialoguePanel"
	dialogue_panel.position = Vector2(86, 438)
	dialogue_panel.size = Vector2(1108, 264)
	dialogue_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.004, 0.006, 0.005, 0.97), Color(0.38, 0.4, 0.34, 0.96), 1, 2))
	add_child(dialogue_panel)

	portrait_slot = Panel.new()
	portrait_slot.name = "MerchantPortraitSlot"
	portrait_slot.position = Vector2(16, 16)
	portrait_slot.size = Vector2(70, 70)
	portrait_slot.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.075, 0.06), Color(0.43, 0.42, 0.32), 1, 2))
	dialogue_panel.add_child(portrait_slot)
	var portrait_glyph := _label("◆", 28, COLOR_GOLD)
	portrait_glyph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	portrait_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	portrait_slot.add_child(portrait_glyph)

	merchant_name_label = _label("유물 중개인 모르칸", 18, COLOR_IVORY)
	merchant_name_label.name = "MerchantName"
	merchant_name_label.position = Vector2(102, 13)
	merchant_name_label.size = Vector2(530, 31)
	merchant_name_label.add_theme_font_override("font", ui_medium_font)
	dialogue_panel.add_child(merchant_name_label)
	var history_hint := _label("중개소 대화", 11, COLOR_MUTED)
	history_hint.position = Vector2(900, 18)
	history_hint.size = Vector2(176, 22)
	history_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dialogue_panel.add_child(history_hint)

	var divider := ColorRect.new()
	divider.position = Vector2(102, 48)
	divider.size = Vector2(974, 1)
	divider.color = Color(0.32, 0.34, 0.29, 0.8)
	dialogue_panel.add_child(divider)
	dialogue_line_label = _label("왔군. 성물실은 자비가 없지. 들어가기 전에 필요한 걸 챙겨 가게.", 14, COLOR_TEXT)
	dialogue_line_label.name = "MerchantDialogueLine"
	dialogue_line_label.position = Vector2(102, 55)
	dialogue_line_label.size = Vector2(974, 30)
	dialogue_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_panel.add_child(dialogue_line_label)

	trade_option_button = _dialogue_button("›  물건을 거래합니다.", "TradeDialogueOption", 92)
	rumor_option_button = _dialogue_button("›  성물실의 소문을 묻습니다.", "RumorDialogueOption", 124)
	work_option_button = _dialogue_button("›  일거리가 있는지 묻습니다.", "WorkDialogueOption", 156)
	dungeon_option_button = _dialogue_button("›  던전으로 출발합니다.", "DungeonDialogueOption", 188)
	leave_option_button = _dialogue_button("›  은신처로 돌아갑니다.", "LeaveDialogueOption", 220)
	dialogue_buttons = [trade_option_button, rumor_option_button, work_option_button, dungeon_option_button, leave_option_button]
	trade_option_button.pressed.connect(_show_trade)
	rumor_option_button.pressed.connect(_show_rumor)
	work_option_button.pressed.connect(_show_work)
	dungeon_option_button.pressed.connect(_go_to_dungeon)
	leave_option_button.pressed.connect(_go_to_hideout)


func _dialogue_button(text_value: String, node_name: String, y: float) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = Vector2(102, y)
	button.size = Vector2(974, 32)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_font)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", Color(0.72, 0.73, 0.67))
	button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	button.add_theme_color_override("font_focus_color", COLOR_IVORY)
	button.add_theme_stylebox_override("normal", _row_style(Color.TRANSPARENT, Color.TRANSPARENT, 0))
	button.add_theme_stylebox_override("hover", _row_style(Color(0.25, 0.27, 0.21, 0.42), COLOR_GOLD, 2))
	button.add_theme_stylebox_override("focus", _row_style(Color(0.25, 0.27, 0.21, 0.42), COLOR_GOLD, 2))
	dialogue_panel.add_child(button)
	return button


func _build_trade_panel() -> void:
	trade_panel = Panel.new()
	trade_panel.name = "MerchantTradePanel"
	trade_panel.position = Vector2(40, 28)
	trade_panel.size = Vector2(1200, 664)
	trade_panel.visible = false
	trade_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.006, 0.009, 0.008, 0.985), Color(0.37, 0.39, 0.33), 1, 3))
	add_child(trade_panel)

	var title := _label("모르칸의 거래소", 24, COLOR_IVORY)
	title.position = Vector2(26, 18)
	title.size = Vector2(400, 36)
	title.add_theme_font_override("font", ui_title_font)
	trade_panel.add_child(title)
	currency_label = _label("", 16, COLOR_GOLD)
	currency_label.name = "MerchantWalletLabel"
	currency_label.position = Vector2(760, 21)
	currency_label.size = Vector2(220, 30)
	currency_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	currency_label.add_theme_font_override("font", ui_spaced_font)
	trade_panel.add_child(currency_label)
	capacity_label = _label("", 12, COLOR_MUTED)
	capacity_label.position = Vector2(990, 24)
	capacity_label.size = Vector2(176, 24)
	capacity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trade_panel.add_child(capacity_label)

	var stock_panel := _trade_column("상인 재고 · 구매", Vector2(24, 72), Vector2(552, 468))
	trade_panel.add_child(stock_panel)
	stock_rows = _scroll_rows(stock_panel, "StockRows")
	buy_detail_label = _detail_label(stock_panel, "BuyDetail", Vector2(14, 353), Vector2(382, 94))
	buy_button = _action_button("구매", "BuySelectedButton", Vector2(408, 374), Vector2(126, 48))
	buy_button.disabled = true
	buy_button.pressed.connect(_buy_selected)
	stock_panel.add_child(buy_button)

	var bag_panel := _trade_column("내 가방 · 판매", Vector2(596, 72), Vector2(580, 468))
	trade_panel.add_child(bag_panel)
	bag_rows = _scroll_rows(bag_panel, "BagRows")
	sell_detail_label = _detail_label(bag_panel, "SellDetail", Vector2(14, 353), Vector2(408, 94))
	sell_button = _action_button("판매", "SellSelectedButton", Vector2(436, 374), Vector2(126, 48))
	sell_button.disabled = true
	sell_button.pressed.connect(_sell_selected)
	bag_panel.add_child(sell_button)

	trade_status_label = _label("거래할 물건을 선택하십시오.", 13, COLOR_TEXT)
	trade_status_label.name = "TradeStatus"
	trade_status_label.position = Vector2(24, 552)
	trade_status_label.size = Vector2(1152, 30)
	trade_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trade_panel.add_child(trade_status_label)
	trade_back_button = _action_button("대화로 돌아가기", "TradeBackButton", Vector2(334, 594), Vector2(250, 44))
	trade_back_button.pressed.connect(_show_dialogue)
	trade_panel.add_child(trade_back_button)
	trade_dungeon_button = _action_button("던전으로 출발", "TradeDungeonButton", Vector2(616, 594), Vector2(250, 44), true)
	trade_dungeon_button.pressed.connect(_go_to_dungeon)
	trade_panel.add_child(trade_dungeon_button)


func _trade_column(title_text: String, column_position: Vector2, column_size: Vector2) -> Panel:
	var panel := Panel.new()
	panel.position = column_position
	panel.size = column_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.022, 0.028, 0.025, 0.96), Color(0.24, 0.27, 0.22), 1, 2))
	var title := _label(title_text, 16, COLOR_IVORY)
	title.position = Vector2(14, 12)
	title.size = Vector2(column_size.x - 28, 28)
	title.add_theme_font_override("font", ui_medium_font)
	panel.add_child(title)
	var divider := ColorRect.new()
	divider.position = Vector2(14, 44)
	divider.size = Vector2(column_size.x - 28, 1)
	divider.color = Color(0.28, 0.31, 0.25)
	panel.add_child(divider)
	return panel


func _scroll_rows(parent: Panel, rows_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(14, 54)
	scroll.size = Vector2(parent.size.x - 28, 286)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = rows_name
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	return rows


func _detail_label(parent: Panel, node_name: String, label_position: Vector2, label_size: Vector2) -> Label:
	var label := _label("선택한 물건의 정보가 여기에 표시됩니다.", 12, COLOR_MUTED)
	label.name = node_name
	label.position = label_position
	label.size = label_size
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _show_dialogue() -> void:
	trade_panel.visible = false
	dialogue_panel.visible = true
	merchant_stage.visible = true
	dialogue_line_label.text = "왔군. 성물실은 자비가 없지. 들어가기 전에 필요한 걸 챙겨 가게."
	_focus_dialogue_default()


func _show_trade() -> void:
	dialogue_panel.visible = false
	merchant_stage.visible = false
	trade_panel.visible = true
	selected_buy_id = ""
	selected_sell_id = ""
	trade_status_label.text = "거래할 물건을 선택하십시오."
	_refresh_trade()
	var first_button: Button = null
	for item_id in stock_buttons:
		var candidate := stock_buttons[item_id] as Button
		if not candidate.disabled:
			first_button = candidate
			break
	if first_button != null:
		first_button.grab_focus()
	else:
		trade_back_button.grab_focus()


func _show_rumor() -> void:
	dialogue_line_label.text = "종소리가 세 번 울린 뒤엔 시체가 제 발로 걷는다고 하더군. 등 뒤를 조심하게."


func _show_work() -> void:
	dialogue_line_label.text = "의뢰 장부는 아직 정리 중이네. 지금은 살아 돌아와 물건을 가져오는 게 일이지."


func _refresh_trade() -> void:
	_refresh_header()
	_rebuild_stock_rows()
	_rebuild_bag_rows()
	_refresh_selection_details()


func _refresh_header() -> void:
	currency_label.text = "보유  %d 크라운" % ExpeditionSession.crowns
	capacity_label.text = "가방 %d / %d · %.1f 무게" % [inventory.slots.size(), ExpeditionInventory.MAX_SLOTS, inventory.total_weight()]


func _rebuild_stock_rows() -> void:
	_clear_children(stock_rows)
	stock_buttons.clear()
	var item_ids := ExpeditionSession.merchant_stock.keys()
	item_ids.sort()
	for item_value in item_ids:
		var item_id := str(item_value)
		var definition := ExpeditionInventory.get_item_definition(item_id)
		if definition.is_empty():
			continue
		var quantity := ExpeditionSession.get_stock_quantity(item_id)
		var price := ExpeditionSession.get_buy_price(item_id)
		var row := _item_row_button(
			"%s    재고 %d    %d 크라운" % [str(definition.get("name", item_id)), quantity, price],
			"Stock_%s" % item_id,
			item_id
		)
		row.disabled = quantity <= 0
		row.set_pressed_no_signal(item_id == selected_buy_id)
		row.pressed.connect(_select_stock_item.bind(item_id))
		stock_rows.add_child(row)
		stock_buttons[item_id] = row


func _rebuild_bag_rows() -> void:
	_clear_children(bag_rows)
	bag_buttons.clear()
	var totals: Dictionary = {}
	for slot in inventory.slots:
		var item_id := str(slot.get("id", ""))
		totals[item_id] = int(totals.get(item_id, 0)) + int(slot.get("quantity", 0))
	var item_ids := totals.keys()
	item_ids.sort()
	for item_value in item_ids:
		var item_id := str(item_value)
		var definition := ExpeditionInventory.get_item_definition(item_id)
		var quantity := int(totals[item_id])
		var price := ExpeditionSession.get_sell_price(item_id)
		var row := _item_row_button(
			"%s    보유 %d    개당 %d 크라운" % [str(definition.get("name", item_id)), quantity, price],
			"Bag_%s" % item_id,
			item_id
		)
		row.set_pressed_no_signal(item_id == selected_sell_id)
		row.pressed.connect(_select_bag_item.bind(item_id))
		bag_rows.add_child(row)
		bag_buttons[item_id] = row
	if item_ids.is_empty():
		var empty := _label("판매할 수 있는 가방 물품이 없습니다.", 12, COLOR_MUTED)
		empty.custom_minimum_size = Vector2(0, 46)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bag_rows.add_child(empty)


func _item_row_button(text_value: String, node_name: String, item_id: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.icon = _item_texture(item_id)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 36)
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	button.add_theme_color_override("font_focus_color", COLOR_IVORY)
	button.add_theme_stylebox_override("normal", _row_style(Color(0.035, 0.041, 0.035), Color(0.18, 0.2, 0.16), 0))
	button.add_theme_stylebox_override("hover", _row_style(Color(0.15, 0.16, 0.11), COLOR_GOLD, 2))
	button.add_theme_stylebox_override("focus", _row_style(Color(0.15, 0.16, 0.11), COLOR_GOLD, 2))
	button.add_theme_stylebox_override("pressed", _row_style(Color(0.2, 0.19, 0.12), COLOR_GOLD.lightened(0.15), 2))
	button.add_theme_stylebox_override("disabled", _row_style(Color(0.018, 0.021, 0.018), Color(0.11, 0.12, 0.1), 0))
	return button


func _select_stock_item(item_id: String) -> void:
	selected_buy_id = item_id
	for stock_id in stock_buttons:
		(stock_buttons[stock_id] as Button).set_pressed_no_signal(str(stock_id) == item_id)
	_refresh_selection_details()
	trade_status_label.text = "%s을(를) 선택했습니다." % ExpeditionInventory.get_item_name(item_id)


func _select_bag_item(item_id: String) -> void:
	selected_sell_id = item_id
	for bag_id in bag_buttons:
		(bag_buttons[bag_id] as Button).set_pressed_no_signal(str(bag_id) == item_id)
	_refresh_selection_details()
	trade_status_label.text = "%s을(를) 판매 대상으로 선택했습니다." % ExpeditionInventory.get_item_name(item_id)


func _refresh_selection_details() -> void:
	buy_button.disabled = selected_buy_id.is_empty() or ExpeditionSession.get_stock_quantity(selected_buy_id) <= 0
	sell_button.disabled = selected_sell_id.is_empty() or inventory.count_item(selected_sell_id) <= 0
	if selected_buy_id.is_empty():
		buy_detail_label.text = "상품을 선택하면 설명과 구매 가격을 확인할 수 있습니다."
	else:
		var buy_definition := ExpeditionInventory.get_item_definition(selected_buy_id)
		buy_detail_label.text = "%s\n%s\n무게 %.2f · 구매 %d 크라운" % [
			str(buy_definition.get("name", selected_buy_id)),
			str(buy_definition.get("summary", "")),
			float(buy_definition.get("weight", 0.0)),
			ExpeditionSession.get_buy_price(selected_buy_id),
		]
	if selected_sell_id.is_empty():
		sell_detail_label.text = "가방 물품을 선택하면 판매 가격을 확인할 수 있습니다."
	else:
		var sell_definition := ExpeditionInventory.get_item_definition(selected_sell_id)
		sell_detail_label.text = "%s\n%s\n보유 %d · 판매 %d 크라운" % [
			str(sell_definition.get("name", selected_sell_id)),
			str(sell_definition.get("summary", "")),
			inventory.count_item(selected_sell_id),
			ExpeditionSession.get_sell_price(selected_sell_id),
		]


func _buy_selected() -> void:
	if selected_buy_id.is_empty():
		return
	var item_name := ExpeditionInventory.get_item_name(selected_buy_id)
	var result := ExpeditionSession.buy_item(selected_buy_id, 1)
	if bool(result.get("accepted", false)):
		trade_status_label.text = "%s을(를) 구매했습니다.  -%d 크라운" % [item_name, int(result.get("price", 0))]
	else:
		trade_status_label.text = _transaction_error(str(result.get("reason", "unknown")))
	_refresh_trade()


func _sell_selected() -> void:
	if selected_sell_id.is_empty():
		return
	var item_name := ExpeditionInventory.get_item_name(selected_sell_id)
	var result := ExpeditionSession.sell_item(selected_sell_id, 1)
	if bool(result.get("accepted", false)):
		trade_status_label.text = "%s을(를) 판매했습니다.  +%d 크라운" % [item_name, int(result.get("price", 0))]
	else:
		trade_status_label.text = _transaction_error(str(result.get("reason", "unknown")))
	if inventory.count_item(selected_sell_id) <= 0:
		selected_sell_id = ""
	_refresh_trade()


func _transaction_error(reason: String) -> String:
	match reason:
		"out_of_stock":
			return "재고가 모두 소진되었습니다."
		"not_enough_crowns":
			return "크라운이 부족합니다."
		"inventory_full":
			return "가방에 빈자리가 없습니다."
		"already_learned":
			return "이미 익힌 주문의 마법서입니다."
		"already_owned":
			return "같은 마법서를 이미 가방에 보유하고 있습니다."
		"not_owned":
			return "판매할 물건을 보유하고 있지 않습니다."
		_:
			return "거래를 완료할 수 없습니다."


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		if trade_panel.visible:
			_show_dialogue()
		else:
			_go_to_hideout()
		get_viewport().set_input_as_handled()


func _go_to_dungeon() -> void:
	_transition_to_scene(GAME_SCENE_PATH)


func _go_to_hideout() -> void:
	_transition_to_scene(HIDEOUT_SCENE_PATH)


func _transition_to_scene(scene_path: String) -> void:
	if transitioning:
		return
	transitioning = true
	for button in dialogue_buttons + [buy_button, sell_button, trade_back_button, trade_dungeon_button]:
		if is_instance_valid(button):
			button.disabled = true
	fade_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween()
	tween.tween_property(fade_layer, "color", Color(0, 0, 0, 1), transition_duration)
	await tween.finished
	loading_screen = LOADING_SCREEN_SCRIPT.new() as SanctuaryLoadingScreen
	loading_screen.name = "SceneLoadingOverlay"
	if scene_path == GAME_SCENE_PATH:
		loading_screen.configure(
			scene_path,
			"검은 성물실로 향하는 중",
			"어둠 속 통로와 전투 구역을 준비하고 있습니다",
			"원정 장비를 점검하는 중",
			0.7
		)
	else:
		loading_screen.configure(
			scene_path,
			"은신처로 돌아가는 중",
			"성소의 안전한 불빛과 보관함을 준비하고 있습니다",
			"귀환로를 밝히는 중",
			0.7
		)
	loading_screen.load_failed.connect(_on_scene_loading_failed.bind(loading_screen))
	loading_screen.attach_as_overlay(get_tree())


func _on_scene_loading_failed(_error_code: int, failed_screen: SanctuaryLoadingScreen) -> void:
	if failed_screen != loading_screen:
		return
	failed_screen.dismiss()
	loading_screen = null
	transitioning = false
	fade_layer.color = Color(0, 0, 0, 0)
	fade_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for button in dialogue_buttons + [buy_button, sell_button, trade_back_button, trade_dungeon_button]:
		if is_instance_valid(button):
			button.disabled = false
	_focus_dialogue_default()


func _focus_dialogue_default() -> void:
	if is_instance_valid(trade_option_button) and dialogue_panel.visible:
		trade_option_button.grab_focus()


func _clear_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.free()


func _item_texture(item_id: String) -> Texture2D:
	var definition := ExpeditionInventory.get_item_definition(item_id)
	var icon_path := str(definition.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path, "Texture2D"):
		return load(icon_path) as Texture2D
	var atlas_cell: Vector2i = definition.get("atlas_cell", Vector2i.ZERO)
	var texture := AtlasTexture.new()
	texture.atlas = ITEM_ATLAS
	var cell_size := Vector2(float(ITEM_ATLAS.get_width()) / 4.0, float(ITEM_ATLAS.get_height()) / 4.0)
	texture.region = Rect2(Vector2(atlas_cell.x, atlas_cell.y) * cell_size, cell_size)
	return texture


func _action_button(text_value: String, node_name: String, button_position: Vector2, button_size: Vector2, accent := false) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text_value
	button.position = button_position
	button.size = button_size
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", ui_spaced_font)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_IVORY)
	var edge := COLOR_GOLD if accent else COLOR_OLIVE
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.045, 0.052, 0.043), edge, 1, 2))
	button.add_theme_stylebox_override("hover", _panel_style(edge.darkened(0.46), edge.lightened(0.18), 2, 2))
	button.add_theme_stylebox_override("focus", _panel_style(edge.darkened(0.46), edge.lightened(0.18), 2, 2))
	button.add_theme_stylebox_override("pressed", _panel_style(edge.darkened(0.58), edge.lightened(0.25), 2, 2))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.02, 0.024, 0.02), Color(0.12, 0.13, 0.11), 1, 2))
	return button


func _label(text_value: String, size_value: int, color_value: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size_value)
	label.add_theme_color_override("font_color", color_value)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _font_variation(base_font: Font, weight: int, glyph_spacing: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base_font
	var text_server := TextServerManager.get_primary_interface()
	variation.variation_opentype = {text_server.name_to_tag("wght"): weight}
	variation.spacing_glyph = glyph_spacing
	return variation


func _row_style(background: Color, edge: Color, left_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = edge
	style.border_width_left = left_width
	style.border_width_bottom = 1 if edge.a > 0.0 else 0
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


func _panel_style(background: Color, border: Color, width := 1, radius := 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style
