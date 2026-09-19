extends "res://tests/creep_ragdoll_preview.gd"
## Actual first-person dagger contacts: one rear kill, one surviving front hit.
## Run only in the audited embedded renderer, fixed 30 fps / real 60 Hz physics.
const ARMS := preload("res://tests/player_arm_preview.gd")
const DAGGER := preload("res://scripts/dagger_motion.gd")
const DAGGER_CASES := [
	{"id": "rear_assassination", "rear": true, "frames": 120, "title": "뒤에서 찌르기 · 한 번에 처치 / REAR STAB · ONE-HIT KILL"},
	{"id": "front_control", "rear": false, "frames": 90, "title": "정면 비교 · 일반 피해만 / FRONT CONTROL · NORMAL DAMAGE"},
]
const DAGGER_SOURCES := [
	"res://scripts/player.gd", "res://scripts/enemy.gd", "res://scripts/creep_enemy.gd",
	"res://scripts/dagger_visual.gd", "res://scripts/dagger_motion.gd", "res://scripts/inventory_model.gd",
	"res://scripts/expedition_session.gd", "res://scripts/located_hit_query.gd", "res://scripts/first_person_renderer.gd",
	"res://scripts/creep_dismemberment.gd", "res://scripts/creep_ragdoll.gd", "res://scripts/creep_ragdoll_pose.gd",
	"res://scripts/creep_locomotion_blend.gd", "res://scripts/supplied_fp_arm.gd", "res://scripts/sword_long_grip_visual.gd",
	"res://assets/3d/player/fp_arms/right.scn", "res://assets/3d/player/fp_arms/rig.json", "res://assets/ui/iron_dagger.svg",
	"res://tests/dagger_assassination_preview.gd", "res://tests/dagger_assassination_preview.gd.uid",
	"res://tests/player_arm_preview.gd", "res://tests/creep_ragdoll_preview.gd", "res://scripts/test_room_sandbox.gd",
	"res://project.godot", CREEP.MODEL_PATH, CREEP.DISMEMBERMENT.MODEL_PATH,
]

class DaggerDriver extends Node:
	var player: DungeonPlayer
	var actor
	var rear := true
	var max_ticks := 240
	var tick := 0
	var began: Dictionary = {}
	var defeats := 0
	var landed := 0
	var damage_events: Array[Dictionary] = []
	var records: Array[Dictionary] = []
	var hit_snapshot: Dictionary = {}
	var initial_pitch := 0.0
	var initial_chest := Vector3.ZERO
	var changed_camera := false

	func _physics_process(delta: float) -> void:
		tick += 1
		if not rear and actor.health > 0.0:
			# Keep the short stab aimed at the moving chest in the frontal control.
			# This is inspection-camera input, never gameplay aim assistance.
			var bone: int = actor.skeleton.find_bone("Chest")
			var chest: Vector3 = (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(bone)).origin
			var aim := chest - player.camera.global_position
			player.rotation.y = atan2(-aim.x, -aim.z)
			player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
			player.head.rotation.x = player._pitch
		if tick == (36 if rear else 6):
			began = player.begin_sword_attack()
			if bool(began.get("accepted", false)):
				player.attack_release_requested = true
		# The player input callback is disabled; these are the same runtime
		# advance/pose/contact calls made by its normal gameplay coordinator.
		player.advance_combat_state(delta)
		if rear and actor.health <= 0.0 and float(tick) / 60.0 > 1.3:
			var amount := smoothstep(1.3, 2.1, float(tick) / 60.0)
			player._pitch = lerpf(initial_pitch, deg_to_rad(-43.0), amount)
			player.head.rotation.x = player._pitch
			changed_camera = true
		player._update_viewmodel(delta)
		var health_before: float = actor.health
		var before := capture_state()
		player._resolve_active_attack()
		actor._resolve_active_attack()
		player.viewmodel_renderer.sync_view()
		var after := capture_state()
		if actor.health < health_before and hit_snapshot.is_empty():
			hit_snapshot = {"before": before, "after": after}
		records.append(after)
		if tick >= max_ticks: set_physics_process(false)

	func _on_defeated(_enemy: DungeonEnemy) -> void:
		defeats += 1

	func _on_attack_landed(damage: float, headshot: bool) -> void:
		landed += 1
		damage_events.append({"tick": tick, "damage": damage, "headshot": headshot})

	func capture_state() -> Dictionary:
		var contact: Dictionary = player._located_melee_contact(actor, player.get_melee_reach()) if actor.health > 0.0 else {}
		var tip: Vector3 = player.dagger_visual_root.get_node("BladeTip").global_position
		var forward := -player.camera.global_basis.z.normalized()
		var blade_tip_error := -1.0
		var blade_tip_depth := 0.0
		var blade_lateral_error := -1.0
		var contact_data := {}
		if not contact.is_empty():
			var offset: Vector3 = tip - contact.position
			blade_tip_error = offset.length()
			blade_tip_depth = offset.dot(forward)
			blade_lateral_error = (offset - forward * blade_tip_depth).length()
			contact_data = {"position": contact.position, "region": contact.get("region", ""), "fraction": contact.get("fraction", -1.0)}
		var chest_bone: int = actor.skeleton.find_bone("Chest")
		var chest: Vector3 = (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(chest_bone)).origin
		return {"tick": tick, "seconds": float(tick) / 60.0, "player_state": player.combat_state,
			"player_state_time": player.state_time, "enemy_state": actor.ai_state, "health": actor.health,
			"player_health": player.health, "ragdoll_phase": actor.ragdoll.phase,
			"defeats": defeats, "landed": landed, "enemy_root": actor.global_transform,
			"enemy_chest": chest, "initial_chest_distance_m": chest.distance_to(initial_chest),
			"target_is_actual_player": actor.target == player, "enemy_ai_enabled": actor.is_physics_processing(),
			"rear_eligible": actor.can_receive_dagger_assassination(player.global_position),
			"player_position": player.global_position, "camera": player.camera.global_transform,
			"dagger_visible": player.dagger_visual_root.is_visible_in_tree(),
			"sword_visible": player.sword_visual_root.is_visible_in_tree(),
			"left_support_visible": player.left_support_arm.is_visible_in_tree() or player.sword_support_arm.is_visible_in_tree(),
			"world_contact": player.viewmodel_renderer.world_contact_enabled,
			"contact": contact_data, "blade_tip": tip, "blade_tip_contact_distance_m": blade_tip_error,
			"blade_axis_penetration_m": blade_tip_depth, "blade_lateral_error_m": blade_lateral_error,
			"blade_axis_forward_dot": player.dagger_visual_root.global_basis.y.normalized().dot(forward)}


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Use the audited embedded runner with Dummy audio and --fixed-fps 30."); quit(2); return
	var tag := OS.get_environment("DAGGER_ASSASSINATION_QA_ITERATION").strip_edges()
	if not tag.is_valid_filename() or tag.begins_with(".") or not CREEP.is_available():
		push_error("Set a new DAGGER_ASSASSINATION_QA_ITERATION and install the Creep asset."); quit(2); return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Dagger preview requires its own isolated session."); quit(2); return
	var directory := ProjectSettings.globalize_path("res://artifacts/visual_qa/dagger_assassination/" + tag)
	if DirAccess.dir_exists_absolute(directory):
		push_error("Existing dagger captures will not be overwritten."); quit(2); return
	if DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) != OK:
		push_error("Could not create dagger capture directory."); quit(2); return
	root.gui_disable_input = true
	root.physics_object_picking = false
	var session_before := ExpeditionSession.capture_snapshot()
	var inventory_before: ExpeditionInventory = session_before.inventory
	var bag_before := {} if inventory_before == null else {"slots": inventory_before.slots.duplicate(true), "equipment": inventory_before.equipment.duplicate(true), "equipment_data": inventory_before.equipment_data.duplicate(true)}
	var cursor_before := Input.mouse_mode
	var audio_before := AudioServer.is_bus_mute(0)
	var hz_before := Engine.physics_ticks_per_second
	var steps_before := Engine.max_physics_steps_per_frame
	var hashes := _dagger_hashes()
	AudioServer.set_bus_mute(0, true)
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(8, steps_before)
	sandbox.begin()
	var frames: Array[Dictionary] = []
	var outcomes: Array[Dictionary] = []
	for scenario: Dictionary in DAGGER_CASES:
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
		_add_dagger_floor(world)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-32, 155, 0)
		fill.light_energy = 0.8
		fill.light_color = Color(0.90, 0.94, 1.0)
		world.add_child(fill)
		player.position = Vector3(0, .9, 1.05 if scenario.rear else -1.05)
		player.inventory_model.add_item("iron_dagger", 1)
		_check(ARMS._equip_weapon(player.inventory_model, "iron_dagger"), "Equip actual dagger: " + scenario.id)
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
		# Flush a newly-created body's relocated physics transform before a
		# second capsule is spawned at the fixture origin.
		for settle in 2:
			await physics_frame
			await process_frame
		var actor = CREEP.new()
		actor.configure("암살 검수 크리프", 118, 8, 2.2, Color.WHITE)
		actor.position = Vector3(0, .9, 0)
		world.add_child(actor)
		actor.target = null
		actor.set_process_input(false)
		actor.set_process_unhandled_input(false)
		var driver := DaggerDriver.new()
		driver.player = player
		driver.actor = actor
		driver.rear = bool(scenario.rear)
		driver.max_ticks = int(scenario.frames) * 2
		driver.process_physics_priority = 100
		world.add_child(driver)
		driver.set_physics_process(false)
		actor.defeated.connect(driver._on_defeated)
		player.attack_landed.connect(driver._on_attack_landed)
		for warm in 10:
			await process_frame
		var chest_index: int = actor.skeleton.find_bone("Chest")
		driver.initial_chest = (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(chest_index)).origin
		var aim := driver.initial_chest - player.camera.global_position
		player.rotation.y = atan2(-aim.x, -aim.z)
		player._pitch = atan2(aim.y, Vector2(aim.x, aim.z).length())
		player.head.rotation.x = player._pitch
		driver.initial_pitch = player._pitch
		player._update_viewmodel(1.0)
		player.camera.make_current()
		player.viewmodel_renderer.sync_view()
		var label := _dagger_overlay(viewport, str(scenario.title))
		for warm in 4:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await RenderingServer.frame_post_draw
		actor.target = player
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
			label.text = "%s\n체력 HP %.0f / 118  ·  타격 HIT %d  ·  처치 KILL %d  |  %.2f s" % [scenario.title, sample.health, driver.landed, driver.defeats, float(frame) / 30.0]
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			var filename := "frames/%05d.jpg" % frames.size()
			_check(pixels != null and not pixels.is_empty(), "Actual GPU frame exists: " + filename)
			if pixels != null and not pixels.is_empty():
				_check(pixels.save_jpg(directory.path_join(filename), .95) == OK, "Saved frame: " + filename)
				var still := ""
				if frame == 0: still = "ready"
				elif int(sample.player_state) == DungeonPlayer.CombatState.WINDUP and not stills.has("windup"): still = "windup"
				elif driver.landed == 1 and not stills.has("contact"): still = "contact"
				elif frame == int(scenario.frames) - 1: still = "ragdoll" if scenario.rear else "survives"
				if not still.is_empty():
					var still_file: String = scenario.id + "_" + still + ".png"
					_check(pixels.save_png(directory.path_join(still_file)) == OK, "Saved still: " + still_file)
					stills[still] = {"file": still_file, "tick": driver.tick, "frame": frame}
			sample.merge({"frame": frames.size(), "scenario": scenario.id, "case_frame": frame, "file": filename})
			frames.append(sample)
			case_frames.append(sample)
		_check_dagger_case(driver, scenario, case_frames)
		outcomes.append({"id": scenario.id, "rear": scenario.rear, "initial_health": 118,
			"begin_result": driver.began, "attacks_landed": driver.landed, "defeats": driver.defeats,
			"damage_events": driver.damage_events, "hit_snapshot": driver.hit_snapshot,
			"camera_inspection_tilt": driver.changed_camera, "initial_pitch_radians": driver.initial_pitch,
			"stills": stills, "physics_samples": driver.records, "final_creep": actor.get_creep_snapshot()})
		viewport.queue_free()
		await process_frame
		print("DAGGER PREVIEW CASE: ", scenario.id, " | landed ", outcomes.back().attacks_landed)
	sandbox.finish()
	Engine.physics_ticks_per_second = hz_before
	Engine.max_physics_steps_per_frame = steps_before
	AudioServer.set_bus_mute(0, audio_before)
	var bag_preserved: bool = inventory_before == null or (inventory_before.slots == bag_before.slots and inventory_before.equipment == bag_before.equipment and inventory_before.equipment_data == bag_before.equipment_data)
	var session_preserved := session_before == ExpeditionSession.capture_snapshot() and bag_preserved
	var cursor_preserved := cursor_before == Input.mouse_mode
	var hashes_after := _dagger_hashes()
	_check(session_preserved and not sandbox.active, "Original expedition, inventory and sandbox restored.")
	_check(cursor_preserved, "Original cursor mode preserved.")
	_check(hashes == hashes_after, "Sources unchanged during rendering.")
	_check(frames.size() == 210, "Seven seconds at 30 fps produces 210 actual GPU frames.")
	var manifest := {"iteration": tag, "resolution": [960, 540], "fps": 30, "physics_hz": 60,
		"frame_count": frames.size(), "duration_seconds": 7.0, "display_driver": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_driver_name(), "audio_driver_policy": "Dummy enforced by audited run_embedded_preview.sh",
		"source_hashes_before": hashes, "source_hashes_after": hashes_after, "sources_preserved": hashes == hashes_after,
		"session_inventory_preserved": session_preserved, "cursor_preserved": cursor_preserved,
		"capture_scope": "Actual DungeonPlayer dagger, real short-range contact, live Creep AI and physical ragdoll. One press/release through production combat functions per case; no forced damage, pose, death or debris coordinates.",
		"camera_motion": "Rear: after death, pitch tilts down from 1.3 to 2.1 seconds to -43 degrees for corpse inspection. Front: camera tracks the animated chest from 1.05m in front, keeping the short-range control aimed. Front attacks at tick 6 before the live enemy lunges into the camera; rear attacks at tick 36. These are capture camera movements and inputs, not added gameplay assistance or animations.",
		"input_scope": "OS input disabled; gameplay press/release methods called directly. No desktop capture, focus changes, mouse capture or audio output. Labels are inspection subtitles, not production HUD.",
		"scenarios": outcomes, "frames": frames, "failures": failures}
	var output := FileAccess.open(directory.path_join("capture_manifest.json"), FileAccess.WRITE)
	if output != null: output.store_string(JSON.stringify(_json_safe(manifest), "\t") + "\n")
	else: _check(false, "Could not save dagger manifest.")
	print("DAGGER_ASSASSINATION_PREVIEW_COMPLETE %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)


func _check_dagger_case(driver: DaggerDriver, scenario: Dictionary, records: Array[Dictionary]) -> void:
	var prefix: String = scenario.id + ": "
	_check(bool(driver.began.get("accepted", false)), prefix + "actual attack accepted")
	_check(driver.landed == 1 and driver.damage_events.size() == 1, prefix + "one actual contact, no duplicate hit")
	_check(not driver.hit_snapshot.is_empty(), prefix + "contact changed actual health")
	for record: Dictionary in records:
		_check(record.dagger_visible and not record.sword_visible and not record.left_support_visible, prefix + "dagger-only weapon and one-handed grip")
		_check(record.enemy_ai_enabled and record.target_is_actual_player, prefix + "real AI retains actual player target")
		if int(record.player_state) in [DungeonPlayer.CombatState.ACTIVE, DungeonPlayer.CombatState.RECOVERY]:
			_check(record.world_contact, prefix + "attack mesh uses world depth")
		elif int(record.player_state) == DungeonPlayer.CombatState.READY:
			_check(not record.world_contact, prefix + "ready restores ordinary first-person rendering")
		if bool(scenario.rear) and int(record.tick) < 36:
			_check(int(record.enemy_state) == DungeonEnemy.AIState.IDLE and record.rear_eligible, prefix + "unalerted rear approach stays idle")
	if records.is_empty(): return
	var last: Dictionary = records.back()
	if scenario.rear:
		_check(driver.defeats == 1 and is_zero_approx(float(last.health)), prefix + "118 health killed once")
		_check(str(last.ragdoll_phase) in ["simulating", "settled"], prefix + "real ragdoll started")
		_check(float(last.initial_chest_distance_m) > .20, prefix + "corpse physically moved from standing pose")
	else:
		_check(driver.defeats == 0 and float(last.health) > 0 and float(last.health) < 118, prefix + "front hit is ordinary damage, actor survives")
		_check(str(last.ragdoll_phase) == "living", prefix + "front control remains alive")
	if not driver.hit_snapshot.is_empty():
		_check(not (driver.hit_snapshot.before.contact as Dictionary).is_empty(), prefix + "real anatomical contact exists before damage")
		_check(float(driver.hit_snapshot.before.blade_axis_forward_dot) > .95, prefix + "actual blade points along the thrust")
		print("DAGGER CONTACT: ", scenario.id, " | tip distance m ", driver.hit_snapshot.before.blade_tip_contact_distance_m, " | axial depth m ", driver.hit_snapshot.before.blade_axis_penetration_m, " | lateral m ", driver.hit_snapshot.before.blade_lateral_error_m)


func _dagger_hashes() -> Dictionary:
	var hashes := {}
	for source: String in DAGGER_SOURCES:
		var digest := FileAccess.get_sha256(source)
		_check(digest.length() == 64, "Source exists: " + source)
		hashes[source] = digest
	return hashes


func _add_dagger_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "DaggerContactFloor"
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	floor_body.position.y = -.1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, .2, 20)
	shape.shape = box
	floor_body.add_child(shape)
	world.add_child(floor_body)


func _dagger_overlay(viewport: SubViewport, title: String) -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 20
	viewport.add_child(layer)
	return _add_label(layer, title, Vector2(20, 16), 18)
