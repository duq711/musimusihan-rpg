extends SceneTree
## Real runtime-selected shield meshes, rendered through the production player.
## Inspector copies share the selected mesh/material resources; they are clearly
## separate from the first-person views. No desktop window or input is used.
const STUDIO := preload("res://tests/sword_shield_preview.gd")
const DAMAGE := preload("res://scripts/shield_damage_visual.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/shield_damage"
const CONDITIONS := [
	{"stage": "high", "value": 75.0, "title": "상 · 온전한 방패"},
	{"stage": "medium", "value": 50.0, "title": "중 · 갈라진 방패"},
	{"stage": "low", "value": 20.0, "title": "하 · 크게 파손된 방패"},
]
const MARKERS := ["RearArmStrap", "RearGrip", "RearGripBottom", "RearGripTop"]
const SOURCES := [
	"res://tests/shield_damage_preview.gd", "res://tests/run_embedded_preview.sh",
	"res://scripts/shield_damage_visual.gd", "res://scripts/inventory_model.gd",
	"res://assets/3d/player/shield_damage/round_shield_medium.glb",
	"res://assets/3d/player/shield_damage/round_shield_low.glb",
	"res://assets/3d/player/shield_damage/round_shield_medium.glb.import",
	"res://assets/3d/player/shield_damage/round_shield_low.glb.import",
]
const FPS := 30
const SEQUENCE_FRAMES := 240

var failures: Array[String] = []
var captures: Array[Dictionary] = []

class WearDriver extends Node:
	var player: DungeonPlayer
	var inventory: ExpeditionInventory
	var tick := 0
	var hits: Array[Dictionary] = []
	var stages: Dictionary = {}

	func _physics_process(delta: float) -> void:
		tick += 1
		player.advance_combat_state(delta, true)
		if tick in [72, 144, 216, 288, 360]:
			# Isolate durability presentation from exhaustion. The actual hit,
			# blocking decision, wear and dedicated equipment signal are unmodified.
			player.stamina = player.MAX_STAMINA
			var before := player.get_shield_damage_snapshot()
			var result := player.receive_attack(40.0, player.global_position - player.global_basis.z * 2.0)
			hits.append({"tick": tick, "seconds": float(tick) / 60.0,
				"attack_damage": 40.0, "before": before, "result": result,
				"after": player.get_shield_damage_snapshot(), "health": player.health,
				"blocking_after_signal": player.blocking})
		player._update_viewmodel(delta)
		player._update_torch(delta)
		player.viewmodel_renderer.sync_view()
		var current := player.get_shield_damage_snapshot()
		stages[str(current.visual_stage)] = true
		if tick >= 480: set_physics_process(false)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Shield damage captures require the audited embedded runner at --fixed-fps 30.")
		quit(2)
		return
	var iteration := OS.get_environment("SHIELD_DAMAGE_QA_ITERATION").strip_edges()
	if not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("Set SHIELD_DAMAGE_QA_ITERATION to a new plain folder name.")
		quit(2)
		return
	var directory := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(directory):
		push_error("Previous shield captures will not be overwritten.")
		quit(2)
		return
	var sandbox := root.get_node("TestRoomSandbox")
	if sandbox.active:
		push_error("Shield preview requires its own test-room sandbox.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create shield capture directory.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	var audio_before := AudioServer.is_bus_mute(0)
	var cursor_before := Input.mouse_mode
	var session_before := ExpeditionSession.capture_snapshot()
	var fingerprint_before := STUDIO.PREVIEW.inventory_fingerprint(session_before.inventory)
	AudioServer.set_bus_mute(0, true)
	var source_paths: Array = STUDIO.PREVIEW.SOURCE_FILES.duplicate()
	source_paths.append_array(STUDIO.SOURCES)
	source_paths.append_array(SOURCES)
	var hashes := {}
	for path: String in source_paths:
		hashes[path] = FileAccess.get_sha256(path)
		_check(str(hashes[path]).length() == 64, "capture dependency exists: " + path)
	var previous_hz := Engine.physics_ticks_per_second
	var previous_steps := Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = maxi(previous_steps, 8)
	sandbox.begin()
	var viewport := STUDIO.create_studio_viewport()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var fixture := STUDIO.PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_check(STUDIO.configure_pose(fixture, "idle"), "production shield idle is available")
	STUDIO.configure_studio(fixture)
	var original_identity := _model_identity(player.shield_model)
	var mesh_ids := {}
	var pose_transforms := {}
	for pose: String in ["idle", "guard"]:
		_check(STUDIO.configure_pose(fixture, pose), "actual first-person " + pose + " configured")
		STUDIO.configure_studio(fixture)
		# Hold this production pose and its animation clock across all three
		# conditions. Only the item's dedicated durability signal changes it.
		for condition: Dictionary in CONDITIONS:
			inventory.set_equipment_durability("offhand", float(condition.value))
			var immediate := player.get_shield_damage_snapshot()
			_check(immediate.get("stage", "") == condition.stage and immediate.get("visual_stage", "") == condition.stage,
				"dedicated equipment signal immediately selects " + str(condition.stage))
			_check(immediate.get("source_path", "") == DAMAGE.SOURCES[condition.stage], "runtime asset agrees with durability stage")
			mesh_ids[condition.stage] = immediate.get("mesh_id", 0)
			player.viewmodel_renderer.sync_view()
			var label := _label(viewport, str(condition.title) + (" · 대기" if pose == "idle" else " · 방어"))
			var file := "%s_%s.png" % [condition.stage, pose]
			await _capture(viewport, directory.path_join(file))
			var production := player.get_first_person_motion_snapshot()
			var contact: Dictionary = production.get("hand_contacts", {}).get("shield", {})
			_check(not contact.is_empty() and float(contact.get("error", INF)) < .002, "shield hand remains on its real grip: " + file)
			_check(_same_identity(original_identity, _model_identity(player.shield_model)), "shield nodes and grip markers are preserved: " + file)
			_check(bool(production.get("shield_visible", false)), "shield remains visible in first person: " + file)
			var transforms := {"shield": player.shield_model.global_transform, "camera": player.camera.global_transform, "weapon": player.weapon_pivot.global_transform}
			if not pose_transforms.has(pose): pose_transforms[pose] = transforms
			else:
				for part: String in transforms:
					var expected: Transform3D = pose_transforms[pose][part]
					_check(expected.is_equal_approx(transforms[part]), "matching " + pose + " comparison transform: " + part)
			var material_info := _materials(player.shield_model)
			_check(bool(material_info.valid), "active runtime materials exist: " + file)
			captures.append({"file": file, "view": "actual_first_person", "pose": pose,
				"durability": player.get_shield_damage_snapshot(), "production": production,
				"transforms": transforms, "materials": material_info})
			label.get_parent().queue_free()
	for condition: Dictionary in CONDITIONS:
		inventory.set_equipment_durability("offhand", float(condition.value))
		await _capture_inspector(viewport, fixture, condition, directory)
	_check(int(mesh_ids.get("high", 0)) != 0 and mesh_ids.values().count(mesh_ids.get("high")) == 1 and mesh_ids.get("medium") != mesh_ids.get("low"), "all three stages use different actual mesh resources")
	# Verify returning to the original asset on this same player, not a fresh rig.
	inventory.set_equipment_durability("offhand", 75.0)
	_check(player.get_shield_damage_snapshot().get("mesh_id") == mesh_ids.get("high"), "repair restores the original cached shield mesh")
	_check(_same_identity(original_identity, _model_identity(player.shield_model)), "repair preserves original model and grip markers")
	viewport.queue_free()
	await process_frame
	var stills_only := OS.get_environment("SHIELD_DAMAGE_QA_STILLS") == "1"
	var sequence := await _capture_wear_sequence(directory, stills_only)
	sandbox.finish()
	Engine.physics_ticks_per_second = previous_hz
	Engine.max_physics_steps_per_frame = previous_steps
	AudioServer.set_bus_mute(0, audio_before)
	var state_preserved := session_before == ExpeditionSession.capture_snapshot() and cursor_before == Input.mouse_mode and fingerprint_before == STUDIO.PREVIEW.inventory_fingerprint(session_before.inventory)
	_check(state_preserved, "original expedition, inventory and cursor are preserved")
	var sources_preserved := true
	for path: String in hashes:
		if hashes[path] != FileAccess.get_sha256(path): sources_preserved = false
	_check(sources_preserved, "capture source files stayed unchanged")
	_check(captures.size() == 12, "six first-person and six inspector images captured")
	var manifest := {"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "desktop_capture": false, "source_sha256": hashes,
		"sources_unchanged_during_capture": sources_preserved, "session_inventory_cursor_preserved": state_preserved,
		"captures": captures, "sequence": sequence, "stills_only": stills_only, "failures": failures}
	var report := FileAccess.open(directory.path_join("capture_manifest.json"), FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: _check(false, "manifest saved")
	for failure: String in failures: push_error(failure)
	print("SHIELD DAMAGE PREVIEW %s: 12 views, 5 actual shield blocks, %d sequence frames; %s" % ["PASS" if failures.is_empty() else "FAIL", 0 if stills_only else SEQUENCE_FRAMES, directory])
	quit(0 if failures.is_empty() else 1)


func _capture_inspector(viewport: SubViewport, fixture: Dictionary, condition: Dictionary, directory: String) -> void:
	var player: DungeonPlayer = fixture.player
	var world: Node3D = fixture.stage
	var floor_node := world.get_node("ArmPreviewFloor") as Node3D
	var inspection := player.shield_model.duplicate(0) as Node3D
	inspection.name = "RuntimeSelectedShieldInspection"
	world.add_child(inspection)
	inspection.transform = Transform3D(Basis.IDENTITY, Vector3(0, 1, 0))
	inspection.visible = true
	for mesh: MeshInstance3D in inspection.find_children("*", "MeshInstance3D", true, false): mesh.layers = 1
	var selected_surface := player.shield_model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	var inspected_surface := inspection.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	_check(inspected_surface != null and selected_surface != null and inspected_surface.mesh == selected_surface.mesh, "inspector shares the exact runtime-selected mesh")
	var was_visible := player.visible
	var floor_visible := floor_node.visible
	player.visible = false
	floor_node.visible = false
	# Equal neutral fill reveals the rear grip and fracture depth on every stage.
	# These lights exist only during inspection, never in the first-person shots.
	var inspection_fill := Node3D.new()
	inspection_fill.name = "ShieldInspectionWhiteFill"
	world.add_child(inspection_fill)
	for angle: float in [0.0, 180.0]:
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20.0, angle, 0.0)
		fill.light_color = Color.WHITE
		fill.light_energy = .9
		fill.light_specular = .2
		fill.shadow_enabled = false
		fill.layers = 1
		fill.light_cull_mask = 1
		inspection_fill.add_child(fill)
	var observer := Camera3D.new()
	observer.projection = Camera3D.PROJECTION_ORTHOGONAL
	observer.size = 1.05
	observer.near = .01
	observer.far = 10
	observer.cull_mask = 1
	world.add_child(observer)
	for side: String in ["front", "rear"]:
		observer.position = Vector3(0, 1, 1.4 if side == "front" else -1.4)
		observer.look_at(Vector3(0, 1, 0), Vector3.UP)
		observer.make_current()
		player.viewmodel_renderer.sync_view()
		# CanvasLayer does not inherit Node3D visibility. The production renderer
		# explicitly disables its overlay when the source player/camera is hidden
		# or another camera is current; verify that path instead of hiding it by hand.
		_check(_inspector_isolated(player, viewport, observer), "inspector disables the independent first-person overlay")
		var label := _label(viewport, str(condition.title) + (" · 앞면 검사" if side == "front" else " · 뒷면 검사"))
		var file := "%s_inspector_%s.png" % [condition.stage, side]
		await _capture(viewport, directory.path_join(file))
		var isolated := _inspector_isolated(player, viewport, observer)
		_check(isolated, "inspector remains free of original arms, sword and overlay: " + file)
		captures.append({"file": file, "view": "runtime_selected_mesh_inspector", "side": side,
			"durability": player.get_shield_damage_snapshot(), "shares_runtime_mesh": inspected_surface.mesh == selected_surface.mesh,
			"original_player_and_equipment_hidden": isolated,
			"inspection_fill": {"color": "white", "energy_per_light": .9, "front_yaw": 0.0, "rear_yaw": 180.0, "pitch": -20.0},
			"camera": observer.global_transform, "projection": "orthographic", "size": observer.size,
			"model_transform": inspection.global_transform, "materials": _materials(inspection)})
		label.get_parent().queue_free()
	observer.queue_free()
	inspection.queue_free()
	inspection_fill.queue_free()
	player.visible = was_visible
	floor_node.visible = floor_visible
	player.camera.make_current()
	player.viewmodel_renderer.sync_view()
	await process_frame


static func _inspector_isolated(player: DungeonPlayer, viewport: SubViewport, observer: Camera3D) -> bool:
	return not player.is_visible_in_tree() and not player.weapon_arm.is_visible_in_tree() \
		and not player.shield_arm.is_visible_in_tree() and not player.sword_visual_root.is_visible_in_tree() \
		and not player.viewmodel_renderer.overlay.visible \
		and player.viewmodel_renderer.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED \
		and viewport.get_camera_3d() == observer \
		and (observer.cull_mask & player.viewmodel_renderer.EQUIPMENT_LAYER) == 0


func _capture_wear_sequence(directory: String, stills_only: bool) -> Dictionary:
	var viewport := STUDIO.create_studio_viewport()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var fixture := STUDIO.PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var player: DungeonPlayer = fixture.player
	var inventory: ExpeditionInventory = fixture.inventory
	_check(STUDIO.configure_pose(fixture, "guard"), "actual block sequence is configured")
	STUDIO.configure_studio(fixture)
	inventory.set_equipment_durability("offhand", 75.0)
	player.block_time = .6
	var original_identity := _model_identity(player.shield_model)
	var original_health := player.health
	var driver := WearDriver.new()
	driver.player = player
	driver.inventory = inventory
	driver.set_physics_process(false)
	(fixture.stage as Node3D).add_child(driver)
	driver.set_physics_process(false)
	var label := _label(viewport, "실제 방어 피격 · 내구도 75 → 25")
	for warm in 4:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
	if not stills_only: _check(DirAccess.make_dir_recursive_absolute(directory.path_join("frames")) == OK, "sequence folder created")
	driver.set_physics_process(true)
	var records: Array[Dictionary] = []
	var transition_images: Array[Dictionary] = []
	var previous_tick := -1
	var prior_stage := ""
	for frame in SEQUENCE_FRAMES:
		await process_frame
		if previous_tick >= 0: _check(driver.tick - previous_tick == 2, "exactly two gameplay ticks per video frame")
		previous_tick = driver.tick
		var current := player.get_shield_damage_snapshot()
		var stage := str(current.visual_stage)
		var translated := "상" if stage == "high" else ("중" if stage == "medium" else "하")
		label.text = "실제 방어 피격 · 내구도 %d / %d · %s\n%d회 차단 · 피해 0 · %.2f초" % [current.current, current.maximum, translated, driver.hits.size(), float(driver.tick) / 60.0]
		var stage_changed := stage != prior_stage
		var save_still := stage_changed or frame == SEQUENCE_FRAMES - 1
		if not stills_only or save_still:
			viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
			await RenderingServer.frame_post_draw
			var pixels := viewport.get_texture().get_image()
			_check(pixels != null and not pixels.is_empty(), "actual wear sequence GPU image exists")
			if pixels != null and not pixels.is_empty():
				if not stills_only: _check(pixels.save_jpg(directory.path_join("frames/%05d.jpg" % frame), .94) == OK, "actual GPU sequence frame saved")
				if save_still:
					var file := "wear_%03d_%s.png" % [frame, stage]
					_check(pixels.save_png(directory.path_join(file)) == OK, "actual wear transition image saved")
					transition_images.append({"file": file, "frame": frame, "physics_tick": driver.tick, "durability": current})
		_check(_same_identity(original_identity, _model_identity(player.shield_model)), "wear preserves actual model nodes and grip markers")
		var production := player.get_first_person_motion_snapshot()
		var contact: Dictionary = production.get("hand_contacts", {}).get("shield", {})
		_check(not contact.is_empty() and float(contact.get("error", INF)) < .002, "hand remains attached through actual impact and mesh swap")
		records.append({"frame": frame, "physics_tick": driver.tick, "durability": current,
			"health": player.health, "stamina": player.stamina, "blocking": player.blocking, "production": production})
		prior_stage = stage
	_check(driver.tick == 480 and records.size() == SEQUENCE_FRAMES, "eight seconds of real gameplay clock captured")
	_check(driver.hits.size() == 5, "five real receive_attack calls completed")
	_check(driver.stages.has("high") and driver.stages.has("medium") and driver.stages.has("low"), "actual blocked hits crossed both visual stage thresholds")
	for hit: Dictionary in driver.hits:
		_check(bool(hit.result.get("blocked", false)) and bool(hit.result.get("shield_guard", false)) and is_zero_approx(float(hit.result.get("damage", -1))), "incoming hit was actually blocked by shield")
		_check(is_equal_approx(float(hit.before.current) - float(hit.after.current), 10.0), "forty incoming damage caused ten shield wear")
		_check(hit.after.stage == hit.after.visual_stage and hit.after.source_path == DAMAGE.SOURCES[hit.after.stage], "actual hit immediately selected the correct asset")
		_check(bool(hit.blocking_after_signal), "equipment condition signal preserved guard")
	_check(is_equal_approx(player.health, original_health), "successful blocks preserved health")
	var final_state := player.get_shield_damage_snapshot()
	_check(is_equal_approx(float(final_state.current), 25.0) and final_state.visual_stage == "low", "five blocked hits finish at low durability")
	var result := {"fps": FPS, "duration_seconds": 8.0, "physics_hz": 60, "frame_count": records.size(),
		"saved_video_frames": 0 if stills_only else SEQUENCE_FRAMES, "frames": records,
		"hits": driver.hits, "transition_images": transition_images, "final": final_state,
		"setup": "A new isolated player holds normal guard. Stamina is refilled before each 40-damage test hit; wear, shield mesh changes, hand poses and impact recoil run through production code."}
	viewport.queue_free()
	await process_frame
	return result


func _capture(viewport: SubViewport, path: String) -> void:
	for warm in 8:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
	var pixels := viewport.get_texture().get_image()
	_check(pixels != null and not pixels.is_empty() and pixels.get_size() == IMAGE_SIZE, "actual GPU capture dimensions: " + path.get_file())
	if pixels != null and not pixels.is_empty(): _check(pixels.save_png(path) == OK, "image saved: " + path.get_file())


static func _model_identity(model: Node3D) -> Dictionary:
	var surface := model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	var result := {"model_id": model.get_instance_id(), "surface_id": surface.get_instance_id() if surface else 0, "markers": {}}
	for marker_name: String in MARKERS:
		var marker := model.find_child(marker_name, true, false) as Node3D
		if marker != null: result.markers[marker_name] = {"id": marker.get_instance_id(), "transform": marker.transform}
	return result


static func _same_identity(before: Dictionary, after: Dictionary) -> bool:
	if before.model_id != after.model_id or before.surface_id != after.surface_id or before.markers.size() != MARKERS.size() or after.markers.size() != MARKERS.size(): return false
	for marker_name: String in MARKERS:
		var original: Dictionary = before.markers[marker_name]
		var current: Dictionary = after.markers[marker_name]
		var transform: Transform3D = original.transform
		if original.id != current.id or not transform.is_equal_approx(current.transform): return false
	return true


static func _materials(model: Node3D) -> Dictionary:
	var surface := model.find_child("SwordsmanRoundShield_Surface", true, false) as MeshInstance3D
	var entries: Array[Dictionary] = []
	var valid := surface != null and surface.mesh != null
	if valid:
		for index in surface.mesh.get_surface_count():
			var material := surface.get_active_material(index) as StandardMaterial3D
			if material == null:
				valid = false
				continue
			entries.append({"surface": index, "name": material.resource_name, "roughness": material.roughness,
				"albedo": material.albedo_texture.resource_path if material.albedo_texture else "",
				"normal": material.normal_texture.resource_path if material.normal_texture else "",
				"normal_enabled": material.normal_enabled, "vertex_color": material.vertex_color_use_as_albedo})
	return {"valid": valid, "surfaces": entries}


static func _label(viewport: SubViewport, text: String) -> Label:
	var layer := CanvasLayer.new()
	layer.layer = 8
	viewport.add_child(layer)
	var label := Label.new()
	label.position = Vector2(22, 18)
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 23)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(label)
	return label


func _check(condition: bool, message: String) -> void:
	if not condition and not failures.has(message): failures.append(message)
