extends "res://tests/creep_ragdoll_preview.gd"
## Before/after evidence for real attack recovery -> locomotion transitions.
## This harness never seeks an animation or edits a bone/actor transform while recording.
const TARGET_FIXTURE := preload("res://tests/creep_dismemberment_preview.gd")
const TRANSITION_FRAMES := 120
const TRACKED_BONES := ["Torso", "Chest", "Head", "Hand.L", "Hand.R", "Leg2.L", "Leg2.R", "Foot.L", "Foot.R"]
const TRANSITION_CASES := [
	{"id": "bite_to_walk", "title": "BITE -> WALK", "attack_index_before": -1, "expected_contacts": 1},
	{"id": "punch_to_walk", "title": "PUNCH -> WALK", "attack_index_before": 0, "expected_contacts": 2},
]
const CAMERA_POSITION := Vector3(-5.4, 2.8, -6.0)
const CAMERA_TARGET := Vector3(0.0, .9, -2.25)
const EXTRA_SOURCES := [
	"res://scripts/creep_locomotion_blend.gd",
	"res://tests/creep_transition_preview.gd", "res://tests/creep_transition_preview.gd.uid",
	"res://tests/creep_dismemberment_preview.gd", "res://scripts/creep_dismemberment.gd",
	"res://scripts/creep_crawl.gd", "res://scripts/creep_execution_reaction.gd",
	"res://scripts/test_room_sandbox.gd", CREEP.DISMEMBERMENT.MODEL_PATH,
	"res://assets/licensed/creep/creep_dismembered.glb.import",
]

class TransitionDriver extends Node:
	var actor
	var target: DungeonPlayer
	var tick := 0
	var retreat_tick := -1
	var chase_tick := -1
	var recovery_tick := -1
	var retreat_from := Vector3.ZERO
	var retreat_to := Vector3(0.0, .9, -9.0)
	var records: Array[Dictionary] = []

	func _physics_process(_delta: float) -> void:
		tick += 1
		# The game coordinator calls this once per physics step as well.
		# The actor retains its ordinary AI _physics_process and move_and_slide.
		actor._resolve_active_attack()
		if actor.ai_state == DungeonEnemy.AIState.RECOVERY:
			if recovery_tick < 0: recovery_tick = tick
			if retreat_tick < 0 and actor.state_time >= .12:
				retreat_from = target.global_position
				target.global_position = retreat_to
				retreat_tick = tick
		if retreat_tick >= 0 and chase_tick < 0 and actor.ai_state == DungeonEnemy.AIState.CHASE:
			chase_tick = tick
		var bones := {}
		var rig: Skeleton3D = actor.skeleton
		for bone_name: String in TRACKED_BONES:
			var bone := rig.find_bone(bone_name)
			if bone < 0: continue
			var pose := rig.get_bone_global_pose(bone)
			var world_pose := rig.global_transform * pose
			bones[bone_name] = {"world": world_pose.origin,
				"actor_local": actor.to_local(world_pose.origin),
				"local_rotation": rig.get_bone_pose_rotation(bone)}
		records.append({"tick": tick, "seconds": float(tick) / 60.0,
			"state": actor.ai_state, "state_time": actor.state_time,
			"clip": actor.animation_clip, "sample": actor.animation_sample,
			"attack_index": actor.attack_index, "root": actor.global_transform,
			"velocity": actor.velocity, "on_floor": actor.is_on_floor(),
			"target": target.global_position, "contacts": target.get("contacts"), "bones": bones})
		if tick >= 240: set_physics_process(false)


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited embedded runner with --fixed-fps 30."); quit(2); return
	var tag := OS.get_environment("CREEP_TRANSITION_QA_ITERATION").strip_edges()
	if not tag.is_valid_filename() or tag.begins_with("."):
		push_error("Choose a new CREEP_TRANSITION_QA_ITERATION directory."); quit(2); return
	if not CREEP.is_available():
		push_error("The licensed Creep asset must be installed."); quit(2); return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Transition preview requires its own isolated session."); quit(2); return
	var directory := ProjectSettings.globalize_path("res://artifacts/visual_qa/creep_transition/" + tag)
	if DirAccess.dir_exists_absolute(directory):
		push_error("Existing captures will not be overwritten."); quit(2); return
	if DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) != OK:
		push_error("Could not create transition output directory."); quit(2); return
	root.gui_disable_input = true
	root.physics_object_picking = false
	var audio_before := AudioServer.is_bus_mute(0)
	var cursor_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var inventory_before: ExpeditionInventory = session_before.inventory
	var slots_before: Array = inventory_before.slots.duplicate(true) if inventory_before != null else []
	var equipment_before: Dictionary = inventory_before.equipment.duplicate(true) if inventory_before != null else {}
	var equipment_data_before: Dictionary = inventory_before.equipment_data.duplicate(true) if inventory_before != null else {}
	var physics_hz_before := Engine.physics_ticks_per_second
	var max_steps_before := Engine.max_physics_steps_per_frame
	AudioServer.set_bus_mute(0, true)
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(8, max_steps_before)
	var hashes := _transition_hashes()
	sandbox.begin()
	var frames: Array[Dictionary] = []
	var outcomes: Array[Dictionary] = []
	for scenario: Dictionary in TRANSITION_CASES:
		var viewport := _create_viewport()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var fixture := _create_fixture(viewport, {"wall_position": Vector3(0, -10, 8), "wall_size": Vector3(.1, .1, .1), "title": scenario.title})
		var world: Node3D = fixture.world
		for child in world.get_node("Floor").get_children():
			if child is CollisionShape3D: child.shape.size = Vector3(24, .2, 24)
			if child is MeshInstance3D: child.mesh.size = Vector3(24, .2, 24)
		for child in viewport.get_children():
			if child is CanvasLayer:
				for label in child.get_children():
					if label is Label and label.text.begins_with("CREEP  |"):
						label.text = "CREEP | ATTACK RECOVERY -> LOCOMOTION"
		var actor = fixture.actor
		actor.move_speed = 2.2
		actor.attack_index = int(scenario.attack_index_before)
		var camera: Camera3D = fixture.camera
		camera.position = CAMERA_POSITION
		camera.look_at(CAMERA_TARGET)
		camera.fov = 45.0
		var camera_transform := camera.global_transform
		var target := TARGET_FIXTURE.TargetDummy.new()
		target.position = Vector3(0.0, .9, -1.2)
		world.add_child(target)
		var driver := TransitionDriver.new()
		driver.actor = actor
		driver.target = target
		driver.process_physics_priority = 100
		driver.set_physics_process(false)
		world.add_child(driver)
		driver.set_physics_process(false) # Node insertion enables its virtual callback.
		var clip_lengths := {}
		for clip: String in ["idle", "walk", "bite", "punch"]:
			var animation: Animation = actor.animation_player.get_animation(clip)
			clip_lengths[clip] = {"length": animation.length, "tracks": animation.get_track_count()}
		# Standing settles before the target becomes visible to the AI.
		for warm in 10:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await RenderingServer.frame_post_draw
		actor.target = target
		driver.set_physics_process(true)
		var case_frames: Array[Dictionary] = []
		var previous_tick := -1
		for case_frame in TRANSITION_FRAMES:
			await process_frame
			_check(not driver.records.is_empty(), "Actual physics produced a transition sample.")
			if driver.records.is_empty(): continue
			if previous_tick >= 0: _check(driver.tick - previous_tick == 2, "Two real 60 Hz ticks per saved frame.")
			previous_tick = driver.tick
			var current: Dictionary = driver.records.back()
			var phase := _transition_phase(int(current.state), driver.retreat_tick >= 0)
			fixture.status.text = "%s | %.2f s | 60 Hz / 30 fps" % [phase, float(case_frame) / 30.0]
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			var filename := "frames/%05d.png" % frames.size()
			_check(pixels != null and not pixels.is_empty() and pixels.get_size() == Vector2i(1280, 720), "Actual Vulkan GPU pixels exist.")
			if pixels != null and not pixels.is_empty():
				_check(pixels.save_png(directory.path_join(filename)) == OK, "Save actual transition frame.")
			var record := {"frame": frames.size(), "case": scenario.id, "case_frame": case_frame,
				"file": filename, "phase": phase, "physics_tick": driver.tick, "sample": current}
			frames.append(record)
			case_frames.append(record)
			_check(camera.global_transform.is_equal_approx(camera_transform), "Inspection camera stays fixed.")
		var metrics := _transition_metrics(driver.records, driver.chase_tick)
		var stills := {}
		var desired_ticks := {"attack": driver.recovery_tick - 2, "recovery": driver.retreat_tick,
			"before_walk": driver.chase_tick - 1, "walk_entry": driver.chase_tick,
			"walk_blend": driver.chase_tick + 8, "walk_settled": driver.chase_tick + 24}
		for name: String in desired_ticks:
			var best_frame := _nearest_capture_tick(case_frames, int(desired_ticks[name]), name in ["walk_entry", "walk_blend", "walk_settled"])
			if best_frame < 0: continue
			var record: Dictionary = case_frames[best_frame]
			var filename: String = scenario.id + "_" + name + ".png"
			_check(DirAccess.copy_absolute(directory.path_join(record.file), directory.path_join(filename)) == OK, "Preserve named transition still.")
			stills[name] = {"file": filename, "physics_tick": record.physics_tick, "case_frame": best_frame, "state": record.sample.state}
		_check(driver.tick == 240 and driver.records.size() == 240 and case_frames.size() == 120, "Four seconds of actual continuous physics per example.")
		_check(driver.recovery_tick > 0 and driver.retreat_tick > driver.recovery_tick and driver.chase_tick > driver.retreat_tick, "Real recovery -> target retreat -> chase sequence occurred.")
		_check(target.contacts == int(scenario.expected_contacts), "Exactly one complete authored attack landed before target retreat.")
		_check(actor.animation_clip == "walk" and actor.ai_state == DungeonEnemy.AIState.CHASE, "Actor ends walking through actual chase AI.")
		_check(float(metrics.get("root_travel_after_transition_m", 0.0)) > 1.0, "Walking advances the physical actor.")
		_check(actor.ragdoll.phase == "living" and not actor.is_crawling(), "Intact living animation retains rig ownership.")
		outcomes.append({"id": scenario.id, "title": scenario.title, "clip_lengths": clip_lengths,
			"camera": camera_transform, "camera_fov": camera.fov, "metrics": metrics, "stills": stills,
			"target_retreat": {"tick": driver.retreat_tick, "from": driver.retreat_from, "to": driver.retreat_to, "during_state": "RECOVERY"},
			"recovery_tick": driver.recovery_tick, "chase_tick": driver.chase_tick,
			"actual_contacts": target.contacts, "physics_samples": driver.records.duplicate(true)})
		viewport.queue_free()
		await process_frame
		print("CREEP TRANSITION CASE: ", scenario.id, " | chase tick ", outcomes.back().chase_tick)
	sandbox.finish()
	Engine.physics_ticks_per_second = physics_hz_before
	Engine.max_physics_steps_per_frame = max_steps_before
	AudioServer.set_bus_mute(0, audio_before)
	var bag_preserved := inventory_before == null or (inventory_before.slots == slots_before and inventory_before.equipment == equipment_before and inventory_before.equipment_data == equipment_data_before)
	var session_preserved := session_before == ExpeditionSession.capture_snapshot() and bag_preserved
	var cursor_preserved := cursor_before == Input.mouse_mode
	var hashes_after := _transition_hashes()
	_check(session_preserved and not sandbox.active, "Original expedition and inventory restored.")
	_check(cursor_preserved, "Cursor mode preserved.")
	_check(hashes == hashes_after, "Capture sources remain unchanged.")
	_check(frames.size() == 240, "Two four-second examples produce 240 PNG frames.")
	var report := {"iteration": tag, "renderer": RenderingServer.get_current_rendering_driver_name(), "display_driver": DisplayServer.get_name(),
		"resolution": [1280, 720], "fps": 30, "physics_hz": 60, "duration_seconds": 8.0, "frame_count": frames.size(),
		"source_hashes_before": hashes, "source_hashes_after": hashes_after, "sources_preserved": hashes == hashes_after,
		"session_inventory_preserved": session_preserved, "cursor_preserved": cursor_preserved,
		"capture_scope": "Two separately initialized real AI examples, identical fixed three-quarter camera. The only in-take setup change is the target retreat during recovery. No animation seeking, bone editing, manual actor movement, external input or desktop capture.",
		"metrics_scope": "Pose discontinuities are measured at every actual 60 Hz tick, including root-relative positions and local joint rotations. Baseline captures are allowed to contain visible jumps; capture PASS is not an animation-quality verdict.",
		"scenarios": outcomes, "frames": frames, "failures": failures}
	var output := FileAccess.open(directory.path_join("metrics.json"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(_json_safe(report), "\t") + "\n")
	else: _check(false, "Could not save transition metrics.")
	print("CREEP_TRANSITION_PREVIEW_COMPLETE %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)


func _transition_hashes() -> Dictionary:
	var hashes := _source_hashes()
	for path: String in EXTRA_SOURCES:
		var digest := FileAccess.get_sha256(path)
		_check(digest.length() == 64, "Capture source exists: " + path)
		hashes[path] = digest
	return hashes


func _transition_phase(state: int, retreated: bool) -> String:
	match state:
		DungeonEnemy.AIState.WINDUP: return "WINDUP"
		DungeonEnemy.AIState.ACTIVE: return "ATTACK"
		DungeonEnemy.AIState.RECOVERY: return "RECOVERY / TARGET RETREAT" if retreated else "RECOVERY"
		DungeonEnemy.AIState.CHASE: return "WALK" if retreated else "ACQUIRE TARGET"
	return "IDLE"


func _nearest_capture_tick(records: Array[Dictionary], tick: int, at_or_after := false) -> int:
	if tick < 1: return -1
	var best := -1
	for index in records.size():
		if at_or_after and int(records[index].physics_tick) < tick: continue
		if not at_or_after and int(records[index].physics_tick) > tick: continue
		if best < 0 or absi(int(records[index].physics_tick) - tick) < absi(int(records[best].physics_tick) - tick): best = index
	return best


func _transition_metrics(records: Array[Dictionary], chase_tick: int) -> Dictionary:
	if chase_tick < 2 or records.size() < chase_tick: return {}
	var index := chase_tick - 1
	var before: Dictionary = records[index - 1]
	var first: Dictionary = records[index]
	var boundary := {}
	var window := {}
	for bone_name: String in TRACKED_BONES:
		if not before.bones.has(bone_name) or not first.bones.has(bone_name): continue
		boundary[bone_name] = _bone_step(before.bones[bone_name], first.bones[bone_name])
		var maximum_position := 0.0
		var maximum_angle := 0.0
		var maximum_world := 0.0
		for sample_index in range(maxi(1, index - 3), mini(records.size(), index + 25)):
			var step := _bone_step(records[sample_index - 1].bones[bone_name], records[sample_index].bones[bone_name])
			maximum_position = maxf(maximum_position, float(step.actor_local_distance_m))
			maximum_angle = maxf(maximum_angle, float(step.local_angle_deg))
			maximum_world = maxf(maximum_world, float(step.world_distance_m))
		window[bone_name] = {"maximum_actor_local_step_m": maximum_position, "maximum_local_angle_step_deg": maximum_angle, "maximum_world_step_m": maximum_world}
	var last: Dictionary = records.back()
	var first_root: Transform3D = first.root
	var last_root: Transform3D = last.root
	return {"boundary_from_tick": chase_tick - 1, "boundary_to_tick": chase_tick,
		"previous_clip": before.clip, "previous_sample": before.sample, "entry_clip": first.clip, "entry_sample": first.sample,
		"boundary": boundary, "window_before_ticks": 3, "window_after_ticks": 24, "window_maxima": window,
		"root_travel_after_transition_m": first_root.origin.distance_to(last_root.origin),
		"entry_velocity": first.velocity, "final_velocity": last.velocity}


func _bone_step(before: Dictionary, after: Dictionary) -> Dictionary:
	var before_world: Vector3 = before.world
	var after_world: Vector3 = after.world
	var before_local: Vector3 = before.actor_local
	var after_local: Vector3 = after.actor_local
	var before_rotation: Quaternion = before.local_rotation
	var after_rotation: Quaternion = after.local_rotation
	return {"world_distance_m": before_world.distance_to(after_world),
		"actor_local_distance_m": before_local.distance_to(after_local),
		"local_angle_deg": rad_to_deg(before_rotation.normalized().angle_to(after_rotation.normalized()))}
