extends "res://scripts/game.gd"

const CAVE_SCENE_PATH := "res://cave_dungeon.tscn"
const CAVE_LAYOUT := preload("res://scripts/cave_layout.gd")
const CAVE_GEOMETRY := preload("res://scripts/cave_geometry.gd")
const DUNGEON_TITLE := "검은 물길 동굴"

var cave_geometry: Node3D
var _current_chamber_title := ""
var _chamber_data: Array[Dictionary] = CAVE_LAYOUT.rooms()


func _ready() -> void:
	super._ready()
	_update_chamber_hud()
	hud.show_event("검은 물길 동굴 · 131 m × 139 m\n버려진 18개 공동 · 감시자 6명을 처치하고 북동쪽 성소로 귀환", 4.2)


func _process(delta: float) -> void:
	super._process(delta)
	_update_chamber_hud()


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = make_environment()
	add_child(world_environment)


static func make_environment() -> Environment:
	return preload("res://scripts/cave_art_direction.gd").make_environment()


static func configure_player_lighting(target: Node) -> void:
	preload("res://scripts/cave_art_direction.gd").configure_player_lighting(target)


func _build_dungeon() -> void:
	cave_geometry = CAVE_GEOMETRY.new()
	cave_geometry.name = "CaveGeometry"
	add_child(cave_geometry)
	cave_geometry.build()


func _spawn_player() -> void:
	player = PLAYER_SCRIPT.new() as DungeonPlayer
	player.position = CAVE_LAYOUT.spawn_position()
	var trial_room := TestRoomSandbox.consume_cave_entry_room()
	if not trial_room.is_empty():
		player.position = CAVE_LAYOUT.room_position(trial_room) + Vector3.UP
	player.setup(self, hud, inventory)
	player.died.connect(_on_player_died)
	add_child(player)
	configure_player_lighting(player)
	if is_instance_valid(cave_geometry.water_system):
		cave_geometry.water_system.bind_player(player)


func _spawn_encounters() -> void:
	var guards := {
		"quarry_warden": ["중앙 채석장의 검지기", 82.0, 21.0, 2.1, "fracture"],
		"drowned_miner": ["굶주린 침수 갱도의 광부", 65.0, 17.0, 2.1, "poison"],
		"workroom_guard": ["감독관 작업실의 감시자", 76.0, 20.0, 2.0, "curse"],
		"store_guard": ["동쪽 창고의 검지기", 68.0, 18.0, 2.2, "fracture"],
		"shrine_warden": ["기둥 성소의 수호자", 92.0, 23.0, 2.05, "curse"],
		"bone_scavenger": ["굶주린 거수 무덤의 망자", 64.0, 17.0, 2.3, "bleeding"],
	}
	for placement: Dictionary in CAVE_LAYOUT.gameplay("enemies"):
		var profile: Array = guards[placement.id]
		_spawn_enemy(profile[0], placement.position, profile[1], profile[2], profile[3], Color(0.24, 0.21, 0.17), profile[4])
	for actor in get_children():
		if actor is DungeonEnemy:
			actor.detection_range = 9.0
	var hazards := {
		"workshop_rune": ["작업실의 속박 룬", 27.0, 0.82, 0.60, "paralysis"],
		"quarry_rune": ["채석장의 철침진", 32.0, 0.92, 0.44, "bleeding"],
		"hoist_rune": ["승강기실의 봉인 룬", 30.0, 0.90, 0.57, "fracture"],
		"shrine_rune": ["기둥 성소의 마지막 봉인", 35.0, 1.02, 0.40, "curse"],
	}
	for placement: Dictionary in CAVE_LAYOUT.gameplay("traps"):
		var profile: Array = hazards[placement.id]
		_spawn_trap(profile[0], placement.position, profile[1], profile[2], profile[3], profile[4])


func _spawn_loot_chests() -> void:
	_spawn_loot_sites("blackwater_cave")

func _build_extraction_gate() -> void:
	var existing_children := get_children()
	super._build_extraction_gate()
	var gate_offset: Vector3 = CAVE_LAYOUT.extraction_position() - Vector3(0, 0, -15)
	for child in get_children():
		if child is Node3D and not existing_children.has(child):
			child.position += gate_offset


func _begin_scene_loading(scene_path: String, title_text: String, detail_text: String, status_text: String, failure_text: String) -> void:
	# The inherited death / extraction shortcuts must start another cave run.
	var target_path := restart_scene_path() if scene_path == GAME_SCENE_PATH else scene_path
	var target_detail := "검은 물길 동굴과 원정 장비를 다시 준비하고 있습니다" if target_path == CAVE_SCENE_PATH else detail_text
	super._begin_scene_loading(target_path, title_text, target_detail, status_text, failure_text)


func restart_scene_path() -> String:
	return CAVE_SCENE_PATH


func _on_extraction_body_entered(body: Node3D) -> void:
	super._on_extraction_body_entered(body)
	if body == player and game_mode == GameMode.WON:
		hud.overlay_detail.text = hud.overlay_detail.text.replace("검은 성물실", DUNGEON_TITLE)


func _placement_position(kind: String, id: String) -> Vector3:
	for placement: Dictionary in CAVE_LAYOUT.gameplay(kind):
		if placement.id == id:
			return placement.position
	push_error("Missing authored mine placement: " + id)
	return CAVE_LAYOUT.spawn_position()


func chamber_title_at(world_position: Vector3) -> String:
	var point := Vector2(world_position.x, world_position.z)
	for room: Dictionary in _chamber_data:
		if Geometry2D.is_point_in_polygon(point, room.polygon):
			return str(room.title)
	return "어두운 연결 갱도"


func _update_chamber_hud() -> void:
	if not is_instance_valid(player) or not is_instance_valid(hud):
		return
	var next_title := chamber_title_at(player.global_position)
	if next_title == _current_chamber_title:
		return
	_current_chamber_title = next_title
	hud.location_label.text = "%s · %s" % [DUNGEON_TITLE, next_title]
	hud.location_label.add_theme_color_override("font_color", Color(0.81, 0.65, 0.43))


func get_dungeon_info() -> Dictionary:
	return {
		"id": "blackwater_cave",
		"title": DUNGEON_TITLE,
		"width_m": CAVE_LAYOUT.WIDTH,
		"depth_m": CAVE_LAYOUT.DEPTH,
		"chambers": _chamber_data.size(),
		"layout_version": 2,
		"passages": CAVE_LAYOUT.corridors().size(),
		"water_surfaces": CAVE_LAYOUT.pools().size(),
		"geometry_source": "Blender",
		"enemy_count": 6,
		"trap_count": 4,
		"chest_count": loot_chests.size(),
		"chest_candidate_count": loot_spawn_sites.size(),
		"chest_occupancy_limits": LOOT_SPAWN_CATALOG.occupancy_limits("blackwater_cave"),
		"spawn": CAVE_LAYOUT.spawn_position(),
		"extraction": CAVE_LAYOUT.extraction_position(),
	}
