extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const OUTFIT_PATH := "res://assets/3d/player/medival_outfit.glb"
const BODY_LAYER := 1 << 17
const APPEARANCE := preload("res://scripts/player_appearance.gd")
var failures: Array[String] = []
var sandbox: Node


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Exercise the shipped fallback even when this Mac has the optional asset.
	var fallback := APPEARANCE.create_body(false)
	if fallback == null:
		push_error("Public Medival fallback could not be instantiated.")
		quit(1)
		return
	root.add_child(fallback)
	_check(not bool(fallback.get_meta("licensed_character", true)), "explicit fallback must not depend on the local licensed character")
	_check(_contains_import(fallback) and _contains_import(fallback, OUTFIT_PATH), "public fallback must retain its two shipped model resources")
	_inspect_supplied_body_hands(_meshes(fallback))
	_inspect_outfit_composite(fallback, _meshes(fallback))
	fallback.free()
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 11)
	original.equipment["weapon"] = "hunting_bow"
	ExpeditionSession.crowns = 631
	ExpeditionSession.hunger = 62.0
	ExpeditionSession.thirst = 48.0
	ExpeditionSession.stress = 29.0
	ExpeditionSession.apply_condition("bleeding", 37.0)
	var saved := ExpeditionSession.capture_snapshot()
	var original_slots := original.slots.duplicate(true)
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	_check(sandbox.active and paused and room.panel_open and bag != original, "appearance inspection must begin in the paused, isolated test expedition")
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_appearance")
	_check(entries.size() == 1 and entries[0].action == "player_appearance" and entries[0].category == "기본", "player appearance must have one executable basic-category entry")
	for iteration in range(2):
		var equipment := bag.equipment.duplicate(true)
		var slots := bag.slots.duplicate(true)
		var trial_before := ExpeditionSession.capture_snapshot()
		room.run_feature("player_appearance")
		await process_frame
		_check(room.inventory_overlay.is_open() and not room.panel_open and paused and room.game_mode == room.GameMode.INVENTORY, "appearance fixture must open the real paused inventory")
		await _inspect_shared_model(room)
		_check(is_zero_approx(room.inventory_overlay.player_portrait.get_view_angle()), "reselecting the appearance fixture must restore the same front view")
		await _test_rotation_controls(room.inventory_overlay.player_portrait)
		_check(bag.equipment == equipment and bag.slots == slots and ExpeditionSession.capture_snapshot() == trial_before, "inspection and rotation must preserve current trial inventory, equipment and survival values")
		await _press_f2()
		_check(room.panel_open and paused and not room.inventory_overlay.is_open(), "F2 must close appearance inspection and restore the paused test menu")
		_check(room.inventory_overlay.player_portrait.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "closing the portrait must stop its hidden rendering")
		_check(sandbox.saved_session == saved and original.slots == original_slots, "repeated appearance inspection must never modify the saved expedition")
		room.run_feature("dungeon")
		if not await _wait_for_scene("res://main.tscn"):
			break
		var dungeon := current_scene as Node3D
		dungeon.player.set_physics_process(false)
		_check(dungeon.inventory == bag, "the linked real dungeon must retain the isolated trial bag")
		dungeon._open_inventory()
		await process_frame
		_check(dungeon.inventory_overlay.is_open() and paused, "ordinary dungeon inventory must expose the same real character portrait")
		_check(dungeon.inventory_overlay.health_tab_active, "normal inventory must retain the unified default page")
		dungeon.inventory_overlay.open_appearance_view()
		await process_frame
		await _inspect_shared_model(dungeon)
		await _press_f2()
		if not await _wait_for_scene(ROOM_PATH):
			break
		room = current_scene as Node3D
		_check(room.panel_open and paused and room.inventory == bag, "F2 from the linked appearance inventory must restore the paused test room and the same bag")
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room.reset_room()
		await process_frame
		_check(room.inventory != bag and sandbox.saved_session == saved and room.panel_open and paused, "test-room reset must create a fresh trial bag while preserving the original expedition")
		room.run_feature("player_appearance")
		await process_frame
		await _inspect_shared_model(room)
		_check(room.inventory_overlay.inventory_model == room.inventory and is_zero_approx(room.inventory_overlay.player_portrait.get_view_angle()), "inspection after reset must show the new trial bag and initial model view")
		var portrait_ref: WeakRef = weakref(room.inventory_overlay.player_portrait)
		var viewport_ref: WeakRef = weakref(room.inventory_overlay.player_portrait.viewport)
		var body_ref: WeakRef = weakref(room.player.player_body)
		await _press_f2()
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
		_check(portrait_ref.get_ref() == null and viewport_ref.get_ref() == null and body_ref.get_ref() == null, "leaving must free the actual player body and portrait viewport together with their scene")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == saved and original.slots == original_slots, "ending appearance trials must restore the original inventory identity, equipment, conditions and every saved expedition value")
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("PLAYER APPEARANCE PASS: actual imported 3D body and shared inventory portrait, camera layers, paused rotation controls, repeated F2/dungeon roundtrips, reset, cleanup and full expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _inspect_shared_model(scene: Node3D) -> void:
	var player: DungeonPlayer = scene.player
	var body: Node3D = player.player_body
	var portrait: Control = scene.inventory_overlay.player_portrait
	_check(is_instance_valid(body) and body.get_parent() == player and is_equal_approx(body.position.y, -0.89), "the playable character must own the full body at its actual foot origin")
	_check(portrait.name == "PlayerPortrait" and portrait.get_script().resource_path == "res://scripts/player_portrait.gd", "the normal inventory must use the shipped 3D portrait control")
	_check(portrait.is_visible_in_tree() and portrait.can_process(), "the real portrait must remain visible and usable while the world is paused")
	_check(portrait.viewport.own_world_3d and portrait.viewport.find_world_3d() != player.get_world_3d() and portrait.body.get_world_3d() == portrait.viewport.find_world_3d(), "portrait lighting and camera must be isolated from the playable world")
	_check(portrait.camera.current and portrait.camera.get_viewport() == portrait.viewport, "portrait must render its live model with its own active 3D camera")
	_inspect_portrait_framing(portrait)
	_check(portrait.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "opening inventory must enable actual portrait rendering")
	_check((player.camera.cull_mask & BODY_LAYER) == 0 and (portrait.camera.cull_mask & BODY_LAYER) != 0, "first-person view must exclude the full body while the portrait can see it")
	_check((player.viewmodel_renderer.camera.cull_mask & BODY_LAYER) == 0, "the full body must not leak into the carried-equipment rendering")
	var body_meshes := _meshes(body)
	var portrait_meshes := _meshes(portrait.body)
	_check(body.find_children("*", "Sprite3D", true, false).is_empty() and portrait.body.find_children("*", "Sprite3D", true, false).is_empty(), "the character must use actual volumetric meshes without image billboards")
	_check(not body_meshes.is_empty() and body_meshes.size() == portrait_meshes.size(), "world body and portrait must contain the same non-empty imported 3D geometry")
	var licensed := APPEARANCE.has_licensed_character()
	var expected_model: String = APPEARANCE.LICENSED_MODEL_PATH if licensed else MODEL_PATH
	_check(_contains_import(body, expected_model) and _contains_import(portrait.body, expected_model), "world and portrait must instantiate the same available production GLB")
	_check(bool(body.get_meta("licensed_character", false)) == licensed and bool(portrait.body.get_meta("licensed_character", false)) == licensed, "both presentations must choose Roger only when the local licensed model is available")
	if not licensed:
		_check(_contains_import(body, OUTFIT_PATH) and _contains_import(portrait.body, OUTFIT_PATH), "public fallback must load the shipped Medival garment GLB")
	var mask_materials: Dictionary = {}
	if body_meshes.size() == portrait_meshes.size():
		for index in range(body_meshes.size()):
			var world_mesh: MeshInstance3D = body_meshes[index]
			var portrait_mesh: MeshInstance3D = portrait_meshes[index]
			_check(world_mesh.name == portrait_mesh.name and world_mesh.visible == portrait_mesh.visible, "portrait and world body must have matching parts and active visibility: " + str(world_mesh.name))
			_check(world_mesh.mesh == portrait_mesh.mesh and world_mesh.material_override == portrait_mesh.material_override, "portrait and world body must share the intact source geometry and material resources: " + str(world_mesh.name))
			_check(world_mesh.layers == BODY_LAYER and portrait_mesh.layers == BODY_LAYER, "every body mesh must use the dedicated character layer: " + str(world_mesh.name))
			_check(world_mesh.mesh != null and world_mesh.mesh.get_surface_count() > 0, "body parts must have real mesh surfaces: " + str(world_mesh.name))
			if world_mesh.visible:
				for surface_index in range(world_mesh.mesh.get_surface_count()):
					var material := world_mesh.mesh.surface_get_material(surface_index) as BaseMaterial3D
					_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not material.emission_enabled, "visible character surfaces must respond to real scene lighting instead of displaying unlit concept art")
					if material != null and str(world_mesh.name) in APPEARANCE.OUTFIT_PARTS:
						_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "replacement source garment must be opaque: " + str(world_mesh.name))
					elif licensed and material != null and material.resource_name in ["Roger_Hair", "Roger_Scalp"]:
						mask_materials[material.resource_name] = true
						_check(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and is_equal_approx(material.alpha_scissor_threshold, 0.3), "Roger hair and scalp must use the corrected depth-tested alpha cutout")
	if licensed:
		_check(mask_materials.size() == 2, "Roger must retain both imported hair and scalp cutout materials")
	if not licensed:
		_inspect_supplied_body_hands(body_meshes)
		_inspect_supplied_body_hands(portrait_meshes)
	_inspect_outfit_composite(body, body_meshes)
	_inspect_outfit_composite(portrait.body, portrait_meshes)
	# This checks the real imported mesh bounds, not a synthetic success flag.
	var active_meshes: Array[MeshInstance3D] = []
	for part in body_meshes:
		if part.visible:
			active_meshes.append(part)
	var bounds := _body_bounds(body, active_meshes)
	if licensed:
		_check(bounds.size.y > 1.75 and bounds.size.y < 1.95 and bounds.size.x > 0.5 and bounds.size.x < 2.0 and bounds.size.z > 0.2 and bounds.size.z < 0.8, "local Roger must have complete human-scale head-to-shoe bounds")
	else:
		_check(bounds.size.y > 1.52 and bounds.size.y < 1.68 and bounds.size.x > 1.1 and bounds.size.x < 1.3 and bounds.size.z > 0.2 and bounds.size.z < 0.8, "the visible replacement outfit must retain its full source shirt-to-shoe dimensions and original sleeve span")
	_check(bounds.position.y > -0.08 and bounds.position.y < 0.08, "the visible replacement outfit must include the original shoes at floor height")
	_inspect_first_person_materials(player)
	await process_frame


func _inspect_supplied_body_hands(parts: Array[MeshInstance3D]) -> void:
	var names: Array[String] = []
	for part in parts:
		var part_name := str(part.name)
		names.append(part_name)
		for retired: String in ["Gravebound_SuppliedHand_", "Gravebound_SuppliedNail_", "Gravebound_Finger_", "Gravebound_FingerlessGlove_", "Gravebound_Sleeve_", "Gravebound_Bracer_"]:
			_check(not part_name.begins_with(retired), "old hands and overlapping sleeves must be physically removed: " + part_name)
		if not part_name.begins_with("Gravebound_FP_"): continue
		var vertex_count := 0
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			vertex_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var material := part.get_active_material(surface) as BaseMaterial3D
			_check(material != null and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null, "replacement FP arm/hand must carry actual color and normal textures")
		_check(vertex_count > 100, "replacement must contain the detailed source geometry")
		_check(part.skin == null, "fullbody standing pose must be baked without inactive duplicate rigs")
		if part_name.ends_with("_Arm"):
			var highest := -INF
			var to_body: Transform3D = part.get_parent().global_transform.affine_inverse() * part.global_transform
			for surface in part.mesh.get_surface_count():
				for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					highest = maxf(highest, (to_body * vertex).y)
			_check(highest > 1.42 and highest < 1.46, "FP sleeve upper end must retain its fitted shoulder height")
	_check(parts.size() == 25, "fullbody must retain its 20 original pieces and add the five original Medival garment and shoe pieces")
	for retired: String in ["Gravebound_PointHood", "Gravebound_InnerNeckCowl", "Gravebound_Mantle_L", "Gravebound_Mantle_R", "Gravebound_MantleBack", "Gravebound_CoatBackAndSides", "Gravebound_CoatSkirt_L", "Gravebound_CoatSkirt_R"]:
		_check(not retired in names, "world body and portrait must omit removed hood, neck cloth and long coat tails: " + retired)
	for side: String in ["L", "R"]:
		for section: String in ["Arm", "Hand"]:
			_check(names.count("Gravebound_FP_" + side + "_" + section) == 1, "each anatomical arm and hand must occur exactly once")


func _inspect_outfit_composite(body: Node3D, parts: Array[MeshInstance3D]) -> void:
	var by_name: Dictionary = {}
	for part in parts:
		by_name[str(part.name)] = part
	var hidden_originals := 0
	for part in parts:
		if str(part.name).begins_with("Gravebound_"):
			_check(not part.visible, "every original head, eye, hand, boot and garment mesh must be hidden without deleting its source: " + str(part.name))
			hidden_originals += 1
	if bool(body.get_meta("licensed_character", false)):
		_check(hidden_originals == 0, "local Roger must not carry a duplicate former body")
		var roger_parts := 0
		for part in parts:
			if str(part.name).begins_with("Roger_"):
				roger_parts += 1
				_check(part.visible and part.mesh != null and part.mesh.get_surface_count() > 0, "Roger body surfaces must exist and render: " + str(part.name))
				_check(part.skin == null, "Roger's fitted standing pose must not retain an inactive skin rig: " + str(part.name))
		_check(roger_parts > 0, "local dressed character must include Roger body geometry, not just the garments")
		for body_part in ["Roger_Head_Neck", "Roger_Hand_L", "Roger_Hand_R", "Roger_Calf_L", "Roger_Calf_R"]:
			_check(by_name.has(body_part), "fitted Roger must retain each exposed anatomical region: " + body_part)
	else:
		_check(hidden_originals == 20, "all twenty original meshes must stay in the fallback scene but not render")
	for garment_name in APPEARANCE.OUTFIT_PARTS:
		_check(by_name.has(garment_name) and (by_name.get(garment_name) as MeshInstance3D).visible, "supplied original outfit part must be present and visible: " + garment_name)
	_check(body.find_children("MedivalClothSimulation_*", "Node", true, false).is_empty(), "the intact source tunic must not be cut into simulated hem panels")


func _inspect_portrait_framing(portrait: Control) -> void:
	var bounds := APPEARANCE.visible_bounds(portrait.body)
	var half_height: float = portrait.camera.size * 0.5
	var half_width: float = half_height * float(portrait.viewport.size.x) / float(portrait.viewport.size.y)
	var initial_angle: float = portrait.get_view_angle()
	for degrees in [0.0, 90.0, 180.0, 270.0]:
		portrait.set_view_angle(degrees)
		for corner in range(8):
			var camera_point: Vector3 = portrait.camera.to_local(portrait.body.to_global(bounds.get_endpoint(corner)))
			_check(absf(camera_point.x) < half_width and absf(camera_point.y) < half_height, "portrait must keep head, hands and shoes inside the frame after rotation")
	portrait.set_view_angle(initial_angle)


func _inspect_first_person_materials(player: DungeonPlayer) -> void:
	# All current equipment roles share the supplied FP pair. Dedicated legacy
	# sword/shield assets and the September 11 bare hands are no longer shipped.
	for arm: Node3D in [player._legacy_weapon_arm, player.weapon_arm, player.shield_arm, player.sword_support_arm, player.torch_arm, player.left_support_arm, player.right_relaxed_arm]:
		_check("fp_arms/" in str(arm.get_meta("source_model", "")), "first-person equipment must retain the current source used by the fullbody replacement")
		_check(not arm.get("hand_meshes").is_empty() and not arm.get("arm_meshes").is_empty(), "first-person source must retain both hand and sleeve surfaces")


func _test_rotation_controls(portrait: Control) -> void:
	var right := portrait.find_child("ViewRight", true, false) as Button
	var left := portrait.find_child("ViewLeft", true, false) as Button
	var reset := portrait.find_child("ViewReset", true, false) as Button
	_check(is_instance_valid(right) and is_instance_valid(left) and is_instance_valid(reset), "portrait must provide executable left/right/front controls")
	if not is_instance_valid(right) or not is_instance_valid(left) or not is_instance_valid(reset):
		return
	var initial_rotation: Vector3 = portrait.body.rotation
	right.pressed.emit()
	await process_frame
	_check(is_equal_approx(absf(portrait.get_view_angle()), 30.0) and portrait.body.rotation != initial_rotation, "right rotation must rotate the actual model by 30 degrees while paused")
	left.pressed.emit()
	_check(is_zero_approx(portrait.get_view_angle()) and portrait.body.rotation.is_equal_approx(initial_rotation), "opposite rotation must restore the same model orientation")
	for step in range(6):
		right.pressed.emit()
	_check(is_equal_approx(absf(portrait.get_view_angle()), 180.0), "rotation must allow inspecting the model's back")
	reset.pressed.emit()
	_check(is_zero_approx(portrait.get_view_angle()) and portrait.body.rotation.is_equal_approx(initial_rotation), "front control must restore the initial model orientation")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result


func _contains_import(node: Node, expected_path: String = MODEL_PATH) -> bool:
	if node.scene_file_path == expected_path:
		return true
	for child in node.get_children():
		if _contains_import(child, expected_path):
			return true
	return false


func _body_bounds(body: Node3D, meshes: Array[MeshInstance3D]) -> AABB:
	var bounds := AABB()
	var initialized := false
	for instance in meshes:
		if instance.mesh == null:
			continue
		var local_to_body: Transform3D = body.global_transform.affine_inverse() * instance.global_transform
		var transformed: AABB = local_to_body * instance.mesh.get_aabb()
		bounds = bounds.merge(transformed) if initialized else transformed
		initialized = true
	return bounds


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


func _wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "appearance trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
