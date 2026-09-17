extends "res://tests/creep_ragdoll_preview.gd"
## Continuous production crawl, real cuts, chase and bite in an isolated viewport.
const DUMMY := preload("res://tests/creep_dismemberment_preview.gd")
const CRAWL_CASES := [
	{"regions": ["left_leg"], "id": "left_leg", "title": "왼다리 절단 · 기어서 추적 / LEFT LEG · CRAWL", "camera": Vector3(-2.7, 1.8, -3.5)},
	{"regions": ["right_leg"], "id": "right_leg", "title": "오른다리 절단 · 측면 / RIGHT LEG · SIDE VIEW", "camera": Vector3(3.8, 1.3, -.6)},
	{"regions": ["left_leg", "right_leg"], "id": "both_legs", "title": "양다리 절단 · 기어서 물기 / BOTH LEGS · CRAWL & BITE", "camera": Vector3(-2.7, 1.8, -3.5)},
]

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Only audited embedded rendering is permitted."); quit(2); return
	var tag := OS.get_environment("CREEP_CRAWL_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):
		push_error("Choose a new CREEP_CRAWL_QA_ITERATION directory."); quit(2); return
	var directory := "/private/tmp/creep-crawl-" + tag
	if DirAccess.dir_exists_absolute(directory):
		push_error("Cannot overwrite existing renders."); quit(2); return
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
	var record_video := OS.get_environment("CREEP_CRAWL_VIDEO") == "1"
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor := Input.mouse_mode
	var session := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "isolated preview session")
	sandbox.begin()
	var hashes := _source_hashes()
	for path in [CREEP.DISMEMBERMENT.MODEL_PATH, "res://scripts/creep_crawl.gd", "res://scripts/creep_dismemberment.gd", "res://tests/creep_crawl_preview.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	var frame_number := 0
	var frames: Array = []
	var outcomes: Array = []
	for scenario: Dictionary in CRAWL_CASES:
		var viewport := _create_viewport()
		viewport.size = Vector2i(960, 540)
		viewport.size_2d_override = Vector2i(1280, 720)
		viewport.size_2d_override_stretch = true
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var fixture := _create_fixture(viewport, {"wall_position": Vector3(0, -10, 8), "wall_size": Vector3(.1, .1, .1), "title": scenario.title})
		for child in fixture.world.get_node("Floor").get_children():
			if child is CollisionShape3D: child.shape.size = Vector3(24, .2, 24)
			if child is MeshInstance3D: child.mesh.size = Vector3(24, .2, 24)
		for child in viewport.get_children():
			if child is CanvasLayer:
				for label in child.get_children():
					if label is Label and label.text.begins_with("CREEP  |"):
						label.text = "CREEP | 다리 손실 후 포복 / CRAWLING AFTER LEG LOSS"
		var actor = fixture.actor
		actor.health = 118; actor.max_health = 118
		var target := DUMMY.TargetDummy.new()
		fixture.world.add_child(target)
		target.position = Vector3(0, .9, -2.0 if scenario.id == "both_legs" else -3.8)
		actor.target = target
		actor.set_physics_process(false)
		for warm in 8: await process_frame
		var previous_tick := -1
		for frame in 180:
			await process_frame
			var tick := int(Engine.get_physics_frames())
			if previous_tick >= 0: _check(tick - previous_tick == 4, "continuous 60 Hz physics at 15 fps")
			previous_tick = tick
			if frame in [9, 21, 33, 45]:
				var cut_index := 0 if frame < 30 else 1
				if cut_index < scenario.regions.size():
					var region: String = scenario.regions[cut_index]
					actor.receive_located_hit(18, actor.global_position + Vector3(0, 0, -3), .5, false, actor.dismemberment.hit_point_for_region(region))
			if frame == 22: actor.set_physics_process(true)
			actor._resolve_active_attack()
			fixture.camera.position = actor.position + scenario.camera
			fixture.camera.look_at(actor.position + Vector3(0, -.35, .0))
			fixture.status.text = "%0.2f초 | 절단 %s | HP %d | %s | 공격 접촉 %d" % [float(frame)/15, str(actor.dismemberment.severed), actor.health, actor.animation_clip, target.contacts]
			if record_video or frame in [8, 21, 36, 60, 90, 119, 150, 179]:
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				var rendered := viewport.get_texture().get_image()
				if record_video: _check(rendered.save_jpg(directory.path_join("frames/%05d.jpg" % frame_number), .94) == OK, "GPU frame saved")
				if frame in [8, 21, 36, 60, 90, 119, 150, 179]:
					_check(rendered.save_png(directory.path_join("%s_%03d.png" % [scenario.id, frame])) == OK, "GPU still saved")
			frames.append({"frame": frame_number, "case": scenario.id, "case_frame": frame, "clip": actor.animation_clip, "crawl": actor.crawl.snapshot(), "position": actor.position, "severed": actor.dismemberment.severed.duplicate(), "contacts": target.contacts})
			frame_number += 1
		_check(actor.dismemberment.severed == scenario.regions, "only selected legs severed")
		_check(actor.is_crawling() and actor.crawl.blend > .99, "living crawl fully active")
		_check(target.contacts > 0, "surviving crawler reaches and bites target")
		outcomes.append({"case": scenario.id, "contacts": target.contacts, "snapshot": actor.get_creep_snapshot()})
		viewport.queue_free()
		await process_frame
		print("CREEP CRAWL CASE: ", scenario.id)
	sandbox.finish()
	_check(session == ExpeditionSession.capture_snapshot(), "original expedition restored")
	_check(cursor == Input.mouse_mode, "cursor unchanged")
	for path: String in hashes: _check(hashes[path] == FileAccess.get_sha256(path), "source unchanged: " + path)
	var output := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(_json_safe({"record_video": record_video, "frames": frames, "outcomes": outcomes, "hashes": hashes, "failures": failures, "fps": 15, "physics_hz": 60, "renderer": "embedded Vulkan Forward+"}), "\t"))
	print("CREEP CRAWL PREVIEW %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)
