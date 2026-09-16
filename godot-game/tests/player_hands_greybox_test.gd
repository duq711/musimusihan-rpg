extends SceneTree

const ARM := preload("res://scripts/greybox_arm_visual.gd")
const PREVIEW := preload("res://tests/player_hands_greybox_preview.gd")
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
	print("PLAYER HANDS GREYBOX %s: bilateral imported skin and handedness, real finger deformation, free/bow/chest gameplay, render layers, default fidelity and isolated F2/repeat/switch/reset/exit" % ("PASS" if failures.is_empty() else "FAIL"))
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
		_check(arm.setup(side), "greybox source must load for side " + str(side))
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
		var source_path := "res://assets/3d/player/hands_greybox/%s_hand_greybox.glb" % ("left" if side < 0 else "right")
		var source := (load(source_path) as PackedScene).instantiate()
		var source_meshes: Array[Mesh] = []
		for mesh in _meshes(source): source_meshes.append(mesh.mesh)
		var skinned_count := 0
		for mesh in _meshes(arm):
			_check(source_meshes.has(mesh.mesh), "greybox rendering must use the actual imported GLB geometry")
			_check(mesh.mesh.get_aabb().size.length() > 0.015, "greybox parts must have nonempty physical geometry")
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface) as BaseMaterial3D
				_check(material != null, "every greybox surface needs an actual material")
				if material == null: continue
				var color := material.albedo_color
				_check(maxf(color.r, maxf(color.g, color.b)) - minf(color.r, minf(color.g, color.b)) < 0.06 and material.albedo_texture == null and material.normal_texture == null and material.roughness_texture == null, "greybox must remain neutral grey without inherited color/normal/roughness textures")
				_check(material.roughness >= 0.75 and material.metallic < 0.1, "greybox material must be matte and nonmetallic")
			if mesh.skin != null:
				skinned_count += 1
				_check(mesh.skin.get_bind_count() == 16 and mesh.get_node_or_null(mesh.skeleton) == skeleton, "visible hand geometry must really bind to its sixteen-bone Skeleton3D")
		_check(skinned_count > 0 and arm.arm_meshes.size() >= 2, "each imported greybox requires a skinned hand plus both real arm segments")
		_check(arm.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual substitution must not add combat or interaction collisions")
		source.free()
		arm.reset_pose()
		var wrist := arm.global_transform
		var rest := _bone_poses(skeleton)
		var open_skin := _skin_samples(arm)
		_check(open_skin.size() >= 100, "deformation audit needs actual weighted source vertices")
		arm.set_finger_curl(0, -0.5, -0.8)
		_check(_bone_poses(skeleton) != rest and _max_displacement(open_skin, _skin_samples(arm)) > 0.005, "finger curl must move weighted rendered skin, not only a reported pose value")
		arm.reset_pose()
		_check(_bone_poses(skeleton) == rest and _max_displacement(open_skin, _skin_samples(arm)) < 0.00001, "reset must restore the imported open skin exactly")
		arm.set_grip(1.0)
		var grip_skin := _skin_samples(arm)
		_check(_max_displacement(open_skin, grip_skin) > 0.015, "full grip must deform the actual greybox finger surface")
		var segments_before := _transforms(arm.arm_meshes)
		arm.fit_arm(wrist.origin + wrist.basis * Vector3(float(side) * 0.11, 0.18, 0.55), wrist.origin + wrist.basis * Vector3(float(side) * 0.13, -0.04, 0.29))
		_check(_transforms(arm.arm_meshes) != segments_before and arm.global_transform.is_equal_approx(wrist), "arm fitting must move sleeve/forearm while preserving the wrist")
		_check(_max_displacement(grip_skin, _skin_samples(arm)) < 0.00001, "arm fitting must preserve the posed hand and equipment contact frame")
		arm.set_string_draw(1.0, 0.0)
		var hook := _skin_samples(arm)
		arm.set_string_draw(1.0, 1.0)
		_check(_max_displacement(hook, _skin_samples(arm)) > 0.01 and arm.global_transform.is_equal_approx(wrist), "bow release must open real greybox finger skin without moving its wrist")
		arm.set_relaxed_pose(0.0)
		var relaxed := _skin_samples(arm)
		arm.set_relaxed_pose(1.0)
		_check(_max_displacement(relaxed, _skin_samples(arm)) > 0.005, "free-hand openness must drive the real imported skeleton")
	stage.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == cursor, "standalone greybox assembly and skin checks must preserve session and cursor")


func _test_player_runtime_and_preview() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var contents := PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory)
	var cursor := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d, "greybox preview must isolate world, external input, picking and audio")
	_check(not player.hands_greybox_enabled and fixture.inventory != original.get("inventory"), "greybox must default off and QA must use a private inventory")
	await physics_frame
	await physics_frame
	var wrappers := [player._legacy_weapon_arm, player.torch_arm, player.left_support_arm, player.right_relaxed_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]
	var baseline := _legacy_state(wrappers)
	var bag_before := PREVIEW.inventory_contents(fixture.inventory)
	var anchors := _gameplay_anchors(player)
	_check(player.set_hands_greybox_enabled(true), "player-local opt-in must load both available greybox assets")
	_check(PREVIEW.inventory_contents(fixture.inventory) == bag_before and _gameplay_anchors(player) == anchors, "presentation toggle alone must preserve inventory, weapon hit/muzzle and equipment anchors")
	for wrapper: Node3D in wrappers:
		var greybox := wrapper.get("greybox_visual") as Node3D
		_check(greybox != null and greybox.visible, "every generic gameplay arm must connect to its actual greybox child")
		if greybox == null: continue
		var expected_layer := 1 if player.chest_hands.is_ancestor_of(wrapper) else EQUIPMENT_LAYER
		for mesh in _meshes(greybox): _check(mesh.layers == expected_layer, "late-created greybox must keep equipment layer20 or chest world layer1")
	_check(player.set_hands_greybox_enabled(false) and _legacy_state(wrappers) == baseline, "turning preview off must restore original mesh/material identities and visibility")
	for pose_id: String in PREVIEW.POSE_IDS:
		_check(PREVIEW.configure_pose(fixture, pose_id), "capture must configure actual gameplay: " + pose_id)
		_check(bool(PREVIEW.inspect_pose(fixture, pose_id).passed), "capture must inspect actual gameplay state: " + pose_id)
		if pose_id == "free_hands":
			_check(player.left_support_arm.get("greybox_visual").is_visible_in_tree() and player.right_relaxed_arm.get("greybox_visual").is_visible_in_tree(), "unarmed gameplay must show both real greybox hands")
		elif pose_id == "bow_draw":
			var greybox := player._legacy_weapon_arm.get("greybox_visual") as Node3D
			var pose_before := _bone_poses(greybox.get("skeleton"))
			player._legacy_weapon_arm.set_string_draw(1.0, 1.0)
			_check(_bone_poses(greybox.get("skeleton")) != pose_before, "actual bow wrapper must forward finger release into greybox bones")
			player._update_character_arms()
		elif pose_id.begins_with("chest_"):
			for side in [-1, 1]:
				_check(not player.chest_hands.is_visible_in_tree(), "Chest opening must keep its hand rig hidden.")
		var before := _gameplay_anchors(player)
		var bag_contents := PREVIEW.inventory_contents(fixture.inventory)
		player._update_character_arms()
		_check(_gameplay_anchors(player) == before and PREVIEW.inventory_contents(fixture.inventory) == bag_contents, "greybox updates must preserve combat geometry and bag: " + pose_id)
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and PREVIEW.inventory_contents(original.get("inventory") as ExpeditionInventory) == contents and Input.mouse_mode == cursor, "preview poses and cleanup must preserve original nested inventory, session and cursor")


func _test_room_lifecycle() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	var sword := original.get_equipment_instance("weapon")
	sword["uid"] = "greybox_original_sword"
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
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_hands_greybox")
	_check(entries.size() == 1 and entries[0].action == "player_hands_greybox" and entries[0].category == "기본", "greybox requires one executable basic-category testroom entry")
	_check(sandbox.active and paused and room.panel_open and room.inventory != original and not room.player.hands_greybox_enabled, "testroom must begin isolated, paused and with the default player appearance")
	var previous_chest := 0
	for iteration in 2:
		room.run_feature("player_hands_greybox")
		var player := room.player as DungeonPlayer
		player.set_physics_process(false)
		await physics_frame
		await physics_frame
		var chest := room.arm_motion_chest as DungeonLootChest
		var bag := room.inventory as ExpeditionInventory
		_check(player.hands_greybox_enabled and not paused and not room.panel_open and is_instance_valid(chest) and not chest.opened, "greybox trial must resume actual gameplay and prepare a real closed chest")
		_check(chest.get_instance_id() != previous_chest, "reselecting greybox must create a fresh closed chest")
		previous_chest = chest.get_instance_id()
		_check(str(bag.equipment.get("weapon", "")).is_empty() and str(bag.equipment.get("offhand", "")).is_empty() and player.left_support_arm.is_visible_in_tree() and player.right_relaxed_arm.is_visible_in_tree(), "trial must really unequip carried weapons and expose both actual free hands: iteration %d weapon=%s offhand=%s left=%s right=%s support_root=%s stowed=%s torch=%s role=%s" % [iteration, bag.equipment.get("weapon", ""), bag.equipment.get("offhand", ""), player.left_support_arm.is_visible_in_tree(), player.right_relaxed_arm.is_visible_in_tree(), player.support_arm_root.visible, player.chest_equipment_stowed, player.torch_enabled, player._left_hand_role()])
		room._teleport(chest.position + Vector3(0.0, 1.0, 1.6))
		var direction := chest.to_global(Vector3(0.0, 0.77, -0.595)) - player.camera.global_position
		player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		player.head.rotation.x = player._pitch
		var bag_before := PREVIEW.inventory_contents(bag)
		chest.interact(player)
		player.advance_timed_interaction(chest.OPEN_DURATION * 0.55)
		_check(player.is_timed_interacting() and player.chest_equipment_stowed and not player.chest_hands.active and not player.chest_hands.visible, "trial chest must invoke production timed opening and its actual contact phase")
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side < 0 else player.chest_hands.right_hand
			var contact := chest.get_hand_contact_transform(side, 0.55)
			_check(not hand.is_visible_in_tree(), "Chest opening must not display a reaching or gripping hand.")
		_check(PREVIEW.inventory_contents(bag) == bag_before, "chest hand animation must preserve selected inventory and metadata")
		await _press_f2()
		_check(paused and room.panel_open and not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "F2 must cancel greybox chest contact and return to paused menu")
		var hunger := ExpeditionSession.hunger
		await create_timer(0.03, true).timeout
		_check(is_equal_approx(ExpeditionSession.hunger, hunger), "greybox F2 menu must pause survival")
		_check(sandbox.saved_session == snapshot and PREVIEW.inventory_contents(original) == contents and signals[0] == 0, "repeated trials must never mutate or signal the original inventory")
	room.run_feature("player_arm_motion")
	_check(not room.player.hands_greybox_enabled, "selecting another feature must clear greybox preview")
	await _press_f2()
	room.run_feature("player_hands_greybox")
	var old_bag: ExpeditionInventory = room.inventory
	room.reset_room()
	_check(room.inventory != old_bag and not room.player.hands_greybox_enabled and paused and room.panel_open and sandbox.saved_session == snapshot, "reset must clear greybox and replace only the isolated test inventory")
	room.run_feature("player_hands_greybox")
	_check(room.player.hands_greybox_enabled and is_instance_valid(room.arm_motion_chest), "greybox trial must remain executable after reset")
	await _press_f2()
	room.leave_room()
	await _wait_for_main_menu()
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and PREVIEW.inventory_contents(original) == contents, "exit must restore exact original inventory identity, nested metadata and expedition state")
	_check(original.changed.is_connected(observer), "original inventory signal connections must survive greybox trial lifecycle")
	original.changed.emit()
	_check(signals[0] == 1, "restored original inventory must still notify its existing observers")
	original.changed.disconnect(observer)


func _skin_samples(arm: Node3D) -> PackedVector3Array:
	var samples := PackedVector3Array()
	var skeleton := arm.get("skeleton") as Skeleton3D
	if skeleton == null: return samples
	for mesh in _meshes(arm):
		if mesh.skin == null: continue
		var matrices: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(str(mesh.skin.get_bind_name(bind)))
			if bone < 0: return PackedVector3Array()
			matrices.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
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
	_check(false, "greybox lifecycle timed out returning to main menu")


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
