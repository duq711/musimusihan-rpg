extends "res://tests/creep_ragdoll_preview.gd"
## Real charge/release, source sword skin contact and ragdoll death at 60 Hz.
## Observer views are separate runtime repeats, never a composited first-person hand.
const ARMS := preload("res://tests/player_arm_preview.gd")
const OUTPUT := "res://artifacts/visual_qa/creep_execution"
const EXECUTION_CASES := [
	{"id": "left_leg_first_person", "legs": ["left_leg"], "observer": false, "title": "한 다리 절단 · 1인칭 내려찌르기 / FIRST PERSON"},
	{"id": "left_leg_side_repeat", "legs": ["left_leg"], "observer": true, "title": "같은 기능 재실행 · 측면 접촉 확인 / SIDE REPEAT"},
	{"id": "both_legs_first_person", "legs": ["left_leg", "right_leg"], "observer": false, "title": "양다리 절단 · 1인칭 내려찌르기 / BOTH LEGS"},
]
const EXECUTION_SOURCES := [
	"res://scripts/player.gd", "res://scripts/enemy.gd", "res://scripts/creep_enemy.gd",
	"res://scripts/creep_execution_motion.gd", "res://scripts/first_person_renderer.gd",
	"res://scripts/creep_crawl.gd", "res://scripts/creep_dismemberment.gd",
	"res://scripts/creep_ragdoll.gd", "res://scripts/creep_ragdoll_pose.gd",
	"res://tests/creep_execution_preview.gd", "res://tests/player_arm_preview.gd",
	CREEP.MODEL_PATH, CREEP.DISMEMBERMENT.MODEL_PATH,
]

class ActionDriver extends Node:
	var player: DungeonPlayer
	var actor
	var tick := 0
	var began := false
	var reserved := false
	var defeats := 0
	var contact: Dictionary = {}

	func _physics_process(delta: float) -> void:
		tick += 1
		if tick == 45:
			began = bool(player.begin_sword_attack().get("accepted", false))
		if tick == 71:
			player.attack_release_requested = true
		var had_hit: bool = player._execution_hit_committed
		player.advance_combat_state(delta)
		player.advance_movement(delta, Vector2.ZERO, false)
		if actor.ai_state == DungeonEnemy.AIState.EXECUTION:
			actor._process_execution_physics(delta)
		player._update_viewmodel(delta)
		player.viewmodel_renderer.sync_view()
		reserved = reserved or player.is_execution_active()
		if player._execution_hit_committed and not had_hit:
			contact = {"tick": tick, "snapshot": player.get_execution_snapshot(), "creature": actor.get_creep_snapshot(), "hands": player.get_first_person_motion_snapshot()}
		if tick >= 360:
			set_physics_process(false)

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Creep execution requires the audited embedded runner at --fixed-fps 30."); quit(2); return
	var tag := OS.get_environment("CREEP_EXECUTION_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with(".") or not CREEP.is_available():
		push_error("Set a new CREEP_EXECUTION_QA_ITERATION and install the Creep source asset."); quit(2); return
	var directory := ProjectSettings.globalize_path(OUTPUT.path_join(tag))
	if DirAccess.dir_exists_absolute(directory):
		push_error("Execution preview will not overwrite previous captures."); quit(2); return
	if DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) != OK:
		push_error("Could not create execution capture output."); quit(2); return
	var stills_only := OS.get_environment("CREEP_EXECUTION_QA_STILLS") == "1"
	root.gui_disable_input = true
	root.physics_object_picking = false
	var audio_before := AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	var cursor_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Execution preview requires a separate test-room sandbox."); quit(2); return
	var hashes := {}
	for path: String in EXECUTION_SOURCES:
		hashes[path] = FileAccess.get_sha256(path)
		_check(str(hashes[path]).length() == 64, "source hash available: " + path)
	var previous_hz := Engine.physics_ticks_per_second
	var previous_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(previous_steps, 8)
	sandbox.begin()
	var frame_number := 0
	var records: Array = []
	var outcomes: Array = []
	for scenario: Dictionary in EXECUTION_CASES:
		var viewport := ARMS.create_viewport()
		viewport.size = Vector2i(960, 540)
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.use_taa = false
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var fixture := ARMS.populate_viewport(viewport)
		var player: DungeonPlayer = fixture.player
		var world: Node3D = fixture.stage
		fixture.chest.position = Vector3(20, 0, 20)
		_add_floor(world)
		player.position = Vector3(0, .9, 5)
		player.inventory_model.equipment.weapon = "rusted_sword"
		player.inventory_model.equipment.offhand = "round_shield"
		player.inventory_model.changed.emit()
		player.set_torch_enabled(false)
		player._torch_draw_elapsed = 0.0
		player._sword_draw_elapsed = player.SWORD_DRAW_DURATION
		player._motion_equip_elapsed = player.MOTION.EQUIP_DURATION
		_check(bool(player.request_primary_weapon().get("accepted", false)), scenario.id + ": actual primary-weapon action packs shield")
		player._shield_stow_elapsed = player.SHIELD_STOW_DURATION + player.SWORD_SUPPORT_DURATION
		player._update_viewmodel(1.0)
		var actor = CREEP.new()
		actor.configure("포복 크리프 처형", 118, 8, 0, Color.WHITE)
		actor.position = Vector3(0, .9, 0)
		world.add_child(actor)
		actor.target = null
		actor.set_physics_process(false)
		for warm in 6: await process_frame
		for region: String in scenario.legs:
			for strike in 2:
				actor.receive_located_hit(18, actor.global_position + Vector3(0, 0, -3), .5, false, actor.dismemberment.hit_point_for_region(region))
		actor.set_physics_process(true)
		var setup_phases := {}
		for wait_frame in 900:
			await process_frame
			setup_phases[actor.knockdown_phase] = true
			if not actor.is_knocked_down(): break
		_check(not actor.is_knocked_down() and actor.ragdoll.phase == "living", scenario.id + ": physical fall and recovery completed")
		_check(actor.dismemberment.severed == scenario.legs, scenario.id + ": selected legs removed through actual localized hits")
		actor.set_physics_process(false)
		actor.velocity = Vector3.ZERO
		var chest: Vector3 = actor.get_aim_point()
		# Only move the player. Keep the creature where real physics placed it.
		player.position = Vector3(chest.x, .9, chest.z + 1.5)
		var toward: Vector3 = chest - player.camera.global_position
		player.rotation.y = atan2(-toward.x, -toward.z)
		player._pitch = atan2(toward.y, Vector2(toward.x, toward.z).length())
		player.head.rotation.x = player._pitch
		player.health = player.MAX_HEALTH
		player.stamina = player.MAX_STAMINA
		player.velocity = Vector3.ZERO
		player._update_viewmodel(.1)
		player.camera.make_current()
		var observer: Camera3D
		if scenario.observer:
			observer = Camera3D.new()
			observer.cull_mask = 0xFFFFF & ~player.PLAYER_APPEARANCE.BODY_LAYER
			observer.fov = 62
			world.add_child(observer)
			observer.position = chest + Vector3(2.0, 1.05, 1.5)
			observer.look_at(chest + Vector3(0, .35, .35))
			observer.make_current()
		player.viewmodel_renderer.sync_view()
		var label := _overlay_label(viewport, str(scenario.title))
		var driver := ActionDriver.new()
		driver.player = player
		driver.actor = actor
		driver.set_physics_process(false)
		world.add_child(driver)
		driver.set_physics_process(false)
		actor.defeated.connect(func(_enemy: DungeonEnemy) -> void: driver.defeats += 1)
		for warm in 4:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await process_frame
			await RenderingServer.frame_post_draw
		_check(player.get_execution_target() == actor, scenario.id + ": real crawler is targetable with packed shield")
		driver.set_physics_process(true)
		var previous_tick := -1
		for frame in 180:
			await process_frame
			if previous_tick >= 0:
				_check(driver.tick - previous_tick == 2, scenario.id + ": two gameplay physics ticks per 30 fps frame")
			previous_tick = driver.tick
			label.text = str(scenario.title) + "\n%0.2f초 | %s | HP %d" % [float(driver.tick) / 60, player._execution_phase() if player.is_execution_active() else ("래그돌 사망 / RAGDOLL" if actor.health <= 0 else "LMB 길게 → 놓기 / CHARGE → RELEASE"), actor.health]
			var is_still := frame in [0, 34, 43, 51, 58, 59, 60, 62, 70, 82, 105, 150, 179]
			if not stills_only or is_still:
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				var rendered := viewport.get_texture().get_image()
				if not stills_only: _check(rendered.save_jpg(directory.path_join("frames/%05d.jpg" % frame_number), .94) == OK, "actual GPU frame saved")
				if is_still: _check(rendered.save_png(directory.path_join("%s_%03d.png" % [scenario.id, frame])) == OK, "actual GPU still saved")
			records.append({"frame": frame_number, "case": scenario.id, "case_frame": frame, "physics_tick": driver.tick, "execution": player.get_execution_snapshot(), "health": actor.health, "ragdoll_phase": actor.ragdoll.phase, "player_position": player.position, "chest": actor.get_aim_point(), "camera": viewport.get_camera_3d().global_transform})
			frame_number += 1
		_check(driver.began and driver.reserved, scenario.id + ": actual attack charge/release enters execution")
		_check(driver.defeats == 1 and actor.health == 0, scenario.id + ": contact kills exactly once")
		_check(not driver.contact.is_empty(), scenario.id + ": contact clock and actual blade snapshot captured")
		if not driver.contact.is_empty():
			var joint: Dictionary = driver.contact.hands.joint_landmarks.get("sword", {})
			_check(float(joint.get("shoulder_adjustment_m", INF)) < .025, scenario.id + ": physical approach keeps shoulder attached with original arm lengths")
			_check(bool(actor.get_meta("execution_contact_on_skin", false)), scenario.id + ": rendered torso triangles own the stab point")
		_check(not player.is_execution_active(), scenario.id + ": weapon recovers after execution")
		_check(actor.ragdoll.phase in ["simulating", "settled"], scenario.id + ": actual corpse physics active")
		outcomes.append({"case": scenario.id, "observer_repeat": scenario.observer, "fall_setup_phases": setup_phases, "contact": driver.contact, "defeats": driver.defeats, "final_ragdoll": actor.ragdoll.snapshot(), "hands": player.get_first_person_motion_snapshot()})
		player.cancel_sword_attack()
		viewport.queue_free()
		await process_frame
		print("CREEP EXECUTION CASE: ", scenario.id)
	sandbox.finish()
	Engine.physics_ticks_per_second = previous_hz
	Engine.max_physics_steps_per_frame = previous_steps
	AudioServer.set_bus_mute(0, audio_before)
	_check(session_before == ExpeditionSession.capture_snapshot(), "original expedition restored")
	_check(cursor_before == Input.mouse_mode and not sandbox.active, "cursor and sandbox preserved")
	for path: String in hashes: _check(hashes[path] == FileAccess.get_sha256(path), "source unchanged: " + path)
	var output := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(_json_safe({"fps": 30, "physics_hz": 60, "resolution": [960, 540], "stills_only": stills_only, "duration_seconds": 18.0, "capture_scope": "Actual production charge/release, posed sword contact, death ragdoll in isolated GPU scene; side angle is a separate runtime repeat.", "input_scope": "Production gameplay APIs at 60 Hz; no OS keyboard/mouse/focus, no desktop capture or audible playback.", "source_sha256": hashes, "outcomes": outcomes, "frames": records, "failures": failures}), "\t"))
	else: _check(false, "manifest saved")
	print("CREEP EXECUTION PREVIEW %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)

func _add_floor(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DungeonPlayer.WORLD_LAYER
	floor_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, .2, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.1
	world.add_child(floor_body)

func _overlay_label(viewport: SubViewport, title: String) -> Label:
	var overlay := CanvasLayer.new()
	overlay.layer = 10
	viewport.add_child(overlay)
	return _add_label(overlay, title, Vector2(24, 20), 20)
