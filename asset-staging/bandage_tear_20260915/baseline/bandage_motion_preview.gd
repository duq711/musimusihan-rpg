extends SceneTree
## Reviewed embedded-only capture. No window, focus, input sampling or injection.
const FIXTURE := preload("res://tests/player_arm_preview.gd")
var output := "res://artifacts/visual_qa/bandage_forearm/transition_05"

func _init() -> void:
	call_deferred("_run")

static func create_fixture(viewport: SubViewport) -> Dictionary:
	var fixture := FIXTURE.populate_viewport(viewport)
	var player: DungeonPlayer = fixture.player
	player.position = Vector3(0, 1.5, 0)
	player.head.rotation = Vector3.ZERO
	player.camera.transform = Transform3D.IDENTITY
	player.set_torch_enabled(false)
	player._update_viewmodel(1.0)
	player.select_treatment_part("left_arm")
	player.apply_body_damage("left_arm", 24.0)
	fixture.inventory.add_item("linen_bandage", 3)
	return fixture

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var cursor := Input.mouse_mode
	var snapshot := ExpeditionSession.capture_snapshot()
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := FIXTURE.create_viewport()
	viewport.size = Vector2i(960, 540)
	root.add_child(viewport)
	var fixture := create_fixture(viewport)
	var player: DungeonPlayer = fixture.player
	var accepted: Dictionary = player.use_consumable("linen_bandage", fixture.inventory)
	var path := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path)
	var hashes := {}
	for source in ["res://scripts/bandage_use_visuals.gd", "res://scripts/player.gd"]:
		hashes[source] = FileAccess.get_sha256(source)
	var frames: Array = []
	var sparse := OS.get_environment("BANDAGE_QA_STILLS") == "1"
	var count := 15 if sparse else 176
	var step := 0.4 if sparse else 1.0 / 30.0
	for i in count:
		player.viewmodel_renderer.sync_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var filename := "frame_%03d.png" % i
		if picture.save_png(path.path_join(filename)) != OK:
			push_error("Bandage capture could not save frame")
			quit(1)
			return
		frames.append({"file": filename, "time": i * step, "active": player.is_bandage_motion_active(), "winding": player.bandage_hands.winding, "hands_visible": player.bandage_hands.visible, "weapon_visible": player.weapon_pivot.visible})
		player._update_viewmodel(step)
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode
	for source in hashes:
		preserved = preserved and hashes[source] == FileAccess.get_sha256(source)
	var manifest := {"renderer": RenderingServer.get_current_rendering_driver_name(), "display": DisplayServer.get_name(), "source_hashes": hashes, "state_and_sources_preserved": preserved, "use_result": accepted, "frames": frames}
	FileAccess.open(path.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("BANDAGE MOTION PREVIEW %s: %d production frames" % ["PASS" if preserved and accepted.accepted else "FAIL", count])
	quit(0 if preserved and accepted.accepted else 1)
