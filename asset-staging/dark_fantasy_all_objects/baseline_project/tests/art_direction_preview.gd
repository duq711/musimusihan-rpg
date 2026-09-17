extends SceneTree
## Compare real production visuals with the cave concept from fixed cameras.
## No game session, input capture, preview-only material or lighting substitute.

const NATURALISM := preload("res://tests/mine_naturalism_preview.gd")
const CONTACT := preload("res://tests/contact_visual_preview.gd")
const OUTPUT_ROOT := "res://artifacts/visual_qa/abandoned_mine/art_direction"
const SHOTS := [
	{"name": "water_shore", "position": Vector3(-57.0, 1.5, -18.0), "target": Vector3(-53.9, 0.035, -15.8)},
	{"name": "entry_rock_attachment", "position": Vector3(0.6, 1.75, 60.1), "target": Vector3(3.356, 0.65, 57.54)},
	{"name": "soil_rock_transition", "position": Vector3(-0.3, 1.6, 59.9), "target": Vector3(3.5, 0.55, 60.0)},
	{"name": "water_steps", "position": Vector3(-56.5, 1.4, -18.0), "target": Vector3(-54.2, 0.035, -16.2)},
	{"name": "equipment_water_shore", "position": Vector3(-57.0, 1.5, -18.0), "target": Vector3(-53.9, 0.035, -15.8), "equipment": true},
]


func _init() -> void:
	call_deferred("_run")


static func output_directory(iteration: String) -> String:
	var slug := iteration.strip_edges()
	if slug.is_empty():
		slug = "iteration_01"
	var format := RegEx.new()
	format.compile("^[a-z0-9][a-z0-9_-]{0,47}$")
	if slug == "baseline" or format.search(slug) == null:
		return ""
	return OUTPUT_ROOT + "/" + slug


static func selected_shots(selection: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selection.strip_edges().is_empty():
		for shot: Dictionary in SHOTS:
			result.append(shot)
		return result
	var used: Array[String] = []
	for value: String in selection.split(",", false):
		var shot_name := value.strip_edges()
		if used.has(shot_name):
			continue
		var found := false
		for shot: Dictionary in SHOTS:
			if shot.name == shot_name:
				result.append(shot)
				used.append(shot_name)
				found = true
				break
		if not found:
			return []
	return result


static func create_viewport() -> SubViewport:
	var viewport := NATURALISM.create_viewport()
	viewport.name = "ArtDirectionViewport"
	viewport.use_taa = bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa", false))
	return viewport


static func begin_matched_water_capture(viewport: SubViewport) -> bool:
	var production_taa := viewport.use_taa
	# TAA retains previous pixels. Disable only for the counterfactual pair
	# so a prior ripple frame cannot contaminate the no-ripple baseline.
	viewport.use_taa = false
	return production_taa


static func end_matched_water_capture(viewport: SubViewport, previous_taa: bool) -> void:
	viewport.use_taa = previous_taa


static func populate_viewport(viewport: SubViewport) -> DungeonPlayer:
	var player := NATURALISM.populate_viewport(viewport)
	# Apply the exact same profile that the playable cave applies at spawn.
	# No light color, energy or range is authored by this comparison harness.
	load("res://scripts/cave_dungeon.gd").configure_player_lighting(player)
	player.camera.fov = 76.0
	player.viewmodel_renderer.sync_view()
	return player


static func configure_shot(player: DungeonPlayer, shot: Dictionary) -> void:
	NATURALISM.configure_shot(player, shot)
	for carried: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		carried.visible = bool(shot.get("equipment", false))
	player.viewmodel_renderer.sync_view()


static func await_geometry_ready(geometry: Node) -> bool:
	# Imported colliders reach the physics server before grounded lamps and
	# dressing can project onto them. Never capture an incomplete first frame.
	var deadline := Time.get_ticks_msec() + 45000
	while is_instance_valid(geometry) and Time.get_ticks_msec() < deadline:
		var complete := true
		for property in ["art_lighting", "art_details"]:
			var system: Node = geometry.get(property)
			if system != null:
				complete = complete and bool(system.call("get_state_snapshot").get("ready", false))
		if complete:
			return true
		await geometry.get_tree().physics_frame
	return false


static func inspect_detail_rendering(geometry: Node) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"passed": false, "verified": false, "reason": "Dummy renderer has no MultiMesh buffer readback"}
	var details: Node3D = geometry.get("art_details")
	if details == null or not details.has_method("get_render_batches"):
		return {"passed": false, "verified": false, "reason": "Production dressing submission is unavailable"}
	var count := 0
	var mismatches := 0
	for submission: Dictionary in details.call("get_render_batches"):
		var visual := details.get_node_or_null(NodePath(str(submission.name))) as MultiMeshInstance3D
		if visual == null or visual.multimesh == null or visual.multimesh.instance_count != submission.transforms.size():
			mismatches += 1
			continue
		for index in range(visual.multimesh.instance_count):
			var expected: Transform3D = submission.transforms[index]
			var actual := visual.multimesh.get_instance_transform(index)
			count += 1
			if actual.origin.distance_to(expected.origin) > 0.0001 or actual.basis.x.distance_to(expected.basis.x) > 0.0001 or actual.basis.y.distance_to(expected.basis.y) > 0.0001 or actual.basis.z.distance_to(expected.basis.z) > 0.0001:
				mismatches += 1
	return {"passed": count > 100 and mismatches == 0, "verified": true, "instances": count, "mismatches": mismatches}


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Art direction captures require the real renderer; headless tests do not verify appearance.")
		quit(1)
		return
	if OS.get_environment("CAVE_QA_WINDOW_APPROVED") != "1":
		push_error("Native window activation requires prior user approval before launching the art direction preview.")
		quit(1)
		return
	var directory := output_directory(OS.get_environment("MINE_ART_QA_ITERATION"))
	var shots := selected_shots(OS.get_environment("MINE_ART_QA_SHOTS"))
	if directory.is_empty() or shots.is_empty():
		push_error("Use a safe MINE_ART_QA_ITERATION slug and authored MINE_ART_QA_SHOTS names; baseline is reserved.")
		quit(1)
		return
	var output := ProjectSettings.globalize_path(directory)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Could not create art direction output directory.")
		quit(1)
		return
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var viewport := create_viewport()
	root.add_child(viewport)
	var player := populate_viewport(viewport)
	var geometry: Node = viewport.find_child("CaveGeometry", true, false)
	var water: Node = geometry.get("water_system")
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.title = "폐광 시각 방향 · 실제 화면 비교 후 자동 종료"
	await physics_frame
	await physics_frame
	if not await await_geometry_ready(geometry):
		push_error("Production cave dressing did not finish attaching to its collision surfaces.")
		quit(1)
		return
	await process_frame
	RenderingServer.force_draw(false)
	var dressing := inspect_detail_rendering(geometry)
	print("ART DIRECTION NATIVE INSTANCE READBACK: %s" % str(dressing))
	if not dressing.passed:
		push_error("Actual dressing render transforms must match the independently checked placement data.")
		quit(1)
		return
	for shot in shots:
		configure_shot(player, shot)
		print("ART DIRECTION CAMERA %s: %s" % [shot.name, str(player.camera.global_position)])
		if shot.name == "water_steps":
			if water == null or not await _capture_water_steps(viewport, water, output):
				quit(1)
				return
		else:
			if await _capture(viewport, str(shot.name), output) == null:
				quit(1)
				return
		if shot.get("equipment", false):
			var equipment: Image = player.viewmodel_renderer.viewport.get_texture().get_image()
			var visibility := CONTACT.inspect_equipment_pixels(equipment)
			if equipment != null and not equipment.is_empty():
				equipment.save_png(output + "/" + str(shot.name) + "_equipment.png")
			print("ART DIRECTION EQUIPMENT PIXELS: %s" % str(visibility))
			if not visibility.passed:
				push_error("The real gameplay equipment must remain visible under the production cave lighting.")
				quit(1)
				return
	viewport.queue_free()
	await process_frame
	if Input.mouse_mode != mouse_mode or ExpeditionSession.capture_snapshot() != snapshot:
		push_error("Art direction preview changed input mode or the expedition.")
		quit(1)
		return
	print("ART DIRECTION VISUAL PASS: %d production camera comparisons in %s; input and expedition preserved" % [shots.size(), output])
	quit(0)


func _capture(viewport: SubViewport, file_name: String, directory: String) -> Image:
	for frame in range(35):
		await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var pixels := NATURALISM.inspect_pixels(image)
	if image == null or image.is_empty() or image.save_png(directory + "/" + file_name + ".png") != OK:
		push_error("Could not save art direction frame: " + file_name)
		return null
	print("ART DIRECTION PIXELS %s: %s" % [file_name, str(pixels)])
	if not pixels.passed:
		push_error("Art direction frame must contain readable actual geometry: " + file_name)
		return null
	return image


func _capture_water_steps(viewport: SubViewport, water: Node, directory: String) -> bool:
	var state := NATURALISM.generate_walk_ripples(water)
	if state.is_empty() or state.ripple_count < 3:
		push_error("Art direction water comparison requires real walking ripple history.")
		return false
	var production_taa := begin_matched_water_capture(viewport)
	var original: PackedVector4Array = water.call("get_ripple_events")
	var empty := PackedVector4Array()
	empty.resize(original.size())
	for index in empty.size():
		empty[index] = Vector4(0, 0, -100, 0)
	NATURALISM.set_rendered_ripples(water, empty)
	var before := await _capture(viewport, "water_steps_before", directory)
	NATURALISM.set_rendered_ripples(water, original)
	var after := await _capture(viewport, "water_steps_after", directory)
	end_matched_water_capture(viewport, production_taa)
	var difference := NATURALISM.compare_water_pixels(before, after)
	print("ART DIRECTION MATCHED-CLOCK WATER PIXELS: %s" % str(difference))
	if not difference.passed or not is_equal_approx(water.call("get_state_snapshot").clock, float(state.clock)):
		push_error("Production footstep ripples must remain visible at the same water clock.")
		return false
	return true
