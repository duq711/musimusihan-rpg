extends "res://tests/creep_ragdoll_preview.gd"
## Production rear sword takedown and an alerted-target refusal, on live AI.
## Audited hidden GPU capture only: 30 rendered fps, actual 60 Hz physics.
const ARMS := preload("res://tests/player_arm_preview.gd")
const REAR_MOTION := preload("res://scripts/rear_takedown_motion.gd")
const WRIST_METRICS := preload("res://tests/rear_takedown_test.gd")
const REAR_CASES := [
	{"id": "rear_sword", "alerted": false, "frames": 180, "title": "후방 제압 · 찌르기·출혈 → 비틀기 → 뽑기 / STAB + BLOOD → TWIST → PULL-OUT"},
	{"id": "alerted_denial", "alerted": true, "frames": 90, "title": "경계 중인 적 · 제압 거부 / ALERTED TARGET · TAKEDOWN REFUSED"},
]
const REAR_STAGES := {
	"prepare": REAR_MOTION.PREPARE_END,
	"before_contact": REAR_MOTION.STAB_CONTACT - .03,
	"first_contact": REAR_MOTION.STAB_CONTACT,
	"impact": REAR_MOTION.STAB_CONTACT + .04,
	"recoil": REAR_MOTION.STAB_CONTACT + .08,
	"thrust_mid": (REAR_MOTION.PREPARE_END + REAR_MOTION.STAB_HIT) * .5,
	"stab": REAR_MOTION.STAB_HIT,
	"twist_mid": (REAR_MOTION.TWIST_START + REAR_MOTION.TWIST_END) * .5,
	"twist_end": REAR_MOTION.TWIST_END,
	"hold": REAR_MOTION.HOLD_END - .05,
	"withdraw_mid": (REAR_MOTION.HOLD_END + REAR_MOTION.WITHDRAW_END) * .5,
	"clear": REAR_MOTION.WITHDRAW_END,
	"recover": REAR_MOTION.RECOVER_START,
	"recovered": REAR_MOTION.DURATION,
}
const REAR_SOURCES := [
	"res://scripts/player.gd", "res://scripts/enemy.gd", "res://scripts/creep_enemy.gd",
	"res://scripts/rear_takedown_motion.gd", "res://scripts/rear_sword_reaction.gd",
	"res://scripts/rear_stab_blood_effect.gd", "res://scripts/creep_wound_effect.gd",
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
	var first_release: Dictionary = {}
	var first_blood: Dictionary = {}
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
		if int(sample.blood.burst_count) > 0 and first_blood.is_empty(): first_blood = sample.duplicate(true)
		if actor.health <= 0.0 and first_death.is_empty(): first_death = sample.duplicate(true)
		if actor.health <= 0.0 and str(sample.ragdoll.phase) in ["simulating", "settled"] and first_release.is_empty(): first_release = sample.duplicate(true)
		if "head" in sample.dismemberment.severed and first_head_detach.is_empty(): first_head_detach = sample.duplicate(true)
		for stage_name: String in REAR_STAGES:
			if bool(began.get("accepted", false)) and not stages.has(stage_name) and max_elapsed + .000001 >= float(REAR_STAGES[stage_name]):
				var stage: Dictionary = sample.duplicate(true)
				stage["expected_execution_seconds"] = REAR_STAGES[stage_name]
				if stage_name in ["before_contact", "first_contact", "recoil", "stab", "hold"]:
					var posed_skin := WRIST_METRICS.bake_visible_skin(actor)
					stage["actual_skin"] = measure_back_skin(stage.actual_blade, stage.execution, posed_skin)
					if stage_name in ["stab", "hold"]:
						stage["far_side_visibility"] = WRIST_METRICS.measure_far_side_visibility(player.camera, stage.actual_blade.tip_world, stage.actual_skin, posed_skin, player.camera.global_position - player.camera.global_basis * REAR_MOTION.contact_lean(player.execution_elapsed))
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
		var bone_world := WRIST_METRICS.capture_head_bones(actor)
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
			"blood": actor.get_rear_takedown_blood_snapshot(),
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
			elif elapsed > REAR_MOTION.RECOVER_START: requested = requested.lerp(player._rear_arm_entry.shoulder, smoothstep(REAR_MOTION.RECOVER_START, REAR_MOTION.DURATION, elapsed))
		if player.is_execution_active(): requested -= REAR_MOTION.contact_lean(elapsed)
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
		var torso_hit: Dictionary = actor.query_located_hit(tip - axis * length_m, tip, .045)
		var projection := WRIST_METRICS.measure_blade_projection(player.camera, tip - axis * length_m, tip, contact, direction)
		return {"length_m": length_m, "tip_world": tip, "base_world": base,
			"projection": projection,
			"axis_world": axis, "axis_depth_m": depth, "inserted_fraction": depth / maxf(length_m, .000001),
			"anchor_world": contact, "lateral_error_m": (offset - direction * depth).length(),
			"axis_direction_dot": axis.dot(direction),
			"located_contact": torso_hit, "torso_contact": torso_hit.get("region", "") == "torso"}

	func measure_back_skin(blade: Dictionary, execution: Dictionary, posed_skin: Array[Dictionary] = []) -> Dictionary:
		var heel: Vector3 = (blade.tip_world as Vector3) - (blade.axis_world as Vector3) * float(blade.length_m)
		return WRIST_METRICS.measure_skin_passage(actor, heel, blade.tip_world, execution.contact_point, execution.stab_direction, posed_skin)


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
		var inspections := _create_passage_inspection_views(world.get_world_3d()) if not bool(scenario.alerted) else {}
		var inspection_stills := {}
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
			# Secondary cameras share this exact World3D and render the same physics
			# sample. Neither the actor nor blade is reposed or mirrored for them.
			var inspection_stage := ""
			for candidate: String in ["prepare", "before_contact", "first_contact", "impact", "recoil", "thrust_mid", "stab", "twist_mid", "twist_end", "hold", "withdraw_mid", "clear", "recover"]:
				if driver.stages.has(candidate) and not inspection_stills.has(candidate): inspection_stage = candidate
			if not inspection_stage.is_empty():
				for angle: String in inspections:
					var inspection: Dictionary = inspections[angle]
					var camera: Camera3D = inspection.camera
					_frame_passage_inspection(camera, angle, sample)
					inspection.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			if not inspection_stage.is_empty():
				var files := {}
				for angle: String in inspections:
					var inspection: Dictionary = inspections[angle]
					var image: Image = inspection.viewport.get_texture().get_image()
					var shot: String = "rear_sword_%s_%s.png" % [inspection_stage, angle]
					_check(image != null and not image.is_empty() and image.save_png(directory.path_join(shot)) == OK, "Actual same-pose passage inspection saved: " + shot)
					files[angle] = {"file": shot, "camera": inspection.camera.global_transform}
				inspection_stills[inspection_stage] = {"tick": driver.tick, "execution_elapsed": sample.execution.elapsed, "weapon_transform": sample.weapon_transform, "enemy_root": sample.enemy_root, "views": files, "same_physics_sample": true}
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
			"damage_events": driver.damage_events, "first_death": driver.first_death, "first_release": driver.first_release, "first_blood": driver.first_blood, "last_alive_before_death": driver.last_alive_before_death, "first_head_detach": driver.first_head_detach,
			"stages": driver.stages, "stills": stills, "passage_inspection_stills": inspection_stills, "camera_inspection_tilt": driver.changed_camera,
			"maximum_shoulder_adjustment_m": driver.max_shoulder_adjustment_m,
			"maximum_requested_arm_reach_m": driver.max_requested_arm_reach_m,
			"wrist_metrics": driver.wrist_summary,
			"minimum_shoulder_camera_z_m": driver.minimum_shoulder_camera_z_m if is_finite(driver.minimum_shoulder_camera_z_m) else 0.0,
			"physics_samples": driver.records, "final_creep": actor.get_creep_snapshot()})
		print("REAR TAKEDOWN CASE: ", scenario.id, " | accepted ", driver.began.get("accepted", false), " | defeats ", driver.defeats)
		if not bool(scenario.alerted):
			for required: String in ["prepare", "before_contact", "first_contact", "impact", "recoil", "thrust_mid", "stab", "twist_mid", "twist_end", "hold", "withdraw_mid", "clear", "recover"]:
				_check(inspection_stills.has(required), "same-pose full-arm, hand and head/neck side/front closeups captured: " + required)
		for view: Dictionary in inspections.values(): view.viewport.queue_free()
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
		"capture_scope": "Actual DungeonPlayer sword and live Creep AI. One begin_rear_takedown call at .6 seconds per case. Production actual contact emits one world-space blood burst, deep stab kills once, a single 20-degree twist produces a second held-body reaction, then steel withdraws on the same line, and releases attached-head ragdoll only after actual steel clears. No forced damage, death, pose, detached-part position or contact.",
		"depth_measurement": "Displayed blade vertices are scanned independently at every physics tick. Actual visible torso triangles establish entry and far-side exit at contact, deep stab and held death. Pull-out must remain on the same axis with roll fixed after the single 20-degree twist and monotonic decreasing penetration. The first physical release records actual clearance beyond the original held entry plane. Dead targets intentionally stop answering combat hit queries; held-skin triangles and pre-death samples provide independent geometry evidence.",
		"far_side_visibility_measurement": "At deep stab and hold, all visible posed CreepPart torso, head and limb meshes are baked once for both actual skin passage and camera ray tests. Twenty-five steel samples from opposite-skin exit to real blade tip are tested against every triangle in both windings. At least four must be unoccluded and in frame, spanning at least 30px at a normalized 960px viewport width. The contact eye must stay 6–25cm outside skin; its extra lean segment is also checked against both triangle windings. This verifies target-skin occlusion; actual same-pose GPU images inspect remaining hand, sleeve, blood and environment overlap. The old heel-side frustum-only projection is retained separately and is not evidence of far-side visibility.",
		"arm_measurement": "Actual fitted shoulder/elbow/wrist are recorded in world and camera space every physics tick. The real rendered rig also measures blade-to-forearm angle, elbow behind/right of wrist, and palm-anchor/digit-bone position relative to the handle. Bone distances and a fixed palm anchor do not prove skin contact; separate GPU grip-side closeups inspect it. During the full active takedown, shoulder displacement from its anatomical rest anchor must stay within 4.5cm, its eye-relative anchor counter-translates the 45cm close lean so the real arm does not move with the eyes, and upper/forearm lengths remain 34/26cm. Side inspection frames the whole shoulder/elbow/wrist and sword at preparation, mid-thrust, deepest stab and hold, in the same world pose.",
		"wrist_measurement": "Actual supplied wrist/elbow bones independently measure hand-to-forearm neutral-axis mismatch, not a clinical wrist angle. Embedded and withdrawal samples retain the existing 45-degree limit, actual 60Hz joint continuity, and fixed-length arm checks. Actual sword world rotation must match the single timed 20-degree twist within 0.1 degrees, with no other roll or sideways slicing; lateral tip displacement stays within 2mm through thrust, twist, hold and straight withdrawal. All 17 actual gripping-hand landmarks must be outside the first-person frustum during deepest contact. GPU images independently verify the entire skin/glove silhouette. Near-side heel projection is retained only as a diagnostic.",
		"camera_motion": "A smooth 45cm eye lean closes the final shoulder gap; hand and sword remain at their world-space contact. No FOV change, hand hiding or scale change. Starts 1.15m behind the actual actor, aimed at back skin. Production aiming and a collision-tested curved approach move beside the left shoulder for a close over-shoulder view of the real protruding blade. During straight withdrawal the capsule reverses the approach to keep the hand reachable. Only after completion, capture-only pitch tilt inspects the intact corpse. Alerted control keeps its initial camera and runs live AI.",
		"input_scope": "No OS keyboard/mouse/focus, hardware cursor change, desktop capture or audible playback. Labels are inspection subtitles. The alerted control is initialized in CHASE, then runs normal AI; the rear case starts unaware in IDLE.",
		"reference_scope": "Latest user references are the Far Cry close-contact image (1b1c4f8c) and rejected hand-visible game frame (d5e0cf5b). Contact must place the gripping hand entirely outside the first-person view. The attached Far Cry rear-takedown screenshot was opened and visually inspected: close shoulder framing and visible far-side steel guide the camera and approach. Existing game weapon, target and straight extraction are retained. Source video was not watched this turn; this is not a frame-matched recreation.",
		"inspection_geometry_scope": "First-person arm geometry; the third-person avatar body layer is excluded just like the main first-person camera. All inspection views share the same live world, first-person arm, weapon and enemy pose; no actor or weapon is reposed or mirrored.",
		"visual_acceptance_scope": "Numerical tests alone do not approve the appearance. Separately inspect the actual first-person clip, complete-arm side silhouettes and grip closeups for thumb closure, fingers staying around the hilt, continuous shoulder/elbow/wrist, and hand size in the frame.",
		"contact_reaction_measurement": "Before-contact, first-contact, early recoil and full-depth frames independently intersect visible posed torso skin. Blood begins once at the actual blade-contact event. Full-depth chest recoil and the later twist response are measured from actual bone transforms. The final twist pose is retained until real tip clearance; capsule hit queries are not substituted for visible skin evidence.",
		"head_reaction_measurement": "Actual Head-to-native-Jaw1/Jaw2-pivot direction measures snout elevation, including the model's downward resting face. Actor forward and authored angle values are not substituted. Before-contact face and jaw must remain unchanged; deepest stab requires more than 30 degrees of real face lift and above 10 degrees world elevation, with rotation shared by Neck and Head and the actual lower jaw opening. Same-pose head_side/head_front images require independent visual inspection; no scream audio is claimed.",
		"blood_measurement": "One target-owned pausable world-space effect emits 24 actual mesh droplets at the validated entry point. Every physics frame records burst count and effect age, real droplet positions, velocities, stains and visibility. Side/front/hand closeups at impact and twist use the same 3D scene; visual blood appearance must be inspected separately.",
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
				var actual: Dictionary = sample.right_arm.actual_rig
				_check(absf(float(actual.thrust_grip_amount) - REAR_MOTION.grip_blend(float(sample.execution.elapsed))) < .0001, prefix + "rendered hand follows the rear-only diagonal grip clock")
				_check(float(actual.actual_wrist_fit_error_m) < .001 and float(actual.actual_neutral_api_error_degrees) < .1, prefix + "real wrist/hand axis match the rear IK helper coordinates")
				_check(float(actual.planned_grip_offset_error_m) < .001, prefix + "actual palm anchor follows the planned hand-to-hilt contact offset")
				_check(float(sample.right_arm.actual_shoulder_adjustment_m) <= .045, prefix + "shoulder stays attached throughout takedown (maximum 4.5cm adjustment)")
				_check((sample.right_arm.camera.shoulder as Vector3).z >= .015, prefix + "upper-arm origin remains behind the first-person camera")
				_check(absf(float(sample.right_arm.upper_length_m) - .34) <= .004 and absf(float(sample.right_arm.forearm_length_m) - .26) <= .003, prefix + "actual arm segments retain anatomical lengths")
			if float(sample.execution.elapsed) < REAR_MOTION.STAB_HIT - .000001:
				_check(float(sample.health) > 0.0 and not ("head" in sample.dismemberment.severed), prefix + "alive with attached head until actual deep-stab contact")
			if float(sample.health) <= 0.0 and float(sample.execution.elapsed) <= REAR_MOTION.WITHDRAW_END:
				var depth := float(sample.actual_blade.axis_depth_m)
				if str(sample.ragdoll.phase) == "execution_hold":
					_check(int(sample.ragdoll.bodies) == 0 and depth > -REAR_MOTION.WITHDRAW_CLEARANCE - .002, prefix + "embedded sword supports held corpse before physics starts")
				elif driver.first_release.is_empty() or int(sample.tick) == int(driver.first_release.tick):
					_check(depth <= -REAR_MOTION.WITHDRAW_CLEARANCE + .002, prefix + "first rigid-body frame requires actual blade clearance")
			if float(sample.execution.elapsed) <= REAR_MOTION.STAB_CONTACT:
				_check(is_zero_approx(float(sample.reaction.get("recoil_weight", -1.0))), prefix + "no victim recoil before the first physical blade-contact clock")
		elif int(sample.player_state) == DungeonPlayer.CombatState.READY:
			_check(not sample.world_contact, prefix + "ready restores normal first-person rendering")
			if bool(sample.right_arm.available):
				_check(is_zero_approx(float(sample.right_arm.actual_rig.thrust_grip_amount)), prefix + "ready and refused actions retain the original non-thrust grip")
	if bool(scenario.alerted):
		_check(driver.first_blood.is_empty() and int(last.blood.burst_count) == 0, prefix + "denied target emits no rear-stab blood")
		_check(not bool(driver.began.get("accepted", false)) and not driver.before_begin.candidate_is_actor, prefix + "alerted target refuses rear takedown")
		_check(int(driver.before_begin.enemy_state) != DungeonEnemy.AIState.IDLE, prefix + "refusal used a genuinely alerted AI state")
		_check(driver.defeats == 0 and driver.landed == 0 and is_equal_approx(float(last.health), 118.0), prefix + "refusal causes no attack or damage")
		_check((last.dismemberment.severed as Array).is_empty() and last.ragdoll.phase == "living", prefix + "refused target stays intact and alive")
		return
	_check(bool(driver.began.get("accepted", false)) and driver.before_begin.candidate_is_actor, prefix + "actual unaware rear target accepted")
	_check(int(driver.before_begin.enemy_state) == DungeonEnemy.AIState.IDLE, prefix + "enemy was unaware immediately before reservation")
	_check(driver.defeats == 1 and driver.landed == 1 and is_zero_approx(float(last.health)), prefix + "one production lethal stab, defeat and reward event")
	if driver.stages.has("stab"):
		var actual: Dictionary = driver.stages.stab.right_arm.actual_rig
		_check(float(actual.blade_forearm_angle_degrees) <= 25.0, prefix + "close takedown aligns the rendered blade within 25 degrees of forearm extension")
		_check(float(actual.elbow_extension_angle_degrees) >= 70.0, prefix + "close takedown keeps a tucked elbow open at least 70 degrees without requiring a distant fully extended thrust")
		_check(float(actual.axis_mismatch_degrees) <= 25.0, prefix + "close takedown keeps the actual hand/forearm neutral-axis mismatch within 25 degrees")
		_check(float(actual.elbow_behind_wrist_along_blade_m) > .15, prefix + "deep thrust keeps the rendered elbow more than 15cm behind the wrist along the blade")
	_check((last.dismemberment.severed as Array).is_empty() and int(last.dismemberment.detached_bodies) == 0, prefix + "head and all limbs remain attached")
	_check(str(last.ragdoll.phase) in ["simulating", "settled"] and int(last.ragdoll.bodies) > 0, prefix + "actual rigid-body corpse simulation")
	_check(float(last.initial_chest_distance_m) > .20, prefix + "corpse physically moved from standing pose")
	_check(not driver.first_death.is_empty() and driver.first_head_detach.is_empty(), prefix + "lethal contact is recorded without any head-detachment event")
	if not driver.first_death.is_empty():
		_check(absf(float(driver.first_death.execution.elapsed) - REAR_MOTION.STAB_HIT) <= 1.0 / 60.0 + .00001, prefix + "death occurs at the actual deep-stab contact")
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
			_check(bool(live.actual_blade.torso_contact) and float(live.execution.elapsed) >= REAR_MOTION.STAB_HIT - 2.0 / 60.0 - .00001, prefix + "displayed thrusting blade intersects the actual live torso immediately before lethal contact")
		_check((driver.first_death.dismemberment.severed as Array).is_empty() and int(driver.first_death.dismemberment.detached_bodies) == 0, prefix + "lethal contact preserves the complete physical body")

	for stage_name: String in REAR_STAGES:
		_check(driver.stages.has(stage_name), prefix + "stage recorded: " + stage_name)
	_check_physical_contact_recoil(driver, prefix)
	_check_blood_and_twist_reaction(driver, prefix)
	_check_actual_head_lift(driver, prefix)
	for stage_name: String in ["stab", "hold"]:
		if not driver.stages.has(stage_name): continue
		var stage: Dictionary = driver.stages[stage_name]
		_check(bool(stage.execution.stab_contact_committed), prefix + stage_name + " actual stab contact accepted")
		_check(float(stage.actual_blade.inserted_fraction) >= .89 and float(stage.actual_blade.inserted_fraction) <= .99, prefix + stage_name + " actual blade buried nearly its full length past back anchor")
		_check(absf(float(stage.actual_blade.length_m) - float(stage.execution.blade_length_m)) < .002, prefix + stage_name + " independent blade length matches runtime")
		_check(float(stage.actual_blade.axis_direction_dot) > .99 and float(stage.actual_blade.lateral_error_m) < .01, prefix + stage_name + " blade aligned with stab axis")
		_check(bool(stage.actual_skin.found), prefix + stage_name + " independently found posed back and opposite skin")
		if bool(stage.actual_skin.found):
			_check(stage.actual_skin.entry_mesh == "CreepPart_torso" and stage.actual_skin.exit_mesh == "CreepPart_torso", prefix + stage_name + " entry and farthest opposite exit both belong to actual torso skin, not the head")
			_check(float(stage.actual_skin.exit_protrusion_m) > .03 and float(stage.actual_skin.heel_depth_m) < -.008, prefix + stage_name + " actual blade protrudes beyond opposite skin while guard remains outside entry")
			_check(float(stage.actual_skin.inserted_fraction) >= .89 and float(stage.actual_skin.inserted_fraction) <= .99, prefix + stage_name + " near-full insertion measured from actual posed skin")
		var visibility: Dictionary = stage.get("far_side_visibility", {})
		_check(bool(visibility.get("found_exit", false)) and int(visibility.get("visible_samples", 0)) >= 4, prefix + stage_name + " at least four opposite-side blade samples are in frame and unobscured by real posed target skin")
		_check(float(visibility.get("visible_span_at_960_px", 0.0)) >= 30.0, prefix + stage_name + " opposite-side protruding steel occupies at least 30px at 960px width after skin occlusion")
		_check(float(visibility.get("camera_skin_clearance_m", 0.0)) >= .06 and float(visibility.get("camera_skin_clearance_m", 99.0)) <= .25, prefix + stage_name + " eyes remain 6–25cm outside the actual posed monster skin")
		_check(bool(visibility.get("eye_sweep_measured", false)) and not bool(visibility.get("eye_lean_crosses_skin", true)), prefix + stage_name + " eye lean never crosses the actual posed target skin")
	_check(not driver.first_release.is_empty(), prefix + "actual blade-clear ragdoll release was recorded")
	if not driver.first_release.is_empty():
		var release: Dictionary = driver.first_release
		_check(float(release.actual_blade.axis_depth_m) <= -REAR_MOTION.WITHDRAW_CLEARANCE + .002 and float(release.execution.elapsed) > REAR_MOTION.HOLD_END and float(release.execution.elapsed) <= REAR_MOTION.WITHDRAW_END + 1.0 / 60.0, prefix + "ragdoll starts only after straight blade clearance")
		_check(not bool(release.ragdoll.execution_held) and not str(release.ragdoll.execution_release_reason).is_empty(), prefix + "corpse records its one completed physical release")
		_check(int(release.defeats) == 1 and int(release.landed) == 1, prefix + "release cannot create a second kill or reward")
	if driver.stages.has("hold") and driver.stages.has("clear"):
		var held: Dictionary = driver.stages.hold
		var exited: Dictionary = driver.stages.clear
		var axis: Vector3 = held.execution.stab_direction
		var shift: Vector3 = (exited.actual_blade.tip_world as Vector3) - (held.actual_blade.tip_world as Vector3)
		var lateral := (shift - axis * shift.dot(axis)).length()
		var exit_depth := ((exited.actual_blade.tip_world as Vector3) - (held.execution.contact_point as Vector3)).dot(axis)
		_check(lateral < .002 and exit_depth <= -REAR_MOTION.WITHDRAW_CLEARANCE + .002, prefix + "actual sword leaves the wound on the same straight line without a sideways slice")
		_check(str(held.ragdoll.phase) == "execution_hold" and int(held.ragdoll.bodies) == 0, prefix + "deep hold supports dead body instead of starting early ragdoll")
		exited["straight_extraction"] = {"lateral_tip_shift_m": lateral, "tip_retreat_m": -shift.dot(axis), "tip_entry_plane_depth_m": exit_depth, "reference": "original held back-entry plane; first physical release requires actual tip clearance"}
	if driver.stages.has("withdraw_mid"):
		var middle: Dictionary = driver.stages.withdraw_mid
		_check(middle.ragdoll.phase == "execution_hold" and int(middle.ragdoll.bodies) == 0, prefix + "partly withdrawn blade still holds the corpse")
		if driver.stages.has("twist_end"):
			for bone: String in ["Chest", "Neck", "Head"]:
				_check((middle.bone_world[bone] as Transform3D).is_equal_approx(driver.stages.twist_end.bone_world[bone]), prefix + "corpse retains its exact completed twist reaction until steel is clear: " + bone)

	_check(int(last.player_state) == DungeonPlayer.CombatState.READY and not last.execution.active, prefix + "player recovers to ready")


func _check_physical_contact_recoil(driver: RearDriver, prefix: String) -> void:
	if driver.before_begin.is_empty(): return
	var initial_chest: Transform3D = driver.before_begin.bone_world.Chest
	for name_value: String in ["before_contact", "first_contact", "recoil", "stab"]:
		if not driver.stages.has(name_value): continue
		var stage: Dictionary = driver.stages[name_value]
		var skin: Dictionary = stage.get("actual_skin", {})
		_check(bool(skin.get("found", false)) and skin.get("entry_mesh", "") == "CreepPart_torso", prefix + name_value + " contact timing independently resolves real posed torso skin")
		if not bool(skin.get("found", false)): continue
		var depth := float(skin.depth_m)
		var recoil := float(stage.reaction.get("recoil_weight", -1.0))
		var chest: Transform3D = stage.bone_world.Chest
		var chest_change := WRIST_METRICS.basis_angle_degrees(initial_chest.basis.orthonormalized(), chest.basis.orthonormalized())
		if name_value == "before_contact":
			_check(depth < 0.0 and is_zero_approx(recoil) and chest_change < .01, prefix + "victim remains unreactive before actual steel reaches its back skin")
		else:
			_check(depth >= -.002 and recoil > 0.0 and chest_change > .01, prefix + name_value + " rendered recoil begins only after actual blade/skin contact")
		if name_value == "first_contact":
			_check(depth < .08 and float(stage.execution.elapsed) - REAR_MOTION.STAB_CONTACT <= 1.0 / 60.0 + .00001, prefix + "first-contact evidence is the first actual physics sample after entry, not a later buried frame")
		if name_value == "recoil":
			_check(recoil > .20, prefix + "victim has a visible early reaction while the thrust is still advancing")
		if name_value == "stab":
			_check(recoil > .95 and float(stage.reaction.get("contact_weight", -1.0)) > .99 and float(stage.reaction.get("penetration_weight", -1.0)) > .95 and chest_change > 5.0, prefix + "maximum-depth frame already contains full penetration recoil and real chest movement")
		stage["contact_reaction_geometry"] = {"actual_skin_depth_m": depth, "actual_chest_rotation_degrees": chest_change, "recoil_weight": recoil, "actual_entry_mesh": skin.entry_mesh}


func _check_actual_head_lift(driver: RearDriver, prefix: String) -> void:
	for key: String in ["before_contact", "first_contact", "recoil", "stab", "twist_mid", "twist_end", "hold", "withdraw_mid"]:
		if not driver.stages.has(key): continue
		var sample: Dictionary = driver.stages[key]
		var measured := WRIST_METRICS.measure_head_lift(driver.before_begin.bone_world, sample.bone_world)
		sample["actual_head_lift"] = measured
		_check(bool(measured.available), prefix + key + " actual head/neck/native jaw geometry available")
		if not bool(measured.available): continue
		_check(float(measured.neck_head_length_error_m) < .001 and float(measured.head_jaw_length_error_m) < .001, prefix + key + " head lift preserves bone lengths")
		if key == "before_contact":
			_check(float(measured.head_world_rotation_degrees) < .01 and absf(float(measured.face_lift_degrees)) < .01 and float(measured.lower_jaw_local_rotation_degrees) < .01, prefix + "face and lower jaw do not react before actual blade contact")
		elif key in ["stab", "twist_mid", "twist_end", "hold", "withdraw_mid"]:
			_check(float(measured.face_lift_degrees) > 30.0 and float(measured.face_elevation_after_degrees) > 10.0, prefix + key + " actual snout looks upward after the deep stab")
			_check(float(measured.neck_local_rotation_degrees) > 5.0 and float(measured.head_local_rotation_degrees) > 20.0, prefix + key + " actual neck and head share the extension")
			_check(float(measured.lower_jaw_local_rotation_degrees) > 15.0 and float(measured.upper_jaw_local_rotation_degrees) < .01, prefix + key + " actual lower jaw opens without rotating the upper jaw away from the head")
		else:
			_check(float(measured.face_lift_degrees) > .0 and float(sample.reaction.get("head_lift_weight", 0.0)) > .0, prefix + key + " actual head begins rising while steel advances after contact")


func _check_blood_and_twist_reaction(driver: RearDriver, prefix: String) -> void:
	for sample: Dictionary in driver.records:
		var count := int(sample.blood.burst_count)
		if driver.first_blood.is_empty() or int(sample.tick) < int(driver.first_blood.tick):
			_check(count == 0, prefix + "there is no blood burst before the actual contact event")
		else:
			_check(count == 1, prefix + "later recoil, twist and extraction cannot repeat the blood burst")
	_check(not driver.first_blood.is_empty(), prefix + "actual contact blood event recorded")
	if not driver.first_blood.is_empty():
		var impact: Dictionary = driver.first_blood
		var time := float(impact.execution.elapsed)
		var effect: Dictionary = impact.blood.effect
		_check(time >= REAR_MOTION.STAB_CONTACT - .000001 and time <= REAR_MOTION.STAB_CONTACT + 1.0 / 60.0 + .000001, prefix + "blood begins on the first actual blade-contact physics tick")
		_check(not effect.is_empty() and int(effect.get("spawned_droplet_count", 0)) == 24 and int(effect.get("visible_droplets", 0)) > 0, prefix + "blood event creates real visible world-space 3D droplets")
		_check(bool(effect.get("top_level", false)) and bool(effect.get("pausable", false)) and not bool(effect.get("emission_enabled", true)), prefix + "blood is a pausable one-shot world effect")
		_check((impact.blood.contact_point as Vector3).distance_to(impact.execution.contact_point) < .025 and (effect.origin as Vector3).distance_to(impact.blood.contact_point) < .001, prefix + "blood originates at the measured sword-entry wound")
		for point: Vector3 in effect.get("droplet_positions", []): _check(point.is_finite(), prefix + "blood droplet positions are finite actual 3D coordinates")
	if driver.stages.has("stab") and driver.stages.has("twist_mid") and driver.stages.has("twist_end"):
		var deep: Dictionary = driver.stages.stab
		for key: String in ["twist_mid", "twist_end"]:
			var sample: Dictionary = driver.stages[key]
			var chest: Transform3D = sample.bone_world.Chest
			var initial_chest: Transform3D = deep.bone_world.Chest
			var rotation := WRIST_METRICS.basis_angle_degrees(initial_chest.basis.orthonormalized(), chest.basis.orthonormalized())
			_check(rotation > 1.0 and float(sample.reaction.get("twist_weight", 0.0)) > 0.0 and absf(float(sample.reaction.get("chest_twist_angle", 0.0))) > deg_to_rad(1.0), prefix + key + " actual chest visibly follows the blade twist")
			_check(sample.ragdoll.phase == "execution_hold" and int(sample.ragdoll.bodies) == 0, prefix + key + " reaction remains supported by the embedded sword")
			if key == "twist_mid": _check(float(sample.reaction.get("twist_reaction_weight", 0.0)) > .2, prefix + "twisting produces a second visible recoil pulse")
			_check((sample.actual_blade.tip_world as Vector3).distance_to(deep.actual_blade.tip_world) < .002 and (sample.actual_blade.axis_world as Vector3).dot(deep.actual_blade.axis_world) > .9999, prefix + "twist rotates planted steel without lateral displacement")
			sample["twist_reaction_geometry"] = {"actual_chest_rotation_degrees": rotation, "reaction": sample.reaction}


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
	var maximum_lateral_shift := 0.0
	var previous_withdrawal_depth := INF
	var minimum_thrust_forearm_clearance := INF
	var minimum_preparation_forearm_clearance := INF
	for sample: Dictionary in driver.records:
		if not bool(sample.execution.active):
			previous = {}
			continue
		var actual: Dictionary = sample.right_arm.get("actual_rig", {})
		_check(bool(actual.get("available", false)), prefix + "actual supplied wrist and elbow bones are captured")
		if not bool(actual.get("available", false)): continue
		var time := float(sample.execution.elapsed)
		var depth := float(sample.actual_blade.axis_depth_m)
		if time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.HOLD_END:
			minimum_thrust_forearm_clearance = minf(minimum_thrust_forearm_clearance, float(actual.camera_forearm_centerline_clearance_m))
			_check(float(actual.camera_forearm_centerline_clearance_m) >= .14, prefix + "actual forearm centerline stays at least 14cm from camera during middle-guard thrust/hold at %.4fs" % time)
		elif time < REAR_MOTION.PREPARE_END:
			minimum_preparation_forearm_clearance = minf(minimum_preparation_forearm_clearance, float(actual.camera_forearm_centerline_clearance_m))
		var strict_axis := (time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.WITHDRAW_END and depth > 0.0) or (time >= REAR_MOTION.STAB_HIT and time <= REAR_MOTION.WITHDRAW_END)
		if strict_axis:
			checked_axis_samples += 1
			maximum_mismatch = maxf(maximum_mismatch, float(actual.axis_mismatch_degrees))
			maximum_legacy_mismatch = maxf(maximum_legacy_mismatch, float(actual.legacy_axis_mismatch_degrees))
			_check(float(actual.axis_mismatch_degrees) <= 45.0, prefix + "hand-to-forearm authored axis mismatch at %.4fs stays within 45 degrees (actual %.3f)" % [time, actual.axis_mismatch_degrees])
		if time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.WITHDRAW_END:
			var basis := (sample.weapon_transform as Transform3D).basis.orthonormalized()
			if not fixed_basis_seen:
				fixed_basis = basis
				fixed_basis_seen = true
			var expected := WRIST_METRICS.expected_rear_blade_basis(fixed_basis, sample.execution.stab_direction, time)
			var drift := WRIST_METRICS.basis_angle_degrees(expected, basis)
			maximum_blade_drift = maxf(maximum_blade_drift, drift)
			_check(drift <= .10, prefix + "actual blade follows one timed 20-degree axial twist and preserves that roll during straight pull-out")
		if time >= REAR_MOTION.PREPARE_END and time <= REAR_MOTION.WITHDRAW_END:
			maximum_lateral_shift = maxf(maximum_lateral_shift, float(sample.actual_blade.lateral_error_m))
			_check(float(sample.actual_blade.lateral_error_m) < .002, prefix + "actual blade stays on its original line with no sideways slice")
		if time >= REAR_MOTION.HOLD_END and time <= REAR_MOTION.WITHDRAW_END:
			_check(depth <= previous_withdrawal_depth + .0001, prefix + "actual tip retreats monotonically during straight extraction")
			previous_withdrawal_depth = depth
		if time >= REAR_MOTION.STAB_HIT and time <= REAR_MOTION.HOLD_END:
			var projection: Dictionary = sample.actual_blade.projection
			minimum_projection_fraction = minf(minimum_projection_fraction, float(projection.projected_span_viewport_fraction))
			_check(int(actual.hand_framing.in_frame_landmarks) == 0, prefix + "actual gripping wrist, palm and finger joints remain outside the first-person view during deep contact")
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
		_check(checked_axis_samples >= 40 and fixed_basis_seen, prefix + "complete embedded and straight-extraction interval was measured at actual 60Hz")
	driver.wrist_summary = {"axis_samples": checked_axis_samples, "maximum_axis_mismatch_degrees": maximum_mismatch,
		"maximum_legacy_axis_mismatch_degrees": maximum_legacy_mismatch, "maximum_joint_step_m": maximum_step,
		"maximum_step_time": maximum_step_time, "maximum_hand_rotation_step_degrees": maximum_hand_rotation,
		"maximum_expected_blade_rotation_error_degrees": maximum_blade_drift, "maximum_lateral_tip_shift_m": maximum_lateral_shift,
		"minimum_near_side_blade_projection_fraction": minimum_projection_fraction if is_finite(minimum_projection_fraction) else 0.0,
		"minimum_thrust_forearm_camera_clearance_m": minimum_thrust_forearm_clearance if is_finite(minimum_thrust_forearm_clearance) else 0.0,
		"minimum_preparation_forearm_camera_clearance_m": minimum_preparation_forearm_clearance if is_finite(minimum_preparation_forearm_clearance) else 0.0,
		"forearm_clearance_scope": "Actual rendered elbow/wrist centerline versus camera origin; a 14cm proxy guard from preparation-end through deep-stab hold. Preparation rotation is reported separately. Not a complete skin/sleeve collision proof.",
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


func _create_passage_inspection_views(shared_world: World3D) -> Dictionary:
	var result := {}
	for angle: String in ["side", "front", "grip_side", "head_side", "head_front"]:
		var inspection := SubViewport.new()
		inspection.name = "PassageInspection_" + angle
		inspection.size = Vector2i(960, 720)
		inspection.world_3d = shared_world
		inspection.gui_disable_input = true
		inspection.physics_object_picking = false
		inspection.audio_listener_enable_3d = false
		inspection.msaa_3d = Viewport.MSAA_2X
		inspection.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(inspection)
		var camera := Camera3D.new()
		camera.near = .025
		camera.fov = 48.0
		camera.cull_mask = ((1 << 20) - 1) & ~DungeonPlayer.PLAYER_APPEARANCE.BODY_LAYER
		inspection.add_child(camera)
		camera.make_current()
		var title: String = {"side": "전체 팔 측면", "front": "정면", "grip_side": "손·파지 확대", "head_side": "머리·목 측면", "head_front": "머리·목 정면"}[angle]
		_rear_overlay(inspection, "1인칭 팔 · 동일 자세 · %s / FP ARM · SAME POSE · %s" % [title, angle.to_upper()])
		result[angle] = {"viewport": inspection, "camera": camera}
	return result


func _frame_passage_inspection(camera: Camera3D, angle: String, sample: Dictionary) -> void:
	if angle in ["head_side", "head_front"]:
		# These cameras inspect the same real head/neck pose, never a separately
		# posed face. Actor forward keeps framing independent of blade recovery.
		var head: Transform3D = sample.bone_world.Head
		var neck: Transform3D = sample.bone_world.Neck
		var actor_basis: Basis = (sample.enemy_root as Transform3D).basis.orthonormalized()
		var forward := -actor_basis.z
		var focus := neck.origin.lerp(head.origin, .7) + Vector3.UP * .09
		var offset := actor_basis.x * 1.10 + forward * .18 if angle == "head_side" else forward * 1.10 + actor_basis.x * .18
		camera.global_position = focus + offset + Vector3.UP * .04
		camera.look_at(focus, Vector3.UP)
		return
	var anchor: Vector3 = sample.execution.contact_point
	var axis: Vector3 = sample.actual_blade.axis_world
	var right := axis.cross(Vector3.UP).normalized()
	var actual: Dictionary = sample.right_arm.actual_rig
	if angle == "front":
		var focus := anchor + axis * .20
		camera.global_position = focus + axis * 1.7 + right * .36 + Vector3.UP * .12
		camera.look_at(focus, Vector3.UP)
		return
	if angle == "grip_side":
		var focus: Vector3 = (actual.wrist_world as Vector3).lerp(actual.handle_center_world, .6)
		# A separate close view resolves the thumb/finger wrap that a whole-arm
		# camera cannot show. It uses this same real rig, without any repose.
		camera.global_position = focus + right * .56 - axis * .22 + Vector3.UP * .11
		camera.look_at(focus, Vector3.UP)
		return
	var landmarks: Array[Vector3] = [actual.shoulder_world, actual.elbow_world, actual.wrist_world, sample.actual_blade.base_world, sample.actual_blade.tip_world]
	var minimum := landmarks[0]
	var maximum := landmarks[0]
	for point in landmarks:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var center := (minimum + maximum) * .5
	var radius := .25
	for point in landmarks: radius = maxf(radius, point.distance_to(center))
	# Fit the complete arm and blade inside the narrower vertical field of
	# view. Keep a margin around actual landmarks for the sleeve's thickness.
	var distance := (radius + .09) / sin(deg_to_rad(camera.fov * .5))
	var offset := (right + Vector3.UP * .10 - axis * .05).normalized()
	camera.global_position = center + offset * distance
	camera.look_at(center, Vector3.UP)
