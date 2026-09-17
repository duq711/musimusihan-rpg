extends "res://tests/creep_ragdoll_preview.gd"
## Production geometry and hits in the existing isolated renderer fixture.
func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Wound preview requires the audited hidden renderer."); quit(2); return
	var tag := OS.get_environment("CREEP_WOUND_QA_ITERATION")
	if not tag.is_valid_filename() or tag.begins_with("."):
		push_error("Choose a new CREEP_WOUND_QA_ITERATION."); quit(2); return
	var directory := ProjectSettings.globalize_path("res://artifacts/visual_qa/creep_wounds/" + tag)
	if DirAccess.dir_exists_absolute(directory):
		push_error("Cannot overwrite existing renders."); quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor := Input.mouse_mode
	var session := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "isolated session")
	sandbox.begin()
	var hashes := _source_hashes()
	for path in [CREEP.DISMEMBERMENT.MODEL_PATH, "res://scripts/creep_dismemberment.gd", "res://scripts/creep_wound_effect.gd", "res://shaders/creep_wound.gdshader"]:
		hashes[path] = FileAccess.get_sha256(path)
	var captures: Array = []
	for region in ["head", "right_arm", "left_leg"]:
		var viewport := _create_viewport()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var fixture := _create_fixture(viewport, {"wall_position": Vector3(0, 2, 8), "wall_size": Vector3(.1, .1, .1), "title": "절단면 개선 / RECESSED WOUNDS · " + region})
		for canvas in viewport.get_children():
			if canvas is CanvasLayer:
				for label in canvas.get_children():
					if label is Label and label.text.begins_with("CREEP  |"):
						label.text = "CREEP | 실제 게임 모델 · 절단면 / IN-GAME WOUND SURFACES"
		var actor = fixture.actor
		actor.set_physics_process(false)
		actor.health = 120; actor.max_health = 120
		for warmup in 5: await process_frame
		var cap: MeshInstance3D = actor.dismemberment.body_caps[region][0]
		var posed: ArrayMesh = actor.dismemberment._bake_world_mesh(cap, Vector3.ZERO)
		var centre := posed.get_aabb().get_center()
		var side := Vector3(-.8, .45, -1.65) if region == "head" else Vector3(1.3, .5, -1.25)
		if region == "left_leg": side = Vector3(-1.2, .35, .8)
		fixture.camera.position = centre + side
		fixture.camera.look_at(centre)
		fixture.status.text = "원본 유지 · 같은 카메라 / INTACT · SAME CAMERA"
		await _capture_wound(viewport, directory, region + "_intact", captures)
		for hit in 2:
			var point: Vector3 = actor.dismemberment.hit_point_for_region(region)
			actor.receive_located_hit(18, Vector3(0, .9, -3), .5, region == "head", point)
		# Allow separation and the production hit flash to clear before judging
		# the cut. Do not alter actor transforms or fake the detached pose.
		for separation_frame in 6: await process_frame
		posed = actor.dismemberment._bake_world_mesh(cap, Vector3.ZERO)
		centre = posed.get_aabb().get_center()
		fixture.camera.position = centre + side
		fixture.camera.look_at(centre)
		fixture.status.text = "실제 2회 타격 후 0.4초 / 0.4s AFTER TWO REAL HITS"
		await _capture_wound(viewport, directory, region + "_cut", captures)
		# Inspect both tissue surfaces close enough to see shading and depth.
		var part: RigidBody3D = actor.dismemberment.detached[0]
		var part_cap := part.find_child("CreepCap_part_" + region + "*", false, false) as MeshInstance3D
		if part_cap != null:
			var part_centre := part_cap.global_transform * part_cap.mesh.get_aabb().get_center()
			var normals: PackedVector3Array = part_cap.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
			var mean_normal := Vector3.ZERO
			for normal in normals: mean_normal += normal
			mean_normal = (part_cap.global_basis * mean_normal).normalized()
			fixture.camera.position = part_centre + mean_normal * 1.1 + Vector3.UP * .40
			fixture.camera.position.y = maxf(.30, fixture.camera.position.y)
			fixture.camera.look_at(part_centre)
			# Diagnostic close-up: suppress only the occluding main-body skin.
			# The actual baked part, pose, material and world physics stay intact.
			actor.visual_root.hide()
			fixture.status.text = "분리 부위 단독 검수 · 본체 가림 해제 / DETACHED SURFACE · BODY HIDDEN"
			await _capture_wound(viewport, directory, region + "_part", captures)
			actor.visual_root.show()
		for frame in 45: await process_frame
		fixture.camera.position = Vector3(-2.7, 2.0, -3.8)
		fixture.camera.look_at(Vector3(0, .75, 0))
		fixture.status.text = "분리 부위·바닥 접촉 혈흔 / DETACHED PART · CONTACT STAINS"
		await _capture_wound(viewport, directory, region + "_settled", captures)
		_check(actor.dismemberment.severed == [region], "only intended region severed")
		viewport.queue_free()
		await process_frame
	sandbox.finish()
	_check(session == ExpeditionSession.capture_snapshot(), "session restored")
	_check(cursor == Input.mouse_mode, "cursor preserved")
	for path in hashes: _check(hashes[path] == FileAccess.get_sha256(path), "source preserved")
	var file := FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(), "captures": captures, "source_hashes": hashes, "failures": failures, "scope": "Isolated actual GPU fixture; no desktop/input/audio"}, "\t"))
	print("CREEP WOUND PREVIEW %s: %s" % ["PASS" if failures.is_empty() else "FAIL", directory])
	quit(0 if failures.is_empty() else 1)

func _capture_wound(viewport: SubViewport, directory: String, filename: String, captures: Array) -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var path := directory.path_join(filename + ".png")
	_check(viewport.get_texture().get_image().save_png(path) == OK, "saved " + filename)
	captures.append(filename + ".png")
