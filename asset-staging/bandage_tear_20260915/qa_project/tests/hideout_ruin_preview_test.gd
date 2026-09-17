extends SceneTree

const PREVIEW := preload("res://tests/hideout_ruin_preview.gd")
const VIEWS := preload("res://scripts/hideout_ruin_views.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var expected: Array[String] = ["central", "entrance", "sleep", "storage", "workshop", "flooded_store", "ossuary", "drain"]
	_check(VIEWS.ordered_ids() == expected and VIEWS.selected_shots("").size() == 8, "default capture includes each of the eight authored rooms exactly once")
	var selection := VIEWS.selected_shots("drain,central,central")
	_check(selection.size() == 2 and selection[0].id == "central" and selection[1].id == "drain", "filtered captures deduplicate and retain the canonical room order")
	_check(VIEWS.selected_shots("central,unknown").is_empty() and VIEWS.get_shot("unknown").is_empty(), "unknown room ids fail closed")
	var copied := VIEWS.get_shot("central")
	copied.position = Vector3.ZERO
	_check(VIEWS.get_shot("central").position == Vector3(0.0, 1.7, 8.4), "camera consumers cannot mutate the shared authored catalog")
	var original := ExpeditionSession.capture_snapshot()
	ExpeditionSession.begin_new_journey()
	var bag := ExpeditionSession.get_inventory()
	bag.add_item("alchemy_wine", 3)
	ExpeditionSession.crowns = 873
	ExpeditionSession.hunger = 38.0
	ExpeditionSession.stress = 47.0
	var expedition_before := ExpeditionSession.capture_snapshot()
	var bag_before := PREVIEW.inventory_fingerprint(bag)
	var cursor_before := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	var sandbox_original := PREVIEW.sandbox_snapshot(sandbox)
	# A queued, active test expedition must remain just as untouched as normal
	# play. The harness does not consume pending requests or call begin/finish.
	sandbox.active = true
	sandbox.saved_session = original.duplicate(true)
	sandbox.pending_cave_entry_room = "preview-preservation-sentinel"
	sandbox.pending_blacksmith_trial = "rune"
	sandbox.pending_alchemy_trial = "hearth_brandy"
	sandbox.pending_cooking_trial = true
	var sandbox_before := PREVIEW.sandbox_snapshot(sandbox)
	_check(sandbox_before.has("active") and sandbox_before.has("saved_session") and sandbox_before.has("pending_cooking_trial") and sandbox_before.has("return_banner"), "sandbox evidence discovers all script variables, including object identity and future pending views")
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	_check(viewport.size == Vector2i(1280, 720) and viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d and not viewport.audio_listener_enable_2d, "actual rendering is isolated and cannot read external UI, physics picking or audio")
	_check(viewport.find_children("*", "MeshInstance3D", true, false).size() > 50, "room images use the combined real hideout world and functional production props")
	_check(_inputs_disabled(viewport), "the inspected world and camera cannot run gameplay processing or sample input")
	var regions := {}
	for region in get_nodes_in_group("hideout_stream_region"):
		if viewport.is_ancestor_of(region):
			regions[str(region.get_meta("region_id"))] = region
	_check(regions.size() == 8, "preview constructs all eight actual production streaming regions")
	for shot in VIEWS.SHOTS:
		_check(regions.has(shot.region_id), "catalog view resolves to the real region: " + str(shot.id))
		if regions.has(shot.region_id):
			var bounds: AABB = regions[shot.region_id].get_meta("streaming_bounds")
			_check(bounds.has_point(shot.position), "camera eye remains inside its own actual room: " + str(shot.id))
		_check(PREVIEW.configure_shot(viewport, shot), "actual production camera configures: " + str(shot.id))
		var camera := PREVIEW.PRODUCTION.active_camera(viewport)
		_check(camera != null and camera.global_position.distance_to(shot.position) < 0.01 and is_equal_approx(camera.fov, float(shot.fov)) and is_equal_approx(camera.global_position.y, 1.7), "baseline and current retain eye height, exact position and field of view: " + str(shot.id))
		_check(camera.unproject_position(shot.target).distance_to(Vector2(viewport.size) * 0.5) < 1.0, "authored target remains centered without composition drift: " + str(shot.id))
		var player := viewport.find_child("ProductionTorchCamera", true, false) as DungeonPlayer
		_check(player.torch.is_visible_in_tree() and player.torch_fill.is_visible_in_tree(), "real torch spotlight and fill survive hiding hands: " + str(shot.id))
	_check(not PREVIEW.configure_shot(viewport, {"id": "unknown"}), "unsupported camera id cannot render an unlabeled room")
	viewport.free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == expedition_before and ExpeditionSession.get_inventory() == bag and PREVIEW.inventory_fingerprint(bag) == bag_before, "preview builders and eight views preserve every expedition field, original bag identity and contents")
	_check(PREVIEW.sandbox_snapshot(sandbox) == sandbox_before and Input.mouse_mode == cursor_before, "all pending test requests, saved expedition, UI object references and cursor remain unchanged")
	var hashes := PREVIEW.collect_source_hashes()
	for source in ["res://scripts/hideout.gd", "res://scripts/hideout_ruin_views.gd", "res://tests/hideout_ruin_preview.gd", "res://tests/run_embedded_preview.sh"]:
		_check(str(hashes.get(source, "")).length() == 64, "evidence hashes the production scene and shared camera/capture sources: " + source)
	for property in sandbox_original:
		sandbox.set(property, sandbox_original[property])
	ExpeditionSession.restore_snapshot(original)
	if failures.is_empty():
		print("HIDEOUT RUIN PREVIEW TEST PASS: eight isolated production rooms, matching eye-height cameras, real torch lighting, fail-closed selection and complete journey/bag/sandbox/cursor preservation")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _inputs_disabled(node: Node) -> bool:
	if node.is_processing_input() or node.is_processing_unhandled_input() or node.is_processing() or node.is_physics_processing():
		return false
	for child in node.get_children():
		if not _inputs_disabled(child):
			return false
	return true


func _check(passed: bool, message: String) -> void:
	if not passed:
		failures.append(message)
