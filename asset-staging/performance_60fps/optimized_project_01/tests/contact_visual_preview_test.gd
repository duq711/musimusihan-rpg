extends SceneTree

const PREVIEW := preload("res://tests/contact_visual_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(PREVIEW.selected_shots("").size() == 5, "default contact preview must retain all five authored shots")
	var wall_shots := PREVIEW.selected_shots(" wall_close_sword_shield_torch , wall_close_guard,wall_close_guard ")
	_check(wall_shots.size() == 2 and wall_shots[0].name == "wall_close_sword_shield_torch" and wall_shots[1].name == "wall_close_guard", "shot selection must trim names, preserve requested order and avoid duplicate renders")
	_check(PREVIEW.selected_shots("missing,wall_close_guard").is_empty(), "unknown shot names must reject the run rather than claim a partial capture")
	var black_equipment := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	black_equipment.fill(Color(0.0, 0.0, 0.0, 1.0))
	black_equipment.fill_rect(Rect2i(0, 0, 64, 128), Color(1.0, 0.45, 0.05, 1.0))
	var black_pixels: Dictionary = PREVIEW.inspect_equipment_pixels(black_equipment)
	_check(not black_pixels.passed and black_pixels.opaque_pixels > 1000 and black_pixels.lit_pixels == 0, "bright left-hand flames must not conceal an otherwise black sword silhouette")
	var lit_equipment := black_equipment.duplicate() as Image
	lit_equipment.fill_rect(Rect2i(96, 0, 32, 128), Color(0.16, 0.13, 0.09, 1.0))
	_check(PREVIEW.inspect_equipment_pixels(lit_equipment).passed, "substantial illuminated sword material must pass the actual pixel visibility criterion")
	lit_equipment.fill(Color(0.9, 0.9, 0.9, 0.0))
	_check(not PREVIEW.inspect_equipment_pixels(lit_equipment).passed, "transparent image pixels must not count as visible equipment")
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 823
	ExpeditionSession.hunger = 57.0
	var inventory := ExpeditionSession.get_inventory()
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var player := PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking, "contact preview must isolate physics and reject desktop input")
	_check(player.game == null and player.hud == null and player.inventory_model == null, "contact preview player must have no gameplay, HUD or live bag binding")
	_check(not player.is_physics_processing() and not player.is_processing_unhandled_input(), "contact preview must disable gameplay physics and input before its first frame")
	_check(player.get_world_3d() == viewport.find_world_3d(), "contact camera and actual cave must share only their dedicated viewport world")
	_check(viewport.find_child("CaveGeometry", true, false) != null and PREVIEW.SHOTS.size() == 5, "contact preview must cover real mine dressing and near-wall ready and guard poses")
	for shot in PREVIEW.SHOTS:
		_check(PREVIEW.configure_shot(player, shot), "contact preview must resolve real geometry and equipped renderer for shot: " + str(shot.name))
		var equipment: bool = shot.get("equipment", false)
		_check(player.weapon_pivot.visible == equipment and player.shield_pivot.visible == equipment and player.torch_pivot.visible == equipment, "contact framing must show gear only in its wall proximity shots")
		if shot.get("wall_close", false):
			var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, player.camera.global_position - player.camera.global_basis.z * 0.7, DungeonPlayer.WORLD_LAYER)
			var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
			_check(not hit.is_empty() and player.camera.global_position.distance_to(hit.position) < 0.48, "wall proximity captures must actually face a wall within 48cm")
		elif shot.name == "entrance_wall_lamp":
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3d/abandoned_mine/build_manifest.json"))
			var lamp: Dictionary = PREVIEW._nearest_contact(manifest.get("prop_contact", {}).get("wall_lanterns", []), "wick_godot", Vector3(0.44, 2.0, 50.35))
			if not lamp.is_empty():
				var inward: Vector3 = PREVIEW._point3(lamp.wall_normal_godot)
				inward.y = 0.0
				inward = inward.normalized()
				var offset: Vector3 = player.camera.global_position - PREVIEW._point3(lamp.wick_godot)
				_check(is_equal_approx(offset.dot(inward), 1.45) and is_equal_approx(offset.dot(inward.cross(Vector3.UP)), 0.7), "wall-lamp framing must retain its inward clearance while revealing the bracket from 70cm to the side")
		_check(player.viewmodel_renderer != null and player.viewmodel_renderer.viewport.find_world_3d() == player.get_world_3d(), "contact preview must use the production separate-depth gear renderer")
	_check(player.blocking, "last contact capture must exercise the real raised guard pose")
	_check(viewport.find_children("*", "AudioStreamPlayer", true, false).is_empty() and viewport.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(), "contact preview must create no audio players")
	_check(Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot and ExpeditionSession.get_inventory() == inventory, "contact construction and shot changes must preserve cursor and original expedition")
	viewport.queue_free()
	await process_frame
	_check(Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot, "contact preview cleanup must preserve live state")
	if failures.is_empty():
		print("CONTACT PREVIEW STRUCTURE PASS: real mine and production equipment compositor, five actual camera poses, close-wall collision, no input/audio/expedition mutation; no pixel verification claimed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
