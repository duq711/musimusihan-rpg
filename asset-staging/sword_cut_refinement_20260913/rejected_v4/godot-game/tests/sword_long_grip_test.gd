extends SceneTree
## Verify the supplied static pose against its actual imported geometry, then
## drive the normal player clocks to ensure combat keeps that exact assembly.
const GRIP := preload("res://scripts/sword_long_grip_visual.gd")
const PREVIEW := preload("res://tests/player_arm_preview.gd")
const SOURCE_PATH := "res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb"
const OLD_SWORD := preload("res://assets/3d/player/sword_shield/longsword.glb")
const DT := 1.0 / 120.0
var failures: Array[String] = []
static var _thumb_reference_mapping: Dictionary = {}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var original := ExpeditionSession.capture_snapshot()
	var fingerprint := _inventory_fingerprint(original.inventory)
	var cursor := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	await physics_frame
	var player := fixture.player as DungeonPlayer
	_check(PREVIEW.configure_pose(fixture, "idle"), "imported grip fixture must use the production idle state")
	failures.append_array(audit_static_arm(player.weapon_arm))
	failures.append_array(audit_source_fidelity(player))
	_check(FileAccess.get_sha256(SOURCE_PATH) == GRIP.SOURCE_SHA256, "runtime must preserve the exact supplied GLB bytes")
	var source := GRIP.SOURCE.instantiate() as Node3D
	_check(source.find_children("*", "Skeleton3D", true, false).is_empty() and source.find_children("*", "AnimationPlayer", true, false).is_empty(), "source is a static pose and must not be represented as a supplied animation or rig")
	source.free()
	_test_blade_geometry(player)
	_test_source_sleeve_rest(player)
	_test_actual_swings(player)
	_test_smithing_isolation(player)
	_test_equipment_and_stowing(fixture)
	player.cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	_check(ExpeditionSession.capture_snapshot() == original and _inventory_fingerprint(original.inventory) == fingerprint and Input.mouse_mode == cursor, "source, combat, smithing and equipment checks must preserve original expedition contents and cursor")
	for failure in failures: push_error(failure)
	print("SWORD LONG GRIP %s: original mesh/material fidelity, authored hand through six real attacks, canonical blade/clash, smithing isolation, other weapons/chest/safe-zone restoration" % ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)


static func audit_static_arm(arm: Node3D) -> Array[String]:
	var errors: Array[String] = []
	if not is_instance_valid(arm):
		errors.append("Production sword must own its imported right hand")
		return errors
	if not bool(arm.get_meta("imported_static_grip", false)) or str(arm.get_meta("source_model", "")) != SOURCE_PATH:
		errors.append("Production sword hand must use the supplied static long-grip source")
	if bool(arm.get_meta("continuous_skin", false)) or not arm.find_children("*", "Skeleton3D", true, false).is_empty():
		errors.append("Imported static hand must not pretend to contain a continuous skin rig")
	if not arm.transform.is_equal_approx(Transform3D.IDENTITY):
		errors.append("Imported hand must retain its canonical frame under the moving weapon pivot")
	var parts := arm.find_children("*", "MeshInstance3D", true, false)
	if parts.size() != 4:
		errors.append("Imported right hand requires exactly the supplied glove and three sleeve surfaces")
	for part: MeshInstance3D in parts:
		if not GRIP.ARM_PARTS.has(str(part.name)) or part.mesh == null or part.skin != null or (str(part.name) == "RightHand_Glove" and not part.transform.is_equal_approx(Transform3D.IDENTITY)) or not part.transform.origin.is_finite() or not part.transform.basis.is_finite():
			errors.append("Imported hand must keep the authored unskinned surface in its canonical frame: " + str(part.name))
	if not arm.find_children("*", "CollisionObject3D", true, false).is_empty():
		errors.append("Imported visual must not add duplicate combat collision objects")
	return errors


static func audit_source_fidelity(player: DungeonPlayer, sword_materials_modified: bool = false, allow_sleeve_fit: bool = true) -> Array[String]:
	var errors: Array[String] = []
	var source := GRIP.SOURCE.instantiate() as Node3D
	var thumb_corrective: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GRIP.THUMB_CORRECTIVE_PATH))
	if FileAccess.get_sha256(GRIP.THUMB_CORRECTIVE_PATH) != GRIP.THUMB_CORRECTIVE_SHA256 or thumb_corrective.source_sha256 != GRIP.SOURCE_SHA256:
		errors.append("Authored thumb corrective must retain its reviewed bytes and immutable source provenance")
	var original_parts := source.find_children("*", "MeshInstance3D", true, false)
	var rendered := player._sword_weapon_arm.find_children("*", "MeshInstance3D", true, false)
	for part: MeshInstance3D in player.sword_visual_root.find_children("*", "MeshInstance3D", true, false):
		if part.has_meta("source_node"): rendered.append(part)
	if original_parts.size() != 11 or rendered.size() != original_parts.size():
		errors.append("Production sword and hand must include all eleven supplied surfaces exactly once")
	var seen := {}
	for part: MeshInstance3D in rendered:
		var source_name := str(part.get_meta("source_node", ""))
		var reference := source.find_child(source_name, true, false) as MeshInstance3D
		if reference == null or seen.has(source_name):
			errors.append("Imported source part must map once to actual rendered geometry: " + source_name)
			continue
		seen[source_name] = true
		var relative := player.weapon_pivot.global_transform.affine_inverse() * part.global_transform
		var reference_frame := _relative_transform(reference, source.get_parent())
		var fitted_sleeve := source_name in ["RightArm_Forearm_Surface", "RightArm_UpperArm_Surface", "RightArm_WristCuff_Surface"]
		# Sleeves fit the arm and the cuff follows its wrist rotation. Their
		# source meshes stay immutable; glove and sword retain their world relationship.
		var restored_frame := GRIP.SOURCE_READY if fitted_sleeve and allow_sleeve_fit else GRIP.SOURCE_READY * relative
		if part.mesh == null or reference.mesh == null or part.mesh.get_surface_count() != reference.mesh.get_surface_count():
			errors.append("Imported part must retain all supplied material surfaces: " + source_name)
			continue
		for surface in reference.mesh.get_surface_count():
			var expected := reference.mesh.surface_get_arrays(surface)
			var actual := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
			var original_vertices: PackedVector3Array = expected[Mesh.ARRAY_VERTEX]
			var thumb_vertices: Dictionary = authored_thumb_mapping(expected, thumb_corrective) if source_name == "RightHand_Glove" and surface == 0 else {}
			var valid := vertices.size() == original_vertices.size()
			if valid:
				for index in vertices.size():
					var expected_vertex: Vector3 = _thumb_expected_position(thumb_vertices, index, original_vertices[index]) if source_name == "RightHand_Glove" and surface == 0 else original_vertices[index]
					if (restored_frame * vertices[index]).distance_to(reference_frame * expected_vertex) > 0.000015:
						valid = false
						break
			if not valid: errors.append("Actual rendered vertices must preserve the original assembly or the scoped Blender thumb corrective within 0.015mm: " + source_name)
			for channel in [Mesh.ARRAY_INDEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				if actual[channel] != expected[channel]: errors.append("Imported indices, UVs and vertex colors must remain the supplied data: " + source_name + "/" + str(channel))
			var original_material := reference.get_active_material(surface)
			if part.mesh.surface_get_material(surface) != original_material:
				errors.append("Canonical geometry must retain the original material resources: " + source_name)
			if not (sword_materials_modified and source_name.begins_with("Sword_")) and part.get_active_material(surface) != original_material:
				errors.append("Runtime must render the supplied embedded material without a replacement atlas: " + source_name)
	source.free()
	return errors


static func _thumb_expected_position(mapping: Dictionary, index: int, original: Vector3) -> Vector3:
	if not mapping.has(index): return original
	var xyz: Array = mapping[index].position
	return Vector3(xyz[0], xyz[1], xyz[2])


static func authored_thumb_mapping(arrays: Array, corrective: Dictionary) -> Dictionary:
	if not _thumb_reference_mapping.is_empty(): return _thumb_reference_mapping
	# Independent reference lookup walks source corrections along sorted
	# imported X positions; production instead queries a 3D spatial grid.
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var sorted_indices: Array[int] = []
	for index in vertices.size(): sorted_indices.append(index)
	sorted_indices.sort_custom(func(a: int, b: int) -> bool: return vertices[a].x < vertices[b].x)
	for entry: Dictionary in corrective.changes:
		var position := Vector3(entry.source_position[0], entry.source_position[1], entry.source_position[2])
		var normal := Vector3(entry.source_normal[0], entry.source_normal[1], entry.source_normal[2])
		var low := 0
		var high := sorted_indices.size()
		while low < high:
			var middle := (low + high) / 2
			if vertices[sorted_indices[middle]].x < position.x - 0.000005: low = middle + 1
			else: high = middle
		var best := -1
		var score := INF
		while low < sorted_indices.size():
			var index := sorted_indices[low]
			if vertices[index].x > position.x + 0.000005: break
			low += 1
			if _thumb_reference_mapping.has(index): continue
			var distance_squared := vertices[index].distance_squared_to(position)
			if distance_squared > 0.000005 * 0.000005: continue
			var candidate := distance_squared + (1.0 - normals[index].dot(normal)) * 0.000000000001
			if candidate < score:
				score = candidate
				best = index
		assert(best >= 0, "Authored thumb must have an independent imported reference vertex")
		_thumb_reference_mapping[best] = entry
	return _thumb_reference_mapping


static func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != null and parent != ancestor:
		if parent is Node3D: result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result


func _test_blade_geometry(player: DungeonPlayer) -> void:
	var original := OLD_SWORD.instantiate() as Node3D
	var blade := original.find_child("PittedBlade", true, false) as MeshInstance3D
	_check(blade != null and player.sword_blade != null, "actual old and imported blades must exist for independent clash comparison")
	if blade != null and player.sword_blade != null:
		var expected := blade.mesh.get_aabb()
		var actual := player.sword_blade.mesh.get_aabb()
		_check(expected.position.distance_to(actual.position) < 0.00002 and expected.size.distance_to(actual.size) < 0.00002, "normalization must preserve the established slender canonical blade AABB, not the inflated camera-space bounds")
		var proxy := player.get_sword_clash_proxy()
		_check(not proxy.is_empty(), "visible imported blade must supply actual clash geometry")
		if not proxy.is_empty():
			_check((proxy.center as Vector3).distance_to(player.sword_blade.to_global(actual.get_center())) < 0.00001 and (proxy.half_extents as Vector3).distance_to(actual.size * 0.5) < 0.00001, "clash proxy must use the real normalized rendered blade")
	original.free()


func _test_source_sleeve_rest(player: DungeonPlayer) -> void:
	var arm := player._sword_weapon_arm
	arm.call("fit_arm", arm.to_global(GRIP.REST_SHOULDER), arm.to_global(GRIP.REST_ELBOW))
	_check((arm.get("_forearm") as Node3D).transform.is_equal_approx(Transform3D.IDENTITY) and (arm.get("_upper_arm") as Node3D).transform.is_equal_approx(Transform3D.IDENTITY) and (arm.get("_cuff") as Node3D).transform.is_equal_approx(Transform3D.IDENTITY), "returning to the source rest anchors must restore the exact original sleeve and cuff transforms")
	failures.append_array(audit_source_fidelity(player, false, false))
	player._update_character_arms()


static func audit_sleeve_connections(player: DungeonPlayer, context: String = "") -> Array[String]:
	var errors: Array[String] = []
	var arm := player._sword_weapon_arm
	var forearm := arm.get("_forearm") as Node3D
	var upper := arm.get("_upper_arm") as Node3D
	var cuff := arm.get("_cuff") as Node3D
	if forearm == null or upper == null or cuff == null:
		errors.append("Imported sleeve needs both real source segments and its original wrist cuff")
		return errors
	var wrist := arm.to_global(GRIP.REST_WRIST)
	var shoulder := player.camera.to_global(GRIP.SOURCE_READY * GRIP.REST_SHOULDER)
	var joints: Dictionary = player.get_first_person_motion_snapshot().joint_landmarks.get("sword", {})
	if bool(joints.get("authored_arm_active", false)):
		shoulder = joints.shoulder
	var cuff_pivot_error := cuff.to_global(GRIP.REST_WRIST).distance_to(wrist)
	var cuff_alignment := cuff.basis.is_equal_approx(forearm.basis.orthonormalized())
	var cuff_scale_preserved := cuff.basis.get_scale().is_equal_approx(Vector3.ONE)
	if cuff_pivot_error > 0.00003 or not cuff_alignment or not cuff_scale_preserved:
		errors.append("Original cuff must rotate with the fitted forearm about the authored wrist without scaling: %s pivot %.6fmm rotation aligned %s scale %s" % [context, cuff_pivot_error * 1000.0, str(cuff_alignment), str(cuff.basis.get_scale())])
	var wrist_error := forearm.to_global(GRIP.REST_WRIST).distance_to(wrist)
	var elbow_error := forearm.to_global(GRIP.REST_ELBOW).distance_to(upper.to_global(GRIP.REST_ELBOW))
	var shoulder_error := upper.to_global(GRIP.REST_SHOULDER).distance_to(shoulder)
	if wrist_error > 0.00003 or elbow_error > 0.00003 or shoulder_error > 0.00003:
		var fitted: Dictionary = arm.call("get_snapshot")
		errors.append("Actual imported sleeve endpoints must join the authored wrist, each other and the camera-relative shoulder through combat: %s wrist %.6fmm elbow %.6fmm shoulder %.6fmm; fitted elbow %s fitted shoulder %s" % [context, wrist_error * 1000.0, elbow_error * 1000.0, shoulder_error * 1000.0, str(fitted.fitted_elbow), str(fitted.fitted_shoulder)])
	return errors


func _test_actual_swings(player: DungeonPlayer) -> void:
	for charge in [false, true]:
		for variant: String in ["right_diagonal", "left_reverse", "overhead"]:
			player.cancel_sword_attack()
			player.stamina = 100.0
			player.set_sword_attack_mode(variant)
			player._motion_equip_elapsed = 1.0
			player._update_viewmodel(0.0)
			var baseline := _rigid_signature(player._sword_weapon_arm)
			var before := player.weapon_pivot.transform
			var sleeve_before := (player._sword_weapon_arm.get("_forearm") as Node3D).transform
			var sleeve_fitted := false
			var expected_cost := player.get_melee_stamina_cost(1.0 if charge else 0.0)
			_check(bool(player.begin_sword_attack().accepted), "production clock must accept imported grip cut: " + variant)
			player.attack_release_requested = not charge
			var phases := {}
			var moved := false
			for frame in 360:
				player.advance_action_timers(DT)
				player.advance_combat_state(DT, false)
				player._update_viewmodel(DT)
				player._resolve_active_attack()
				phases[player.combat_state] = true
				moved = moved or not player.weapon_pivot.transform.is_equal_approx(before)
				sleeve_fitted = sleeve_fitted or not (player._sword_weapon_arm.get("_forearm") as Node3D).transform.is_equal_approx(sleeve_before)
				failures.append_array(audit_sleeve_connections(player, "%s charge %s frame %d" % [variant, str(charge), frame]))
				_check(_rigid_signature(player._sword_weapon_arm) == baseline, "actual sword animation must preserve the supplied glove transform, plus every source mesh and material")
				if frame in [15, 35, 60]: failures.append_array(audit_source_fidelity(player))
				if player.combat_state == DungeonPlayer.CombatState.READY: break
			_check(moved and phases.has(DungeonPlayer.CombatState.WINDUP) and phases.has(DungeonPlayer.CombatState.ACTIVE) and phases.has(DungeonPlayer.CombatState.RECOVERY) and player.combat_state == DungeonPlayer.CombatState.READY, "new grip must traverse real windup, active, recovery and ready through every cut")
			_check(sleeve_fitted, "actual sword cuts must fit the imported sleeve to its shoulder while preserving the authored hand contact")
			_check(is_equal_approx(player.stamina, 100.0 - expected_cost), "imported sword must retain one real light/heavy stamina cost")


func _test_smithing_isolation(player: DungeonPlayer) -> void:
	var baseline := _rigid_signature(player._sword_weapon_arm)
	var instance := player.inventory_model.get_equipment_instance("weapon")
	var mods: Dictionary = instance.get("smithing", {}).duplicate(true)
	instance["smithing"] = {"quality": 0.85, "grip": "balanced_grip", "reinforcement": "silver_edge", "sockets": 1, "runes": ["ember_rune"]}
	player._sync_smithing_weapon_visual()
	_check(_rigid_signature(player._sword_weapon_arm) == baseline, "smithing must never recolor, decorate or rebuild the supplied hand and sleeve")
	for name: String in ["GripLeather", "GripLeather_Extension", "GripBinding", "GripBinding_Extension"]:
		var part := player.sword_visual_root.find_child(name, true, false) as MeshInstance3D
		_check(part != null and part.material_override != null, "real smithing grip change must reach original and extended handle surfaces: " + name)
	_check(player.sword_visual_root.find_child("RuneGem0", true, false) != null and player._sword_weapon_arm.find_child("SmithingDetails", true, false) == null, "real rune details belong only to the sword")
	failures.append_array(audit_source_fidelity(player, true))
	instance["smithing"] = mods
	player._sync_smithing_weapon_visual()
	failures.append_array(audit_source_fidelity(player))


func _test_equipment_and_stowing(fixture: Dictionary) -> void:
	var player := fixture.player as DungeonPlayer
	var inventory := fixture.inventory as ExpeditionInventory
	var original_arm := player._sword_weapon_arm
	for id: String in ["hunting_bow", "chain_flail", "weathered_staff"]:
		inventory.add_item(id, 1)
		_check(PREVIEW._equip_weapon(inventory, id), "other actual weapon must equip: " + id)
		player._update_viewmodel(0.0)
		_check(player.weapon_arm == player._legacy_weapon_arm and not original_arm.is_visible_in_tree() and not player.sword_visual_root.visible, "other weapons must restore their articulated arm and hide supplied sword surfaces: " + id)
		_check(PREVIEW._equip_weapon(inventory, "rusted_sword"), "switching back must use real sword inventory equipment")
		player._update_viewmodel(0.0)
		_check(player.weapon_arm == original_arm, "switching back must reuse the original supplied grip without duplicates")
		player._update_viewmodel(player.SWORD_DRAW_DURATION + 0.1)
		_check(original_arm.is_visible_in_tree(), "the reused sword grip must become visible when the actual draw finishes")
		failures.append_array(audit_static_arm(original_arm))
	player.configure_safe_zone(true)
	player._update_viewmodel(0.0)
	_check(not original_arm.is_visible_in_tree(), "safe zones must stow the imported sword hand")
	player.configure_safe_zone(false)
	player._update_viewmodel(1.0)
	_check(original_arm.is_visible_in_tree(), "leaving a safe zone must restore the same sword hand")
	_check(PREVIEW.configure_pose(fixture, "chest_touch"), "actual chest interaction must accept the imported sword equipment")
	_check(player.is_timed_interacting() and player.chest_equipment_stowed and not original_arm.is_visible_in_tree(), "actual timed chest contact must stow the sword hand and use bare chest hands")
	player.cancel_timed_interaction()
	player._update_viewmodel(1.0)
	_check(player.weapon_arm == original_arm and original_arm.is_visible_in_tree(), "canceling chest contact must restore the same imported sword grip")
	failures.append_array(audit_source_fidelity(player))


static func _rigid_signature(arm: Node3D) -> Array:
	var result: Array = [arm.transform]
	for part: MeshInstance3D in arm.find_children("*", "MeshInstance3D", true, false):
		result.append([part.get_instance_id(), Transform3D.IDENTITY if str(part.name) in ["RightArm_Forearm_Surface", "RightArm_UpperArm_Surface", "RightArm_WristCuff_Surface"] else part.transform, part.mesh, part.material_override])
	return result


static func _inventory_fingerprint(inventory: ExpeditionInventory) -> String:
	if inventory == null: return "no_inventory"
	return JSON.stringify({"slots": inventory.slots, "equipment": inventory.equipment, "equipment_data": inventory.equipment_data}).sha256_text()


func _check(passed: bool, message: String) -> void:
	if not passed and not failures.has(message): failures.append(message)
