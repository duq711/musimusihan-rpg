extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const APPEARANCE := preload("res://scripts/player_appearance.gd")
const HEM_NAMES := ["Medival_HemBackSoft", "Medival_HemFrontSoft"]
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
	_check(sandbox.active and paused and room.panel_open and bag != original, "cloth trial must begin in the paused, isolated test expedition")
	_check(body != null and body.get_meta("model_path", "") == APPEARANCE.MODEL_PATH, "observer must use the production player body")
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_cloth_motion")
	_check(entries.size() == 1 and entries[0].action == "player_cloth_motion" and entries[0].category == "기본", "cloth motion must be an executable basic-category entry")
	for iteration in range(2):
		room.run_feature("player_cloth_motion")
		await process_frame
		var observer: Camera3D = room.cloth_observation_camera
		_check(is_instance_valid(observer) and observer.current and get_root().get_camera_3d() == observer, "cloth trial must use a live third-person camera")
		_check(observer.get_parent() == player and (observer.cull_mask & APPEARANCE.BODY_LAYER) != 0, "camera must follow the same player and render the real body layer")
		_check(player.player_body == body and not first_person_camera.visible and not first_person_camera.current, "trial must show the existing player body while hiding first-person equipment")
		_check(not paused and not room.panel_open and room.game_mode == room.GameMode.RUNNING, "cloth trial must resume actual gameplay and physics")
		var hems := _inspect_live_hems(body)
		var controllers: Array[Node] = []
		for hem_name in HEM_NAMES:
			var controller := body.find_child("MedivalClothSimulation_" + hem_name, true, false)
			_check(controller != null and bool(controller.get_motion_state().get("configured", false)), "each independent hem must have a configured spring motion driver: " + hem_name)
			if controller != null:
				controllers.append(controller)
		_check(controllers.size() == 2 and body.find_children("MedivalClothSimulation_*", "Node", true, false).size() == 2, "the player must have exactly one independent motion driver per hem")
		var lower_indices: Array[PackedInt32Array] = []
		var still_samples: Array[PackedVector3Array] = []
		if iteration == 0 and hems.size() == 2 and controllers.size() == 2:
			for step in range(24):
				await physics_frame
			for hem_index in hems.size():
				var hem: MeshInstance3D = hems[hem_index]
				var rest: PackedVector3Array = controllers[hem_index].get_rest_vertices()
				var indices := _lower_edge_indices(rest)
				lower_indices.append(indices)
				still_samples.append(_sample_points(hem, indices))
				_check(_max_rest_deviation(hem, rest) < 0.08 and _top_edge_fixed(hem, rest), "cloth must start near its authored shape with its top edge fixed")
		var start := player.global_position
		var peak_motion := 0.0
		for step in range(30):
			player.advance_movement(1.0 / 30.0, Vector2(0.0, -1.0), false)
			await physics_frame
			if iteration == 0 and hems.size() == 2 and controllers.size() == 2:
				for hem_index in hems.size():
					peak_motion = maxf(peak_motion, _point_rms_motion(hems[hem_index], lower_indices[hem_index], still_samples[hem_index]))
					if step % 5 == 0:
						_check(_max_rest_deviation(hems[hem_index], controllers[hem_index].get_rest_vertices()) < 0.08, "all moving cloth vertices must remain within a bounded distance of the authored hem")
		_check(player.global_position.distance_to(start) > 0.02, "the real player movement path must move the observed body")
		_check((observer.global_position - player.global_position).length() < 2.5, "observer must follow the moving player's transform")
		for step in range(110 if iteration == 0 else 8):
			player.advance_movement(1.0 / 30.0, Vector2.ZERO, false)
			await physics_frame
		if iteration == 0 and hems.size() == 2 and controllers.size() == 2:
			var settled_motion := 0.0
			for hem_index in hems.size():
				settled_motion = maxf(settled_motion, _point_rms_motion(hems[hem_index], lower_indices[hem_index], still_samples[hem_index]))
				var rest: PackedVector3Array = controllers[hem_index].get_rest_vertices()
				_check(_max_rest_deviation(hems[hem_index], rest) < 0.08 and _top_edge_fixed(hems[hem_index], rest), "no cloth vertex may stretch away and the upper edge must remain attached after movement")
			_check(peak_motion > 0.0015 and peak_motion < 0.08, "actual lower hem vertices must move visibly but stay within a human garment's range")
			_check(settled_motion < maxf(0.008, peak_motion * 0.55), "cloth motion must damp toward its standing shape after movement stops")
			for controller in controllers:
				var state: Dictionary = controller.get_motion_state()
				_check((state.get("target", Vector3.ZERO) as Vector3).length() < 0.01 and (state.get("offset", Vector3.ZERO) as Vector3).length() < 0.015 and (state.get("spring_velocity", Vector3.ZERO) as Vector3).length() < 0.015, "cloth spring target, offset and velocity must settle after the wearer stops")
		player.rotation.y = deg_to_rad(35.0)
		await process_frame
		_check(observer.global_position.is_finite(), "turning must leave the observer at a finite position")
		await _press_f2()
		_check(room.panel_open and paused and room.game_mode == room.GameMode.PAUSED, "F2 must pause the real test room")
		_check(room.cloth_observation_camera == null and first_person_camera.visible and first_person_camera.current and get_root().get_camera_3d() == first_person_camera, "F2 must restore the original camera and first-person equipment")
		_check(player.player_body == body and room.inventory == bag, "inspection must preserve the player and trial inventory")
	room.run_feature("player_cloth_motion")
	await process_frame
	_check(is_instance_valid(room.cloth_observation_camera), "cloth trial must be restartable after F2")
	room.reset_room()
	await process_frame
	_check(room.cloth_observation_camera == null and first_person_camera.visible and first_person_camera.current and room.panel_open and paused, "reset must restore the original camera and paused menu")
	_check(sandbox.saved_session == saved and original.slots == original_slots, "trial and reset must preserve the original expedition")
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved, "leaving must restore the original expedition")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("PLAYER CLOTH MOTION PASS: two attached spring-mesh hems move and settle with the actual player, third-person F2/reselection/reset cleanup, expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


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


func _inspect_live_hems(body: Node3D) -> Array[MeshInstance3D]:
	var hems: Array[MeshInstance3D] = []
	for hem_name in HEM_NAMES:
		var hem := body.find_child(hem_name, true, false) as MeshInstance3D
		_check(hem != null and hem.visible and hem.mesh is ArrayMesh, "visible hem must be the deforming production garment mesh: " + hem_name)
		if hem == null or hem.mesh == null:
			continue
		_check(hem.layers == APPEARANCE.BODY_LAYER and hem.mesh.get_surface_count() == 1, "cloth must render as one production garment surface on the body layer")
		var controller := body.find_child("MedivalClothSimulation_" + hem_name, true, false)
		if controller == null:
			continue
		var vertices: PackedVector3Array = controller.get_rest_vertices()
		var live: PackedVector3Array = hem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_check(vertices.size() > 100 and live.size() == vertices.size(), "spring cloth must preserve the full authored garment vertex topology")
		var top := -INF
		var bottom := INF
		for vertex in vertices:
			top = maxf(top, vertex.y)
			bottom = minf(bottom, vertex.y)
		var fixed_count := 0
		var free_count := 0
		for index in vertices.size():
			if top - vertices[index].y <= 0.0001:
				fixed_count += 1
				_check(live[index].distance_to(vertices[index]) < 0.0002, "the top hem vertices must stay fixed to the wearer: " + hem_name)
			elif top - vertices[index].y > 0.02:
				free_count += 1
		_check(fixed_count >= 4 and free_count >= 4 and fixed_count < vertices.size() / 2, "hem must have an anchored waist and a mobile lower edge")
		var bounds := hem.mesh.get_aabb()
		_check(bounds.position.is_finite() and bounds.size.is_finite() and bounds.size.y > 0.12 and bounds.size.y < 0.35 and bounds.size.x < 0.9 and bounds.size.z < 0.45 and bottom > 0.72 and top < 1.1, "deforming garment must retain a finite, human-sized shape around the waist")
		hems.append(hem)
	_check(hems.size() == 2, "the production outfit needs both front and back moving hems")
	return hems


func _lower_edge_indices(vertices: PackedVector3Array) -> PackedInt32Array:
	var lowest := INF
	for vertex in vertices:
		lowest = minf(lowest, vertex.y)
	var indices := PackedInt32Array()
	for index in vertices.size():
		if vertices[index].y - lowest < 0.028:
			indices.append(index)
	_check(indices.size() >= 4, "each hem needs several moving lower-edge vertices")
	return indices


func _sample_points(hem: MeshInstance3D, indices: PackedInt32Array) -> PackedVector3Array:
	var positions := PackedVector3Array()
	var vertices: PackedVector3Array = hem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point_index in indices:
		positions.append(vertices[point_index])
	return positions


func _point_rms_motion(hem: MeshInstance3D, indices: PackedInt32Array, baseline: PackedVector3Array) -> float:
	if indices.is_empty() or indices.size() != baseline.size():
		return 0.0
	var vertices: PackedVector3Array = hem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var squared := 0.0
	for index in indices.size():
		var point := vertices[indices[index]]
		_check(point.is_finite(), "simulated cloth vertices must remain finite")
		squared += point.distance_squared_to(baseline[index])
	return sqrt(squared / indices.size())


func _max_rest_deviation(hem: MeshInstance3D, rest: PackedVector3Array) -> float:
	var vertices: PackedVector3Array = hem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == rest.size(), "deformation must not change the garment's vertex count")
	if vertices.size() != rest.size():
		return INF
	var maximum := 0.0
	for index in vertices.size():
		var point := vertices[index]
		_check(point.is_finite(), "every simulated cloth point must remain finite")
		maximum = maxf(maximum, point.distance_to(rest[index]))
	return maximum


func _top_edge_fixed(hem: MeshInstance3D, rest: PackedVector3Array) -> bool:
	var vertices: PackedVector3Array = hem.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if vertices.size() != rest.size():
		return false
	var top := -INF
	for point in rest:
		top = maxf(top, point.y)
	var count := 0
	for index in rest.size():
		if top - rest[index].y <= 0.0001:
			count += 1
			if vertices[index].distance_to(rest[index]) >= 0.0002:
				return false
	return count >= 4


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
	_check(false, "cloth trial scene transition timed out: " + path)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
