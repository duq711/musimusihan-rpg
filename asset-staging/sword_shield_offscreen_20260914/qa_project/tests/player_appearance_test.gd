extends SceneTree

const ROOM_PATH := "res://test_room.tscn"
const MODEL_PATH := "res://assets/3d/player/gravebound_player.glb"
const BODY_LAYER := 1 << 17
const APPEARANCE := preload("res://scripts/player_appearance.gd")
const LEGACY_ARM_PATH := "res://scripts/player_arm_visual.gd"
const SKINNED_ARM_PATH := "res://scripts/sword_shield_arm_visual.gd"
const HAND_MODEL_ROOT := "res://assets/3d/player/sword_shield/"
const STATIC_GRIP := preload("res://tests/sword_long_grip_test.gd")
var failures: Array[String] = []
var sandbox: Node
var _anatomical_mesh_sources: Dictionary = {}
var _supplied_mesh_sources: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
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
	_check(portrait.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "opening inventory must enable actual portrait rendering")
	_check((player.camera.cull_mask & BODY_LAYER) == 0 and (portrait.camera.cull_mask & BODY_LAYER) != 0, "first-person view must exclude the full body while the portrait can see it")
	_check((player.viewmodel_renderer.camera.cull_mask & BODY_LAYER) == 0, "the full body must not leak into the carried-equipment rendering")
	var body_meshes := _meshes(body)
	var portrait_meshes := _meshes(portrait.body)
	_check(body.find_children("*", "Sprite3D", true, false).is_empty() and portrait.body.find_children("*", "Sprite3D", true, false).is_empty(), "the character must use actual volumetric meshes without image billboards")
	_check(not body_meshes.is_empty() and body_meshes.size() == portrait_meshes.size(), "world body and portrait must contain the same non-empty imported 3D geometry")
	_check(_contains_import(body) and _contains_import(portrait.body), "both presentations must instantiate the actual gravebound player GLB")
	if body_meshes.size() == portrait_meshes.size():
		for index in range(body_meshes.size()):
			var world_mesh: MeshInstance3D = body_meshes[index]
			var portrait_mesh: MeshInstance3D = portrait_meshes[index]
			_check(world_mesh.mesh == portrait_mesh.mesh and world_mesh.material_override == portrait_mesh.material_override, "portrait and world body must share geometry and material resources: " + str(world_mesh.name))
			_check(world_mesh.layers == BODY_LAYER and portrait_mesh.layers == BODY_LAYER and world_mesh.visible and portrait_mesh.visible, "every body mesh must use the dedicated visible character layer: " + str(world_mesh.name))
			_check(world_mesh.mesh != null and world_mesh.mesh.get_surface_count() > 0, "body parts must have real mesh surfaces: " + str(world_mesh.name))
			for surface_index in range(world_mesh.mesh.get_surface_count()):
				var material := world_mesh.mesh.surface_get_material(surface_index) as BaseMaterial3D
				_check(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not material.emission_enabled, "character surfaces must respond to real scene lighting instead of displaying unlit concept art")
	_inspect_supplied_body_hands(body_meshes)
	_inspect_supplied_body_hands(portrait_meshes)
	# This checks the real imported mesh bounds, not a synthetic success flag.
	var bounds := _body_bounds(body, body_meshes)
	_check(bounds.size.y > 1.72 and bounds.size.y < 1.84 and bounds.size.x > 0.4 and bounds.size.x < 0.9 and bounds.size.z > 0.2 and bounds.size.z < 0.65, "the actual model must fit human proportions and the player capsule without oversized primitive parts")
	_check(absf(bounds.position.y) < 0.02, "the actual model feet must meet the shared local ground origin")
	_inspect_first_person_materials(player)
	await process_frame


func _inspect_supplied_body_hands(parts: Array[MeshInstance3D]) -> void:
	var supplied_hands := {}
	var supplied_nails := {}
	var retained_count := 0
	for part in parts:
		var name := str(part.name)
		_check(not name.begins_with("Gravebound_Finger_") and not name.begins_with("Gravebound_FingerlessGlove_"), "the shipped full character must physically remove the old capsule fingers and glove hands")
		if name.begins_with("Gravebound_SuppliedHand_"):
			supplied_hands[name] = part
		elif name.begins_with("Gravebound_SuppliedNail_"):
			supplied_nails[name] = part
		else:
			retained_count += 1
	_check(supplied_hands.size() == 2 and supplied_nails.size() == 10 and retained_count == 28, "world body and inventory portrait must include both supplied hands and their ten nails while retaining the other 28 body parts")
	for suffix: String in ["L", "R"]:
		var hand_name := "Gravebound_SuppliedHand_" + suffix
		_check(supplied_hands.has(hand_name), "the full body needs its actual supplied hand: " + hand_name)
		if supplied_hands.has(hand_name):
			var hand: MeshInstance3D = supplied_hands[hand_name]
			var vertex_count := 0
			for surface in hand.mesh.get_surface_count():
				var arrays := hand.mesh.surface_get_arrays(surface)
				vertex_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				var material := hand.get_active_material(surface) as BaseMaterial3D
				_check(material != null and material.resource_name.begins_with("Supplied_Skin") and material.albedo_texture != null and material.normal_enabled and material.normal_texture != null, "static supplied hands must carry their actual imported skin color and detail maps")
			_check(vertex_count > 1000, "the supplied full-body hand must contain real anatomical geometry beyond the retired capsule pieces")
		for digit: String in ["thumb", "index", "middle", "ring", "little"]:
			var nail_name := "Gravebound_SuppliedNail_" + suffix + "_" + digit
			_check(supplied_nails.has(nail_name), "the full body needs its actual supplied nail: " + nail_name)


func _inspect_first_person_materials(player: DungeonPlayer) -> void:
	# The current melee hand is an independently supplied static pose; the
	# shield retains its distinct articulated source and contact solver.
	_check(player.weapon_arm == (player._sword_weapon_arm if player._equipped_weapon_type() == "melee" else player._legacy_weapon_arm), "weapon selection must retain the actual static melee hand and supplied generic hand roles")
	failures.append_array(STATIC_GRIP.audit_static_arm(player._sword_weapon_arm))
	failures.append_array(STATIC_GRIP.audit_source_fidelity(player))
	_inspect_skinned_arm(player.shield_arm, -1)
	var rigs: Array[Node3D] = [player._legacy_weapon_arm, player.torch_arm, player.left_support_arm, player.right_relaxed_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]
	for rig in rigs:
		var correct_rig: bool = is_instance_valid(rig) and rig.get_script() != null and rig.get_script().resource_path == LEGACY_ARM_PATH
		_check(correct_rig, "generic weapons, torch, support and chest hands must use the production supplied-hand wrapper")
		if not correct_rig: continue
		var adapter := rig.get("_active_visual") as Node3D
		_check(adapter != null and adapter == rig.get("detailed_visual") and rig.visual_profile == "original" and adapter.visible, "the normal player appearance must show the supplied hand without enabling the art-review profile")
		if adapter == null: continue
		var side := int(rig.get_meta("anatomical_side", 0))
		var path := "res://assets/3d/player/hands_detailed/%s_hand_detailed.glb" % ("left" if side < 0 else "right")
		_check(str(rig.get_meta("source_model", "")) == path and _contains_import(rig, path), "default hands must instantiate the actual supplied left/right GLB")
		if not _supplied_mesh_sources.has(side):
			var source := (load(path) as PackedScene).instantiate()
			var imported: Array[Mesh] = []
			for part in _meshes(source): imported.append(part.mesh)
			_supplied_mesh_sources[side] = imported
			source.free()
		var imported: Array = _supplied_mesh_sources[side]
		var declared_sources: Array = rig.get_source_meshes()
		var rendered_parts: Array[MeshInstance3D] = []
		rendered_parts.assign(rig.arm_meshes)
		rendered_parts.append_array(rig.hand_meshes)
		_check(rendered_parts.size() == imported.size() and declared_sources.size() == imported.size(), "the default wrapper must expose all actual supplied arm/hand parts")
		var skeleton := adapter.get("skeleton") as Skeleton3D
		_check(skeleton != null and skeleton.get_bone_count() == 16 and bool(rig.get_joint_snapshot().corrective_available), "default supplied hands must retain real finger bones and usable joint correctives")
		if skeleton == null: continue
		for digit: String in ["thumb", "index", "middle", "ring", "little"]:
			var parent := skeleton.find_bone("wrist")
			for joint in 3:
				var bone := skeleton.find_bone(digit + str(joint))
				_check(bone >= 0 and skeleton.get_bone_parent(bone) == parent, "default supplied digits must have three genuine linked bones: " + digit)
				parent = bone
		var skin_surfaces := 0
		var nail_surfaces := 0
		for part in rendered_parts:
			var source_mesh: Mesh = adapter.get("_wrist_cuff_deformer").call("source_mesh_for", part)
			_check(imported.has(source_mesh) and declared_sources.has(source_mesh), "default surfaces must retain their actual imported supplied mesh resource")
			if part.mesh != source_mesh: _check(str(part.name).begins_with("WristCuff") and part.skin == null, "only the actual flexible cuff may own a runtime mesh copy")
			if part.skin != null: _check(part.get_node_or_null(part.skeleton) == skeleton and part.skin.get_bind_count() == 16, "supplied hand and nail surfaces must resolve their actual sixteen-bone skin binding")
			for surface in part.mesh.get_surface_count():
				var source_material := part.mesh.surface_get_material(surface) as BaseMaterial3D
				var actual := part.get_active_material(surface) as BaseMaterial3D
				_check(actual == source_material and actual != null and actual.albedo_texture != null and actual.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not actual.emission_enabled, "default supplied surfaces must use their real imported lit material resources")
				if actual != null:
					if actual.resource_name.begins_with("Supplied_Skin"): skin_surfaces += 1
					if actual.resource_name.begins_with("Supplied_Nail"): nail_surfaces += 1
		_check(skin_surfaces > 0 and nail_surfaces >= 5, "each default hand must render supplied anatomical skin and all five actual nails")


func _inspect_skinned_arm(arm: Node3D, side: int) -> void:
	var correct_rig: bool = is_instance_valid(arm) and arm.get_script() != null and arm.get_script().resource_path == SKINNED_ARM_PATH
	_check(correct_rig, "sword and shield must use their actual dedicated anatomical arm implementation")
	if not correct_rig: return
	var model_path := HAND_MODEL_ROOT + ("left_arm.glb" if side < 0 else "right_arm.glb")
	_check(_contains_import(arm, model_path), "each equipment hand must instantiate the correct left/right source GLB")
	if not _anatomical_mesh_sources.has(side):
		var source := (load(model_path) as PackedScene).instantiate() as Node3D
		var source_meshes: Array[Mesh] = []
		for part in _meshes(source): source_meshes.append(part.mesh)
		_anatomical_mesh_sources[side] = source_meshes
		source.free()
	var imported_meshes: Array = _anatomical_mesh_sources[side]
	var declared_sources: Array = arm.get_source_meshes()
	var rendered_parts := _meshes(arm)
	_check(not rendered_parts.is_empty() and declared_sources.size() == rendered_parts.size() and imported_meshes.size() == rendered_parts.size(), "anatomical arms must render all actual source meshes, including their original fingerless glove")
	_check(arm.find_children("*", "Sprite3D", true, false).is_empty() and arm.find_children("*", "CollisionObject3D", true, false).is_empty(), "anatomical appearance must use real mesh surfaces without image planes or extra combat collisions")
	var skeleton := arm.get("skeleton") as Skeleton3D
	_check(skeleton != null and skeleton.get_bone_count() == 16, "anatomical hands require the actual wrist plus fifteen deforming finger bones")
	if skeleton == null or skeleton.get_bone_count() != 16: return
	var wrist := skeleton.find_bone("wrist")
	_check(wrist >= 0, "anatomical skin must contain its real wrist bone")
	if wrist < 0: return
	for digit in ["little", "ring", "middle", "index", "thumb"]:
		var previous := wrist
		var posed := false
		for joint_index in 3:
			var bone := skeleton.find_bone(digit + str(joint_index))
			_check(bone >= 0 and skeleton.get_bone_parent(bone) == previous, "anatomical digit must retain its actual three-bone parent chain: " + digit)
			if bone < 0: continue
			posed = posed or skeleton.get_bone_pose_rotation(bone).angle_to(skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()) > 0.01
			previous = bone
		_check(posed, "each anatomical digit must actually articulate away from its imported open pose: " + digit)
	var thumb := skeleton.find_bone("thumb0")
	var index := skeleton.find_bone("index0")
	var little := skeleton.find_bone("little0")
	if thumb >= 0 and index >= 0 and little >= 0:
		_check(skeleton.get_bone_global_rest(thumb).origin.x * side < -0.01 and (skeleton.get_bone_global_rest(index).origin.x-skeleton.get_bone_global_rest(little).origin.x) * side < -0.04, "actual hand geometry must have right thumb on -X and left thumb on +X; file names alone do not establish handedness")
	var continuous_count := 0
	var skinned_count := 0
	var glove_count := 0
	var continuous_part: MeshInstance3D
	var glove_part: MeshInstance3D
	for part in rendered_parts:
		_check(imported_meshes.has(part.mesh) and declared_sources.has(part.mesh), "anatomical arm must retain the actual imported mesh resource: " + str(part.name))
		if part.skin != null:
			skinned_count += 1
			_check(part.skin.get_bind_count() == 16 and arm.hand_meshes.has(part), "every leather/skin hand surface must be bound to the same sixteen-bone hand")
			_check(part.get_node_or_null(part.skeleton) == skeleton, "each visible skinned mesh must resolve to the real anatomical skeleton")
		else:
			_check(arm.arm_meshes.has(part), "rigid sleeves and cuff must remain in the fitted arm geometry list")
		_check(not str(part.name).begins_with("ProximalFingerlessLeatherExtensions"), "restored finger openings must not retain the added proximal leather cover")
		if str(part.name).begins_with("ContinuousAnatomicalHand"):
			continuous_part = part
		if str(part.name).begins_with("FingerlessLeatherGlove"):
			glove_count += 1
			glove_part = part
			_check_original_glove(part, skeleton)
		for surface in part.mesh.get_surface_count():
			var source_material := part.mesh.surface_get_material(surface) as BaseMaterial3D
			var actual_material := part.get_active_material(surface) as BaseMaterial3D
			_check(source_material != null and actual_material != null and actual_material.resource_name == source_material.resource_name, "prepared anatomical materials must retain the source surface identity")
			if actual_material == null or source_material == null: continue
			_check(actual_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not actual_material.emission_enabled, "anatomical skin, leather and cloth must respond to real lighting")
			var expected_texture := ""
			match source_material.resource_name:
				"FP_Skin":
					continuous_count += 1
					expected_texture = "res://assets/ai/sword_shield/weathered_hand_skin.png"
					_check_continuous_skin(part, surface, skeleton)
				"FP_WornLeather", "FP_LayeredVambrace", "FP_SleeveStrap": expected_texture = "res://assets/ai/sword_shield/worn_charcoal_leather.png"
				"FP_QuiltedLinen": expected_texture = "res://assets/3d/player/sword_shield/textures/linen_albedo.jpg"
			if not expected_texture.is_empty():
				_check(actual_material.albedo_texture != null and actual_material.albedo_texture.resource_path == expected_texture, "anatomical skin/leather/cloth must use the actual authored surface texture: " + source_material.resource_name)
	_check(continuous_count == 1 and skinned_count == 2 and glove_count == 1, "each hand must contain exactly the continuous anatomical skin and its original weighted fingerless glove")
	if continuous_part != null and glove_part != null:
		for digit: String in ["little", "ring", "middle", "index", "thumb"]:
			var skin_extent := _digit_surface_extent(continuous_part, skeleton, digit)
			var glove_extent := _digit_surface_extent(glove_part, skeleton, digit)
			_check(is_finite(skin_extent) and is_finite(glove_extent) and skin_extent - glove_extent > 0.008, "each actual skin fingertip must extend beyond the original leather opening in rest geometry: " + digit)


func _check_original_glove(part: MeshInstance3D, skeleton: Skeleton3D) -> void:
	_check(part.skin != null and part.skin.get_bind_count() == 16 and part.mesh.get_surface_count() == 2, "the original glove must have sixteen real skin binds and its leather/opening-edge surfaces")
	if part.skin == null or part.skin.get_bind_count() != 16: return
	var materials: Array[String] = []
	var used_bones: Dictionary = {}
	var valid := true
	for surface in part.mesh.get_surface_count():
		var source_material := part.mesh.surface_get_material(surface) as BaseMaterial3D
		if source_material != null: materials.append(str(source_material.resource_name))
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := 8 if (part.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 else 4
		_check(vertices.size() > 100 and joints.size() == vertices.size() * stride and weights.size() == joints.size(), "original glove surfaces must have actual weighted vertices, not a rigid mesh with skin metadata")
		if joints.size() != vertices.size() * stride or weights.size() != joints.size():
			valid = false
			continue
		for vertex in vertices.size():
			var total := 0.0
			for slot in stride:
				var entry: int = vertex * stride + slot
				var weight := weights[entry]
				valid = valid and is_finite(weight) and weight >= 0.0
				total += weight
				if weight <= 0.0: continue
				var bind := joints[entry]
				if bind < 0 or bind >= part.skin.get_bind_count():
					valid = false
					continue
				var name := part.skin.get_bind_name(bind)
				var bone := skeleton.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind)
				if bone < 0 or bone >= skeleton.get_bone_count():
					valid = false
					continue
				used_bones[str(skeleton.get_bone_name(bone))] = true
			valid = valid and absf(total - 1.0) < 0.0001
	_check(valid and used_bones.has("wrist"), "original glove weights must remain finite, normalized and connected to the real wrist")
	for digit: String in ["little", "ring", "middle", "index", "thumb"]:
		_check(used_bones.has(digit + "0"), "original leather must deform with each actual finger root: " + digit)
	_check(materials.has("FP_WornLeather") and materials.has("FP_LeatherEdge"), "original glove must retain its imported leather and bound opening-edge material identities")


func _digit_surface_extent(part: MeshInstance3D, skeleton: Skeleton3D, digit: String) -> float:
	var root_bone := skeleton.find_bone(digit + "0")
	if root_bone < 0 or part.skin == null: return -INF
	var digit_rest := skeleton.get_bone_global_rest(root_bone)
	var axis := digit_rest.basis.y.normalized()
	var to_skeleton := skeleton.global_transform.affine_inverse() * part.global_transform
	var family_binds: Dictionary = {}
	for bind in part.skin.get_bind_count():
		var name := part.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind)
		if bone >= 0 and bone < skeleton.get_bone_count() and str(skeleton.get_bone_name(bone)).begins_with(digit): family_binds[bind] = true
	var furthest := -INF
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := 8 if (part.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 else 4
		if joints.size() != vertices.size() * stride or weights.size() != joints.size(): continue
		for vertex in vertices.size():
			var family_weight := 0.0
			for slot in stride:
				var entry: int = vertex * stride + slot
				if family_binds.has(joints[entry]): family_weight += weights[entry]
			if family_weight > 0.55:
				furthest = maxf(furthest, ((to_skeleton * vertices[vertex]) - digit_rest.origin).dot(axis))
	return furthest


func _check_continuous_skin(part: MeshInstance3D, surface: int, skeleton: Skeleton3D) -> void:
	_check(part.skin != null and part.skin.get_bind_count() == 16, "continuous hand skin must have sixteen real deformation binds")
	if part.skin == null or part.skin.get_bind_count() != 16: return
	var arrays := part.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := 8 if (part.mesh.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) != 0 else 4
	_check(vertices.size() > 1000 and joints.size() == vertices.size() * stride and weights.size() == joints.size(), "continuous anatomical skin must include real per-vertex bone indices and weights, not rigid finger pieces")
	if joints.size() != vertices.size() * stride or weights.size() != joints.size(): return
	for bind in part.skin.get_bind_count():
		var name := part.skin.get_bind_name(bind)
		var bone := skeleton.find_bone(name) if not name.is_empty() else part.skin.get_bind_bone(bind)
		_check(bone >= 0 and bone < skeleton.get_bone_count(), "every actual skin bind must resolve to an anatomical joint")
	var used_binds: Dictionary = {}
	var valid := true
	for vertex in vertices.size():
		var total := 0.0
		for slot in stride:
			var entry: int = vertex * stride + slot
			var weight := weights[entry]
			valid = valid and is_finite(weight) and weight >= 0.0
			total += weight
			if weight > 0.0:
				valid = valid and joints[entry] >= 0 and joints[entry] < part.skin.get_bind_count()
				used_binds[joints[entry]] = true
		valid = valid and absf(total - 1.0) < 0.0001
	_check(valid and used_binds.size() == 16, "actual continuous skin weights must be normalized, finite and deform through all sixteen bones")


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
