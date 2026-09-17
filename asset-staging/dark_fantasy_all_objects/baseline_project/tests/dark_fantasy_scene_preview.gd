extends SceneTree
## Whole production locations, without a running gameplay scene or native UI.
## All constructors are explicit reviewed visual builders. The mine reuses the
## already-reviewed input-free production geometry and torch camera helpers.

const MINE_PREVIEW := preload("res://tests/art_direction_preview.gd")
const EVIDENCE := preload("res://tests/dark_fantasy_capture_evidence.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/dark_fantasy_scenes"
const SHOTS: Array[Dictionary] = [
	{"id": "hideout_hearth", "scene": "hideout", "position": Vector3(3.5, 1.65, 5.5), "target": Vector3(0.0, 0.65, 2.2)},
	{"id": "hideout_storage", "scene": "hideout", "position": Vector3(9.1, 1.8, 3.3), "target": Vector3(13.0, 0.95, 6.1)},
	{"id": "hideout_saint", "scene": "hideout", "position": Vector3(3.0, 1.7, -2.0), "target": Vector3(0.0, 1.3, -6.45)},
	{"id": "hideout_workshop", "scene": "hideout", "position": Vector3(9.1, 1.8, -3.5), "target": Vector3(12.0, 0.8, -7.0)},
	{"id": "dungeon_entry", "scene": "dungeon", "position": Vector3(0.0, 1.72, 13.0), "target": Vector3(0.0, 1.4, 3.0)},
	{"id": "dungeon_chest", "scene": "dungeon", "position": Vector3(-1.9, 1.72, 13.0), "target": Vector3(-5.6, 0.65, 10.5)},
	{"id": "dungeon_sanctum", "scene": "dungeon", "position": Vector3(1.4, 1.72, -6.2), "target": Vector3(0.0, 1.5, -14.0)},
	{"id": "mine_entrance", "scene": "mine", "position": Vector3(0.6, 1.75, 60.1), "target": Vector3(3.356, 0.65, 57.54)},
	{"id": "mine_timber", "scene": "mine", "position": Vector3(-0.8, 1.75, 59.6), "target": Vector3(0.25, 3.6, 54.7)},
	{"id": "mine_water_shore", "scene": "mine", "position": Vector3(-57.0, 1.5, -18.0), "target": Vector3(-53.9, 0.035, -15.8)},
]


func _init() -> void:
	call_deferred("_run")


static func create_viewport(scene_id: String) -> SubViewport:
	if scene_id not in ["hideout", "dungeon", "mine"]:
		return null
	var viewport := SubViewport.new()
	viewport.name = "ActualLocation_" + scene_id
	viewport.size = IMAGE_SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.audio_listener_enable_3d = false
	viewport.audio_listener_enable_2d = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.set_meta("production_location", scene_id)
	return viewport


static func populate_viewport(viewport: SubViewport) -> void:
	var scene_id := str(viewport.get_meta("production_location"))
	if scene_id == "mine":
		var player := MINE_PREVIEW.populate_viewport(viewport)
		player.name = "ProductionTorchCamera"
		_stop_execution(viewport, false)
		return
	var stage: Node3D
	if scene_id == "hideout":
		var helper: Node = load("res://scripts/hideout.gd").new()
		helper.call("_build_materials")
		# _build_world creates only authored geometry, environment, props and
		# occluders. The separate _ready/player/UI/input paths are never called.
		helper.call("_build_world")
		stage = helper.get("world_root") as Node3D
		helper.remove_child(stage)
		helper.free()
	else:
		var helper: Node3D = load("res://scripts/game.gd").new()
		helper.call("_build_materials")
		helper.call("_build_environment")
		helper.call("_build_dungeon")
		helper.call("_spawn_encounters")
		helper.call("_spawn_loot_chests")
		helper.call("_build_extraction_gate")
		# Constructors are the same functions used by the live actors' _ready,
		# but no actor is permitted to enter the tree with a gameplay script.
		for child in helper.get_children():
			if child is DungeonEnemy:
				child.call("_build_body")
				# Use the same settled production idle wrist as the object gallery.
				child.call("_update_weapon_pose", 1.0)
			elif child is DungeonLootChest or child is RuneTrap:
				child.call("_build_visuals")
		stage = Node3D.new()
		for child in helper.get_children():
			helper.remove_child(child)
			stage.add_child(child)
		helper.free()
	stage.name = "ProductionLocation"
	_stop_execution(stage, true)
	viewport.add_child(stage)
	# The playable scenes are explored with the production handheld torch.
	# Retain that exact camera/light rig while hiding the completed body/arms.
	var player := DungeonPlayer.new()
	player.name = "ProductionTorchCamera"
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	if scene_id == "hideout":
		player.configure_safe_zone(true)
	stage.add_child(player)
	player.name = "ProductionTorchCamera"
	player.camera.fov = 76.0
	player.camera.far = 160.0
	_stop_execution(player, false)


static func configure_shot(viewport: SubViewport, shot: Dictionary) -> bool:
	if str(shot.scene) != str(viewport.get_meta("production_location")):
		return false
	var player := viewport.find_child("ProductionTorchCamera", true, false) as DungeonPlayer
	if player == null:
		return false
	MINE_PREVIEW.configure_shot(player, {"name": str(shot.id), "position": shot.position, "target": shot.target, "equipment": false})
	# Hide carried meshes individually so their parented real torch fill
	# remains enabled exactly as it is during ordinary exploration.
	for carried: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		carried.show()
		_hide_carried_geometry(carried)
	player.viewmodel_renderer.sync_view()
	return true


static func active_camera(viewport: SubViewport) -> Camera3D:
	return viewport.get_camera_3d()


static func _stop_execution(node: Node, strip_scripts: bool) -> void:
	if strip_scripts and node.get_script() != null:
		node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_ALWAYS if node is CPUParticles3D or node is CollisionObject3D else Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child in node.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			node.remove_child(child)
			child.free()
		else:
			_stop_execution(child, strip_scripts)


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Production location captures require the reviewed embedded Vulkan renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("DARK_FANTASY_SCENE_ITERATION").strip_edges()
	if iteration.is_empty():
		iteration = "iteration_01"
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Use a new production-scene capture folder; existing evidence is preserved.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var source_hashes := EVIDENCE.collect()
	var records: Array[Dictionary] = []
	var failed := false
	for scene_id in ["hideout", "dungeon", "mine"]:
		var viewport := create_viewport(scene_id)
		root.add_child(viewport)
		populate_viewport(viewport)
		await physics_frame
		await physics_frame
		if scene_id == "mine":
			var geometry := viewport.find_child("CaveGeometry", true, false)
			if not await MINE_PREVIEW.await_geometry_ready(geometry):
				failed = true
				push_error("Production mine surface attachments did not finish.")
		for shot in SHOTS:
			if str(shot.scene) != scene_id:
				continue
			if not configure_shot(viewport, shot):
				failed = true
				break
			for frame in range(16):
				await process_frame
			RenderingServer.force_draw(false)
			var captured := viewport.get_texture().get_image()
			var filename := str(shot.id) + ".png"
			if captured == null or captured.is_empty() or captured.save_png(output.path_join(filename)) != OK:
				failed = true
				break
			records.append({"id": shot.id, "scene": scene_id, "file": filename, "sha256": FileAccess.get_sha256(output.path_join(filename)), "position": _vector(shot.position), "target": _vector(shot.target), "fov": 76.0})
			print("PRODUCTION SCENE CAPTURE: " + filename)
		viewport.free()
		await process_frame
	var preserved := snapshot == ExpeditionSession.capture_snapshot() and mouse_mode == Input.mouse_mode
	failed = failed or not preserved
	var sources_unchanged := source_hashes == EVIDENCE.collect()
	if not sources_unchanged:
		push_error("Production art sources changed during the location capture; freeze sources and use a new iteration.")
		failed = true
	var manifest := {"capture_kind": "Actual combined production hideout, dungeon and mine from fixed cameras and production lighting", "carried_geometry_visible": false, "production_torch_spot_and_fill_visible": true, "display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(), "desktop_capture": false, "external_input": false, "expedition_and_cursor_preserved": preserved, "source_sha256": source_hashes, "images": records}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	manifest["source_files_unchanged"] = sources_unchanged
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify(manifest, "\t") + "\n")
	print("DARK FANTASY SCENE PREVIEW %s: %d actual production location images; %s" % ["FAIL" if failed else "PASS", records.size(), output])
	quit(1 if failed else 0)


static func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _hide_carried_geometry(node: Node) -> void:
	if node is GeometryInstance3D:
		node.hide()
	for child in node.get_children():
		_hide_carried_geometry(child)
