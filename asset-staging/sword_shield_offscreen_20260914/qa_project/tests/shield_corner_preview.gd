extends SceneTree
## Input-free, real production viewport; no OS window or cursor changes.
const STUDIO = preload("res://tests/sword_shield_preview.gd")
var failures: Array[String] = []
func _init(): call_deferred("run")
func run():
	if DisplayServer.get_name() != "embedded": quit(2); return
	var output := ProjectSettings.globalize_path("res://artifacts/visual_qa/shield_reference_framing")
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var saved := ExpeditionSession.capture_snapshot()
	var cursor := Input.mouse_mode
	var sandbox = root.get_node("TestRoomSandbox")
	if sandbox.active: quit(2); return
	sandbox.begin()
	var vp := STUDIO.create_studio_viewport()
	root.add_child(vp)
	var f := STUDIO.PREVIEW.populate_viewport(vp)
	await physics_frame
	await physics_frame
	var p: DungeonPlayer = f.player
	if not STUDIO.configure_pose(f, "idle"): failures.append("Could not equip real sword and shield")
	STUDIO.configure_studio(f)
	var captures := []
	for label in ["idle", "walk", "run", "raise_half", "guard", "impact", "lower_half", "returned"]:
		p.velocity = Vector3.ZERO
		p.blocking = label in ["raise_half", "guard", "impact"]
		if label == "walk": p.velocity = p.global_basis * Vector3(0, 0, -p.WALK_SPEED)
		if label == "run": p.velocity = p.global_basis * Vector3(0, 0, -p.SPRINT_SPEED)
		STUDIO.PREVIEW._sample_view(p, 0.12 if label == "raise_half" else (0.15 if label == "lower_half" else 0.8))
		if label == "impact":
			p.receive_attack(18, p.global_position - p.global_basis.z * 2.0)
			STUDIO.PREVIEW._sample_view(p, 0.055)
		p.viewmodel_renderer.sync_view()
		for i in 12: await process_frame
		RenderingServer.force_draw(false)
		var pixels := vp.get_texture().get_image()
		if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(label + ".png")) != OK: failures.append("Capture failed: " + label)
		var left := p.camera.to_local(p.shield_model.find_child("RearGrip", true, false).global_position)
		var right := p.camera.to_local(p.sword_visual_root.find_child("HandGrip", true, false).global_position)
		var mirror_error := right.distance_to(Vector3(-left.x, left.y, left.z))
		if label in ["idle", "walk", "run", "returned"] and mirror_error > 0.002: failures.append("Carry grips not aligned: " + label)
		var left_screen := p.camera.unproject_position(p.shield_model.find_child("RearGrip", true, false).global_position) / Vector2(vp.size)
		var tip := p.camera.to_local(p.sword_visual_root.find_child("BladeTip", true, false).global_position)
		var rim_screen := p.camera.unproject_position(p.shield_model.to_global(Vector3(0, 0.427, 0))) / Vector2(vp.size)
		if label in ["guard", "impact"]:
			if rim_screen.y < 0.60 or rim_screen.y > 0.92: failures.append("Shield rim not at the bottom: " + label)
			if right.y > -0.60 or tip.y > right.y: failures.append("Sword not lowered: " + label)
		captures.append({"rim_screen":str(rim_screen),"left_grip_screen":str(left_screen),"right_grip":str(right),"mirror_error_m":mirror_error,"pose":label,"shield_position":str(p.shield_pivot.position),"guard_progress":p._shield_raise_progress})
	vp.queue_free()
	await process_frame
	sandbox.finish()
	if saved != ExpeditionSession.capture_snapshot() or cursor != Input.mouse_mode: failures.append("Session/cursor changed")
	var report := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"player_sha256":FileAccess.get_sha256("res://scripts/player.gd"),"guard_sha256":FileAccess.get_sha256("res://scripts/sword_shield_choreography.gd"),"motion_sha256":FileAccess.get_sha256("res://scripts/first_person_motion.gd"),"captures":captures,"failures":failures}, "\t"))
	print("SHIELD CORNER PREVIEW " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
