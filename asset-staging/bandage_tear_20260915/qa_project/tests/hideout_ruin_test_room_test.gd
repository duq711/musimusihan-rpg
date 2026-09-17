extends SceneTree

const VIEWS := preload("res://scripts/hideout_ruin_views.gd")
const CATALOG := preload("res://scripts/test_room_catalog.gd")
const ROOM_PATH := "res://test_room.tscn"
const HIDEOUT_PATH := "res://hideout.tscn"
const SCENE_TIMEOUT_MSEC := 30000
const ORIGINAL_ROOFS := {
	"central": {"position": Vector3(0.0, 5.45, 0.0), "size": Vector3(16.0, 0.5, 20.0)},
	"entrance": {"position": Vector3(0.0, 4.45, 15.0), "size": Vector3(8.0, 0.5, 10.0)},
	"sleep": {"position": Vector3(-11.75, 4.38, 5.5), "size": Vector3(7.0, 0.46, 7.0)},
	"storage": {"position": Vector3(11.75, 4.38, 5.5), "size": Vector3(7.0, 0.46, 7.0)},
	"workshop": {"position": Vector3(12.0, 4.38, -5.0), "size": Vector3(8.0, 0.46, 6.0)},
	"flooded_store": {"position": Vector3(-11.75, 4.38, -5.0), "size": Vector3(7.0, 0.46, 6.0)},
	"ossuary": {"position": Vector3(0.0, 4.75, -16.0), "size": Vector3(12.0, 0.5, 12.0)},
	"drain": {"position": Vector3(20.3, 3.55, -5.0), "size": Vector3(8.6, 0.45, 3.4)},
}
var failures: Array[String] = []
var sandbox: Node
var room: Node3D
var trial_bag: ExpeditionInventory
var actor_was_processing := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	sandbox = root.get_node("TestRoomSandbox")
	ExpeditionSession.begin_new_journey()
	var original := ExpeditionSession.get_inventory()
	original.add_item("liquor_hearth_brandy_normal", 2)
	ExpeditionSession.crowns = 643
	ExpeditionSession.hunger = 52.0
	ExpeditionSession.thirst = 31.0
	ExpeditionSession.stress = 37.0
	ExpeditionSession.apply_condition("bleeding", 83.0)
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["price"] = 11
	(ExpeditionSession.merchant_stock["alchemy_wine"] as Dictionary)["unlimited"] = false
	var original_slots := original.slots.duplicate(true)
	var original_equipment := original.equipment.duplicate(true)
	var original_equipment_data := original.equipment_data.duplicate(true)
	var notifications: Array[int] = []
	var observer := func() -> void: notifications.append(1)
	original.changed.connect(observer)
	var snapshot := ExpeditionSession.capture_snapshot()
	_check(not sandbox.prepare_hideout_view("central") and str(sandbox.pending_hideout_view).is_empty(), "room inspection routing must reject use outside a sandbox")
	room = (load(ROOM_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await process_frame
	trial_bag = room.inventory
	_check(sandbox.active and trial_bag != original and room.panel_open and paused, "ruin inspection starts in a paused isolated test room")
	_test_catalog()
	_test_pending_routes()
	trial_bag.add_item("liquor_moon_absinthe_normal", 2)
	ExpeditionSession.crowns = 8642
	var trial_slots := trial_bag.slots.duplicate(true)
	var trial_crowns := ExpeditionSession.crowns
	for room_id in VIEWS.ordered_ids():
		if not await _enter_room_view(room_id):
			break
		_test_actual_room(room_id)
		if room_id == "central":
			await _test_normal_interaction()
		_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_equipment_data and notifications.is_empty(), "scene inspection and actual interactions cannot touch the original inventory or its signals")
		if not await _return_to_room():
			break
		_check(trial_bag.slots == trial_slots and ExpeditionSession.crowns == trial_crowns, "view entry and F2 return must preserve the existing trial items and money")
		await _test_menu_pause()
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		# A repeated visit must consume a fresh view request and rebuild the
		# actual decorated world without carrying another room's camera.
		if await _enter_room_view("central"):
			_test_actual_room("central")
			await _return_to_room()
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		var previous_bag := trial_bag
		_check(sandbox.prepare_hideout_view("drain"), "a known view may be pending before test reset")
		room.reset_room()
		trial_bag = room.inventory
		_check(trial_bag != previous_bag and trial_bag != original and sandbox.saved_session == snapshot, "reset replaces only the sandbox inventory and retains the original snapshot")
		_check(str(sandbox.pending_hideout_view).is_empty(), "test reset clears an unused room inspection request")
		if await _enter_room_view("storage"):
			_test_actual_room("storage")
			await _return_to_room()
	if is_instance_valid(current_scene) and current_scene.scene_file_path == ROOM_PATH:
		room.leave_room()
		await _wait_for_scene("res://main_menu.tscn")
	_check(not sandbox.active and str(sandbox.pending_hideout_view).is_empty(), "finishing the test session clears all pending room inspection state")
	_check(ExpeditionSession.get_inventory() == original and ExpeditionSession.capture_snapshot() == snapshot, "finishing restores the exact original bag reference, wallet, stock, needs and condition durations")
	_check(original.slots == original_slots and original.equipment == original_equipment and original.equipment_data == original_equipment_data and original.changed.is_connected(observer) and notifications.is_empty(), "original items, equipment and connected signals survive every room inspection")
	original.changed.disconnect(observer)
	paused = false
	if is_instance_valid(current_scene):
		current_scene.queue_free()
		current_scene = null
	await process_frame
	if failures.is_empty():
		print("HIDEOUT RUIN TEST ROOM PASS: eight source-catalog routes, actual decorated rooms and camera positions, living interactions, region bounds, F2 pause/repeat/reset and full original expedition restoration")
		quit(0)
	else:
		for failure in failures:
			push_error("HIDEOUT RUIN TEST ROOM FAIL: " + failure)
		quit(1)


func _test_catalog() -> void:
	var entries := CATALOG.entries()
	var generated := 0
	_check(VIEWS.ordered_ids().size() == 8 and VIEWS.SHOTS.size() == 8, "source camera catalog must include all eight physical hideout rooms")
	for entry in entries:
		if str(entry.id).begins_with("hideout_ruin:"):
			generated += 1
	_check(generated == VIEWS.ordered_ids().size(), "room inspection entries must be generated once from the authoritative views")
	for room_id in VIEWS.ordered_ids():
		var shot := VIEWS.get_shot(room_id)
		var matches: Array = entries.filter(func(entry: Dictionary) -> bool: return str(entry.id) == "hideout_ruin:" + room_id)
		_check(matches.size() == 1 and str(matches[0].action) == "hideout_ruin" and str(matches[0].payload) == room_id and str(matches[0].category) == "장면" and str(matches[0].title).contains(str(shot.title)), "each named room must expose an executable scene-category trial: " + room_id)
		var original_position: Vector3 = shot.position
		shot.position = Vector3.ZERO
		_check(VIEWS.get_shot(room_id).position == original_position, "view copies cannot alter the canonical production inspection position")
	_check(VIEWS.get_shot("missing_room").is_empty(), "unknown room IDs must not acquire a fallback camera")


func _test_pending_routes() -> void:
	var state := ExpeditionSession.capture_snapshot()
	_check(sandbox.prepare_hideout_view("central") and str(sandbox.pending_hideout_view) == "central", "valid room inspection request must be stored once")
	_check(not sandbox.prepare_hideout_view("missing_room") and str(sandbox.pending_hideout_view).is_empty(), "invalid room request must reject and clear a previous pending view")
	_check(sandbox.prepare_hideout_view("sleep") and str(sandbox.consume_hideout_view()) == "sleep" and str(sandbox.consume_hideout_view()).is_empty(), "room inspection routes must be consumed exactly once")
	_check(sandbox.prepare_hideout_view("drain") and sandbox.prepare_hideout_view("") and str(sandbox.pending_hideout_view).is_empty(), "clearing a room route must not leave stale camera state")
	_check(ExpeditionSession.capture_snapshot() == state, "preparing and consuming a room view must not change the actual expedition")


func _enter_room_view(room_id: String) -> bool:
	if not is_instance_valid(current_scene) or current_scene.scene_file_path != ROOM_PATH:
		_check(false, "room view selection requires the actual paused test room")
		return false
	room = current_scene as Node3D
	actor_was_processing = false
	room.run_feature("hideout_ruin:" + room_id)
	return await _wait_for_scene(HIDEOUT_PATH, true)


func _test_actual_room(room_id: String) -> void:
	var hideout: SanctuaryHideout = current_scene
	var shot := VIEWS.get_shot(room_id)
	var actor: DungeonPlayer = hideout.player
	_check(hideout.scene_file_path == HIDEOUT_PATH and hideout.inventory == trial_bag and hideout.world_root.visible and actor.visible and actor.safe_zone_mode and not paused and actor_was_processing, "the room trial must enter the live production hideout and retain ordinary safe-zone control")
	_check(str(sandbox.pending_hideout_view).is_empty() and str(sandbox.pending_alchemy_trial).is_empty() and str(sandbox.pending_blacksmith_trial).is_empty() and not bool(sandbox.pending_cooking_trial), "room inspection must consume its route without opening another workshop trial")
	_check(not is_instance_valid(hideout.alchemy_overlay) and not is_instance_valid(hideout.blacksmith_overlay), "inspection enters the actual world instead of a crafting overlay")
	var expected_eye: Vector3 = shot.position
	var expected_direction := ((shot.target as Vector3) - expected_eye).normalized()
	var applied: Dictionary = hideout.get_meta("ruin_trial_camera", {})
	_check(str(applied.get("room_id", "")) == room_id and applied.has("transform"), "actual room route must record its applied camera before ordinary physics resumes")
	if applied.has("transform"):
		var camera_at_entry: Transform3D = applied.transform
		_check(camera_at_entry.origin.distance_to(expected_eye) < 0.0001 and (-camera_at_entry.basis.z).normalized().dot(expected_direction) > 0.99999 and is_equal_approx(float(applied.fov), float(shot.fov)), "the actual applied camera must exactly match source eye, direction and FOV: " + room_id)
		var body_at_entry: Vector3 = applied.player_position
		var player_colliders := actor.find_children("*", "CollisionShape3D", false, false)
		_check(player_colliders.size() == 1 and (player_colliders[0] as CollisionShape3D).shape is CapsuleShape3D, "the routed actor must retain its actual standing capsule")
		if player_colliders.size() == 1:
			var standing_half_height := ((player_colliders[0] as CollisionShape3D).shape as CapsuleShape3D).height * 0.5
			_check(actor.global_position.y <= body_at_entry.y + 0.001 and actor.global_position.y >= standing_half_height - 0.005, "normal gravity after routing may settle the capsule onto the authored floor without falling through it: " + room_id)
	var horizontal_error := Vector2(actor.camera.global_position.x - expected_eye.x, actor.camera.global_position.z - expected_eye.z).length()
	_check(horizontal_error < 0.0001, "normal loading physics must preserve the exact routed horizontal camera position: " + room_id)
	_check((-actor.camera.global_basis.z).normalized().dot(expected_direction) > 0.999 and is_equal_approx(actor.camera.fov, float(shot.fov)), "actual view direction, pitch and FOV must match the source room camera: " + room_id)
	_check(is_instance_valid(hideout.ruin_visual) and hideout.ruin_visual.has_method("get_validation_snapshot"), "the live hideout must own its production ruin dressing")
	if not is_instance_valid(hideout.ruin_visual):
		return
	var validation: Dictionary = hideout.ruin_visual.get_validation_snapshot()
	if room_id == "central":
		_test_roof_openings(hideout, validation)
	var regions: Dictionary = validation.get("regions", {})
	_check(regions.size() == VIEWS.ordered_ids().size(), "the actual ruin snapshot must account for every source region")
	for region_id in VIEWS.ordered_ids():
		_check(regions.has(region_id) and hideout.region_nodes.has(region_id), "the actual production world must contain region " + region_id)
		if not regions.has(region_id) or not hideout.region_nodes.has(region_id):
			continue
		var counts: Dictionary = regions[region_id]
		_check(int(counts.get("prop_count", 0)) > 0 and int(counts.get("stain_count", 0)) > 0 and int(counts.get("leak_count", 0)) > 0, "every real room must have ruin props, damp/mold treatment and water leaks: " + region_id)
		var region: Node3D = hideout.region_nodes[region_id]
		var dressing := region.get_node_or_null("RuinDressing_" + region_id) as Node3D
		_check(dressing != null, "ruin geometry must live in its actual streaming region: " + region_id)
		if dressing == null:
			continue
		var chips := dressing.get_node_or_null("RuinScatteredStoneChips") as MeshInstance3D
		_check(chips != null and chips.mesh != null and chips.mesh.get_surface_count() == 1 and chips.is_visible_in_tree(), "each room must contain a real single-surface mesh for small fallen stone fragments: " + region_id)
		_check(int(counts.get("scatter_count", 0)) >= 25 and int(counts.get("scatter_count", 0)) <= 45, "reported stone scatter must contain the bounded set of real fragments: " + region_id)
		_check(dressing.find_children("*", "CollisionObject3D", true, false).is_empty() and dressing.find_children("*", "CollisionShape3D", true, false).is_empty(), "room decoration must not introduce unseen blockers or interaction areas: " + region_id)
		var visible_meshes := 0
		var bounds: AABB = region.get_meta("streaming_bounds")
		for mesh: MeshInstance3D in dressing.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null or mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				continue
			visible_meshes += 1
			_check(mesh.layers == 1, "ruin mesh must render in the ordinary world layer: " + str(mesh.name))
			var placement := region.global_transform.affine_inverse() * mesh.global_transform
			_check(bounds.grow(0.35).encloses(placement * mesh.mesh.get_aabb()), "ruin mesh must remain inside its room's authored envelope: " + region_id + "/" + str(mesh.name))
		_check(visible_meshes > 0, "reported ruin props must be backed by visible production meshes: " + region_id)
		var emitters := dressing.find_children("*", "CPUParticles3D", true, false)
		emitters.append_array(dressing.find_children("*", "GPUParticles3D", true, false))
		var active_leaks := 0
		for emitter in emitters:
			if bool(emitter.get_meta("ruin_leak", false)) and bool(emitter.get("emitting")) and int(emitter.get("amount")) > 0:
				active_leaks += 1
		_check(active_leaks > 0, "reported water leaks must connect to actual emitting particles: " + region_id)


func _test_roof_openings(hideout: SanctuaryHideout, validation: Dictionary) -> void:
	var openings: Dictionary = validation.get("roof_openings", {})
	_check(openings.size() == ORIGINAL_ROOFS.size(), "all eight rooms must have actual roof openings")
	var total_openings := 0
	for region_id in ORIGINAL_ROOFS:
		var holes: Array = openings.get(region_id, [])
		total_openings += holes.size()
		_check(holes.size() == (2 if region_id == "central" else 1), "each room must expose its authored number of roof breaks: " + region_id)
		if holes.is_empty():
			continue
		var region: Node3D = hideout.region_nodes[region_id]
		var body := region.get_node_or_null(str(holes[0].ceiling_body)) as StaticBody3D
		_check(body != null, "roof opening must refer to its original production ceiling body")
		if body == null:
			continue
		var colliders := body.find_children("*", "CollisionShape3D", true, false)
		_check(colliders.size() == 1 and body.collision_layer == 2 and body.collision_mask == 1, "roof dressing must retain one original collider and its exact world/player layers")
		if colliders.size() != 1:
			continue
		var original: Dictionary = ORIGINAL_ROOFS[region_id]
		var shape := (colliders[0] as CollisionShape3D).shape as BoxShape3D
		_check(shape != null and shape.size.is_equal_approx(original.size) and body.position.is_equal_approx(original.position), "roof break must retain the authored ceiling collision size and placement: " + region_id)
		var architecture: Node3D
		for child in body.get_children():
			if child.has_meta("ruin_roof_openings"):
				architecture = child as Node3D
		_check(architecture != null, "roof break must be backed by an actual split architecture root")
		if architecture == null:
			continue
		_check(architecture.get_meta("ruin_roof_original_size") == original.size and architecture.get_meta("ruin_roof_openings") == holes, "roof inspection metadata must identify its exact original ceiling and real apertures")
		var full_size: Vector3 = original.size
		var roof := Rect2(Vector2(body.position.x, body.position.z) - Vector2(full_size.x, full_size.z) * 0.5, Vector2(full_size.x, full_size.z))
		var hole_rects: Array[Rect2] = []
		var partition_area := 0.0
		for hole: Dictionary in holes:
			var center: Vector3 = hole.center
			var extent: Vector2 = hole.size
			var opening := Rect2(Vector2(center.x, center.z) - extent * 0.5, extent)
			_check(roof.grow(-0.239).encloses(opening) and opening.has_area(), "localized roof opening must retain a closed rim inside its original room")
			for previous in hole_rects:
				_check(previous.intersection(opening).get_area() < 0.00001, "independent roof holes cannot overlap")
			hole_rects.append(opening)
			partition_area += opening.get_area()
		var panel_rects: Array[Rect2] = []
		for child in architecture.get_children():
			_check(child.has_meta("ruin_roof_fragment"), "whole original slab, mortar core or solid shadow must not remain across the cut roof")
			if not child.has_meta("ruin_roof_fragment"):
				continue
			var fragment := child as Node3D
			var size: Vector3 = fragment.get_meta("ruin_roof_fragment")
			var center := body.position + fragment.position
			var panel := Rect2(Vector2(center.x, center.z) - Vector2(size.x, size.z) * 0.5, Vector2(size.x, size.z))
			_check(roof.grow(0.0001).encloses(panel) and panel.has_area() and is_equal_approx(size.y, full_size.y), "actual roof fragment must retain original depth and remain inside the ceiling")
			for hole in hole_rects:
				_check(panel.intersection(hole).get_area() < 0.00001, "actual remaining ceiling panels cannot cover the visual holes")
			for previous in panel_rects:
				_check(panel.intersection(previous).get_area() < 0.00001, "actual remaining ceiling panels must partition the roof without overlaps")
			panel_rects.append(panel)
			partition_area += panel.get_area()
			_check(fragment.find_child("FlagstoneSlabs", true, false) != null and fragment.find_child("RecessedMortarCore", true, false) != null and fragment.find_child("SolidArchitectureShadow", true, false) != null, "remaining roof fragments must include their actual stone, opaque core and local shadow geometry")
			for hole: Dictionary in holes:
				var local_center := (hole.center as Vector3) - body.position - fragment.position
				for surface: MeshInstance3D in fragment.find_children("*", "MeshInstance3D", true, false):
					if surface.mesh == null:
						continue
					var local_bounds := surface.transform * surface.mesh.get_aabb()
					var horizontal_bounds := Rect2(Vector2(local_bounds.position.x, local_bounds.position.z), Vector2(local_bounds.size.x, local_bounds.size.z))
					_check(not horizontal_bounds.has_point(Vector2(local_center.x, local_center.z)), "the center of each hole must stay open through actual stone, mortar and shadow geometry")
		_check(panel_rects.size() == (architecture.get_meta("ruin_roof_fragments") as Array).size() and absf(partition_area - roof.get_area()) < 0.001, "actual roof fragments plus holes must account for the whole original ceiling exactly")
	_check(total_openings == 9, "the actual hideout must have nine localized roof openings")


func _test_normal_interaction() -> void:
	var hideout: SanctuaryHideout = current_scene
	var actor: DungeonPlayer = hideout.player
	var pot := hideout.find_child("CookingPotInteraction", true, false) as HideoutInteractable
	_check(pot != null and pot.action_id == "meal", "room dressing must preserve the actual central cooking interaction")
	if pot == null:
		return
	actor.global_position = Vector3(0.0, 1.0, 4.7)
	await physics_frame
	var target := pot.global_position + pot.interaction_offset
	var query := PhysicsRayQueryParameters3D.create(actor.camera.global_position, target, DungeonPlayer.WORLD_LAYER | DungeonPlayer.INTERACT_LAYER)
	query.collide_with_areas = true
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	_check(not hit.is_empty() and hit.collider.get_meta("interaction_owner", null) == pot, "new ruin geometry must leave the actual pot's approach and sightline clear")
	pot.interact(actor)
	_check(actor.timed_interaction_owner == pot, "ordinary pot use after room inspection begins the real timed interaction")
	actor.advance_timed_interaction(0.35)
	_check(paused and hideout.cooking_controller.is_open(), "ordinary pot use must open the real cooking UI and pause the inspected world")
	hideout.cooking_controller.close_kitchen()
	_check(not paused and hideout.world_root.visible, "closing a real living interaction must resume the inspected hideout")


func _return_to_room() -> bool:
	var previous_scene := current_scene
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	sandbox._input(f2)
	var returned := await _wait_for_scene(ROOM_PATH)
	if returned:
		room = current_scene as Node3D
		_check(not is_instance_valid(previous_scene) and room.panel_open and paused and room.inventory == trial_bag, "F2 must free the inspected world and return to the same paused sandbox inventory")
		_check(str(sandbox.pending_hideout_view).is_empty(), "F2 return must not retain a consumed room camera")
	return returned


func _test_menu_pause() -> void:
	var before := ExpeditionSession.capture_snapshot()
	var position_before: Vector3 = room.player.global_position
	for frame in 3:
		await process_frame
	_check(paused and ExpeditionSession.capture_snapshot() == before and room.player.global_position == position_before, "the test menu must stop survival and movement between room inspections")


func _wait_for_scene(path: String, freeze_player := false) -> bool:
	var deadline := Time.get_ticks_msec() + SCENE_TIMEOUT_MSEC
	var frozen := false
	while Time.get_ticks_msec() < deadline:
		var matches := is_instance_valid(current_scene) and current_scene.scene_file_path == path
		if matches and freeze_player and not frozen and is_instance_valid(current_scene.player):
			actor_was_processing = current_scene.player.is_physics_processing()
			current_scene.player.set_physics_process(false)
			frozen = true
		var loading := false
		for child in root.get_children():
			loading = loading or bool(child.get_meta(&"sanctuary_loading_host", false))
		if matches and not loading:
			await process_frame
			return true
		await process_frame
	_check(false, "bounded actual room scene transition timed out: " + path)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition and message not in failures:
		failures.append(message)
