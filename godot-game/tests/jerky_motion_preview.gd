extends SceneTree
## Actual timed food use, captured only by the reviewed hidden Vulkan renderer.
## No desktop window, external input, cursor capture, audio or save-file writes.

const FIXTURE := preload("res://tests/player_arm_preview.gd")
const IMAGE_SIZE := Vector2i(960, 540)
const FPS := 30
const OUTPUT_ROOT := "res://artifacts/visual_qa/jerky_eat"
const KEY_TIMES := [0.0, 0.8, 1.5, 2.8, 3.8, 4.8, 5.8, 6.7, 7.5, 8.5]
const SOURCE_FILES := [
	"res://tests/jerky_motion_preview.gd",
	"res://scripts/jerky_eat_visuals.gd",
	"res://scripts/bandage_use_visuals.gd",
	"res://scripts/player.gd",
	"res://scripts/inventory_model.gd",
	"res://scripts/first_person_renderer.gd",
	"res://scripts/supplied_fp_arm.gd",
	"res://scripts/player_arm_visual.gd",
	"res://assets/3d/player/fp_arms/left.scn",
	"res://assets/3d/player/fp_arms/right.scn",
	"res://assets/3d/items/beef_jerky/beef_jerky_variants.glb",
]

var failures: Array[String] = []


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
	ExpeditionSession.hunger = 35.0
	fixture.inventory.add_item("beef_jerky", 3)
	return fixture


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Jerky capture requires the reviewed embedded renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("JERKY_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("JERKY_QA_ITERATION must name a new capture folder.")
		quit(2)
		return
	var path := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(path):
		push_error("Refusing to overwrite previous jerky captures.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		push_error("Could not create jerky capture folder.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var original_cursor := Input.mouse_mode
	var original_session := ExpeditionSession.capture_snapshot()
	var original_bag_contents := _inventory_contents(original_session.inventory)
	var hashes := _source_hashes()
	for source: String in hashes:
		if str(hashes[source]).length() != 64:
			failures.append("Missing source hash: " + source)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := FIXTURE.create_viewport()
	viewport.size = IMAGE_SIZE
	root.add_child(viewport)
	var fixture := create_fixture(viewport)
	var player: DungeonPlayer = fixture.player
	var initial_count: int = fixture.inventory.count_item("beef_jerky")
	var initial_hunger := ExpeditionSession.hunger
	var accepted := player.begin_item_use("beef_jerky", fixture.inventory)
	if not bool(accepted.get("accepted", false)):
		failures.append("Actual player refused timed beef_jerky use.")
	var sparse := OS.get_environment("JERKY_QA_STILLS") == "1"
	var diagnostics := OS.get_environment("JERKY_QA_DIAGNOSTICS") == "1"
	var side_view: SubViewport
	if diagnostics:
		side_view = _create_side_diagnostic(player)
	var step := 0.25 if sparse else 1.0 / float(FPS)
	var duration: float = player.jerky_hands.EAT_DURATION
	var count := ceili((duration + 0.7) / step) + 1
	var frames: Array[Dictionary] = []
	var keyframes: Array[Dictionary] = []
	var properties := {}
	for property: Dictionary in player.jerky_hands.get_property_list():
		properties[str(property.name)] = true
	var next_key := 0
	for i in count:
		var time := float(i) * step
		var is_key: bool = next_key < KEY_TIMES.size() and time + step * 0.5 >= float(KEY_TIMES[next_key])
		if is_key and is_instance_valid(side_view):
			side_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		player.viewmodel_renderer.sync_view()
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		var filename := "frame_%03d.png" % i
		if picture.save_png(path.path_join(filename)) != OK:
			failures.append("Could not save frame: " + filename)
			break
		var frame := {
			"file": filename,
			"time": time,
			"item_use_active": player.is_item_use_active(),
			"motion_active": bool(player.jerky_hands.active),
			"hands_visible": player.jerky_hands.visible,
			"weapon_visible": player.weapon_pivot.visible,
			"count": fixture.inventory.count_item("beef_jerky"),
			"hunger": ExpeditionSession.hunger,
		}
		for property_name: String in ["stage", "bite_count", "remaining_fraction", "mouth_contact", "food_remaining", "eaten_fraction"]:
			if properties.has(property_name):
				frame[property_name] = player.jerky_hands.get(property_name)
		if properties.has("bite_tip"):
			var tip: Vector3 = player.jerky_hands.bite_tip
			frame["bite_tip_camera_space"] = [tip.x, tip.y, tip.z]
		frames.append(frame)
		if is_key:
			var key := {"file": filename, "time": time}
			if is_instance_valid(side_view):
				var diagnostic_file := "diagnostic_side_%02d.png" % next_key
				if side_view.get_texture().get_image().save_png(path.path_join(diagnostic_file)) != OK:
					failures.append("Could not save side diagnostic.")
				key["diagnostic_file"] = diagnostic_file
			keyframes.append(key)
			next_key += 1
		# Production progression owns both poses and the delayed inventory commit.
		player._update_viewmodel(step)
		player.advance_item_use(step)
	var completed: bool = not player.is_item_use_active() and not player.jerky_hands.active and bool(player.last_item_use_result.get("accepted", false)) and fixture.inventory.count_item("beef_jerky") == initial_count - 1
	var expected_hunger := minf(ExpeditionSession.MAX_NEED, initial_hunger + float(ExpeditionInventory.get_item_definition("beef_jerky").amount))
	completed = completed and is_equal_approx(ExpeditionSession.hunger, expected_hunger)
	if not completed:
		failures.append("Timed food consumption or hunger restoration did not complete.")
	if not player.weapon_pivot.visible:
		failures.append("Weapon did not return after the eating motion.")
	if is_instance_valid(side_view):
		side_view.queue_free()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := original_session == ExpeditionSession.capture_snapshot() and original_cursor == Input.mouse_mode
	preserved = preserved and original_bag_contents == _inventory_contents(original_session.inventory)
	if not preserved:
		failures.append("Preview changed the original expedition or cursor mode.")
	var sources_preserved := hashes == _source_hashes()
	if not sources_preserved:
		failures.append("Production sources changed during capture.")
	var manifest := {
		"renderer": RenderingServer.get_current_rendering_driver_name(),
		"display": DisplayServer.get_name(),
		"capture_kind": "Actual DungeonPlayer timed beef_jerky use in isolated TestRoomSandbox",
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y],
		"fps": 1.0 / step,
		"sparse_stills": sparse,
		"desktop_capture": false,
		"side_images_are_diagnostic_only": diagnostics,
		"source_hashes": hashes,
		"state_and_sources_preserved": preserved and sources_preserved,
		"use_result": accepted,
		"timed_completion_verified": completed,
		"keyframes": keyframes,
		"frames": frames,
		"failures": failures,
	}
	var file := FileAccess.open(path.path_join("manifest.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else:
		failures.append("Could not save jerky capture manifest.")
	for failure: String in failures:
		push_error(failure)
	print("JERKY MOTION PREVIEW %s: %d production frames, %d keyframes; %s" % ["PASS" if failures.is_empty() else "FAIL", frames.size(), keyframes.size(), path])
	quit(0 if failures.is_empty() else 1)


func _source_hashes() -> Dictionary:
	var result := {}
	for source: String in SOURCE_FILES:
		result[source] = FileAccess.get_sha256(source)
	return result


func _inventory_contents(inventory: ExpeditionInventory) -> Dictionary:
	if inventory == null:
		return {}
	return {"slots": inventory.slots.duplicate(true), "equipment": inventory.equipment.duplicate(true), "equipment_data": inventory.equipment_data.duplicate(true)}


func _create_side_diagnostic(player: DungeonPlayer) -> SubViewport:
	# A second camera observes the same posed production meshes. It never changes
	# the player's camera, hand pose, object attachment or first-person recording.
	var view := SubViewport.new()
	view.name = "JerkyWristSideDiagnostic"
	view.size = IMAGE_SIZE
	view.gui_disable_input = true
	view.physics_object_picking = false
	view.audio_listener_enable_3d = false
	view.world_3d = player.camera.get_world_3d()
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.msaa_3d = Viewport.MSAA_4X
	root.add_child(view)
	var camera := Camera3D.new()
	camera.name = "DiagnosticOnlyCamera"
	camera.cull_mask = 1 << 19
	camera.near = 0.025
	camera.fov = 55.0
	view.add_child(camera)
	camera.global_position = player.camera.to_global(Vector3(0.65, -0.12, 0.02))
	camera.look_at(player.camera.to_global(Vector3(0.08, -0.22, -0.27)))
	camera.current = true
	return view
