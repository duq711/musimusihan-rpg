extends SceneTree
## Production hand joints and their actual controls in a private rendering world.
## Entry is restricted to the audited windowless embedded renderer.

const HANDS := preload("res://tests/player_hands_detailed_preview.gd")
const CONTROLS := preload("res://scripts/finger_joint_controls.gd")
const IMAGE_SIZE := Vector2i(1280, 720)
const OUTPUT_ROOT := "res://artifacts/visual_qa/player_finger_joints"
const POSE_IDS := ["open", "palm", "wrist_side", "roots", "middles", "tips", "fist", "bow_draw", "chest_touch", "controls"]
const DIGITS := ["little", "ring", "middle", "index", "thumb"]
const SOURCE_FILES := [
	"res://assets/3d/player/hands_detailed/left_hand_detailed.glb",
	"res://assets/3d/player/hands_detailed/right_hand_detailed.glb",
	"res://scripts/greybox_arm_visual.gd",
	"res://scripts/wrist_cuff_deformer.gd",
	"res://scripts/player_arm_visual.gd",
	"res://scripts/player.gd",
	"res://scripts/chest_hand_visuals.gd",
	"res://scripts/finger_joint_controls.gd",
	"res://scripts/test_room.gd",
	"res://assets/fonts/NotoSansKR-Variable.ttf",
	"res://tests/player_arm_preview.gd",
	"res://tests/player_hands_detailed_preview.gd",
	"res://tests/player_finger_joints_preview.gd",
]
var failures: Array[String] = []
var captures: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Finger joint captures require the audited tests/run_embedded_preview.sh renderer.")
		quit(2)
		return
	var iteration := OS.get_environment("PLAYER_FINGER_JOINTS_QA_ITERATION").strip_edges()
	if iteration.is_empty() or not iteration.is_valid_filename() or iteration.begins_with("."):
		push_error("PLAYER_FINGER_JOINTS_QA_ITERATION must name a new plain output folder.")
		quit(2)
		return
	var output := ProjectSettings.globalize_path(OUTPUT_ROOT.path_join(iteration))
	if DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Joint capture output must be a new writable folder.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var snapshot := ExpeditionSession.capture_snapshot()
	var contents := HANDS.inventory_contents(snapshot.get("inventory"))
	var mouse := Input.mouse_mode
	var hashes := source_hashes()
	for path: String in SOURCE_FILES:
		if str(hashes[path]).length() != 64: failures.append("Missing joint capture source: " + path)
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := create_viewport()
	root.add_child(viewport)
	var fixture := populate_viewport(viewport)
	await physics_frame
	await physics_frame
	for pose: String in POSE_IDS:
		if not configure_pose(fixture, pose):
			failures.append("Could not configure actual joint pose: " + pose)
			continue
		var inspection := inspect_pose(fixture, pose)
		if not inspection.passed: failures.append("Actual joint pose inspection failed: " + pose)
		await _capture(viewport, output, pose, inspection, fixture)
	if OS.get_environment("PLAYER_FINGER_JOINTS_QA_SEQUENCE") == "1":
		if configure_pose(fixture, "open"):
			var controls: Control = fixture.controls
			controls.sequence_button.pressed.emit()
			controls.show()
			var sequence_path := output.path_join("sequence")
			DirAccess.make_dir_recursive_absolute(sequence_path)
			var duration_text := OS.get_environment("PLAYER_FINGER_JOINTS_QA_SEQUENCE_SECONDS")
			var duration := clampi(duration_text.to_int(), 1, 15) if not duration_text.is_empty() else 3
			for frame in duration * 15 + 1:
				if frame > 0: controls.advance_sequence(1.0 / 15.0)
				(fixture.player as DungeonPlayer).viewmodel_renderer.sync_view()
				var inspection := inspect_sequence(fixture, frame)
				if not inspection.passed: failures.append("Actual joint sequence values failed at frame " + str(frame))
				await _capture(viewport, sequence_path, "joint_%03d" % frame, inspection, fixture)
		else:
			failures.append("Could not prepare actual joint sequence.")
	(fixture.player as DungeonPlayer).end_finger_joint_review()
	(fixture.player as DungeonPlayer).cancel_timed_interaction()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == snapshot and HANDS.inventory_contents(snapshot.get("inventory")) == contents and Input.mouse_mode == mouse
	if not preserved: failures.append("Joint preview changed expedition, original inventory or cursor.")
	var unchanged := source_hashes() == hashes
	if not unchanged: failures.append("Joint preview sources changed during capture.")
	var manifest := {
		"display_driver": DisplayServer.get_name(), "actual_renderer": RenderingServer.get_current_rendering_driver_name(),
		"image_size": [IMAGE_SIZE.x, IMAGE_SIZE.y], "desktop_capture": false, "external_input": false,
		"capture_kind": "Actual DungeonPlayer independent joints, corrective blend shapes, production bow/chest and production controls in isolated SubViewport",
		"expedition_inventory_and_cursor_preserved": preserved, "source_sha256": hashes, "sources_unchanged_during_capture": unchanged,
		"captures": captures, "failures": failures,
	}
	var file := FileAccess.open(output.path_join("capture_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(manifest, "\t") + "\n")
	else: failures.append("Could not save joint capture manifest.")
	for failure in failures: push_error(failure)
	print("PLAYER FINGER JOINTS PREVIEW %s: %d actual captures; %s" % ["PASS" if failures.is_empty() else "FAIL", captures.size(), output])
	quit(0 if failures.is_empty() else 1)


func _capture(viewport: SubViewport, output: String, name: String, inspection: Dictionary, fixture: Dictionary) -> void:
	for _frame in 8: await process_frame
	RenderingServer.force_draw(false)
	var buffers := inspect_wrist_buffers(fixture)
	inspection["wrist_gpu_buffers"] = buffers
	inspection.passed = inspection.passed and buffers.passed
	if not buffers.passed: failures.append("Actual GPU cuff buffers differ from evaluated geometry: " + name)
	var rendered := viewport.get_texture().get_image()
	if rendered == null or rendered.is_empty():
		failures.append("Actual renderer returned no image: " + name)
		return
	var file_name := name + ".png"
	if rendered.save_png(output.path_join(file_name)) != OK:
		failures.append("Could not save joint image: " + name)
		return
	inspection["image"] = ("sequence/" if name.begins_with("joint_") else "") + file_name
	inspection["image_sha256"] = FileAccess.get_sha256(output.path_join(file_name))
	captures.append(inspection)
	print("PLAYER FINGER JOINTS CAPTURE: " + output.path_join(file_name))


static func inspect_wrist_buffers(fixture: Dictionary) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var wrists: Array[Dictionary] = []
	var passed := true
	for wrapper: Node3D in [player.left_support_arm, player.right_relaxed_arm, player._legacy_weapon_arm, player.torch_arm, player.chest_hands._arms[-1], player.chest_hands._arms[1]]:
		var arm := wrapper.get("detailed_visual") as Node3D
		if arm == null or not arm.is_visible_in_tree(): continue
		var report: Dictionary = arm.call("get_wrist_snapshot")
		var count := 0
		var position_error := 0.0
		var normal_error := 0.0
		var invalid_tangents := 0
		var buffers_match := bool(report.enabled)
		for surface: Dictionary in report.surfaces:
			# Read the actual ArrayMesh after renderer submission. On the embedded
			# renderer this checks the packed dynamic GPU upload, not the headless
			# surface-rebuild path or a report that only repeats the CPU vertices.
			var arrays := (surface.mesh as MeshInstance3D).mesh.surface_get_arrays(int(surface.surface))
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var original: Mesh = arm.get("_wrist_cuff_deformer").source_mesh_for(surface.mesh)
			var original_arrays := original.surface_get_arrays(int(surface.surface))
			var original_tangents: PackedFloat32Array = original_arrays[Mesh.ARRAY_TANGENT] if original_arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var evaluated: PackedVector3Array = surface.current_vertices
			var evaluated_normals: PackedVector3Array = surface.current_normals
			buffers_match = buffers_match and vertices.size() == evaluated.size() and normals.size() == evaluated_normals.size() and tangents.size() == vertices.size() * 4
			if vertices.size() != evaluated.size() or normals.size() != evaluated_normals.size() or tangents.size() != vertices.size() * 4: continue
			for vertex in vertices.size():
				count += 1
				if not vertices[vertex].is_finite() or not normals[vertex].is_finite(): buffers_match = false
				position_error = maxf(position_error, vertices[vertex].distance_to(evaluated[vertex]))
				normal_error = maxf(normal_error, normals[vertex].distance_to(evaluated_normals[vertex]))
				var tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2])
				var handedness := original_tangents[vertex * 4 + 3] if original_tangents.size() == vertices.size() * 4 else 1.0
				if not tangent.is_finite() or absf(tangent.length() - 1.0) > 0.003 or absf(tangent.dot(normals[vertex])) > 0.003 or not is_equal_approx(tangents[vertex * 4 + 3], handedness): invalid_tangents += 1
		var valid := buffers_match and count >= 64 and position_error < 0.00002 and normal_error < 0.001 and invalid_tangents == 0 and int(report.invalid_vertex_count) == 0 and float(report.minimum_jacobian_determinant) > 0.0
		passed = passed and valid
		wrists.append({"arm": str(wrapper.name), "vertex_count": count, "max_position_error_m": position_error, "max_normal_error": normal_error, "invalid_tangents": invalid_tangents, "minimum_jacobian_determinant": report.minimum_jacobian_determinant, "invalid_vertex_count": report.invalid_vertex_count, "passed": valid})
	return {"passed": passed and wrists.size() >= 2, "wrists": wrists, "readback": "ArrayMesh.surface_get_arrays after RenderingServer.force_draw"}


static func create_viewport() -> SubViewport:
	var viewport := HANDS.create_viewport()
	viewport.name = "PlayerFingerJointsPreviewViewport"
	return viewport


static func populate_viewport(viewport: SubViewport) -> Dictionary:
	var fixture := HANDS.populate_viewport(viewport)
	# TestRoomControls uses layer 70 above the player's viewmodel overlay.
	var controls_layer := CanvasLayer.new()
	controls_layer.name = "TestRoomControls"
	controls_layer.layer = 70
	viewport.add_child(controls_layer)
	var controls := CONTROLS.new()
	# Match the production test-room theme, including the bundled Korean font.
	var font := FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansKR-Variable.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 450}
	controls.theme = Theme.new()
	controls.theme.default_font = font
	controls.theme.default_font_size = 16
	controls.theme.set_color("font_color", "Button", Color(0.86, 0.90, 0.85))
	controls_layer.add_child(controls)
	controls.set_process(false)
	controls.set_process_unhandled_input(false)
	controls.set_process_input(false)
	controls.hide()
	fixture["controls"] = controls
	return fixture


static func configure_pose(fixture: Dictionary, pose: String) -> bool:
	if not POSE_IDS.has(pose): return false
	var player := fixture.player as DungeonPlayer
	var controls: Control = fixture.controls
	player.end_finger_joint_review()
	controls.hide()
	if pose in ["bow_draw", "chest_touch"]:
		return HANDS.configure_pose(fixture, pose)
	if not HANDS.configure_pose(fixture, "free_hands") or not player.begin_finger_joint_review(): return false
	controls.setup(player)
	controls.set_process(false)
	controls.select_side(0)
	if not controls.select_view(pose if pose in ["palm", "wrist_side"] else "dorsal"): return false
	controls.apply_preset("open")
	match pose:
		"roots", "middles", "tips":
			var joint := ["roots", "middles", "tips"].find(pose)
			for digit: String in DIGITS: controls.set_joint_value(digit, joint, 0.85)
		"fist":
			controls.apply_preset("fist")
		"controls":
			controls.select_side(-1)
			controls.set_joint_value("index", 1, 0.65)
	if pose in ["controls", "palm", "wrist_side"]: controls.show()
	else: controls.hide()
	player.viewmodel_renderer.sync_view()
	return true


static func inspect_pose(fixture: Dictionary, pose: String) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var controls_layer := (fixture.controls as Control).get_parent() as CanvasLayer
	var layer_number := controls_layer.layer if controls_layer != null else -1
	if pose in ["bow_draw", "chest_touch"]:
		var result := HANDS.inspect_pose(fixture, pose)
		result["independent_review_inactive"] = not player.get_finger_joint_review_snapshot().active
		result["controls_canvas_layer"] = layer_number
		result.passed = result.passed and result.independent_review_inactive and layer_number == 70
		return result
	var review: Dictionary = player.get_finger_joint_review_snapshot()
	var result := {"pose": pose, "review": review, "controls_visible": (fixture.controls as Control).visible, "controls_canvas_layer": layer_number, "passed": review.active and layer_number == 70 and not player.is_physics_processing() and not player.is_processing_unhandled_input()}
	for side in [-1, 1]:
		for digit: String in DIGITS:
			var expected := Vector3.ZERO
			if pose == "fist": expected = Vector3.ONE
			elif pose in ["roots", "middles", "tips"]: expected[["roots", "middles", "tips"].find(pose)] = 0.85
			elif pose == "controls" and side == -1 and digit == "index": expected.y = 0.65
			result.passed = result.passed and (review.values[side][digit] as Vector3).is_equal_approx(expected)
	result.passed = result.passed and result.controls_visible == (pose in ["controls", "palm", "wrist_side"])
	var expected_view := pose if pose in ["palm", "wrist_side"] else "dorsal"
	result["view_selector_index"] = (fixture.controls as Control).view_selector.selected
	result.passed = result.passed and review.view == expected_view and result.view_selector_index == ["dorsal", "palm", "wrist_side"].find(expected_view)
	return result


static func source_hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_FILES: result[path] = FileAccess.get_sha256(path)
	return result


static func inspect_sequence(fixture: Dictionary, frame: int) -> Dictionary:
	var player := fixture.player as DungeonPlayer
	var controls: Control = fixture.controls
	var controls_layer := controls.get_parent() as CanvasLayer
	var layer_number := controls_layer.layer if controls_layer != null else -1
	var review: Dictionary = player.get_finger_joint_review_snapshot()
	var elapsed := float(frame) / 15.0
	var step := floori(elapsed)
	var amount := sin(PI * fmod(elapsed, 1.0)) if step < 15 else 0.0
	var expected_digit := str(CONTROLS.DIGITS[step / 3]) if step < 15 else ""
	var passed := bool(review.active) and layer_number == 70
	for side in [-1, 1]:
		for digit: String in DIGITS:
			var expected := Vector3.ZERO
			if digit == expected_digit: expected[step % 3] = amount
			passed = passed and (review.values[side][digit] as Vector3).is_equal_approx(expected)
			for joint in 3:
				passed = passed and absf(float(controls.sliders["%s:%d" % [digit, joint]].value) - expected[joint]) < 0.0101
	return {"pose": "production_joint_sequence", "sequence_frame": frame, "sequence_fps": 15, "controls_visible": controls.visible, "controls_canvas_layer": layer_number, "expected_digit": expected_digit, "expected_joint": step % 3 if step < 15 else -1, "review": review, "passed": passed}
