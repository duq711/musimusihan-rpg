extends "res://tests/creep_ragdoll_preview.gd"
## Production rear sword takedown and an alerted-target refusal, on live AI.
## Audited hidden GPU capture only: 30 rendered fps, actual 60 Hz physics.
const ARMS := preload("res://tests/player_arm_preview.gd")
const REAR_MOTION := preload("res://scripts/rear_takedown_motion.gd")
const WRIST_METRICS := preload("res://tests/rear_takedown_test.gd")
const REAR_CASES := [
	{"id": "rear_sword", "alerted": false, "frames": 180, "title": "후방 제압 · 깊게 찌르기 → 좌측으로 베어 빼기 / STAB → SLICE OUT LEFT"},
	{"id": "alerted_denial", "alerted": true, "frames": 90, "title": "경계 중인 적 · 제압 거부 / ALERTED TARGET · TAKEDOWN REFUSED"},
]
const REAR_STAGES := {
	"prepare": REAR_MOTION.PREPARE_END,
	"stab": REAR_MOTION.STAB_HIT,
	"hold": REAR_MOTION.HOLD_END - .05,
	"withdraw": REAR_MOTION.WITHDRAW_END,
	"slash": (REAR_MOTION.CUT_START + REAR_MOTION.CUT_HIT) * .5,
	"death": REAR_MOTION.CUT_HIT,
	"cut_end": REAR_MOTION.CUT_END,
	"recovered": REAR_MOTION.DURATION,
}
const REAR_SOURCES := [
	"res://scripts/player.gd", "res://scripts/enemy.gd", "res://scripts/creep_enemy.gd",
	"res://scripts/rear_takedown_motion.gd", "res://scripts/rear_sword_reaction.gd",
	"res://scripts/inventory_model.gd", "res://scripts/expedition_session.gd",
	"res://scripts/located_hit_query.gd", "res://scripts/first_person_renderer.gd",
	"res://scripts/creep_dismemberment.gd", "res://scripts/creep_ragdoll.gd", "res://scripts/creep_ragdoll_pose.gd",
	"res://scripts/creep_locomotion_blend.gd", "res://scripts/supplied_fp_arm.gd", "res://scripts/sword_long_grip_visual.gd",
	"res://scripts/reference_sword_arm.gd", "res://scripts/reference_continuous_sleeve.gd",
	"res://assets/3d/player/sword_hold_long_grip/SwordHold_Static.glb",
	"res://assets/3d/player/fp_arms/right.scn", "res://assets/3d/player/fp_arms/rig.json",
	"res://tests/rear_takedown_preview.gd", "res://tests/rear_takedown_preview.gd.uid",
	"res://tests/rear_takedown_test.gd", "res://tests/dagger_assassination_test.gd",
	"res://tests/player_arm_preview.gd", "res://tests/creep_ragdoll_preview.gd",
	"res://tests/run_embedded_preview.sh", "res://scripts/test_room_sandbox.gd",
	"res://project.godot", CREEP.MODEL_PATH, CREEP.DISMEMBERMENT.MODEL_PATH,
]


class RearDriver extends Node:
	var player: DungeonPlayer
	var actor
	var alerted := false
	var max_ticks := 360
	var tick := 0
	var began: Dictionary = {}
	var before_begin: Dictionary = {}
	var initial_contacts: Dictionary = {}
	var defeats := 0
	var landed := 0
	var damage_events: Array[Dictionary] = []
	var records: Array[Dictionary] = []
	var stages: Dictionary = {}
	var first_death: Dictionary = {}
	var last_alive_before_death: Dictionary = {}
	var first_head_detach: Dictionary = {}
	var initial_chest := Vector3.ZERO
	var inspection_pitch := 0.0
	var changed_camera := false
	var max_elapsed := 0.0
	var max_shoulder_adjustment_m := 0.0
	var max_requested_arm_reach_m := 0.0
	var minimum_shoulder_camera_z_m := INF
	var wrist_summary := {}

	func _physics_process(delta: float) -> void:
		tick += 1
		if tick == 36:
			before_begin = capture_state()
			before_begin["candidate_is_actor"] = player.get_rear_takedown_target() == actor
			began = player.begin_rear_takedown()
		# Input and the player's own coordinator are disabled by the fixture.
		# Use their production advance/pose/contact functions without forcing a
		# contact, target reaction, health change, dismemberment or rigid body.
		player.advance_combat_state(delta)
		if not alerted and actor.health <= 0.0 and not player.is_execution_active() and float(tick) / 60.0 >= 3.5:
			if not changed_camera: inspection_pitch = player._pitch
			player._pitch = lerpf(inspection_pitch, deg_to_rad(-47.0), smoothstep(3.5, 4.3, float(tick) / 60.0))
			player.head.rotation.x = player._pitch
			changed_camera = true
		player._update_viewmodel(delta)
		player._resolve_active_attack()
		actor._resolve_active_attack()
		player.viewmodel_renderer.sync_view()
		var sample := capture_state()
		max_elapsed = maxf(max_elapsed, float(sample.execution.elapsed))
		if bool(sample.execution.active) and bool(sample.right_arm.available):
			max_shoulder_adjustment_m = maxf(max_shoulder_adjustment_m, float(sample.right_arm.actual_shoulder_adjustment_m))
			max_requested_arm_reach_m = maxf(max_requested_arm_reach_m, float(sample.right_arm.requested_reach_m))
			minimum_shoulder_camera_z_m = minf(minimum_shoulder_camera_z_m, (sample.right_arm.camera.shoulder as Vector3).z)
		if actor.health <= 0.0 and first_death.is_empty(): first_death = sample.duplicate(true)
		if "head" in sample.dismemberment.severed and first_head_detach.is_empty(): first_head_detach = sample.duplicate(true)
		for stage_name: String in REAR_STAGES:
			if bool(began.get("accepted", false)) and not stages.has(stage_name) and max_elapsed + .000001 >= float(REAR_STAGES[stage_name]):
				var stage: Dictionary = sample.duplicate(true)
				stage["expected_execution_seconds"] = REAR_STAGES[stage_name]
				if stage_name in ["stab", "hold"]:
					stage["actual_skin"] = measure_back_skin(stage.actual_blade, stage.execution)
				stages[stage_name] = stage
		records.append(sample)
		if tick >= max_ticks: set_physics_process(false)

	func _on_defeated(_enemy: DungeonEnemy) -> void:
		defeats += 1

	func _on_attack_landed(damage: float, headshot: bool) -> void:
		landed += 1
		damage_events.append({"tick": tick, "damage": damage, "headshot": headshot})

	func capture_state() -> Dictionary:
		var execution: Dictionary = player.get_execution_snapshot()
		var bone_world := {}
		for bone_name: String in ["Chest", "Neck", "Head"]:
			var index: int = actor.skeleton.find_bone(bone_name)
			if index >= 0:
				bone_world[bone_name] = actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(index)
		var chest: Vector3 = (bone_world.get("Chest", Transform3D.IDENTITY) as Transform3D).origin
		return {
			"tick": tick, "seconds": float(tick) / 60.0, "execution": execution,
			"player_state": player.combat_state, "enemy_state": actor.ai_state,
			"health": actor.health, "player_health": player.health, "stamina": player.stamina,
			"defeats": defeats, "landed": landed,
			"enemy_root": actor.global_transform, "bone_world": bone_world,
			"initial_chest_distance_m": chest.distance_to(initial_chest),
			"target_is_actual_player": actor.target == player, "enemy_ai_enabled": actor.is_physics_processing(),
			"player_transform": player.global_transform, "camera": player.camera.global_transform,
			"weapon_transform": player.weapon_pivot.global_transform,
			"sword_visible": player.sword_visual_root.is_visible_in_tree(),
			"dagger_visible": player.dagger_visual_root.is_visible_in_tree(),
			"shield_visible": player.shield_model.is_visible_in_tree(),
			"world_contact": player.viewmodel_renderer.world_contact_enabled,
			"actual_blade": measure_blade(execution),
			"right_arm": measure_right_arm(),
			"dismemberment": actor.dismemberment.snapshot(), "ragdoll": actor.ragdoll.snapshot(),
			"reaction": actor.get_rear_takedown_reaction_snapshot(),
		}

	func measure_right_arm() -> Dictionary:
		var motion: Dictionary = player.get_first_person_motion_snapshot()
		var joints: Dictionary = (motion.joint_landmarks as Dictionary).get("sword", {})
		if joints.is_empty(): return {"available": false}
		var camera_joints := {}
		var world_joints := {}
		for joint_name: String in ["shoulder", "elbow", "wrist"]:
			var point: Vector3 = joints[joint_name]
			world_joints[joint_name] = point
			camera_joints[joint_name] = player.camera.to_local(point)
		var requested: Vector3 = player.SWORD_LONG_GRIP.SOURCE_READY * player.SWORD_LONG_GRIP.REST_SHOULDER
		# Preparation/recovery blend from the actual ready shoulder. The active
		# contact phases still require the original fixed shoulder anchor.
		var elapsed := player.execution_elapsed
		if player.is_execution_active() and not player._rear_arm_entry.is_empty():
			if elapsed < REAR_MOTION.PREPARE_END: requested = (player._rear_arm_entry.shoulder as Vector3).lerp(requested, smoothstep(0, REAR_MOTION.PREPARE_END, elapsed))
			elif elapsed > REAR_MOTION.CUT_END: requested = requested.lerp(player._rear_arm_entry.shoulder, smoothstep(REAR_MOTION.CUT_END, REAR_MOTION.DURATION, elapsed))
		return {"available": true, "world": world_joints, "camera": camera_joints,
			"actual_rig": WRIST_METRICS.measure_wrist_geometry(player),
			"requested_shoulder_camera": requested,
			"actual_shoulder_adjustment_m": (camera_joints.shoulder as Vector3).distance_to(requested),
			"reported_shoulder_adjustment_m": joints.get("shoulder_adjustment_m", -1.0),
			"requested_reach_m": (camera_joints.wrist as Vector3).distance_to(requested),
			"upper_length_m": (world_joints.shoulder as Vector3).distance_to(world_joints.elbow),
			"forearm_length_m": (world_joints.elbow as Vector3).distance_to(world_joints.wrist)}

	func measure_blade(execution: Dictionary) -> Dictionary:
		# Independently scan displayed mesh vertices; the gameplay's measured
		# tip and cached length are recorded separately for comparison.
		var blade: MeshInstance3D = player.sword_blade
		var axis := player.weapon_pivot.global_basis.y.normalized()
		var lowest := INF
		var highest := -INF
		var tip := Vector3.ZERO
		var base := Vector3.ZERO
		for surface in blade.mesh.get_surface_count():
			var vertices: PackedVector3Array = blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := blade.to_global(vertex)
				var projection := point.dot(axis)
				if projection > highest:
					highest = projection
					tip = point
				if projection < lowest:
					lowest = projection
					base = point
		var length_m := highest - lowest
		var direction: Vector3 = execution.get("stab_direction", Vector3.FORWARD)
		var contact: Vector3 = execution.get("contact_point", Vector3.ZERO)
		var offset := tip - contact
		var depth := offset.dot(direction)
		var lateral_contact: Vector3 = execution.get("lateral_cut_contact", contact)
		var torso_hit: Dictionary = actor.query_located_hit(tip - axis * length_m, tip, .045)
		var projection := WRIST_METRICS.measure_blade_projection(player.camera, tip - axis * length_m, tip, contact, direction)
		return {"length_m": length_m, "tip_world": tip, "base_world": base,
			"projection": projection,
			"axis_world": axis, "axis_depth_m": depth, "inserted_fraction": depth / maxf(length_m, .000001),
			"anchor_world": contact, "lateral_error_m": (offset - direction * depth).length(),
			"axis_direction_dot": axis.dot(direction), "lateral_contact_world": lateral_contact,
			"located_contact": torso_hit, "torso_contact": torso_hit.get("region", "") == "torso"}

	func measure_back_skin(blade: Dictionary, execution: Dictionary) -> Dictionary:
		# Re-intersect actual posed torso triangles at the recorded stage. This
		# independently checks insertion past entry skin, not an invisible capsule.
		var direction: Vector3 = execution.stab_direction
		var contact: Vector3 = execution.contact_point
		var from := contact - direction * .85
		var to := contact + direction * 1.1
		var nearest := INF
		var point := Vector3.ZERO
		for part: MeshInstance3D in actor.visual_meshes:
			if part.name != "CreepPart_torso" or not part.is_visible_in_tree(): continue
			var faces: PackedVector3Array = actor.dismemberment._bake_world_mesh(part, Vector3.ZERO).get_faces()
			for index in range(0, faces.size(), 3):
				var hit = Geometry3D.segment_intersects_triangle(from, to, faces[index], faces[index + 1], faces[index + 2])
				if hit is Vector3 and from.distance_squared_to(hit) < nearest:
					nearest = from.distance_squared_to(hit)
					point = hit
		var depth := ((blade.tip_world as Vector3) - point).dot(direction)
		return {"found": nearest < INF, "position": point, "entry_anchor_error_m": point.distance_to(contact),
			"depth_m": depth, "inserted_fraction": depth / maxf(float(blade.length_m), .000001)}


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited embedded runner with Dummy audio and --fixed-fps 30."); quit(2); return
	var tag := OS.get_environment("REAR_TAKEDOWN_QA_ITERATION").strip_edges()
	if not tag.is_valid_filename() or tag.begins_with(".") or not CREEP.is_available():
		push_error("Set a new REAR_TAKEDOWN_QA_ITERATION and install the Creep asset."); quit(2); return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Rear takedown preview requires its own isolated session."); quit(2); return
	var directory := ProjectSettings.globalize_path("res://artifacts/visual_qa/rear_takedown/" + tag)
	if DirAccess.dir_exists_absolute(directory):
		push_error("Existing rear takedown captures will not be overwritten."); quit(2); return
	if DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) != OK:
		push_error("Could not create rear takedown capture directory."); quit(2); return
	var gui_before := root.gui_disable_input
	var picking_before := root.physics_object_picking
	root.gui_disable_input = true
	root.physics_object_picking = false
	var session_before := ExpeditionSession.capture_snapshot()
	var inventory_before: ExpeditionInventory = session_before.inventory
	var bag_before := {} if inventory_before == null else {"slots": inventory_before.slots.duplicate(true), "equipment": inventory_before.equipment.duplicate(true), "equipment_data": inventory_before.equipment_data.duplicate(true)}
	var cursor_before := Input.mouse_mode
	var audio_before := AudioServer.is_bus_mute(0)
	var hz_before := Engine.physics_ticks_per_second
	var steps_before := Engine.max_physics_steps_per_frame
	var hashes := _rear_hashes()
	AudioServer.set_bus_mute(0, true)
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(8, steps_before)
	sandbox.begin()
	var frames: Array[Dictionary] = []
	var outcomes: Array[Dictionary] = []
	for scenario: Dictionary in REAR_CASES:
		var viewport := ARMS.create_viewport()
		viewport.size = Vector2i(960, 540)
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.use_taa = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var fixture := ARMS.populate_viewport(viewport)
		var world: Node3D = fixture.stage
		var player: DungeonPlayer = fixture.player
		fixture.chest.position = Vector3(20, 0, 20)
		_add_rear_floor(world)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-32, 155, 0)
		fill.light_energy = .8
		fill.light_color = Color(.90, .94, 1.0)
		world.add_child(fill)
		player.position = Vector3(0, .9, 1.15)
		_check(ARMS._equip_weapon(player.inventory_model, "rusted_sword"), "Equip actual rusted sword: " + scenario.id)
		player.inventory_model.equipment.offhand = ""
		player.inventory_model.changed.emit()
		player.configure_safe_zone(false)
		player.set_torch_enabled(false)
		player._torch_draw_elapsed = 0.0
		player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
		player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
		player.velocity = Vector3.ZERO
		player.stamina = player.MAX_STAMINA
		player.health = player.MAX_HEALTH
		# Flush the new player body's relocated PhysicsServer transform before
		# spawning another capsule at the world origin (including case two).
		for settle in 2:
			await physics_frame
			await process_frame
		var actor = CREEP.new()
		actor.configure("후방 제압 검수 크리프", 118, 8, 2.2, Color.WHITE)
		actor.position = Vector3(0, .9, 0)
		world.add_child(actor)
		actor.target = null
		actor.set_process_input(false)
		actor.set_process_unhandled_input(false)
		var driver := RearDriver.new()
		driver.player = player
		driver.actor = actor
		driver.alerted = bool(scenario.alerted)
		driver.max_ticks = int(scenario.frames) * 2
		driver.process_physics_priority = 100
		world.add_child(driver)
		driver.set_physics_process(false)
		actor.defeated.connect(driver._on_defeated)
		player.attack_landed.connect(driver._on_attack_landed)
		for warm in 10: await process_frame
		var chest_index: int = actor.skeleton.find_bone("Chest")
		driver.initial_chest = (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(chest_index)).origin
		driver.initial_contacts = actor.get_rear_takedown_contacts()
		_check(not driver.initial_contacts.is_empty(), "Actual back skin contact available: " + scenario.id)
		var initial_focus: Vector3 = driver.initial_contacts.get("back", driver.initial_chest)
		var aim := initial_focus - player.camera.global_position
		player.rotation.y = atan2(-aim.x, -aim.z)
		player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
		player.head.rotation.x = player._pitch
		player._update_viewmodel(1.0)
		player.camera.make_current()
		player.viewmodel_renderer.sync_view()
		var label := _rear_overlay(viewport, str(scenario.title))
		for warm in 4:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await RenderingServer.frame_post_draw
		actor.target = player
		if bool(scenario.alerted): actor._set_state(DungeonEnemy.AIState.CHASE)
		driver.set_physics_process(true)
		var previous_tick := -1
		var case_frames: Array[Dictionary] = []
		var stills := {}
		for frame in int(scenario.frames):
			await process_frame
			_check(not driver.records.is_empty(), "Real physics callback recorded: " + scenario.id)
			if driver.records.is_empty(): continue
			if previous_tick >= 0: _check(driver.tick - previous_tick == 2, "Two actual physics ticks per saved frame: " + scenario.id)
			previous_tick = driver.tick
			var sample: Dictionary = driver.records.back().duplicate(true)
			label.text = "%s\n체력 HP %.0f / 118  ·  머리 분리 HEAD DETACHED %d  ·  처치 KILL %d  |  %.2f s" % [scenario.title, sample.health, (sample.dismemberment.severed as Array).count("head"), driver.defeats, float(frame) / 30.0]
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			var filename := "frames/%05d.jpg" % frames.size()
			_check(pixels != null and not pixels.is_empty(), "Actual GPU frame exists: " + filename)
			if pixels != null and not pixels.is_empty():
				_check(pixels.save_jpg(directory.path_join(filename), .95) == OK, "Saved frame: " + filename)
				var names: Array[String] = []
				if frame == 0: names.append("ready")
				if bool(scenario.alerted) and not driver.began.is_empty() and not stills.has("denied"): names.append("denied")
				for stage_name: String in driver.stages:
					if not stills.has(stage_name): names.append(stage_name)
				if frame == int(scenario.frames) - 1: names.append("final")
				for name_value: String in names:
					var still_file: String = scenario.id + "_" + name_value + ".png"
					_check(pixels.save_png(directory.path_join(still_file)) == OK, "Saved still: " + still_file)
					stills[name_value] = {"file": still_file, "tick": driver.tick, "frame": frame, "execution_elapsed": sample.execution.elapsed}
			sample.merge({"frame": frames.size(), "scenario": scenario.id, "case_frame": frame, "file": filename})
			frames.append(sample)
			case_frames.append(sample)
		_check_rear_case(driver, scenario, case_frames)
		outcomes.append({"id": scenario.id, "alerted": scenario.alerted, "initial_health": 118,
			"initial_contacts": driver.initial_contacts, "before_begin": driver.before_begin,
			"begin_result": driver.began, "attacks_landed": driver.landed, "defeats": driver.defeats,
			"damage_events": driver.damage_events, "first_death": driver.first_death, "last_alive_before_death": driver.last_alive_before_death, "first_head_detach": driver.first_head_detach,
			"stages": driver.stages, "stills": stills, "camera_inspection_tilt": driver.changed_camera,
			"maximum_shoulder_adjustment_m": driver.max_shoulder_adjustment_m,
			"maximum_requested_arm_reach_m": driver.max_requested_arm_reach_m,
			"wrist_metrics": driver.wrist_summary,
			"minimum_shoulder_camera_z_m": driver.minimum_shoulder_camera_z_m if is_finite(driver.minimum_shoulder_camera_z_m) else 0.0,
			"physics_samples": driver.records, "final_creep": actor.get_creep_snapshot()})
		print("REAR TAKEDOWN CASE: ", scenario.id, " | accepted ", driver.began.get("accepted", false), " | defeats ", driver.defeats)
		viewport.queue_free()
		await process_frame
	sandbox.finish()
	Engine.physics_ticks_per_second = hz_before
	Engine.max_physics_steps_per_frame = steps_before
	AudioServer.set_bus_mute(0, audio_before)
	root.gui_disable_input = gui_before
	root.physics_object_picking = picking_before
	var bag_preserved: bool = inventory_before == null or (inventory_before.slots == bag_before.slots and inventory_before.equipment == bag_before.equipment and inventory_before.equipment_data == bag_before.equipment_data)
	var session_preserved := session_before == ExpeditionSession.capture_snapshot() and bag_preserved
	var cursor_preserved := cursor_before == Input.mouse_mode
	var hashes_after := _rear_hashes()
	_check(session_preserved and not sandbox.active, "Original expedition, inventory and sandbox restored.")
	_check(cursor_preserved, "Original cursor mode preserved.")
	_check(hashes == hashes_after, "Sources unchanged during rendering.")
	_check(frames.size() == 270, "Nine seconds at 30 fps produces 270 actual GPU frames.")
	var manifest := {"iteration": tag, "resolution": [960, 540], "fps": 30, "physics_hz": 60,
		"frame_count": frames.size(), "duration_seconds": 9.0, "display_driver": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_driver_name(), "audio_driver_policy": "Dummy enforced by audited run_embedded_preview.sh",
		"source_hashes_before": hashes, "source_hashes_after": hashes_after, "sources_preserved": hashes == hashes_after,
		"session_inventory_preserved": session_preserved, "cursor_preserved": cursor_preserved,
		"capture_scope": "Actual DungeonPlayer sword and live Creep AI. One begin_rear_takedown call at .6 seconds per case; actual production stab, leftward slicing extraction and whole-body rigid-body death with attached head. No forced damage, death, pose, detached-part position or contact.",
		"depth_measurement": "Displayed blade vertices are scanned independently in world space at every physics tick. Stab/hold stages additionally re-intersect posed torso triangles. Lateral extraction is measured against the original wound plane because the intact corpse is already physically falling. The final living physics sample (within two ticks of death) records actual torso contact; dead bodies intentionally no longer answer combat hit queries. Entry-skin insertion fraction is measured against actual blade length; this is not a claim that the tip cannot exit the far side.",
		"arm_measurement": "Actual fitted shoulder/elbow/wrist are recorded in world and camera space every physics tick. During the full active takedown, shoulder displacement from its anatomical rest anchor must stay within 4.5cm, its camera-space Z stays behind the camera, and upper/forearm lengths remain 34/26cm. These checks supplement, not replace, inspection of the rendered sleeve edge.",
		"wrist_measurement": "Actual supplied wrist/elbow bone poses and the authored neutral forearm axis independently measure hand-to-forearm axis mismatch, not a clinical wrist angle. Embedded stab and lateral-extraction keys require at most 45 degrees. All 60Hz samples retain real bone continuity; exposed-blade frustum projection is required through the lethal lateral cut, after which the leftward follow-through may leave the frame; projection does not prove that skin or sleeve does not occlude it. The blade world basis must remain fixed within 0.1 degrees during axial thrust and hold; controlled rotation is allowed during the leftward slice.",
		"camera_motion": "Starts 1.15m behind the actual actor, aimed at back skin. Production aiming/lean and collision-tested initial approach own the active sequence. There is no additional post-stab neck-cut step. Only after the completed kill, a capture-only pitch tilt from 3.5 to 4.3 seconds ends at -47 degrees to inspect the intact corpse. Alerted control keeps its initial camera; live AI can turn and move.",
		"input_scope": "No OS keyboard/mouse/focus, hardware cursor change, desktop capture or audible playback. Labels are inspection subtitles. The alerted control is initialized in CHASE, then runs normal AI; the rear case starts unaware in IDLE.",
		"reference_scope": "Requested action sequence only. The linked reference video could not be played silently with the available tools and was not visually observed.",
		"stages_seconds": REAR_STAGES, "penetration_ratio_target": REAR_MOTION.PENETRATION_RATIO,
		"scenarios": outcomes, "frames": frames, "failures": failures}
	var output := FileAccess.open(directory.path_join("capture_manifest.json"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(_json_safe(manifest), "\t") + "\n")
	else: _check(false, "Could not save rear takedown manifest.")
	print("REAR_TAKEDOWN_PREVIEW_COMPLETE %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)


func _check_rear_case(driver: RearDriver, scenario: Dictionary, rendered: Array[Dictionary]) -> void:
	var prefix: String = scenario.id + ": "
	_check(driver.records.size() == int(scenario.frames) * 2, prefix + "all actual 60 Hz physics samples retained")
	_check(not driver.before_begin.is_empty(), prefix + "production request attempted once")
	_check(not rendered.is_empty(), prefix + "actual GPU samples retained")
	if driver.records.is_empty() or driver.before_begin.is_empty(): return
	_check_wrist_sequence(driver, prefix)
	var last: Dictionary = driver.records.back()
	for sample: Dictionary in driver.records:
		_check(sample.sword_visible and not sample.dagger_visible and not sample.shield_visible, prefix + "actual sword equipped without shield")
		_check(sample.enemy_ai_enabled and sample.target_is_actual_player, prefix + "live AI targets the actual player")
		_check((sample.player_transform as Transform3D).origin.is_finite() and (sample.weapon_transform as Transform3D).origin.is_finite(), prefix + "finite actual player/weapon transforms")
		if bool(sample.execution.active):
			_check(sample.execution.profile == "rear_sword" and sample.world_contact, prefix + "rear profile renders with world depth")
			_check(bool(sample.right_arm.available), prefix + "actual fitted right-arm joints recorded")
			if bool(sample.right_arm.available):
				_check(float(sample.right_arm.actual_shoulder_adjustment_m) <= .045, prefix + "shoulder stays attached throughout takedown (maximum 4.5cm adjustment)")
				_check((sample.right_arm.camera.shoulder as Vector3).z >= .015, prefix + "upper-arm origin remains behind the first-person camera")
				_check(absf(float(sample.right_arm.upper_length_m) - .34) <= .004 and absf(float(sample.right_arm.forearm_length_m) - .26) <= .003, prefix + "actual arm segments retain anatomical lengths")
			if float(sample.execution.elapsed) < REAR_MOTION.CUT_HIT - .000001:
				_check(float(sample.health) > 0.0 and not ("head" in sample.dismemberment.severed), prefix + "alive with attached head until actual lateral cutting contact")
		elif int(sample.player_state) == DungeonPlayer.CombatState.READY:
			_check(not sample.world_contact, prefix + "ready restores normal first-person rendering")
	if bool(scenario.alerted):
		_check(not bool(driver.began.get("accepted", false)) and not driver.before_begin.candidate_is_actor, prefix + "alerted target refuses rear takedown")
		_check(int(driver.before_begin.enemy_state) != DungeonEnemy.AIState.IDLE, prefix + "refusal used a genuinely alerted AI state")
		_check(driver.defeats == 0 and driver.landed == 0 and is_equal_approx(float(last.health), 118.0), prefix + "refusal causes no attack or damage")
		_check((last.dismemberment.severed as Array).is_empty() and last.ragdoll.phase == "living", prefix + "refused target stays intact and alive")
		return
	_check(bool(driver.began.get("accepted", false)) and driver.before_begin.candidate_is_actor, prefix + "actual unaware rear target accepted")
	_check(int(driver.before_begin.enemy_state) == DungeonEnemy.AIState.IDLE, prefix + "enemy was unaware immediately before reservation")
	_check(driver.defeats == 1 and driver.landed == 1 and is_zero_approx(float(last.health)), prefix + "one production lethal cut, defeat and reward event")
	_check((last.dismemberment.severed as Array).is_empty() and int(last.dismemberment.detached_bodies) == 0, prefix + "head and all limbs remain attached")
	_check(str(last.ragdoll.phase) in ["simulating", "settled"] and int(last.ragdoll.bodies) > 0, prefix + "actual rigid-body corpse simulation")
	_check(float(last.initial_chest_distance_m) > .20, prefix + "corpse physically moved from standing pose")
	_check(not driver.first_death.is_empty() and driver.first_head_detach.is_empty(), prefix + "lethal contact is recorded without any head-detachment event")
	if not driver.first_death.is_empty():
		_check(absf(float(driver.first_death.execution.elapsed) - REAR_MOTION.CUT_HIT) <= 1.0 / 60.0 + .00001, prefix + "death occurs at lateral cut contact, not at stab")
		# Dead targets deliberately stop answering located-hit queries. Read the
		# last actual living physics sample instead of querying the new corpse.
		for sample: Dictionary in driver.records:
			if int(sample.tick) >= int(driver.first_death.tick): break
			if float(sample.health) > 0.0: driver.last_alive_before_death = sample
		_check(not driver.last_alive_before_death.is_empty(), prefix + "last live blade contact before lethal tick is retained")
		if not driver.last_alive_before_death.is_empty():
			var live: Dictionary = driver.last_alive_before_death
			var ticks := int(driver.first_death.tick) - int(live.tick)
			_check(ticks >= 1 and ticks <= 2, prefix + "torso-contact evidence is within two actual physics ticks before death")
			_check(bool(live.actual_blade.torso_contact) and float(live.execution.elapsed) >= REAR_MOTION.CUT_HIT - 2.0 / 60.0 - .00001, prefix + "displayed cutting blade intersects the actual live torso immediately before lethal contact")
		_check((driver.first_death.dismemberment.severed as Array).is_empty() and int(driver.first_death.dismemberment.detached_bodies) == 0, prefix + "lethal contact preserves the complete physical body")

	for stage_name: String in REAR_STAGES:
		_check(driver.stages.has(stage_name), prefix + "stage recorded: " + stage_name)
	for stage_name: String in ["stab", "hold"]:
		if not driver.stages.has(stage_name): continue
		var stage: Dictionary = driver.stages[stage_name]
		_check(bool(stage.execution.stab_contact_committed), prefix + stage_name + " actual stab contact accepted")
		_check(float(stage.actual_blade.inserted_fraction) >= .50 and float(stage.actual_blade.inserted_fraction) <= .60, prefix + stage_name + " actual blade buried halfway past back anchor")
		_check(absf(float(stage.actual_blade.length_m) - float(stage.execution.blade_length_m)) < .002, prefix + stage_name + " independent blade length matches runtime")
		_check(float(stage.actual_blade.axis_direction_dot) > .99 and float(stage.actual_blade.lateral_error_m) < .01, prefix + stage_name + " blade aligned with stab axis")
		_check(bool(stage.actual_skin.found), prefix + stage_name + " independently found posed back skin")
		if bool(stage.actual_skin.found):
			_check(float(stage.actual_skin.inserted_fraction) >= .50 and float(stage.actual_skin.inserted_fraction) <= .60, prefix + stage_name + " halfway insertion measured from actual posed skin")
	if driver.stages.has("hold") and driver.stages.has("withdraw"):
		var held: Dictionary = driver.stages.hold
		var exited: Dictionary = driver.stages.withdraw
		var right := (held.camera as Transform3D).basis.x.normalized()
		var axis: Vector3 = held.execution.stab_direction
		var held_heel: Vector3 = (held.actual_blade.tip_world as Vector3) - (held.actual_blade.axis_world as Vector3) * float(held.actual_blade.length_m)
		var exited_heel: Vector3 = (exited.actual_blade.tip_world as Vector3) - (exited.actual_blade.axis_world as Vector3) * float(exited.actual_blade.length_m)
		var left_shift := -(exited_heel - held_heel).dot(right)
		var retreat := -((exited.actual_blade.tip_world as Vector3) - (held.actual_blade.tip_world as Vector3)).dot(axis)
		var exit_depth := ((exited.actual_blade.tip_world as Vector3) - (held.execution.contact_point as Vector3)).dot(axis)
		_check(left_shift > .18 and retreat > .20 and exit_depth < -.03, prefix + "actual blade exits the initial wound plane leftward and backward")
		driver.stages.withdraw["lateral_extraction"] = {"heel_left_shift_m": left_shift, "tip_retreat_m": retreat, "tip_entry_plane_depth_m": exit_depth, "reference": "original back-entry plane; victim is already a falling whole-body ragdoll"}

	_check(int(last.player_state) == DungeonPlayer.CombatState.READY and not last.execution.active, prefix + "player recovers to ready")


func _check_wrist_sequence(driver: RearDriver, prefix: String) -> void:
	var previous: Dictionary = {}
	var fixed_basis := Basis.IDENTITY
	var fixed_basis_seen := false
	var maximum_mismatch := 0.0
	var maximum_legacy_mismatch := 0.0
	var maximum_step := 0.0
	var maximum_hand_rotation := 0.0
	var maximum_blade_drift := 0.0
	var minimum_projection_fraction := INF
	var checked_axis_samples := 0
	var maximum_step_time := 0.0
	for sample: Dictionary in driver.records:
		if not bool(sample.execution.active):
			previous = {}
			continue
		var actual: Dictionary = sample.right_arm.get("actual_rig", {})
		_check(bool(actual.get("available", false)), prefix + "actual supplied wrist and elbow bones are captured")
		if not bool(actual.get("available", false)): continue
		var time := float(sample.execution.elapsed)
		var depth := float(sample.actual_blade.axis_depth_m)
		var strict_axis := (time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.WITHDRAW_END and depth > 0.0) or (time >= REAR_MOTION.STAB_HIT and time <= REAR_MOTION.WITHDRAW_END) or absf(time - REAR_MOTION.CUT_HIT) <= 1.0 / 60.0
		if strict_axis:
			checked_axis_samples += 1
			maximum_mismatch = maxf(maximum_mismatch, float(actual.axis_mismatch_degrees))
			maximum_legacy_mismatch = maxf(maximum_legacy_mismatch, float(actual.legacy_axis_mismatch_degrees))
			_check(float(actual.axis_mismatch_degrees) <= 45.0, prefix + "hand-to-forearm authored axis mismatch at %.4fs stays within 45 degrees (actual %.3f)" % [time, actual.axis_mismatch_degrees])
		if time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.HOLD_END:
			var basis := (sample.weapon_transform as Transform3D).basis.orthonormalized()
			if not fixed_basis_seen:
				fixed_basis = basis
				fixed_basis_seen = true
			var drift := WRIST_METRICS.basis_angle_degrees(fixed_basis, basis)
			maximum_blade_drift = maxf(maximum_blade_drift, drift)
			_check(drift <= .10, prefix + "axial thrust and hold keep real world blade rotation fixed")
		if time >= REAR_MOTION.STAB_HIT and time <= REAR_MOTION.CUT_HIT:
			var projection: Dictionary = sample.actual_blade.projection
			minimum_projection_fraction = minf(minimum_projection_fraction, float(projection.projected_span_viewport_fraction))
			_check(int(projection.in_frame_samples) >= 2 and float(projection.projected_span_px) > 1.0, prefix + "exposed steel has a non-degenerate on-screen projection through the lethal lateral cut")
		if previous.is_empty() and not driver.before_begin.is_empty():
			var entry_rig: Dictionary = driver.before_begin.right_arm.get("actual_rig", {})
			if bool(entry_rig.get("available", false)): previous = {"actual": entry_rig, "time": 0.0}
		if not previous.is_empty():
			var step := WRIST_METRICS.actual_joint_step(previous.actual, actual)
			var rotation := WRIST_METRICS.basis_angle_degrees(previous.actual.hand_basis_world, actual.hand_basis_world)
			if step > maximum_step:
				maximum_step = step
				maximum_step_time = time
			maximum_hand_rotation = maxf(maximum_hand_rotation, rotation)
			_check(step < .12 and rotation < 45.0, prefix + "actual 60Hz hand/arm joints stay below 12cm / 45deg per tick at %.4fs" % time)
		previous = {"actual": actual, "time": time}
	if bool(driver.began.get("accepted", false)):
		_check(checked_axis_samples >= 40 and fixed_basis_seen, prefix + "complete embedded and lateral-extraction interval was measured at actual 60Hz")
	driver.wrist_summary = {"axis_samples": checked_axis_samples, "maximum_axis_mismatch_degrees": maximum_mismatch,
		"maximum_legacy_axis_mismatch_degrees": maximum_legacy_mismatch, "maximum_joint_step_m": maximum_step,
		"maximum_step_time": maximum_step_time, "maximum_hand_rotation_step_degrees": maximum_hand_rotation,
		"maximum_embedded_blade_rotation_degrees": maximum_blade_drift,
		"minimum_exposed_blade_projection_fraction": minimum_projection_fraction if is_finite(minimum_projection_fraction) else 0.0,
		"projection_occlusion_verified": false}


func _rear_hashes() -> Dictionary:
	var hashes := {}
	for source: String in REAR_SOURCES:
		var digest := FileAccess.get_sha256(source)
		_check(digest.length() == 64, "Source exists: " + source)
		hashes[source] = digest
	return hashes


func _add_rear_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "RearTakedownFloor"
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position.y = -.1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, .2, 20)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)


func _rear_overlay(viewport: SubViewport, title: String) -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 20
	viewport.add_child(layer)
	return _add_label(layer, title, Vector2(20, 16), 18)
