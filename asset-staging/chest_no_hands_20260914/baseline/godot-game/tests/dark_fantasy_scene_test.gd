extends SceneTree

const PREVIEW := preload("res://tests/dark_fantasy_scene_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(PREVIEW.capture_locations("") == ["hideout", "dungeon", "mine"], "the default capture must include all ten actual camera shots")
	_check(PREVIEW.capture_locations("hideout,hideout") == ["hideout"], "targeted hideout capture must select one real location without duplicate shots")
	_check(PREVIEW.capture_locations("mine,hideout") == ["hideout", "mine"], "partial captures must retain the canonical scene order")
	_check(PREVIEW.capture_locations("unknown").is_empty(), "unknown location selection must fail closed")
	ExpeditionSession.begin_new_journey()
	var inventory := ExpeditionSession.get_inventory()
	ExpeditionSession.crowns = 927
	ExpeditionSession.stress = 42.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var sandbox := root.get_node("TestRoomSandbox")
	_check(not sandbox.active, "whole-location art inspection must not enter or alter a test expedition")
	for scene_id in ["hideout", "dungeon", "mine"]:
		var viewport := PREVIEW.create_viewport(scene_id)
		root.add_child(viewport)
		PREVIEW.populate_viewport(viewport)
		await physics_frame
		await physics_frame
		if scene_id == "mine":
			var geometry := viewport.find_child("CaveGeometry", true, false)
			_check(await PREVIEW.MINE_PREVIEW.await_geometry_ready(geometry), "mine capture must wait for actual wall lamps and surface-attached production dressing")
			_check(is_instance_valid(geometry.get("art_details")) and is_instance_valid(geometry.get("art_lighting")), "mine composition must include the real production dressing and lighting systems")
			if OS.get_environment("DARK_FANTASY_EXPORT_BOARD_SAMPLES") == "1":
				_export_board_samples(geometry.get("art_details"))
		_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking and not viewport.audio_listener_enable_3d, "every production location must render in an isolated world with native input/audio disabled")
		var meshes := viewport.find_children("*", "MeshInstance3D", true, false)
		_check(meshes.size() > 50, "production location must contain its combined authored world and objects: " + scene_id)
		_check(_inputs_disabled(viewport), "no production location actor may sample input or run gameplay physics: " + scene_id)
		for shot in PREVIEW.SHOTS:
			if str(shot.scene) != scene_id:
				continue
			_check(PREVIEW.configure_shot(viewport, shot), "fixed production camera must configure: " + str(shot.id))
			var torch_owner := viewport.find_child("ProductionTorchCamera", true, false) as DungeonPlayer
			_check(torch_owner.torch.is_visible_in_tree() and torch_owner.torch_fill.is_visible_in_tree(), "hiding completed body and hands must preserve both actual production torch lights: " + str(shot.id))
			var camera := PREVIEW.active_camera(viewport)
			_check(is_instance_valid(camera) and camera.global_position.distance_to(shot.position) < 0.01 and is_equal_approx(camera.fov, 76.0), "baseline/current must use exact same authored camera and field of view: " + str(shot.id))
			var centered := camera.unproject_position(shot.target)
			_check(centered.distance_to(Vector2(PREVIEW.IMAGE_SIZE) * 0.5) < 1.0, "fixed target must remain at the actual camera center: " + str(shot.id))
		_check(snapshot == ExpeditionSession.capture_snapshot() and ExpeditionSession.get_inventory() == inventory and Input.mouse_mode == mouse and not sandbox.active, "whole-location construction and camera changes must preserve inventory identity, every expedition field, sandbox state and cursor")
		viewport.free()
		await process_frame
	_check(PREVIEW.create_viewport("unknown") == null, "unsupported production location ids must fail closed")
	if failures.is_empty():
		print("DARK FANTASY SCENE PASS: actual hideout, dungeon and mine builders, production dressing, ten matching cameras, no input/physics/gameplay execution and complete expedition/cursor preservation")
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


func _export_board_samples(details: Node) -> void:
	var batches: Dictionary = details.get("_batches")
	var samples := {}
	for key in batches:
		var batch: Dictionary = batches[key]
		var variant := int(batch.variant)
		if variant < 12 or samples.has(str(variant)) or batch.transforms.is_empty():
			continue
		var transform: Transform3D = batch.transforms[0]
		var color: Color = batch.colors[0]
		samples[str(variant)] = {"batch": str(key), "basis": [PREVIEW._vector(transform.basis.x), PREVIEW._vector(transform.basis.y), PREVIEW._vector(transform.basis.z)], "origin": PREVIEW._vector(transform.origin), "scale": PREVIEW._vector(transform.basis.get_scale()), "color": [color.r, color.g, color.b, color.a]}
	_check(samples.size() == 3, "actual placed board evidence must include every production board variant")
	var output := "res://artifacts/visual_qa/mine_board_samples.json"
	var file := FileAccess.open(output, FileAccess.WRITE)
	_check(file != null, "actual board evidence must save for matching baseline/current capture factories")
	if file != null:
		file.store_string(JSON.stringify(samples, "\t") + "\n")
		print("ACTUAL BOARD SAMPLES: " + ProjectSettings.globalize_path(output))
