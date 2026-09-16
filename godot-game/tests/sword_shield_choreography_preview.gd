extends SceneTree
## Actual carried arms and weapons: production action clocks, then camera-only
## inspection of the same nodes. Never invokes native windows or hardware input.
const PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const STUDIO := preload("res://tests/sword_shield_preview.gd")
const ACTIONS := ["ready", "right_diagonal", "left_reverse", "overhead", "shield_raise", "block_impact"]
const ATTACKS := ["right_diagonal", "left_reverse", "overhead"]
const EXTERNAL_VIEWS := ["top", "bottom", "left", "right"]
const POV_SIZE := Vector2i(1280, 720)
const EXTERNAL_SIZE := Vector2i(960, 720)
const FPS := 30
const FRAME_COUNT := 34
const STEP := 1.0 / 120.0
const OUTPUT_ROOT := "res://artifacts/visual_qa/sword_shield_choreography"
const REFERENCE_DIRECTORY := "res://../asset-staging/sword_shield_single_pose/references"
const EXTRA_SOURCES := ["res://scripts/sword_shield_choreography.gd", "res://tests/sword_shield_choreography_preview.gd", "res://tests/sword_shield_choreography_preview_test.gd", "res://tests/run_embedded_preview.sh", "res://../asset-staging/sword_shield_single_pose/references.json", "res://../asset-staging/sword_shield_single_pose/generation_records.json", "res://../asset-staging/sword_shield_single_pose/external_generation_records.json"]
const EXTERNAL_CAPTION := "동일한 실제 1인칭 검·오른손 파지·왼팔·방패를 촬영. 오른손은 제공된 정적 모델의 실제 메시 범위로 기록하고 왼팔은 어깨까지 확인. 별도 정적 전신·바닥·보관된 횃불은 숨기며 대체 신체나 팔은 추가하지 않음."
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Choreography capture requires the reviewed embedded renderer; native windows and dummy screenshots are refused.")
		quit(2)
		return
	var iteration := OS.get_environment("SWORD_SHIELD_CHOREOGRAPHY_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("SWORD_SHIELD_CHOREOGRAPHY_QA_ITERATION must name a new plain output folder.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active or DirAccess.dir_exists_absolute(output):
		push_error("Preserve active test-room sessions and existing choreography captures.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor := Input.mouse_mode
	var original := ExpeditionSession.capture_snapshot()
	var original_bag := original.get("inventory") as ExpeditionInventory
	var inventory_before := PREVIEW.inventory_fingerprint(original_bag)
	var hashes := source_hashes()
	for path: String in hashes:
		if str(hashes[path]).length() != 64: failures.append("Missing capture source: " + path)
	sandbox.begin()
	var sequences: Array[Dictionary] = []
	for action_id: String in ACTIONS:
		sequences.append(await _capture_action(output, action_id))
	sandbox.finish()
	var inventory_after := PREVIEW.inventory_fingerprint(original_bag)
	var preserved: bool = ExpeditionSession.capture_snapshot() == original and inventory_before == inventory_after and Input.mouse_mode == cursor and not sandbox.active
	var unchanged := hashes == source_hashes()
	if not preserved: failures.append("Original expedition, nested inventory contents or cursor changed")
	if not unchanged: failures.append("Consumed production/reference sources changed during capture")
	var manifest := {
		"capture_kind": "Same actual DungeonPlayer arms, sword and shield driven by shared production action clocks",
		"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"desktop_capture": false, "hardware_input": false, "audio_muted": AudioServer.is_bus_mute(0),
		"pov_size": POV_SIZE, "external_size": EXTERNAL_SIZE, "fps": FPS, "simulation_hz": 120,
		"duration_seconds": float(FRAME_COUNT - 1) / FPS, "external_caption": EXTERNAL_CAPTION,
		"external_direction_convention": "Camera-local axes: TOP +Y, BOTTOM -Y, LEFT -X, RIGHT +X. Each looks at the same carried geometry; source camera and player poses are unchanged.",
		"expedition_and_cursor_preserved": preserved, "original_inventory_contents_preserved": inventory_before == inventory_after,
		"original_inventory_sha256_before": inventory_before, "original_inventory_sha256_after": inventory_after,
		"source_sha256": hashes, "sources_unchanged_during_capture": unchanged,
		"sequences": sequences, "failures": failures,
	}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(json_value(manifest), "\t") + "\n")
	else: failures.append("Could not write choreography capture manifest")
	for failure in failures: push_error(failure)
	print("SWORD SHIELD CHOREOGRAPHY PREVIEW %s: six production actions, 204 POV and 96 same-arm external PNGs; %s" % ["PASS" if failures.is_empty() else "FAIL", output])
	quit(0 if failures.is_empty() else 1)


func _capture_action(output: String, action_id: String) -> Dictionary:
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var valid := begin_action(fixture, action_id)
	var folder := output.path_join(action_id)
	DirAccess.make_dir_recursive_absolute(folder.path_join("pov"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("external"))
	var frames: Array[Dictionary] = []
	var external: Array[Dictionary] = []
	for frame in range(FRAME_COUNT):
		if frame > 0: valid = advance_action(fixture, 1.0 / FPS) and valid
		select_view(fixture, "pov")
		var filename := "%s/pov/frame_%03d.png" % [action_id, frame]
		valid = await _save_pixels(viewport, output.path_join(filename)) and valid
		var inspection := inspect_action(fixture)
		inspection["frame"] = frame
		inspection["image"] = filename
		frames.append(inspection)
		if not bool(inspection.passed): valid = false
		if keyframes(action_id).has(frame):
			var player := fixture.player as DungeonPlayer
			var pose_before := player.get_first_person_motion_snapshot().duplicate(true)
			var hands_before := arm_landmarks(player)
			for view: String in EXTERNAL_VIEWS:
				valid = select_view(fixture, view) and valid
				var external_name := "%s/external/key_%03d_%s.png" % [action_id, frame, view]
				valid = await _save_pixels(viewport, output.path_join(external_name)) and valid
				var record := inspect_action(fixture)
				record["frame"] = frame
				record["image"] = external_name
				record["caption"] = EXTERNAL_CAPTION
				record["same_pose_as_pov"] = pose_before == player.get_first_person_motion_snapshot() and hands_before == arm_landmarks(player)
				if not bool(record.passed) or not bool(record.same_pose_as_pov): valid = false
				external.append(record)
			select_view(fixture, "pov")
	var summary := action_summary(fixture)
	valid = bool(summary.passed) and valid
	if not valid: failures.append("Production action or same-arm capture failed: " + action_id)
	(fixture.player as DungeonPlayer).cancel_sword_attack()
	viewport.queue_free()
	await process_frame
	return {"id": action_id, "passed": valid, "fps": FPS, "frame_count": frames.size(), "keyframes": keyframes(action_id), "summary": summary, "pov": frames, "external": external}


func _save_pixels(viewport: SubViewport, path: String) -> bool:
	# Only renderer warmup advances here; the production player scheduler is
	# disabled, so every external camera observes the exact same action instant.
	for warmup in range(3): await process_frame
	RenderingServer.force_draw(false)
	var pixels := viewport.get_texture().get_image()
	return pixels != null and not pixels.is_empty() and pixels.get_size() == viewport.size and pixels.save_png(path) == OK


static func create_viewport() -> SubViewport:
	var viewport := STUDIO.create_studio_viewport()
	viewport.name = "SwordShieldChoreographyViewport"
	viewport.use_taa = false
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	var fixture := PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	var external := Camera3D.new()
	external.name = "SamePlayerExternalCamera"
	external.cull_mask = (1 << 20) - 1
	external.projection = Camera3D.PROJECTION_ORTHOGONAL
	external.keep_aspect = Camera3D.KEEP_HEIGHT
	external.near = 0.01
	external.far = 50.0
	(fixture.stage as Node3D).add_child(external)
	fixture["viewport"] = viewport
	fixture["external_camera"] = external
	fixture["source_camera_parent"] = player.camera.get_parent().get_instance_id()
	fixture["source_camera_id"] = player.camera.get_instance_id()
	fixture["body_visible"] = player.player_body.visible
	fixture["stowed_torch_visible"] = player.torch_pivot.visible
	fixture["floor_visible"] = (fixture.stage as Node3D).get_node("ArmPreviewFloor").visible
	fixture["view"] = "pov"
	return fixture


static func begin_action(fixture: Dictionary, action_id: String) -> bool:
	if not ACTIONS.has(action_id): return false
	if not PREVIEW.configure_pose(fixture, "shield_idle"): return false
	STUDIO.configure_studio(fixture)
	var player := fixture.player as DungeonPlayer
	player.cancel_sword_attack()
	if not player.set_sword_attack_mode("cycle"): return false
	for tick in range(60): _step(player, STEP, action_id == "block_impact")
	fixture["action_id"] = action_id
	fixture["action_time"] = 0.0
	fixture["events"] = {}
	fixture["action_result"] = {}
	fixture["initial_health"] = player.health
	fixture["initial_stamina"] = player.stamina
	fixture["light_attack_cost"] = player.get_melee_stamina_cost(0.0)
	fixture["phases"] = {}
	fixture["max_impact"] = 0.0
	fixture["saw_blocking"] = player.blocking
	fixture["saw_lowered_after_raise"] = false
	fixture["valid"] = true
	if ATTACKS.has(action_id):
		fixture.action_result = player.begin_sword_attack(action_id)
		fixture.valid = bool(fixture.action_result.get("accepted", false))
	fixture.phases[str(player.get_first_person_motion_snapshot().phase)] = true
	select_view(fixture, "pov")
	return bool(fixture.valid) and int(player.get_first_person_motion_snapshot().visible_arm_count) == 2


static func advance_action(fixture: Dictionary, duration: float) -> bool:
	if not fixture.has("action_id") or not is_finite(duration) or duration < 0.0: return false
	var player := fixture.player as DungeonPlayer
	var action_id := str(fixture.action_id)
	var remaining := duration
	while remaining > 0.000001:
		var delta := minf(STEP, remaining)
		var now := float(fixture.action_time)
		var events: Dictionary = fixture.events
		if ATTACKS.has(action_id) and now >= 0.22 - 0.000001 and not events.has("release"):
			player.attack_release_requested = true
			events["release"] = now
		if action_id == "block_impact" and now >= 0.30 - 0.000001 and not events.has("impact"):
			fixture.action_result = player.receive_attack(18, player.global_position - player.global_basis.z * 2.0)
			events["impact"] = now
			fixture.valid = bool(fixture.valid) and bool(fixture.action_result.get("blocked", false)) and not bool(fixture.action_result.get("parried", false))
		var wants_block := action_id == "block_impact" or (action_id == "shield_raise" and now >= 0.10 - 0.000001 and now < 0.65 - 0.000001)
		_step(player, delta, wants_block)
		fixture.action_time = now + delta
		fixture.phases[str(player.get_first_person_motion_snapshot().phase)] = true
		fixture.max_impact = maxf(float(fixture.max_impact), player._shield_impact)
		fixture.saw_blocking = bool(fixture.saw_blocking) or player.blocking
		if action_id == "shield_raise" and now >= 0.65: fixture.saw_lowered_after_raise = not player.blocking
		if ATTACKS.has(action_id) and player.sword_attack_variant != action_id: fixture.valid = false
		remaining -= delta
	player.viewmodel_renderer.sync_view()
	return bool(fixture.valid)


static func _step(player: DungeonPlayer, delta: float, block_requested: bool) -> void:
	player.advance_action_timers(delta)
	player.advance_combat_state(delta, block_requested)
	player._update_viewmodel(delta)
	player._resolve_active_attack()
	player._update_torch(delta)


static func keyframes(action_id: String) -> Array[int]:
	match action_id:
		"shield_raise": return [0, 5, 12, 27]
		"block_impact": return [0, 10, 11, 18]
		"ready": return [0, 11, 22, 33]
	return [0, 6, 11, 17]


static func select_view(fixture: Dictionary, view: String) -> bool:
	if view != "pov" and not EXTERNAL_VIEWS.has(view): return false
	var player := fixture.player as DungeonPlayer
	var viewport := fixture.viewport as SubViewport
	var floor_node := (fixture.stage as Node3D).get_node("ArmPreviewFloor") as Node3D
	if view == "pov":
		viewport.size = POV_SIZE
		player.player_body.visible = bool(fixture.body_visible)
		player.torch_pivot.visible = bool(fixture.stowed_torch_visible)
		floor_node.visible = bool(fixture.floor_visible)
		player.camera.make_current()
	else:
		viewport.size = EXTERNAL_SIZE
		player.player_body.visible = false
		player.torch_pivot.visible = false
		floor_node.visible = false
		var external := fixture.external_camera as Camera3D
		var points := geometry_points(player)
		if points.is_empty(): return false
		var bounds := AABB(points[0], Vector3.ZERO)
		for point in points: bounds = bounds.expand(point)
		var center := bounds.get_center()
		var local_axis := Vector3.UP if view == "top" else Vector3.DOWN if view == "bottom" else Vector3.LEFT if view == "left" else Vector3.RIGHT
		var axis := player.camera.global_basis * local_axis
		var up := player.camera.global_basis * (Vector3.FORWARD if view == "top" else Vector3.BACK if view == "bottom" else Vector3.UP)
		external.global_position = center + axis * (bounds.size.length() + 2.0)
		external.look_at(center, up)
		var half_width := 0.0
		var half_height := 0.0
		for point in points:
			var local := external.global_basis.inverse() * (point - center)
			half_width = maxf(half_width, absf(local.x))
			half_height = maxf(half_height, absf(local.y))
		external.size = maxf(0.8, maxf(half_height, half_width / (float(EXTERNAL_SIZE.x) / EXTERNAL_SIZE.y)) * 2.25 + 0.12)
		external.make_current()
	fixture.view = view
	player.viewmodel_renderer.sync_view()
	return true


static func geometry_points(player: DungeonPlayer) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for carried: Node3D in [player.weapon_arm, player.shield_arm, player.sword_visual_root, player.shield_model]:
		for mesh: MeshInstance3D in carried.find_children("*", "MeshInstance3D", true, false):
			if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
			var bounds := mesh.get_aabb().grow(0.025)
			for corner in range(8): points.append(mesh.global_transform * bounds.get_endpoint(corner))
	var arms := arm_landmarks(player)
	for side: String in arms:
		var landmarks: Dictionary = arms[side]
		for name: String in ["wrist", "elbow", "shoulder"]:
			if landmarks.has(name): points.append(landmarks[name] as Vector3)
	return points


static func arm_landmarks(player: DungeonPlayer) -> Dictionary:
	var result := {}
	for arm: Node3D in [player.weapon_arm, player.shield_arm]:
		if bool(arm.get_meta("imported_static_grip", false)):
			var imported := STUDIO.imported_arm_geometry(arm)
			imported["node_id"] = arm.get_instance_id()
			imported["node_path"] = str(arm.get_path())
			imported["continuous_skin"] = false
			imported["bones"] = []
			if arm.has_method("get_combat_grip_snapshot"): imported["grip"] = arm.call("get_combat_grip_snapshot")
			result["right" if arm == player.weapon_arm else "left"] = imported
			continue
		var forearm := arm.get("_forearm") as Node3D
		var upper := arm.get("_upper_arm") as Node3D
		var skeleton := arm.get("skeleton") as Skeleton3D
		var data := {"node_id": arm.get_instance_id(), "node_path": str(arm.get_path()), "wrist": arm.global_position, "wrist_transform": arm.global_transform, "continuous_skin": bool(arm.get_meta("continuous_skin", false)), "bones": []}
		if forearm != null: data["elbow"] = forearm.to_global(Vector3(0, 0, 0.26))
		if upper != null: data["shoulder"] = upper.to_global(Vector3(0, 0, 0.60))
		if skeleton != null:
			for bone in range(skeleton.get_bone_count()):
				data.bones.append({"name": skeleton.get_bone_name(bone), "local_pose": skeleton.get_bone_pose(bone), "world_pose": skeleton.global_transform * skeleton.get_bone_global_pose(bone)})
		if arm.has_method("get_combat_grip_snapshot"): data["grip"] = arm.call("get_combat_grip_snapshot")
		result["right" if arm == player.weapon_arm else "left"] = data
	return result


static func inspect_action(fixture: Dictionary) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var viewport := fixture.viewport as SubViewport
	var camera := viewport.get_camera_3d()
	var view := str(fixture.view)
	var production := player.get_first_person_motion_snapshot()
	var input_disabled := viewport.gui_disable_input and not viewport.physics_object_picking and not player.is_processing() and not player.is_physics_processing() and not player.is_processing_input() and not player.is_processing_unhandled_input()
	var camera_preserved := player.camera.get_instance_id() == int(fixture.source_camera_id) and player.camera.get_parent().get_instance_id() == int(fixture.source_camera_parent)
	var correct_camera: bool = camera == player.camera if view == "pov" else camera == fixture.external_camera and (camera.cull_mask & (1 << 19)) != 0
	var correct_overlay: bool = player.viewmodel_renderer.overlay.visible == (view == "pov")
	var finite := player.weapon_pivot.global_transform.is_finite() and player.shield_pivot.global_transform.is_finite()
	return {"passed": input_disabled and camera_preserved and correct_camera and correct_overlay and finite and int(production.visible_arm_count) == 2,
		"action": str(fixture.action_id), "time_seconds": float(fixture.action_time), "view": view, "production": production,
		"health": player.health, "stamina": player.stamina, "blocking": player.blocking, "block_time": player.block_time, "impact_remaining": player._shield_impact,
		"arm_landmarks": arm_landmarks(player), "sword_transform": player.sword_visual_root.global_transform, "shield_transform": player.shield_model.global_transform,
		"source_camera_transform": player.camera.global_transform, "view_camera_transform": camera.global_transform, "view_camera_projection": camera.projection, "view_camera_size": camera.size,
		"image_size": viewport.size, "camera_parent_preserved": camera_preserved, "input_disabled": input_disabled, "equipment_overlay_visible": player.viewmodel_renderer.overlay.visible,
		"static_body_visible": player.player_body.visible, "studio_floor_visible": (fixture.stage as Node3D).get_node("ArmPreviewFloor").visible}


static func action_summary(fixture: Dictionary) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var id := str(fixture.action_id)
	var stamina_spent := float(fixture.initial_stamina) - player.stamina
	var health_lost := float(fixture.initial_health) - player.health
	var valid := bool(fixture.valid) and float(fixture.action_time) >= 1.1 - 0.00001
	if ATTACKS.has(id):
		for phase: String in ["windup", "active", "recovery", "ready"]: valid = valid and fixture.phases.has(phase)
		valid = valid and is_equal_approx(stamina_spent, float(fixture.light_attack_cost)) and player.sword_attack_variant == id
	elif id == "shield_raise":
		valid = valid and bool(fixture.saw_blocking) and bool(fixture.saw_lowered_after_raise) and not player.blocking and is_zero_approx(health_lost) and is_zero_approx(stamina_spent)
	elif id == "block_impact":
		valid = valid and bool(fixture.action_result.get("blocked", false)) and not bool(fixture.action_result.get("parried", false)) and float(fixture.max_impact) > 0.0 and is_zero_approx(health_lost) and is_equal_approx(stamina_spent, 18 * 1.18)
	else:
		valid = valid and player.combat_state == DungeonPlayer.CombatState.READY and not player.blocking and is_zero_approx(health_lost) and is_zero_approx(stamina_spent)
	return {"passed": valid, "phases": fixture.phases, "events": fixture.events, "action_result": fixture.action_result, "stamina_spent": stamina_spent, "health_lost": health_lost, "max_impact": fixture.max_impact}


static func source_hashes() -> Dictionary:
	var paths: Array = PREVIEW.SOURCE_FILES.duplicate()
	paths.append_array(STUDIO.SOURCES)
	paths.append_array(EXTRA_SOURCES)
	for filename: String in DirAccess.get_files_at(REFERENCE_DIRECTORY):
		if filename.ends_with(".png"): paths.append(REFERENCE_DIRECTORY.path_join(filename))
	var hashes := {}
	for path: String in paths: hashes[path] = FileAccess.get_sha256(path)
	return hashes


static func json_value(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Vector3 or value is Vector3i: return [value.x, value.y, value.z]
	if value is Quaternion: return [value.x, value.y, value.z, value.w]
	if value is Basis: return [json_value(value.x), json_value(value.y), json_value(value.z)]
	if value is Transform3D: return {"basis": json_value(value.basis), "origin": json_value(value.origin)}
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)] = json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for entry in value: result.append(json_value(entry))
		return result
	return value
