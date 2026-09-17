extends SceneTree

const ARM := preload("res://scripts/greybox_arm_visual.gd")
const PREVIEW := preload("res://tests/player_hands_detailed_preview.gd")
const EQUIPMENT_LAYER := 1 << 19
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_imported_rigs_and_actual_skin()
	await _test_player_runtime_and_preview()
	await _test_room_lifecycle()
	paused = false
	if is_instance_valid(current_scene): current_scene.queue_free()
	current_scene = null
	await process_frame
	for failure in failures: push_error(failure)
	print("PLAYER HANDS DETAILED %s: bilateral imported skin and handedness, real finger deformation, free/bow/chest gameplay, render layers, default fidelity and isolated F2/repeat/switch/reset/exit" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


func _test_imported_rigs_and_actual_skin() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var stage := Node3D.new()
	root.add_child(stage)
	stage.transform = Transform3D(Basis(Vector3.UP, 0.3), Vector3(1.0, 0.5, -1.0))
	for side in [-1, 1]:
		var arm := ARM.new()
		stage.add_child(arm)
		_check(arm.setup(side, "detailed"), "detailed source must load for side " + str(side))
		var skeleton := arm.skeleton as Skeleton3D
		_check(skeleton != null and skeleton.get_bone_count() == 16, "both imported hands must retain all sixteen deform bones")
		if skeleton == null: continue
		_check(skeleton.find_bone("wrist") >= 0, "imported rig must retain the wrist bone")
		for digit: String in ["index", "middle", "ring", "little", "thumb"]:
			for joint in 3:
				_check(skeleton.find_bone(digit + str(joint)) >= 0, "all five digits require three imported joints: " + digit)
		var thumb := skeleton.get_bone_global_rest(skeleton.find_bone("thumb0")).origin
		var index := skeleton.get_bone_global_rest(skeleton.find_bone("index0")).origin
		var little := skeleton.get_bone_global_rest(skeleton.find_bone("little0")).origin
		_check(thumb.x * side < -0.01 and (index.x - little.x) * side < -0.04, "actual skeleton anatomy must match left/right handedness in dorsal wrist space")
		_check(arm.global_basis.determinant() > 0.0, "handedness must come from actual bilateral geometry without a reflected runtime frame")
		var source_path := "res://assets/3d/player/hands_detailed/%s_hand_detailed.glb" % ("left" if side < 0 else "right")
		var source := (load(source_path) as PackedScene).instantiate()
		var source_meshes: Array[Mesh] = []
		for mesh in _meshes(source): source_meshes.append(mesh.mesh)
		var greybox_path := "res://assets/3d/player/hands_greybox/%s_hand_greybox.glb" % ("left" if side < 0 else "right")
		var greybox := (load(greybox_path) as PackedScene).instantiate()
		_check(_triangle_count(source) > _triangle_count(greybox) * 2, "detailed hand must contain actual higher-density geometry than the preserved greybox")
		_check(_geometry_fingerprint(source) != _geometry_fingerprint(greybox), "detailed source must differ geometrically from the greybox, not only by materials")
		greybox.free()
		var previous_path := "res://assets/3d/player/sword_shield/%s_arm.glb" % ("left" if side < 0 else "right")
		var previous := (load(previous_path) as PackedScene).instantiate()
		var dense_hand := source.find_child("ContinuousAnatomicalHand*", true, false) as MeshInstance3D
		var previous_hand := previous.find_child("ContinuousAnatomicalHand*", true, false) as MeshInstance3D
		_check(dense_hand != null and previous_hand != null and _geometry_fingerprint(dense_hand) != _geometry_fingerprint(previous_hand), "skin and glove sculpt must change actual hand geometry beyond the previous dense source")
		previous.free()
		var skinned_count := 0
		var material_names: Array[String] = []
		for mesh in _meshes(arm):
			_check(source_meshes.has(mesh.mesh), "detailed rendering must use the actual imported GLB geometry")
			_check(mesh.mesh.get_aabb().size.length() > 0.001, "skin, nail and garment details must have nonempty physical geometry")
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				_check(material != null, "every detailed surface needs an actual material")
				if material == null: continue
				if not material_names.has(material.resource_name): material_names.append(material.resource_name)
				_check(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "detailed geometry must respond to actual gameplay lighting")
			if mesh.skin != null:
				skinned_count += 1
				_check(mesh.skin.get_bind_count() == 16 and mesh.get_node_or_null(mesh.skeleton) == skeleton, "visible hand geometry must really bind to its sixteen-bone Skeleton3D")
		_check(skinned_count > 0 and arm.arm_meshes.size() >= 2, "each imported detailed requires a skinned hand plus both real arm segments")
		for material_name: String in ["Detailed_Skin", "Detailed_Glove", "Detailed_Sleeve", "Detailed_Nail", "Detailed_Trim"]:
			_check(material_names.any(func(value: String) -> bool: return value.begins_with(material_name)), "detailed parts require their actual authored surface material: " + material_name)
		_check(arm.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual substitution must not add combat or interaction collisions")
		source.free()
		arm.reset_pose()
		var wrist := arm.global_transform
		var rest := _bone_poses(skeleton)
		var open_skin := _skin_samples(arm)
		var open_skin_surface := _skin_samples(arm, "Detailed_Skin")
		var open_seams := _skin_samples(arm, "Detailed_Trim")
		var nail_samples := {}
		for digit: String in ["thumb", "index", "middle", "ring", "little"]:
			var nail := arm.find_child("Nail_" + digit + "*", true, false) as MeshInstance3D
			_check(nail != null and nail.skin != null, "all five modeled nails must be real skinned geometry: " + digit)
			if nail != null:
				_check(_weighted_bone_names(nail, skeleton) == [digit + "2"], "each modeled nail must really attach to its own distal finger joint: " + digit)
				nail_samples[str(nail.name)] = _skin_samples(arm, "Detailed_Nail", str(nail.name))
		_check(open_skin_surface.size() > 50 and open_seams.size() > 8, "deformation checks require real skin and sewn trim surface vertices")
		_check(open_skin.size() >= 100, "deformation audit needs actual weighted source vertices")
		arm.set_finger_curl(0, -0.5, -0.8)
		_check(_bone_poses(skeleton) != rest and _max_displacement(open_skin, _skin_samples(arm)) > 0.005, "finger curl must move weighted rendered skin, not only a reported pose value")
		arm.reset_pose()
		_check(_bone_poses(skeleton) == rest and _max_displacement(open_skin, _skin_samples(arm)) < 0.00001, "reset must restore the imported open skin exactly")
		arm.set_grip(1.0)
		var grip_skin := _skin_samples(arm)
		_check(_max_displacement(open_skin, grip_skin) > 0.015, "full grip must deform the actual detailed finger surface")
		_check(_max_displacement(open_skin_surface, _skin_samples(arm, "Detailed_Skin")) > 0.015, "sculpted skin and knuckle creases must follow real finger joints")
		_check(_max_displacement(open_seams, _skin_samples(arm, "Detailed_Trim")) > 0.002, "modeled glove seams must deform with their actual skinned hand")
		for nail_name: String in nail_samples:
			var open_nail: PackedVector3Array = nail_samples[nail_name]
			_check(open_nail.size() > 8 and _max_displacement(open_nail, _skin_samples(arm, "Detailed_Nail", nail_name)) > 0.005, "each modeled nail must follow its own actual distal joint: " + nail_name)
		var segments_before := _transforms(arm.arm_meshes)
		arm.fit_arm(wrist.origin + wrist.basis * Vector3(float(side) * 0.11, 0.18, 0.55), wrist.origin + wrist.basis * Vector3(float(side) * 0.13, -0.04, 0.29))
		_check(_transforms(arm.arm_meshes) != segments_before and arm.global_transform.is_equal_approx(wrist), "arm fitting must move sleeve/forearm while preserving the wrist")
		_check(_max_displacement(grip_skin, _skin_samples(arm)) < 0.00001, "arm fitting must preserve the posed hand and equipment contact frame")
		arm.set_string_draw(1.0, 0.0)
		var hook := _skin_samples(arm)
		arm.set_string_draw(1.0, 1.0)
		_check(_max_displacement(hook, _skin_samples(arm)) > 0.01 and arm.global_transform.is_equal_approx(wrist), "bow release must open real detailed finger skin without moving its wrist")
		arm.set_relaxed_pose(0.0)
		var relaxed := _skin_samples(arm)
		arm.set_relaxed_pose(1.0)
		_check(_max_displacement(relaxed, _skin_samples(arm)) > 0.005, "free-hand openness must drive the real imported skeleton")
	stage.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "standalone detailed assembly and skin checks must preserve session and cursor")


func _test_player_runtime_and_preview() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var contents := PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory)
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d, "detailed preview must isolate world, external input, picking and audio")
	_check(not player.hands_detailed_enabled and player.hands_visual_profile == "original" and fixture.inventory != original.get("inventory"), "detailed must default off and QA must use the original appearance with a private inventory")
	await physics_frame
	await physics_frame
	var wrappers := [player._legacy_weapon_arm, player.torch_arm, player.left_support_arm, player.right_relaxed_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]
	var baseline := _legacy_state(wrappers)
	var bag_before := PREVIEW.inventory_contents(fixture.inventory)
	var anchors := _gameplay_anchors(player)
	_check(player.set_hands_detailed_enabled(true), "player-local opt-in must load both available detailed assets")
	_check(PREVIEW.inventory_contents(fixture.inventory) == bag_before and _gameplay_anchors(player) == anchors, "presentation toggle alone must preserve inventory, weapon hit/muzzle and equipment anchors")
	for wrapper: Node3D in wrappers:
		var detailed := wrapper.get("detailed_visual") as Node3D
		_check(detailed != null and detailed.visible, "every generic gameplay arm must connect to its actual detailed child")
		if detailed == null: continue
		var expected_layer := 1 if player.chest_hands.is_ancestor_of(wrapper) else EQUIPMENT_LAYER
		for mesh in _meshes(detailed): _check(mesh.layers == expected_layer, "late-created detailed must keep equipment layer20 or chest world layer1")
	_check(player.set_hands_detailed_enabled(false) and _legacy_state(wrappers) == baseline, "turning preview off must restore original mesh/material identities and visibility")
	_check(player.set_hands_greybox_enabled(true) and player.hands_visual_profile == "greybox" and not player.hands_detailed_enabled, "the previous greybox must remain available for comparison")
	_check(player.set_hands_detailed_enabled(false) and player.hands_visual_profile == "greybox", "disabling inactive detail must preserve an explicitly selected greybox")
	_check(player.set_hands_detailed_enabled(true) and player.hands_visual_profile == "detailed" and not player.hands_greybox_enabled, "detailed and greybox appearances must be mutually exclusive")
	for wrapper: Node3D in wrappers:
		_check(wrapper.get("detailed_visual").visible and not wrapper.get("greybox_visual").visible, "switching to detail must hide comparison geometry without overlaying duplicate hands")
	_check(player.set_hands_greybox_enabled(false) and player.hands_visual_profile == "detailed", "disabling inactive greybox must preserve selected detailed hands")
	_check(player.set_hands_visual_profile("original") and _legacy_state(wrappers) == baseline, "explicit original profile must restore the default source appearances")
	for pose_id: String in PREVIEW.POSE_IDS:
		_check(PREVIEW.configure_pose(fixture, pose_id), "capture must configure actual gameplay: " + pose_id)
		_check(bool(PREVIEW.inspect_pose(fixture, pose_id).passed), "capture must inspect actual gameplay state: " + pose_id)
		if pose_id == "free_hands":
			_check(player.left_support_arm.get("detailed_visual").is_visible_in_tree() and player.right_relaxed_arm.get("detailed_visual").is_visible_in_tree(), "unarmed gameplay must show both real detailed hands")
		elif pose_id == "bow_draw":
			var detailed := player._legacy_weapon_arm.get("detailed_visual") as Node3D
			var pose_before := _bone_poses(detailed.get("skeleton"))
			player._legacy_weapon_arm.set_string_draw(1.0, 1.0)
			_check(_bone_poses(detailed.get("skeleton")) != pose_before, "actual bow wrapper must forward finger release into detailed bones")
			player._update_character_arms()
		elif pose_id.begins_with("chest_"):
			for side in [-1, 1]:
				_check(player.chest_hands._arms[side].get("detailed_visual").is_visible_in_tree(), "actual timed chest interaction must display both detailed hands")
		var before := _gameplay_anchors(player)
		var bag_contents := PREVIEW.inventory_contents(fixture.inventory)
		player._update_character_arms()
		_check(_gameplay_anchors(player) == before and PREVIEW.inventory_contents(fixture.inventory) == bag_contents, "detailed updates must preserve combat geometry and bag: " + pose_id)
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory) == contents and Input.mouse_mode == cursor, "preview poses and cleanup must preserve original nested inventory, session and cursor")


func _test_room_lifecycle() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	var sword := original.get_equipment_instance("weapon")
	sword["uid"] = "detailed_original_sword"
	sword["smithing"] = {"quality": 0.83, "reinforcement": "silver", "runes": ["ember"], "drill_progress": 0.25}
	original.add_item("wooden_arrow", 11)
	ExpeditionSession.crowns = 519
	ExpeditionSession.hunger = 51.5
	ExpeditionSession.thirst = 42.25
	ExpeditionSession.stress = 37.0
	var contents := PREVIEW.inventory_contents(original)
	var snapshot := ExpeditionSession.capture_snapshot()
	var signals := [0]
	var observer := func() -> void: signals[0] += 1
	original.changed.connect(observer)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load("res://test_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_hands_detailed")
	_check(entries.size() == 1 and entries[0].action == "player_hands_detailed" and entries[0].category == "기본", "detailed requires one executable basic-category testroom entry")
	_check(sandbox.active and paused and room.panel_open and room.inventory != original and room.player.hands_visual_profile == "original", "testroom must begin isolated, paused and with the default player appearance")
	var previous_chest := 0
	for iteration in 2:
		room.run_feature("player_hands_detailed")
		var player := room.player as DungeonPlayer
		player.set_physics_process(false)
		await physics_frame
		await physics_frame
		var chest := room.arm_motion_chest as DungeonLootChest
		var bag := room.inventory as ExpeditionInventory
		_check(player.hands_detailed_enabled and not paused and not room.panel_open and is_instance_valid(chest) and not chest.opened, "detailed trial must resume actual gameplay and prepare a real closed chest")
		_check(chest.get_instance_id() != previous_chest, "reselecting detailed must create a fresh closed chest")
		previous_chest = chest.get_instance_id()
		_check(str(bag.equipment.get("weapon", "")).is_empty() and str(bag.equipment.get("offhand", "")).is_empty() and player.left_support_arm.is_visible_in_tree() and player.right_relaxed_arm.is_visible_in_tree(), "trial must really unequip carried weapons and expose both actual free hands: iteration %d weapon=%s offhand=%s left=%s right=%s support_root=%s stowed=%s torch=%s role=%s" % [iteration, bag.equipment.get("weapon", ""), bag.equipment.get("offhand", ""), player.left_support_arm.is_visible_in_tree(), player.right_relaxed_arm.is_visible_in_tree(), player.support_arm_root.visible, player.chest_equipment_stowed, player.torch_enabled, player._left_hand_role()])
		room._teleport(chest.position + Vector3(0.0, 1.0, 1.6))
		var direction := chest.to_global(Vector3(0.0, 0.77, -0.595)) - player.camera.global_position
		player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		player.head.rotation.x = player._pitch
		var bag_before := PREVIEW.inventory_contents(bag)
		chest.interact(player)
		player.advance_timed_interaction(chest.OPEN_DURATION * 0.55)
		_check(player.is_timed_interacting() and player.chest_equipment_stowed and player.chest_hands.phase == "fidget", "trial chest must invoke production timed opening and its actual contact phase")
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side < 0 else player.chest_hands.right_hand
			var contact := chest.get_hand_contact_transform(side, 0.55)
			_check(hand.global_position.distance_to(contact.origin) < 0.015 and player.chest_hands._arms[side].get("detailed_visual").is_visible_in_tree(), "both detailed hands must reach the real chest contact transforms")
		_check(PREVIEW.inventory_contents(bag) == bag_before, "chest hand animation must preserve selected inventory and metadata")
		await _press_f2()
		_check(paused and room.panel_open and not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "F2 must cancel detailed chest contact and return to paused menu")
		var hunger := ExpeditionSession.hunger
		await create_timer(0.03, true).timeout
		_check(is_equal_approx(ExpeditionSession.hunger, hunger), "detailed F2 menu must pause survival")
		_check(sandbox.saved_session == snapshot and PREVIEW.inventory_contents(original) == contents and signals[0] == 0, "repeated trials must never mutate or signal the original inventory")
	room.run_feature("player_arm_motion")
	_check(room.player.hands_visual_profile == "original", "selecting another feature must restore the original profile and clear both preview variants")
	await _press_f2()
	room.run_feature("player_hands_greybox")
	_check(room.player.hands_greybox_enabled and not room.player.hands_detailed_enabled, "the testroom greybox entry must remain independently executable after detailed trials")
	await _press_f2()
	room.run_feature("player_hands_detailed")
	var old_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != old_bag and room.player.hands_visual_profile == "original" and paused and room.panel_open and sandbox.saved_session == snapshot, "reset must restore the original profile and replace only the isolated test inventory")
	room.run_feature("player_hands_detailed")
	_check(room.player.hands_detailed_enabled and is_instance_valid(room.arm_motion_chest), "detailed trial must remain executable after reset")
	await _press_f2()
	room.leave_room()
	await _wait_for_main_menu()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and PREVIEW.inventory_contents(original) == contents, "exit must restore exact original inventory identity, nested metadata and expedition state")
	_check(original.changed.is_connected(observer), "original inventory signal connections must survive detailed trial lifecycle")
	original.changed.emit()
	_check(signals[0] == 1, "restored original inventory must still notify its existing observers")
	original.changed.disconnect(observer)


func _skin_samples(arm: Node3D, material_filter := "", mesh_filter := "") -> PackedVector3Array:
	var samples := PackedVector3Array()
	var skeleton := arm.get("skeleton") as Skeleton3D
	if skeleton == null: return samples
	for mesh in _meshes(arm):
		if mesh.skin == null: continue
		if not mesh_filter.is_empty() and str(mesh.name) != mesh_filter: continue
		var matrices: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
			if bone < 0: return PackedVector3Array()
			matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			if not material_filter.is_empty() and not mesh.get_active_material(surface).resource_name.begins_with(material_filter): continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or bones.is_empty() or bones.size() != weights.size(): continue
			var stride := bones.size() / vertices.size()
			for vertex in range(0, vertices.size(), maxi(1, vertices.size() / 256)):
				var point := Vector3.ZERO
				for slot in stride:
					var entry := vertex * stride + slot
					if weights[entry] > 0.0: point += (matrices[bones[entry]] * vertices[vertex]) * weights[entry]
				samples.append(mesh.to_global(point))
	return samples


func _triangle_count(node: Node) -> int:
	var result := 0
	for part in _meshes(node):
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			result += (indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return result


func _geometry_fingerprint(node: Node) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for part in _meshes(node):
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			hash.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
			hash.update((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	return hash.finish().hex_encode()


func _weighted_bone_names(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Array[String]:
	var result: Array[String] = []
	if mesh.skin == null: return result
	var names: Array[String] = []
	for bind in mesh.skin.get_bind_count():
		var bone := mesh.skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
		names.append(skeleton.get_bone_name(bone) if bone >= 0 else "missing")
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for entry in weights.size():
			if weights[entry] > 0.00001 and not result.has(names[bones[entry]]): result.append(names[bones[entry]])
	result.sort()
	return result


func _max_displacement(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty(): return INF
	var maximum := 0.0
	for index in a.size(): maximum = maxf(maximum, a[index].distance_to(b[index]))
	return maximum


func _bone_poses(skeleton: Skeleton3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result


func _transforms(parts: Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for part: Node3D in parts: result.append(part.global_transform)
	return result


func _legacy_state(wrappers: Array) -> Array:
	var result := []
	for wrapper: Node3D in wrappers:
		for mesh: MeshInstance3D in wrapper.get("arm_meshes") + wrapper.get("hand_meshes"):
			var materials: Array[Material] = []
			for surface in mesh.mesh.get_surface_count(): materials.append(mesh.get_active_material(surface))
			result.append([mesh, mesh.mesh, materials, mesh.visible])
	return result


func _gameplay_anchors(player: DungeonPlayer) -> Array[Transform3D]:
	return [player.sword_blade.global_transform, player.staff_muzzle.global_transform, player.weapon_pivot.global_transform, player.shield_pivot.global_transform, player.torch_pivot.global_transform]


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


func _wait_for_main_menu() -> void:
	var deadline := Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		var loading := false
		for child in root.get_children(): loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if is_instance_valid(current_scene) and current_scene.scene_file_path == "res://main_menu.tscn" and not loading:
			await process_frame
			return
		await process_frame
	_check(false, "detailed lifecycle timed out returning to main menu")


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
