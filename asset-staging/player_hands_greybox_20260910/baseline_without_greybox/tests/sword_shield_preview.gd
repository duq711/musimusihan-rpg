extends SceneTree
## Four real production states, using an input-free embedded Vulkan viewport.
const PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const POSES := ["idle", "guard", "impact", "riposte"]
const SOURCES := ["res://assets/ai/sword_shield/weapon_material_atlas_v2.png.import", "res://assets/ai/sword_shield/weapon_material_normal_v2.png.import", "res://assets/ai/sword_shield/weapon_material_normal_v2.png", "res://assets/ai/sword_shield/weapon_material_atlas_v2.png", "res://scripts/player.gd", "res://scripts/sword_shield_arm_visual.gd", "res://scripts/first_person_motion.gd", "res://scripts/first_person_renderer.gd", "res://assets/3d/player/sword_shield/left_arm.glb", "res://assets/3d/player/sword_shield/right_arm.glb", "res://assets/3d/player/sword_shield/longsword.glb", "res://assets/3d/player/sword_shield/round_shield.glb", "res://tests/sword_shield_preview.gd", "res://assets/3d/player/sword_shield/textures/leather_normal.jpg", "res://assets/3d/player/sword_shield/textures/linen_albedo.jpg", "res://assets/3d/player/sword_shield/textures/linen_normal.jpg", "res://assets/ai/sword_shield/worn_charcoal_leather.png", "res://assets/ai/sword_shield/weathered_hand_skin.png", "res://assets/3d/player/sword_shield/left_arm.glb.import", "res://assets/3d/player/sword_shield/right_arm.glb.import", "res://assets/3d/player/sword_shield/longsword.glb.import", "res://assets/3d/player/sword_shield/round_shield.glb.import", "res://assets/ai/materials/wet_flagstone.png", "res://assets/3d/abandoned_mine/textures/rough_wood_albedo_2k.jpg", "res://assets/3d/abandoned_mine/textures/rough_wood_normal_gl_2k.jpg"]
var failures: Array[String] = []

func _init() -> void: call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded": quit(2); return
	var iteration := OS.get_environment("SWORD_SHIELD_QA_ITERATION")
	if not iteration.is_valid_filename() or iteration.begins_with("."): quit(2); return
	var output := ProjectSettings.globalize_path("res://artifacts/visual_qa/sword_shield/" + iteration)
	if DirAccess.dir_exists_absolute(output): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var fingerprint := PREVIEW.inventory_fingerprint(snapshot.inventory)
	var cursor := Input.mouse_mode
	var hashes := {}
	var source_paths: Array = PREVIEW.SOURCE_FILES.duplicate()
	source_paths.append_array(SOURCES)
	for source in source_paths:
		hashes[source] = FileAccess.get_sha256(source)
		if str(hashes[source]).length() != 64: failures.append("Missing capture dependency " + source)
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active: quit(2); return
	sandbox.begin()
	var captures: Array[Dictionary] = []
	var hand_study := OS.get_environment("SWORD_SHIELD_QA_HAND_STUDY") == "1"
	var shots: Array = ["study_30", "study_70", "study_110", "study_140"] if hand_study else POSES
	for pose_id in shots:
		var viewport := create_studio_viewport()
		root.add_child(viewport)
		var fixture := PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		var player := fixture.player as DungeonPlayer
		var valid := configure_pose(fixture, "guard" if hand_study else pose_id)
		configure_studio(fixture)
		if hand_study: study_hand_rotation(player, shots.find(pose_id))
		player.viewmodel_renderer.sync_view()
		for frame in 12: await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(pose_id + ".png")) != OK: valid = false
		var tip := player.sword_visual_root.find_child("BladeTip", true, false) as Node3D
		var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
		var result := {"pose": pose_id, "passed": valid, "image": pose_id + ".png", "production": player.get_first_person_motion_snapshot(), "sword_tip": str(player.camera.unproject_position(tip.global_position)), "sword_grip": str(player.camera.unproject_position(grip.global_position)), "shield_center": str(player.camera.unproject_position(player.shield_model.global_position))}
		result["arm_landmarks"] = {}
		for arm: Node3D in [player.weapon_arm, player.shield_arm]:
			if bool(arm.get_meta("imported_static_grip", false)):
				var imported := imported_arm_geometry(arm)
				var screen_bounds: Array[String] = []
				for corner: Vector3 in imported.source_forearm_bounds_world:
					screen_bounds.append(str(player.camera.unproject_position(corner)))
				imported["source_forearm_bounds_screen"] = screen_bounds
				result.arm_landmarks[str(arm.get_meta("hand_side"))] = imported
				continue
			var forearm := arm.get("_forearm") as Node3D
			result.arm_landmarks[str(arm.get_meta("hand_side"))] = {"wrist": str(player.camera.unproject_position(arm.global_position)), "elbow": str(player.camera.unproject_position(forearm.to_global(Vector3(0,0,0.26)))), "forearm_wrist": str(player.camera.unproject_position(forearm.global_position))}
		captures.append(result)
		if not valid: failures.append("Invalid production pose " + pose_id)
		viewport.queue_free()
		await process_frame
	var sequence: Array[Dictionary] = []
	if OS.get_environment("SWORD_SHIELD_QA_SEQUENCE") == "1": sequence = await _capture_sequence(output)
	sandbox.finish()
	var preserved := snapshot == ExpeditionSession.capture_snapshot() and fingerprint == PREVIEW.inventory_fingerprint(snapshot.inventory) and Input.mouse_mode == cursor
	if not preserved: failures.append("Original session or cursor changed")
	for source in source_paths:
		if hashes[source] != FileAccess.get_sha256(source): failures.append("Source changed during capture")
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"actual_renderer": RenderingServer.get_current_rendering_driver_name(), "display_driver": DisplayServer.get_name(), "source_sha256": hashes, "session_and_cursor_preserved": preserved, "captures": captures, "sequence_fps": 20, "sequence": sequence, "reference_sha256": FileAccess.get_sha256("res://../asset-staging/sword_shield_first_person/reference.png"), "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	print("SWORD SHIELD PREVIEW %s: %s; %s" % ["PASS" if failures.is_empty() else "FAIL", "four diagnostic hand rotations" if hand_study else "four production poses", output])
	quit(0 if failures.is_empty() else 1)


static func imported_arm_geometry(arm: Node3D) -> Dictionary:
	# This imported arm has no rig. Record the actual mesh bounds instead of
	# interpreting the old skinned arm's local offsets as anatomical joints.
	var data := {"imported_static_grip": true, "arm_transform": arm.global_transform, "source_forearm_bounds_world": []}
	var forearm := arm.get("_forearm") as MeshInstance3D
	if forearm != null and forearm.mesh != null:
		var bounds := forearm.get_aabb()
		data["source_forearm_node"] = str(forearm.get_path())
		data["source_forearm_transform"] = forearm.global_transform
		data["source_forearm_bounds_local"] = {"position": bounds.position, "size": bounds.size}
		for corner in range(8):
			data.source_forearm_bounds_world.append(forearm.global_transform * bounds.get_endpoint(corner))
	return data


static func study_hand_rotation(player: DungeonPlayer, index: int) -> void:
	# Explicit diagnostic contact orientations, never used in gameplay or the
	# final production captures. The imported fist keeps its authored grip;
	# this rig-orientation study only rotates arms that actually have joints.
	if not bool(player.weapon_arm.get_meta("imported_static_grip", false)):
		var right_basis := player.weapon_pivot.global_basis * Basis.from_euler(Vector3(0, deg_to_rad([30,70,110,140][index]), PI/2))
		var grip := player.sword_visual_root.find_child("HandGrip", true, false) as Node3D
		player._place_hand_contact(player.weapon_arm, grip.global_position, right_basis, "study_sword")
	var top := player.shield_model.find_child("RearGripTop", true, false) as Node3D
	var bottom := player.shield_model.find_child("RearGripBottom", true, false) as Node3D
	var axis := (top.global_position-bottom.global_position).normalized()
	var normal := player.shield_pivot.global_basis.z.normalized()
	var angle := deg_to_rad([-30,-50,-70,-85][index])
	var back := (axis.cross(-normal)*cos(angle)+normal*sin(angle)).normalized()
	var contact := player.shield_model.find_child("RearGrip", true, false) as Node3D
	player._place_hand_contact(player.shield_arm, contact.global_position, Basis(-axis,back.cross(-axis).normalized(),back), "shield")
	for arm: Node3D in [player.weapon_arm,player.shield_arm]:
		if bool(arm.get_meta("imported_static_grip", false)): continue
		var side := float(arm.get_meta("hand_side"))
		var shoulder := player.camera.to_global(Vector3(side*.29,-.34,.10))
		var elbow := DungeonPlayer.MOTION.elbow(shoulder,arm.global_position,player.camera.global_basis*Vector3(side*.65,-.85,.14))
		arm.call("fit_arm",shoulder,elbow)


static func configure_pose(fixture: Dictionary, pose_id: String) -> bool:
	if not POSES.has(pose_id): return false
	if not PREVIEW.configure_pose(fixture, "shield_idle"): return false
	var player := fixture.player as DungeonPlayer
	if pose_id != "idle":
		player.blocking = true
		player.block_time = 0.1
		PREVIEW._sample_view(player, 0.35)
	if pose_id in ["impact", "riposte"]:
		var result := player.receive_attack(18, player.global_position + Vector3(0, 0, -2))
		if not result.get("blocked", false): return false
		PREVIEW._sample_view(player, 0.05)
	if pose_id == "riposte":
		player.blocking = false
		player._try_begin_attack()
		# Let the real windup carry the shield to the flank before the cut;
		# an immediate commit would photograph a skipped transition.
		player.state_time = 0.24
		PREVIEW._sample_view(player, 0.24, true)
		player._commit_attack()
		player.state_time = 0.12
		PREVIEW._sample_view(player, 0.16)
	return player.get_first_person_motion_snapshot().visible_arm_count == 2


static func create_studio_viewport() -> SubViewport:
	var viewport := PREVIEW.create_viewport()
	# A room's ground bounce, represented by an actual light in the comparison
	# scene. The equipment pass discovers and mirrors it just like the key.
	var bounce := DirectionalLight3D.new()
	bounce.name = "StudioGroundBounce"
	bounce.rotation_degrees = Vector3(20, 10, 0)
	bounce.light_color = Color(0.77, 0.75, 0.71)
	bounce.light_energy = 0.50
	bounce.shadow_enabled = false
	viewport.add_child(bounce)
	return viewport


static func configure_studio(fixture: Dictionary) -> void:
	var stage := fixture.stage as Node3D
	var player := fixture.player as DungeonPlayer
	player._pitch = -0.105
	player.head.rotation.x = player._pitch
	var environment := stage.find_child("*", false, false) as WorldEnvironment
	if environment:
		environment.environment.background_color = Color("#101415")
		environment.environment.ambient_light_color = Color(0.62, 0.66, 0.70)
		environment.environment.ambient_light_energy = 0.40
		environment.environment = environment.environment.duplicate()
	var floor_node := stage.get_node("ArmPreviewFloor") as MeshInstance3D
	(floor_node.mesh as PlaneMesh).size = Vector2(80,80)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load("res://assets/ai/materials/wet_flagstone.png")
	material.albedo_color = Color(0.65, 0.60, 0.53)
	material.uv1_scale = Vector3(24,24,24)
	material.roughness = 0.92
	floor_node.material_override = material
	for key: DirectionalLight3D in stage.find_children("*", "DirectionalLight3D", false, false):
		key.rotation_degrees = Vector3(-40, 35, 0)
		key.light_color = Color(0.91, 0.91, 0.88)
		key.light_energy = 1.2


func _capture_sequence(output: String) -> Array[Dictionary]:
	var viewport := create_studio_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var valid := configure_pose(fixture, "idle")
	configure_studio(fixture)
	var player := fixture.player as DungeonPlayer
	var folder := output.path_join("sequence")
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	fixture["sequence_time"] = 0.0
	fixture["sequence_events"] = {}
	for frame in 53:
		if frame > 0: valid = advance_sequence(fixture, 0.05) and valid
		for warmup in 3: await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var filename := "frame_%03d.png" % frame
		if pixels == null or pixels.is_empty() or pixels.save_png(folder.path_join(filename)) != OK: valid = false
		frames.append({"image": "sequence/" + filename, "time": frame * 0.05, "production": player.get_first_person_motion_snapshot(), "health": player.health, "stamina": player.stamina})
	if not valid: failures.append("Production guard/impact/counterattack sequence failed")
	viewport.queue_free()
	await process_frame
	return frames


static func advance_sequence(fixture: Dictionary, duration: float) -> bool:
	var player := fixture.player as DungeonPlayer
	var remaining := duration
	var valid := true
	var events: Dictionary = fixture.sequence_events
	while remaining > 0.00001:
		var delta := minf(remaining, 1.0/120.0)
		var now := float(fixture.sequence_time)
		if now >= 0.35 and not events.has("guard"):
			events.guard = true
			player.blocking = true
			player.block_time = 0.0
		if now >= 0.75 and not events.has("impact"):
			events.impact = true
			var hit := player.receive_attack(18, player.global_position + Vector3(0,0,-2))
			valid = bool(hit.get("blocked", false)) and valid
		if now >= 1.15 and not events.has("counter"):
			events.counter = true
			player.blocking = false
			player._try_begin_attack()
		if now >= 1.50 and not events.has("release"):
			events.release = true
			player.attack_release_requested = true
		player.advance_action_timers(delta)
		player.advance_combat_state(delta, now >= 0.35 and now < 1.15)
		player._update_viewmodel(delta)
		player._resolve_active_attack()
		player._update_stamina(delta)
		fixture.sequence_time = now + delta
		remaining -= delta
	player.viewmodel_renderer.sync_view()
	return valid
