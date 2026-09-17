extends SceneTree

const PREVIEW := preload("res://tests/art_direction_preview.gd")
const NATURALISM := preload("res://tests/mine_naturalism_preview.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(PREVIEW.output_directory("revision_02").ends_with("/revision_02"), "art direction iterations must have isolated output directories")
	for unsafe in ["../naturalism", "/tmp/overwrite", "baseline", "two/parts", "UPPER", " "]:
		if unsafe.strip_edges().is_empty():
			_check(PREVIEW.output_directory(unsafe).ends_with("/iteration_01"), "empty iteration must have a safe default")
		else:
			_check(PREVIEW.output_directory(unsafe).is_empty(), "unsafe or reserved output slugs must be rejected: " + unsafe)
	_check(PREVIEW.selected_shots("").size() == 5 and PREVIEW.selected_shots("missing").is_empty(), "art direction shot selection must be complete by default and reject unknown names")
	_check(PREVIEW.SHOTS[0].position == NATURALISM.SHOTS[0].position and PREVIEW.SHOTS[0].target == NATURALISM.SHOTS[0].target, "water-shore comparison must use exactly the preserved naturalism camera")
	var baseline_path := PREVIEW.OUTPUT_ROOT + "/baseline/manifest.json"
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
	_check(not baseline.get("files", []).is_empty(), "pre-art-direction actual screenshots must remain preserved")
	for file: Dictionary in baseline.get("files", []):
		_check(FileAccess.get_sha256(PREVIEW.OUTPUT_ROOT + "/baseline/" + file.file) == file.sha256, "baseline screenshots must remain byte-for-byte unchanged: " + str(file.file))
	ExpeditionSession.begin_new_journey()
	ExpeditionSession.crowns = 631
	ExpeditionSession.stress = 33.0
	var snapshot := ExpeditionSession.capture_snapshot()
	var inventory := ExpeditionSession.get_inventory()
	var mouse_mode := Input.mouse_mode
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	_check(viewport.use_taa == bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false)), "normal art direction captures must use the actual project's temporal antialiasing setting")
	for initial_taa in [false, true]:
		viewport.use_taa = initial_taa
		var previous_taa := PREVIEW.begin_matched_water_capture(viewport)
		_check(not viewport.use_taa and previous_taa == initial_taa, "matched-clock water capture must clear temporal history while preserving its previous setting")
		PREVIEW.end_matched_water_capture(viewport, previous_taa)
		_check(viewport.use_taa == initial_taa, "both enabled and disabled temporal antialiasing settings must be restored after the water comparison")
	viewport.use_taa = bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false))
	var player := PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var geometry: Node3D = viewport.find_child("CaveGeometry", true, false)
	_check(await PREVIEW.await_geometry_ready(geometry), "actual wall lights and grounded dressing must finish before comparisons")
	_check(not bool(PREVIEW.inspect_detail_rendering(geometry).verified), "dummy MultiMesh storage must never be treated as actual renderer readback")
	_inspect_wall_lighting(geometry)
	_check(viewport.own_world_3d and viewport.gui_disable_input and not viewport.physics_object_picking, "art direction preview must isolate its world and reject desktop input")
	_check(player.game == null and player.hud == null and player.inventory_model == null and not player.is_physics_processing() and not player.is_processing_unhandled_input(), "preview must not attach a real expedition, UI or input handler")
	var environment := viewport.find_child("WorldEnvironment", true, false) as WorldEnvironment
	var production: Environment = load("res://scripts/cave_dungeon.gd").make_environment()
	_check(environment.environment.background_color == production.background_color and environment.environment.ambient_light_color == production.ambient_light_color and is_equal_approx(environment.environment.ambient_light_energy, production.ambient_light_energy), "actual preview environment must match the playable cave's light and background")
	_check(environment.environment.ambient_light_color.b > environment.environment.ambient_light_color.r and player.torch.light_color.r > player.torch.light_color.b, "cool cave ambience and warm carried fire must remain distinct production lighting roles")
	_check(player.torch.has_meta("base_energy") and player.torch_fill.has_meta("base_energy"), "preview must receive the production animated-light profile rather than a fixed preview override")
	var spot_base := float(player.torch.get_meta("base_energy", 0.0))
	var fill_base := float(player.torch_fill.get_meta("base_energy", 0.0))
	for time_step in [0.016, 0.15, 0.8, 1.2]:
		player._update_torch(time_step)
		_check(absf(player.torch.light_energy - spot_base) < spot_base * 0.15 and absf(player.torch_fill.light_energy - fill_base) < fill_base * 0.15, "normal torch animation must not snap back to the previous overbright cave profile")
	player.set_torch_enabled(false)
	_check(not player.torch.visible and not player.torch_fill.visible, "production torch off must still disable both world lights")
	player.set_torch_enabled(true)
	_check(player.torch.visible and player.torch_fill.visible and float(player.torch.get_meta("base_energy")) == spot_base, "turning the real torch back on must preserve its cave profile")
	for shot in PREVIEW.SHOTS:
		PREVIEW.configure_shot(player, shot)
		var show_gear := bool(shot.get("equipment", false))
		_check(player.weapon_pivot.visible == show_gear and player.shield_pivot.visible == show_gear and player.torch_pivot.visible == show_gear, "actual gameplay equipment must be visible only in the equipment comparison")
		_check(player.camera.fov == 76.0 and player.viewmodel_renderer.camera.fov == player.camera.fov, "real and equipment cameras must preserve the baseline perspective")
	_check(Input.mouse_mode == mouse_mode and ExpeditionSession.capture_snapshot() == snapshot and ExpeditionSession.get_inventory() == inventory, "art direction construction and light comparisons must preserve live input and original expedition")
	viewport.queue_free()
	await process_frame
	_check(ExpeditionSession.capture_snapshot() == snapshot, "art direction cleanup must preserve original expedition state")
	if failures.is_empty():
		print("ART DIRECTION PREVIEW STRUCTURE PASS: unchanged baseline hashes, fixed cameras, safe iteration paths, shared production atmosphere and animated torch profile, real equipment, isolated input and expedition; no rendered pixel verification claimed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)


func _inspect_wall_lighting(geometry: Node3D) -> void:
	var lighting: Node3D = geometry.get("art_lighting")
	_check(lighting != null, "production cave must build attached working-face lamps")
	if lighting == null:
		return
	var state: Dictionary = lighting.call("get_state_snapshot")
	print("ART DIRECTION WORKING-FACE LAMPS: %s" % str(state))
	_check(state.ready and state.lamp_count > 0, "working-face lamps must finish with real surface attachments")
	var lights := lighting.find_children("*", "OmniLight3D", true, false)
	_check(lights.size() == int(state.lamp_count), "each reported working-face fixture must contain an actual world light")
	_check(lighting.find_children("*", "CollisionObject3D", true, false).is_empty(), "supplemental visual lamps must not alter walking collision")
	var excluded: Array[RID] = []
	for body in geometry.find_children("*", "StaticBody3D", true, false):
		if not str(body.name).begins_with("Collision_Terrain_"):
			excluded.append(body.get_rid())
	for contact: Dictionary in state.contacts:
		var mount := lighting.get_node_or_null(NodePath(str(contact.name)))
		_check(mount != null, "reported lamp must have a real fixture node")
		if mount == null:
			continue
		var light := mount.get_node_or_null("SurveyLampLight") as OmniLight3D
		_check(light != null and light.global_position.distance_to(contact.wick) < 0.005, "lamp illumination must originate at the actual fixture wick")
		if light:
			_check(light.light_energy > 0.0 and light.omni_range > 0.0 and light.light_color.r > light.light_color.b, "actual working-face lamps must cast localized warm light")
		var imported_parts := mount.find_children("BlenderLanternPart_*", "MeshInstance3D", false, false)
		_check(imported_parts.size() > 0 and imported_parts.size() == int(contact.blender_parts), "working-face lights need the real imported lantern cage, not an empty light node")
		for point: Vector3 in [contact.upper_contact, contact.lower_contact]:
			var normal: Vector3 = contact.normal
			var query := PhysicsRayQueryParameters3D.create(point + normal * 0.4, point - normal * 0.4, 2, excluded)
			query.hit_back_faces = true
			var hit: Dictionary = geometry.get_world_3d().direct_space_state.intersect_ray(query)
			_check(not hit.is_empty() and str(hit.collider.name).begins_with("Collision_Terrain_"), "both lamp supports must meet actual imported rock triangles")
			if not hit.is_empty():
				_check(point.distance_to(hit.position) < 0.085, "both working-face mount anchors must remain embedded against the rock")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
