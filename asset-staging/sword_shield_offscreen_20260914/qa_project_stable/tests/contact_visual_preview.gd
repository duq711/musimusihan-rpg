extends SceneTree
## Actual mine and carried-equipment rendering in an isolated, input-free
## viewport. No game scene, expedition mutation, mouse capture or audio.
## Native macOS window activation still requires the caller's prior approval.

const OUTPUT_DIR := "res://artifacts/visual_qa/abandoned_mine/contact"
const IMAGE_SIZE := Vector2i(1280, 720)
const SHOTS := [
	{"name": "entrance_ground_props", "position": Vector3(0.6, 1.75, 60.1), "target": Vector3(3.356, 0.65, 57.54), "equipment": false},
	{"name": "entrance_roof_support", "position": Vector3(-0.8, 1.75, 59.6), "target": Vector3(0.25, 3.6, 54.7), "equipment": false},
	{"name": "entrance_wall_lamp", "position": Vector3(-0.7, 1.75, 59.2), "target": Vector3(1.0, 1.8, 55.6), "equipment": false},
	{"name": "wall_close_sword_shield_torch", "wall_close": true, "equipment": true},
	{"name": "wall_close_guard", "wall_close": true, "equipment": true, "guard": true},
]


func _init() -> void:
	call_deferred("_run")


static func create_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "ContactPreviewViewport"
	viewport.size = IMAGE_SIZE
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return viewport


static func selected_shots(selection: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if selection.strip_edges().is_empty():
		for shot: Dictionary in SHOTS:
			result.append(shot)
		return result
	var requested: Array[String] = []
	for value: String in selection.split(",", false):
		var shot_name := value.strip_edges()
		if not requested.has(shot_name):
			requested.append(shot_name)
	for shot_name in requested:
		var found := false
		for shot: Dictionary in SHOTS:
			if shot.name == shot_name:
				result.append(shot)
				found = true
				break
		if not found:
			return []
	return result


static func populate_viewport(viewport: SubViewport) -> DungeonPlayer:
	var stage := Node3D.new()
	stage.name = "ContactPreviewStage"
	viewport.add_child(stage)
	var geometry: Node3D = load("res://scripts/cave_geometry.gd").new()
	geometry.name = "CaveGeometry"
	stage.add_child(geometry)
	geometry.build()
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	environment.environment = load("res://scripts/cave_dungeon.gd").make_environment()
	stage.add_child(environment)
	var player := DungeonPlayer.new()
	player.name = "ContactPreviewPlayer"
	# _ready constructs the production geometry without a game/HUD binding.
	# Disable processing before adding it, so no frame can sample input.
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	stage.add_child(player)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	player.camera.far = 160.0
	player.torch.light_color = Color(1.0, 0.78, 0.55)
	player.torch_fill.light_color = Color(1.0, 0.68, 0.40)
	return player


static func configure_shot(player: DungeonPlayer, shot: Dictionary) -> bool:
	var camera_position: Vector3 = shot.get("position", Vector3.ZERO)
	var target: Vector3 = shot.get("target", Vector3.ZERO)
	# Final contact coordinates come from the same exported source as the
	# playable model, keeping close inspection centered after surface snapping.
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/3d/abandoned_mine/build_manifest.json"))
	var contact: Dictionary = manifest.get("prop_contact", {}) if manifest is Dictionary else {}
	if shot.name == "entrance_roof_support":
		var support := _nearest_contact(contact.get("timber_supports", []), "position_godot", Vector3(-0.7, 0.0, 56.0))
		var roof_contacts: Array = support.get("roof_contacts", [])
		if not roof_contacts.is_empty():
			target = Vector3.ZERO
			for point: Dictionary in roof_contacts:
				target += _point3(point.get("point_godot", [0, 0, 0]))
			target /= float(roof_contacts.size())
	elif shot.name == "entrance_wall_lamp":
		var lamp := _nearest_contact(contact.get("wall_lanterns", []), "wick_godot", Vector3(0.44, 2.0, 50.35))
		if not lamp.is_empty():
			target = _point3(lamp.wick_godot)
			var inward := _point3(lamp.wall_normal_godot)
			inward.y = 0.0
			inward = inward.normalized()
			# Look diagonally along the wall so the bracket and its stone anchor
			# remain visible beside the lantern rather than hidden behind it.
			var tangent := inward.cross(Vector3.UP).normalized()
			camera_position = target + inward * 1.45 + tangent * 0.7
			camera_position.y = target.y - 0.25
	if shot.get("wall_close", false):
		var origin := Vector3(-0.7, 1.68, 59.2)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(12.0, 0.0, 0.0), DungeonPlayer.WORLD_LAYER)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			return false
		target = hit.position
		camera_position = hit.position + hit.normal * 0.42
	player.global_position = camera_position - Vector3(0.0, 0.67, 0.0)
	var direction := target - camera_position
	player.rotation = Vector3(0.0, atan2(-direction.x, -direction.z), 0.0)
	player._pitch = atan2(direction.y, Vector2(direction.x, direction.z).length())
	player.head.rotation = Vector3(player._pitch, 0.0, 0.0)
	player.camera.rotation = Vector3.ZERO
	player.blocking = bool(shot.get("guard", false))
	player._update_viewmodel(1.0)
	player._update_torch(0.016)
	for equipment: Node3D in [player.weapon_pivot, player.shield_pivot, player.torch_pivot]:
		equipment.visible = bool(shot.get("equipment", false))
	var renderer: Node = player.get("viewmodel_renderer")
	if renderer == null or not renderer.has_method("sync_view"):
		return false
	renderer.call("sync_view")
	return true


static func _point3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func inspect_equipment_pixels(captured: Image) -> Dictionary:
	var result := {"passed": false, "opaque_pixels": 0, "lit_pixels": 0, "lit_fraction": 0.0, "minimum_opaque_pixels": 1000, "minimum_lit_fraction": 0.10}
	if captured == null or captured.is_empty():
		return result
	# The carried flame sits on the left. Count only the right side, occupied
	# by the sword/gauntlet in both authored wall poses, so an emissive flame
	# cannot make an otherwise black equipment silhouette pass the check.
	var first_x := int(ceil(captured.get_width() * 0.52))
	for y in range(captured.get_height()):
		for x in range(first_x, captured.get_width()):
			var pixel := captured.get_pixel(x, y)
			if pixel.a <= 0.95:
				continue
			result.opaque_pixels += 1
			if maxf(pixel.r, maxf(pixel.g, pixel.b)) > 0.04:
				result.lit_pixels += 1
	result.lit_fraction = float(result.lit_pixels) / maxf(float(result.opaque_pixels), 1.0)
	result.passed = result.opaque_pixels > result.minimum_opaque_pixels and result.lit_fraction > result.minimum_lit_fraction
	return result


static func _nearest_contact(entries: Array, point_key: String, near: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := INF
	for entry: Dictionary in entries:
		if not entry.has(point_key):
			continue
		var point := _point3(entry[point_key])
		var gap := Vector2(point.x, point.z).distance_to(Vector2(near.x, near.z))
		if gap < distance:
			distance = gap
			nearest = entry
	return nearest


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Contact captures require the actual renderer; contact_visual_preview_test verifies structure only.")
		quit(1)
		return
	if OS.get_environment("CAVE_QA_WINDOW_APPROVED") != "1":
		push_error("Native window activation needs explicit prior user approval before this contact preview is launched.")
		quit(1)
		return
	var shots := selected_shots(OS.get_environment("CONTACT_QA_SHOTS"))
	if shots.is_empty():
		push_error("CONTACT_QA_SHOTS must contain comma-separated names from the defined contact shots.")
		quit(1)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse_mode := Input.mouse_mode
	var viewport := create_viewport()
	root.add_child(viewport)
	var player := populate_viewport(viewport)
	var display := TextureRect.new()
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.title = "폐광 접촉과 장비 · 검토 후 자동 종료"
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(output_path)
	await physics_frame
	await physics_frame
	for shot in shots:
		if not configure_shot(player, shot):
			push_error("Could not configure actual contact shot: " + str(shot.name))
			quit(1)
			return
		for _frame in range(45):
			await process_frame
		RenderingServer.force_draw(false)
		var captured := viewport.get_texture().get_image()
		if captured == null or captured.is_empty() or captured.save_png("%s/%s.png" % [output_path, shot.name]) != OK:
			push_error("Contact capture failed: " + str(shot.name))
			quit(1)
			return
		print("CONTACT CAPTURE: %s/%s.png" % [output_path, shot.name])
		if shot.get("wall_close", false):
			var equipment_image: Image = player.viewmodel_renderer.viewport.get_texture().get_image()
			var pixels := inspect_equipment_pixels(equipment_image)
			if equipment_image != null and not equipment_image.is_empty():
				equipment_image.save_png("%s/%s_equipment.png" % [output_path, shot.name])
			print("CONTACT EQUIPMENT PIXELS %s: right-side opaque=%d lit=%d lit_fraction=%.4f (required opaque>1000, lit_fraction>0.10)" % [shot.name, pixels.opaque_pixels, pixels.lit_pixels, pixels.lit_fraction])
			if not pixels.passed:
				push_error("Carried gear is missing or a black silhouette in the actual equipment render: " + str(shot.name))
				quit(1)
				return
	viewport.queue_free()
	await process_frame
	if Input.mouse_mode != mouse_mode or ExpeditionSession.capture_snapshot() != snapshot:
		push_error("Contact preview changed the cursor mode or expedition.")
		quit(1)
		return
	print("CONTACT VISUAL PREVIEW PASS: %d selected actual mine and carried-gear captures; input and expedition preserved" % shots.size())
	quit(0)
