extends SceneTree
## The replacement source outfit is unrigged. This checks its real movement
## observation path and proves its intact garment topology is not deformed.

const ROOM_PATH := "res://test_room.tscn"
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var sandbox := root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 9)
	var saved := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	var player: DungeonPlayer = room.player
	var body: Node3D = player.player_body
	var first_person_camera: Camera3D = player.camera
	_check(sandbox.active and paused and room.panel_open and bag != original, "outfit trial must begin in the paused, isolated test expedition")
	_check(body != null and body.get_meta("outfit_path", "") == APPEARANCE.OUTFIT_PATH, "observer must use the replacement source outfit")
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_cloth_motion")
	_check(entries.size() == 1 and entries[0].action == "player_cloth_motion" and entries[0].category == "기본", "outfit observation must be an executable basic-category entry")
	for iteration in range(2):
		room.run_feature("player_cloth_motion")
		await process_frame
		var observer: Camera3D = room.cloth_observation_camera
		_check(is_instance_valid(observer) and observer.current and get_root().get_camera_3d() == observer, "outfit trial must use a live third-person camera")
		_check(observer.get_parent() == player and (observer.cull_mask & APPEARANCE.BODY_LAYER) != 0, "camera must follow the same player and render the garment layer")
		_check(player.player_body == body and not first_person_camera.visible and not first_person_camera.current, "trial must show the existing player outfit while hiding first-person equipment")
		_check(not paused and not room.panel_open and room.game_mode == room.GameMode.RUNNING, "outfit trial must resume actual gameplay and physics")
		var garment_meshes := _source_garments(body)
		_check(body.find_children("MedivalClothSimulation_*", "Node", true, false).is_empty(), "source shirt must not be split or spring-deformed")
		var source_meshes: Array[Mesh] = []
		var source_bounds: Array[AABB] = []
		for part in garment_meshes:
			source_meshes.append(part.mesh)
			source_bounds.append(part.mesh.get_aabb())
		var start := player.global_position
		for step in range(30):
			player.advance_movement(1.0 / 30.0, Vector2(0.0, -1.0), false)
			await physics_frame
		_check(player.global_position.distance_to(start) > 0.02, "real player movement must move the observed outfit")
		_check((observer.global_position - player.global_position).length() < 2.5, "observer must follow the moving player's transform")
		for step in range(12):
			player.advance_movement(1.0 / 30.0, Vector2.ZERO, false)
			await physics_frame
		for index in garment_meshes.size():
			_check(garment_meshes[index].mesh == source_meshes[index] and garment_meshes[index].mesh.get_aabb() == source_bounds[index], "movement must preserve intact source garment geometry: " + str(garment_meshes[index].name))
		player.rotation.y = deg_to_rad(35.0)
		await process_frame
		_check(observer.global_position.is_finite(), "turning must leave the observer at a finite position")
		await _press_f2()
		_check(room.panel_open and paused and room.game_mode == room.GameMode.PAUSED, "F2 must pause the real test room")
		_check(room.cloth_observation_camera == null and first_person_camera.visible and first_person_camera.current and get_root().get_camera_3d() == first_person_camera, "F2 must restore the original camera and first-person equipment")
		_check(player.player_body == body and room.inventory == bag, "inspection must preserve player and trial inventory")
	room.run_feature("player_cloth_motion")
	await process_frame
	_check(is_instance_valid(room.cloth_observation_camera), "outfit trial must restart after F2")
	room.reset_room()
	await process_frame
	_check(room.cloth_observation_camera == null and first_person_camera.visible and first_person_camera.current and room.panel_open and paused, "reset must restore original camera and paused menu")
	_check(sandbox.saved_session == saved and original.slots == original_slots, "trial and reset must preserve original expedition")
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved, "leaving must restore original expedition")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("PLAYER OUTFIT OBSERVATION PASS: source garments stay intact while the playable model moves; F2/reselection/reset restore state")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _source_garments(body: Node3D) -> Array[MeshInstance3D]:
	var garments: Array[MeshInstance3D] = []
	for part_name in APPEARANCE.OUTFIT_PARTS:
		var part := body.find_child(part_name, true, false) as MeshInstance3D
		_check(part != null and part.visible and part.mesh != null, "all five original garment and shoe meshes must remain visible: " + part_name)
		if part != null and part.mesh != null:
			_check(part.layers == APPEARANCE.BODY_LAYER and part.mesh.get_surface_count() > 0, "source garment must render on the player layer: " + part_name)
			garments.append(part)
	_check(garments.size() == APPEARANCE.OUTFIT_PARTS.size(), "the observed model must display every original outfit piece")
	return garments


func _press_f2() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F2
	event.physical_keycode = KEY_F2
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_for_scene(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "outfit trial scene transition timed out: " + path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
