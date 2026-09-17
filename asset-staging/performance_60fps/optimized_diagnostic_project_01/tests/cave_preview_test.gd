extends SceneTree

const PREVIEW := preload("res://tests/cave_preview.gd")
const LAYOUT := preload("res://scripts/cave_layout.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 413
	ExpeditionSession.hunger = 63.0
	ExpeditionSession.stress = 27.0
	var inventory := ExpeditionSession.get_inventory()
	var inventory_slots := inventory.slots.duplicate(true)
	var equipment := inventory.equipment.duplicate(true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var camera := PREVIEW.populate_viewport(viewport)
	if camera == null:
		viewport.queue_free()
		push_error("Cave preview must construct successfully before structural or export checks.")
		quit(1)
		return
	await process_frame
	_check(viewport.size == Vector2i(1280, 720), "preview must capture 1280 x 720 pixels")
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking, "preview must isolate its world and reject desktop input")
	_check(camera.is_current() and camera.get_world_3d() == viewport.find_world_3d(), "preview camera must use its own 3D viewport")
	var carried_spot := camera.get_node_or_null("PreviewCarriedTorchSpot") as SpotLight3D
	var carried_fill := camera.get_node_or_null("PreviewCarriedTorchFill") as OmniLight3D
	_check(carried_spot != null and carried_fill != null and is_equal_approx(carried_spot.spot_range, 19.0) and is_equal_approx(carried_fill.omni_range, 7.2), "preview must include the actual player's lit hand-torch ranges without instantiating a player")
	var geometry := viewport.find_child("CaveGeometry", true, false)
	_check(geometry != null and geometry.get_child_count() > 0, "preview must build the actual playable cave geometry")
	var environment := viewport.find_child("WorldEnvironment", true, false) as WorldEnvironment
	_check(environment != null and environment.environment != null and environment.environment.fog_enabled, "preview must use the cave game's fog and lighting environment")
	_check(PREVIEW.SHOTS.size() == 5, "preview must cover quarry, monster bones, shrine, long lake and workshops")
	for shot in PREVIEW.SHOTS:
		_check(LAYOUT.bounds().has_point(Vector2(shot.position.x, shot.position.z)), "camera must remain within the metre-based cave footprint: %s" % shot.name)
		camera.global_position = shot.position
		camera.look_at(shot.target, Vector3.UP)
		var forward := -camera.global_transform.basis.z
		_check(forward.dot((shot.target - shot.position).normalized()) > 0.999, "camera must face the requested chamber: %s" % shot.name)
	_check(get_nodes_in_group("player").is_empty() and get_nodes_in_group("enemy").is_empty(), "geometry preview must never create gameplay actors")
	_check(viewport.find_children("*", "AudioStreamPlayer", true, false).is_empty() and viewport.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "geometry preview must not create audio players")
	_check(Input.mouse_mode == mouse_mode, "preview construction must not change cursor mode")
	_check(ExpeditionSession.capture_snapshot() == snapshot, "preview construction must not mutate the live expedition")
	_check(inventory.slots == inventory_slots and inventory.equipment == equipment, "preview must preserve the live bag contents and equipment")
	if OS.get_environment("CAVE_QA_EXPORT_GEOMETRY") == "1":
		var export_result: Variant = load("res://tests/cave_offline_export.gd").export_geometry(viewport, PREVIEW.SHOTS)
		_check(export_result is Dictionary and export_result.get("success", false), "optional offline geometry transfer must complete explicitly: %s" % str(export_result))
		var exported_glb := FileAccess.open("res://artifacts/visual_qa/cave_offline/cave_geometry.glb", FileAccess.READ)
		_check(exported_glb != null and exported_glb.get_length() > 1024, "offline geometry transfer must create a nonempty actual GLB")
		if exported_glb != null:
			exported_glb.close()
		var metadata := FileAccess.open("res://artifacts/visual_qa/cave_offline/metadata.json", FileAccess.READ)
		_check(metadata != null and metadata.get_length() > 100, "offline geometry transfer must create camera metadata")
		if metadata != null:
			metadata.close()
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot, "preview cleanup must preserve the live expedition")
	if failures.is_empty():
		print("CAVE PREVIEW STRUCTURE PASS: real geometry, five cameras, shared atmosphere, isolated world, no input/audio/session side effects; no pixel verification claimed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
