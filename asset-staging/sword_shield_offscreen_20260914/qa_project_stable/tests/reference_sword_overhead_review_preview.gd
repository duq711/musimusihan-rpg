extends SceneTree
## A single authored-time visual review using actual production player meshes.
## It does not exercise gameplay attack clocks or install an incomplete delivery.

const DATA := preload("res://tests/reference_sword_overhead_review_data.gd")
const EXISTING := preload("res://tests/reference_sword_motion_preview.gd")
const ARM := preload("res://scripts/sword_long_grip_visual.gd")
const PRODUCTION := preload("res://scripts/reference_sword_motion.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/reference_sword_overhead_review"
const IMAGE_SIZE := Vector2i(640, 360)
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Single overhead review requires the audited embedded renderer.")
		quit(2)
		return
	var review := DATA.read_review(OS.get_environment("OVERHEAD_REVIEW_MANIFEST").strip_edges())
	if not bool(review.get("ok", false)):
		push_error(str(review.get("error", "Review data unavailable.")))
		quit(2)
		return
	var iteration := OS.get_environment("OVERHEAD_REVIEW_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("OVERHEAD_REVIEW_ITERATION must specify a new plain folder name.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output):
		push_error("Existing review frames are preserved: " + output)
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Single-clip review cannot replace an active test-room session.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output.path_join("sequences/overhead")) != OK:
		push_error("Cannot create a new overhead review output folder.")
		quit(2)
		return
	var original := ExpeditionSession.capture_snapshot()
	var original_cursor := Input.mouse_mode
	var original_pause := paused
	var original_mute := AudioServer.is_bus_mute(0)
	var original_sources := source_hashes()
	var loader_available := PRODUCTION.is_available()
	var loader_error := PRODUCTION.get_load_error()
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	var ready := prepare_fixture(fixture)
	if not ready:
		failures.append("Could not prepare actual sword and shield meshes.")
	var immutable := gameplay_state(player)
	var frames: Array[Dictionary] = []
	var stretched_frames := 0
	if ready:
		for frame in range(DATA.FRAME_COUNT):
			var time := DATA.frame_time(frame)
			var metrics := apply_review_pose(player, DATA.sample(review, time, "sword"), DATA.sample(review, time, "shield"), DATA.sample_right_arm(review, time))
			if bool(metrics.get("arm_length_outside_source_range", false)):
				stretched_frames += 1
			for warmup in range(2): await process_frame
			RenderingServer.force_draw(false)
			var pixels := viewport.get_texture().get_image()
			var relative := "sequences/overhead/frame_%03d.png" % frame
			if pixels == null or pixels.is_empty() or pixels.get_size() != IMAGE_SIZE or pixels.save_png(output.path_join(relative)) != OK:
				failures.append("Could not save actual overhead review frame: " + relative)
			if gameplay_state(player) != immutable:
				failures.append("Authored-time review changed gameplay state at frame %d." % frame)
			if float(metrics.get("grip_error", 1.0)) > 0.00001 or not bool(metrics.get("finite", false)):
				failures.append("Actual arm/weapon geometry is not finite and attached at frame %d." % frame)
			if float(metrics.get("authored_wrist_error", 1.0)) >= DATA.WRIST_TOLERANCE_METERS:
				failures.append("Authored wrist differs from the actual glove by at least 1 mm at frame %d." % frame)
			if float(metrics.get("authored_joint_fit_error", 1.0)) >= DATA.WRIST_TOLERANCE_METERS:
				failures.append("Actual sleeve joints differ from authored shoulder/elbow by at least 1 mm at frame %d." % frame)
			if bool(metrics.get("arm_length_outside_source_range", true)):
				failures.append("Authored right arm exceeds the declared +/-1%% length tolerance at frame %d." % frame)
			frames.append({"frame": frame, "time_seconds": time, "image": relative,
				"arm_measurements": metrics, "source_motion": "external_overhead_review",
				"gameplay_timing_remapped": false})
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	AudioServer.set_bus_mute(0, original_mute)
	var preserved := ExpeditionSession.capture_snapshot() == original and Input.mouse_mode == original_cursor and paused == original_pause
	var sources_preserved := source_hashes() == original_sources
	var loader_preserved := PRODUCTION.is_available() == loader_available and PRODUCTION.get_load_error() == loader_error
	if not preserved: failures.append("Original expedition, cursor or pause state changed.")
	if not sources_preserved: failures.append("Production files changed during the isolated review.")
	if not loader_preserved: failures.append("Single overhead review changed production loader availability.")
	if FileAccess.get_sha256(str(review.input_path)) != str(review.input_sha256):
		failures.append("External review input changed during capture.")
	var capture := {
		"preview_kind": "overhead_only_authored_timing_review", "incomplete_delivery": true,
		"gameplay_timing_remapped": false, "gameplay_attack_executed": false,
		"arm_playback": "authored_right_arm_joints_on_original_meshes",
		"authored_right_arm_joints_replayed": true,
		"explicit_part_bases_replayed": false,
		"quality_approval": false,
		"arm_review_note": "After the production grip setup, explicit Windows shoulder/elbow keys drive the original sword arm fit_arm. Wrist keys are checked against the actual glove. Part bases or a replacement rig are not inferred. Shield arm still uses production fitting.",
		"kinematic_thresholds": {"wrist_error_meters_less_than": DATA.WRIST_TOLERANCE_METERS,
			"upper_length_meters": DATA.UPPER_LENGTH_METERS, "forearm_length_meters": DATA.FOREARM_LENGTH_METERS,
			"length_relative_tolerance": DATA.LENGTH_RELATIVE_TOLERANCE},
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"display_driver": DisplayServer.get_name(), "desktop_capture": false,
		"hardware_input_sampled_or_injected": false, "image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"fps": DATA.FPS, "duration_seconds": DATA.DURATION, "frame_count": frames.size(),
		"camera_vertical_fov_degrees": 76.0, "source_clock": "unremapped_authored_seconds",
		"input": review.input_path, "input_sha256": review.input_sha256,
		"declared_windows_provenance": review.declared_provenance,
		"production_motion_available_before": loader_available, "production_loader_unchanged": loader_preserved,
		"source_sha256": original_sources, "sources_unchanged_during_capture": sources_preserved,
		"expedition_and_cursor_preserved": preserved,
		"arm_length_diagnostic_frames": stretched_frames,
		"sequences": [{"id": "overhead", "fps": DATA.FPS, "duration_seconds": DATA.DURATION, "frame_count": frames.size(), "frames": frames}],
		"failures": failures,
	}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(capture, "\t") + "\n")
	else: failures.append("Could not save overhead review capture manifest.")
	for failure in failures: push_error(failure)
	print("REFERENCE SWORD OVERHEAD REVIEW PREVIEW %s: authored 1.55s at 60fps, explicit right-arm joints on original meshes, no gameplay remap; %s" % ["PASS" if failures.is_empty() else "FAIL", output])
	quit(0 if failures.is_empty() else 1)


static func create_viewport() -> SubViewport:
	var viewport := EXISTING.create_viewport()
	viewport.name = "IsolatedOverheadAuthoredTimeReview"
	viewport.size = IMAGE_SIZE
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	return EXISTING.populate_viewport(viewport)


static func prepare_fixture(fixture: Dictionary) -> bool:
	if not EXISTING.ARM_PREVIEW.configure_pose(fixture, "idle"):
		return false
	var player := fixture.player as DungeonPlayer
	player.set_torch_enabled(false)
	player.position = Vector3(0, 0.9, 2.4)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.camera.position = Vector3.ZERO
	player.head.position.y = 0.67
	player._pitch = 0.0
	player.velocity = Vector3.ZERO
	player.camera.fov = 76.0
	player.cancel_sword_attack()
	return player._has_shield_equipped() and player.weapon_arm.get_meta("imported_static_grip", false)


static func apply_review_pose(player: DungeonPlayer, sword: Transform3D, shield: Transform3D, authored_arm: Dictionary) -> Dictionary:
	if not authored_arm.has_all(["shoulder", "elbow", "wrist"]):
		return {"finite": false, "error": "Explicit authored right-arm joints are required."}
	player.weapon_pivot.transform = sword
	player.shield_pivot.transform = shield
	player._update_character_arms()
	# Review-only adapter: preserve the glove/weapon and original sleeve meshes,
	# but replace the production solver's shoulder/elbow with authored joints.
	# Any future explicit part-basis or rig adapter belongs at this boundary.
	player.weapon_arm.call("fit_arm", player.camera.global_transform * (authored_arm.shoulder as Vector3),
		player.camera.global_transform * (authored_arm.elbow as Vector3), true)
	player.viewmodel_renderer.sync_view()
	var arm_snapshot: Dictionary = player.weapon_arm.call("get_snapshot")
	var wrist := player.weapon_arm.to_global(ARM.REST_WRIST)
	var elbow := player.weapon_arm.to_global(arm_snapshot.fitted_elbow)
	var shoulder := player.weapon_arm.to_global(arm_snapshot.fitted_shoulder)
	var upper := shoulder.distance_to(elbow)
	var forearm := elbow.distance_to(wrist)
	var rest_upper := ARM.REST_SHOULDER.distance_to(ARM.REST_ELBOW)
	var rest_forearm := ARM.REST_ELBOW.distance_to(ARM.REST_WRIST)
	var wrist_error := player.camera.to_local(wrist).distance_to(authored_arm.wrist)
	var fit_error := maxf(player.camera.to_local(elbow).distance_to(authored_arm.elbow),
		player.camera.to_local(shoulder).distance_to(authored_arm.shoulder))
	var snapshot := player.get_first_person_motion_snapshot()
	var contacts: Dictionary = snapshot.hand_contacts.get("sword", {})
	return {"finite": sword.is_finite() and shield.is_finite() and wrist.is_finite() and elbow.is_finite() and shoulder.is_finite(),
		"grip_error": float(contacts.get("error", 1.0)),
		"authored_wrist_error": wrist_error,
		"authored_joint_fit_error": fit_error,
		"right_shoulder_camera": _vector(player.camera.to_local(shoulder)),
		"right_elbow_camera": _vector(player.camera.to_local(elbow)),
		"right_wrist_camera": _vector(player.camera.to_local(wrist)),
		"upper_length": upper, "forearm_length": forearm,
		"source_upper_length": rest_upper, "source_forearm_length": rest_forearm,
		"arm_length_outside_source_range": absf(upper - DATA.UPPER_LENGTH_METERS) > DATA.UPPER_LENGTH_METERS * DATA.LENGTH_RELATIVE_TOLERANCE
			or absf(forearm - DATA.FOREARM_LENGTH_METERS) > DATA.FOREARM_LENGTH_METERS * DATA.LENGTH_RELATIVE_TOLERANCE}


static func gameplay_state(player: DungeonPlayer) -> Dictionary:
	return {"health": player.health, "stamina": player.stamina, "combat_state": player.combat_state,
		"state_time": player.state_time, "velocity": player.velocity, "position": player.position,
		"camera": player.camera.transform, "head": player.head.transform,
		"motion_clock": player._motion_clock, "equipment": player.inventory_model.equipment.duplicate(true),
		"original_arm_mesh_resources": arm_mesh_ids(player),
		"automatic_physics": player.is_physics_processing(), "automatic_input": player.is_processing_unhandled_input()}


static func arm_mesh_ids(player: DungeonPlayer) -> Array[int]:
	var ids: Array[int] = []
	for part in player.weapon_arm.find_children("*", "MeshInstance3D", true, false):
		var mesh := part as MeshInstance3D
		if mesh.mesh != null: ids.append(mesh.mesh.get_instance_id())
	return ids


static func source_hashes() -> Dictionary:
	var hashes := {}
	for path: String in ["res://scripts/player.gd", "res://scripts/reference_sword_motion.gd",
			"res://scripts/sword_long_grip_visual.gd", "res://scripts/sword_shield_arm_visual.gd",
			"res://tests/reference_sword_overhead_review_data.gd", "res://tests/reference_sword_overhead_review_preview.gd",
			"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
			PRODUCTION.MANIFEST_PATH]:
		hashes[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return hashes


static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
