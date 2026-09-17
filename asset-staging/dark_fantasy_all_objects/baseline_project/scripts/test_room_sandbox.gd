extends Node

# This small session owner survives scene changes so the real hideout and shop
# can be tested without ever replacing the player's original expedition.
const ROOM_PATH := "res://test_room.tscn"
const MENU_PATH := "res://main_menu.tscn"
const LOADING_SCRIPT := preload("res://scripts/loading_screen.gd")
const UI_FONT := preload("res://assets/fonts/NotoSansKR-Variable.ttf")

var active := false
var saved_session: Dictionary = {}
var return_banner: Button
var loading_screen: SanctuaryLoadingScreen
var pending_cave_entry_room := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	return_banner = Button.new()
	return_banner.text = "테스트 세션 · F2 테스트룸 복귀"
	var banner_font := FontVariation.new()
	banner_font.base_font = UI_FONT
	banner_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	return_banner.add_theme_font_override("font", banner_font)
	return_banner.add_theme_font_size_override("font_size", 14)
	return_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	return_banner.position = Vector2(-160, 8)
	return_banner.size = Vector2(320, 36)
	return_banner.pressed.connect(return_to_room)
	return_banner.hide()
	layer.add_child(return_banner)


func begin() -> void:
	if active:
		return
	saved_session = ExpeditionSession.capture_snapshot()
	active = true
	reset_loadout()


func reset_loadout() -> void:
	pending_cave_entry_room = ""
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 9999
	var bag := ExpeditionSession.get_inventory()
	bag.add_item("weathered_staff")
	for spell_id in SpellCatalog.ordered_spell_ids():
		ExpeditionSession.learn_spell(spell_id)


func finish() -> void:
	pending_cave_entry_room = ""
	if not active:
		return
	_cancel_scene_activities()
	ExpeditionSession.restore_snapshot(saved_session)
	saved_session.clear()
	active = false
	return_banner.hide()


func prepare_cave_entry(room_id: String) -> bool:
	pending_cave_entry_room = ""
	if not active:
		return false
	if room_id.is_empty():
		return true
	for room: Dictionary in preload("res://scripts/cave_layout.gd").rooms():
		if room.id == room_id:
			pending_cave_entry_room = room_id
			return true
	return false


func consume_cave_entry_room() -> String:
	var requested := pending_cave_entry_room if active else ""
	pending_cave_entry_room = ""
	return requested


func _process(_delta: float) -> void:
	if not active:
		return
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	if scene.scene_file_path in [MENU_PATH, "res://boot.tscn"]:
		finish()
		return
	return_banner.visible = scene.scene_file_path != ROOM_PATH and not _transition_in_progress()


func _input(event: InputEvent) -> void:
	if not active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F2 or event.physical_keycode == KEY_F2:
		var scene := get_tree().current_scene
		if is_instance_valid(scene) and scene.scene_file_path != ROOM_PATH:
			get_viewport().set_input_as_handled()
			return_to_room()


func return_to_room() -> void:
	if not active or _transition_in_progress():
		return
	pending_cave_entry_room = ""
	_cancel_scene_activities()
	var was_paused := get_tree().paused
	var previous_mouse_mode := Input.mouse_mode
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	loading_screen = LOADING_SCRIPT.new() as SanctuaryLoadingScreen
	loading_screen.configure(ROOM_PATH, "테스트룸으로 복귀", "시험용 원정 상태를 유지합니다", "시험장을 여는 중", 0.3)
	loading_screen.load_failed.connect(func(_code: int) -> void:
		loading_screen.dismiss()
		loading_screen = null
		get_tree().paused = was_paused
		Input.mouse_mode = previous_mouse_mode
	)
	loading_screen.attach_as_overlay(get_tree())


func _cancel_scene_activities() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	if scene.has_method("suspend_stress_effects"):
		scene.call("suspend_stress_effects")
	if scene.has_method("cancel_camp"):
		scene.call("cancel_camp", "시험 장면 종료", false)
	var actor := scene.get_node_or_null("Player") as DungeonPlayer
	if is_instance_valid(actor):
		actor.cancel_timed_interaction()
		actor.set_chest_container_open(false)
		actor.cancel_flail_action()


func _transition_in_progress() -> bool:
	if is_instance_valid(loading_screen):
		return true
	var scene := get_tree().current_scene
	if is_instance_valid(scene):
		# The real dungeon has no `transitioning` property. Do not attempt to
		# construct a bool from that null value during a linked-room return.
		var scene_transition: Variant = scene.get("transitioning")
		if scene_transition is bool and scene_transition:
			return true
	for child in get_tree().root.get_children():
		if bool(child.get_meta(&"sanctuary_loading_host", false)):
			return true
	return false
