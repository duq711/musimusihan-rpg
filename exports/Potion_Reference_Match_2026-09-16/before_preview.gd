extends SceneTree
## Reviewed embedded-only capture. No window, focus, input sampling or injection.
const FIXTURE := preload("res://tests/player_arm_preview.gd")
var output := "res://artifacts/visual_qa/potion_drink/drink_01"

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
	player.apply_body_damage("left_arm", 40.0)
	fixture.inventory.add_item("healing_draught", 3)
	return fixture

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		quit(2)
		return
	var iteration := OS.get_environment("POTION_QA_ITERATION")
	if not iteration.is_empty():
		if not iteration.is_valid_filename() or iteration.begins_with("."):
			quit(2)
			return
		output = "res://artifacts/visual_qa/potion_drink/".path_join(iteration)
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
	var initial_count: int = fixture.inventory.count_item("healing_draught")
	var accepted: Dictionary = player.begin_item_use("healing_draught", fixture.inventory)
	var path := ProjectSettings.globalize_path(output)
	if DirAccess.dir_exists_absolute(path):
		push_error("Refusing to overwrite previous captures")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(path)
	var hashes := {}
	for source in ["res://scripts/potion_drink_visuals.gd", "res://scripts/bandage_use_visuals.gd", "res://scripts/player.gd", "res://scripts/supplied_fp_arm.gd", "res://scripts/player_arm_visual.gd", "res://assets/3d/player/fp_arms/left.scn", "res://assets/3d/player/fp_arms/right.scn", "res://assets/3d/items/potions/red_potion.glb"]:
		hashes[source] = FileAccess.get_sha256(source)
	var frames: Array = []
	var sparse := OS.get_environment("POTION_QA_STILLS") == "1"
	var count := 20 if sparse else ceili((player.potion_hands.DRINK_DURATION + 0.7) * 30.0)
	var step := 0.4 if sparse else 1.0 / 30.0
	for i in count:
		player.viewmodel_renderer.sync_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var filename := "frame_%03d.png" % i
		if picture.save_png(path.path_join(filename)) != OK:
			push_error("Potion capture could not save frame")
			quit(1)
			return
		frames.append({"file": filename, "time": i * step, "active": player.is_bandage_motion_active(), "stage": player.potion_hands.stage, "fill": player.potion_hands.fill, "cap_turn": player.potion_hands.cap_turn, "cap_hand_turn": player.potion_hands.cap_hand_turn, "cap_grip": player.potion_hands.cap_grip_strength, "cap_lift": player.potion_hands.cap_lift, "liquid_level": player.potion_hands.liquid_level, "hands_visible": player.potion_hands.visible, "weapon_visible": player.weapon_pivot.visible, "fracture": ExpeditionSession.condition_affects_part("fracture", "left_arm"), "count": fixture.inventory.count_item("healing_draught")})
		player._update_viewmodel(step)
		player.advance_item_use(step)
	var completed: bool = not player.is_item_use_active() and bool(player.last_item_use_result.get("accepted", false)) and fixture.inventory.count_item("healing_draught") == initial_count - 1
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := snapshot == ExpeditionSession.capture_snapshot() and cursor == Input.mouse_mode
	for source in hashes:
		preserved = preserved and hashes[source] == FileAccess.get_sha256(source)
	var manifest := {"renderer": RenderingServer.get_current_rendering_driver_name(), "display": DisplayServer.get_name(), "source_hashes": hashes, "state_and_sources_preserved": preserved, "use_result": accepted, "timed_completion_verified": completed, "frames": frames}
	FileAccess.open(path.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t"))
	print("POTION MOTION PREVIEW %s: %d production frames" % ["PASS" if preserved and accepted.accepted and completed else "FAIL", count])
	quit(0 if preserved and accepted.accepted and completed else 1)
