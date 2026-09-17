extends CanvasLayer
class_name InventoryOverlay

signal closed
signal consumable_requested(item_id: String)
signal treatment_part_selected(part_id: String)
signal item_discarded(stack: Dictionary)

const BAG_COLUMNS := 6
const BAG_ROWS := 5
const CONTAINER_COLUMNS := 5
const CONTAINER_ROWS := 4
const BAG_SLOT_COUNT := BAG_COLUMNS * BAG_ROWS
const CONTAINER_SLOT_COUNT := CONTAINER_COLUMNS * CONTAINER_ROWS
const ITEM_ATLAS_PATH := "res://assets/ui/inventory_item_atlas.png"
const PLAYER_PORTRAIT := preload("res://scripts/player_portrait.gd")
const ITEM_DETAIL_WINDOW := preload("res://scripts/item_detail_window.gd")
const HEALTH_PANEL := preload("res://scripts/health_panel.gd")
const ATLAS_GRID_SIZE := Vector2i(4, 4)
const BAG_VISUAL_COLUMNS := 10
const BAG_VISUAL_ROWS := 5
const STORAGE_VISUAL_COLUMNS := 10
const STORAGE_VISUAL_ROWS := 4
const BAG_CELL_SIZE := Vector2(28.0, 28.0)
const STORAGE_CELL_SIZE := Vector2(28.0, 28.0)
const GRID_GAP := 2.0

# The inventory intentionally follows a compact tactical-survival language:
# almost-black panes, thin desaturated olive rules, square cells and dense data.
# The character portrait shares the production player model across scenes.
const COLOR_BACKDROP := Color(0.002, 0.003, 0.003, 0.54)
const COLOR_PANEL := Color(0.018, 0.019, 0.018, 0.965)
const COLOR_PANEL_INNER := Color(0.008, 0.009, 0.009, 0.965)
const COLOR_BORDER := Color(0.27, 0.285, 0.27, 0.98)
const COLOR_BORDER_BRIGHT := Color(0.61, 0.57, 0.43, 1.0)
const COLOR_TEXT := Color(0.82, 0.81, 0.73)
const COLOR_MUTED := Color(0.47, 0.47, 0.43)
const COLOR_OLIVE := Color(0.28, 0.285, 0.205)
const COLOR_ACTIVE := Color(0.72, 0.61, 0.34)
const COLOR_METAL_DARK := Color(0.105, 0.11, 0.108, 0.98)
const COLOR_GOLD := Color(0.72, 0.58, 0.31)

# Public roots and controls are intentionally exposed so integration tests can
# inspect the overlay without depending on private node paths.
var overlay_root: ColorRect
var modal_root: Panel
var equipment_root: Panel
var inventory_root: Panel
var inventory_grid_root: Control
var container_root: Panel
var container_grid_root: Control
var detail_root: Panel
var status_footer: Panel
var weight_value_label: Label
var weight_capacity_label: Label
var stamina_bar: ProgressBar
var stamina_value_label: Label
var hunger_bar: ProgressBar
var hunger_value_label: Label
var thirst_bar: ProgressBar
var thirst_value_label: Label
var stress_bar: ProgressBar
var stress_value_label: Label

var equipment_slot_buttons: Array[Button] = []
var inventory_slot_buttons: Array[Button] = []
var container_slot_buttons: Array[Button] = []
var equipment_slot_keys: Array[String] = []

var equip_button: Button
var unequip_button: Button
var use_button: Button
var transfer_button: Button
var take_all_button: Button
var close_button: Button
var detail_button: Button
var item_detail_window: ITEM_DETAIL_WINDOW
var health_panel: HEALTH_PANEL
var health_tab_button: Button
var equipment_tab_button: Button
var health_tab_active := false
var _navigation_tabs: Array[Panel] = []
var quantity_dialog_root: ColorRect
var quantity_spinbox: SpinBox
var quantity_confirm_button: Button
var quantity_cancel_button: Button

var inventory_model: ExpeditionInventory
var loot_container: LootContainer

var selected_source := ""
var selected_index := -1
var selected_equipment_slot := ""

var _built := false
var _title_label: Label
var _mode_hint_label: Label
var _bag_status_label: Label
var _container_title_label: Label
var _container_subtitle_label: Label
var _container_status_label: Label
var _detail_glyph_label: Label
var _detail_name_label: Label
var _detail_summary_label: Label
var _detail_description_label: Label
var _detail_meta_label: Label
var _action_status_label: Label
var _character_stats_label: Label
var _character_stat_values_label: Label
var _quick_loadout_label: Label
var _detail_art_rect: TextureRect
var _footer_status_label: Label
var _item_atlas: Texture2D
var _atlas_texture_cache: Dictionary = {}
var _fallback_texture_cache: Dictionary = {}
var _quickbar_art_rects: Array[TextureRect] = []
var _quickbar_quantity_labels: Array[Label] = []
var _utility_rail: Panel
var _skip_equipment_press_slot := ""
var _skip_container_press_index := -1
var _quantity_source_index := -1
var _quantity_source_item_id := ""
var _quantity_title_label: Label
var _quantity_info_label: Label
var _inventory_heading_label: Label
var _equipment_area: Panel
var player_portrait: Control
var _status_provider := Callable()
var _status_refresh_elapsed := 0.0
var _inspected_source := ""
var _inspected_equipment_slot := ""
var _inspected_item_id := ""
var _inspected_stack: Dictionary = {}
var _inspected_equipment_data: Dictionary = {}
var _inspected_presentation: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_ensure_built()


func _process(delta: float) -> void:
	# The dungeon pauses the SceneTree while this overlay is open. ALWAYS
	# processing keeps both the character readout and deliberate rummaging cadence
	# current without requiring the paused world to run.
	if not is_open():
		return
	_status_refresh_elapsed += delta
	if _status_refresh_elapsed >= 0.1:
		_status_refresh_elapsed = 0.0
		refresh_status_readout()
	if loot_container != null and loot_container.has_unidentified_items():
		loot_container.advance_search(delta)


func _exit_tree() -> void:
	_disconnect_models()


func _input(event: InputEvent) -> void:
	if not is_open() or item_detail_window == null or not item_detail_window.is_open():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		item_detail_window.handle_cancel()
		get_viewport().set_input_as_handled()


func open_inventory(model: ExpeditionInventory, status_provider: Callable = Callable()) -> void:
	_ensure_built()
	health_tab_active = false
	_dismiss_item_details()
	_hide_quantity_dialog()
	_status_provider = status_provider
	_status_refresh_elapsed = 0.0
	_bind_models(model, null)
	_set_container_mode_layout(false)
	_clear_selection()
	_action_status_label.text = "장비와 인벤토리를 정비합니다."
	_refresh()
	overlay_root.visible = true


func open_container(model: ExpeditionInventory, container: LootContainer, status_provider: Callable = Callable()) -> void:
	_ensure_built()
	health_tab_active = false
	_dismiss_item_details()
	_hide_quantity_dialog()
	_status_provider = status_provider
	_status_refresh_elapsed = 0.0
	_bind_models(model, container)
	_set_container_mode_layout(true)
	if loot_container != null:
		loot_container.ever_opened = true
		loot_container.begin_search()
	_clear_selection()
	_action_status_label.text = (
		"상자를 뒤적이는 중입니다. 물품의 정체가 하나씩 드러납니다."
		if loot_container != null and loot_container.has_unidentified_items()
		else "더블클릭: 가져오기 · Ctrl+클릭: 전부 가져오기"
	)
	_refresh()
	overlay_root.visible = true


func close() -> void:
	if item_detail_window != null and item_detail_window.is_open():
		item_detail_window.handle_cancel()
		return
	if quantity_dialog_root != null and quantity_dialog_root.visible:
		_hide_quantity_dialog()
		_action_status_label.text = "수량 선택을 취소했습니다."
		return
	if not is_open():
		return
	overlay_root.visible = false
	_clear_selection()
	closed.emit()


func is_open() -> bool:
	return _built and overlay_root != null and overlay_root.visible


func set_status(text_value: String) -> void:
	_ensure_built()
	_action_status_label.text = text_value


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_load_visual_assets()
	_build_interface()


func _build_interface() -> void:
	overlay_root = ColorRect.new()
	overlay_root.name = "InventoryModalBackdrop"
	overlay_root.color = COLOR_BACKDROP
	overlay_root.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.visible = false
	overlay_root.z_index = 100
	add_child(overlay_root)

	modal_root = Panel.new()
	modal_root.name = "InventoryModal"
	modal_root.anchor_left = 0.5
	modal_root.anchor_top = 0.5
	modal_root.anchor_right = 0.5
	modal_root.anchor_bottom = 0.5
	modal_root.offset_left = -640.0
	modal_root.offset_top = -360.0
	modal_root.offset_right = 640.0
	modal_root.offset_bottom = 360.0
	modal_root.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_root.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0))
	overlay_root.add_child(modal_root)

	var inner_frame := Panel.new()
	inner_frame.name = "InnerFrame"
	inner_frame.position = Vector2.ZERO
	inner_frame.size = Vector2(1280, 720)
	inner_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.006, 0.006, 0.1), Color.TRANSPARENT, 0, 0))
	modal_root.add_child(inner_frame)

	var navigation_bar := Panel.new()
	navigation_bar.name = "InventoryNavigationBar"
	navigation_bar.position = Vector2.ZERO
	navigation_bar.size = Vector2(1280, 39)
	navigation_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	navigation_bar.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.019, 0.018, 0.975), Color(0.25, 0.255, 0.235), 1, 0))
	modal_root.add_child(navigation_bar)

	var navigation_items := ["종합정보", "장비", "건강상태", "스킬", "지도", "임무"]
	var navigation_widths := [80, 60, 88, 56, 56, 56]
	var navigation_names := ["OverviewTab", "EquipmentTab", "HealthTab", "SkillTab", "MapTab", "MissionTab"]
	var tab_x := 8
	for tab_index in range(navigation_items.size()):
		var tab_panel := Panel.new()
		tab_panel.name = str(navigation_names[tab_index])
		tab_panel.position = Vector2(tab_x, 3)
		tab_panel.size = Vector2(navigation_widths[tab_index], 33)
		tab_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var is_active := tab_index == 1
		tab_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.16, 0.145, 0.105, 0.94) if is_active else Color(0.025, 0.027, 0.025, 0.45), COLOR_ACTIVE if is_active else Color(0.11, 0.12, 0.11), 1 if is_active else 0, 0))
		navigation_bar.add_child(tab_panel)
		_navigation_tabs.append(tab_panel)
		var tab_label := _label(str(navigation_items[tab_index]), 11, Color(0.89, 0.9, 0.8) if is_active else Color(0.55, 0.57, 0.51))
		tab_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
		tab_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tab_panel.add_child(tab_label)
		if tab_index in [1, 2]:
			var tab_button := Button.new()
			tab_button.name = "OpenTab"
			tab_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			for style_name in ["normal", "hover", "pressed", "focus"]:
				tab_button.add_theme_stylebox_override(style_name, _panel_style(Color.TRANSPARENT, COLOR_ACTIVE if style_name == "focus" else Color.TRANSPARENT, 1 if style_name == "focus" else 0, 0))
			tab_panel.add_child(tab_button)
			if tab_index == 2:
				health_tab_button = tab_button
				tab_button.tooltip_text = "부위별 체력과 치료"
				tab_button.pressed.connect(open_health_tab)
			else:
				equipment_tab_button = tab_button
				tab_button.tooltip_text = "장비와 가방"
				tab_button.pressed.connect(open_equipment_tab)
		tab_x += navigation_widths[tab_index] - 2

	var interaction_guide := _label("더블클릭: 1개/수량 선택  ·  Ctrl+클릭: 전체 이동  ·  장비 더블클릭: 해제", 10, Color(0.55, 0.55, 0.5))
	interaction_guide.name = "InventoryInteractionGuide"
	interaction_guide.position = Vector2(420, 7)
	interaction_guide.size = Vector2(505, 24)
	interaction_guide.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_guide.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	navigation_bar.add_child(interaction_guide)

	_title_label = _label("장비", 16, Color(0.86, 0.88, 0.8))
	_title_label.position = Vector2(1018, 4)
	_title_label.size = Vector2(90, 30)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_label.visible = false
	modal_root.add_child(_title_label)

	_mode_hint_label = _label("슬롯 선택 · 호버 정보 · I", 10, Color(0.48, 0.5, 0.44))
	_mode_hint_label.position = Vector2(788, 8)
	_mode_hint_label.size = Vector2(226, 22)
	_mode_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_hint_label.visible = false
	modal_root.add_child(_mode_hint_label)

	close_button = _action_button("뒤로  ESC", Vector2(1118, 3), Vector2(154, 31), Color(0.065, 0.065, 0.058))
	close_button.name = "CloseInventoryButton"
	close_button.pressed.connect(close)
	modal_root.add_child(close_button)

	_build_equipment_panel()
	_build_inventory_panel()
	_build_transfer_rail()
	_build_container_panel()
	_build_bottom_dock()
	_build_quantity_dialog()
	_build_item_detail_window()
	_build_health_panel()
	_set_container_mode_layout(false)


func _build_equipment_panel() -> void:
	equipment_root = Panel.new()
	equipment_root.name = "EquipmentRoot"
	equipment_root.position = Vector2(16, 47)
	equipment_root.size = Vector2(392, 610)
	equipment_root.clip_contents = true
	equipment_root.add_theme_stylebox_override("panel", _ornate_panel_style(COLOR_PANEL))
	modal_root.add_child(equipment_root)
	_decorate_ornate_frame(equipment_root, equipment_root.size)

	var heading := _section_heading("캐릭터", "파이터")
	heading.position = Vector2(12, 11)
	heading.size = Vector2(368, 27)
	equipment_root.add_child(heading)

	var portrait_ring := Panel.new()
	portrait_ring.name = "CharacterPortraitRing"
	portrait_ring.position = Vector2(59, 45)
	portrait_ring.size = Vector2(274, 290)
	portrait_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_ring.add_theme_stylebox_override("panel", _panel_style(Color(0.006, 0.006, 0.006, 0.5), Color(0.34, 0.33, 0.28), 2, 138))
	equipment_root.add_child(portrait_ring)
	_add_character_ring_ornaments(equipment_root)

	player_portrait = PLAYER_PORTRAIT.new()
	player_portrait.name = "PlayerPortrait"
	player_portrait.position = Vector2(68, 48)
	player_portrait.size = Vector2(256, 297)
	player_portrait.z_index = 4
	equipment_root.add_child(player_portrait)

	var character_name := _label("— 파이터 —", 13, Color(0.68, 0.63, 0.49))
	character_name.position = Vector2(66, 350)
	character_name.size = Vector2(260, 24)
	character_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipment_root.add_child(character_name)

	_character_stats_label = _label("힘\n민첩\n의지\n지식\n수완\n───────────────\n체력\n무게", 11, Color(0.67, 0.68, 0.62))
	_character_stats_label.position = Vector2(24, 378)
	_character_stats_label.size = Vector2(344, 160)
	_character_stats_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_character_stats_label.add_theme_constant_override("line_spacing", 2)
	_character_stats_label.add_theme_stylebox_override("normal", _panel_style(Color(0.006, 0.007, 0.007, 0.74), Color(0.12, 0.125, 0.115), 1, 0))
	equipment_root.add_child(_character_stats_label)
	# Label starts with a larger text-derived size; clamp it again after theme resolution.
	_character_stats_label.size = Vector2(344, 160)
	_character_stat_values_label = _label("15\n15\n15\n15\n15\n\n100 / 100\n0.0 KG", 11, Color(0.43, 0.7, 0.26))
	_character_stat_values_label.position = Vector2(218, 378)
	_character_stat_values_label.size = Vector2(136, 160)
	_character_stat_values_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_character_stat_values_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_character_stat_values_label.add_theme_constant_override("line_spacing", 2)
	equipment_root.add_child(_character_stat_values_label)
	_character_stat_values_label.size = Vector2(136, 160)

	unequip_button = _action_button("선택 장비를 인벤토리에 넣기", Vector2(24, 542), Vector2(344, 32), Color(0.07, 0.068, 0.057))
	unequip_button.name = "UnequipButton"
	unequip_button.pressed.connect(_unequip_selected)
	equipment_root.add_child(unequip_button)

	var equipment_help := _label("장비 더블클릭으로도 바로 해제할 수 있습니다", 9, COLOR_MUTED)
	equipment_help.position = Vector2(24, 579)
	equipment_help.size = Vector2(344, 16)
	equipment_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equipment_root.add_child(equipment_help)


func _build_inventory_panel() -> void:
	inventory_root = Panel.new()
	inventory_root.name = "InventoryRoot"
	inventory_root.position = Vector2(408, 47)
	inventory_root.size = Vector2(392, 610)
	inventory_root.add_theme_stylebox_override("panel", _ornate_panel_style(COLOR_PANEL))
	modal_root.add_child(inventory_root)
	_decorate_ornate_frame(inventory_root, inventory_root.size)

	var heading := _section_heading("장착 장비", "클릭 선택 · 더블클릭 해제")
	heading.position = Vector2(12, 11)
	heading.size = Vector2(368, 27)
	inventory_root.add_child(heading)

	_equipment_area = Panel.new()
	_equipment_area.name = "EquippedItemsLayout"
	_equipment_area.position = Vector2(12, 42)
	_equipment_area.size = Vector2(368, 267)
	_equipment_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipment_area.add_theme_stylebox_override("panel", _panel_style(Color(0.006, 0.007, 0.007, 0.76), Color(0.135, 0.14, 0.13), 1, 0))
	inventory_root.add_child(_equipment_area)

	var equipment_positions := {
		"head": Vector2(140, 20),
		"body": Vector2(121, 94),
		"weapon": Vector2(14, 34),
		"offhand": Vector2(270, 34),
		"utility": Vector2(147, 202)
	}
	var equipment_sizes := {
		"head": Vector2(88, 67),
		"body": Vector2(126, 101),
		"weapon": Vector2(84, 158),
		"offhand": Vector2(84, 158),
		"utility": Vector2(74, 52)
	}
	for equipment_slot in ExpeditionInventory.EQUIPMENT_ORDER:
		var slot_key := str(equipment_slot)
		var slot_size: Vector2 = equipment_sizes.get(slot_key, Vector2(82, 72))
		var button := _slot_button(slot_size)
		button.name = "Equipment_%s" % slot_key
		button.position = equipment_positions.get(slot_key, Vector2.ZERO)
		button.size = slot_size
		button.z_index = 8
		button.set_meta("equipment_caption", str(ExpeditionInventory.EQUIPMENT_LABELS.get(slot_key, slot_key)))
		button.pressed.connect(_on_equipment_slot_pressed.bind(slot_key))
		button.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_key))
		button.mouse_entered.connect(_on_equipment_slot_hovered.bind(slot_key))
		button.mouse_exited.connect(_restore_selected_details)
		_equipment_area.add_child(button)
		equipment_slot_keys.append(slot_key)
		equipment_slot_buttons.append(button)

	for socket_position in [Vector2(90, 46), Vector2(250, 46), Vector2(90, 204), Vector2(250, 204)]:
		_add_empty_equipment_socket(_equipment_area, socket_position)

	_quick_loadout_label = _label("", 9, Color(0.5, 0.53, 0.46))
	_quick_loadout_label.position = Vector2(74, 242)
	_quick_loadout_label.size = Vector2(220, 18)
	_quick_loadout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_loadout_label.visible = false
	_equipment_area.add_child(_quick_loadout_label)

	_inventory_heading_label = _label("인벤토리", 12, Color(0.75, 0.72, 0.61))
	_inventory_heading_label.position = Vector2(16, 316)
	_inventory_heading_label.size = Vector2(170, 24)
	_inventory_heading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inventory_root.add_child(_inventory_heading_label)
	_bag_status_label = _label("물품 00종  ·  0개  ·  0.0KG", 11, COLOR_MUTED)
	_bag_status_label.position = Vector2(184, 316)
	_bag_status_label.size = Vector2(192, 24)
	_bag_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bag_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inventory_root.add_child(_bag_status_label)

	inventory_grid_root = Control.new()
	inventory_grid_root.name = "InventoryGridRoot"
	inventory_grid_root.position = Vector2(47, 344)
	inventory_grid_root.size = Vector2(298, 148)
	inventory_grid_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inventory_grid_root.set_meta("continuous_grid", true)
	inventory_grid_root.set_meta("visual_columns", BAG_VISUAL_COLUMNS)
	inventory_grid_root.set_meta("visual_rows", BAG_VISUAL_ROWS)
	inventory_root.add_child(inventory_grid_root)
	for row_index in range(BAG_VISUAL_ROWS):
		for column_index in range(BAG_VISUAL_COLUMNS):
			var cell_index := row_index * BAG_VISUAL_COLUMNS + column_index
			_add_micro_grid_cell(
				inventory_grid_root,
				Vector2(column_index * (BAG_CELL_SIZE.x + GRID_GAP), row_index * (BAG_CELL_SIZE.y + GRID_GAP)),
				BAG_CELL_SIZE,
				Color(0.012, 0.014, 0.013, 0.88),
				"BagGridCell_%02d" % cell_index
			)
	for index in range(BAG_SLOT_COUNT):
		var button := _slot_button(BAG_CELL_SIZE)
		button.name = "InventorySlot_%02d" % index
		button.visible = false
		button.z_index = 8
		button.pressed.connect(_on_inventory_slot_pressed.bind(index))
		button.gui_input.connect(_on_inventory_slot_gui_input.bind(index))
		button.mouse_entered.connect(_on_inventory_slot_hovered.bind(index))
		button.mouse_exited.connect(_restore_selected_details)
		inventory_grid_root.add_child(button)
		inventory_slot_buttons.append(button)

	detail_root = Panel.new()
	detail_root.name = "SelectedItemDetailRoot"
	detail_root.position = Vector2(874, 155)
	detail_root.size = Vector2(304, 148)
	detail_root.z_index = 220
	detail_root.visible = false
	detail_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_theme_stylebox_override("panel", _panel_style(Color(0.005, 0.006, 0.007, 0.985), Color(0.35, 0.37, 0.35), 2, 0))
	modal_root.add_child(detail_root)

	_detail_art_rect = TextureRect.new()
	_detail_art_rect.name = "SelectedItemArtwork"
	_detail_art_rect.position = Vector2(10, 42)
	_detail_art_rect.size = Vector2(72, 92)
	_detail_art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_root.add_child(_detail_art_rect)
	_detail_glyph_label = _label("", 1, Color.TRANSPARENT)
	_detail_glyph_label.visible = false
	detail_root.add_child(_detail_glyph_label)
	_detail_name_label = _label("아이템 정보", 15, Color(0.36, 0.62, 0.88))
	_detail_name_label.position = Vector2(12, 8)
	_detail_name_label.size = Vector2(280, 27)
	_detail_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name_label.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.08, 0.13, 0.92), Color(0.15, 0.31, 0.46), 1, 0))
	detail_root.add_child(_detail_name_label)
	_detail_summary_label = _label("슬롯을 선택하거나 마우스를 올리십시오.", 10, Color(0.59, 0.63, 0.52))
	_detail_summary_label.position = Vector2(90, 44)
	_detail_summary_label.size = Vector2(202, 20)
	detail_root.add_child(_detail_summary_label)
	_detail_description_label = _label("", 9, COLOR_MUTED)
	_detail_description_label.position = Vector2(90, 66)
	_detail_description_label.size = Vector2(202, 48)
	_detail_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_root.add_child(_detail_description_label)
	_detail_meta_label = _label("", 9, COLOR_MUTED)
	_detail_meta_label.position = Vector2(90, 116)
	_detail_meta_label.size = Vector2(202, 20)
	detail_root.add_child(_detail_meta_label)

	equip_button = _action_button("장착", Vector2(16, 518), Vector2(64, 29), Color(0.075, 0.082, 0.061))
	equip_button.name = "EquipButton"
	equip_button.pressed.connect(_equip_selected)
	inventory_root.add_child(equip_button)
	use_button = _action_button("사용", Vector2(86, 518), Vector2(64, 29), Color(0.055, 0.09, 0.065))
	use_button.name = "UseItemButton"
	use_button.pressed.connect(_request_selected_consumable)
	inventory_root.add_child(use_button)
	transfer_button = _action_button("상자로 이동", Vector2(156, 518), Vector2(104, 29), Color(0.095, 0.08, 0.052))
	transfer_button.name = "TransferButton"
	transfer_button.pressed.connect(_transfer_selected)
	inventory_root.add_child(transfer_button)
	detail_button = _action_button("상세 보기", Vector2(266, 518), Vector2(110, 29), Color(0.052, 0.054, 0.051))
	detail_button.name = "ItemDetailButton"
	detail_button.tooltip_text = "우클릭으로도 아이템 상세를 열 수 있습니다."
	detail_button.pressed.connect(_open_selected_item_details)
	inventory_root.add_child(detail_button)

	_action_status_label = _label("", 10, COLOR_MUTED)
	_action_status_label.position = Vector2(16, 553)
	_action_status_label.size = Vector2(360, 42)
	_action_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inventory_root.add_child(_action_status_label)


func _build_item_detail_window() -> void:
	item_detail_window = ITEM_DETAIL_WINDOW.new()
	item_detail_window.name = "ItemDetailWindow"
	item_detail_window.z_index = 700
	overlay_root.add_child(item_detail_window)
	item_detail_window.closed.connect(_on_item_details_closed)
	item_detail_window.tag_requested.connect(_on_item_tag_requested)
	item_detail_window.discard_requested.connect(_on_item_discard_requested)
	item_detail_window.equip_requested.connect(_on_item_equip_requested)


func _build_health_panel() -> void:
	health_panel = HEALTH_PANEL.new()
	health_panel.name = "BodyHealthPanel"
	health_panel.position = Vector2(16, 47)
	health_panel.visible = false
	modal_root.add_child(health_panel)
	health_panel.treatment_part_selected.connect(_on_treatment_part_selected)
	health_panel.consumable_requested.connect(_on_health_consumable_requested)
	overlay_root.resized.connect(_fit_health_layout)


func open_health_tab() -> void:
	_ensure_built()
	health_tab_active = true
	_dismiss_item_details()
	_hide_quantity_dialog()
	_clear_selection()
	_set_container_mode_layout(loot_container != null)
	_refresh()


func open_equipment_tab() -> void:
	_ensure_built()
	health_tab_active = false
	_set_container_mode_layout(loot_container != null)
	_refresh()


func _on_treatment_part_selected(part_id: String) -> void:
	treatment_part_selected.emit(part_id)
	refresh_status_readout()


func _on_health_consumable_requested(item_id: String) -> void:
	if inventory_model == null or inventory_model.count_item(item_id) <= 0:
		return
	consumable_requested.emit(item_id)
	refresh_status_readout()


func _apply_health_tab_layout() -> void:
	if health_panel == null:
		return
	health_panel.visible = health_tab_active
	equipment_root.visible = not health_tab_active
	if health_tab_active:
		inventory_root.position = Vector2(816, 47)
		container_root.visible = false
		_utility_rail.visible = false
		transfer_button.visible = false
		status_footer.position = Vector2(16, 665)
	for index in _navigation_tabs.size():
		var tab: Panel = _navigation_tabs[index]
		var active := index == (2 if health_tab_active else 1)
		tab.add_theme_stylebox_override("panel", _panel_style(Color(0.16, 0.145, 0.105, 0.94) if active else Color(0.025, 0.027, 0.025, 0.45), COLOR_ACTIVE if active else Color(0.11, 0.12, 0.11), 1 if active else 0, 0))
		var label := tab.get_child(0) as Label
		label.add_theme_color_override("font_color", Color(0.89, 0.9, 0.8) if active else Color(0.55, 0.57, 0.51))
	_fit_health_layout()


func _fit_health_layout() -> void:
	if modal_root == null or overlay_root == null:
		return
	modal_root.pivot_offset = Vector2(640, 360)
	var available := overlay_root.size
	var factor := minf(1.0, minf(available.x / 1280.0, available.y / 720.0)) if health_tab_active else 1.0
	modal_root.scale = Vector2.ONE * maxf(0.1, factor)


func _on_inventory_slot_gui_input(event: InputEvent, index: int) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT or (mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.double_click):
		open_item_details("inventory", index)


func _open_selected_item_details() -> void:
	open_item_details(selected_source, selected_index, selected_equipment_slot)


func open_item_details(source: String, index: int, equipment_slot := "") -> bool:
	if not is_open() or (quantity_dialog_root != null and quantity_dialog_root.visible):
		return false
	var context := _item_context(source, index, equipment_slot)
	var item_id := str(context.get("id", ""))
	if item_id.is_empty() or bool(context.get("concealed", false)):
		return false
	_inspected_source = source
	_inspected_equipment_slot = equipment_slot
	_inspected_item_id = item_id
	_inspected_stack = {}
	_inspected_equipment_data = {}
	if source == "inventory":
		_inspected_stack = inventory_model.slots[index]
	elif source == "container":
		_inspected_stack = loot_container.items[index]
	elif source == "equipment":
		_inspected_equipment_data = inventory_model.get_equipment_instance(equipment_slot)
	selected_source = source
	selected_index = index
	selected_equipment_slot = equipment_slot
	_present_item_details(context)
	detail_root.hide()
	return true


func _inspected_context() -> Dictionary:
	# Follow the exact stack object when earlier slots are removed. A new item
	# in the old index must never receive a pending tag, equip or discard action.
	if _inspected_source == "inventory" and inventory_model != null:
		for index in inventory_model.slots.size():
			if is_same(inventory_model.slots[index], _inspected_stack):
				return _item_context("inventory", index, "")
	elif _inspected_source == "container" and loot_container != null:
		for index in loot_container.items.size():
			if is_same(loot_container.items[index], _inspected_stack):
				return _item_context("container", index, "")
	elif _inspected_source == "equipment" and inventory_model != null:
		if str(inventory_model.equipment.get(_inspected_equipment_slot, "")) == _inspected_item_id and is_same(inventory_model.get_equipment_instance(_inspected_equipment_slot), _inspected_equipment_data):
			return _item_context("equipment", -1, _inspected_equipment_slot)
	return {}


func _present_item_details(context: Dictionary) -> void:
	var item_id := str(context.get("id", ""))
	var instance: Dictionary = context.get("instance", {})
	var owned := str(context.get("source", "")) in ["inventory", "equipment"]
	var equipped := str(context.get("source", "")) == "equipment"
	_inspected_presentation = {"id": item_id, "quantity": int(context.get("quantity", 0)), "instance": instance.duplicate(true), "owned": owned, "equipped": equipped}
	item_detail_window.present(item_id, int(context.get("quantity", 1)), instance, _item_texture(item_id), owned, equipped)


func _refresh_open_item_details() -> void:
	if item_detail_window == null or not item_detail_window.is_open():
		return
	var context := _inspected_context()
	if str(context.get("id", "")).is_empty() or bool(context.get("concealed", false)):
		_dismiss_item_details()
		return
	var instance: Dictionary = context.get("instance", {})
	if int(context.get("quantity", 0)) != int(_inspected_presentation.get("quantity", 0)) or instance != _inspected_presentation.get("instance", {}):
		_present_item_details(context)


func _dismiss_item_details() -> void:
	if item_detail_window != null:
		item_detail_window.dismiss()
	_on_item_details_closed()


func _on_item_details_closed() -> void:
	_inspected_source = ""
	_inspected_equipment_slot = ""
	_inspected_item_id = ""
	_inspected_stack = {}
	_inspected_equipment_data = {}
	_inspected_presentation = {}
	if _built and detail_root != null:
		_restore_selected_details()


func _on_item_tag_requested(text_value: String) -> void:
	var context := _inspected_context()
	var source := str(context.get("source", ""))
	if inventory_model == null or source not in ["inventory", "equipment"]:
		return
	var accepted := inventory_model.set_equipment_tag(str(context.get("equipment_slot", "")), text_value) if source == "equipment" else inventory_model.set_slot_tag(int(context.get("index", -1)), text_value)
	if accepted:
		_refresh_open_item_details()
		item_detail_window.set_status("이름표를 저장했습니다." if not text_value.strip_edges().is_empty() else "이름표를 지웠습니다.")


func _on_item_equip_requested() -> void:
	var context := _inspected_context()
	if inventory_model == null or str(context.get("source", "")) != "inventory":
		return
	var item_id := str(context.get("id", ""))
	var result := inventory_model.equip_from_slot(int(context.get("index", -1)))
	if bool(result.get("accepted", false)):
		_action_status_label.text = "%s을(를) 장착했습니다." % ExpeditionInventory.get_item_name(item_id)
		open_item_details("equipment", -1, str(result.get("slot", "")))
	else:
		item_detail_window.set_status("장착할 수 없습니다: " + _reason_text(str(result.get("reason", "unknown"))))


func _on_item_discard_requested(quantity: int) -> void:
	var context := _inspected_context()
	var source := str(context.get("source", ""))
	if inventory_model == null or source not in ["inventory", "equipment"] or quantity <= 0:
		return
	# Capture the target before changed signals refresh selection and close the
	# detail window. Only the selected stack (including its tag/mods) is removed.
	var index := int(context.get("index", -1))
	var equipment_slot := str(context.get("equipment_slot", ""))
	var count := mini(quantity, int(context.get("quantity", 0)))
	var stack := inventory_model.discard_equipment(equipment_slot) if source == "equipment" else inventory_model.remove_from_slot(index, count)
	if stack.is_empty():
		return
	stack["source"] = source
	stack["source_index"] = index
	stack["equipment_slot"] = equipment_slot
	stack["source_remaining"] = maxi(0, int(context.get("quantity", 0)) - int(stack.get("quantity", 0)))
	_dismiss_item_details()
	_clear_selection()
	_refresh()
	item_discarded.emit(stack)


func _build_transfer_rail() -> void:
	_utility_rail = Panel.new()
	_utility_rail.name = "InventoryUtilityRail"
	_utility_rail.position = Vector2(804, 47)
	_utility_rail.size = Vector2(8, 610)
	_utility_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_utility_rail.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.019, 0.018, 0.96), Color(0.34, 0.34, 0.31), 1, 0))
	modal_root.add_child(_utility_rail)
	var marker := _label("›", 15, Color(0.58, 0.53, 0.39))
	marker.position = Vector2(-5, 286)
	marker.size = Vector2(18, 38)
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_utility_rail.add_child(marker)


func _build_container_panel() -> void:
	container_root = Panel.new()
	container_root.name = "ContainerRoot"
	container_root.position = Vector2(816, 47)
	container_root.size = Vector2(392, 610)
	container_root.add_theme_stylebox_override("panel", _ornate_panel_style(COLOR_PANEL))
	modal_root.add_child(container_root)
	_decorate_ornate_frame(container_root, container_root.size)

	_container_title_label = _label("보물 상자", 16, COLOR_GOLD)
	_container_title_label.position = Vector2(18, 11)
	_container_title_label.size = Vector2(356, 26)
	_container_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container_root.add_child(_container_title_label)
	_container_status_label = _label("물품 0종", 10, COLOR_MUTED)
	_container_status_label.position = Vector2(18, 38)
	_container_status_label.size = Vector2(356, 18)
	_container_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container_root.add_child(_container_status_label)

	container_grid_root = Control.new()
	container_grid_root.name = "ContainerGridRoot"
	container_grid_root.position = Vector2(47, 64)
	container_grid_root.size = Vector2(298, 118)
	container_grid_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container_root.add_child(container_grid_root)
	for row_index in range(STORAGE_VISUAL_ROWS):
		for column_index in range(STORAGE_VISUAL_COLUMNS):
			_add_micro_grid_cell(
				container_grid_root,
				Vector2(column_index * (STORAGE_CELL_SIZE.x + GRID_GAP), row_index * (STORAGE_CELL_SIZE.y + GRID_GAP)),
				STORAGE_CELL_SIZE,
				Color(0.006, 0.007, 0.007, 0.94),
				"ContainerGridCell_%02d" % (row_index * STORAGE_VISUAL_COLUMNS + column_index)
			)
	for index in range(CONTAINER_SLOT_COUNT):
		var button := _slot_button(STORAGE_CELL_SIZE)
		button.name = "ContainerSlot_%02d" % index
		button.visible = false
		button.z_index = 8
		button.pressed.connect(_on_container_slot_pressed.bind(index))
		button.gui_input.connect(_on_container_slot_gui_input.bind(index))
		button.mouse_entered.connect(_on_container_slot_hovered.bind(index))
		button.mouse_exited.connect(_restore_selected_details)
		container_grid_root.add_child(button)
		container_slot_buttons.append(button)

	var empty_field := Panel.new()
	empty_field.name = "ContainerInspectionField"
	empty_field.position = Vector2(20, 195)
	empty_field.size = Vector2(352, 309)
	empty_field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_field.add_theme_stylebox_override("panel", _panel_style(Color(0.004, 0.005, 0.005, 0.46), Color(0.08, 0.085, 0.08), 1, 0))
	container_root.add_child(empty_field)

	_container_subtitle_label = _label("상자를 뒤져 물품을 확인하십시오.", 10, COLOR_MUTED)
	_container_subtitle_label.position = Vector2(20, 510)
	_container_subtitle_label.size = Vector2(352, 20)
	_container_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_container_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_container_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container_root.add_child(_container_subtitle_label)

	take_all_button = _action_button("모두 가져오기", Vector2(20, 538), Vector2(352, 31), Color(0.075, 0.072, 0.055))
	take_all_button.name = "TakeAllButton"
	take_all_button.pressed.connect(_take_all_from_container)
	container_root.add_child(take_all_button)
	var take_help := _label("더블클릭: 수량 선택  ·  Ctrl+클릭: 전체 이동", 8, COLOR_MUTED)
	take_help.position = Vector2(20, 575)
	take_help.size = Vector2(352, 14)
	take_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container_root.add_child(take_help)


func _build_bottom_dock() -> void:
	# The two left panes share a Tarkov-like character readout. It stays below the
	# interactive panels and leaves the container column unobstructed.
	status_footer = Panel.new()
	status_footer.name = "InventoryFooter"
	status_footer.position = Vector2(16, 665)
	status_footer.size = Vector2(784, 44)
	status_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_footer.add_theme_stylebox_override("panel", _panel_style(Color(0.008, 0.009, 0.009, 0.94), Color(0.24, 0.235, 0.2), 1, 0))
	modal_root.add_child(status_footer)

	var weight_readout := _status_readout("WeightReadout", "◆", "무게", Color(0.72, 0.72, 0.65), 0)
	weight_value_label = weight_readout.get_node("Value") as Label
	weight_capacity_label = weight_readout.get_node("SubValue") as Label

	var stamina_readout := _status_readout("StaminaReadout", "◆", "스태미나", Color(0.79, 0.66, 0.25), 1)
	stamina_value_label = stamina_readout.get_node("Value") as Label
	stamina_bar = stamina_readout.get_node("Meter") as ProgressBar

	var hunger_readout := _status_readout("HungerReadout", "◆", "포만감", Color(0.53, 0.72, 0.31), 2)
	hunger_value_label = hunger_readout.get_node("Value") as Label
	hunger_bar = hunger_readout.get_node("Meter") as ProgressBar

	var thirst_readout := _status_readout("ThirstReadout", "◆", "수분", Color(0.25, 0.67, 0.82), 3)
	thirst_value_label = thirst_readout.get_node("Value") as Label
	thirst_bar = thirst_readout.get_node("Meter") as ProgressBar
	var stress_readout := _status_readout("StressReadout", "↑", "스트레스", DungeonHUD.stress_color(0.0), 4)
	stress_readout.mouse_filter = Control.MOUSE_FILTER_PASS
	stress_readout.tooltip_text = "높을수록 불안정합니다 · %d부터 환청 · %d부터 환영" % [roundi(StressProfile.AUDIO_THRESHOLD), roundi(StressProfile.VISION_THRESHOLD)]
	stress_value_label = stress_readout.get_node("Value") as Label
	stress_bar = stress_readout.get_node("Meter") as ProgressBar

	# Kept for compatibility with older integrations that queried the compact
	# footer summary directly. The dedicated readouts above own the visible UI.
	_footer_status_label = _label("", 1, Color.TRANSPARENT)
	_footer_status_label.name = "LegacyFooterStatus"
	_footer_status_label.visible = false
	status_footer.add_child(_footer_status_label)


func _status_readout(node_name: String, glyph: String, title: String, accent: Color, column: int) -> Panel:
	var readout := Panel.new()
	readout.name = node_name
	var column_width := status_footer.size.x / 5.0
	readout.position = Vector2(float(column) * column_width, 0)
	readout.size = Vector2(column_width, 44)
	readout.clip_contents = true
	readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	readout.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, Color(0.12, 0.12, 0.105) if column > 0 else Color.TRANSPARENT, 1 if column > 0 else 0, 0))
	status_footer.add_child(readout)

	var icon := _label(glyph, 12, accent)
	icon.name = "Icon"
	icon.position = Vector2(6, 3)
	icon.size = Vector2(16, 21)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_child(icon)

	var title_label := _label(title, 10, Color(0.58, 0.59, 0.53))
	title_label.name = "Title"
	title_label.position = Vector2(24, 3)
	title_label.size = Vector2(56, 21)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_child(title_label)

	var value_label := _label("—", 12, accent)
	value_label.name = "Value"
	value_label.position = Vector2(84, 2)
	value_label.size = Vector2(column_width - 95.0, 22)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout.add_child(value_label)

	if column == 0:
		var subvalue := _label("가방 0 / 30칸", 8, Color(0.43, 0.44, 0.4))
		subvalue.name = "SubValue"
		subvalue.position = Vector2(11, 25)
		subvalue.size = Vector2(column_width - 22.0, 14)
		subvalue.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.add_child(subvalue)
	else:
		var meter := ProgressBar.new()
		meter.name = "Meter"
		meter.custom_minimum_size = Vector2.ZERO
		meter.position = Vector2(11, 30)
		meter.size = Vector2(column_width - 22.0, 6)
		meter.min_value = 0.0
		meter.max_value = 100.0
		meter.value = 100.0
		meter.show_percentage = false
		meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meter.add_theme_stylebox_override("background", _panel_style(Color(0.025, 0.027, 0.025), Color(0.13, 0.135, 0.12), 1, 0))
		meter.add_theme_stylebox_override("fill", _panel_style(accent.darkened(0.12), accent, 0, 0))
		readout.add_child(meter)
		# Theme resolution can restore ProgressBar's text-derived minimum after it
		# enters the tree. Clamp it again so the meter remains a slim status line.
		meter.position = Vector2(11, 30)
		meter.size = Vector2(column_width - 22.0, 6)
	return readout


func _build_quantity_dialog() -> void:
	quantity_dialog_root = ColorRect.new()
	quantity_dialog_root.name = "QuantityDialogRoot"
	quantity_dialog_root.color = Color(0.002, 0.004, 0.003, 0.86)
	quantity_dialog_root.mouse_filter = Control.MOUSE_FILTER_STOP
	quantity_dialog_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	quantity_dialog_root.z_index = 300
	quantity_dialog_root.visible = false
	overlay_root.add_child(quantity_dialog_root)

	var dialog_panel := Panel.new()
	dialog_panel.name = "QuantityDialogPanel"
	dialog_panel.anchor_left = 0.5
	dialog_panel.anchor_top = 0.5
	dialog_panel.anchor_right = 0.5
	dialog_panel.anchor_bottom = 0.5
	dialog_panel.offset_left = -216.0
	dialog_panel.offset_top = -126.0
	dialog_panel.offset_right = 216.0
	dialog_panel.offset_bottom = 126.0
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.018, 0.022, 0.02, 1.0), Color(0.35, 0.38, 0.29), 2, 0))
	quantity_dialog_root.add_child(dialog_panel)

	_quantity_title_label = _label("수량 선택", 17, Color(0.85, 0.87, 0.78))
	_quantity_title_label.position = Vector2(18, 14)
	_quantity_title_label.size = Vector2(396, 28)
	_quantity_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_panel.add_child(_quantity_title_label)
	_quantity_info_label = _label("", 11, Color(0.56, 0.6, 0.52))
	_quantity_info_label.position = Vector2(18, 50)
	_quantity_info_label.size = Vector2(396, 42)
	_quantity_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quantity_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialog_panel.add_child(_quantity_info_label)

	var amount_label := _label("가져올 수량", 11, Color(0.68, 0.71, 0.63))
	amount_label.position = Vector2(76, 105)
	amount_label.size = Vector2(116, 34)
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dialog_panel.add_child(amount_label)
	quantity_spinbox = SpinBox.new()
	quantity_spinbox.name = "QuantitySpinBox"
	quantity_spinbox.position = Vector2(202, 105)
	quantity_spinbox.size = Vector2(154, 34)
	quantity_spinbox.min_value = 1.0
	quantity_spinbox.max_value = 1.0
	quantity_spinbox.step = 1.0
	quantity_spinbox.value = 1.0
	quantity_spinbox.allow_greater = false
	quantity_spinbox.allow_lesser = false
	quantity_spinbox.update_on_text_changed = true
	quantity_spinbox.suffix = " 개"
	quantity_spinbox.add_theme_font_size_override("font_size", 13)
	dialog_panel.add_child(quantity_spinbox)
	var quantity_line_edit := quantity_spinbox.get_line_edit()
	quantity_line_edit.add_theme_color_override("font_color", COLOR_TEXT)
	quantity_line_edit.add_theme_color_override("caret_color", COLOR_ACTIVE)
	quantity_line_edit.add_theme_stylebox_override("normal", _panel_style(Color(0.03, 0.035, 0.031), Color(0.25, 0.275, 0.22), 1, 0))
	quantity_line_edit.add_theme_stylebox_override("focus", _panel_style(Color(0.04, 0.047, 0.04), COLOR_ACTIVE, 1, 0))

	quantity_confirm_button = _action_button("확인", Vector2(72, 178), Vector2(136, 38), Color(0.09, 0.115, 0.073))
	quantity_confirm_button.name = "QuantityConfirmButton"
	quantity_confirm_button.pressed.connect(_on_quantity_confirm_pressed)
	dialog_panel.add_child(quantity_confirm_button)
	quantity_cancel_button = _action_button("취소", Vector2(224, 178), Vector2(136, 38), Color(0.07, 0.075, 0.067))
	quantity_cancel_button.name = "QuantityCancelButton"
	quantity_cancel_button.pressed.connect(_on_quantity_cancel_pressed)
	dialog_panel.add_child(quantity_cancel_button)


func _set_container_mode_layout(container_active: bool) -> void:
	if equipment_root == null or inventory_root == null or container_root == null or _utility_rail == null:
		return
	container_root.visible = container_active
	_utility_rail.visible = container_active
	var footer := modal_root.get_node_or_null("InventoryFooter") as Control
	if container_active:
		equipment_root.position = Vector2(16, 47)
		inventory_root.position = Vector2(408, 47)
		if footer != null:
			footer.position = Vector2(16, 665)
		if detail_root != null:
			detail_root.position = Vector2(850, 166)
	else:
		# The 784px character/equipment pair is centered when no chest is open;
		# there is no inactive "no chest" column or transfer gap.
		equipment_root.position = Vector2(248, 47)
		inventory_root.position = Vector2(640, 47)
		if footer != null:
			footer.position = Vector2(248, 665)
		if detail_root != null:
			detail_root.position = Vector2(716, 166)
	_apply_health_tab_layout()


func _load_visual_assets() -> void:
	if ResourceLoader.exists(ITEM_ATLAS_PATH):
		_item_atlas = load(ITEM_ATLAS_PATH) as Texture2D


func _add_micro_grid_cell(parent: Control, position_value: Vector2, size_value: Vector2, background: Color, node_name := "") -> void:
	var cell := Panel.new()
	if not node_name.is_empty():
		cell.name = node_name
	cell.position = position_value
	cell.size = size_value
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.z_index = 3
	cell.add_theme_stylebox_override("panel", _panel_style(background, Color(0.125, 0.14, 0.12, 0.9), 1, 0))
	parent.add_child(cell)


func _ornate_panel_style(background: Color) -> StyleBoxFlat:
	var style := _panel_style(background, Color(0.36, 0.37, 0.35), 2, 0)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.72)
	style.shadow_size = 8
	style.shadow_offset = Vector2(3, 5)
	return style


func _decorate_ornate_frame(parent: Control, frame_size: Vector2) -> void:
	var inset := 5.0
	var corner := 34.0
	var corner_paths: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(inset, corner), Vector2(inset, inset), Vector2(corner, inset), Vector2(corner + 8.0, inset + 8.0)]),
		PackedVector2Array([Vector2(frame_size.x - corner - 8.0, inset + 8.0), Vector2(frame_size.x - corner, inset), Vector2(frame_size.x - inset, inset), Vector2(frame_size.x - inset, corner)]),
		PackedVector2Array([Vector2(inset, frame_size.y - corner), Vector2(inset, frame_size.y - inset), Vector2(corner, frame_size.y - inset), Vector2(corner + 8.0, frame_size.y - inset - 8.0)]),
		PackedVector2Array([Vector2(frame_size.x - corner - 8.0, frame_size.y - inset - 8.0), Vector2(frame_size.x - corner, frame_size.y - inset), Vector2(frame_size.x - inset, frame_size.y - inset), Vector2(frame_size.x - inset, frame_size.y - corner)])
	]
	for path in corner_paths:
		var line := Line2D.new()
		line.width = 1.5
		line.default_color = Color(0.59, 0.57, 0.49, 0.9)
		line.points = path
		line.antialiased = true
		line.z_index = 40
		parent.add_child(line)


func _add_character_ring_ornaments(parent: Control) -> void:
	var centers := [Vector2(55, 188), Vector2(337, 188), Vector2(196, 48), Vector2(196, 335)]
	for center in centers:
		var ornament := Polygon2D.new()
		ornament.name = "CharacterRingOrnament"
		ornament.polygon = PackedVector2Array([
			center + Vector2(0, -11),
			center + Vector2(11, 0),
			center + Vector2(0, 11),
			center + Vector2(-11, 0)
		])
		ornament.color = Color(0.12, 0.12, 0.105, 1.0)
		ornament.z_index = 2
		parent.add_child(ornament)
		var border := Line2D.new()
		border.width = 1.5
		border.default_color = Color(0.47, 0.44, 0.35, 0.95)
		border.points = PackedVector2Array([
			center + Vector2(0, -11),
			center + Vector2(11, 0),
			center + Vector2(0, 11),
			center + Vector2(-11, 0),
			center + Vector2(0, -11)
		])
		border.antialiased = true
		border.z_index = 3
		parent.add_child(border)


func _add_empty_equipment_socket(parent: Control, position_value: Vector2) -> void:
	var socket := Panel.new()
	socket.name = "DecorativeEquipmentSocket"
	socket.position = position_value
	socket.size = Vector2(28, 28)
	socket.pivot_offset = socket.size * 0.5
	socket.rotation = PI * 0.25
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	socket.add_theme_stylebox_override("panel", _panel_style(Color(0.014, 0.015, 0.014, 0.9), Color(0.24, 0.245, 0.22), 1, 0))
	parent.add_child(socket)


func _bind_models(model: ExpeditionInventory, container: LootContainer) -> void:
	_disconnect_models()
	inventory_model = model
	loot_container = container
	if inventory_model != null and not inventory_model.changed.is_connected(_on_model_changed):
		inventory_model.changed.connect(_on_model_changed)
	if loot_container != null and not loot_container.changed.is_connected(_on_container_changed):
		loot_container.changed.connect(_on_container_changed)
	if loot_container != null and not loot_container.stack_identified.is_connected(_on_container_stack_identified):
		loot_container.stack_identified.connect(_on_container_stack_identified)


func _disconnect_models() -> void:
	if inventory_model != null and inventory_model.changed.is_connected(_on_model_changed):
		inventory_model.changed.disconnect(_on_model_changed)
	if loot_container != null and loot_container.changed.is_connected(_on_container_changed):
		loot_container.changed.disconnect(_on_container_changed)
	if loot_container != null and loot_container.stack_identified.is_connected(_on_container_stack_identified):
		loot_container.stack_identified.disconnect(_on_container_stack_identified)


func _on_model_changed() -> void:
	_refresh()


func _on_container_changed() -> void:
	_refresh()


func _on_container_stack_identified(index: int, item_id: String) -> void:
	if loot_container == null or index < 0 or index >= loot_container.items.size():
		return
	var quantity := int(loot_container.items[index].get("quantity", 0))
	var suffix := " · 상자 조사를 마쳤습니다." if not loot_container.has_unidentified_items() else ""
	_action_status_label.text = "확인됨: %s%s%s" % [
		ExpeditionInventory.get_item_name(item_id),
		" ×%d" % quantity if quantity > 1 else "",
		suffix
	]


func _refresh() -> void:
	if not _built:
		return
	_validate_selection()
	_refresh_tactical_summary()
	_refresh_equipment_slots()
	_refresh_inventory_slots()
	_refresh_container_slots()
	_refresh_action_buttons()
	_refresh_bottom_dock()
	_restore_selected_details()
	_refresh_open_item_details()
	_apply_health_tab_layout()


func _refresh_tactical_summary() -> void:
	if _character_stats_label == null or _character_stat_values_label == null or _quick_loadout_label == null:
		return
	var actor_status := _actor_status_snapshot()
	if health_panel != null:
		health_panel.show_snapshot(actor_status.get("body_health", {}), inventory_model)
	var health := float(actor_status.get("health", 100.0))
	var max_health := maxf(1.0, float(actor_status.get("max_health", 100.0)))
	if inventory_model == null:
		_character_stat_values_label.text = "15\n15\n15\n15\n15\n\n%d / %d\n0.0 KG" % [roundi(health), roundi(max_health)]
		_quick_loadout_label.text = "장착 0/5  ·  회수 0"
		return
	var equipped_count := 0
	for equipment_slot in ExpeditionInventory.EQUIPMENT_ORDER:
		if not str(inventory_model.equipment.get(equipment_slot, "")).is_empty():
			equipped_count += 1
	_character_stat_values_label.text = "15\n15\n15\n15\n15\n\n%d / %d\n%.1f KG" % [roundi(health), roundi(max_health), inventory_model.total_weight()]
	_quick_loadout_label.text = "장착 %d/5  ·  회수 %d" % [equipped_count, inventory_model.raid_loot_value()]


func _refresh_equipment_slots() -> void:
	for index in range(equipment_slot_buttons.size()):
		var button := equipment_slot_buttons[index]
		var equipment_slot := equipment_slot_keys[index]
		var slot_label := str(ExpeditionInventory.EQUIPMENT_LABELS.get(equipment_slot, equipment_slot))
		var item_id := ""
		if inventory_model != null:
			item_id = str(inventory_model.equipment.get(equipment_slot, ""))
		if item_id.is_empty():
			button.tooltip_text = ""
			button.disabled = false
			button.visible = true
			_set_button_art(button, "", 0, slot_label)
			_set_slot_metadata(button, "equipment", index, "", 0)
			_apply_slot_style(button, "", selected_source == "equipment" and selected_equipment_slot == equipment_slot)
			continue
		button.tooltip_text = ""
		button.disabled = false
		button.visible = true
		_set_button_art(button, item_id, 1, slot_label)
		_set_slot_metadata(button, "equipment", index, item_id, 1)
		_apply_slot_style(button, item_id, selected_source == "equipment" and selected_equipment_slot == equipment_slot)


func _refresh_inventory_slots() -> void:
	var occupied := 0
	var total_units := 0
	if inventory_model != null:
		occupied = inventory_model.slots.size()
		for stack in inventory_model.slots:
			total_units += int(stack.get("quantity", 0))
	var stacks: Array = inventory_model.slots if inventory_model != null else []
	var bag_rows: Array[float] = []
	for row_index in range(BAG_VISUAL_ROWS):
		bag_rows.append(row_index * (BAG_CELL_SIZE.y + GRID_GAP))
	_layout_stack_buttons(
		inventory_slot_buttons,
		stacks,
		"inventory",
		BAG_VISUAL_COLUMNS,
		BAG_VISUAL_ROWS,
		BAG_CELL_SIZE,
		bag_rows
	)
	var weight := inventory_model.total_weight() if inventory_model != null else 0.0
	_bag_status_label.text = "물품 %02d종  ·  %d개  ·  %.1fKG" % [occupied, total_units, weight]


func _refresh_container_slots() -> void:
	var stacks: Array = loot_container.items if loot_container != null else []
	var storage_rows: Array[float] = []
	for row_index in range(STORAGE_VISUAL_ROWS):
		storage_rows.append(row_index * (STORAGE_CELL_SIZE.y + GRID_GAP))
	_layout_stack_buttons(
		container_slot_buttons,
		stacks,
		"container",
		STORAGE_VISUAL_COLUMNS,
		STORAGE_VISUAL_ROWS,
		STORAGE_CELL_SIZE,
		storage_rows
	)
	if loot_container == null:
		_container_title_label.text = ""
		_container_status_label.text = ""
		_container_subtitle_label.text = ""
	else:
		_container_title_label.text = loot_container.title
		var concealed_count := loot_container.unidentified_stack_count()
		var identified_count := loot_container.identified_stack_count()
		if concealed_count > 0:
			# Do not expose aggregate unit quantities before their stacks have been
			# inspected; even the status text follows the same concealment contract.
			_container_status_label.text = "물품 %d종  ·  확인 %d/%d" % [loot_container.items.size(), identified_count, loot_container.items.size()]
		else:
			_container_status_label.text = "물품 %d종  ·  %d개" % [loot_container.items.size(), loot_container.item_count()]
		if loot_container.is_empty():
			_container_subtitle_label.text = "%s  ·  빈 상자" % loot_container.subtitle
		elif concealed_count > 0:
			_container_subtitle_label.text = "%s  ·  뒤적이는 중…  %d/%d 물품 확인" % [loot_container.subtitle, identified_count, loot_container.items.size()]
		else:
			_container_subtitle_label.text = "%s  ·  더블클릭 가져오기  ·  Ctrl+클릭 전체" % loot_container.subtitle


func _refresh_action_buttons() -> void:
	var context := _selected_context()
	var item_id := str(context.get("id", ""))
	var definition := ExpeditionInventory.get_item_definition(item_id)
	var category := str(definition.get("category", ""))
	detail_button.disabled = item_id.is_empty() or bool(context.get("concealed", false))
	equip_button.disabled = selected_source != "inventory" or str(definition.get("equip_slot", "")).is_empty()
	unequip_button.disabled = selected_source != "equipment" or item_id.is_empty()
	use_button.disabled = selected_source != "inventory" or category != "consumable"
	use_button.text = "학습" if str(definition.get("effect", "")) == "learn_spell" else "사용"
	transfer_button.visible = loot_container != null or selected_source == "equipment"
	if selected_source == "equipment":
		transfer_button.disabled = item_id.is_empty() or inventory_model == null
		transfer_button.text = "인벤토리에 넣기"
	else:
		transfer_button.disabled = loot_container == null or (selected_source != "inventory" and selected_source != "container") or item_id.is_empty()
		transfer_button.text = "인벤토리로 이동" if selected_source == "container" else "상자로 이동"
	var search_incomplete := loot_container != null and loot_container.has_unidentified_items()
	take_all_button.disabled = loot_container == null or loot_container.is_empty() or inventory_model == null or search_incomplete
	take_all_button.text = "뒤적이는 중…" if search_incomplete else "모두 가져오기"


func _set_item_slot(button: Button, source: String, index: int, item_id: String, quantity: int, selected: bool) -> void:
	button.text = ""
	button.visible = true
	_set_button_art(button, item_id, quantity)
	button.tooltip_text = ""
	button.disabled = false
	_set_slot_metadata(button, source, index, item_id, quantity)
	_apply_slot_style(button, item_id, selected)


func _set_concealed_container_slot(button: Button, index: int) -> void:
	# Retain a semantic '?' in the Button itself while a child label renders it
	# at a larger size without inflating the tactical grid cell's minimum height.
	button.text = "?"
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
	button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
	button.visible = true
	button.disabled = false
	button.tooltip_text = ""
	_set_button_art(button, "", 0)
	var unknown_marker := button.get_node_or_null("UnknownMarker") as Label
	if unknown_marker != null:
		unknown_marker.visible = true
	_set_slot_metadata(button, "container", index, "", 0)
	button.set_meta("concealed", true)
	_apply_concealed_slot_style(button)


func _set_empty_slot(button: Button, source: String, index: int) -> void:
	button.text = ""
	button.visible = false
	button.tooltip_text = "빈 슬롯"
	button.disabled = true
	_set_button_art(button, "", 0)
	_set_slot_metadata(button, source, index, "", 0)
	_apply_slot_style(button, "", false)


func _apply_concealed_slot_style(button: Button) -> void:
	var background := Color(0.018, 0.021, 0.019, 0.99)
	var border := Color(0.25, 0.27, 0.22)
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 1, 0))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.045), border.lightened(0.12), 2, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(background, border, 1, 0))
	button.add_theme_stylebox_override("disabled", _panel_style(background, border, 1, 0))


func _layout_stack_buttons(
	buttons: Array[Button],
	stacks: Array,
	source: String,
	columns: int,
	rows: int,
	cell_size: Vector2,
	row_positions: Array
) -> void:
	var occupancy: Array[bool] = []
	occupancy.resize(columns * rows)
	occupancy.fill(false)
	for index in range(buttons.size()):
		var button := buttons[index]
		if index >= stacks.size() or not stacks[index] is Dictionary:
			_set_empty_slot(button, source, index)
			continue
		var stack := stacks[index] as Dictionary
		var item_id := str(stack.get("id", ""))
		var concealed := source == "container" and loot_container != null and not loot_container.is_stack_identified(index)
		# Concealed stacks all occupy the same footprint so their authored item
		# shape cannot leak before identification.
		var desired_span := Vector2i.ONE if concealed else _item_ui_span(item_id)
		var placement := _find_visual_placement(occupancy, columns, rows, desired_span, source == "inventory")
		if placement.is_empty():
			# The data model counts stacks rather than occupied art cells. There are
			# always at least 30/20 logical buttons, so a crowded view degrades only
			# this item's visual footprint to 1x1 instead of hiding the interaction.
			placement = _find_visual_placement(occupancy, columns, rows, Vector2i.ONE, false)
		if placement.is_empty():
			# Defensive last resort for future capacity changes: keep every logical
			# button reachable in a compact overflow strip at the bottom edge.
			button.position = Vector2((index % columns) * (cell_size.x + GRID_GAP), maxf(0.0, row_positions[-1] - cell_size.y * 0.35))
			button.size = Vector2(cell_size.x, cell_size.y * 0.65)
		else:
			var cell := placement.get("cell", Vector2i.ZERO) as Vector2i
			var span := placement.get("span", Vector2i.ONE) as Vector2i
			var start_y := float(row_positions[cell.y])
			var end_row := cell.y + span.y - 1
			var end_y := float(row_positions[end_row]) + cell_size.y
			button.position = Vector2(cell.x * (cell_size.x + GRID_GAP), start_y)
			button.size = Vector2(span.x * cell_size.x + (span.x - 1) * GRID_GAP, end_y - start_y)
		if concealed:
			_set_concealed_container_slot(button, index)
		else:
			_set_item_slot(button, source, index, item_id, int(stack.get("quantity", 1)), selected_source == source and selected_index == index)


func _find_visual_placement(occupancy: Array[bool], columns: int, rows: int, requested_span: Vector2i, bag_layout: bool) -> Dictionary:
	var span := Vector2i(clampi(requested_span.x, 1, columns), clampi(requested_span.y, 1, rows))
	var candidate_rows: Array[int] = []
	for row_index in range(rows):
		candidate_rows.append(row_index)
	for row_index in candidate_rows:
		if row_index + span.y > rows:
			continue
		for column_index in range(columns - span.x + 1):
			if not _visual_cells_available(occupancy, columns, Vector2i(column_index, row_index), span):
				continue
			_mark_visual_cells(occupancy, columns, Vector2i(column_index, row_index), span)
			return {"cell": Vector2i(column_index, row_index), "span": span}
	if span != Vector2i.ONE:
		return _find_visual_placement(occupancy, columns, rows, Vector2i.ONE, bag_layout)
	return {}


func _visual_cells_available(occupancy: Array[bool], columns: int, cell: Vector2i, span: Vector2i) -> bool:
	for row_offset in range(span.y):
		for column_offset in range(span.x):
			if occupancy[(cell.y + row_offset) * columns + cell.x + column_offset]:
				return false
	return true


func _mark_visual_cells(occupancy: Array[bool], columns: int, cell: Vector2i, span: Vector2i) -> void:
	for row_offset in range(span.y):
		for column_offset in range(span.x):
			occupancy[(cell.y + row_offset) * columns + cell.x + column_offset] = true


func _item_ui_span(item_id: String) -> Vector2i:
	var value: Variant = ExpeditionInventory.get_item_definition(item_id).get("ui_span", Vector2i.ONE)
	if value is Vector2i:
		return value as Vector2i
	if value is Vector2:
		var vector := value as Vector2
		return Vector2i(maxi(1, roundi(vector.x)), maxi(1, roundi(vector.y)))
	if value is Array and (value as Array).size() >= 2:
		var values := value as Array
		return Vector2i(maxi(1, int(values[0])), maxi(1, int(values[1])))
	return Vector2i.ONE


func _set_button_art(button: Button, item_id: String, quantity: int, equipment_caption := "") -> void:
	var art := button.get_node_or_null("ItemArt") as TextureRect
	var name_label := button.get_node_or_null("ItemName") as Label
	var quantity_label := button.get_node_or_null("Quantity") as Label
	var caption_label := button.get_node_or_null("SlotCaption") as Label
	var unknown_marker := button.get_node_or_null("UnknownMarker") as Label
	if unknown_marker != null:
		unknown_marker.visible = false
	if art != null:
		art.texture = _item_texture(item_id) if not item_id.is_empty() else null
		art.visible = not item_id.is_empty()
	if name_label != null:
		# The reference grid keeps cells image-only; names live in the floating
		# inspection card and tooltips instead of covering the item artwork.
		name_label.text = ""
		name_label.visible = false
	if quantity_label != null:
		quantity_label.text = "×%d" % quantity if quantity > 1 else ""
		quantity_label.visible = quantity > 1
	if caption_label != null:
		caption_label.text = equipment_caption
		caption_label.visible = not equipment_caption.is_empty()


func _item_texture(item_id: String) -> Texture2D:
	if item_id.is_empty():
		return null
	if _atlas_texture_cache.has(item_id):
		return _atlas_texture_cache[item_id] as Texture2D
	var definition := ExpeditionInventory.get_item_definition(item_id)
	var icon_path := str(definition.get("icon_path", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path, "Texture2D"):
		var icon_texture := load(icon_path) as Texture2D
		_atlas_texture_cache[item_id] = icon_texture
		return icon_texture
	if _item_atlas != null and definition.has("atlas_cell"):
		var atlas_cell: Variant = definition.get("atlas_cell", Vector2i.ZERO)
		var cell := atlas_cell as Vector2i if atlas_cell is Vector2i else Vector2i.ZERO
		var cell_size := Vector2(float(_item_atlas.get_width()) / float(ATLAS_GRID_SIZE.x), float(_item_atlas.get_height()) / float(ATLAS_GRID_SIZE.y))
		var texture := AtlasTexture.new()
		texture.atlas = _item_atlas
		texture.region = Rect2(Vector2(cell) * cell_size, cell_size)
		_atlas_texture_cache[item_id] = texture
		return texture
	if _fallback_texture_cache.has(item_id):
		return _fallback_texture_cache[item_id] as Texture2D
	var fallback := GradientTexture2D.new()
	var gradient := Gradient.new()
	var base_color := _rarity_color(str(ExpeditionInventory.get_item_definition(item_id).get("rarity", "common")))
	gradient.set_color(0, base_color.darkened(0.72))
	gradient.set_color(1, base_color.darkened(0.18))
	fallback.gradient = gradient
	fallback.width = 128
	fallback.height = 128
	fallback.fill_from = Vector2(0.1, 0.1)
	fallback.fill_to = Vector2(0.9, 0.9)
	_fallback_texture_cache[item_id] = fallback
	return fallback


func _refresh_bottom_dock() -> void:
	for slot_index in range(_quickbar_art_rects.size()):
		var art := _quickbar_art_rects[slot_index]
		var quantity_label := _quickbar_quantity_labels[slot_index]
		if inventory_model == null or slot_index >= inventory_model.slots.size():
			art.texture = null
			quantity_label.text = ""
			continue
		var stack := inventory_model.slots[slot_index]
		art.texture = _item_texture(str(stack.get("id", "")))
		var quantity := int(stack.get("quantity", 1))
		quantity_label.text = "×%d" % quantity if quantity > 1 else ""
	refresh_status_readout()


func refresh_status_readout() -> void:
	if not _built or weight_value_label == null:
		return
	var weight := inventory_model.total_weight() if inventory_model != null else 0.0
	var occupied_slots := inventory_model.slots.size() if inventory_model != null else 0
	weight_value_label.text = "%.1f KG" % weight
	weight_capacity_label.text = "가방 %d / %d칸" % [occupied_slots, ExpeditionInventory.MAX_SLOTS]

	var actor_status := _actor_status_snapshot()
	var max_stamina := maxf(1.0, float(actor_status.get("max_stamina", 100.0)))
	var stamina := clampf(float(actor_status.get("stamina", max_stamina)), 0.0, max_stamina)
	_set_status_meter(stamina_bar, stamina_value_label, stamina, max_stamina, Color(0.79, 0.66, 0.25))

	var survival := ExpeditionSession.get_survival_snapshot()
	var maximum := maxf(1.0, float(survival.get("maximum", 100.0)))
	var hunger := clampf(float(survival.get("hunger", maximum)), 0.0, maximum)
	var thirst := clampf(float(survival.get("thirst", maximum)), 0.0, maximum)
	_set_status_meter(hunger_bar, hunger_value_label, hunger, maximum, _need_readout_color(hunger, Color(0.53, 0.72, 0.31)))
	_set_status_meter(thirst_bar, thirst_value_label, thirst, maximum, _need_readout_color(thirst, Color(0.25, 0.67, 0.82)))
	var stress_maximum := maxf(1.0, float(survival.get("stress_maximum", 100.0)))
	var stress := clampf(float(survival.get("stress", 0.0)), 0.0, stress_maximum)
	_set_status_meter(stress_bar, stress_value_label, stress, stress_maximum, DungeonHUD.stress_color(stress / stress_maximum * StressProfile.MAX_STRESS))

	if _footer_status_label != null:
		_footer_status_label.text = "무게 %.1f KG · 기력 %d/%d · 포만감 %d/%d · 수분 %d/%d · 스트레스 %d/%d" % [
			weight,
			roundi(stamina), roundi(max_stamina),
			roundi(hunger), roundi(maximum),
			roundi(thirst), roundi(maximum),
			roundi(stress), roundi(stress_maximum)
		]


func _actor_status_snapshot() -> Dictionary:
	var snapshot := {
		"health": 100.0,
		"max_health": 100.0,
		"stamina": 100.0,
		"max_stamina": 100.0
	}
	if not _status_provider.is_valid():
		return snapshot
	var supplied: Variant = _status_provider.call()
	if supplied is Dictionary:
		for key in supplied:
			snapshot[key] = supplied[key]
	return snapshot


func _set_status_meter(bar: ProgressBar, label: Label, current: float, maximum: float, accent: Color) -> void:
	if bar == null or label == null:
		return
	bar.max_value = maximum
	bar.value = current
	bar.add_theme_stylebox_override("fill", _panel_style(accent.darkened(0.12), accent, 0, 0))
	label.text = "%d / %d" % [roundi(current), roundi(maximum)]
	label.add_theme_color_override("font_color", accent)


func _need_readout_color(value: float, normal: Color) -> Color:
	if value <= 15.0:
		return Color(0.88, 0.27, 0.19)
	if value <= 30.0:
		return Color(0.9, 0.59, 0.16)
	return normal


func _set_slot_metadata(button: Button, source: String, index: int, item_id: String, quantity: int) -> void:
	button.set_meta("source", source)
	button.set_meta("slot_index", index)
	button.set_meta("item_id", item_id)
	button.set_meta("quantity", quantity)
	button.set_meta("concealed", false)


func _apply_slot_style(button: Button, item_id: String, selected: bool) -> void:
	var border := Color(0.25, 0.22, 0.16)
	var background := Color(0.031, 0.032, 0.029, 0.99)
	if not item_id.is_empty():
		var rarity := str(ExpeditionInventory.get_item_definition(item_id).get("rarity", "common"))
		match rarity:
			"uncommon":
				border = Color(0.29, 0.48, 0.33)
			"rare":
				border = Color(0.27, 0.48, 0.68)
			"legendary":
				border = Color(0.82, 0.52, 0.13)
			_:
				border = Color(0.36, 0.39, 0.3)
	if selected:
		border = COLOR_ACTIVE
		background = Color(0.095, 0.105, 0.068, 0.99)
	button.add_theme_stylebox_override("normal", _panel_style(background, border, 3 if selected else 1, 0))
	button.add_theme_stylebox_override("hover", _panel_style(background.lightened(0.07), border.lightened(0.22), 2, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(background.darkened(0.15), COLOR_ACTIVE.lightened(0.18), 2, 0))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.023, 0.024, 0.022, 0.92), Color(0.14, 0.145, 0.125), 1, 0))


func _on_inventory_slot_pressed(index: int) -> void:
	if inventory_model == null or index < 0 or index >= inventory_model.slots.size():
		return
	selected_source = "inventory"
	selected_index = index
	selected_equipment_slot = ""
	_action_status_label.text = "인벤토리 아이템을 선택했습니다."
	_refresh()


func _on_container_slot_pressed(index: int) -> void:
	if _skip_container_press_index == index:
		_skip_container_press_index = -1
		return
	if loot_container == null or index < 0 or index >= loot_container.items.size():
		return
	if not loot_container.is_stack_identified(index):
		_clear_selection()
		_action_status_label.text = "아직 정체를 확인하는 중입니다."
		_refresh()
		return
	selected_source = "container"
	selected_index = index
	selected_equipment_slot = ""
	_action_status_label.text = "상자 아이템을 선택했습니다."
	_refresh()


func _on_container_slot_gui_input(event: InputEvent, index: int) -> void:
	if quantity_dialog_root != null and quantity_dialog_root.visible:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		open_item_details("container", index)
		return
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	var take_entire_stack := mouse_event.ctrl_pressed
	if not take_entire_stack and not mouse_event.double_click:
		return
	if loot_container == null or inventory_model == null or index < 0 or index >= loot_container.items.size():
		return
	if not loot_container.is_stack_identified(index):
		_clear_selection()
		_action_status_label.text = "이 물품은 아직 정체를 확인하는 중입니다."
		_refresh()
		return
	_arm_container_press_suppression(index)
	selected_source = "container"
	selected_index = index
	selected_equipment_slot = ""
	var stack := loot_container.items[index]
	var stack_quantity := int(stack.get("quantity", 0))
	if stack_quantity <= 0:
		return
	if take_entire_stack or stack_quantity == 1:
		_take_container_quantity(index, stack_quantity if take_entire_stack else 1)
	else:
		_refresh()
		_show_quantity_dialog(index)


func _arm_container_press_suppression(index: int) -> void:
	_skip_container_press_index = index
	if not is_inside_tree():
		return
	var timer := get_tree().create_timer(0.35, true, false, true)
	timer.timeout.connect(_expire_container_press_suppression.bind(index))


func _expire_container_press_suppression(index: int) -> void:
	if _skip_container_press_index == index:
		_skip_container_press_index = -1


func _show_quantity_dialog(index: int) -> void:
	if loot_container == null or index < 0 or index >= loot_container.items.size():
		return
	if not loot_container.is_stack_identified(index):
		_action_status_label.text = "정체가 밝혀진 물품만 가져올 수 있습니다."
		return
	var stack := loot_container.items[index]
	var item_id := str(stack.get("id", ""))
	var stack_quantity := int(stack.get("quantity", 0))
	if item_id.is_empty() or stack_quantity <= 1:
		return
	_quantity_source_index = index
	_quantity_source_item_id = item_id
	_quantity_title_label.text = ExpeditionInventory.get_item_name(item_id)
	_quantity_info_label.text = "상자에 %d개 있습니다. 인벤토리로 옮길 수량을 선택하십시오." % stack_quantity
	quantity_spinbox.min_value = 1.0
	quantity_spinbox.max_value = float(stack_quantity)
	quantity_spinbox.value = 1.0
	quantity_dialog_root.visible = true
	quantity_spinbox.get_line_edit().select_all()
	quantity_spinbox.get_line_edit().grab_focus()


func _hide_quantity_dialog() -> void:
	if quantity_dialog_root == null:
		return
	quantity_dialog_root.visible = false
	_quantity_source_index = -1
	_quantity_source_item_id = ""
	_skip_container_press_index = -1
	if quantity_spinbox != null:
		quantity_spinbox.get_line_edit().release_focus()


func _on_quantity_confirm_pressed() -> void:
	var source_index := _quantity_source_index
	var expected_item_id := _quantity_source_item_id
	var requested_quantity := maxi(1, roundi(quantity_spinbox.value))
	if loot_container == null or source_index < 0 or source_index >= loot_container.items.size():
		_hide_quantity_dialog()
		_action_status_label.text = "상자 내용이 바뀌어 수량 이동을 취소했습니다."
		return
	var current_stack := loot_container.items[source_index]
	if not loot_container.is_stack_identified(source_index) or str(current_stack.get("id", "")) != expected_item_id:
		_hide_quantity_dialog()
		_action_status_label.text = "상자 내용이 바뀌어 수량 이동을 취소했습니다."
		return
	requested_quantity = mini(requested_quantity, int(current_stack.get("quantity", 0)))
	_hide_quantity_dialog()
	_take_container_quantity(source_index, requested_quantity)


func _on_quantity_cancel_pressed() -> void:
	_hide_quantity_dialog()
	_action_status_label.text = "수량 선택을 취소했습니다."


func _take_container_quantity(index: int, requested_quantity: int) -> int:
	if inventory_model == null or loot_container == null or index < 0 or index >= loot_container.items.size() or requested_quantity <= 0:
		return 0
	if not loot_container.is_stack_identified(index):
		_action_status_label.text = "정체가 밝혀진 물품만 가져올 수 있습니다."
		return 0
	var stack := loot_container.items[index]
	var item_id := str(stack.get("id", ""))
	var available := int(stack.get("quantity", 0))
	var requested := mini(requested_quantity, available)
	var moved := _move_container_to_inventory(index, requested)
	var item_name := ExpeditionInventory.get_item_name(item_id)
	if moved <= 0:
		_action_status_label.text = "인벤토리가 가득 찼습니다. %s ×%d은(는) 상자에 그대로 유지됩니다." % [item_name, requested]
	elif moved < requested:
		_action_status_label.text = "%s ×%d만 옮겼습니다. 용량 부족으로 나머지 ×%d은(는) 상자에 안전하게 남아 있습니다." % [item_name, moved, requested - moved]
	else:
		_action_status_label.text = "%s ×%d을(를) 인벤토리로 옮겼습니다." % [item_name, moved]
	_clear_selection()
	_refresh()
	return moved


func _on_equipment_slot_pressed(equipment_slot: String) -> void:
	if _skip_equipment_press_slot == equipment_slot:
		_skip_equipment_press_slot = ""
		return
	selected_source = "equipment"
	selected_index = equipment_slot_keys.find(equipment_slot)
	selected_equipment_slot = equipment_slot
	_action_status_label.text = "장비 슬롯을 선택했습니다."
	_refresh()


func _on_equipment_slot_gui_input(event: InputEvent, equipment_slot: String) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event != null and mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
		open_item_details("equipment", -1, equipment_slot)
		return
	if mouse_event == null or mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed or not mouse_event.double_click:
		return
	_skip_equipment_press_slot = equipment_slot
	selected_source = "equipment"
	selected_index = equipment_slot_keys.find(equipment_slot)
	selected_equipment_slot = equipment_slot
	_unequip_selected()


func _on_inventory_slot_hovered(index: int) -> void:
	_show_context_details(_item_context("inventory", index, ""))


func _on_container_slot_hovered(index: int) -> void:
	_show_context_details(_item_context("container", index, ""))


func _on_equipment_slot_hovered(equipment_slot: String) -> void:
	_show_context_details(_item_context("equipment", -1, equipment_slot))


func _on_clear_selection_pressed() -> void:
	_clear_selection()
	_action_status_label.text = "선택을 해제했습니다."
	_refresh()


func _clear_selection() -> void:
	selected_source = ""
	selected_index = -1
	selected_equipment_slot = ""


func _validate_selection() -> void:
	match selected_source:
		"inventory":
			if inventory_model == null or selected_index < 0 or selected_index >= inventory_model.slots.size():
				_clear_selection()
		"container":
			if loot_container == null or selected_index < 0 or selected_index >= loot_container.items.size() or not loot_container.is_stack_identified(selected_index):
				_clear_selection()
		"equipment":
			if inventory_model == null or not inventory_model.equipment.has(selected_equipment_slot):
				_clear_selection()


func _selected_context() -> Dictionary:
	return _item_context(selected_source, selected_index, selected_equipment_slot)


func _item_context(source: String, index: int, equipment_slot: String) -> Dictionary:
	if source == "inventory" and inventory_model != null and index >= 0 and index < inventory_model.slots.size():
		var stack := inventory_model.slots[index]
		return {"source": source, "index": index, "id": str(stack.get("id", "")), "quantity": int(stack.get("quantity", 1)), "instance": (stack.get("instance", {}) as Dictionary).duplicate(true)}
	if source == "container" and loot_container != null and index >= 0 and index < loot_container.items.size():
		if not loot_container.is_stack_identified(index):
			return {"source": source, "index": index, "concealed": true}
		var stack := loot_container.items[index]
		return {"source": source, "index": index, "id": str(stack.get("id", "")), "quantity": int(stack.get("quantity", 1)), "instance": (stack.get("instance", {}) as Dictionary).duplicate(true)}
	if source == "equipment" and inventory_model != null and inventory_model.equipment.has(equipment_slot):
		var item_id := str(inventory_model.equipment.get(equipment_slot, ""))
		return {"source": source, "index": index, "equipment_slot": equipment_slot, "id": item_id, "quantity": 1 if not item_id.is_empty() else 0, "instance": inventory_model.get_equipment_instance(equipment_slot).duplicate(true)}
	return {}


func _restore_selected_details() -> void:
	_show_context_details(_selected_context())


func _show_context_details(context: Dictionary) -> void:
	if item_detail_window != null and item_detail_window.is_open():
		detail_root.hide()
		return
	# Modified weapons need enough space for their individual properties.
	detail_root.size.y = 148
	_detail_summary_label.size.y = 20
	_detail_summary_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail_description_label.position.y = 66
	_detail_description_label.size.y = 48
	_detail_meta_label.position.y = 116
	if bool(context.get("concealed", false)):
		detail_root.visible = true
		detail_root.modulate = Color(1.0, 1.0, 1.0, 0.88)
		_detail_art_rect.texture = null
		_detail_name_label.text = "?"
		_detail_name_label.add_theme_color_override("font_color", Color(0.69, 0.68, 0.61))
		_detail_name_label.add_theme_stylebox_override("normal", _panel_style(Color(0.055, 0.058, 0.055, 0.96), Color(0.27, 0.28, 0.26), 1, 0))
		_detail_summary_label.text = "정체를 확인하는 중"
		_detail_description_label.text = "상자를 조금 더 뒤져 물품을 확인하십시오."
		_detail_meta_label.text = "미확인"
		return
	var item_id := str(context.get("id", ""))
	if item_id.is_empty():
		detail_root.visible = false
		detail_root.modulate = Color.WHITE
		_detail_art_rect.texture = null
		_detail_name_label.text = "아이템 정보"
		_detail_summary_label.text = "아이템에 마우스를 올리거나 선택"
		_detail_description_label.text = ""
		_detail_meta_label.text = ""
		return
	detail_root.visible = true
	detail_root.modulate = Color.WHITE
	var definition := ExpeditionInventory.get_item_definition(item_id)
	var quantity := int(context.get("quantity", 1))
	var weight := float(definition.get("weight", 0.0)) * quantity
	var value := int(definition.get("value", 0)) * quantity
	var rarity := str(definition.get("rarity", "common"))
	var rarity_name := _rarity_name(rarity)
	var title_color := _rarity_color(rarity).lightened(0.24)
	_detail_art_rect.texture = _item_texture(item_id)
	_detail_name_label.add_theme_color_override("font_color", title_color)
	_detail_name_label.add_theme_stylebox_override("normal", _panel_style(title_color.darkened(0.78), title_color.darkened(0.25), 1, 0))
	_detail_name_label.text = "%s%s" % [str(definition.get("name", item_id)), "  ×%d" % quantity if quantity > 1 else ""]
	_detail_summary_label.text = str(definition.get("summary", ""))
	_detail_description_label.text = str(definition.get("description", ""))
	_detail_meta_label.text = "%s · %.2fkg · %d 크라운" % [rarity_name, weight, value]
	var instance: Dictionary = context.get("instance", {})
	var item_tag := ExpeditionInventory.get_item_tag(instance)
	if not item_tag.is_empty():
		_detail_name_label.text = item_tag + " · " + str(definition.get("name", item_id))
	var smithing_text := ExpeditionInventory.smithing_description(instance)
	if not smithing_text.is_empty():
		var stats := ExpeditionInventory.smithing_stats(item_id, instance)
		_detail_summary_label.text = "피해 %.1f~%.1f · 기력 %.1f~%.1f" % [float(stats.light_damage), float(stats.heavy_damage), 18.0 * float(stats.stamina_scale), 30.0 * float(stats.stamina_scale)]
		_detail_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_summary_label.size.y = 36
		_detail_description_label.text = smithing_text
		_detail_description_label.position.y = 82
		_detail_description_label.size.y = 74
		_detail_meta_label.position.y = 162
		detail_root.size.y = 192


func _equip_selected() -> void:
	if inventory_model == null or selected_source != "inventory":
		return
	var context := _selected_context()
	var item_name := ExpeditionInventory.get_item_name(str(context.get("id", "")))
	var result := inventory_model.equip_from_slot(selected_index)
	if bool(result.get("accepted", false)):
		_action_status_label.text = "%s을(를) 장비했습니다." % item_name
		_clear_selection()
	else:
		_action_status_label.text = "장비할 수 없습니다: %s" % _reason_text(str(result.get("reason", "unknown")))
	_refresh()


func _unequip_selected() -> void:
	if inventory_model == null or selected_source != "equipment":
		return
	var context := _selected_context()
	var item_name := ExpeditionInventory.get_item_name(str(context.get("id", "")))
	var result := inventory_model.unequip(selected_equipment_slot)
	if bool(result.get("accepted", false)):
		_action_status_label.text = "%s을(를) 인벤토리에 넣었습니다." % item_name
		_clear_selection()
	else:
		var reason := str(result.get("reason", "unknown"))
		if reason == "full":
			_action_status_label.text = "인벤토리가 가득 찼습니다. 장비는 원래 위치에 그대로 유지됩니다."
		else:
			_action_status_label.text = "인벤토리로 옮길 수 없습니다: %s" % _reason_text(reason)
	_refresh()


func _request_selected_consumable() -> void:
	var context := _selected_context()
	var item_id := str(context.get("id", ""))
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if selected_source != "inventory" or str(definition.get("category", "")) != "consumable":
		return
	var action_name := "학습" if str(definition.get("effect", "")) == "learn_spell" else "사용"
	_action_status_label.text = "%s %s을(를) 확인하는 중입니다." % [ExpeditionInventory.get_item_name(item_id), action_name]
	consumable_requested.emit(item_id)


func _transfer_selected() -> void:
	if inventory_model == null:
		return
	if selected_source == "equipment":
		_unequip_selected()
		return
	if loot_container == null:
		return
	if selected_source == "container" and not loot_container.is_stack_identified(selected_index):
		_action_status_label.text = "정체가 밝혀진 물품만 가져올 수 있습니다."
		_clear_selection()
		_refresh()
		return
	var moved := 0
	var item_id := str(_selected_context().get("id", ""))
	if selected_source == "inventory":
		moved = _move_inventory_to_container(selected_index)
	elif selected_source == "container":
		moved = _move_container_to_inventory(selected_index)
	if moved > 0:
		_action_status_label.text = "%s ×%d 이동 완료" % [ExpeditionInventory.get_item_name(item_id), moved]
		_clear_selection()
	else:
		_action_status_label.text = "옮길 빈칸이 없습니다. 아이템은 원래 위치에 남아 있습니다."
	_refresh()


func _take_all_from_container() -> void:
	if inventory_model == null or loot_container == null or loot_container.is_empty():
		return
	if loot_container.has_unidentified_items():
		_action_status_label.text = "상자를 모두 조사한 뒤 한꺼번에 가져올 수 있습니다."
		return
	var moved_total := 0
	var index := 0
	while index < loot_container.items.size():
		var before_count := int(loot_container.items[index].get("quantity", 0))
		var moved := _move_container_to_inventory(index, before_count, false)
		moved_total += moved
		if moved <= 0:
			index += 1
		elif moved < before_count:
			# Only a partial source stack stayed at this index because the bag
			# reached capacity. A fully removed stack shifts the next item into the
			# same index, so keep the index unchanged in that case.
			index += 1
	if moved_total > 0:
		inventory_model.changed.emit()
		loot_container.changed.emit()
		_action_status_label.text = "상자에서 총 %d개를 안전하게 가져왔습니다." % moved_total
	else:
		_action_status_label.text = "인벤토리가 가득 찼습니다. 상자의 아이템은 그대로 남아 있습니다."
	_clear_selection()
	_refresh()


func _move_inventory_to_container(index: int, requested_quantity := 999999, notify := true) -> int:
	if inventory_model == null or loot_container == null or index < 0 or index >= inventory_model.slots.size():
		return 0
	var stack := inventory_model.slots[index]
	var item_id := str(stack.get("id", ""))
	var quantity := mini(int(stack.get("quantity", 0)), requested_quantity)
	var movable := mini(quantity, _container_capacity_for(item_id, stack.get("instance", {})))
	if movable <= 0:
		return 0
	var removed := inventory_model.remove_from_slot(index, movable, false)
	var removed_quantity := int(removed.get("quantity", 0))
	if removed_quantity <= 0:
		return 0
	var remainder := loot_container.store_item(item_id, removed_quantity, false, true, removed.get("instance", {}))
	if remainder > 0:
		# The preflight capacity check should make this unnecessary, but restoring
		# into the just-freed source slot keeps the operation lossless if either
		# model gains new capacity rules later.
		var restore_failure := inventory_model.add_item(item_id, remainder, false, removed.get("instance", {}))
		if restore_failure > 0:
			loot_container.store_item(item_id, restore_failure, false, true, removed.get("instance", {}))
	var moved := removed_quantity - remainder
	if notify and moved > 0:
		inventory_model.changed.emit()
		loot_container.changed.emit()
	return moved


func _move_container_to_inventory(index: int, requested_quantity := 999999, notify := true) -> int:
	if inventory_model == null or loot_container == null or index < 0 or index >= loot_container.items.size():
		return 0
	if not loot_container.is_stack_identified(index):
		return 0
	var stack := loot_container.items[index]
	var item_id := str(stack.get("id", ""))
	var source_identified := bool(stack.get("identified", true))
	var quantity := mini(int(stack.get("quantity", 0)), requested_quantity)
	var movable := mini(quantity, _inventory_capacity_for(item_id, stack.get("instance", {})))
	if movable <= 0:
		return 0
	var removed := loot_container.take_from_slot(index, movable, false)
	var removed_quantity := int(removed.get("quantity", 0))
	if removed_quantity <= 0:
		return 0
	var remainder := inventory_model.add_item(item_id, removed_quantity, false, removed.get("instance", {}))
	if remainder > 0:
		var restore_failure := loot_container.store_item(item_id, remainder, false, source_identified, removed.get("instance", {}))
		if restore_failure > 0:
			inventory_model.add_item(item_id, restore_failure, false, removed.get("instance", {}))
	var moved := removed_quantity - remainder
	if notify and moved > 0:
		inventory_model.changed.emit()
		loot_container.changed.emit()
	return moved


func _inventory_capacity_for(item_id: String, instance_data: Dictionary = {}) -> int:
	if inventory_model == null:
		return 0
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty():
		return 0
	var stack_max := maxi(1, int(definition.get("stack_max", 1)))
	var capacity := 0
	for stack in inventory_model.slots:
		if str(stack.get("id", "")) == item_id and stack.get("instance", {}) == instance_data:
			capacity += maxi(0, stack_max - int(stack.get("quantity", 0)))
	capacity += maxi(0, ExpeditionInventory.MAX_SLOTS - inventory_model.slots.size()) * stack_max
	return capacity


func _container_capacity_for(item_id: String, instance_data: Dictionary = {}) -> int:
	if loot_container == null:
		return 0
	var definition := ExpeditionInventory.get_item_definition(item_id)
	if definition.is_empty():
		return 0
	var stack_max := maxi(1, int(definition.get("stack_max", 1)))
	var capacity := 0
	for stack in loot_container.items:
		if str(stack.get("id", "")) == item_id and bool(stack.get("identified", true)) and stack.get("instance", {}) == instance_data:
			capacity += maxi(0, stack_max - int(stack.get("quantity", 0)))
	capacity += maxi(0, loot_container.max_slots - loot_container.items.size()) * stack_max
	return capacity


func _short_item_name(item_id: String) -> String:
	if item_id.is_empty():
		return "—"
	var item_name := ExpeditionInventory.get_item_name(item_id)
	return item_name.left(8) + "…" if item_name.length() > 8 else item_name


func _section_heading(title_text: String, subtitle_text: String) -> Panel:
	var panel := Panel.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.045, 0.049, 0.042), Color(0.15, 0.165, 0.13), 1, 0))
	var title := _label(title_text, 13, Color(0.76, 0.79, 0.69))
	title.anchor_left = 0.0
	title.anchor_right = 0.45
	title.offset_left = 9.0
	title.offset_right = -2.0
	title.offset_top = 0.0
	title.offset_bottom = 30.0
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var subtitle := _label(subtitle_text, 9, Color(0.39, 0.42, 0.36))
	subtitle.anchor_left = 0.38
	subtitle.anchor_right = 1.0
	subtitle.offset_left = 0.0
	subtitle.offset_right = -9.0
	subtitle.offset_top = 0.0
	subtitle.offset_bottom = 30.0
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(subtitle)
	return panel


func _slot_button(minimum_size: Vector2) -> Button:
	var button := Button.new()
	button.custom_minimum_size = minimum_size
	button.focus_mode = Control.FOCUS_NONE
	button.clip_text = true
	button.text = ""
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.92, 0.94, 0.84))
	button.add_theme_color_override("font_pressed_color", Color(0.82, 0.85, 0.66))
	var art := TextureRect.new()
	art.name = "ItemArt"
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.offset_left = 2.0
	art.offset_top = 2.0
	art.offset_right = -2.0
	art.offset_bottom = -2.0
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(art)
	var unknown_marker := _label("?", 26, Color(0.66, 0.69, 0.6))
	unknown_marker.name = "UnknownMarker"
	unknown_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	unknown_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unknown_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	unknown_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unknown_marker.visible = false
	button.add_child(unknown_marker)
	var caption := _label("", 8, Color(0.74, 0.76, 0.68))
	caption.name = "SlotCaption"
	caption.anchor_right = 1.0
	caption.offset_left = 3.0
	caption.offset_top = 1.0
	caption.offset_right = -3.0
	caption.offset_bottom = 14.0
	caption.add_theme_stylebox_override("normal", _panel_style(Color(0.01, 0.012, 0.011, 0.72), Color.TRANSPARENT, 0, 0))
	button.add_child(caption)
	var item_name := _label("", 8, Color(0.74, 0.76, 0.69))
	item_name.name = "ItemName"
	item_name.anchor_top = 1.0
	item_name.anchor_right = 1.0
	item_name.anchor_bottom = 1.0
	item_name.offset_left = 3.0
	item_name.offset_top = -14.0
	item_name.offset_right = -3.0
	item_name.offset_bottom = -1.0
	item_name.clip_text = true
	item_name.add_theme_stylebox_override("normal", _panel_style(Color(0.008, 0.01, 0.009, 0.76), Color.TRANSPARENT, 0, 0))
	button.add_child(item_name)
	var quantity := _label("", 9, Color(0.95, 0.96, 0.89))
	quantity.name = "Quantity"
	quantity.anchor_left = 1.0
	quantity.anchor_right = 1.0
	quantity.offset_left = -34.0
	quantity.offset_top = 2.0
	quantity.offset_right = -3.0
	quantity.offset_bottom = 16.0
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity.add_theme_stylebox_override("normal", _panel_style(Color(0.005, 0.007, 0.006, 0.82), Color.TRANSPARENT, 0, 0))
	button.add_child(quantity)
	return button


func _action_button(text_value: String, position_value: Vector2, size_value: Vector2, color_value: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = position_value
	button.size = size_value
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color(0.94, 0.95, 0.87))
	button.add_theme_color_override("font_pressed_color", Color(0.82, 0.85, 0.66))
	button.add_theme_color_override("font_disabled_color", Color(0.34, 0.33, 0.29))
	button.add_theme_stylebox_override("normal", _panel_style(color_value, color_value.lightened(0.18), 1, 0))
	button.add_theme_stylebox_override("hover", _panel_style(color_value.lightened(0.08), COLOR_BORDER_BRIGHT, 2, 0))
	button.add_theme_stylebox_override("pressed", _panel_style(color_value.darkened(0.16), COLOR_ACTIVE, 2, 0))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.035, 0.037, 0.034), Color(0.13, 0.14, 0.12), 1, 0))
	return button


func _label(text_value: String, font_size: int, color_value: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color_value)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _panel_style(background: Color, border: Color, width := 1, radius := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	return style


func _rarity_name(rarity: String) -> String:
	match rarity:
		"uncommon":
			return "고급"
		"rare":
			return "희귀"
		"legendary":
			return "전설"
	return "일반"


func _rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon":
			return Color(0.32, 0.52, 0.35)
		"rare":
			return Color(0.28, 0.5, 0.72)
		"legendary":
			return Color(0.82, 0.54, 0.16)
	return Color(0.48, 0.5, 0.43)


func _reason_text(reason: String) -> String:
	match reason:
		"full":
			return "인벤토리가 가득 참"
		"empty":
			return "빈 슬롯"
		"not_equipment":
			return "장비 아이템이 아님"
		"invalid_slot":
			return "잘못된 슬롯"
	return reason
