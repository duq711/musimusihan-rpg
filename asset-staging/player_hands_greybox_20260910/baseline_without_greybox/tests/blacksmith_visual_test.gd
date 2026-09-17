extends SceneTree

const VISUAL := preload("res://scripts/blacksmith_visual.gd")
var face_failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var before := Input.mouse_mode
	var visual := VISUAL.new()
	root.add_child(visual)
	var camera := Camera3D.new()
	root.add_child(camera)
	visual.set_camera(camera)
	for stage in ["idle", "fire", "anvil", "quenched", "finished"]:
		visual.update_state({"stage": stage, "temperature": 840.0, "recipe_id": "iron_longsword", "selected_weapon": {"smithing": {"sockets": 2, "runes": ["rune_fragment", "ember_rune"], "grip": "balanced_grip", "reinforcement": "silver_edge"}}})
		for action in ["pump_bellows", "hammer", "flip_blade", "quench", "drill_socket", "insert_rune"]:
			visual.animate_action(action)
			visual._process(0.24)
	assert(visual._weapon.get_meta("visible_socket_count") == 2)
	assert(visual._weapon.get_meta("visible_rune_count") == 2)
	assert(visual.find_child("SocketInterior_0", true, false) != null)
	assert(visual.find_child("BoredBladeSection_0", true, false) != null)
	assert(visual.find_child("ForgedHorn", true, false) is MeshInstance3D)
	# Check actual exposed faces: the first visual regression was an inward
	# wound striking face/body that still had correct nodes and positions.
	var plate: ArrayMesh = visual._extrude(PackedVector2Array([Vector2(-0.4, -0.15), Vector2(0.4, -0.15), Vector2(0.4, 0.15), Vector2(-0.4, 0.15)]), 0.91, 0.95)
	_check_top_normals(plate, 0.95, "anvil striking face")
	var bored: ArrayMesh = visual._socket_plate(0.035, -0.13, 0.125, 0.016, 0.004, 0.023)
	_check_top_normals(bored, 0.023, "drilled blade face")
	var bore_arrays := bored.surface_get_arrays(0)
	var bore_vertices: PackedVector3Array = bore_arrays[Mesh.ARRAY_VERTEX]
	var bore_indices: PackedInt32Array = bore_arrays[Mesh.ARRAY_INDEX]
	for index in range(0, bore_indices.size(), 3):
		var a := bore_vertices[bore_indices[index]]
		var b := bore_vertices[bore_indices[index + 1]]
		var c := bore_vertices[bore_indices[index + 2]]
		if is_equal_approx(a.y, 0.023) and is_equal_approx(b.y, 0.023) and is_equal_approx(c.y, 0.023):
			if Geometry2D.is_point_in_polygon(Vector2(0, -0.13), PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])):
				face_failures.append("A blade triangle caps the actual bored hole")
	# Indexed and procedural primitives share material batches. Without an
	# index array on both, append_from silently omits the custom faces.
	var source: PackedInt32Array = plate.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	if source.is_empty(): face_failures.append("Procedural plate must have triangle indices before batching")
	var joined := SurfaceTool.new()
	joined.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box := BoxMesh.new()
	joined.append_from(box, 0, Transform3D.IDENTITY)
	joined.append_from(plate, 0, Transform3D.IDENTITY)
	var combined := joined.commit()
	var indices: PackedInt32Array = combined.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var box_indices: PackedInt32Array = box.get_mesh_arrays()[Mesh.ARRAY_INDEX]
	if indices.size() != box_indices.size() + source.size(): face_failures.append("Static batch omitted custom anvil triangles")
	if int(visual.get_meta("static_expected_triangles")) != int(visual.get_meta("static_merged_triangles")):
		face_failures.append("Workshop batching lost triangles: expected %d actual %d" % [visual.get_meta("static_expected_triangles"), visual.get_meta("static_merged_triangles")])
	visual.set_station("anvil")
	visual.update_state({"stage": "anvil", "temperature": 820.0, "selected_section": 0, "hammer_charge": 0.0})
	var first_position: Vector3 = visual._weapon.position
	visual.update_state({"stage": "anvil", "temperature": 820.0, "selected_section": 2, "hammer_charge": 0.0})
	if visual._weapon.position.distance_to(first_position) < 0.45:
		face_failures.append("Changing the struck section must physically reposition the blade")
	visual._process(2.0)
	var rest_height: float = visual._hammer.position.y
	visual.update_state({"stage": "anvil", "temperature": 820.0, "hammer_charge": 1.0})
	visual._process(0.0)
	if visual._hammer.position.y < rest_height + 0.15:
		face_failures.append("Holding the hammer must display a real raised windup")
	for station in ["overview", "fire", "anvil", "quench", "upgrade"]:
		var pose: Dictionary = visual.camera_pose(station)
		assert((pose.position as Vector3).is_finite() and (pose.target as Vector3).is_finite())
	assert(Input.mouse_mode == before)
	visual.queue_free()
	camera.queue_free()
	await process_frame
	for failure in face_failures: push_error(failure)
	print("BLACKSMITH VISUAL %s: real forge stations, bored sockets, rune meshes, outward faces, indexed batching, all action poses and cursor preservation" % ("PASS" if face_failures.is_empty() else "FAIL"))
	quit(0 if face_failures.is_empty() else 1)


func _check_top_normals(mesh: ArrayMesh, height: float, label: String) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var upward := 0
	var downward := 0
	for index in vertices.size():
		if absf(vertices[index].y - height) < 0.0001:
			if normals[index].y > 0.5: upward += 1
			if normals[index].y < -0.5: downward += 1
	print("FACE NORMALS %s: up=%d down=%d" % [label, upward, downward])
	if upward == 0 or downward != 0:
		face_failures.append("Exposed top must face outward: " + label)
