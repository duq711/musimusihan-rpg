extends SceneTree
## Read-only inspection of current game grips. No OS input or visible window.
const STUDIO = preload("res://tests/sword_shield_preview.gd")
var output: String
var failures: Array[String] = []
func _init(): call_deferred("run")
func capture(vp: SubViewport, label: String):
	for i in 12: await process_frame
	RenderingServer.force_draw(false)
	var pixels = vp.get_texture().get_image()
	if pixels == null or pixels.is_empty() or pixels.save_png(output.path_join(label + ".png")) != OK:
		failures.append("Capture failed: " + label)
func run():
	if DisplayServer.get_name() != "embedded": quit(2);return
	output = ProjectSettings.globalize_path("res://artifacts/visual_qa/current_hand_grips_20260912")
	if DirAccess.dir_exists_absolute(output): quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	root.gui_disable_input = true;root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var saved = ExpeditionSession.capture_snapshot();var cursor = Input.mouse_mode
	var source_hash = FileAccess.get_sha256("res://scripts/player.gd")
	var sandbox = root.get_node("TestRoomSandbox");sandbox.begin()
	var vp = STUDIO.create_studio_viewport();root.add_child(vp)
	var f = STUDIO.PREVIEW.populate_viewport(vp);var p = f.player
	await physics_frame;await physics_frame
	if not STUDIO.configure_pose(f, "idle"): failures.append("Idle setup failed")
	STUDIO.configure_studio(f);p.viewmodel_renderer.sync_view()
	await capture(vp, "first_person_idle")
	if not STUDIO.configure_pose(f, "guard"): failures.append("Guard setup failed")
	p.viewmodel_renderer.sync_view();await capture(vp, "first_person_guard")
	var camera = Camera3D.new();f.stage.add_child(camera)
	camera.cull_mask = (1 << 20) - 1
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL;camera.size = 0.32;camera.near = 0.01
	f.stage.get_node("ArmPreviewFloor").visible = false
	p.player_body.visible = false;p.torch_pivot.visible = false
	vp.size = Vector2i(1000, 850)
	var pose_before = p.get_first_person_motion_snapshot()
	for grip in ["sword", "shield"]:
		var target: Vector3 = pose_before.hand_contacts[grip].actual
		var direction: Vector3 = target.direction_to(p.camera.global_position)
		camera.global_position = target + direction * 0.65
		camera.look_at(target, p.camera.global_basis.y);camera.make_current()
		p.viewmodel_renderer.sync_view();await capture(vp, grip + "_hand_close")
	if p.get_first_person_motion_snapshot() != pose_before: failures.append("Inspection changed grip pose")
	vp.queue_free();await process_frame;sandbox.finish()
	if saved != ExpeditionSession.capture_snapshot() or cursor != Input.mouse_mode: failures.append("Session changed")
	if source_hash != FileAccess.get_sha256("res://scripts/player.gd"): failures.append("Player source changed")
	var report = FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer": RenderingServer.get_current_rendering_driver_name(), "source_sha256": source_hash, "failures": failures}, "\t"))
	print("HAND HOLD PREVIEW " + ("PASS" if failures.is_empty() else "FAIL"))
	quit(0 if failures.is_empty() else 1)
