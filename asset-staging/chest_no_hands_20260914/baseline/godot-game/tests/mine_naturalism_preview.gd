extends SceneTree
## Native visual evidence from the actual cave and shared water contact path.
## It never loads a game scene, captures input or changes expedition state.

const CONTACT := preload("res://tests/contact_visual_preview.gd")
const LAYOUT := preload("res://scripts/cave_layout.gd")
const OUTPUT_DIR := "res://artifacts/visual_qa/abandoned_mine/naturalism"
const SHOTS := [
	{"name": "water_shore", "position": Vector3(-57.0, 1.5, -18.0), "target": Vector3(-53.9, 0.035, -15.8)},
	{"name": "water_steps", "position": Vector3(-56.5, 1.4, -18.0), "target": Vector3(-54.2, 0.035, -16.2)},
	{"name": "entry_rock_attachment", "position": Vector3(0.6, 1.75, 60.1), "target": Vector3(3.356, 0.65, 57.54)},
	{"name": "soil_rock_transition", "position": Vector3(-0.3, 1.6, 59.9), "target": Vector3(3.5, 0.55, 60.0)},
	{"name": "formation_ground_contact", "position": Vector3(-0.8, 1.2, 61.3), "target": Vector3(0.0, 0.35, 59.2)},
]


func _init() -> void:
	call_deferred("_run")


static func selected_shots(selection: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selection.strip_edges().is_empty():
		for shot: Dictionary in SHOTS:
			result.append(shot)
		return result
	var used: Array[String] = []
	for name_value: String in selection.split(",", false):
		var shot_name := name_value.strip_edges()
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
	var viewport := CONTACT.create_viewport()
	viewport.name = "MineNaturalismViewport"
	# Matched-clock water comparisons must not differ because of TAA history.
	viewport.use_taa = false
	return viewport


static func populate_viewport(viewport: SubViewport) -> DungeonPlayer:
	var player := CONTACT.populate_viewport(viewport)
	var geometry: Node = viewport.find_child("CaveGeometry", true, false)
	# Cave lanterns flicker in _process; hold those lights fixed as well as the
	# water clock for the before/after contact-ripple pixel comparison.
	geometry.set_process(false)
	var water: Node = geometry.get("water_system")
	if water != null:
		water.call("bind_player", player)
		water.set_physics_process(false)
	for equipment: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		equipment.hide()
	return player


static func configure_shot(player: DungeonPlayer, shot: Dictionary) -> void:
	var camera_position: Vector3 = shot.position
	var target: Vector3 = shot.target
	if shot.name == "formation_ground_contact":
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3d/abandoned_mine/build_manifest.json"))
		var entries: Array = manifest.get("formation_contact", {}).get("assets", []) if manifest is Dictionary else []
		var nearest: Dictionary = {}
		var distance := INF
		var room_center := Vector3(-0.7313, 0.0, 59.1914)
		for entry: Dictionary in entries:
			if entry.get("kind", "") != "floor_stalagmite" or entry.get("contact_samples", []).is_empty():
				continue
			if entry.get("name", "") == "RockFormation_0247":
				nearest = entry
				break
			var position: Vector3 = CONTACT._point3(entry.position_godot)
			var gap := Vector2(position.x, position.z).distance_to(Vector2(room_center.x, room_center.z))
			if gap < distance:
				distance = gap
				nearest = entry
		if not nearest.is_empty():
			var base := Vector3.ZERO
			for sample: Dictionary in nearest.contact_samples:
				base += CONTACT._point3(sample.surface_godot)
			base /= float(nearest.contact_samples.size())
			var room_id := LAYOUT.room_id_at(Vector2(base.x, base.z))
			if not room_id.is_empty():
				room_center = LAYOUT.room_position(room_id)
			var inward := room_center - base
			inward.y = 0.0
			if inward.length_squared() < 0.01:
				inward = Vector3.BACK
			target = base + Vector3.UP * 0.50
			camera_position = base + inward.normalized() * 2.1 + Vector3.UP * 1.15
	player.global_position = camera_position - Vector3(0.0, 0.67, 0.0)
	var direction := target - camera_position
	player.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.head.rotation = Vector3(player._pitch, 0.0, 0.0)
	player.camera.rotation = Vector3.ZERO
	player.viewmodel_renderer.sync_view()


static func inspect_pixels(captured: Image) -> Dictionary:
	var result := {"passed": false, "samples": 0, "lit_samples": 0, "minimum": 1.0, "maximum": 0.0}
	if captured == null or captured.is_empty():
		return result
	for y in range(0, captured.get_height(), 8):
		for x in range(0, captured.get_width(), 8):
			var pixel := captured.get_pixel(x, y)
			var brightness := maxf(pixel.r, maxf(pixel.g, pixel.b))
			result.samples += 1
			result.lit_samples += 1 if brightness > 0.035 else 0
			result.minimum = minf(result.minimum, brightness)
			result.maximum = maxf(result.maximum, brightness)
	result.passed = result.samples > 100 and result.lit_samples > result.samples * 0.04 and result.maximum - result.minimum > 0.045
	return result


static func compare_water_pixels(before: Image, after: Image) -> Dictionary:
	var result := {"passed": false, "samples": 0, "changed_pixels": 0, "changed_fraction": 0.0, "mean_difference": 0.0}
	if before == null or after == null or before.is_empty() or before.get_size() != after.get_size():
		return result
	# The fixed water camera looks down into the lower-west pool. Avoid dark
	# upper corners and use the central/lower water region for ripple evidence.
	var x_start := int(before.get_width() * 0.20)
	var x_end := int(before.get_width() * 0.88)
	var y_start := int(before.get_height() * 0.28)
	var y_end := int(before.get_height() * 0.90)
	for y in range(y_start, y_end):
		for x in range(x_start, x_end):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			var difference := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
			result.samples += 1
			result.mean_difference += difference
			result.changed_pixels += 1 if difference > 0.012 else 0
	result.changed_fraction = float(result.changed_pixels) / maxf(float(result.samples), 1.0)
	result.mean_difference /= maxf(float(result.samples), 1.0)
	result.passed = result.changed_pixels > 40 and result.changed_fraction > 0.001
	return result


static func generate_walk_ripples(water: Node) -> Dictionary:
	# The same controller method receives real player feet in ordinary play.
	# The camera remains stationary while these prescribed foot contacts cross
	# the real lower-west pool, avoiding any desktop input in the native preview.
	for index in range(4):
		var feet := Vector3(-54.3, -0.24, -18.0 + index * 0.75)
		var surface: Dictionary = water.call("sample_surface", feet)
		if surface.is_empty():
			return {}
		feet.y = float(surface.height) - float(surface.depth)
		water.call("advance_contact", 0.016 if index == 0 else 0.25, feet, Vector3(0.0, 0.0, 3.0), true)
	water.call("advance_contact", 0.35, Vector3(-54.3, -0.24, -15.75), Vector3.ZERO, true)
	return water.call("get_state_snapshot")


static func set_rendered_ripples(water: Node, events: PackedVector4Array) -> void:
	for surface: MeshInstance3D in water.get("surfaces"):
		(surface.material_override as ShaderMaterial).set_shader_parameter("ripple_events", events)


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Mine naturalism PNGs require the real renderer; headless checks cannot verify pixels.")
		quit(1)
		return
	if OS.get_environment("CAVE_QA_WINDOW_APPROVED") != "1":
		push_error("Native window activation requires prior user approval before this preview is launched.")
		quit(1)
		return
	var shots := selected_shots(OS.get_environment("MINE_NATURALISM_QA_SHOTS"))
	if shots.is_empty():
		push_error("MINE_NATURALISM_QA_SHOTS must contain comma-separated authored shot names.")
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
	if water == null:
		push_error("The actual mine water system is required for naturalism validation.")
		quit(1)
		return
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.title = "폐광 암석과 물 · 검토 후 자동 종료"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await physics_frame
	await physics_frame
	for shot in shots:
		configure_shot(player, shot)
		print("NATURALISM CAMERA %s: %s" % [shot.name, str(player.camera.global_position)])
		if shot.name == "water_steps":
			if not await _capture_water_steps(viewport, water):
				quit(1)
				return
		else:
			if await _capture(viewport, shot.name) == null:
				quit(1)
				return
	viewport.queue_free()
	await process_frame
	if Input.mouse_mode != mouse_mode or ExpeditionSession.capture_snapshot() != snapshot:
		push_error("Naturalism preview changed input mode or the expedition.")
		quit(1)
		return
	print("MINE NATURALISM VISUAL PASS: %d selected actual mine shots; readable pixels, input and expedition preserved" % shots.size())
	quit(0)


func _capture(viewport: SubViewport, file_name: String) -> Image:
	for frame in range(35):
		await process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	var pixels := inspect_pixels(image)
	if image != null and not image.is_empty():
		image.save_png("%s/%s.png" % [ProjectSettings.globalize_path(OUTPUT_DIR), file_name])
	print("NATURALISM PIXELS %s: %s" % [file_name, str(pixels)])
	if not pixels.passed:
		push_error("Naturalism image is empty, black or lacks visible geometry: " + file_name)
		return null
	return image


func _capture_water_steps(viewport: SubViewport, water: Node) -> bool:
	var state := generate_walk_ripples(water)
	if state.is_empty() or state.ripple_count < 3 or state.last_pool != "lower_west_water":
		push_error("Real water contact path did not emit the prescribed walking ripples.")
		return false
	var events: PackedVector4Array = water.call("get_ripple_events")
	var empty_events := PackedVector4Array()
	empty_events.resize(events.size())
	for index in empty_events.size():
		empty_events[index] = Vector4(0.0, 0.0, -100.0, 0.0)
	# The geometry, camera, lighting and water_clock are identical in both
	# images. Only the actual contact ripple history differs; natural waves or
	# flicker therefore cannot masquerade as a successful footstep response.
	set_rendered_ripples(water, empty_events)
	var before := await _capture(viewport, "water_steps_before")
	set_rendered_ripples(water, events)
	var after := await _capture(viewport, "water_steps_after")
	var difference := compare_water_pixels(before, after)
	print("NATURALISM WATER CONTACTS: %s" % str(state))
	print("NATURALISM MATCHED-CLOCK WATER PIXELS: %s" % str(difference))
	if not difference.passed or not is_equal_approx(water.call("get_state_snapshot").clock, float(state.clock)):
		push_error("Footstep ripples must visibly change the real water pixels at an unchanged simulation clock.")
		return false
	if OS.get_environment("MINE_WATER_QA_SEQUENCE") == "1":
		return await _capture_water_sequence(viewport, water)
	return true


func _capture_water_sequence(viewport: SubViewport, water: Node) -> bool:
	var directory := ProjectSettings.globalize_path(OUTPUT_DIR + "/water_motion")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("Could not create the water motion capture directory.")
		return false
	var initial: Dictionary = water.call("get_state_snapshot")
	var feet := Vector3(-54.3, -0.24, -15.75)
	var surface: Dictionary = water.call("sample_surface", feet)
	if surface.is_empty():
		push_error("The stationary water sequence feet must remain in the real pool.")
		return false
	feet.y = float(surface.height) - float(surface.depth)
	for index in range(20):
		# Advance the existing contact history only. Stationary feet cannot
		# inject additional walking events, and the inspection camera stays put.
		water.call("advance_contact", 0.16, feet, Vector3.ZERO, true)
		for draw_frame in range(3):
			await process_frame
		RenderingServer.force_draw(false)
		var image := viewport.get_texture().get_image()
		if image == null or image.is_empty() or image.save_png("%s/frame_%03d.png" % [directory, index]) != OK:
			push_error("Could not save water motion frame %03d." % index)
			return false
		var current: Dictionary = water.call("get_state_snapshot")
		if current.total_ripples != initial.total_ripples:
			push_error("Stationary water motion capture must not add ripple events.")
			return false
		print("NATURALISM WATER MOTION frame_%03d.png: clock=%.3f active=%d total=%d" % [index, current.clock, current.ripple_count, current.total_ripples])
	print("NATURALISM WATER MOTION PASS: 20 actual frames at 0.16-second simulation intervals; existing ripple history preserved")
	return true
