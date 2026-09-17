extends SceneTree
## One diagnostic capture using the audited production fixture. No game edits.
const PREVIEW := preload("res://tests/player_finger_joints_preview.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() != "embedded":
		push_error("Diagnostic requires the audited embedded display driver.")
		quit(2)
		return
	var output := OS.get_environment("PLAYER_REALISM_NORMAL_PROBE_OUTPUT")
	if output.is_empty() or DirAccess.dir_exists_absolute(output) or DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Diagnostic output must be a new explicit directory.")
		quit(2)
		return
	root.gui_disable_input = true
	root.physics_object_picking = false
	AudioServer.set_bus_mute(0, true)
	var original := ExpeditionSession.capture_snapshot()
	var contents := PREVIEW.HANDS.inventory_contents(original.get("inventory"))
	var cursor := Input.mouse_mode
	var hashes := PREVIEW.source_hashes()
	var sandbox := root.get_node("TestRoomSandbox")
	sandbox.begin()
	var viewport := PREVIEW.create_viewport()
	root.add_child(viewport)
	var fixture := PREVIEW.populate_viewport(viewport)
	await physics_frame
	await physics_frame
	var configured := PREVIEW.configure_pose(fixture, "open")
	var player := fixture.player as DungeonPlayer
	var camera_before := player.camera.global_transform
	var pose_before := PREVIEW.inspect_pose(fixture, "open")
	var copies := {}
	var surface_count := 0
	var changed_names: Array[String] = []
	for wrapper: Node3D in [player.left_support_arm, player.right_relaxed_arm]:
		var arm := wrapper.get("detailed_visual") as Node3D
		if arm == null or not arm.is_visible_in_tree():
			failures.append("Expected both real review hands.")
			continue
		for mesh: MeshInstance3D in arm.get("arm_meshes") + arm.get("hand_meshes"):
			for surface in mesh.mesh.get_surface_count():
				var original_material := mesh.get_active_material(surface) as BaseMaterial3D
				if original_material == null or original_material.normal_texture == null or not original_material.normal_enabled:
					failures.append("Expected an actual enabled normal map before the diagnostic.")
					continue
				var id := original_material.get_instance_id()
				if not copies.has(id):
					var copy := original_material.duplicate() as BaseMaterial3D
					copy.albedo_texture = null
					copy.albedo_color = Color(0.11, 0.07, 0.04)
					if original_material.resource_name.begins_with("Detailed_Skin"): copy.albedo_color = Color(0.52, 0.33, 0.22)
					elif original_material.resource_name.begins_with("Detailed_Nail"): copy.albedo_color = Color(0.62, 0.43, 0.34)
					elif original_material.resource_name.begins_with("Detailed_Sleeve"): copy.albedo_color = Color(0.18, 0.15, 0.11)
					elif original_material.resource_name.begins_with("Detailed_Trim"): copy.albedo_color = Color(0.24, 0.18, 0.10)
					if copy is StandardMaterial3D: copy.roughness_texture = null
					elif copy is ORMMaterial3D: copy.orm_texture = null
					copy.roughness = 0.65
					copies[id] = copy
					changed_names.append(original_material.resource_name)
				mesh.set_surface_override_material(surface, copies[id])
				surface_count += 1
	for _frame in 8: await process_frame
	RenderingServer.force_draw(false)
	var pose_after := PREVIEW.inspect_pose(fixture, "open")
	var buffers := PREVIEW.inspect_wrist_buffers(fixture)
	var unchanged_pose := pose_before == pose_after and camera_before == player.camera.global_transform
	if not configured or not pose_after.passed or not unchanged_pose or not buffers.passed or surface_count < 18:
		failures.append("Actual open pose, camera, skin or cuff-buffer inspection failed.")
	var rendered := viewport.get_texture().get_image()
	var image_name := "open_color_roughness_constant.png"
	if rendered == null or rendered.is_empty() or rendered.save_png(output.path_join(image_name)) != OK:
		failures.append("Could not capture the actual diagnostic image.")
	player.end_finger_joint_review()
	viewport.queue_free()
	await process_frame
	sandbox.finish()
	var preserved := ExpeditionSession.capture_snapshot() == original and PREVIEW.HANDS.inventory_contents(original.get("inventory")) == contents and Input.mouse_mode == cursor
	var sources_unchanged := PREVIEW.source_hashes() == hashes
	if not preserved or not sources_unchanged: failures.append("Source or original session changed during diagnostic.")
	var report := {
		"diagnostic_only": true, "display_driver": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_driver_name(),
		"external_input": false, "desktop_capture": false, "image": image_name,
		"image_sha256": FileAccess.get_sha256(output.path_join(image_name)),
		"single_change": "basecolor and roughness textures disabled; per-material constant color and roughness 0.65; original normal maps remain enabled",
		"constant_color_roughness_surface_count": surface_count, "material_names": changed_names,
		"same_gameplay_camera_lighting_pose": unchanged_pose, "actual_pose": pose_after, "wrist_gpu_buffers": buffers,
		"original_expedition_inventory_cursor_preserved": preserved, "source_sha256": hashes, "sources_unchanged": sources_unchanged,
		"failures": failures, "passed": failures.is_empty(),
	}
	var file := FileAccess.open(output.path_join("diagnostic_manifest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	else: failures.append("Could not save the diagnostic manifest.")
	for failure in failures: push_error(failure)
	print("REALISM COLOR ROUGHNESS DIAGNOSTIC %s: %s" % ["PASS" if failures.is_empty() else "FAIL", output])
	quit(0 if failures.is_empty() else 1)
