extends SceneTree

const ARM := preload("res://scripts/player_arm_visual.gd")
const STATIC_GRIP := preload("res://tests/sword_long_grip_test.gd")
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const ROOM_PATH := "res://test_room.tscn"
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_shared_geometry_and_joints()
	await _test_actual_preview_poses()
	await _test_trial_roundtrip()
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("PLAYER ARM PASS: supplied default hand GLB/texture fidelity, real skinned grip and wrist-preserving arm fit, actual combat/bow/chest preview paths, trial hits and contacts, F2/repeat/reset and expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _test_shared_geometry_and_joints() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var mouse_before := Input.mouse_mode
	var stage := Node3D.new()
	root.add_child(stage)
	stage.position = Vector3(2.0, 0.6, -1.0)
	stage.rotation.y = 0.37
	for side in [-1, 1]:
		var path := "res://assets/3d/player/hands_detailed/%s_hand_detailed.glb" % ("left" if side < 0 else "right")
		var source := (load(path) as PackedScene).instantiate() as Node3D
		var imported_meshes: Array[Mesh] = []
		for part in _meshes(source): imported_meshes.append(part.mesh)
		var rig: Node3D = ARM.new()
		stage.add_child(rig)
		rig.setup(side)
		rig.position = Vector3(float(side) * 0.35, 1.0, -0.4)
		rig.rotation = Vector3(-0.25, 0.15, float(side) * 0.4)
		var wrist_before := rig.global_transform
		var parent_before := stage.global_transform
		var adapter := rig.get("detailed_visual") as Node3D
		_check(adapter != null and adapter.is_visible_in_tree() and rig.visual_profile == "original" and not rig.detailed_enabled, "the logical default must immediately render the supplied rig without requiring the detailed review toggle")
		if adapter == null:
			source.free()
			continue
		_check(str(rig.get_meta("source_model", "")) == path and rig.get_meta("supplied_hand", false), "default hand provenance must identify its actual supplied left/right GLB")
		var source_refs: Array = rig.get_source_meshes()
		var parts := _meshes(rig)
		_check(parts.size() == source_refs.size() and source_refs.size() == imported_meshes.size(), "default arms must contain exactly their imported supplied mesh parts")
		for part in parts:
			var rendered_source: Mesh = adapter.get("_wrist_cuff_deformer").call("source_mesh_for", part)
			_check(imported_meshes.has(rendered_source) and source_refs.has(rendered_source), "every default rendered part must come from the actual supplied GLB")
			if part.mesh != rendered_source:
				_check(str(part.name).begins_with("WristCuff") and part.skin == null, "only the authored cuff may own a private deforming mesh copy")
			_check(not str(part.name).begins_with("Gravebound_Finger"), "retired body glove/capsule pieces must not be instantiated behind the supplied hands")
			for surface in part.mesh.get_surface_count():
				var material := part.get_active_material(surface) as BaseMaterial3D
				_check(material == part.mesh.surface_get_material(surface) and material != null and material.albedo_texture != null and material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "default supplied surfaces must retain their imported lit texture materials")
		_check(rig.find_children("*", "CollisionObject3D", true, false).is_empty(), "supplied visuals must not add combat or interaction collisions")
		var skeleton := adapter.get("skeleton") as Skeleton3D
		_check(skeleton != null and skeleton.get_bone_count() == 16, "default supplied hands must use the actual wrist and fifteen finger bones")
		if skeleton == null:
			source.free()
			continue
		for digit: String in ["thumb", "index", "middle", "ring", "little"]:
			var parent := skeleton.find_bone("wrist")
			for joint in 3:
				var bone := skeleton.find_bone(digit + str(joint))
				_check(bone >= 0 and skeleton.get_bone_parent(bone) == parent, "each supplied digit must preserve its three actual linked bones: " + digit)
				parent = bone
		rig.reset_pose()
		var open_points := _skin_points(rig)
		var open_joints := _joint_transforms(rig)
		_check(open_points.size() > 100, "default deformation evidence requires actual weighted supplied vertices")
		rig.set_grip(1.0)
		_check(_joint_transforms(rig) != open_joints and _max_displacement(open_points, _skin_points(rig)) > 0.005, "default gripping must bend real supplied skin through its skeleton")
		_check(rig.global_transform.is_equal_approx(wrist_before) and stage.global_transform.is_equal_approx(parent_before), "grip animation must preserve wrist and parent equipment frames")
		var held_points := _skin_points(rig)
		var arm_before := _part_transforms(rig.arm_meshes)
		var shoulder := wrist_before.origin + wrist_before.basis * Vector3(float(side) * 0.12, 0.18, 0.56)
		var elbow := wrist_before.origin + wrist_before.basis * Vector3(float(side) * 0.16, -0.05, 0.28)
		rig.fit_arm(shoulder, elbow)
		_check(_part_transforms(rig.arm_meshes) != arm_before, "fitting an arm must move its actual sleeve and forearm meshes")
		_check(_max_displacement(held_points, _skin_points(rig)) < 0.00001 and rig.global_transform.is_equal_approx(wrist_before) and stage.global_transform.is_equal_approx(parent_before), "shoulder and elbow fitting must preserve supplied skin, wrist and carried weapon")
		_check(rig.get_source_meshes() == source_refs, "posing must retain imported source resources")
		rig.set_arm_visible(false)
		for part: MeshInstance3D in rig.arm_meshes: _check(not part.visible, "arm stowing must hide sleeve and cuff geometry")
		for part: MeshInstance3D in rig.hand_meshes: _check(part.visible, "arm-only hiding must preserve supplied hand and nail visibility")
		rig.set_arm_visible(true)
		rig.reset_pose()
		_check(_joint_transforms(rig) == open_joints and _max_displacement(open_points, _skin_points(rig)) < 0.00001 and rig.global_transform.is_equal_approx(wrist_before), "reset must restore supplied finger bones and weighted surface without moving the wrist")
		rig.set_finger_curl(0, -0.35, -0.60)
		_check(_joint_transforms(rig) != open_joints and _max_displacement(open_points, _skin_points(rig)) > 0.001, "an individual curl must affect the actual supplied surface")
		rig.set_string_draw(1.0, 0.0)
		var hooked := _skin_points(rig)
		rig.set_string_draw(1.0, 1.0)
		_check(_max_displacement(hooked, _skin_points(rig)) > 0.005 and rig.global_transform.is_equal_approx(wrist_before), "bow release must open the supplied fingers while preserving the nock wrist frame")
		rig.set_relaxed_pose(0.0)
		var relaxed := _skin_points(rig)
		rig.set_relaxed_pose(1.0)
		_check(_max_displacement(relaxed, _skin_points(rig)) > 0.001 and rig.get_source_meshes() == source_refs, "relaxed and assisting palms must animate the supplied resources")
		# The default and explicit detailed review refer to the same instance;
		# returning from greybox must restore the new hands, never old capsules.
		rig.set_render_layers(1 << 19)
		_check(rig.set_visual_profile("detailed") and rig.detailed_visual == adapter and rig.detailed_enabled and rig.get_source_meshes() == source_refs, "detailed review must reuse the current production hand without overlaying a duplicate")
		_check(rig.set_visual_profile("greybox") and rig.greybox_visual.visible and not adapter.visible, "greybox comparison must remain independently selectable")
		_check(rig.hand_meshes == rig.greybox_visual.hand_meshes and rig.arm_meshes == rig.greybox_visual.arm_meshes, "public mesh arrays must track the actual selected comparison")
		_check(rig.set_visual_profile("original") and rig.detailed_visual == adapter and adapter.visible and not rig.greybox_visual.visible and rig.get_source_meshes() == source_refs, "original profile restoration must show the same supplied production hands")
		for part: MeshInstance3D in rig.hand_meshes + rig.arm_meshes: _check(part.layers == 1 << 19, "profile switches must preserve actual viewmodel render layers")
		_check(not rig.set_visual_profile("unknown") and rig.visual_profile == "original" and rig.get_source_meshes() == source_refs, "invalid profile requests must preserve the real supplied hand selection")
		var adapter_instance_id := adapter.get_instance_id()
		rig.setup(side)
		_check(rig.visual_profile == "original" and rig.detailed_visual.get_instance_id() != adapter_instance_id and rig.get_source_meshes() == source_refs and rig.global_transform.is_equal_approx(wrist_before), "repeated setup must replace owned nodes once and preserve actual source resources and wrist")
		for part: MeshInstance3D in rig.hand_meshes + rig.arm_meshes: _check(part.layers == 1 << 19, "rebuilding supplied arm nodes must preserve the renderer-assigned layer")
		source.free()
	stage.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_before, "default arm construction and poses must preserve expedition and cursor state")


func _test_actual_preview_poses() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var original_inventory := original.get("inventory") as ExpeditionInventory
	var mouse_before := Input.mouse_mode
	var viewport: SubViewport = PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture: Dictionary = PREVIEW.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and fixture.inventory != original_inventory, "visual QA must use an isolated rendering world and private inventory without input")
	await physics_frame
	await physics_frame
	var idle_weapon := Transform3D.IDENTITY
	var idle_shield := Transform3D.IDENTITY
	for pose_id: String in PREVIEW.POSE_IDS:
		_check(PREVIEW.configure_pose(fixture, pose_id), "preview must configure the actual production pose: " + pose_id)
		var inspection: Dictionary = PREVIEW.inspect_pose(fixture, pose_id)
		_check(inspection.passed, "preview must verify its real gameplay state: " + pose_id)
		if pose_id == "idle":
			idle_weapon = player.weapon_arm.global_transform
			idle_shield = player.shield_arm.global_transform
		elif pose_id in ["sword_windup", "sword_active", "bow_draw"]:
			_check(not player.weapon_arm.global_transform.is_equal_approx(idle_weapon), "actual weapon poses must carry the shared arm with the real grip: " + pose_id)
		elif pose_id == "shield_guard":
			_check(not player.shield_arm.global_transform.is_equal_approx(idle_shield), "guarding must move the actual shared shield arm")
		elif pose_id.begins_with("chest_"):
			_check(player.chest_hands._arms[-1].is_visible_in_tree() and player.chest_hands._arms[1].is_visible_in_tree(), "actual chest preview must display both shared arms")
		if pose_id in ["idle", "sword_windup", "sword_active", "shield_guard"]:
			failures.append_array(STATIC_GRIP.audit_static_arm(player.weapon_arm))
			failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
		elif pose_id == "bow_draw":
			_check(player.weapon_arm == player._legacy_weapon_arm and not player._sword_weapon_arm.visible, "bow must restore the articulated arm and hide the imported sword grip")
		var anchors := [player.sword_blade.global_transform, player.staff_muzzle.global_transform, player.weapon_pivot.global_transform, player.shield_pivot.global_transform, player.torch_pivot.global_transform]
		var before_pose := ExpeditionSession.capture_snapshot()
		player._update_character_arms()
		_check(anchors == [player.sword_blade.global_transform, player.staff_muzzle.global_transform, player.weapon_pivot.global_transform, player.shield_pivot.global_transform, player.torch_pivot.global_transform], "updating arms must preserve real hit geometry, muzzle and all equipment pivots: " + pose_id)
		_check(ExpeditionSession.capture_snapshot() == before_pose, "presentation posing must not consume expedition resources: " + pose_id)
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == mouse_before, "preview construction, real pose paths and cleanup must preserve original expedition and cursor")


func _test_trial_roundtrip() -> void:
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("wooden_arrow", 9)
	ExpeditionSession.crowns = 619
	ExpeditionSession.hunger = 54.0
	ExpeditionSession.thirst = 39.0
	ExpeditionSession.stress = 34.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var slots_original := original.slots.duplicate(true)
	var sandbox := root.get_node("TestRoomSandbox")
	var room := (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	var bag: ExpeditionInventory = room.inventory
	var entries: Array = room.feature_entries.filter(func(entry: Dictionary) -> bool: return entry.id == "player_arm_motion")
	_check(entries.size() == 1 and entries[0].action == "player_arm_motion" and entries[0].category == "기본", "shared arms need one executable test-room feature")
	_check(sandbox.active and bag != original and room.panel_open and paused, "arm fixture must begin in the isolated paused test room")
	var previous_target := 0
	var previous_chest := 0
	for iteration in range(2):
		if iteration == 1:
			_check(_equip(bag, "hunting_bow"), "repeat fixture must allow keeping a player-selected bow")
		var slots := bag.slots.duplicate(true)
		var equipment := bag.equipment.duplicate(true)
		room.run_feature("player_arm_motion")
		room.player.set_physics_process(false)
		await physics_frame
		await physics_frame
		var player: DungeonPlayer = room.player
		var target: DungeonEnemy = room.arm_motion_target
		var chest: DungeonLootChest = room.arm_motion_chest
		_check(not paused and not room.panel_open and room.enemies_alive == 1 and not room.enemy_ai_enabled and is_instance_valid(target) and is_instance_valid(chest), "arm trial must resume real play with a stationary target and a real chest")
		_check(player.global_position.distance_to(target.global_position) < 2.1 and not chest.opened and player.global_position.distance_to(chest.global_position) < 3.0, "trial must place actual attack and chest targets within a short movement distance")
		_check(target.get_instance_id() != previous_target and chest.get_instance_id() != previous_chest, "reselection must prepare fresh targets and a closed chest")
		previous_target = target.get_instance_id()
		previous_chest = chest.get_instance_id()
		_check(bag.slots == slots and bag.equipment == equipment and player.health == 100.0 and player.stamina == 100.0, "fixture must preserve selected equipment and bag while restoring health and stamina")
		_check(_equip(bag, "rusted_sword"), "actual inventory must equip the sword for the melee check")
		var target_health := target.health
		var stamina := player.stamina
		player._try_begin_attack()
		player._update_viewmodel(1.0)
		player._commit_attack()
		player._update_viewmodel(1.0)
		player.state_time = player.get_melee_hit_time() - 0.001
		player._resolve_active_attack()
		_check(is_equal_approx(target.health, target_health) and is_equal_approx(player.stamina, stamina - 18.0), "actual equipped melee profile must charge once at commit and wait for its own hit checkpoint")
		player.state_time = player.get_melee_hit_time() + 0.01
		player._update_viewmodel(1.0)
		player._resolve_active_attack()
		_check(target.health < target_health and is_equal_approx(player.stamina, stamina - 18.0), "shared-arm attack must use actual melee damage and the ordinary single stamina cost")
		var health_after_hit := target.health
		player._resolve_active_attack()
		_check(is_equal_approx(target.health, health_after_hit) and is_equal_approx(player.stamina, stamina - 18.0), "repeated resolution of the same visible swing must not duplicate damage or stamina cost")
		room._teleport(chest.position + Vector3(0.0, 1.0, 1.6))
		var direction := chest.to_global(Vector3(0.0, 0.77, -0.595)) - player.camera.global_position
		player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
		player.head.rotation.x = player._pitch
		var chest_slots := bag.slots.duplicate(true)
		var chest_equipment := bag.equipment.duplicate(true)
		chest.interact(player)
		player.advance_timed_interaction(chest.OPEN_DURATION * 0.55)
		_check(player.is_timed_interacting() and player.chest_hands.phase == "fidget" and player.chest_equipment_stowed, "trial chest must invoke real timed contact animation and stow carried equipment")
		for side in [-1, 1]:
			var hand: Node3D = player.chest_hands.left_hand if side == -1 else player.chest_hands.right_hand
			var contact := chest.get_hand_contact_transform(side, 0.55)
			_check(hand.global_position.distance_to(contact.origin) < 0.015, "shared trial hands must touch the actual chest surface")
		_check(bag.slots == chest_slots and bag.equipment == chest_equipment, "chest arm presentation must not unequip or consume items")
		await _press_f2()
		_check(room.panel_open and paused and not player.is_timed_interacting() and not player.chest_hands.active and not player.chest_equipment_stowed, "F2 during arm contact must cancel it and restore the paused trial menu")
		var paused_hunger := ExpeditionSession.hunger
		await create_timer(0.03, true).timeout
		_check(is_equal_approx(ExpeditionSession.hunger, paused_hunger), "arm trial menu must pause survival")
		_check(sandbox.saved_session == snapshot and original.slots == slots_original, "actual trial attacks, hand contacts and repetitions must preserve the saved original expedition")
	room.reset_room()
	_check(room.inventory != bag and room.panel_open and paused and sandbox.saved_session == snapshot, "arm trial reset must replace only the isolated loadout")
	room.run_feature("player_arm_motion")
	_check(is_instance_valid(room.arm_motion_target) and is_instance_valid(room.arm_motion_chest), "arm fixture must remain executable after reset")
	await _press_f2()
	room.leave_room()
	await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot and original.slots == slots_original, "leaving arm trials must restore original inventory identity and every expedition value")


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_meshes(child))
	return result


func _part_transforms(parts: Array) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	for part: Node3D in parts:
		result.append(part.global_transform)
	return result


func _joint_transforms(rig: Node3D) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var adapter := rig.get("_active_visual") as Node3D
	var skeleton := adapter.get("skeleton") as Skeleton3D if adapter != null else null
	if skeleton != null:
		for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result


func _skin_points(rig: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var adapter := rig.get("_active_visual") as Node3D
	var skeleton := adapter.get("skeleton") as Skeleton3D if adapter != null else null
	if skeleton == null: return result
	for part: MeshInstance3D in rig.hand_meshes:
		if part.skin == null: continue
		var matrices: Array[Transform3D] = []
		for bind in part.skin.get_bind_count():
			var bone := part.skin.get_bind_bone(bind)
			if bone < 0: bone = skeleton.find_bone(str(part.skin.get_bind_name(bind)))
			if bone < 0: return PackedVector3Array()
			matrices.append(skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(bind))
		var active: Array[int] = []
		for shape in part.get_blend_shape_count():
			if absf(part.get_blend_shape_value(shape)) > 0.000001: active.append(shape)
		for surface in part.mesh.get_surface_count():
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var shapes := part.mesh.surface_get_blend_shape_arrays(surface)
			if vertices.is_empty() or bones.is_empty(): continue
			var stride := bones.size() / vertices.size()
			for index in range(0, vertices.size(), maxi(1, vertices.size() / 512)):
				var point := vertices[index]
				for shape in active:
					var target: Vector3 = shapes[shape][Mesh.ARRAY_VERTEX][index]
					point += (target - vertices[index] if (part.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_NORMALIZED else target) * part.get_blend_shape_value(shape)
				var posed := Vector3.ZERO
				for slot in stride:
					var entry := index * stride + slot
					if weights[entry] > 0.0: posed += matrices[bones[entry]] * point * weights[entry]
				result.append(part.to_global(posed))
	return result


func _max_displacement(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.is_empty() or a.size() != b.size(): return INF
	var result := 0.0
	for index in a.size(): result = maxf(result, a[index].distance_to(b[index]))
	return result


func _equip(inventory: ExpeditionInventory, id: String) -> bool:
	if inventory.equipment.get("weapon") == id:
		return true
	for index in inventory.slots.size():
		if inventory.slots[index].id == id:
			return bool(inventory.equip_from_slot(index).get("accepted", false))
	return false


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
	_check(false, "arm trial scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
