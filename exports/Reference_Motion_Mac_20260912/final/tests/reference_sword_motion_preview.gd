extends SceneTree
## Actual production sword rig and authored trajectories, rendered only
## through the audited embedded driver. Automatic player/input processing is off;
## explicit 60 Hz production movement calls still use real floor collisions.
const ARM_PREVIEW := preload("res://tests/player_arm_preview.gd")
const MOTION_PREVIEW := preload("res://tests/first_person_motion_preview.gd")
const REFERENCE_MOTION := preload("res://scripts/reference_sword_motion.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/reference_sword_motion"
const FPS := 60
const PHYSICS_FPS := 60
const STEP := 1.0 / float(PHYSICS_FPS)
const SEQUENCE_IDS := ["idle", "walk", "run", "jump", "right_diagonal", "left_reverse", "overhead"]
const CONTACT_IDS := ["idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"]
const ADDITIONAL_SOURCES := [
	"res://scripts/reference_sword_motion.gd",
	"res://scripts/reference_sword_arm.gd",
	"res://scripts/sword_shield_choreography.gd",
	"res://assets/animations/reference_sword_motion/motion_manifest.json",
	"res://tests/reference_sword_motion_preview.gd",
]
var failures: Array[String] = []
var sequences: Array[Dictionary] = []
var selected: Dictionary = {}
var output_path := ""
var partial_overhead := false
var motion_only := false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Reference sword captures require the audited tests/run_embedded_preview.sh embedded renderer.")
		quit(2)
		return
	if not REFERENCE_MOTION.is_available():
		push_error("authored reference motion must load before visual QA: " + REFERENCE_MOTION.get_load_error())
		quit(2)
		return
	var requested_scope := OS.get_environment("REFERENCE_SWORD_MOTION_QA_SCOPE")
	motion_only = requested_scope == "overhead_motion_only"
	partial_overhead = requested_scope in ["overhead", "overhead_motion_only"]
	if partial_overhead and (not REFERENCE_MOTION.has_right_arm("overhead") or not REFERENCE_MOTION.has_track("overhead", "shield")):
		push_error("Partial overhead QA requires the actual overhead sword, shield and right-arm delivery.")
		quit(2)
		return
	if not partial_overhead and (not REFERENCE_MOTION.full_delivery_available() or not REFERENCE_MOTION.right_arm_available()):
		push_error("Final visual QA requires the v2 authored right arm, not only sword pivots.")
		quit(2)
		return
	var iteration := OS.get_environment("REFERENCE_SWORD_MOTION_QA_ITERATION").strip_edges()
	if iteration.is_empty():
		iteration = "iteration_01"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("REFERENCE_SWORD_MOTION_QA_ITERATION must be a plain new folder name.")
		quit(2)
		return
	output_path = ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output_path):
		push_error("Existing reference sword captures are preserved: " + output_path)
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Visual QA must not replace an active test-room expedition.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(output_path) != OK:
		push_error("Could not create reference sword capture folder.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	var old_mute := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var old_ticks := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = PHYSICS_FPS
	var initial_mouse := Input.mouse_mode
	var initial_snapshot := ExpeditionSession.capture_snapshot()
	var original_inventory := initial_snapshot.get("inventory") as ExpeditionInventory
	var initial_inventory_hash := MOTION_PREVIEW.inventory_fingerprint(original_inventory)
	var initial_sources := source_hashes()
	for source_path: String in initial_sources:
		if str(initial_sources[source_path]).length() != 64:
			failures.append("Capture source could not be hashed: " + source_path)
	sandbox.begin()
	for sequence_id: String in SEQUENCE_IDS:
		await _capture_sequence(sequence_id)
	_save_contact_sheet()
	sandbox.finish()
	var inventory_hash := MOTION_PREVIEW.inventory_fingerprint(original_inventory)
	var preserved := Input.mouse_mode == initial_mouse and ExpeditionSession.capture_snapshot() == initial_snapshot and inventory_hash == initial_inventory_hash
	var unchanged := source_hashes() == initial_sources
	if not preserved:
		failures.append("Original expedition, inventory contents or cursor mode changed.")
	if not unchanged:
		failures.append("Production sources changed during reference motion capture.")
	Engine.physics_ticks_per_second = old_ticks
	AudioServer.set_bus_mute(0, old_mute)
	var clip_metadata := {}
	for clip: String in ["idle", "run", "takeoff", "air", "land", "right_diagonal", "left_reverse", "overhead"]:
		clip_metadata[clip] = REFERENCE_MOTION.clip_metadata(clip)
	var poses := {}
	for pose_id: String in selected:
		var entry: Dictionary = selected[pose_id].duplicate()
		entry.erase("pixels")
		poses[pose_id] = entry
	var manifest := {
		"delivery_scope": REFERENCE_MOTION.get_delivery_scope(),
		"qa_scope": "overhead_motion_on_existing_arm" if motion_only else ("overhead_integration_and_existing_motion_regressions" if partial_overhead else "full_eight_clip_delivery"),
		"finished_sleeve_required_for_this_capture": not motion_only,
		"incomplete_delivery": not REFERENCE_MOTION.full_delivery_available(),
		"display_driver": DisplayServer.get_name(),
		"actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"capture_kind": "Actual production DungeonPlayer static glove/sword and shield, with production movement/combat clocks and loaded Mac trajectories",
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "fps": FPS, "physics_fps": PHYSICS_FPS,
		"desktop_capture": false, "hardware_input_sampled_or_injected": false,
		"automatic_player_processing": false, "audio_muted_during_capture": true,
		"jump_evidence": "request_jump acceptance, move_and_slide on real physics frames, observed floor transitions and landing count; no assigned floor flags or jump phase clocks",
		"attack_evidence": "begin_sword_attack, scheduled release intent, advance_combat_state and resolve_active_attack; production retiming is retained",
		"direct_authored_clip_sampling": false,
		"reference_video": "https://youtu.be/sU7jk2OQlgc",
		"reference_timing_note": "Gameplay timing differs from the reference showcase; this capture verifies integrated production behavior, not one-to-one source timestamps.",
		"expedition_and_cursor_preserved": preserved,
		"original_inventory_sha256_before": initial_inventory_hash,
		"original_inventory_sha256_after": inventory_hash,
		"source_sha256": initial_sources, "sources_unchanged_during_capture": unchanged,
		"clip_metadata": clip_metadata, "sequences": sequences, "selected_poses": poses,
		"contact_sheet": {"image": "contact_sheet.png", "columns": 4, "tile_size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "row_major_pose_ids": CONTACT_IDS},
		"failures": failures,
	}
	var file := FileAccess.open(output_path.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not write reference sword motion capture manifest.")
	for failure in failures:
		push_error(failure)
	print("REFERENCE SWORD MOTION PREVIEW %s: %d production sequences, %d selected poses; %s" % ["PASS" if failures.is_empty() else "FAIL", sequences.size(), selected.size(), output_path])
	quit(0 if failures.is_empty() else 1)


static func source_hashes() -> Dictionary:
	var hashes := MOTION_PREVIEW.source_hashes()
	for path: String in ADDITIONAL_SOURCES:
		if path.ends_with("motion_manifest.json"):
			var actual_path: String = REFERENCE_MOTION.get_delivery_scope().get("manifest_path", path)
			hashes[actual_path] = FileAccess.get_sha256(actual_path)
		else:
			hashes[path] = FileAccess.get_sha256(path)
	for path: String in ["res://assets/animations/reference_sword_motion/Overhead_Final.glb", "res://scripts/reference_continuous_sleeve.gd"]:
		if FileAccess.file_exists(path):
			hashes[path] = FileAccess.get_sha256(path)
	return hashes


static func create_viewport() -> SubViewport:
	var viewport := ARM_PREVIEW.create_viewport()
	viewport.name = "ReferenceSwordMotionIsolatedViewport"
	viewport.size = IMAGE_SIZE
	viewport.use_taa = false
	viewport.audio_listener_enable_2d = false
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	var fixture := ARM_PREVIEW.populate_viewport(viewport)
	var player := fixture.player as DungeonPlayer
	player.set_process(false)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)
	(fixture.chest as DungeonLootChest).position = Vector3(30, 0, 30)
	var visible_floor := (fixture.stage as Node3D).get_node("ArmPreviewFloor") as MeshInstance3D
	(visible_floor.mesh as PlaneMesh).size = Vector2(100, 100)
	# Neutral inspection lighting and real world-space checker floor reveal stride.
	var grid_shader := Shader.new()
	grid_shader.code = "shader_type spatial; varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){float c=mod(floor(wp.x)+floor(wp.z),2.0); ALBEDO=mix(vec3(.18),vec3(.32),c); ROUGHNESS=1.0;}"
	var grid := ShaderMaterial.new()
	grid.shader = grid_shader
	visible_floor.material_override = grid
	for child in (fixture.stage as Node3D).get_children():
		if child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.85
			child.environment.background_color = Color(.22,.25,.28)
		if child is DirectionalLight3D:
			child.light_energy = 1.6
			child.light_color = Color.WHITE

	# The existing arm preview has only a visual plane. This collider makes the
	# movement/jump captures observe actual production floor contacts.
	var floor_body := StaticBody3D.new()
	floor_body.name = "ReferenceMotionCollisionFloor"
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position.y = -0.10
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100, 0.20, 100)
	shape.shape = box
	floor_body.add_child(shape)
	(fixture.stage as Node3D).add_child(floor_body)
	return fixture


func _prepare_fixture(fixture: Dictionary) -> bool:
	if not ARM_PREVIEW.configure_pose(fixture, "idle"):
		return false
	var player := fixture.player as DungeonPlayer
	var inventory := fixture.inventory as ExpeditionInventory
	if str(inventory.equipment.get("offhand", "")) != "round_shield":
		var shield_index := -1
		for index in inventory.slots.size():
			if str(inventory.slots[index].get("id", "")) == "round_shield":
				shield_index = index
		if shield_index < 0 or not bool(inventory.equip_from_slot(shield_index).get("accepted", false)):
			return false
	player.set_torch_enabled(false)
	player.position = Vector3(0, 0.90, 2.4)
	player.velocity = Vector3.ZERO
	player._pitch = 0.0
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO
	player.reset_reference_movement_motion(true)
	seed(8127)
	for step in range(PHYSICS_FPS / 2):
		await _advance_physics(player, Vector2.ZERO, false)
	# Discard any initial placement drop, then establish the floor again through
	# the real movement path. The measured jump begins with zero landings.
	player.reset_reference_movement_motion(true)
	await _advance_physics(player, Vector2.ZERO, false)
	player.stamina = player.MAX_STAMINA
	return player.is_on_floor() and bool(player.get_first_person_motion_snapshot().reference_motion_available)


func _advance_physics(player: DungeonPlayer, movement: Vector2, sprinting: bool) -> void:
	await physics_frame
	# Match the production player ordering without querying keyboard/mouse or
	# calling its hardware-input and interaction update functions.
	player.advance_action_timers(STEP)
	player.advance_combat_state(STEP, false)
	player.advance_movement(STEP, movement, sprinting)
	player._update_viewmodel(STEP)
	player._resolve_active_attack()
	player._update_torch(STEP)
	player._update_stamina(STEP)
	player.viewmodel_renderer.sync_view()


func _capture_sequence(sequence_id: String) -> void:
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	if not await _prepare_fixture(fixture):
		failures.append("Could not establish real grounded production fixture: " + sequence_id)
		viewport.queue_free()
		await process_frame
		return
	var player := fixture.player as DungeonPlayer
	if partial_overhead and not motion_only:
		var sleeve: Dictionary = player.weapon_arm.get_snapshot().get("continuous_sleeve", {})
		if not bool(sleeve.get("ok", false)) or int(sleeve.get("bone_count", 0)) != 7 or int(sleeve.get("mesh_count", 0)) != 3:
			failures.append("Partial integration capture requires the actual finished seven-bone continuous sleeve.")
			viewport.queue_free()
			await process_frame
			return
	var action_result := {}
	var movement := Vector2(0, -1) if sequence_id in ["walk", "run"] else Vector2.ZERO
	var sprinting := sequence_id == "run"
	if sequence_id in ["walk", "run"]:
		for step in range(PHYSICS_FPS):
			await _advance_physics(player, movement, sprinting)
	elif sequence_id == "jump":
		action_result = player.request_jump()
	elif REFERENCE_MOTION.ATTACK_CLIPS.has(sequence_id):
		action_result = player.begin_sword_attack(sequence_id)
	if sequence_id not in ["idle", "walk", "run"] and not bool(action_result.get("accepted", false)):
		failures.append("Production action rejected: " + sequence_id + " " + str(action_result))
	var duration := 1.0
	if sequence_id in ["walk", "run"]:
		duration = maxf(1.0, float(REFERENCE_MOTION.clip_metadata("run").get("duration_seconds", 1.0)))
	elif sequence_id == "jump":
		duration = 2.0 * player.JUMP_VELOCITY / player.gravity + float(REFERENCE_MOTION.clip_metadata("land").get("duration_seconds", 0.24)) + 0.40
	elif REFERENCE_MOTION.ATTACK_CLIPS.has(sequence_id):
		duration = 1.50
	var frame_count := ceili(duration * FPS) + 1
	var relative_folder := "sequences/" + sequence_id
	var folder := output_path.path_join(relative_folder)
	DirAccess.make_dir_recursive_absolute(folder)
	var frames: Array[Dictionary] = []
	var phase_counts := {}
	var released := false
	for frame in range(frame_count):
		if frame > 0:
			for substep in range(PHYSICS_FPS / FPS):
				var time_before_step := (float(frame - 1) / FPS) + substep * STEP
				if REFERENCE_MOTION.ATTACK_CLIPS.has(sequence_id) and not released and time_before_step >= 0.45 - 0.000001:
					player.attack_release_requested = true
					released = true
				await _advance_physics(player, movement, sprinting)
		for warmup in range(2):
			await process_frame
		RenderingServer.force_draw(false)
		var pixels := viewport.get_texture().get_image()
		var image_name := "frame_%03d.png" % frame
		var relative_image := relative_folder.path_join(image_name)
		if pixels == null or pixels.is_empty() or pixels.get_size() != IMAGE_SIZE or pixels.save_png(folder.path_join(image_name)) != OK:
			failures.append("Actual renderer could not save sequence frame: " + relative_image)
			continue
		var snapshot := player.get_first_person_motion_snapshot()
		var phase := str(snapshot.movement_phase)
		phase_counts[phase] = int(phase_counts.get(phase, 0)) + 1
		var record := _frame_record(player, snapshot, frame, relative_image)
		var arm: Dictionary = record.right_arm
		if not bool(arm.get("authored_arm_active", false)) or absf(float(arm.get("upper_length", 0.0)) / 0.34 - 1.0) > 0.011 or absf(float(arm.get("forearm_length", 0.0)) / 0.26 - 1.0) > 0.011:
			failures.append("Authored right arm lost its connection or length: " + relative_image)
		frames.append(record)
		_consider_pose(sequence_id, player, snapshot, record, pixels)
	var final_snapshot := player.get_first_person_motion_snapshot()
	if sequence_id == "jump":
		if not bool(action_result.get("accepted", false)) or int(final_snapshot.landing_count) != 1 or not player.is_on_floor():
			failures.append("Jump did not produce exactly one real floor landing and finish grounded.")
		for phase: String in ["takeoff", "air", "land"]:
			if int(phase_counts.get(phase, 0)) == 0:
				failures.append("Real jump did not render phase: " + phase)
	elif sprinting and Vector2(player.velocity.x, player.velocity.z).length() <= player.WALK_SPEED:
		failures.append("Run sequence never reached production sprint speed.")
	elif REFERENCE_MOTION.ATTACK_CLIPS.has(sequence_id) and player.combat_state != DungeonPlayer.CombatState.READY:
		failures.append("Production sword cycle did not return to READY: " + sequence_id)
	sequences.append({"id": sequence_id, "fps": FPS, "duration_seconds": float(frame_count - 1) / FPS, "frame_count": frames.size(), "action_result": action_result, "release_intent_seconds": 0.45 if released else null, "movement_intent": [movement.x, movement.y], "sprint_requested": sprinting, "phase_frame_counts": phase_counts, "frames": frames})
	player.cancel_sword_attack()
	viewport.queue_free()
	await process_frame


static func _frame_record(player: DungeonPlayer, snapshot: Dictionary, frame: int, image_path: String) -> Dictionary:
	return {
		"frame": frame, "time_seconds": float(frame) / FPS, "image": image_path,
		"delivered_attack_clip": REFERENCE_MOTION.has_track(str(snapshot.sword_attack_variant)),
		"combat_phase": snapshot.phase, "combat_phase_time": snapshot.phase_time,
		"sword_variant": snapshot.sword_attack_variant,
		"movement_phase": snapshot.movement_phase, "movement_phase_time": snapshot.movement_phase_time,
		"grounded": player.is_on_floor(), "landing_count": snapshot.landing_count,
		"landing_strength": snapshot.landing_strength, "stamina": player.stamina,
		"position": [player.position.x, player.position.y, player.position.z],
		"velocity": [player.velocity.x, player.velocity.y, player.velocity.z],
		"weapon_transform": _transform_record(player.weapon_pivot.transform),
		"shield_transform": _transform_record(player.shield_pivot.transform),
		"shield_visible": snapshot.shield_visible,
		"automatic_physics_processing": player.is_physics_processing(),
		"unhandled_input_processing": player.is_processing_unhandled_input(),
		"reference_motion_available": snapshot.reference_motion_available,
		"grip_screen": _screen_point(player, player.sword_visual_root.find_child("HandGrip", true, false).global_position),
		"tip_screen": _screen_point(player, player.sword_visual_root.find_child("BladeTip", true, false).global_position),
		"shield_rim_screen": _screen_point(player, player.shield_model.to_global(Vector3(0,.427,0))),
		"shield_upper_length": snapshot.joint_landmarks.shield.upper_length,
		"grip_contact_error": snapshot.hand_contacts.sword.error,
		"continuous_sleeve": player.weapon_arm.get_snapshot().get("continuous_sleeve", {}),
		"right_arm": _arm_record(player, snapshot),
	}


static func _screen_point(player: DungeonPlayer, point: Vector3) -> Array:
	var p := player.camera.unproject_position(point) / player.camera.get_viewport().get_visible_rect().size
	return [p.x,p.y]


static func _arm_record(player: DungeonPlayer, snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = snapshot.joint_landmarks.get("sword", {}).duplicate(true)
	for joint: String in ["shoulder", "elbow", "wrist"]:
		if result.has(joint):
			var point := player.camera.to_local(result[joint])
			result[joint] = [point.x, point.y, point.z]
	result["coordinate_space"] = "godot_camera_local_x_right_y_up_minus_z_forward"
	return result


static func _transform_record(value: Transform3D) -> Dictionary:
	var q := value.basis.get_rotation_quaternion()
	return {"position": [value.origin.x, value.origin.y, value.origin.z], "rotation_xyzw": [q.x, q.y, q.z, q.w]}


func _consider_pose(sequence_id: String, player: DungeonPlayer, snapshot: Dictionary, record: Dictionary, pixels: Image) -> void:
	var pose_id := sequence_id
	var score := absf(float(record.time_seconds) - 0.5)
	if sequence_id == "jump":
		pose_id = str(snapshot.movement_phase)
		if not pose_id in ["takeoff", "air", "land"]:
			return
		var clip_duration := float(REFERENCE_MOTION.clip_metadata(pose_id).get("duration_seconds", 0.24))
		score = absf(float(snapshot.movement_phase_time) - minf(clip_duration * 0.5, 0.12))
	elif REFERENCE_MOTION.ATTACK_CLIPS.has(sequence_id):
		if player.combat_state != DungeonPlayer.CombatState.ACTIVE:
			return
		score = absf(float(snapshot.phase_time) - player.get_melee_hit_time())
	if selected.has(pose_id) and float(selected[pose_id].score) <= score:
		return
	selected[pose_id] = {"sequence": sequence_id, "frame": record.frame, "time_seconds": record.time_seconds, "source_image": record.image, "image": pose_id + ".png", "score": score, "movement_phase": snapshot.movement_phase, "combat_phase": snapshot.phase, "pixels": pixels.duplicate()}


func _save_contact_sheet() -> void:
	var sheet := Image.create(IMAGE_SIZE.x * 4, IMAGE_SIZE.y * 2, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.02, 0.02, 0.02))
	for index in CONTACT_IDS.size():
		var pose_id: String = CONTACT_IDS[index]
		if not selected.has(pose_id):
			failures.append("Production sequence did not supply selected pose: " + pose_id)
			continue
		var pixels: Image = selected[pose_id].pixels
		if pixels.save_png(output_path.path_join(pose_id + ".png")) != OK:
			failures.append("Could not save selected production pose: " + pose_id)
		pixels.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(pixels, Rect2i(Vector2i.ZERO, IMAGE_SIZE), Vector2i((index % 4) * IMAGE_SIZE.x, (index / 4) * IMAGE_SIZE.y))
	if sheet.save_png(output_path.path_join("contact_sheet.png")) != OK:
		failures.append("Could not save reference sword contact sheet.")
