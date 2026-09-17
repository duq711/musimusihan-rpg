extends "res://scripts/game.gd"

const CATALOG := preload("res://scripts/test_room_catalog.gd")
const ART_GALLERY := preload("res://scripts/dark_fantasy_gallery.gd")
const STATUS_CONTROLS := preload("res://scripts/test_room_status_controls.gd")
const SMITHING_SYSTEM := preload("res://scripts/smithing_system.gd")
const ALCHEMY_SYSTEM := preload("res://scripts/alchemy_system.gd")
const FINGER_JOINT_CONTROLS := preload("res://scripts/finger_joint_controls.gd")
const ROOM_FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")
const TEST_ROOM_PATH := "res://test_room.tscn"
const HOME_POSITION := Vector3(0, 1.0, 12)
const REFERENCE_MOTION_START := Vector3(0.0, 1.0, 10.0)
const REFERENCE_MOTION_TARGET := Vector3(0.0, 1.0, 1.0)

var art_gallery: Control
var panel_open := false
var enemy_ai_enabled := false
var test_panel: ColorRect
var entry_list: VBoxContainer
var status_label: Label
var room_hint: Label
var resume_button: Button
var status_controls: Control
var stat_controls_button: Button
var entry_scroll: ScrollContainer
var panel_margin: MarginContainer
var panel_actions: GridContainer
var panel_content: VBoxContainer
var panel_heading: Label
var panel_explanation: Label
var category_buttons: Array[Button] = []
var selected_category := "기본"
var feature_entries: Array[Dictionary] = []
var room_font: FontVariation
var archery_power_target: DungeonEnemy
var archery_power_last_damage := 0.0
var flail_near_target: DungeonEnemy
var flail_far_target: DungeonEnemy
var flail_last_damage := 0.0
var arm_motion_target: DungeonEnemy
var arm_motion_chest: DungeonLootChest
var finger_joint_controls: Control


func _ready() -> void:
	TestRoomSandbox.begin()
	room_font = FontVariation.new()
	room_font.base_font = ROOM_FONT
	room_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	child_entered_tree.connect(_on_test_actor_added)
	super._ready()
	player.attack_landed.connect(_on_flail_fixture_hit)
	player.position = HOME_POSITION
	feature_entries = CATALOG.entries()
	_build_test_panel()
	_show_test_panel()


func _spawn_hud() -> void:
	super._spawn_hud()
	hud.location_label.text = "성소 테스트룸"


func _refresh_survival_hud(snapshot := {}) -> void:
	super._refresh_survival_hud(snapshot)
	var sign := get_node_or_null("StressInstructions") as Label3D
	if is_instance_valid(sign) and not sign.is_queued_for_deletion():
		# Fixture labels follow custom edits and ordinary recovery, not only the
		# initial preset, so they never contradict the real stress HUD.
		sign.text = "스트레스 %d / 100 · %s\n60 환청 · 80 환영\nC 야영 · F2 수치 조절" % [roundi(ExpeditionSession.stress), StressProfile.stage_name(ExpeditionSession.stress)]
		hud.objective_label.text = "스트레스 %d · C 야영 / F2 수치 조절" % roundi(ExpeditionSession.stress)


func _on_test_actor_added(child: Node) -> void:
	# The controller and UI must run while paused; simulation actors must not.
	if child is DungeonPlayer or child is DungeonEnemy or child is RuneTrap or child is MagicProjectile or child is ArrowProjectile or child is FlailProjectile:
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	if child is ArrowProjectile:
		child.hit_target.connect(_on_archery_power_hit)


func _build_environment() -> void:
	super._build_environment()
	var environment := (get_node("WorldEnvironment") as WorldEnvironment).environment
	environment.ambient_light_color = Color(0.4, 0.51, 0.52)
	environment.ambient_light_energy = 0.65
	environment.fog_density = 0.003
	(get_node("ColdMoonlight") as DirectionalLight3D).light_energy = 0.75
	for at in [Vector3(0, 4.5, -5), Vector3(-8, 4, 7), Vector3(8, 4, 4)]:
		var light := OmniLight3D.new()
		light.name = "TestRoomWorkLight"
		light.position = at
		light.light_color = Color(0.75, 0.84, 0.81)
		light.light_energy = 3.2
		light.light_specular = 0.0
		light.omni_range = 18
		add_child(light)


func _build_dungeon() -> void:
	floor_material.roughness = 0.85
	_add_static_box("TestFloor", Vector3(0, -0.5, 0), Vector3(28, 1, 34), floor_material)
	_add_static_box("WestWall", Vector3(-14, 2.5, 0), Vector3(0.6, 5, 34), stone_material)
	_add_static_box("EastWall", Vector3(14, 2.5, 0), Vector3(0.6, 5, 34), stone_material)
	_add_static_box("NorthWall", Vector3(0, 2.5, -17), Vector3(28, 5, 0.6), stone_material)
	_add_static_box("SouthWall", Vector3(0, 2.5, 17), Vector3(28, 5, 0.6), stone_material)
	for index in range(4):
		var height := 0.25 * (index + 1)
		_add_static_box("JumpStep%d" % index, Vector3(9, height * 0.5, 7.0 - index * 1.4), Vector3(3, height, 1.25), stone_material)
	for x in [-12.0, 12.0]:
		for z in [-10.0, 2.0, 13.0]:
			_add_torch(Vector3(x, 2.7, z), Color(0.65, 0.84, 0.77))
	_add_station_sign("01  전투 · 마법", Vector3(-5, 3.2, -7))
	_add_station_sign("02  함정 조사", Vector3(8, 2.8, -7))
	_add_station_sign("03  보급 · 수색", Vector3(-9, 2.8, 6))
	_add_station_sign("04  이동 · 점프", Vector3(9, 2.8, 2))
	_add_station_sign("05  귀환문", Vector3(0, 4.6, -15.2))


func _add_station_sign(text_value: String, at: Vector3) -> void:
	var sign := Label3D.new()
	sign.text = text_value
	sign.font = room_font
	sign.font_size = 48
	sign.pixel_size = 0.008
	sign.modulate = Color(0.77, 0.88, 0.81)
	sign.outline_size = 10
	sign.no_depth_test = false
	sign.position = at
	sign.name = "TestStationSign"
	add_child(sign)


func _spawn_encounters() -> void:
	_spawn_enemy("망각의 검지기", Vector3(-6, 1, -3), 82, 21, 2.2, Color(0.145, 0.18, 0.19), "bleeding")
	_spawn_enemy("굶주린 성소지기", Vector3(-2, 1, -3), 68, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	_spawn_trap("속박의 룬 압력판", Vector3(8, 0, -2), 32, 0.86, 0.62, "curse")
	_spawn_trap("피를 부르는 철침진", Vector3(11, 0, -5), 38, 1.12, 0.37, "bleeding")
	_set_enemy_ai(enemy_ai_enabled)


func _spawn_loot_chests() -> void:
	# Paginate the authoritative item catalog: a normal chest holds 20 stacks.
	var stacks: Array = []
	var page := 0
	for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
		var definition := ExpeditionInventory.get_item_definition(item_id)
		stacks.append({"id": item_id, "quantity": mini(3, int(definition.get("stack_max", 1)))})
		if stacks.size() == 12:
			_spawn_catalog_chest(stacks, page)
			stacks = []
			page += 1
	if not stacks.is_empty():
		_spawn_catalog_chest(stacks, page)


func _spawn_catalog_chest(stacks: Array, page: int) -> void:
	_spawn_loot_chest("시험 보급 상자 %d" % (page + 1), Vector3(-10 + (page % 2) * 3, 0, 7 - floori(page / 2.0) * 3), stacks, "전체 물품 카탈로그 · 조사와 수색은 실제 규칙 적용")


func _build_test_panel() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TestRoomControls"
	layer.layer = 70
	add_child(layer)
	room_hint = Label.new()
	room_hint.text = "테스트룸  /  F2 · 시험 메뉴  /  Esc · 일시정지"
	room_hint.add_theme_font_override("font", room_font)
	room_hint.add_theme_font_size_override("font_size", 15)
	room_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	room_hint.position = Vector2(-240, -40)
	room_hint.size = Vector2(480, 30)
	room_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(room_hint)
	test_panel = ColorRect.new()
	test_panel.name = "TestRoomPanel"
	test_panel.color = Color(0.015, 0.022, 0.022, 0.96)
	test_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var ui_theme := Theme.new()
	ui_theme.default_font = room_font
	ui_theme.default_font_size = 16
	ui_theme.set_color("font_color", "Button", Color(0.86, 0.90, 0.85))
	test_panel.theme = ui_theme
	layer.add_child(test_panel)
	var margin := MarginContainer.new()
	panel_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 64)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	test_panel.add_child(margin)
	var content := VBoxContainer.new()
	panel_content = content
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var heading_row := HBoxContainer.new()
	content.add_child(heading_row)
	var heading := Label.new()
	panel_heading = heading
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.text = "성소 테스트룸"
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color(0.86, 0.79, 0.59))
	heading_row.add_child(heading)
	stat_controls_button = _make_button("수치 조절", run_feature.bind("survival_controls"))
	heading_row.add_child(stat_controls_button)
	var explanation := Label.new()
	panel_explanation = explanation
	explanation.text = "실제 게임 기능을 바로 시험합니다. 원래 원정은 보존되며, 메인 메뉴로 나가면 복원됩니다."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.add_theme_color_override("font_color", Color(0.66, 0.73, 0.70))
	content.add_child(explanation)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	content.add_child(tabs)
	for category in CATALOG.CATEGORIES:
		var count := feature_entries.filter(func(entry: Dictionary) -> bool: return entry.category == category).size()
		var button := _make_button("%s  %d" % [category, count], func() -> void: _select_category(category))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)
		category_buttons.append(button)
	var scroll := ScrollContainer.new()
	entry_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	entry_list = VBoxContainer.new()
	entry_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry_list.add_theme_constant_override("separation", 7)
	scroll.add_child(entry_list)
	status_label = Label.new()
	status_label.name = "TestStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.max_lines_visible = 2
	status_label.add_theme_color_override("font_color", Color(0.58, 0.83, 0.72))
	content.add_child(status_label)
	var actions := GridContainer.new()
	panel_actions = actions
	actions.columns = 4
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 6)
	content.add_child(actions)
	resume_button = _make_button("시험장 들어가기 · F2", _hide_test_panel)
	actions.add_child(resume_button)
	actions.add_child(_make_button("체력 · 기력 회복", func() -> void: _recover_player(); _status("체력과 기력을 회복했습니다.")))
	actions.add_child(_make_button("테스트룸 초기화", reset_room))
	actions.add_child(_make_button("메인 메뉴로 나가기", leave_room))
	for button in actions.get_children():
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	get_viewport().size_changed.connect(_resize_test_panel)
	_resize_test_panel()
	_select_category(selected_category)
	_status("%d개 시험 항목 · AI 정지 표적으로 시작 · F2는 언제든 시험 메뉴" % feature_entries.size())


func _resize_test_panel() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var compact := viewport_size.x < 900.0 or viewport_size.y < 600.0
	panel_actions.columns = 2 if viewport_size.x < 900.0 else 4
	for side in ["left", "right"]:
		panel_margin.add_theme_constant_override("margin_" + side, 20 if compact else 64)
	for side in ["top", "bottom"]:
		panel_margin.add_theme_constant_override("margin_" + side, 12 if compact else 30)
	panel_content.add_theme_constant_override("separation", 7 if compact else 12)
	panel_heading.add_theme_font_size_override("font_size", 24 if compact else 30)
	panel_explanation.visible = viewport_size.y >= 600.0
	for button: Button in panel_actions.get_children():
		button.custom_minimum_size.y = 36 if compact else 42
		button.add_theme_font_size_override("font_size", 13 if compact else 16)


func _make_button(caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 42
	button.pressed.connect(action)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.075, 0.11, 0.105)
	normal.border_color = Color(0.25, 0.37, 0.32)
	normal.set_border_width_all(1)
	normal.set_content_margin_all(12)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.21, 0.18)
	hover.border_color = Color(0.56, 0.65, 0.46)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button


func _select_category(category: String) -> void:
	_commit_test_status_edits()
	selected_category = category
	for child in entry_list.get_children():
		entry_list.remove_child(child)
		child.queue_free()
	status_controls = null
	entry_scroll.scroll_vertical = 0
	for index in range(category_buttons.size()):
		category_buttons[index].set_pressed_no_signal(CATALOG.CATEGORIES[index] == category)
	for entry in feature_entries:
		if entry.category != category:
			continue
		if entry.action == "survival_controls":
			status_controls = STATUS_CONTROLS.new()
			status_controls.name = "Feature_survival_controls"
			status_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			status_controls.stat_changed.connect(set_test_stat)
			entry_list.add_child(status_controls)
			status_controls.name = "Feature_survival_controls"
			_refresh_test_status_controls()
			continue
		var button := _make_button(entry.title + "\n" + entry.detail, run_feature.bind(entry.id))
		button.name = "Feature_" + str(entry.id).replace(":", "_")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 72
		entry_list.add_child(button)


func _show_test_panel() -> void:
	_close_finger_joint_controls(false)
	_close_art_gallery(false)
	if not is_instance_valid(test_panel) or is_instance_valid(loading_screen):
		return
	if game_mode == GameMode.INVENTORY:
		return
	cancel_camp("시험 메뉴 열기", false)
	suspend_stress_effects()
	player.prepare_for_inventory()
	if player.combat_state == DungeonPlayer.CombatState.DEAD:
		_recover_player()
	panel_open = true
	test_panel.show()
	room_hint.hide()
	hud.hide_overlay()
	game_mode = GameMode.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_test_status_controls()
	resume_button.grab_focus()


func _hide_test_panel() -> void:
	_commit_test_status_edits()
	var focused := get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and test_panel.is_ancestor_of(focused):
		focused.release_focus()
	panel_open = false
	test_panel.hide()
	room_hint.show()
	hud.hide_overlay()
	game_mode = GameMode.RUNNING
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _pause_game() -> void:
	_show_test_panel()


func _resume_game() -> void:
	_hide_test_panel()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(loading_screen):
		return
	if is_instance_valid(finger_joint_controls):
		if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F2 or event.physical_keycode == KEY_F2)):
			_close_finger_joint_controls()
			get_viewport().set_input_as_handled()
		return
	if is_instance_valid(art_gallery):
		if event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F2 or event.physical_keycode == KEY_F2)):
			_close_art_gallery()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F2 or event.physical_keycode == KEY_F2):
		if game_mode == GameMode.INVENTORY:
			_close_inventory()
			if game_mode == GameMode.INVENTORY:
				get_viewport().set_input_as_handled()
				return
		if panel_open:
			_hide_test_panel()
		else:
			_show_test_panel()
		get_viewport().set_input_as_handled()
		return
	if panel_open:
		if event.is_action_pressed("pause"):
			_hide_test_panel()
			get_viewport().set_input_as_handled()
		return
	if game_mode in [GameMode.DEAD, GameMode.WON] and event.is_action_pressed("restart"):
		reset_room()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func run_feature(feature_id: String) -> void:
	if is_instance_valid(loading_screen):
		return
	var entry: Dictionary = {}
	for candidate in feature_entries:
		if candidate.id == feature_id:
			entry = candidate
			break
	if entry.is_empty():
		return
	_close_finger_joint_controls(false)
	_close_art_gallery(false)
	_commit_test_status_edits()
	cancel_camp("시험 항목 변경", false)
	suspend_stress_effects()
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	if feature_id not in ["player_hands_greybox", "player_hands_detailed"]:
		player.set_hands_visual_profile("original")
	var payload := str(entry.payload)
	match str(entry.action):
		"performance":
			TestRoomSandbox.toggle_performance_monitor()
			_hide_test_panel()
		"survival_controls":
			_show_test_panel()
			_select_category("생존")
			status_controls.focus_stat("stress")
			_status("현재 시험의 수치를 직접 바꿉니다. F2로 재개하면 회복·소모와 스트레스 연출이 이어집니다.")
		"movement":
			_teleport(Vector3(9, 1, 10))
			_hide_test_panel()
		"wall_equipment":
			_prepare_wall_equipment()
			_hide_test_panel()
		"armed", "skeleton":
			_prepare_duel(entry.action == "skeleton", true)
			_equip_weapon("rusted_sword")
			_hide_test_panel()
		"flail":
			_prepare_flail()
			_hide_test_panel()
		"camping":
			_prepare_camping()
			_hide_test_panel()
		"cooking":
			_prepare_cooking()
			_hide_test_panel()
		"stress":
			_prepare_stress(float(payload))
			_hide_test_panel()
			_update_stress_presentation()
		"archery":
			_prepare_archery()
			_hide_test_panel()
		"archery_accuracy":
			_prepare_archery(true)
			_hide_test_panel()
		"archery_power":
			_prepare_archery(false, true)
			_hide_test_panel()
		"torch":
			player.toggle_torch()
			_hide_test_panel()
		"inventory":
			_hide_test_panel()
			_open_inventory()
		"dark_fantasy_gallery":
			_open_art_gallery()
		"player_appearance":
			# Open the shipped inventory portrait: it instantiates the same 3D
			# appearance as DungeonPlayer, rather than a test-only mannequin.
			_hide_test_panel()
			_open_inventory()
			inventory_overlay.player_portrait.set_view_angle(0.0)
			inventory_overlay.set_status("플레이어 3D 외형 · 회전하여 두건·누비옷·가죽 장비 확인 · F2로 시험 메뉴")
		"player_arm_motion":
			_prepare_player_arm_motion()
			_hide_test_panel()
		"player_hands_greybox":
			if _prepare_player_hands_greybox():
				_hide_test_panel()
		"player_hands_detailed":
			if _prepare_player_hands_detailed():
				_hide_test_panel()
		"player_finger_joints":
			_open_finger_joint_controls()
		"first_person_motion":
			_prepare_first_person_motion(payload)
			_hide_test_panel()
		"reference_sword_motion":
			_prepare_reference_sword_motion(payload)
			_hide_test_panel()
		"chest":
			_prepare_chest()
			_hide_test_panel()
		"traps":
			_teleport(Vector3(8, 1, 0.3))
			player.head.rotation.x = -0.55
			player._pitch = -0.55
			_hide_test_panel()
		"ai":
			_set_enemy_ai(not enemy_ai_enabled)
			_status("적 AI: " + ("활성 · 시험장을 재개하면 공격합니다" if enemy_ai_enabled else "정지 · 피격 가능한 표적"))
		"respawn":
			_refresh_targets()
			_status("적 2종 · 함정 2종 · 전체 물품 상자를 재생성했습니다.")
		"extraction":
			_remove_test_actors(false)
			enemies_alive = 0
			portal_material.albedo_color = Color(0.12, 0.58, 0.5, 0.72)
			portal_material.emission = Color(0.08, 0.95, 0.72)
			hud.update_objective(enemies_alive, loot_count, traps_disarmed)
			_teleport(Vector3(0, 1, -12.5))
			_hide_test_panel()
		"death":
			_hide_test_panel()
			player.receive_environment_damage(999, "사망 화면 시험")
		"spell":
			_prepare_duel(false, false)
			_equip_weapon("weathered_staff")
			ExpeditionSession.learn_spell(payload)
			ExpeditionSession.select_spell(payload)
			player._refresh_magic_hud()
			if SpellCatalog.get_spell_definition(payload).get("cast_type", "") == "heal":
				player.health = 40
				hud.update_health(player.health, player.MAX_HEALTH)
			_hide_test_panel()
		"learn_books":
			ExpeditionSession.learned_spells.clear()
			ExpeditionSession.selected_spell = ""
			var missing := 0
			for item_id in ExpeditionInventory.ITEM_DEFINITIONS:
				if ExpeditionInventory.get_item_definition(item_id).get("effect", "") == "learn_spell" and inventory.count_item(item_id) == 0:
					missing += inventory.add_item(item_id)
			player._refresh_magic_hud()
			_status("습득 기록 초기화 · 마법서 지급 완료. I에서 학습하세요." if missing == 0 else "습득 기록 초기화 · 가방이 가득 찼습니다. 물품 탭에서 부족한 책을 지급하세요.")
		"needs":
			ExpeditionSession.hunger = 10
			ExpeditionSession.thirst = 10
			_give_item("pilgrim_ration")
			_give_item("boiled_rainwater")
			_refresh_survival_hud()
			_status("포만감 · 수분 10. 식량과 물은 I에서 사용할 수 있습니다.")
		"wounded":
			player.health = 25
			hud.update_health(player.health, player.MAX_HEALTH)
			player.apply_condition("bleeding")
			_give_item("healing_draught")
			_give_item("linen_bandage")
			_status("체력 25 · 출혈 적용. I에서 회복약과 붕대를 사용하세요.")
		"time":
			_advance_survival(600)
			_status("생존 시간 10분을 진행했습니다.")
		"cleanse":
			ExpeditionSession.clear_conditions()
			ExpeditionSession.restore_needs(100, 100)
			_refresh_survival_hud()
			_status("상태이상 해제 · 포만감과 수분 회복 완료.")
		"condition":
			player.apply_condition(payload)
			_status(ExpeditionSession.get_condition_display_name(payload) + " 적용 · HUD와 인벤토리에서 확인하세요.")
		"item":
			_give_item(payload)
		"hideout_cooking":
			TestRoomSandbox.prepare_hideout_view("")
			var supplies := _cooking_fixture_supplies()
			supplies.erase("camp_kit")
			var replaced := _restock_trial_supplies(supplies)
			var detail := "전체 조리법 재료와 여분 1개씩 · 야영 도구 없이 조리하고 바로 먹기"
			if replaced > 0:
				detail += " · 마지막 시험용 스택 %d개를 재료로 교체" % replaced
			_status(detail)
			TestRoomSandbox.prepare_cave_entry("")
			TestRoomSandbox.prepare_blacksmith_trial("")
			TestRoomSandbox.prepare_alchemy_trial("")
			if TestRoomSandbox.prepare_cooking_trial():
				_begin_scene_loading("res://hideout.tscn", entry.title, detail + "\n실제 은신처 화롯불 · F2로 테스트룸 복귀", "조리 기구를 준비하는 중", "은신처 요리 시험을 불러올 수 없습니다")
		"smithing":
			TestRoomSandbox.prepare_hideout_view("")
			TestRoomSandbox.prepare_cooking_trial(false)
			_prepare_smithing_trial(payload)
			if TestRoomSandbox.prepare_blacksmith_trial(payload):
				TestRoomSandbox.prepare_cave_entry("")
				TestRoomSandbox.prepare_alchemy_trial("")
				_begin_scene_loading("res://hideout.tscn", entry.title, status_label.text + "\n실제 은신처 대장간 · F2로 테스트룸 복귀", "대장간을 여는 중", "대장간 시험을 불러올 수 없습니다")
		"alchemy", "distilling":
			TestRoomSandbox.prepare_hideout_view("")
			TestRoomSandbox.prepare_cooking_trial(false)
			if TestRoomSandbox.prepare_alchemy_trial(payload):
				_prepare_alchemy_trial()
				TestRoomSandbox.prepare_cave_entry("")
				TestRoomSandbox.prepare_blacksmith_trial("")
				var instruction := "\n실제 은신처 연금대 · F2로 테스트룸 복귀"
				if entry.action == "distilling": instruction += "\n술을 병에 담고 ESC → M 지도 → 중개인 → 거래 → 판매"
				_begin_scene_loading("res://hideout.tscn", entry.title, status_label.text + instruction, "연금대를 여는 중", "연금술 시험을 불러올 수 없습니다")
		"hideout_ruin":
			TestRoomSandbox.prepare_cooking_trial(false)
			TestRoomSandbox.prepare_cave_entry("")
			TestRoomSandbox.prepare_blacksmith_trial("")
			TestRoomSandbox.prepare_alchemy_trial("")
			if TestRoomSandbox.prepare_hideout_view(payload):
				_begin_scene_loading("res://hideout.tscn", entry.title, "실제 은신처의 방별 폐허·습기·낙수 · WASD 탐색 / E 생활 기능 / F 횃불 / F2 테스트룸 복귀", "은신처의 방을 살펴보는 중", "은신처 공간 시험을 불러올 수 없습니다")
		"scene":
			TestRoomSandbox.prepare_hideout_view("")
			TestRoomSandbox.prepare_cooking_trial(false)
			TestRoomSandbox.prepare_cave_entry("")
			TestRoomSandbox.prepare_blacksmith_trial("")
			TestRoomSandbox.prepare_alchemy_trial("")
			var scene_detail := "시험용 원정 · F2로 테스트룸에 돌아올 수 있습니다"
			if payload == "res://cave_dungeon.tscn":
				scene_detail = "131m × 139m 동굴 원정 · F2 복귀 후 재입장하면 적과 상자를 다시 준비합니다"
			_begin_scene_loading(payload, entry.title, scene_detail, "시험 장면을 여는 중", "시험 장면을 불러올 수 없습니다")
		"cave_zone":
			TestRoomSandbox.prepare_hideout_view("")
			TestRoomSandbox.prepare_cooking_trial(false)
			TestRoomSandbox.prepare_blacksmith_trial("")
			TestRoomSandbox.prepare_alchemy_trial("")
			if TestRoomSandbox.prepare_cave_entry(payload):
				var detail := "실제 폐광의 지정 공동에서 시험합니다 · 전투 가능 · F2로 테스트룸 복귀"
				if payload == "west_pool":
					detail = "F 횃불로 암벽·흙·수면과 벽등 분위기 비교 · 오른쪽 물로 걸어가 파동 확인 · F2 복귀"
				elif payload == "entrance":
					detail = "F 횃불로 실제 흙·암벽과 벽등 비교 · 소품 접지와 천장 지지대 확인 · F2 복귀"
				_begin_scene_loading("res://cave_dungeon.tscn", entry.title, detail, "공동으로 진입하는 중", "폐광 공동을 불러올 수 없습니다")
	_refresh_test_status_controls()


func set_test_stat(id: String, value: float) -> bool:
	# These setters exist only on the sandbox room, never on normal gameplay.
	# Editing a debug value must not simulate damage, spend supplies or clear
	# ailments/targets; resume then exercises the ordinary gameplay systems.
	if not is_finite(value) or not is_inside_tree() or not TestRoomSandbox.active:
		return false
	if not panel_open or not get_tree().paused or game_mode != GameMode.PAUSED or is_instance_valid(loading_screen):
		return false
	if not is_instance_valid(player) or player.health <= 0.0 or player.combat_state == DungeonPlayer.CombatState.DEAD or inventory != ExpeditionSession.get_inventory():
		return false
	match id:
		"health": player.health = clampf(value, 1.0, DungeonPlayer.MAX_HEALTH)
		"stamina": player.stamina = clampf(value, 0.0, DungeonPlayer.MAX_STAMINA)
		"hunger": ExpeditionSession.hunger = clampf(value, 0.0, ExpeditionSession.MAX_NEED)
		"thirst": ExpeditionSession.thirst = clampf(value, 0.0, ExpeditionSession.MAX_NEED)
		"stress": ExpeditionSession.set_stress(value)
		_: return false
	hud.update_health(player.health, DungeonPlayer.MAX_HEALTH)
	hud.update_stamina(player.stamina, DungeonPlayer.MAX_STAMINA)
	_refresh_survival_hud()
	_update_stress_presentation()
	_refresh_test_status_controls()
	_status("시험 수치 적용 · 체력 %d · 기력 %d · 포만감 %d · 수분 %d · 스트레스 %d" % [roundi(player.health), roundi(player.stamina), roundi(ExpeditionSession.hunger), roundi(ExpeditionSession.thirst), roundi(ExpeditionSession.stress)])
	return true


func _refresh_test_status_controls() -> void:
	if not is_instance_valid(status_controls) or not is_instance_valid(player):
		return
	status_controls.set_snapshot({"health": player.health, "max_health": DungeonPlayer.MAX_HEALTH, "stamina": player.stamina, "max_stamina": DungeonPlayer.MAX_STAMINA, "hunger": ExpeditionSession.hunger, "thirst": ExpeditionSession.thirst, "stress": ExpeditionSession.stress})


func _commit_test_status_edits() -> void:
	if is_instance_valid(status_controls) and panel_open:
		status_controls.commit_pending_edits()


func _give_item(item_id: String) -> void:
	var remaining := inventory.add_item(item_id)
	_status(ExpeditionInventory.get_item_name(item_id) + (" 1개 지급" if remaining == 0 else " · 가방이 가득 찼습니다"))


func _equip_weapon(item_id: String) -> void:
	# A fixture may replace equipment even when the bag is full. Normal equipment
	# operations remain available through the unmodified inventory screen.
	inventory.equipment["weapon"] = item_id
	inventory.changed.emit()
	player._refresh_magic_hud()


func _teleport(at: Vector3) -> void:
	cancel_camp("시험 위치 이동", false)
	suspend_stress_effects()
	player.cancel_timed_interaction()
	if is_instance_valid(player.current_trap):
		player.current_trap.cancel_disarm("시험 위치 이동")
	player.finish_trap_disarm()
	player.prepare_for_inventory()
	player.velocity = Vector3.ZERO
	player.position = at
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player._pitch = 0


func _recover_player() -> void:
	_commit_test_status_edits()
	cancel_camp("시험 회복", false)
	suspend_stress_effects()
	ExpeditionSession.set_stress(0.0)
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	if is_instance_valid(player.current_trap):
		player.current_trap.cancel_disarm("시험 회복 · 함정 조사 취소")
	player.finish_trap_disarm()
	player.health = player.MAX_HEALTH
	player.stamina = player.MAX_STAMINA
	player.stamina_regen_delay = 0
	player.spell_cooldown = 0
	player.bow_cooldown = 0
	player.cancel_bow_draw()
	player.cancel_flail_action()
	player.blocking = false
	player.velocity = Vector3.ZERO
	player._set_combat_state(DungeonPlayer.CombatState.READY)
	hud.update_health(player.health, player.MAX_HEALTH)
	hud.update_stamina(player.stamina, player.MAX_STAMINA)
	_refresh_survival_hud()
	_refresh_test_status_controls()


func _set_enemy_ai(enabled: bool) -> void:
	enemy_ai_enabled = enabled
	for child in get_children():
		if child is DungeonEnemy and child.ai_state != DungeonEnemy.AIState.DEAD:
			child.set_physics_process(enabled)


func _remove_test_actors(include_props := true) -> void:
	cancel_camp("시험 대상 재설정", false)
	suspend_stress_effects()
	archery_power_target = null
	archery_power_last_damage = 0.0
	flail_near_target = null
	flail_far_target = null
	flail_last_damage = 0.0
	arm_motion_target = null
	arm_motion_chest = null
	player.cancel_flail_action()
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	if is_instance_valid(player.current_trap):
		player.current_trap.cancel_disarm("시험 대상 재설정")
	player.finish_trap_disarm()
	for child in get_children():
		if child is DungeonEnemy or child is MagicProjectile or child is ArrowProjectile or child is FlailProjectile or child.is_in_group("flail_projectile") or child.is_in_group("test_fixture_prop") or (include_props and (child is RuneTrap or child is DungeonLootChest)):
			remove_child(child)
			child.queue_free()
	enemies_alive = 0
	if include_props:
		loot_chests.clear()
		active_loot_chest = null


func _refresh_targets() -> void:
	_remove_test_actors()
	enemy_ai_enabled = false
	loot_count = 0
	traps_disarmed = 0
	traps_triggered = 0
	_spawn_encounters()
	_spawn_loot_chests()
	portal_material.albedo_color = Color(0.72, 0.18, 0.12, 0.72)
	portal_material.emission = Color(0.82, 0.045, 0.018)
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	_teleport(HOME_POSITION)


func _prepare_duel(skeleton: bool, ai_enabled: bool) -> void:
	_remove_test_actors(false)
	_recover_player()
	if skeleton:
		_spawn_enemy("굶주린 성소지기", Vector3(0, 1, -3), 68, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	else:
		_spawn_enemy("망각의 검지기", Vector3(0, 1, -3), 82, 21, 2.2, Color(0.145, 0.18, 0.19), "bleeding")
	_set_enemy_ai(ai_enabled)
	_teleport(Vector3(0, 1, 2))
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)


func _prepare_wall_equipment() -> void:
	# Use the real room wall and current equipment, so every weapon can be
	# compared without replacing the trial inventory or inventing a demo mesh.
	_remove_test_actors()
	_recover_player()
	_set_enemy_ai(false)
	_teleport(Vector3(8.0, 1.0, -15.3))
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	hud.objective_label.text = "W 벽 접근 · S 후퇴 · I 장비 교체 · F 횃불"
	_status("북쪽 벽 앞 1.4m · 현재 장비 유지. 벽에 다가가 검·방패·횃불의 표시를 확인하세요.")
	hud.show_event("W 벽 접근 / S 후퇴 · 좌우와 위아래도 확인\nI 장비 교체 · F 횃불 · F2 재시험", 5.0)


func _prepare_chest() -> void:
	# Rebuild from the authoritative catalog, but preserve the current bag and
	# equipped weapon so every weapon and the empty-handed case can be tested.
	_remove_test_actors()
	_spawn_loot_chests()
	var chest := loot_chests[0]
	_teleport(chest.position + Vector3(0.0, 1.0, 1.6))
	var lock_position := chest.to_global(Vector3(0.0, 0.77, -0.595))
	var aim := lock_position - player.camera.global_position
	player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
	player.head.rotation.x = player._pitch
	player.trap_lockout = 0.0
	hud.objective_label.text = "E 맨손 열기 · F2 닫힌 상자 재준비"
	_status("닫힌 보급 상자 · 현재 장착 무기와 가방 유지 · E로 1.2초 맨손 열기 · I에서 검·활·철퇴·지팡이 또는 무기 없음으로 바꿔 재시험")
	hud.show_event("E · 무기를 넣고 맨손으로 열기\nF2 · 같은 항목으로 닫힌 상자 재준비", 5.0)


func _prepare_player_arm_motion() -> void:
	# Compare the actual carried and chest-opening arms with the full model.
	# Keep the selected loadout, including an empty weapon slot, for repeats.
	_remove_test_actors()
	_recover_player()
	_spawn_loot_chests()
	arm_motion_chest = loot_chests[0]
	arm_motion_chest.position = Vector3(-2.2, 0.0, 2.0)
	_spawn_enemy("팔 동작 시험 표적", Vector3(0.0, 1.0, 1.0), 300, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	for child in get_children():
		if child is DungeonEnemy:
			arm_motion_target = child
			break
	_set_enemy_ai(false)
	_teleport(Vector3(0.0, 1.0, 3.0))
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	hud.objective_label.text = "LMB 정면 표적 · RMB 가드 · 왼쪽 상자 E · I 외형 비교"
	_status("현재 장비·가방 유지 · 체력·기력 회복 · 2m 정지 표적과 왼쪽 닫힌 상자 · I에서 검·방패·활·지팡이·철퇴 교체 후 F2 재시험")
	hud.show_event("LMB 공격 / RMB 가드 · F 횃불\n왼쪽 상자 E · I 전신 외형 비교 · F2 재시험", 6.0)


func _prepare_player_hands_greybox() -> bool:
	return _prepare_player_hands_profile("greybox")


func _prepare_player_hands_detailed() -> bool:
	return _prepare_player_hands_profile("detailed")


func _prepare_player_hands_profile(profile: String, restore_after := false) -> bool:
	var previous_profile := player.hands_visual_profile
	var label := "양손 디테일 모델" if profile == "detailed" else "양손 그레이박스"
	if not player.set_hands_visual_profile(profile):
		_status(label + "을 불러오지 못했습니다. 현재 플레이어 외형을 유지합니다.")
		return false
	_prepare_player_arm_motion()
	var reserved_slots := 0
	for slot_name in ["weapon", "offhand"]:
		if not str(inventory.equipment.get(slot_name, "")).is_empty():
			reserved_slots += 1
	var replaced := _restock_trial_supplies({}, reserved_slots)
	# Use normal inventory transactions so authored weapon instance metadata
	# survives the review. The sandbox owns any capacity preparation above.
	for slot_name in ["offhand", "weapon"]:
		if not str(inventory.equipment.get(slot_name, "")).is_empty():
			inventory.unequip(slot_name)
	player.cancel_sword_attack()
	player.set_sword_attack_mode("cycle")
	player.set_torch_enabled(false)
	player._refresh_magic_hud()
	# The menu still pauses simulation here. Update presentation directly so
	# both free hands are ready before resuming; _update_viewmodel respects
	# pause and would otherwise retain the just-stowed torch hand for a frame.
	player._refresh_carried_visibility()
	player._update_character_arms()
	if restore_after:
		player.set_hands_visual_profile(previous_profile)
	var guide := label + " · WASD 손·소매 비교 · 왼쪽 상자 E로 실제 손가락·뚜껑 접촉 · I에서 활 장착 / LMB 당기고 놓기"
	if replaced > 0:
		guide += " · 장비 보관을 위해 마지막 시험용 스택 %d개 교체" % replaced
	hud.objective_label.text = label + " · 왼쪽 상자 E · I 활 장착 · F2 재시험"
	_status(guide + " · 다른 시험 선택·초기화·종료 시 원래 외형으로 복구")
	hud.show_event(label + " · 왼쪽 상자 E\nI 활 장착 → LMB 당기고 놓기 · F2 재시험", 7.0)
	return true


func _open_finger_joint_controls() -> bool:
	if not _prepare_player_hands_profile("detailed", true):
		return false
	if not player.begin_finger_joint_review():
		_status("15마디 교정 형상이 포함된 상세 손 모델을 불러오지 못했습니다. 현재 외형을 유지합니다.")
		return false
	panel_open = false
	test_panel.hide()
	room_hint.hide()
	hud.hide_overlay()
	game_mode = GameMode.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	finger_joint_controls = FINGER_JOINT_CONTROLS.new()
	finger_joint_controls.name = "FingerJointControls"
	finger_joint_controls.theme = test_panel.theme
	finger_joint_controls.call("setup", player)
	finger_joint_controls.connect("closed", _close_finger_joint_controls)
	test_panel.get_parent().add_child(finger_joint_controls)
	player.viewmodel_renderer.sync_view()
	return true


func _close_finger_joint_controls(return_to_menu := true) -> void:
	var was_open := is_instance_valid(finger_joint_controls)
	if was_open:
		finger_joint_controls.set_process(false)
		finger_joint_controls.hide()
		finger_joint_controls.queue_free()
		finger_joint_controls = null
	if is_instance_valid(player):
		player.end_finger_joint_review()
	if return_to_menu and was_open:
		_show_test_panel()


func _restock_camping_supplies() -> int:
	return _restock_trial_supplies({"camp_kit": 2, "pilgrim_ration": 2, "boiled_rainwater": 2, "linen_bandage": 2})


func _prepare_reference_sword_motion(family: String) -> void:
	# Keep the existing floor and production player collision. Clearing previous
	# encounters opens a straight lane without switching combat to safe-zone mode.
	_remove_test_actors()
	_recover_player()
	inventory.equipment["offhand"] = "round_shield"
	_equip_weapon("rusted_sword")
	player.cancel_sword_attack()
	player.set_sword_attack_mode("cycle")
	_set_enemy_ai(false)
	_teleport(REFERENCE_MOTION_START)
	player.reset_reference_movement_motion(true)
	player.set_torch_enabled(true)
	if family == "sequence":
		_spawn_enemy("이동 후 베기 시험 표적", REFERENCE_MOTION_TARGET, 300, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
		for child in get_children():
			if child is DungeonEnemy:
				arm_motion_target = child
				break
		_set_enemy_ai(false)
	var guide := str({
		"run": "W 걷기 / W+Shift 달리기 / 놓아 멈추기 · 검과 방패의 이동 연결 확인",
		"jump": "Space 도약·공중·착지 · W+Shift+Space 이동 점프 · 실제 바닥과 기력 소모",
		"sequence": "9m 정면 표적 · W+Shift 접근 → Space 점프 → 가까이서 LMB 베기 · RMB 가드",
	}.get(family, "WASD / Shift / Space / LMB · 실제 검과 방패"))
	var sign := Label3D.new()
	sign.name = "ReferenceSwordMotionInstructions"
	sign.text = guide + "\nF2 · 체력·기력 회복 / 재선택으로 처음부터"
	sign.font = room_font
	sign.font_size = 40
	sign.pixel_size = 0.007
	sign.position = Vector3(0.0, 3.3, -2.0)
	sign.modulate = Color(0.79, 0.86, 0.73)
	sign.add_to_group("test_fixture_prop")
	add_child(sign)
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	hud.objective_label.text = guide
	_status("영상 참고 검 모션 · " + guide + " · F2 재선택 시 위치·표적·체력·기력을 다시 준비합니다")
	hud.show_event(guide + "\nF2 회복·재시험", 7.0)


func _prepare_first_person_motion(family: String) -> void:
	# These are playable production fixtures, not prerecorded pose playback.
	var replaced_stacks := 0
	var sword_mode := "cycle"
	match family:
		"bow": _prepare_archery(false, true)
		"flail": _prepare_flail()
		"chest": _prepare_chest()
		"torch":
			_prepare_player_arm_motion()
			replaced_stacks = _prepare_handheld_torch()
		"shield", "shield_raise", "shield_impact":
			_prepare_duel(false, family != "shield_raise")
			inventory.equipment["offhand"] = "round_shield"
			_equip_weapon("rusted_sword")
		"shield_cut_right", "shield_cut_left", "shield_cut_overhead":
			_prepare_player_arm_motion()
			inventory.equipment["offhand"] = "round_shield"
			_equip_weapon("rusted_sword")
			sword_mode = str({"shield_cut_right": "right_diagonal", "shield_cut_left": "left_reverse", "shield_cut_overhead": "overhead"}[family])
		_:
			_prepare_player_arm_motion()
			if family == "staff":
				_equip_weapon("weathered_staff")
				ExpeditionSession.learn_spell("fire_bolt")
				ExpeditionSession.select_spell("fire_bolt")
				player._refresh_magic_hud()
			elif family == "sword":
				_equip_weapon("rusted_sword")
	# Every fixture starts a new production attack selection. Fixed-cut trials
	# must not carry their mode into the ordinary three-cut cycle or other arms.
	player.cancel_sword_attack()
	player.set_sword_attack_mode(sword_mode)
	player.set_torch_enabled(true)
	var guide := str({
		"sword": "긴 손잡이 검 · 비스듬한 오른손 파지 · LMB 짧게/길게 눌러 준비·타격·회수 · 정면 실제 표적",
		"shield": "긴 손잡이 검과 방패 · LMB 우측 대각→좌측 역베기→내려베기 순환 · RMB 올리기·가드·충격 · 놓고 LMB 반격",
		"shield_cut_right": "우측 대각 베기 고정 · 2m 정지 표적 · LMB 준비·타격·회수 · 길게 눌러 강공격",
		"shield_cut_left": "좌측 역베기 고정 · 2m 정지 표적 · LMB 준비·타격·회수 · 길게 눌러 강공격",
		"shield_cut_overhead": "상단 내려베기 고정 · 2m 정지 표적 · LMB 준비·타격·회수 · 길게 눌러 강공격",
		"shield_raise": "방패 올리기 · 정지 상대 · RMB를 눌러 올리고 놓아 내리기 · 반복 조작으로 연결 동작 확인",
		"shield_impact": "막힘 충격 · 실제 공격 상대 · RMB를 미리 누른 채 유지해 충격·기력 소모 확인 · 놓고 LMB 반격",
		"bow": "활 · LMB 반쯤/끝까지 당겨 놓기 · RMB 취소 · 실제 화살 30개",
		"flail": "철퇴 · LMB 근접 · RMB 회전 후 놓기 · 실제 투척과 자동 회수",
		"staff": "지팡이 · 화염탄 선택 완료 · LMB 실제 시전 · 1~5 주문 변경",
		"torch": "왼손 횃불 · 검·방패는 가방에 보관 · WASD 걷기 / Shift 달리기 / F 켜기·끄기 · I 장비 변경",
		"chest": "맨손 · E로 실제 상자 조사와 열기 · 시선 이동/E 재입력 취소",
	}.get(family, "1인칭 모션"))
	if replaced_stacks > 0:
		guide += " · 장비 보관을 위해 마지막 시험용 스택 %d개 교체" % replaced_stacks
	_status(guide + " · F2 복귀 후 재선택하면 실제 대상·상태를 다시 준비합니다")
	hud.show_event(guide + "\nF2 재시험", 6.0)


func _prepare_handheld_torch() -> int:
	var reserved_slots := 0
	for slot_name in ["weapon", "offhand"]:
		if not str(inventory.equipment.get(slot_name, "")).is_empty():
			reserved_slots += 1
	var needs_torch := str(inventory.equipment.get("utility", "")) != "field_torch"
	var supplies: Dictionary = {"field_torch": 1} if needs_torch else {}
	var replaced := _restock_trial_supplies(supplies, reserved_slots)
	# Normal transactions preserve each carried weapon's instance metadata. This
	# unarmed torch pose works in the dungeon without a lingering safe-zone flag.
	for slot_name in ["offhand", "weapon"]:
		if not str(inventory.equipment.get(slot_name, "")).is_empty():
			inventory.unequip(slot_name)
	if needs_torch:
		for index in inventory.slots.size():
			if str(inventory.slots[index].get("id", "")) == "field_torch":
				inventory.equip_from_slot(index)
				break
	player._refresh_magic_hud()
	return replaced


func _prepare_smithing_trial(station: String) -> void:
	_recover_player()
	# Reserve the craft result or fresh comparison sword before restocking.
	# Existing crafted instances survive repeats unless the bag needs the same
	# explicitly disclosed bounded replacement as all other supply fixtures.
	var replaced := _restock_trial_supplies(SMITHING_SYSTEM.trial_supplies(), 1)
	if station != "forge":
		var fresh_index := inventory.slots.size()
		if inventory.add_item("rusted_sword", 1, false) == 0:
			inventory.equip_from_slot(fresh_index)
			player._refresh_magic_hud()
	var detail := "대장간 재료 보급 · 제작 완료품 자리 확보 · 강화 시험은 새 검으로 시작합니다"
	if replaced > 0:
		detail += " · 마지막 시험용 스택 %d개를 보급품으로 교체했습니다" % replaced
	_status(detail)


func _prepare_alchemy_trial() -> void:
	_recover_player()
	# Reserve result stacks before supplying the actual source-catalog reagents.
	# Repeated trials replenish only the sandbox and never start a batch for the
	# player: every pour, grind, heating stage and finish is a real manual action.
	var replaced := _restock_trial_supplies(ALCHEMY_SYSTEM.trial_supplies(), 3)
	var detail := "연금술 재료와 빈 병 보급 · 완성 물약 자리 확보 · 처방책을 보며 직접 제조하세요"
	if replaced > 0:
		detail += " · 마지막 시험용 스택 %d개를 보급품으로 교체했습니다" % replaced
	_status(detail)


func _restock_trial_supplies(supplies: Dictionary, reserved_slots := 0) -> int:
	var required_slots := 0
	for item_id in supplies:
		var existing := inventory.count_item(item_id)
		if existing > 0:
			inventory.remove_item(item_id, existing, false)
		var definition := ExpeditionInventory.get_item_definition(item_id)
		required_slots += ceili(float(supplies[item_id]) / maxi(1, int(definition.get("stack_max", 1))))
	var replaced_stacks := 0
	# All replacement is confined to the isolated trial bag. Reserve enough
	# whole stacks before adding so even a non-stacking supply is repeatable.
	while inventory.slots.size() + required_slots + reserved_slots > ExpeditionInventory.MAX_SLOTS:
		inventory.slots.remove_at(inventory.slots.size() - 1)
		replaced_stacks += 1
	for item_id in supplies:
		inventory.add_item(item_id, supplies[item_id], false)
	inventory.changed.emit()
	return replaced_stacks


func _prepare_camping() -> void:
	_remove_test_actors()
	_recover_player()
	var replaced_stacks := _restock_camping_supplies()
	ExpeditionSession.clear_conditions()
	ExpeditionSession.hunger = 25.0
	ExpeditionSession.thirst = 25.0
	ExpeditionSession.apply_condition("bleeding", 180.0)
	ExpeditionSession.apply_condition("fracture", 300.0)
	ExpeditionSession.apply_condition("curse", 240.0)
	_teleport(Vector3(0, 1, 12))
	# Teleporting clears the old trap interaction and normally adds a short
	# interaction lockout. This fresh safe fixture has no trap to debounce.
	player.trap_lockout = 0.0
	player.health = 35.0
	player.stamina = 20.0
	player.stamina_regen_delay = 0.75
	hud.update_health(player.health, player.MAX_HEALTH)
	hud.update_stamina(player.stamina, player.MAX_STAMINA)
	_refresh_survival_hud()
	var sign := Label3D.new()
	sign.name = "CampingInstructions"
	sign.text = "안전 지대 · C 야영\n휴식 / 식사 / 붕대 처치\n야영 도구·식량·물·붕대 각 2개\nEsc 중단 · F2 재보급"
	sign.font = room_font
	sign.font_size = 30
	sign.pixel_size = 0.003
	sign.outline_size = 8
	sign.modulate = Color(0.91, 0.82, 0.66)
	sign.position = Vector3(0, 2.6, 9.5)
	sign.add_to_group("test_fixture_prop")
	add_child(sign)
	hud.objective_label.text = "C 야영 · 휴식 / 식사 / 응급처치"
	var message := "야영 시험 · C로 실제 야영 열기 · 체력 35 / 기력 20 / 포만감·수분 25 · 출혈·골절·저주 · 도구와 보급 각 2개 · F2 재시험"
	if replaced_stacks > 0:
		message += " · 가방의 마지막 시험용 스택 %d개를 보급품으로 교체했습니다" % replaced_stacks
	_status(message)
	hud.show_event("안전 지대 · C로 야영 시작\n휴식·식사·붕대 처치 · F2 재보급", 6.0)


func _cooking_fixture_supplies() -> Dictionary:
	var supplies := {"camp_kit": 2}
	for recipe_id in CampCookingCatalog.ordered_recipe_ids():
		var recipe := CampCookingCatalog.get_recipe(recipe_id)
		for item_id in recipe.resources:
			# One of every recipe plus one spare of every ingredient. New catalog
			# recipes automatically join the same real cooking comparison fixture.
			supplies[item_id] = int(supplies.get(item_id, 1)) + int(recipe.resources[item_id])
	return supplies


func _prepare_cooking() -> void:
	_remove_test_actors()
	_recover_player()
	var replaced_stacks := _restock_trial_supplies(_cooking_fixture_supplies())
	ExpeditionSession.clear_conditions()
	ExpeditionSession.hunger = 15.0
	ExpeditionSession.thirst = 20.0
	_teleport(HOME_POSITION)
	player.trap_lockout = 0.0
	player.health = 35.0
	player.stamina = 20.0
	player.stamina_regen_delay = 0.75
	player.set_torch_enabled(true)
	ExpeditionSession.set_stress(55.0)
	hud.update_health(player.health, player.MAX_HEALTH)
	hud.update_stamina(player.stamina, player.MAX_STAMINA)
	_refresh_survival_hud()
	var sign := Label3D.new()
	sign.name = "CookingInstructions"
	sign.text = "C 야영 → 요리\n재료는 시작할 때 소비\n완성하면 바로 먹고 회복\nF2 재보급 · 중단 시 반환 없음"
	sign.font = room_font
	sign.font_size = 30
	sign.pixel_size = 0.003
	sign.outline_size = 8
	sign.modulate = Color(0.94, 0.79, 0.57)
	sign.position = Vector3(0, 2.6, 9.5)
	sign.add_to_group("test_fixture_prop")
	add_child(sign)
	hud.objective_label.text = "C 야영 → 요리 · 완성 즉시 식사"
	var message := "요리 시험 · 야영 도구 2개 / 전체 조리법 재료와 여분 1개씩 · 체력35 기력20 포만감15 수분20 스트레스55 · 온기 부족 시 야영을 새로 설치"
	if replaced_stacks > 0:
		message += " · 마지막 시험용 스택 %d개를 재료로 교체" % replaced_stacks
	_status(message)
	hud.show_event("C 야영 → 요리 · 완성 즉시 식사\n재료는 시작 때 소비 · F2 재보급", 6.0)


func _prepare_stress(value: float) -> void:
	_remove_test_actors()
	_recover_player()
	var replaced_stacks := _restock_camping_supplies()
	ExpeditionSession.clear_conditions()
	ExpeditionSession.hunger = 20.0 if value < 40.0 else 100.0
	ExpeditionSession.thirst = 20.0 if value < 40.0 else 100.0
	if value < 40.0:
		ExpeditionSession.apply_condition("bleeding", 180.0)
		player.health = 35.0
		player.stamina = 30.0
		player.stamina_regen_delay = 0.75
	_teleport(HOME_POSITION)
	player.trap_lockout = 0.0
	player.set_torch_enabled(true)
	ExpeditionSession.set_stress(value)
	hud.update_health(player.health, player.MAX_HEALTH)
	hud.update_stamina(player.stamina, player.MAX_STAMINA)
	_refresh_survival_hud()
	var sign := Label3D.new()
	sign.name = "StressInstructions"
	sign.text = "스트레스 %d / 100\n%s\nC 야영 · F2 회복 / 재시험" % [int(value), "허기·출혈로 누적 · F 소등" if value < 40.0 else "잠시 기다려 소리·주변 확인"]
	sign.font = room_font
	sign.font_size = 30
	sign.pixel_size = 0.003
	sign.outline_size = 8
	sign.modulate = Color(0.86, 0.75, 0.88)
	sign.position = Vector3(0, 2.6, 9.5)
	sign.add_to_group("test_fixture_prop")
	add_child(sign)
	hud.objective_label.text = "스트레스 %d · C 야영 / F2 회복" % int(value)
	var message := "스트레스 %d · %s · 야영 도구·식량·물·붕대 각 2개" % [int(value), "허기·갈증·출혈로 누적 / F 소등 비교" if value < 40.0 else "건강·보급 회복 / 잠시 기다려 실제 환청·환영 확인"]
	if replaced_stacks > 0:
		message += " · 마지막 시험용 스택 %d개를 보급으로 교체" % replaced_stacks
	_status(message)
	hud.show_event("스트레스 %d · %s\nC 야영 · F2 회복 / 재시험" % [int(value), "F 소등으로 누적 비교" if value < 40.0 else "잠시 기다려 주변 확인"], 5.0)


func _prepare_archery(accuracy_test := false, power_test := false) -> void:
	_remove_test_actors(false)
	_recover_player()
	_equip_weapon("hunting_bow")
	# Fixture loadouts may replace one SANDBOX stack when full, just as weapon
	# fixtures replace equipment. The saved original inventory is never touched.
	var arrows := inventory.count_item("wooden_arrow")
	if arrows > 0:
		inventory.remove_item("wooden_arrow", arrows, false)
	var replaced_stack := inventory.slots.size() >= ExpeditionInventory.MAX_SLOTS
	if replaced_stack:
		inventory.slots.remove_at(inventory.slots.size() - 1)
	inventory.add_item("wooden_arrow", 30)
	if accuracy_test:
		_spawn_archery_accuracy_target()
	else:
		_spawn_enemy("굶주린 성소지기", Vector3(0, 1, -3), 150, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
		if power_test:
			for child in get_children():
				if child is DungeonEnemy:
					archery_power_target = child
					break
			_spawn_archery_power_instructions()
	_set_enemy_ai(false)
	_teleport(Vector3(0, 1, 5))
	# A raised bullseye leaves room below the aim line to see the weak shot's
	# spread and normal ballistic drop instead of immediately hitting the floor.
	player._pitch = atan2(2.5 - player.camera.global_position.y, 8.0) if accuracy_test else -0.055
	player.head.rotation.x = player._pitch
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	var message := "궁술 시험 · 사냥활 / 화살 30개 · 8m 정지 표적 · 0.1초 이하: 발밑 낙하 / 길게 당겨 사격 · RMB 취소"
	if accuracy_test:
		message = "활 조준선/탄도 시험 · 8m 과녁 / 화살 30개 · 0.1초 이하: 발밑 낙하 / 0.5초·1초: 과녁 사격 · 당길수록 축소 · 기력 고갈 시 현재 힘으로 1발 / RMB 취소 / F2 재보급"
		hud.objective_label.text = "짧게: 낙하 · 길게: 사격 / 조준선 축소"
	elif power_test:
		message = "활 피해 · 기력 유지 시험 · 0.1초 이하: 발밑 낙하 / 몸통 피해 32(0.5초) → 46(1초) · 기력 초당 22 · 고갈 시 현재 당긴 힘으로 화살 1개 자동 발사 · F2 회복/재보급"
		hud.objective_label.text = "표적 150 / 150 · 기력 고갈: 현재 힘으로 1발"
	if replaced_stack:
		message += " · 가방의 마지막 시험용 스택을 화살로 교체했습니다."
	_status(message)
	var event_text := "0.1초 이하: 발밑 낙하 / 길게: 멀리\n조준선: 넓게 → 좁게 · RMB 취소 / F2 재보급" if accuracy_test else "0.1초 이하: 발밑 낙하 · 길게 당겨 사격 / RMB 취소"
	if power_test:
		event_text = "0.1초 이하 낙하 · 0.5초 피해 32 / 1초 46\n기력 초당 22 · 고갈: 현재 힘으로 1발"
	hud.show_event(event_text + ("\n가방 마지막 시험용 스택을 화살로 교체" if replaced_stack else ""), 7.0 if accuracy_test or power_test else 5.0)


func _prepare_flail() -> void:
	_remove_test_actors(false)
	_recover_player()
	_equip_weapon("chain_flail")
	_spawn_enemy("굶주린 근접 표적", Vector3(-3, 1, 3), 200, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	_spawn_enemy("굶주린 투척 표적", Vector3(3, 1, -3), 200, 18, 2.65, Color(0.21, 0.125, 0.105), "fracture")
	for child in get_children():
		if child is DungeonEnemy:
			if child.position.x < 0:
				flail_near_target = child
			else:
				flail_far_target = child
	_set_enemy_ai(false)
	_teleport(Vector3(-3, 1, 5))
	_build_flail_station_markers()
	hud.update_objective(enemies_alive, loot_count, traps_disarmed)
	hud.objective_label.text = "좌측: 2m 타격 / 우측 파란 발판: 8m 투척"
	_status("사슬철퇴 시험 · 좌측 2m 표적은 LMB 타격 · 오른쪽 파란 발판으로 이동해 RMB 회전 후 놓아 8m 투척 · 0.35초 최소 회전 / 1.2초 최대 · F2 회복/재생성")
	hud.show_event("LMB 근접 · RMB 회전 후 놓아 투척\n오른쪽 파란 발판: 8m 시험 · F2 회복", 6.0)


func _build_flail_station_markers() -> void:
	for lane in [-3.0, 3.0]:
		var marker := MeshInstance3D.new()
		marker.name = "FlailNearLane" if lane < 0 else "FlailFarLane"
		var pad := BoxMesh.new()
		pad.size = Vector3(1.8, 0.015, 1.4)
		marker.mesh = pad
		marker.material_override = _material(Color(0.4, 0.5, 0.3) if lane < 0 else Color(0.23, 0.44, 0.57), 0.95, 0.0)
		marker.position = Vector3(lane, 0.015, 5)
		preload("res://scripts/dark_fantasy_training_visual.gd").decorate_lane(marker, lane < 0)
		marker.add_to_group("test_fixture_prop")
		add_child(marker)
		var sign := Label3D.new()
		sign.name = "FlailNearInstructions" if lane < 0 else "FlailFarInstructions"
		sign.font = room_font
		sign.font_size = 28 if lane < 0 else 35
		sign.pixel_size = 0.0025 if lane < 0 else 0.004
		sign.outline_size = 8
		sign.modulate = Color(0.83, 0.88, 0.75)
		sign.text = "2m · 근접 타격\nLMB · 피해 32 / 기력 18" if lane < 0 else "8m · 회전 투척\nRMB 회전 후 놓기 · 기력 24\n1.2초 최대 피해 60 · 자동 회수"
		# The melee station is only two metres away. Keep its smaller label
		# beside the target rather than above the player's vertical view.
		sign.position = Vector3(-1.6, 2.4, 2.5) if lane < 0 else Vector3(lane, 3.1, -3)
		sign.add_to_group("test_fixture_prop")
		add_child(sign)


func _on_flail_fixture_hit(damage: float, _headshot: bool) -> void:
	if not is_instance_valid(flail_near_target) or not is_instance_valid(flail_far_target) or not player._is_flail_equipped():
		return
	flail_last_damage = damage
	var feedback := "철퇴 명중 %.0f · 근접 %.0f / 투척 %.0f" % [damage, flail_near_target.health, flail_far_target.health]
	hud.objective_label.text = feedback
	hud.show_event(feedback, 2.5)
	_status(feedback + " · F2 회복/재생성")


func _spawn_archery_power_instructions() -> void:
	var sign := Label3D.new()
	sign.name = "ArcheryPowerInstructions"
	sign.add_to_group("test_fixture_prop")
	sign.text = "8m · 활 피해 / 기력 유지\n기본 피해 18 → 32(0.5초) → 46(1초)\n0.1초 이하: 발밑 낙하 · 기력 초당 22\n고갈: 현재 힘으로 1발 · F2 회복 / 재보급"
	sign.font = room_font
	sign.font_size = 38
	sign.pixel_size = 0.004
	sign.modulate = Color(0.83, 0.88, 0.75)
	sign.outline_size = 8
	sign.position = Vector3(0, 3.4, -3)
	add_child(sign)


func _on_archery_power_hit(target: Node, damage: float, headshot: bool) -> void:
	if not is_instance_valid(archery_power_target) or target != archery_power_target:
		return
	archery_power_last_damage = damage
	var feedback := "실제 명중 %.0f%s · 표적 %.0f / %.0f · F2 회복 / 재보급" % [damage, " (머리 1.5배)" if headshot else " (몸통)", archery_power_target.health, archery_power_target.max_health]
	hud.objective_label.text = feedback
	hud.show_event(feedback, 3.0)
	_status(feedback)


func _spawn_archery_accuracy_target() -> void:
	var board := _add_static_box("ArcheryAccuracyTarget", Vector3(0, 2.5, -3), Vector3(5.4, 5, 0.25), _material(Color(0.22, 0.135, 0.07), 0.94, 0.0), false)
	preload("res://scripts/dark_fantasy_training_visual.gd").add_target_timbers(board)
	board.add_to_group("test_fixture_prop")
	# Real world-layer geometry catches production arrows. Nested shallow discs
	# are visual markings only and cannot change a shot's collision result.
	var colors := [Color(0.76, 0.72, 0.59), Color(0.23, 0.32, 0.34), Color(0.70, 0.67, 0.55), Color(0.39, 0.11, 0.07), Color(0.92, 0.66, 0.23)]
	var radii := [2.0, 1.5, 1.0, 0.5, 0.13]
	for index in range(radii.size()):
		var marking := MeshInstance3D.new()
		marking.name = "TargetRing%d" % index
		var disc := CylinderMesh.new()
		disc.top_radius = radii[index]
		disc.bottom_radius = radii[index]
		disc.height = 0.006
		disc.radial_segments = 64
		marking.mesh = disc
		marking.material_override = preload("res://scripts/dark_fantasy_training_visual.gd").target_paint(colors[index])
		marking.rotation.x = PI / 2.0
		marking.position.z = 0.13 + index * 0.008
		board.add_child(marking)
	var sign := Label3D.new()
	sign.name = "AccuracyInstructions"
	sign.text = "8m · 활 조준선 / 탄도 / 정확도\n0.1초 이하: 발밑 낙하 · 길게 당겨 사격\n조준선: 크게 → 당길수록 축소 → 완전 당김: 작게\n고갈 시 1발 · RMB 취소 · F2 재보급"
	sign.font = room_font
	sign.font_size = 40
	sign.pixel_size = 0.005
	sign.modulate = Color(0.83, 0.88, 0.75)
	sign.outline_size = 8
	sign.position = Vector3(0, 3.05, 0.18)
	board.add_child(sign)


func _on_player_died() -> void:
	cancel_camp("", false)
	suspend_stress_effects()
	player.cancel_timed_interaction()
	player.set_chest_container_open(false)
	game_mode = GameMode.DEAD
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_overlay("시험 캐릭터 사망", "원래 원정에는 영향이 없습니다.\n\nR · 테스트룸 초기화\nF2 · 회복 후 시험 메뉴")


func _on_extraction_body_entered(body: Node3D) -> void:
	super._on_extraction_body_entered(body)
	if game_mode == GameMode.WON:
		hud.overlay_detail.text = "생환 흐름 시험 완료 · 원래 원정은 보존됩니다.\n\nE · 시험용 중개인으로 이동\nR · 테스트룸 초기화\nF2 · 시험 메뉴"


func reset_room() -> void:
	if is_instance_valid(loading_screen):
		return
	_close_finger_joint_controls(false)
	_commit_test_status_edits()
	suspend_stress_effects()
	player.set_hands_visual_profile("original")
	TestRoomSandbox.reset_loadout()
	inventory = ExpeditionSession.get_inventory()
	player.bind_inventory(inventory)
	if is_instance_valid(camp):
		camp.setup(self, player, inventory)
	_refresh_targets()
	_recover_player()
	_refresh_survival_hud()
	player._refresh_magic_hud()
	player.set_torch_enabled(true)
	elapsed = 0
	_show_test_panel()
	_status("시험 장비 · 체력 · 보급 · 대상 초기화 완료. 원래 원정은 그대로 보존됩니다.")


func leave_room() -> void:
	player.set_hands_visual_profile("original")
	_begin_scene_loading("res://main_menu.tscn", "테스트룸 나가기", "원래 원정 상태를 복원합니다", "메인 메뉴로 돌아가는 중", "메인 메뉴로 돌아갈 수 없습니다")


func _begin_scene_loading(scene_path: String, title_text: String, detail_text: String, status_text: String, failure_text: String) -> void:
	if is_instance_valid(loading_screen):
		return
	_close_finger_joint_controls(false)
	if is_instance_valid(player):
		player.set_hands_visual_profile("original")
	super._begin_scene_loading(scene_path, title_text, detail_text, status_text, failure_text)


func _status(message: String) -> void:
	status_label.text = message


func _open_art_gallery() -> void:
	_close_art_gallery(false)
	player.prepare_for_inventory()
	panel_open = false
	test_panel.hide()
	room_hint.hide()
	game_mode = GameMode.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	art_gallery = ART_GALLERY.new()
	art_gallery.name = "DarkFantasyGallery"
	art_gallery.theme = test_panel.theme
	test_panel.get_parent().add_child(art_gallery)
	art_gallery.closed.connect(_close_art_gallery)


func _close_art_gallery(return_to_menu := true) -> void:
	if not is_instance_valid(art_gallery):
		return
	art_gallery.hide()
	art_gallery.queue_free()
	art_gallery = null
	if return_to_menu:
		_show_test_panel()
