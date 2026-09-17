extends CanvasLayer
class_name BlacksmithOverlay
## Production workstations. Input stays local to this UI; the hideout owns pause/cursor.
signal closed

const SYSTEM := preload("res://scripts/smithing_system.gd")
const VISUAL := preload("res://scripts/blacksmith_visual.gd")
const FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const INK := Color(0.027, 0.023, 0.019, 0.96)
const GOLD := Color(0.74, 0.56, 0.30)
const IVORY := Color(0.88, 0.84, 0.73)
var system: RefCounted
var inventory_model: ExpeditionInventory
var overlay_root: Control
var scene_viewport: SubViewport
var visual: Node3D
var camera: Camera3D
var station := "forge"
var selected_section := 1
var status_label: Label
var heat_label: Label
var detail_label: Label
var instruction_label: Label
var progress_label: Label
var rhythm: ProgressBar
var heat_bar: ProgressBar
var actions: VBoxContainer
var weapon_picker: OptionButton
var section_buttons: Array[Button] = []
var action_buttons: Dictionary = {}
var _phase := 0.0
var _holding := false
var _held_time := 0.0
var _pull_start := Vector2.ZERO
var _refresh_clock := 0.0
var _sound: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 45
	_build()
	overlay_root.hide()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visual.process_mode = Node.PROCESS_MODE_DISABLED

func is_open() -> bool:
	return is_instance_valid(overlay_root) and overlay_root.visible

func open_for_inventory(bag: ExpeditionInventory) -> void:
	if system == null or inventory_model != bag:
		inventory_model = bag
		system = SYSTEM.new()
		system.setup(bag)
		if not str(bag.equipment.get("weapon", "")).is_empty():
			system.select_weapon(str(bag.equipment["weapon"]))
	overlay_root.show()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	visual.process_mode = Node.PROCESS_MODE_INHERIT
	show_station("forge")
	_refresh()

func close() -> void:
	if not is_open():
		return
	_holding = false
	overlay_root.hide()
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	visual.process_mode = Node.PROCESS_MODE_DISABLED
	closed.emit()

func cancel_work() -> void:
	if system != null:
		system.cancel()
	_holding = false
	if is_instance_valid(overlay_root):
		overlay_root.hide()
		scene_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		visual.process_mode = Node.PROCESS_MODE_DISABLED

func _build() -> void:
	overlay_root = Control.new()
	overlay_root.name = "BlacksmithWorkshop"
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay_root)
	var theme := Theme.new()
	var readable_font := FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	theme.default_font = readable_font
	theme.default_font_size = 15
	overlay_root.theme = theme
	var backdrop := SubViewportContainer.new()
	backdrop.name = "WorkbenchInteractionSurface"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.stretch = true
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_work_surface_input)
	overlay_root.add_child(backdrop)
	scene_viewport = SubViewport.new()
	scene_viewport.name = "RealBlacksmith3D"
	scene_viewport.size = Vector2i(1280, 720)
	scene_viewport.own_world_3d = true
	scene_viewport.handle_input_locally = false
	scene_viewport.gui_disable_input = true
	scene_viewport.audio_listener_enable_3d = false
	scene_viewport.msaa_3d = Viewport.MSAA_2X
	backdrop.add_child(scene_viewport)
	visual = VISUAL.new()
	scene_viewport.add_child(visual)
	camera = Camera3D.new()
	camera.current = true
	scene_viewport.add_child(camera)
	visual.set_camera(camera)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.035, 0.028)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.53, 0.57, 0.61)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 0.5
	environment.ssao_intensity = 1.3
	environment.glow_enabled = true
	environment_node.environment = environment
	scene_viewport.add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, -25, 0)
	key.light_color = Color(0.80, 0.85, 0.91)
	key.light_energy = 1.0
	key.shadow_enabled = true
	scene_viewport.add_child(key)
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 66
	top.add_theme_stylebox_override("panel", _style(Color(0.025, 0.021, 0.017, 0.88)))
	overlay_root.add_child(top)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	top.add_child(header)
	var title := _label("성소의 대장간", 25)
	title.custom_minimum_size.x = 190
	header.add_child(title)
	for entry in [["forge", "01  무기 제작"], ["grip", "02  손잡이"], ["blade", "03  칼날 보강"], ["rune", "04  룬 세공"]]:
		var button := _button(entry[1], func(): show_station(entry[0]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(button)
	var leave := _button("ESC  나가기", close)
	header.add_child(leave)
	var panel := PanelContainer.new()
	panel.name = "BlacksmithActionPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -302
	panel.offset_right = -18
	panel.offset_top = 86
	panel.offset_bottom = -100
	panel.add_theme_stylebox_override("panel", _style(INK))
	overlay_root.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	actions = VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", 10)
	scroll.add_child(actions)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -78
	bottom.add_theme_stylebox_override("panel", _style(Color(0.025, 0.021, 0.017, 0.94)))
	overlay_root.add_child(bottom)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 7)
	bottom.add_child(footer)
	status_label = _label("도면을 선택해 철과 숯을 화로에 넣으세요.", 17)
	footer.add_child(status_label)
	instruction_label = _label("", 13)
	instruction_label.modulate = Color(0.72, 0.71, 0.65)
	footer.add_child(instruction_label)
	var work_meter := VBoxContainer.new()
	work_meter.name = "BlacksmithWorkMeter"
	work_meter.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	work_meter.position = Vector2(-310, -180)
	work_meter.size = Vector2(370, 90)
	work_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.add_child(work_meter)
	progress_label = _label("", 14)
	work_meter.add_child(progress_label)
	rhythm = ProgressBar.new()
	rhythm.custom_minimum_size = Vector2(350, 6)
	rhythm.show_percentage = false
	rhythm.add_theme_stylebox_override("background", _style(Color(0.07, 0.06, 0.04, 0.86)))
	rhythm.add_theme_stylebox_override("fill", _style(GOLD))
	work_meter.add_child(rhythm)
	var row := HBoxContainer.new()
	work_meter.add_child(row)
	for index in 3:
		var b := _button(["A  뿌리", "S  중앙", "D  끝"][index], func(): selected_section = index; _refresh())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		section_buttons.append(b)
	_sound = AudioStreamPlayer.new()
	_sound.volume_db = -17
	add_child(_sound)

func show_station(next: String) -> void:
	station = next if next in ["forge", "grip", "blade", "rune"] else "forge"
	_holding = false
	_rebuild_actions()
	var stage: String = str(system.snapshot().get("stage", "idle")) if system != null else "idle"
	_set_camera(({"fire": "forge", "anvil": "anvil", "quenched": "quench", "finished": "upgrade"}.get(stage, "overview")) if station == "forge" else "upgrade")
	_refresh()

func _rebuild_actions() -> void:
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	action_buttons.clear()
	heat_label = _label("", 21)
	actions.add_child(heat_label)
	heat_bar = ProgressBar.new()
	heat_bar.max_value = 1300
	heat_bar.show_percentage = false
	heat_bar.custom_minimum_size.y = 7
	actions.add_child(heat_bar)
	detail_label = _label("", 13)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(detail_label)
	if station == "forge":
		_add_action("철 장검 만들기", "start", "iron_longsword")
		_add_action("철 한손검 만들기", "start_short", "iron_arming_sword")
		_add_action("풀무 당기기  [Space]", "pump_bellows")
		_add_action("모루로 옮기기  [E]", "move_to_anvil")
		_add_action("칼 뒤집기  [R]", "flip_blade")
		_add_action("다시 가열하기  [F]", "return_to_fire")
		_add_action("물에 담금질  [Q]", "quench")
		_add_action("완성품 가방에 넣기", "finish")
		_add_action("작업 포기 · 투입 재료 소실", "cancel")
	else:
		weapon_picker = OptionButton.new()
		weapon_picker.name = "SmithingWeaponPicker"
		weapon_picker.custom_minimum_size.y = 36
		actions.add_child(weapon_picker)
		_populate_weapons()
		weapon_picker.item_selected.connect(func(index: int): perform_action("select_weapon", weapon_picker.get_item_metadata(index)))
		if station == "grip":
			_add_action("가죽 손잡이로 교체", "replace_grip", "leather_grip")
			_add_action("균형 손잡이로 교체", "balanced_grip", "balanced_grip")
		elif station == "blade":
			_add_action("강철 날 덧대기", "reinforce_blade", "steel_edge")
			_add_action("은 날 덧대기", "silver_edge", "silver_edge")
		else:
			_add_action("홈 파기 · 화면에서 눌렀다 놓기", "drill_socket")
			_add_action("룬 돌조각 끼우기", "insert_rune", "rune_fragment")
			_add_action("불씨 룬 끼우기", "ember_rune", "ember_rune")
		var hint := _label("선택한 검 한 자루에 적용됩니다.\n부품과 룬은 중개인에게 구입할 수 있습니다.", 12)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		actions.add_child(hint)

func _populate_weapons() -> void:
	weapon_picker.clear()
	if system == null:
		return
	var snapshot: Dictionary = system.snapshot()
	var selected_found := false
	for weapon: Dictionary in snapshot.get("weapons", []):
		var uid := str(weapon.get("uid", weapon.get("item_id", "")))
		var index := weapon_picker.item_count
		var mods: Dictionary = weapon.get("smithing", {})
		weapon_picker.add_item("%s · 품질 %d%s" % [str(weapon.get("name", "검")), roundi(float(mods.get("quality", 0))), " · 장착" if weapon.get("equipped", false) else ""] )
		weapon_picker.set_item_metadata(index, uid)
		if uid == str((snapshot.get("selected_weapon", {}) as Dictionary).get("uid", "")):
			selected_found = true
			weapon_picker.select(index)
	if not selected_found and weapon_picker.item_count > 0:
		# OptionButton displays index zero without emitting item_selected. Bind
		# that visible sword even when a bow/staff/flail occupies the weapon slot.
		system.select_weapon(str(weapon_picker.get_item_metadata(0)))
		weapon_picker.select(0)

func _add_action(title: String, action: String, payload: Variant = null) -> void:
	var button := _button(title, func(): perform_action(action, payload))
	button.name = "Smithing_" + action
	button.tooltip_text = title
	actions.add_child(button)
	action_buttons[action] = button

func perform_action(action: String, payload: Variant = null) -> Dictionary:
	if system == null:
		return {"accepted": false, "message": "작업대를 먼저 여세요."}
	var result: Dictionary
	match action:
		"start", "start_short": result = system.start(str(payload) if payload != null else "iron_longsword")
		"hammer":
			var hit: Dictionary = payload if payload is Dictionary else {"section": selected_section, "accuracy": _timing_accuracy()}
			selected_section = clampi(int(hit.get("section", selected_section)), 0, 2)
			result = system.hammer(int(hit.get("section", selected_section)), float(hit.get("accuracy", 1.0)))
		"select_weapon": result = system.select_weapon(str(payload))
		"replace_grip", "balanced_grip": result = system.replace_grip(str(payload))
		"reinforce_blade", "silver_edge": result = system.reinforce_blade(str(payload))
		"drill_socket": result = system.drill_socket(float(payload) if payload is float or payload is int else _timing_accuracy())
		"insert_rune", "ember_rune": result = system.insert_rune(str(payload))
		"pump_bellows", "move_to_anvil", "flip_blade", "return_to_fire", "quench", "finish", "cancel": result = system.call(action)
		_: result = {"accepted": false, "message": "알 수 없는 작업입니다."}
	status_label.text = str(result.get("message", ""))
	if bool(result.get("accepted", false)):
		var visual_action: String = {"start_short": "start", "balanced_grip": "replace_grip", "silver_edge": "reinforce_blade", "ember_rune": "insert_rune"}.get(action, action)
		visual.animate_action(str(visual_action))
		if action in ["start", "start_short", "pump_bellows", "return_to_fire"]: _set_camera("forge")
		elif action in ["move_to_anvil", "hammer", "flip_blade"]: _set_camera("anvil")
		elif action == "quench": _set_camera("quench")
		elif action == "finish": _set_camera("upgrade")
		_play_sound(action)
	_refresh()
	return result

func _set_camera(view: String) -> void:
	if not is_instance_valid(camera): return
	visual.set_station(view)
	var pose: Dictionary = visual.camera_pose(view)
	camera.position = pose.get("position", Vector3(0, 2.2, 3.1))
	camera.look_at(pose.get("target", Vector3(0, 0.8, 0)))
	camera.fov = float(pose.get("fov", 57))
	# Reserve the right edge for the tools, keeping the working steel unobscured.
	camera.h_offset = 0.23 if view != "overview" else 0.35

func _process(delta: float) -> void:
	if not is_open() or system == null: return
	_phase += delta
	if _holding: _held_time += delta
	system.tick(delta)
	rhythm.value = _timing_accuracy() * 100.0
	_refresh_clock += delta
	if _refresh_clock >= 0.08:
		_refresh_clock = 0
		_refresh()

func _timing_accuracy() -> float:
	return clampf(1.0 - absf((_held_time if _holding else fmod(_phase, 1.5)) - 0.75) / 0.75, 0.0, 1.0)

func _refresh() -> void:
	if system == null or not is_instance_valid(heat_label): return
	var state: Dictionary = system.snapshot()
	state["station"] = "upgrade" if station != "forge" else str(state.get("stage", "idle"))
	state["work_mode"] = station
	state["selected_section"] = selected_section
	state["hammer_charge"] = clampf(_held_time / 0.75, 0, 1) if _holding else 0.0
	visual.update_state(state)
	var stage := str(state.get("stage", "idle"))
	progress_label.get_parent().visible = station == "rune" or (station == "forge" and stage == "anvil")
	var temp := float(state.get("temperature", 20))
	heat_bar.value = temp
	heat_bar.visible = station == "forge"
	heat_label.text = "%d °C  ·  %s" % [roundi(temp), {"idle": "준비", "fire": "화로", "anvil": "모루", "quenched": "담금질 완료", "finished": "완성"}.get(stage, stage)] if station == "forge" else {"grip": "손잡이 교체", "blade": "칼날 보강", "rune": "홈 파기 · 룬 부여"}.get(station, "")
	if station == "forge":
		var guide: String = {
			"idle": "장검 · " + _cost_text(SYSTEM.RECIPES.iron_longsword.cost) + "\n한손검 · " + _cost_text(SYSTEM.RECIPES.iron_arming_sword.cost),
			"fire": "풀무로 700–1,000 °C까지 가열\n노란빛이 돌면 모루로 옮기세요.",
			"anvil": "LMB를 0.75초 눌렀다 놓으세요.\n앞뒤 세 구간을 모두 성형합니다.\n700 °C 아래로 식으면 재가열하세요.",
			"quenched": "담금질 완료.\n손잡이를 조립하고 가방에 보관하세요.",
			"finished": "완성된 검을 가방에서 장착하세요.\n손잡이 · 칼날 · 룬 탭에서 개조할 수 있습니다.",
		}.get(stage, "")
		detail_label.text = guide + "\n\n보유 철 %d · 숯 %d\n품질 %d / 100\n\n닫기: 작업 유지\n포기/장면 이동: 투입 재료 소실" % [inventory_model.count_item("iron_ingot"), inventory_model.count_item("forge_charcoal"), roundi(float(state.get("quality", 100)))]
		var progress := 0.0
		for side: Array in state.get("sections", []):
			for amount: Variant in side: progress += float(amount)
		progress_label.text = "%s 면  ·  %s  ·  성형 %d%%" % ["앞" if int(state.get("side", 0)) == 0 else "뒤", ["뿌리", "중앙", "끝"][selected_section], roundi(progress / 6.0 * 100.0)]
		instruction_label.text = "화로: 화면을 누르고 아래로 당기기 / Space 풀무 · E 모루 이동 · 모루: LMB 0.75초 눌렀다 놓기 · A/S/D 타격 위치 · R 뒤집기 · F 재가열 · Q 담금질"
	else:
		var weapon: Dictionary = state.get("selected_weapon", {})
		var mods: Dictionary = weapon.get("smithing", {})
		var upgrade_info := ""
		if station == "grip":
			upgrade_info = "가죽: 기력 −12% · " + _cost_text(SYSTEM.GRIPS.leather_grip.cost) + "\n균형: 기력 −22% · " + _cost_text(SYSTEM.GRIPS.balanced_grip.cost)
			upgrade_info += "\n\n보유 가죽 %d · 부속 %d\n현재: %s" % [inventory_model.count_item("grip_leather"), inventory_model.count_item("steel_fitting"), str(SYSTEM.GRIPS.get(str(mods.get("grip", "")), {"name": "기본 손잡이"}).name)]
		elif station == "blade":
			upgrade_info = "강철: 피해 +5 · " + _cost_text(SYSTEM.REINFORCEMENTS.steel_edge.cost) + "\n은: 피해 +8 · " + _cost_text(SYSTEM.REINFORCEMENTS.silver_edge.cost)
			upgrade_info += "\n\n보유 철 %d · 부속 %d · 은 %d\n현재: %s" % [inventory_model.count_item("iron_ingot"), inventory_model.count_item("steel_fitting"), inventory_model.count_item("silver_inlay"), str(SYSTEM.REINFORCEMENTS.get(str(mods.get("reinforcement", "")), {"name": "보강 없음"}).name)]
		else:
			upgrade_info = "홈 1개: 강철 부속 1 · 천공 3회\n청록 룬: 피해 +3 · 적중 회복 +2\n잿불 룬: 타격 피해 +6\n\n룬 홈 %d / 2 · 삽입 %d\n천공 %d%% · 보유 부속 %d" % [int(mods.get("sockets", 0)), (mods.get("runes", []) as Array).size(), roundi(float(mods.get("drill_progress", 0)) * 100), inventory_model.count_item("steel_fitting")]
		detail_label.text = upgrade_info
		progress_label.text = "정밀 작업 · 표시가 가득 찰 때 놓으세요" if station == "rune" else "검의 부품을 선택해 교체하세요"
		instruction_label.text = "룬 세공: 화면에서 LMB 0.75초 눌렀다 놓기 · 홈을 세 차례 가공한 뒤 조각 삽입 · ESC 공방 닫기" if station == "rune" else "개조할 검과 부품을 선택하세요 · 교체한 부품은 소모됩니다 · 완성한 검은 가방에서 장착 · ESC 공방 닫기"
	for index in section_buttons.size():
		section_buttons[index].visible = station == "forge" and stage == "anvil"
		section_buttons[index].modulate = GOLD if index == selected_section else IVORY
	rhythm.visible = (station == "forge" and stage == "anvil") or station == "rune"
	for action: String in action_buttons:
		var enabled := true
		match action:
			"start", "start_short": enabled = stage in ["idle", "finished"]
			"pump_bellows": enabled = stage == "fire"
			"move_to_anvil": enabled = stage == "fire" and temp >= 700 and temp <= 1000
			"flip_blade", "return_to_fire": enabled = stage == "anvil"
			"quench": enabled = stage in ["fire", "anvil"] and bool(state.get("shaping_complete", false))
			"finish": enabled = stage == "quenched"
			"cancel": enabled = stage in ["fire", "anvil", "quenched"]
		(action_buttons[action] as Button).disabled = not enabled
		if station == "forge":
			(action_buttons[action] as Button).visible = enabled or (action == "move_to_anvil" and stage == "fire")

func _work_surface_input(event: InputEvent) -> void:
	if not is_open(): return
	if station not in ["forge", "rune"]: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_holding = true
			_held_time = 0
			_pull_start = event.position
		else:
			if not _holding: return
			var accuracy := _timing_accuracy()
			_holding = false
			var stage := str(system.snapshot().get("stage", "idle"))
			if station == "rune": perform_action("drill_socket", accuracy)
			elif stage == "fire":
				if event.position.y - _pull_start.y >= 24 or _held_time >= 0.25: perform_action("pump_bellows")
			elif stage == "anvil": perform_action("hammer", {"section": selected_section, "accuracy": accuracy})
		overlay_root.accept_event()

func _input(event: InputEvent) -> void:
	if not is_open() or not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode != KEY_ESCAPE and station != "forge": return
	match event.physical_keycode:
		KEY_ESCAPE: close()
		KEY_A: selected_section = 0
		KEY_S: selected_section = 1
		KEY_D: selected_section = 2
		KEY_SPACE: perform_action("pump_bellows")
		KEY_E: perform_action("move_to_anvil")
		KEY_R: perform_action("flip_blade")
		KEY_F: perform_action("return_to_fire")
		KEY_Q: perform_action("quench")
		_: return
	get_viewport().set_input_as_handled()
	_refresh()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 36
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", IVORY)
	button.add_theme_color_override("font_hover_color", Color(1, 0.87, 0.60))
	button.add_theme_stylebox_override("normal", _style(Color(0.08, 0.066, 0.045, 0.92)))
	button.add_theme_stylebox_override("hover", _style(Color(0.18, 0.12, 0.06, 0.96)))
	button.pressed.connect(callback)
	return button

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", IVORY)
	label.add_theme_font_size_override("font_size", font_size)
	return label

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.39, 0.30, 0.17, 0.65)
	style.set_border_width_all(1)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _play_sound(action: String) -> void:
	if not is_instance_valid(_sound) or DisplayServer.get_name() in ["embedded", "headless"]: return
	var metallic := action in ["hammer", "drill_socket", "reinforce_blade", "silver_edge"]
	if not metallic and action not in ["pump_bellows", "quench", "insert_rune", "ember_rune"]: return
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var data := PackedByteArray()
	data.resize(11025 * 2)
	var random := RandomNumberGenerator.new()
	random.seed = 73
	for index in 11025:
		var t := float(index) / 22050.0
		var sample := (sin(t * TAU * 1240) * 0.45 + sin(t * TAU * 1967) * 0.28 + random.randf_range(-0.25, 0.25)) * exp(-t * 15) if metallic else random.randf_range(-0.55, 0.55) * sin(t * PI * 2) * exp(-t * 4)
		data.encode_s16(index * 2, roundi(clampf(sample, -1, 1) * 26000))
	stream.data = data
	_sound.stream = stream
	_sound.play()


func _cost_text(cost: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item_id: String in cost:
		parts.append("%s %d" % [ExpeditionInventory.get_item_name(item_id), int(cost[item_id])])
	return " · ".join(parts)
