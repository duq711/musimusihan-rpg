extends CanvasLayer
class_name AlchemyOverlay
## A manual, live workbench. The hideout owns world pause and the cursor;
## this isolated UI advances only its own batch while it is visible.
signal closed

const SYSTEM := preload("res://scripts/alchemy_system.gd")
const CATALOG := preload("res://scripts/alchemy_catalog.gd")
const VISUAL := preload("res://scripts/alchemy_visual.gd")
const AUDIO := preload("res://scripts/alchemy_audio.gd")
const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const GOLD := Color("c6a16a")
const IVORY := Color("e4dcc9")
const MUTED := Color("a39d8b")
var system: RefCounted
var inventory_model: ExpeditionInventory
var overlay_root: Control
var scene_viewport: SubViewport
var surface: SubViewportContainer
var visual: Node3D
var camera: Camera3D
var heading: Label
var subtitle: Label
var product_buttons: Dictionary = {}
var _product_type := ""
var recipe_picker: OptionButton
var herb_picker: OptionButton
var recipe_text: RichTextLabel
var contents_label: Label
var mortar_label: Label
var state_label: Label
var hourglass_label: Label
var message_label: Label
var journal_label: RichTextLabel
var heat_bar: ProgressBar
var timer_bar: ProgressBar
var distill_bar: ProgressBar
var tool_hint: Label
var action_buttons: Dictionary = {}
var base_buttons: Dictionary = {}
var _selected_herb := "redroot"
var _refresh_clock := 0.0
var _hovered_tool := ""
var _discard_armed := false
var _journal_visible := false
var _book_expanded := false
var current_view := "overview"
var _tool_audio: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 46
	_build()
	_tool_audio = AudioStreamPlayer.new()
	_tool_audio.name = "AlchemyToolSounds"
	_tool_audio.volume_db = -23
	add_child(_tool_audio)
	overlay_root.hide()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	get_viewport().size_changed.connect(_layout)
	_layout()

func is_open() -> bool:
	return is_instance_valid(overlay_root) and overlay_root.visible

func open_for_inventory(bag: ExpeditionInventory) -> void:
	if system == null or inventory_model != bag:
		inventory_model = bag
		system = SYSTEM.new().setup(bag)
		system.select_recipe(CATALOG.ordered_recipe_ids()[0])
	overlay_root.show()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visual.process_mode = Node.PROCESS_MODE_INHERIT
	_discard_armed = false
	_refresh()

func close() -> void:
	if not is_open(): return
	_hide_workbench()
	closed.emit()

func cancel_work() -> void:
	if system != null: system.discard()
	_hide_workbench()

func _hide_workbench() -> void:
	_discard_armed = false
	if is_instance_valid(_tool_audio): _tool_audio.stop()
	if not is_instance_valid(overlay_root): return
	overlay_root.hide()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visual.process_mode = Node.PROCESS_MODE_DISABLED

func select_recipe(id: String) -> Dictionary:
	return perform_action("select_recipe", id)

func select_product_type(product_type: String) -> Dictionary:
	if product_type not in ["medicine", "liquor"]:
		return {"accepted": false, "message": "알 수 없는 제조 종류입니다."}
	var ids: Array[String] = CATALOG.liquor_recipe_ids() if product_type == "liquor" else CATALOG.medicine_recipe_ids()
	if system != null and str(system.snapshot().recipe_id) in ids:
		return {"accepted": true}
	return select_recipe(ids[0])

func _sync_recipe_picker(recipe_id: String, locked: bool) -> void:
	var product_type := str(CATALOG.recipe(recipe_id).get("product_type", "medicine"))
	if _product_type != product_type:
		_product_type = product_type
		recipe_picker.clear()
		var ids: Array[String] = CATALOG.liquor_recipe_ids() if product_type == "liquor" else CATALOG.medicine_recipe_ids()
		for id: String in ids:
			recipe_picker.add_item(str(CATALOG.recipe(id).name))
			recipe_picker.set_item_metadata(recipe_picker.item_count - 1, id)
	for index in recipe_picker.item_count:
		if str(recipe_picker.get_item_metadata(index)) == recipe_id: recipe_picker.select(index)
	recipe_picker.disabled = locked
	for id: String in product_buttons:
		product_buttons[id].set_pressed_no_signal(id == product_type)
		product_buttons[id].disabled = locked
	heading.text = "성소의 증류 작업대" if product_type == "liquor" else "성소의 연금술 작업대"
	subtitle.text = "향을 입히고, 증류하고, 병에 담아 중개인에게 파세요. 재료와 빈 병도 중개인이 공급합니다." if product_type == "liquor" else "약초를 손질하고, 불을 살피고, 한 병을 완성하십시오."

func recipe_economy(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	if str(recipe.get("product_type", "medicine")) != "liquor": return {}
	var ingredients_cost := ExpeditionSession.get_buy_price(str(CATALOG.BASES[recipe.base].item_id))
	for id: String in recipe.ingredients:
		ingredients_cost += int(recipe.ingredients[id]) * ExpeditionSession.get_buy_price(str(CATALOG.HERBS[id].item_id))
	var result: Dictionary = {}
	for quality: String in ["weak", "normal", "strong"]:
		var quantity := 2 if quality == "strong" else 1
		var cost := ingredients_cost + quantity * ExpeditionSession.get_buy_price("alchemy_empty_bottle")
		var revenue := quantity * ExpeditionSession.get_sell_price(str(recipe.outputs[quality]))
		result[quality] = {"quantity": quantity, "cost": cost, "revenue": revenue, "profit": revenue - cost}
	return result

func perform_action(action: String, payload: Variant = null) -> Dictionary:
	if system == null: return {"accepted": false, "message": "연금술 작업대를 먼저 여세요."}
	var result: Dictionary
	match action:
		"select_recipe": result = system.select_recipe(str(payload))
		"pour_base": result = system.pour_base(str(payload))
		"add_herb": result = system.add_herb(str(payload.get("herb_id", payload.get("id", _selected_herb))), str(payload.get("destination", "cauldron")))
		"add_whole": result = system.add_herb(str(payload) if payload != null else _selected_herb, "cauldron")
		"add_to_mortar": result = system.add_herb(str(payload) if payload != null else _selected_herb, "mortar")
		"grind": result = system.grind()
		"pour_mortar": result = system.pour_mortar()
		"pump_bellows": result = system.pump_bellows()
		"lower_cauldron": result = system.set_cauldron_lowered(true)
		"raise_cauldron": result = system.set_cauldron_lowered(false)
		"set_cauldron_lowered": result = system.set_cauldron_lowered(bool(payload))
		"turn_hourglass": result = system.turn_hourglass()
		"stir": result = system.stir()
		"start_distillation": result = system.start_distillation()
		"bottle": result = system.bottle()
		"discard": result = system.discard()
		_: result = {"accepted": false, "message": "사용할 수 없는 도구입니다."}
	_discard_armed = false
	if bool(result.get("accepted", false)):
		var focus_view: String = {"pour_base": "cauldron", "add_whole": "cauldron", "add_to_mortar": "mortar", "grind": "mortar", "pour_mortar": "cauldron", "pump_bellows": "cauldron", "stir": "cauldron", "start_distillation": "distill"}.get(action, "")
		if not focus_view.is_empty(): set_view(focus_view)
		var animation: String = {"pour_mortar": "add_mortar", "turn_hourglass": "flip_hourglass", "start_distillation": "distill"}.get(action, action)
		if action == "pour_base": animation = "pour_" + str(payload)
		visual.animate_action(animation)
		if action == "bottle" and str(system.snapshot().stage) == "finished": _journal_visible = true
		if action == "bottle": _book_expanded = false
		if action in ["select_recipe", "discard"]:
			_book_expanded = false
			_journal_visible = false
		if is_open() and DisplayServer.get_name() != "headless":
			var sound: AudioStreamWAV = AUDIO.stream_for(action)
			if sound != null:
				_tool_audio.stream = sound
				_tool_audio.play()
	_refresh()
	message_label.text = str(result.get("message", ""))
	message_label.modulate = IVORY if result.get("accepted", false) else Color("e7a48c")
	return result

func _build() -> void:
	overlay_root = Control.new()
	overlay_root.name = "AlchemyWorkbench"
	add_child(overlay_root)
	var theme := Theme.new()
	var readable_font := FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	theme.default_font = readable_font
	theme.default_font_size = 14
	theme.set_color("font_color", "Label", IVORY)
	theme.set_color("font_color", "Button", IVORY)
	for kind in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color := Color("242821") if kind == "normal" else Color("383c2c")
		if kind == "disabled": color = Color("171b17")
		theme.set_stylebox(kind, "Button", _style(color, Color("6e6349") if kind == "focus" else Color("484936")))
	theme.set_color("font_disabled_color", "Button", Color("676c60"))
	overlay_root.theme = theme
	var background := ColorRect.new()
	background.color = Color("111712")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.add_child(background)
	heading = _label("성소의 연금술 작업대", 25, GOLD)
	_place(heading, Rect2(22, 12, 530, 38))
	subtitle = _label("약초를 손질하고, 불을 살피고, 한 병을 완성하십시오.", 13, MUTED)
	_place(subtitle, Rect2(24, 49, 770, 25))
	var close_button := _button("ESC  작업대에서 물러나기", close)
	_place(close_button, Rect2(1042, 20, 215, 39))
	_build_book()
	_build_scene()
	_build_tools()
	var footer := _panel(Rect2(302, 568, 706, 129), Color("1b221b"))
	message_label = _label("", 15)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.y = 48
	footer.add_child(message_label)
	var shortcuts := _label("Space 풀무 · R 솥 올리기/내리기 · T 모래시계 · G 빻기\nH 젓기 · B 병입 · 도구 조작 시 가까이 봅니다. 상단에서 시점을 바꿀 수 있습니다.", 12, MUTED)
	footer.add_child(shortcuts)
	var resume_hint := _label("닫으면 제조가 멈추고 유지됩니다. 배합 폐기·장면 이동 시 투입 재료는 소실됩니다.", 11, MUTED)
	footer.add_child(resume_hint)

func _build_book() -> void:
	var left := _panel(Rect2(20, 86, 266, 611), Color("22271d"))
	left.add_child(_label("HERBARIUM  /  제조서", 14, GOLD))
	var modes := HBoxContainer.new()
	left.add_child(modes)
	for entry in [["medicine", "물약 조제"], ["liquor", "술 증류"]]:
		var product_id := str(entry[0])
		var button := _button(str(entry[1]), func(): select_product_type(product_id))
		button.name = "ProductType_" + product_id
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		product_buttons[product_id] = button
		modes.add_child(button)
	recipe_picker = OptionButton.new()
	recipe_picker.name = "AlchemyRecipePicker"
	recipe_picker.custom_minimum_size.y = 37
	recipe_picker.item_selected.connect(func(index: int): select_recipe(str(recipe_picker.get_item_metadata(index))))
	left.add_child(recipe_picker)
	recipe_text = RichTextLabel.new()
	recipe_text.name = "AlchemyRecipeInstructions"
	recipe_text.bbcode_enabled = true
	recipe_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	recipe_text.add_theme_font_size_override("normal_font_size", 14)
	recipe_text.add_theme_color_override("default_color", IVORY)
	left.add_child(recipe_text)
	var guide := _label("모래 한 번 = 8초 · 절구 세 번 = 가루\n끓는 시간만 셉니다. 솥을 올리면 식습니다.", 12, MUTED)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(guide)
	left.add_child(_button("조제서 크게 펼치기", _toggle_book))
	left.add_child(_button("조제 기록 보기 / 닫기", func(): _book_expanded = false; _journal_visible = not _journal_visible; _refresh()))
	var discard_button := _button("현재 배합 폐기", _request_discard)
	action_buttons["discard"] = discard_button
	left.add_child(discard_button)

func _build_scene() -> void:
	surface = SubViewportContainer.new()
	surface.name = "AlchemyToolInteractionSurface"
	surface.stretch = true
	_place(surface, Rect2(302, 143, 706, 412))
	surface.mouse_filter = Control.MOUSE_FILTER_STOP
	surface.gui_input.connect(_work_surface_input)
	scene_viewport = SubViewport.new()
	scene_viewport.name = "RealAlchemyBench3D"
	scene_viewport.own_world_3d = true
	scene_viewport.size = Vector2i(706, 412)
	scene_viewport.gui_disable_input = true
	scene_viewport.handle_input_locally = false
	scene_viewport.physics_object_picking = false
	scene_viewport.audio_listener_enable_3d = false
	scene_viewport.msaa_3d = Viewport.MSAA_2X
	surface.add_child(scene_viewport)
	visual = VISUAL.new()
	scene_viewport.add_child(visual)
	camera = Camera3D.new()
	camera.current = true
	scene_viewport.add_child(camera)
	visual.set_camera(camera)
	set_view("overview")
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("111a17")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a2b9aa")
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.45
	environment.ssao_intensity = 1.2
	environment.glow_enabled = true
	environment_node.environment = environment
	scene_viewport.add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -30, 0)
	key.light_color = Color("f0d6a6")
	key.light_energy = 1.6
	key.shadow_enabled = true
	scene_viewport.add_child(key)
	state_label = _label("", 17, GOLD)
	_place(state_label, Rect2(306, 87, 456, 30))
	hourglass_label = _label("", 14)
	_place(hourglass_label, Rect2(756, 89, 250, 26))
	heat_bar = _meter(Rect2(306, 123, 439, 5), Color("bd783f"))
	heat_bar.max_value = 130
	timer_bar = _meter(Rect2(766, 123, 239, 5), GOLD)
	distill_bar = _meter(Rect2(305, 548, 698, 5), Color("79bca5"))
	tool_hint = _label("도구를 클릭하거나 오른쪽 작업 버튼을 사용하세요.", 12)
	tool_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(tool_hint, Rect2(314, 514, 685, 27))
	var views := HBoxContainer.new()
	_place(views, Rect2(315, 151, 354, 29))
	for entry in [["overview", "작업대 전체"], ["mortar", "절구"], ["cauldron", "가마솥"], ["distill", "증류기"]]:
		var b := _button(entry[1], func(): set_view(entry[0]))
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size.y = 28
		views.add_child(b)
	journal_label = RichTextLabel.new()
	journal_label.bbcode_enabled = true
	journal_label.add_theme_stylebox_override("normal", _style(Color(0.05, 0.08, 0.06, 0.97), GOLD))
	journal_label.add_theme_color_override("default_color", IVORY)
	_place(journal_label, Rect2(311, 158, 685, 350))
	journal_label.hide()

func _build_tools() -> void:
	var right := _panel(Rect2(1024, 86, 233, 611), Color("1c241d"))
	right.add_theme_constant_override("separation", 5)
	right.add_child(_label("01  바탕 액체", 14, GOLD))
	var bases := GridContainer.new()
	bases.columns = 2
	right.add_child(bases)
	for id: String in ["water", "wine", "spirits", "oil"]:
		var b := _button(str(CATALOG.BASES[id].name), func(): perform_action("pour_base", id))
		b.custom_minimum_size = Vector2(99, 32)
		bases.add_child(b)
		base_buttons[id] = b
	right.add_child(_label("02  약초 손질 · 한 줌씩", 14, GOLD))
	herb_picker = OptionButton.new()
	herb_picker.name = "AlchemyHerbPicker"
	herb_picker.custom_minimum_size.y = 33
	for id: String in CATALOG.HERBS:
		herb_picker.add_item(str(CATALOG.HERBS[id].name))
		herb_picker.set_item_metadata(herb_picker.item_count - 1, id)
	herb_picker.item_selected.connect(func(index: int): _selected_herb = str(herb_picker.get_item_metadata(index)))
	right.add_child(herb_picker)
	var herbs := GridContainer.new()
	herbs.columns = 2
	right.add_child(herbs)
	_action(herbs, "통째로 넣기", "add_whole")
	_action(herbs, "절구에 담기", "add_to_mortar")
	_action(herbs, "G  한 번 빻기", "grind")
	_action(herbs, "절구 비우기", "pour_mortar")
	mortar_label = _label("", 12, MUTED)
	mortar_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mortar_label.custom_minimum_size.y = 34
	right.add_child(mortar_label)
	right.add_child(_label("03  불과 도구", 14, GOLD))
	var tools_grid := GridContainer.new()
	tools_grid.columns = 2
	right.add_child(tools_grid)
	_action(tools_grid, "Space 풀무", "pump_bellows")
	_action(tools_grid, "T  모래시계", "turn_hourglass")
	_action(tools_grid, "솥 내리기", "lower_cauldron")
	_action(tools_grid, "솥 올리기", "raise_cauldron")
	_action(tools_grid, "H  젓기", "stir")
	_action(tools_grid, "증류 시작", "start_distillation")
	_action(right, "B  빈 병에 받기", "bottle")
	contents_label = _label("", 12, MUTED)
	contents_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(contents_label)

func _action(parent: Node, title: String, action: String) -> void:
	var b := _button(title, func(): perform_action(action))
	b.name = "Alchemy_" + action
	b.custom_minimum_size = Vector2(99, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	action_buttons[action] = b

func _request_discard() -> void:
	if system != null and str(system.snapshot().stage) == "finished":
		select_recipe(str(system.snapshot().recipe_id))
		return
	if _discard_armed:
		perform_action("discard")
	else:
		_discard_armed = true
		action_buttons.discard.text = "다시 눌러 폐기 · 재료 소실"
		message_label.text = "투입한 액체와 약초가 사라집니다. 폐기하려면 버튼을 한 번 더 누르세요."

func _process(delta: float) -> void:
	if not is_open() or system == null: return
	system.tick(delta)
	_refresh_clock += delta
	if _refresh_clock >= 0.1:
		_refresh_clock = 0.0
		_refresh()

func _input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
		return
	var action: String = {KEY_SPACE: "pump_bellows", KEY_T: "turn_hourglass", KEY_G: "grind", KEY_H: "stir", KEY_B: "bottle"}.get(event.physical_keycode, "")
	if event.physical_keycode == KEY_R:
		action = "raise_cauldron" if bool(system.snapshot().get("cauldron_lowered", false)) else "lower_cauldron"
	if not action.is_empty():
		perform_action(action)
		get_viewport().set_input_as_handled()

func _work_surface_input(event: InputEvent) -> void:
	if not is_open(): return
	if event is InputEventMouseMotion:
		_hovered_tool = visual.get_interaction_at(camera, event.position)
		tool_hint.text = _tool_title(_hovered_tool)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var tool: String = visual.get_interaction_at(camera, event.position)
		if tool.begins_with("pour_") and tool.trim_prefix("pour_") in CATALOG.BASES:
			perform_action("pour_base", tool.trim_prefix("pour_"))
		elif tool == "recipe_book":
			_toggle_book()
		elif not tool.is_empty():
			perform_action({"add_mortar": "pour_mortar", "flip_hourglass": "turn_hourglass", "distill": "start_distillation"}.get(tool, tool))

func _refresh() -> void:
	if system == null: return
	var state: Dictionary = system.snapshot()
	visual.update_state(state)
	var stage := str(state.get("stage", "empty"))
	var boiling := bool(state.get("boiling", false))
	var temp := float(state.get("temperature", 20))
	var lowered := bool(state.get("cauldron_lowered", false))
	state_label.text = "%d°C  ·  %s  ·  끓인 시간 %.1f회" % [roundi(temp), "끓는 중" if boiling else ("식히는 중" if not lowered and temp > 25 else "가열 중" if lowered else "준비"), float(state.get("boil_turns", 0))]
	if stage == "finished": state_label.text = "조제 완료  ·  기록에서 결과를 확인하세요"
	elif lowered and temp > float(state.get("boiling_point", 100)) + 12:
		state_label.text = "%d°C  ·  과열 주의! 솥을 올려 식히세요" % roundi(temp)
	state_label.modulate = Color("f09b73") if lowered and temp > float(state.get("boiling_point", 100)) + 12 else Color.WHITE
	heat_bar.value = temp
	var remaining := float(state.get("hourglass_remaining", 0))
	hourglass_label.text = "모래시계  %.1f초" % remaining if state.get("hourglass_running", false) else "모래시계  ·  뒤집어 시작"
	timer_bar.value = remaining / maxf(1.0, float(state.get("turn_seconds", 8))) * 100
	distill_bar.visible = stage == "distilling"
	distill_bar.value = float(state.get("distill_progress", 0)) * 100
	for id: String in base_buttons:
		var amount := inventory_model.count_item(str(CATALOG.BASES[id].item_id))
		base_buttons[id].text = "%s %d" % [{"water": "물", "wine": "포도주", "spirits": "증류주", "oil": "기름"}[id], amount]
		base_buttons[id].disabled = stage != "empty" or amount < 1
	for index in herb_picker.item_count:
		var id := str(herb_picker.get_item_metadata(index))
		herb_picker.set_item_text(index, "%s  ·  %d줌" % [str(CATALOG.HERBS[id].name), inventory_model.count_item(str(CATALOG.HERBS[id].item_id))])
	var recipe_id := str(state.get("recipe_id", ""))
	_sync_recipe_picker(recipe_id, stage not in ["empty", "finished"])
	var recipe: Dictionary = CATALOG.recipe(recipe_id)
	var liquor := str(recipe.get("product_type", "medicine")) == "liquor"
	var text := "[color=#c6a16a]%s[/color]\n\n" % str(recipe.get("description", ""))
	if liquor:
		var economy := recipe_economy(recipe_id)
		text = "[b]원가 → 판매액 · 순이익[/b]\n[color=#a39d8b]재료와 빈 병 전부 구매 기준[/color]\n"
		for quality: String in ["normal", "strong"]:
			var quote: Dictionary = economy[quality]
			text += "%s %d병  %d → %d 크라운\n[color=#c6a16a]순이익 +%d 크라운[/color]\n" % [CATALOG.quality_label(recipe_id, quality), quote.quantity, quote.cost, quote.revenue, quote.profit]
		text += "미숙품은 값이 낮고 실패하면 재료를 잃습니다.\n\n"
	var costs: Array[String] = []
	var base: Dictionary = CATALOG.BASES.get(str(recipe.get("base", "")), {})
	costs.append("%s 1병" % str(base.get("name", "바탕 액체")))
	costs.append("빈 약병 2개 (특급 2병)" if liquor else "빈 약병 2개 (상급 2병)")
	for id: String in recipe.get("ingredients", {}): costs.append("%s %d줌" % [str(CATALOG.HERBS[id].name), int(recipe.ingredients[id])])
	text += "[b]준비[/b]  " + " · ".join(costs) + "\n\n"
	var step_index := 1
	for step: String in recipe.get("steps", []):
		text += "[color=#c6a16a]%02d[/color]  %s\n\n" % [step_index, step]
		step_index += 1
	if recipe_text.text != text: recipe_text.text = text
	var mortar: Array = state.get("mortar", [])
	mortar_label.text = "절구: " + _ingredient_text(mortar)
	contents_label.text = "솥: " + _ingredient_text(state.get("ingredients", []))
	contents_label.text += "\n빈 병 %d개" % inventory_model.count_item("alchemy_empty_bottle")
	if stage == "distilling": contents_label.text += "\n증류 %d%% · 풀무로 열 유지" % roundi(float(state.get("distill_progress", 0)) * 100)
	for action: String in action_buttons:
		var enabled := true
		match action:
			"add_whole", "add_to_mortar", "stir": enabled = stage == "brewing"
			"grind", "pour_mortar": enabled = stage == "brewing" and not mortar.is_empty()
			"pump_bellows", "lower_cauldron", "raise_cauldron": enabled = stage in ["brewing", "distilling"]
			"start_distillation": enabled = stage == "brewing"
			"bottle": enabled = (stage == "distilling" and float(state.get("distill_progress", 0)) >= 1.0) if liquor else stage in ["brewing", "distilling"]
			"discard": enabled = stage != "empty" or not mortar.is_empty()
		(action_buttons[action] as Button).disabled = not enabled
	if not _discard_armed: action_buttons.discard.text = "같은 처방으로 다시 만들기" if stage == "finished" else "현재 배합 폐기"
	journal_label.visible = _journal_visible or _book_expanded
	var journal := "[b]조제 기록[/b]\n\n"
	var result: Dictionary = state.get("last_result", {})
	if not result.is_empty():
		var grade: String = CATALOG.quality_label(recipe_id, str(result.get("quality", "")))
		journal += "\n[color=#c6a16a]결과  ·  %s  ·  %d점[/color]\n" % [grade, roundi(float(result.get("score", 0)))]
		journal += ("제조에 실패했습니다. 아래 원인을 확인하고 다시 시도하세요." if str(result.get("quality", "")) == "failed" else "%s %d병을 가방에 넣었습니다." % [ExpeditionInventory.get_item_name(str(result.get("item_id", ""))), int(result.get("quantity", 0))]) + "\n"
		if liquor and int(result.get("quantity", 0)) > 0:
			var sale := ExpeditionSession.get_sell_price(str(result.item_id)) * int(result.quantity)
			journal += "\n[color=#c6a16a]중개인 판매액: 총 %d 크라운[/color]\nESC로 닫기 → M 지도 → 중개인 → 거래 → 완성주 선택 → 판매\n" % sale
	for mistake: Variant in state.get("mistakes", []): journal += "• " + str(mistake) + "\n"
	journal += "\n[color=#a39d8b]최근 작업부터 표시합니다.[/color]\n"
	var history: Array = state.get("history", []).duplicate()
	history.reverse()
	for entry: Variant in history:
		journal += _history_line(entry) + "\n" if entry is Dictionary else str(entry) + "\n"
	if _book_expanded: journal = "[b]%s[/b]\n\n" % str(recipe.get("name", "조제서")) + text
	if journal_label.text != journal: journal_label.text = journal
	if not _discard_armed: message_label.text = str(state.get("last_message", ""))
	if stage == "empty" and inventory_model.count_item("alchemy_empty_bottle") < 2:
		message_label.text = "특급 술은 두 병 나옵니다. 중개인에게 빈 약병 2개와 제조서의 재료를 준비하세요." if liquor else "상급 물약은 두 병 나옵니다. 제조 전에 중개인에게 빈 약병 2개와 조제서의 재료를 준비하세요."

func _toggle_book() -> void:
	_book_expanded = not _book_expanded
	_journal_visible = false
	_refresh()

func set_view(view: String) -> void:
	current_view = view
	if not is_instance_valid(camera): return
	var pose: Dictionary = visual.camera_pose(view)
	camera.position = pose.position
	camera.look_at(pose.target)
	camera.fov = float(pose.fov)

func _ingredient_text(entries: Array) -> String:
	if entries.is_empty(): return "비어 있음"
	var parts: Array[String] = []
	for entry: Variant in entries:
		if entry is Dictionary:
			var id := str(entry.get("herb_id", entry.get("id", "")))
			var herb: Dictionary = CATALOG.HERBS.get(id, {})
			var form := str(entry.get("form", "whole"))
			var detail: String = {"whole": "통째", "bruised": "%d/3회" % int(entry.get("strokes", 0)), "ground": "가루"}.get(form, "통째")
			parts.append("%s(%s)" % [str(herb.get("name", id)), detail])
		else: parts.append(str(entry))
	return ", ".join(parts)

func _history_line(entry: Dictionary) -> String:
	var action := str(entry.get("action", ""))
	var title: String = {"base": "바탕 액체 붓기", "mortar_add": "절구에 약초 담기", "ingredient": "솥에 약초 넣기", "grind": "절구 찧기", "bellows": "풀무 당기기", "lower": "솥 내리기", "raise": "솥 올리기", "hourglass": "모래시계 뒤집기", "stir": "약액 젓기", "distill": "증류 시작", "failed": "제조 실패", "bottle": "완성품 병입"}.get(action, "작업")
	var id := str(entry.get("id", ""))
	if CATALOG.HERBS.has(id): title += " · " + str(CATALOG.HERBS[id].name)
	if CATALOG.BASES.has(id): title += " · " + str(CATALOG.BASES[id].name)
	return "%5.1f초  %s" % [float(entry.get("elapsed", 0)), title]

func _tool_title(id: String) -> String:
	return {"pour_water": "물병 · 물 붓기", "pour_wine": "포도주병 · 포도주 붓기", "pour_spirits": "증류주병 · 증류주 붓기", "pour_oil": "기름병 · 기름 붓기", "grind": "절구 · 한 번 빻기", "add_mortar": "절구의 약초를 솥에 모두 넣기", "pump_bellows": "풀무 · 불 키우기", "lower_cauldron": "가마솥 · 불 위로 내리기", "raise_cauldron": "가마솥 · 불에서 올리기", "stir": "주걱 · 약액 젓기", "flip_hourglass": "모래시계 · 뒤집어 8초 재기", "distill": "증류기 · 증류 시작", "bottle": "빈 병 · 완성 약액 받기", "recipe_book": "조제서 · 작업 기록"}.get(id, "도구를 클릭하거나 오른쪽 작업 버튼을 사용하세요.")

func _layout() -> void:
	if not is_instance_valid(overlay_root): return
	var available := get_viewport().get_visible_rect().size
	var ratio := minf(available.x / 1280.0, available.y / 720.0)
	overlay_root.size = Vector2(1280, 720)
	overlay_root.scale = Vector2.ONE * ratio
	overlay_root.position = (available - overlay_root.size * ratio) * 0.5

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size
	overlay_root.add_child(control)

func _panel(rect: Rect2, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(color, Color("434c38")))
	_place(panel, rect)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	return column

func _label(text: String, size: int = 14, color: Color = IVORY) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	return button

func _meter(rect: Rect2, color: Color) -> ProgressBar:
	var meter := ProgressBar.new()
	meter.show_percentage = false
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meter.add_theme_stylebox_override("background", _style(Color("30372b")))
	meter.add_theme_stylebox_override("fill", _style(color))
	_place(meter, rect)
	return meter

func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_content_margin_all(9 if border.a > 0 else 0)
	style.set_corner_radius_all(3)
	return style
